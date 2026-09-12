extends Node3D
class_name VoxelWorld
## Tier A voxel world: an unbounded field of 32³ chunks at 0.25 m, meshed on
## worker threads, with baked static collision and a live surface heightmap.
##
## Horizontally there is no edge. Chunks exist where the streamer has put them
## and nowhere else, so the store is a dictionary rather than a grid, and the
## heightmap is a dictionary of 32x32 tiles rather than one big array. Only the
## vertical extent is fixed — the world is a landscape, not a cave system, and
## a fixed ceiling lets whole chunk layers be skipped cheaply.
##
## Everything downstream — the generator, navigation, the player — talks to the
## world in voxel coordinates and never touches chunk internals.

signal load_progress(done: int, total: int)
signal load_finished()
signal column_ready(cx: int, cz: int)

const S := VoxelChunk.SIZE
const VOXEL_M := VoxelChunk.VOXEL_M

## Mesh and collision upload are the only parts that must run on the main
## thread, so they are rationed. A time budget rather than a count: a fixed one
## chunk per frame capped the world at sixty chunks a second no matter how cheap
## they were, and a sprinting player outruns that.
const UPLOAD_BUDGET_MS := 2.5
const UPLOAD_BUDGET_MS_LOADING := 12.0

## Collision bodies are only attached near the player, because a StaticBody3D
## per chunk out to the full view distance is a few thousand of them in the
## broadphase for no benefit. The *shape* is baked for every chunk regardless
## and cached on the chunk, so coming into range is a node and not a remesh.
const COLLISION_RADIUS_M := 40.0
## Beyond here the body is dropped again. The gap is hysteresis: without it a
## player walking along the boundary adds and removes the same bodies forever.
const COLLISION_DROP_M := 52.0
## How much ground a worker carries with him. He is one capsule, not a
## camera, so he needs a fraction of what the player does.
const AGENT_RADIUS_M := 14.0

var height_chunks := 6                     ## vertical extent, in chunks
var chunks: Dictionary = {}                ## Vector3i -> VoxelChunk

var _htiles: Dictionary = {}               ## Vector2i -> PackedInt32Array(32*32)
var _nodes: Dictionary = {}                ## Vector3i -> MeshInstance3D
var _bodies: Dictionary = {}               ## Vector3i -> StaticBody3D
var _dirty: Dictionary = {}
var _in_flight: Dictionary = {}
var _results: Array = []
var _mutex := Mutex.new()
var _opaque: PackedByteArray
var _tasks: Array[int] = []
var _loading := false
var _expected := 0
var _completed := 0

## Chunks the player's workers have changed. Kept when a column unloads so a
## building does not evaporate the moment you walk away from it.
var _stash: Dictionary = {}                ## Vector3i -> PackedByteArray
## Chunks a mesh job has actually completed for, empty result included. Needed
## to tell "produced no faces" from "was never looked at" — only the second is
## a hole.
var _meshed: Dictionary = {}

var stat_quads := 0
var stat_mesh_ms := 0.0
## Worst main-thread cost this world has imposed on a single frame. Mesh and
## collision upload are the only work that cannot be threaded, so this is the
## number that decides whether streaming is felt as a hitch.
var stat_worst_frame_ms := 0.0
var stat_frame_ms := 0.0
var stat_worst_dispatch_ms := 0.0
var stat_worst_upload_ms := 0.0
## How many times the streaming budget was overridden to keep a floor under the
## player. Any number above a handful means the budgets are set too low.
var stat_rescues := 0
## Worst time one collision refresh has taken. It only runs when the player
## crosses into a new chunk column, which is also exactly when a stutter while
## walking would be blamed on the streamer.
var stat_worst_collision_ms := 0.0
## Where collision is wanted. Set by the game each frame; cheap to write.
var collision_focus := Vector3.ZERO
var _collision_column := Vector2i(1 << 30, 1 << 30)
## Everyone else who needs ground under them — the crew. A worker sent to a
## plot on the far side of town walks straight out of the player's collision
## bubble, and without this the floor stops existing underneath him and he
## stands in mid-air with is_on_floor() false, forever.
var _agents: Array[Vector3] = []
var _agent_columns: Array[Vector2i] = []


