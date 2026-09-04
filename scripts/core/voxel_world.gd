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
## thread, so they are rationed to keep streaming off the frame budget.
const UPLOADS_PER_FRAME := 4
const UPLOADS_PER_FRAME_LOADING := 24

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


func _ready() -> void:
	_opaque = GreedyMesher.opacity_table()
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
	_dispatch()
	_collect()


func _dispatch() -> void:
	if _dirty.is_empty():
		return
	var budget := 12 if _loading else 4
	var launched := 0
	for cpos: Vector3i in _dirty.keys():
		if launched >= budget:
			break
		if _in_flight.has(cpos):
			continue
		_dirty.erase(cpos)
		if not _needs_mesh(cpos):
			_clear_chunk_node(cpos)
			continue
		var padded := _build_padded(cpos)
		_in_flight[cpos] = true
		launched += 1
		_tasks.append(WorkerThreadPool.add_task(
			_mesh_job.bind(cpos, padded), true, "voxel_mesh"))


## Runs on a worker thread. Pure: reads only its arguments and the immutable
## opacity table, and hands the result back through a mutex.
func _mesh_job(cpos: Vector3i, padded: PackedByteArray) -> void:
	var t0 := Time.get_ticks_usec()
	var res := GreedyMesher.mesh(padded, _opaque)
	res["cpos"] = cpos
	res["us"] = Time.get_ticks_usec() - t0
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _collect() -> void:
	_mutex.lock()
	var take: Array = []
	var limit := UPLOADS_PER_FRAME_LOADING if _loading else UPLOADS_PER_FRAME
	while _results.size() > 0 and take.size() < limit:
		take.append(_results.pop_front())
	_mutex.unlock()

	for res: Dictionary in take:
		_apply(res)
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

	var surfaces: Dictionary = res["surfaces"]
	if surfaces.is_empty():
		_clear_chunk_node(cpos)
		return

	var mesh := ArrayMesh.new()
	var i := 0
	for mat: int in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[mat])
		mesh.surface_set_material(i, VoxelMaterials.get_material(mat))
		i += 1

	var mi: MeshInstance3D = _nodes.get(cpos)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(cpos) * VoxelChunk.SPAN_M
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(mi)
		_nodes[cpos] = mi
	mi.mesh = mesh

	var faces: PackedVector3Array = res["collision"]
	var body: StaticBody3D = _bodies.get(cpos)
	if faces.is_empty():
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
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	(body.get_node("shape") as CollisionShape3D).shape = shape


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
func _build_padded(cpos: Vector3i) -> PackedByteArray:
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
	var col_loaded := PackedByteArray()
	col_loaded.resize(9)
	for dz in 3:
		for dx in 3:
			col_loaded[dx + dz * 3] = 1 if _htiles.has(
				Vector2i(cpos.x + dx - 1, cpos.z + dz - 1)) else 0

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

			var left: VoxelChunk = chunks.get(Vector3i(cpos.x - 1, cy, cz))
			out.append(left.voxels[(S - 1) + row_base] if left != null
				else _absent(below_world, above_world, col_loaded[0 + dz_i * 3] == 1))

			var mid: VoxelChunk = chunks.get(Vector3i(cpos.x, cy, cz))
			if mid != null:
				out.append_array(mid.voxels.slice(row_base, row_base + S))
			elif _absent(below_world, above_world, col_loaded[1 + dz_i * 3] == 1) == VoxelTypes.AIR:
				out.append_array(air_row)
			else:
				out.append_array(rock_row)

			var right: VoxelChunk = chunks.get(Vector3i(cpos.x + 1, cy, cz))
			out.append(right.voxels[row_base] if right != null
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


func chunk_count() -> int:
	return chunks.size()


func mesh_node_count() -> int:
	return _nodes.size()


func busy() -> bool:
	return _loading or not _in_flight.is_empty() or not _dirty.is_empty()


func pending() -> int:
	return _dirty.size() + _in_flight.size()
