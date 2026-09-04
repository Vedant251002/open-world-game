extends Node
class_name ChunkStreamer
## Keeps the world loaded around a focus point and forgets the rest.
##
## Columns are generated on worker threads and installed on the main thread.
## A column is only meshed once its eight neighbours exist, because the greedy
## mesher culls seam faces against whatever is next door — mesh too early and
## the join between two columns is a wall of faces that should not be there.
##
## The village is pinned: those columns never unload, so the town you built is
## always there when you turn round, and workers always have ground to walk on.

signal first_load_done()

const S := VoxelChunk.SIZE
const SPAN := VoxelChunk.SPAN_M

## Radii in chunk columns (8 m each).
@export var load_radius := 10        ## 80 m of full-detail voxels
@export var keep_radius := 13        ## hysteresis, so walking a line does not thrash
@export var jobs_in_flight := 6

var world: VoxelWorld
var gen: WorldGen
var village: Village
var focus: Node3D

var _pending: Dictionary = {}        ## Vector2i -> true
var _results: Array = []
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _pinned: Dictionary = {}         ## Vector2i -> true
var _last_focus := Vector2i(1 << 30, 1 << 30)
## The candidate list for the current focus column, and how far through it the
## search got last frame. Rebuilding and re-sorting three hundred entries every
## frame cost more than the meshing did.
var _wanted: Array[Vector2i] = []
var _scan := 0
var _first_load := true
var _awaiting_first := 0

var stat_generated := 0
var stat_unloaded := 0
var stat_gen_ms := 0.0


func setup(w: VoxelWorld, g: WorldGen, v: Village, focus_node: Node3D) -> void:
	world = w
	gen = g
	village = v
	focus = focus_node

	# Pin every column the town touches, plus a ring around it.
	var b := village.nav_bounds_v(64)
	var c0 := Vector2i(floori(float(b.position.x) / S), floori(float(b.position.y) / S))
	var c1 := Vector2i(ceili(float(b.position.x + b.size.x) / S),
		ceili(float(b.position.y + b.size.y) / S))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_pinned[Vector2i(cx, cz)] = true
	set_process(true)


func _exit_tree() -> void:
	for t: int in _tasks:
		if not WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


## Loads the ground the player will actually be standing on before the game
## starts, so the first frame is a town rather than a hole. The rest of the view
## distance streams in over the next few seconds while they are getting their
## bearings — waiting for all three hundred columns would triple the load.
@export var prime_radius := 5


func prime(around: Vector3) -> int:
	var centre := VoxelWorld.column_of(around)
	var wanted := _ring(centre, prime_radius + 1)
	_awaiting_first = wanted.size()
	world.begin_loading(wanted.size())
	for c: Vector2i in wanted:
		_request(c)
	return wanted.size()


func _process(_delta: float) -> void:
	_collect()
	if focus == null:
		return

	var centre := VoxelWorld.column_of(focus.global_position)
	if centre != _last_focus:
		_last_focus = centre
		# One ring past the visible radius: a column needs all eight neighbours
		# before it can be meshed, so without the spare ring the outermost
		# visible columns would stay invisible forever.
		_wanted = _ring(centre, load_radius + 1)
		_scan = 0
		_evict(centre)

	# Keep the queue topped up, nearest first, resuming where the last frame
	# stopped rather than rescanning the whole disc.
	if _pending.size() >= jobs_in_flight or _wanted.is_empty():
		return
	var looked := 0
	while looked < 64 and _scan < _wanted.size() and _pending.size() < jobs_in_flight:
		var c: Vector2i = _wanted[_scan]
		_scan += 1
		looked += 1
		if not world.has_column(c.x, c.y) and not _pending.has(c):
			_request(c)


## Columns within a radius, ordered by distance so the world fills outward.
func _ring(centre: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			out.append(centre + Vector2i(dx, dz))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - centre).length_squared() < (b - centre).length_squared())
	return out


func _request(c: Vector2i) -> void:
	_pending[c] = true
	_tasks.append(WorkerThreadPool.add_task(_generate_job.bind(c), false, "world_gen"))


## Runs on a worker thread. WorldGen holds no per-column state, so several of
## these run at once without any locking beyond the result queue.
func _generate_job(c: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var column := gen.generate_column(c.x, c.y, world.height_chunks)

	var tile := PackedInt32Array()
	tile.resize(S * S)
	var base_x := c.x * S
	var base_z := c.y * S
	var sea := gen.sea_voxel()
	for lz in S:
		for lx in S:
			var h := gen.height_at(base_x + lx, base_z + lz)
			tile[lx + lz * S] = maxi(h, sea if h <= sea else h)

	_mutex.lock()
	_results.append({"c": c, "chunks": column, "tile": tile,
		"us": Time.get_ticks_usec() - t0})
	_mutex.unlock()


func _collect() -> void:
	_mutex.lock()
	var take: Array = []
	# Installing is cheap, but the remesh it triggers is not, so it is rationed.
	while _results.size() > 0 and take.size() < (12 if _first_load else 2):
		take.append(_results.pop_front())
	_mutex.unlock()

	for r: Dictionary in take:
		var c: Vector2i = r["c"]
		_pending.erase(c)
		stat_generated += 1
		stat_gen_ms = float(r["us"]) * 0.001
		# install_column queues its own meshing, including any neighbour the
		# new column has just unblocked.
		world.install_column(c.x, c.y, r["chunks"], r["tile"])

		if _first_load:
			_awaiting_first -= 1

	# Deliberately not world.busy(): that includes the loading flag this branch
	# exists to clear, so asking it here waits for itself forever.
	if _first_load and _awaiting_first <= 0 and _pending.is_empty() \
			and world.pending() == 0:
		_first_load = false
		world.finish_loading()
		first_load_done.emit()

	if _tasks.size() > 128:
		var live: Array[int] = []
		for t: int in _tasks:
			if not WorkerThreadPool.is_task_completed(t):
				live.append(t)
		_tasks = live


func _evict(centre: Vector2i) -> void:
	var drop: Array[Vector2i] = []
	for key: Variant in world._htiles:
		var c: Vector2i = key
		if _pinned.has(c):
			continue
		if (c - centre).length_squared() > keep_radius * keep_radius:
			drop.append(c)
	for c: Vector2i in drop:
		world.unload_column(c.x, c.y)
		stat_unloaded += 1


func status_text() -> String:
	return "cols %d  pending %d  chunks %d  gen %.0f ms" % [
		world.loaded_columns(), _pending.size(), world.chunk_count(), stat_gen_ms]