func _ready() -> void:
	_opaque = GreedyMesher.opacity_table()
	VoxelMaterials.prewarm()
	set_process(true)


## Meshing jobs outlive a scene change unless they are joined, and they wake up
## holding a mutex that no longer exists.
func _exit_tree() -> void:
	for t: int in _tasks:
		if not WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


func configure(vertical_chunks: int) -> void:
	height_chunks = vertical_chunks
	chunks.clear()
	_htiles.clear()


# ------------------------------------------------------------------ geometry

func voxel_height() -> int:
	return height_chunks * S


## Only the vertical extent bounds anything. X and Z are unbounded.
func in_bounds(v: Vector3i) -> bool:
	return v.y >= 0 and v.y < height_chunks * S


static func to_voxel(world_m: Vector3) -> Vector3i:
	return Vector3i(floori(world_m.x / VOXEL_M), floori(world_m.y / VOXEL_M),
		floori(world_m.z / VOXEL_M))


static func to_metres(v: Vector3i) -> Vector3:
	return Vector3(v) * VOXEL_M


static func centre_metres(v: Vector3i) -> Vector3:
	return (Vector3(v) + Vector3(0.5, 0.5, 0.5)) * VOXEL_M


static func column_of(world_m: Vector3) -> Vector2i:
	return Vector2i(floori(world_m.x / VoxelChunk.SPAN_M),
		floori(world_m.z / VoxelChunk.SPAN_M))


# -------------------------------------------------------------------- access

func get_chunk(cpos: Vector3i, create: bool = false) -> VoxelChunk:
	var c: VoxelChunk = chunks.get(cpos)
	if c == null and create and cpos.y >= 0 and cpos.y < height_chunks:
		c = VoxelChunk.new(cpos)
		chunks[cpos] = c
	return c


func get_voxel(v: Vector3i) -> int:
	if not in_bounds(v):
		return VoxelTypes.AIR
	var c: VoxelChunk = chunks.get(Vector3i(v.x >> 5, v.y >> 5, v.z >> 5))
	if c == null:
		return VoxelTypes.AIR
	return c.voxels[(v.x & 31) + (v.z & 31) * S + (v.y & 31) * S * S]


func is_solid(v: Vector3i) -> bool:
	return VoxelTypes.is_solid(get_voxel(v))


func has_column(cx: int, cz: int) -> bool:
	return _htiles.has(Vector2i(cx, cz))


## A change made by the game rather than by generation. Marks the chunk so the
## column is kept when it unloads.
func set_voxel(v: Vector3i, id: int) -> void:
	if not in_bounds(v):
		return
	var cpos := Vector3i(v.x >> 5, v.y >> 5, v.z >> 5)
	var c := get_chunk(cpos, true)
	if c == null:
		return
	var lx := v.x & 31
	var ly := v.y & 31
	var lz := v.z & 31
	if c.get_voxel(lx, ly, lz) == id:
		return
	c.set_voxel(lx, ly, lz, id)
	c.modified = true
	_dirty[cpos] = true
	_mark_seam_neighbours(cpos, lx, ly, lz)
	_update_height(v, id)


## A voxel on a chunk face changes the culling and the baked AO of the chunks
## it touches, and AO reaches diagonally, so the whole touched corner of the
## 3x3x3 neighbourhood has to be remeshed too.
func _mark_seam_neighbours(cpos: Vector3i, lx: int, ly: int, lz: int) -> void:
	if lx > 0 and lx < 31 and ly > 0 and ly < 31 and lz > 0 and lz < 31:
		return
	for dx in [-1, 0, 1]:
		if (dx < 0 and lx != 0) or (dx > 0 and lx != 31):
			continue
		for dy in [-1, 0, 1]:
			if (dy < 0 and ly != 0) or (dy > 0 and ly != 31):
				continue
			for dz in [-1, 0, 1]:
				if (dz < 0 and lz != 0) or (dz > 0 and lz != 31):
					continue
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var n := cpos + Vector3i(dx, dy, dz)
				if chunks.has(n):
					_dirty[n] = true


# ----------------------------------------------------------------- heightmap
# Stored as one 32x32 tile per chunk column, so it streams with the chunks and
# never needs an allocation proportional to how far the player has walked.

func _tile(cx: int, cz: int, create: bool = false) -> PackedInt32Array:
	var key := Vector2i(cx, cz)
	var t: PackedInt32Array = _htiles.get(key, PackedInt32Array())
	if t.is_empty() and create:
		t = PackedInt32Array()
		t.resize(S * S)
		t.fill(-1)
		_htiles[key] = t
	return t


func set_height_tile(cx: int, cz: int, tile: PackedInt32Array) -> void:
	_htiles[Vector2i(cx, cz)] = tile


func _update_height(v: Vector3i, id: int) -> void:
	var key := Vector2i(v.x >> 5, v.z >> 5)
	var t: PackedInt32Array = _htiles.get(key, PackedInt32Array())
	if t.is_empty():
		return
	var i := (v.x & 31) + (v.z & 31) * S
	if VoxelTypes.is_solid(id):
		if v.y > t[i]:
			t[i] = v.y
			_htiles[key] = t
	elif t[i] == v.y:
		var y := v.y - 1
		while y >= 0 and not is_solid(Vector3i(v.x, y, v.z)):
			y -= 1
		t[i] = y
		_htiles[key] = t


## Top solid voxel y in a column, or -1 where nothing is loaded. O(1).
func height_at(x: int, z: int) -> int:
	var t: PackedInt32Array = _htiles.get(Vector2i(x >> 5, z >> 5), PackedInt32Array())
	if t.is_empty():
		return -1
	return t[(x & 31) + (z & 31) * S]


## Walkable ground height in metres at a world position.
func ground_m(world_x: float, world_z: float) -> float:
	var h := height_at(floori(world_x / VOXEL_M), floori(world_z / VOXEL_M))
	return float(h + 1) * VOXEL_M


func mark_all_dirty() -> void:
	for cpos: Vector3i in chunks:
		_dirty[cpos] = true


func mark_dirty(cpos: Vector3i) -> void:
	if chunks.has(cpos):
		_dirty[cpos] = true


# ------------------------------------------------------------------ streaming

## Installs a freshly generated column. Any chunk the game had previously
## changed is restored on top of the generated ground, so a building survives
## being walked away from and come back to.
func install_column(cx: int, cz: int, column_chunks: Dictionary,
		tile: PackedInt32Array) -> void:
	for cpos: Vector3i in column_chunks:
		var c: VoxelChunk = column_chunks[cpos]
		var stashed: PackedByteArray = _stash.get(cpos, PackedByteArray())
		if not stashed.is_empty():
			c.deserialize(stashed)
			c.modified = true
		chunks[cpos] = c

	# A building can occupy chunks the generator never makes, because they sit
	# above the ground. Those exist only in the stash, so restore them here or a
	# roof would quietly vanish the first time its column streamed back in.
	for cy in height_chunks:
		var cpos2 := Vector3i(cx, cy, cz)
		if chunks.has(cpos2):
			continue
		var blob: PackedByteArray = _stash.get(cpos2, PackedByteArray())
		if blob.is_empty():
			continue
		var restored := VoxelChunk.new(cpos2)
		restored.deserialize(blob)
		restored.modified = true
		chunks[cpos2] = restored

	set_height_tile(cx, cz, tile)
	# Restore height for any modified chunk that changed the surface.
	if not _stash.is_empty():
		_rebuild_column_heights(cx, cz)

	# Queue this column and any neighbour the new arrival has just unblocked.
	# Doing it here rather than in the caller is the difference between a hole
	# in the world and no hole: a column that is installed but never queued
	# looks exactly like ground that does not exist.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := Vector2i(cx + dx, cz + dz)
			if has_column(n.x, n.y) and column_meshable(n.x, n.y):
				mark_column_dirty(n.x, n.y)

	column_ready.emit(cx, cz)


func _rebuild_column_heights(cx: int, cz: int) -> void:
	var t := _tile(cx, cz, true)
	var changed := false
	for cy in range(height_chunks - 1, -1, -1):
		var c: VoxelChunk = chunks.get(Vector3i(cx, cy, cz))
		if c == null or c.is_empty() or not c.modified:
			continue
		for ly in range(S - 1, -1, -1):
			var wy := cy * S + ly
			for i in S * S:
				if c.voxels[i + ly * S * S] != VoxelTypes.AIR and t[i] < wy:
					t[i] = wy
					changed = true
	if changed:
		_htiles[Vector2i(cx, cz)] = t


## Drops a column's chunks and their scene nodes. Anything the game changed is
## kept as a blob so it comes back byte-identical.
func unload_column(cx: int, cz: int) -> void:
	for cy in height_chunks:
		var cpos := Vector3i(cx, cy, cz)
		var c: VoxelChunk = chunks.get(cpos)
		if c == null:
			continue
		if c.modified:
			_stash[cpos] = c.serialize()
		chunks.erase(cpos)
		_dirty.erase(cpos)
		_meshed.erase(cpos)
		_clear_chunk_node(cpos)
	_htiles.erase(Vector2i(cx, cz))


## A column can only be meshed once its eight horizontal neighbours exist,
## otherwise the seam faces are culled against air that is about to become rock.
func column_meshable(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not _htiles.has(Vector2i(cx + dx, cz + dz)):
				return false
	return true


func mark_column_dirty(cx: int, cz: int) -> void:
	for cy in height_chunks:
		var cpos := Vector3i(cx, cy, cz)
		if chunks.has(cpos):
			_dirty[cpos] = true


func loaded_columns() -> int:
	return _htiles.size()


# ------------------------------------------------------------------- meshing

func begin_loading(expected_columns: int) -> void:
	_loading = true
	_expected = maxi(expected_columns, 1)
	_completed = 0


func _needs_mesh(cpos: Vector3i) -> bool:
	var c: VoxelChunk = chunks.get(cpos)
	if c == null or c.is_empty():
		return false
	if c.solid_count < VoxelChunk.VOLUME:
		return true
	for d: Vector3i in GreedyMesher.DIRS:
		var n: VoxelChunk = chunks.get(cpos + d)
		if n == null:
			# Missing above or below the world is sky and bedrock respectively;
			# missing to the side just means that column has not streamed in.
			if d.y > 0 and cpos.y + 1 >= height_chunks:
				continue
			if d.y < 0 and cpos.y == 0:
				continue
			return false
		if n.solid_count < VoxelChunk.VOLUME:
			return true
	return false


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_dispatch()
	var t1 := Time.get_ticks_usec()
	_collect()
	var t2 := Time.get_ticks_usec()
	stat_worst_dispatch_ms = maxf(stat_worst_dispatch_ms, float(t1 - t0) * 0.001)
	stat_worst_upload_ms = maxf(stat_worst_upload_ms, float(t2 - t1) * 0.001)
	stat_frame_ms = float(t2 - t0) * 0.001
	stat_worst_frame_ms = maxf(stat_worst_frame_ms, stat_frame_ms)


func _dispatch() -> void:
	if _dirty.is_empty():
		return
	var budget := 12 if _loading else 5

	# Nearest first, always. The dirty set is unordered and during streaming it
	# runs to a few hundred entries; taking them in the order they happened to
	# be added meant the chunk the player was about to step on could wait behind
	# eighty metres of scenery, and at a sprint it did.
	var pick: Array[Vector3i] = []
	var pick_d: Array[float] = []
	for cpos: Vector3i in _dirty.keys():
		if _in_flight.has(cpos):
			continue

		# Not enough information yet: a neighbouring column has not arrived, so
		# whatever this chunk meshes to would be wrong. Leave it queued and
		# leave its existing mesh alone. Clearing it here was the flicker —
		# during streaming, chunks at the frontier had their geometry destroyed
		# and rebuilt every time a neighbour came and went.
		if not column_meshable(cpos.x, cpos.z):
			continue

		var d := _focus_dist2(cpos)
		if pick.size() >= budget and d >= pick_d[pick.size() - 1]:
			continue
		var at := pick_d.bsearch(d)
		pick.insert(at, cpos)
		pick_d.insert(at, d)
		if pick.size() > budget:
			pick.resize(budget)
			pick_d.resize(budget)

	for cpos: Vector3i in pick:
		_dirty.erase(cpos)
		if not _needs_mesh(cpos):
			_clear_chunk_node(cpos)
			continue
		var neighbourhood := _snapshot(cpos)
		_in_flight[cpos] = true
		_tasks.append(WorkerThreadPool.add_task(
			_mesh_job.bind(cpos, neighbourhood), true, "voxel_mesh"))


## Runs on a worker thread. Pure: reads only its arguments and the immutable
## opacity table, and hands the result back through a mutex.
func _mesh_job(cpos: Vector3i, neighbourhood: Dictionary) -> void:
	var res := _mesh_and_bake(cpos, neighbourhood)
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


## Meshes a chunk and bakes its render and collision resources. Called on a
## worker thread for everything, and on the main thread for the one case that
## cannot wait — see ensure_support().
func _mesh_and_bake(cpos: Vector3i, neighbourhood: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var res := GreedyMesher.mesh(_pad(cpos, neighbourhood), _opaque)

	# Build the mesh and the collision shape here too. Both are resources rather
	# than scene nodes, so they can be made off-thread, and between them they
	# were most of the main thread cost of installing a chunk.
	var surfaces: Dictionary = res["surfaces"]
	if not surfaces.is_empty():
		var mesh := ArrayMesh.new()
		var i := 0
		for mat: int in surfaces:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[mat])
			mesh.surface_set_material(i, VoxelMaterials.get_material(mat))
			i += 1
		res["mesh"] = mesh
	# Bake the shape whether or not the chunk is close enough to be given a body
	# right now. This is worker-thread time, it is the expensive half of
	# collision, and doing it here means the main thread never has to choose
	# between a floor under the player and a steady frame.
	var faces: PackedVector3Array = res["collision"]
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		res["shape"] = shape

	res["cpos"] = cpos
	res["us"] = Time.get_ticks_usec() - t0
	return res


func _collect() -> void:
	_mutex.lock()
	var pending: Array = _results
	_results = []
	_mutex.unlock()
	if pending.is_empty():
		return

	# Nearest first. Which chunk gets uploaded this frame decides whether the
	# ground under the player's next step exists, so finishing order matters far
	# more than arrival order.
	_sort_by_distance(pending)

	var budget := UPLOAD_BUDGET_MS_LOADING if _loading else UPLOAD_BUDGET_MS
	var t0 := Time.get_ticks_usec()
	var done := 0
	for res: Dictionary in pending:
		_apply(res)
		done += 1
		# Always take at least one, or a frame that is already over budget for
		# reasons of its own would starve the world forever.
		if float(Time.get_ticks_usec() - t0) * 0.001 >= budget:
			break

	if done < pending.size():
		var rest := pending.slice(done)
		_mutex.lock()
		# Anything that arrived while we were uploading goes behind the backlog.
		rest.append_array(_results)
		_results = rest
		_mutex.unlock()

	if _tasks.size() > 128:
		var live: Array[int] = []
		for t: int in _tasks:
			if not WorkerThreadPool.is_task_completed(t):
				live.append(t)
		_tasks = live


func finish_loading() -> void:
	if _loading:
		_loading = false
		load_finished.emit()


func _apply(res: Dictionary) -> void:
	var cpos: Vector3i = res["cpos"]
	_in_flight.erase(cpos)
	_meshed[cpos] = true
	_completed += 1
	stat_quads += int(res["quads"])
	stat_mesh_ms = float(res["us"]) * 0.001

	# The column may have unloaded while this job was in flight.
	if not chunks.has(cpos):
		return

	var c: VoxelChunk = chunks[cpos]
	c.shape = res.get("shape")

	var mesh: ArrayMesh = res.get("mesh")
	if mesh == null:
		_clear_chunk_node(cpos)
		return

	var mi: MeshInstance3D = _nodes.get(cpos)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(cpos) * VoxelChunk.SPAN_M
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(mi)
		_nodes[cpos] = mi
	mi.mesh = mesh
	_sync_body(cpos)


## Squared metres from the collision focus to a chunk's centre.
func _focus_dist2(cpos: Vector3i) -> float:
	var centre := (Vector3(cpos) + Vector3(0.5, 0.5, 0.5)) * VoxelChunk.SPAN_M
	var dx := centre.x - collision_focus.x
	var dz := centre.z - collision_focus.z
	return dx * dx + dz * dz


func _sort_by_distance(items: Array) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _focus_dist2(a["cpos"]) < _focus_dist2(b["cpos"]))


## Whether a chunk is close enough to anyone to be worth colliding with.
func _wants_collision(cpos: Vector3i) -> bool:
	var limit := COLLISION_DROP_M if _bodies.has(cpos) else COLLISION_RADIUS_M
	if _focus_dist2(cpos) < limit * limit:
		return true
	# A worker needs far less than the player does: only the ground he is
	# about to put a boot on.
	var centre := (Vector3(cpos) + Vector3(0.5, 0.5, 0.5)) * VoxelChunk.SPAN_M
	for a: Vector3 in _agents:
		var dx := centre.x - a.x
		var dz := centre.z - a.z
		if dx * dx + dz * dz < AGENT_RADIUS_M * AGENT_RADIUS_M:
			return true
	return false


## Tells the world who else is walking about. Bodies are re-synced only when
## one of them crosses into a new chunk column, so this is cheap to call on
## every physics tick.
func set_agents(points: Array[Vector3]) -> void:
	_agents = points
	var cols: Array[Vector2i] = []
	for a: Vector3 in points:
		cols.append(column_of(a))
	if cols == _agent_columns:
		return
	_agent_columns = cols
	var r := int(ceil(AGENT_RADIUS_M / VoxelChunk.SPAN_M)) + 1
	for c: Vector2i in cols:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				for cy in height_chunks:
					var cpos := Vector3i(c.x + dx, cy, c.y + dz)
					if chunks.has(cpos):
						_sync_body(cpos)


## Attaches or drops a chunk's collision body to match where the player is now.
## Costs a node and a shape assignment, never a remesh, because the shape was
## baked on the worker thread when the chunk was meshed.
func _sync_body(cpos: Vector3i) -> void:
	var c: VoxelChunk = chunks.get(cpos)
	var shape: ConcavePolygonShape3D = c.shape if c != null else null
	var body: StaticBody3D = _bodies.get(cpos)
	if shape == null or not _wants_collision(cpos):
		if body != null:
			body.queue_free()
			_bodies.erase(cpos)
		return
	if body == null:
		body = StaticBody3D.new()
		body.position = Vector3(cpos) * VoxelChunk.SPAN_M
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		cs.name = "shape"
		body.add_child(cs)
		add_child(body)
		_bodies[cpos] = body
	(body.get_node("shape") as CollisionShape3D).shape = shape


## Guarantees there is a floor under a position, whatever the queue is doing.
##
## Every other path here is a budget — so many chunks per frame, nearest first —
## and normally that runs comfortably ahead of the player. "Normally" is not
## good enough for the ground under his feet: one frame without collision there
## and he is inside the world falling, which is the single worst thing a voxel
## game can do to you. So the chunks he is actually touching are built here and
## now, on the main thread, ahead of the queue.
##
## This costs a few milliseconds on the frame it fires. It fires almost never,
## because the streaming path is what stops it being needed; stat_rescues says
## how often "almost" was.
func ensure_support(world_m: Vector3) -> void:
	var here := to_voxel(world_m)
	var cy := here.y >> 5
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			# Only the chunks the capsule can actually be over. At 8 m a chunk
			# the player straddles a boundary rarely, and checking a whole 3x3
			# of columns every frame for nothing is waste.
			var near := Vector3(world_m.x + dx * 0.45, 0.0, world_m.z + dz * 0.45)
			var col := column_of(near)
			for y in [cy, cy - 1]:
				if y < 0 or y >= height_chunks:
					continue
				var cpos := Vector3i(col.x, y, col.y)
				if _bodies.has(cpos):
					continue
				var c: VoxelChunk = chunks.get(cpos)
				if c == null or c.is_empty():
					continue
				if c.shape != null:
					_sync_body(cpos)   # baked already; this is just a node
					continue
				if _meshed.has(cpos) or not column_meshable(cpos.x, cpos.z):
					continue           # nothing to build, or not buildable yet
				_build_now(cpos)


## Meshes one chunk synchronously and installs it, jumping the queue.
func _build_now(cpos: Vector3i) -> void:
	if not _needs_mesh(cpos):
		_meshed[cpos] = true
		return
	stat_rescues += 1
	_dirty.erase(cpos)
	_apply(_mesh_and_bake(cpos, _snapshot(cpos)))


## Attaches bodies to everything that has just come within reach and drops the
## ones that have fallen out of it. Runs only when the player crosses into a new
## chunk column.
func refresh_collision(focus: Vector3) -> void:
	collision_focus = focus
	var col := column_of(focus)
	if col == _collision_column:
		return
	_collision_column = col
	var t0 := Time.get_ticks_usec()
	var r := int(ceil(COLLISION_DROP_M / VoxelChunk.SPAN_M)) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for cy in height_chunks:
				var cpos := Vector3i(col.x + dx, cy, col.y + dz)
				if chunks.has(cpos):
					_sync_body(cpos)
	stat_worst_collision_ms = maxf(stat_worst_collision_ms,
		float(Time.get_ticks_usec() - t0) / 1000.0)


func _clear_chunk_node(cpos: Vector3i) -> void:
	if _nodes.has(cpos):
		(_nodes[cpos] as Node).queue_free()
		_nodes.erase(cpos)
	if _bodies.has(cpos):
		(_bodies[cpos] as Node).queue_free()
		_bodies.erase(cpos)


## Builds the 34³ padded neighbourhood for a chunk. Written by appending whole
## 32-byte rows, so the copying happens in engine code rather than in a GDScript
## loop over 39k voxels — roughly twenty times faster, and it matters because
## this runs on the main thread.
##
## Missing neighbours are treated as solid rock, never as air: above the world
## that would be wrong, but nothing is ever above the world, and below or beside
## it stops the map growing a skin of faces nobody can see.
## Grabs references to the 3x3x3 of neighbouring chunks. Copy-on-write means
## this costs 27 dictionary lookups and no copying at all; the worker turns it
## into the padded array.
func _snapshot(cpos: Vector3i) -> Dictionary:
	var out := {}
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := cpos + Vector3i(dx, dy, dz)
				var c: VoxelChunk = chunks.get(n)
				if c != null:
					out[n] = c.voxels
	out["_loaded"] = _loaded_flags(cpos)
	return out


func _loaded_flags(cpos: Vector3i) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(9)
	for dz in 3:
		for dx in 3:
			f[dx + dz * 3] = 1 if _htiles.has(
				Vector2i(cpos.x + dx - 1, cpos.z + dz - 1)) else 0
	return f


func _build_padded(cpos: Vector3i) -> PackedByteArray:
	return _pad(cpos, _snapshot(cpos))


func _pad(cpos: Vector3i, snap: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	var air_row := PackedByteArray()
	air_row.resize(S)
	var rock_row := PackedByteArray()
	rock_row.resize(S)
	rock_row.fill(VoxelTypes.STONE)

	# Whether each of the nine surrounding columns has been generated. A chunk
	# that is missing inside a generated column is simply above the ground, so
	# it is sky; a chunk missing because the column has not streamed in yet is
	# unknown, and is treated as rock so the mesher does not grow a wall of
	# faces into it. Getting this backwards culled the faces off every building
	# wall that faced an empty upper chunk.
	#
	# Read out of the snapshot, never off the live world: this runs on a worker
	# thread, and the streamer is installing and evicting columns while it does.
	var col_loaded: PackedByteArray = snap["_loaded"]

	for py in 34:
		var wy := py - 1
		var cy := cpos.y
		var ly := wy
		if wy < 0:
			cy -= 1
			ly = S - 1
		elif wy >= S:
			cy += 1
			ly = 0
		var below_world := cy < 0
		var above_world := cy >= height_chunks

		for pz in 34:
			var wz := pz - 1
			var cz := cpos.z
			var lz := wz
			var dz_i := 1
			if wz < 0:
				cz -= 1
				lz = S - 1
				dz_i = 0
			elif wz >= S:
				cz += 1
				lz = 0
				dz_i = 2

			var row_base := lz * S + ly * S * S

			var left: PackedByteArray = snap.get(Vector3i(cpos.x - 1, cy, cz),
				PackedByteArray())
			out.append(left[(S - 1) + row_base] if not left.is_empty()
				else _absent(below_world, above_world, col_loaded[0 + dz_i * 3] == 1))

			var mid: PackedByteArray = snap.get(Vector3i(cpos.x, cy, cz),
				PackedByteArray())
			if not mid.is_empty():
				out.append_array(mid.slice(row_base, row_base + S))
			elif _absent(below_world, above_world, col_loaded[1 + dz_i * 3] == 1) == VoxelTypes.AIR:
				out.append_array(air_row)
			else:
				out.append_array(rock_row)

			var right: PackedByteArray = snap.get(Vector3i(cpos.x + 1, cy, cz),
				PackedByteArray())
			out.append(right[row_base] if not right.is_empty()
				else _absent(below_world, above_world, col_loaded[2 + dz_i * 3] == 1))

	return out


## What to treat a missing neighbour chunk as.
##
##   above the world  -> sky, so the top of a hill gets its faces
##   below the world  -> bedrock, so the underside is never drawn
##   column generated -> sky, because that column simply has no ground so high
##   column unknown   -> bedrock, so nothing grows faces into unstreamed space
##
## The third case is the one that matters. Treating it as rock culled the faces
## off every building wall that happened to face a column whose upper chunk had
## never been created, which is most of them.
static func _absent(below_world: bool, above_world: bool, column_generated: bool) -> int:
	if above_world:
		return VoxelTypes.AIR
	if below_world:
		return VoxelTypes.STONE
	return VoxelTypes.AIR if column_generated else VoxelTypes.STONE


## Chunks that ought to be on screen but have no mesh, and are not queued or in
## flight either. Anything above zero here is a hole in the world, so it is
## worth being able to ask the question directly rather than going looking.
func unrendered_chunks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cpos: Vector3i in chunks:
		if _dirty.has(cpos) or _in_flight.has(cpos):
			continue          # queued or being worked on
		if _meshed.has(cpos):
			continue          # looked at; producing no faces is a valid answer
		if not column_meshable(cpos.x, cpos.z):
			continue          # neighbours have not arrived, so not a hole yet
		if _needs_mesh(cpos):
			out.append(cpos)
	return out


## Why a position has no floor. Diagnostic only.
func debug_support(world_m: Vector3) -> String:
	var v := to_voxel(world_m)
	var cpos := Vector3i(v.x >> 5, v.y >> 5, v.z >> 5)
	var parts: Array[String] = []
	parts.append("chunk %s" % str(cpos))
	parts.append("chunk=%s" % ("yes" if chunks.has(cpos) else "NO"))
	parts.append("mesh=%s" % ("yes" if _nodes.has(cpos) else "NO"))
	parts.append("body=%s" % ("yes" if _bodies.has(cpos) else "NO"))
	parts.append("dirty=%s" % ("yes" if _dirty.has(cpos) else "no"))
	parts.append("flight=%s" % ("yes" if _in_flight.has(cpos) else "no"))
	parts.append("wants=%s" % ("yes" if _wants_collision(cpos) else "NO"))
	parts.append("meshable=%s" % ("yes" if column_meshable(cpos.x, cpos.z) else "NO"))
	parts.append("h=%d" % height_at(v.x, v.z))
	return " ".join(parts)


func chunk_count() -> int:
	return chunks.size()


func mesh_node_count() -> int:
	return _nodes.size()


func busy() -> bool:
	return _loading or not _in_flight.is_empty() or not _dirty.is_empty()


func pending() -> int:
	return _dirty.size() + _in_flight.size()
