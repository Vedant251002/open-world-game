extends Node
class_name WalkTest
## Does the ground hold you up while you run?
##
## Collision is baked per chunk on a worker thread and installed on the main
## one, so it is a queue like everything else — and a queue that falls behind
## the player is a hole he drops through. This drives the real player body with
## real gravity along a long path and watches for the floor going missing.
##
## Everything happens in _physics_process: a ray cast from _process asks the
## physics server about a world it has not stepped yet, which produces misses
## that are the test's fault rather than the game's.

var world: VoxelWorld
var player: Player
var streamer: ChunkStreamer

const SPEED := 7.4          ## sprint
const SECONDS := 60.0
## Radians per second of heading drift. A long slow arc rather than a straight
## line: it never stops entering unexplored ground, and it presents the
## streaming ring with a different edge every second instead of only ever the
## same one.
const TURN := 0.05

var _t := 0.0
var _warm := 0
var _start := Vector3.ZERO
var _frames := 0
var _unsupported := 0
var _fell := 0
var _worst_drop := 0.0
var _first_hole := Vector3.ZERO
var _in_run := false
var _runs: Array[String] = []
var _armed := false
var _wait := 0.0
var _worst_backlog := 0
var _fps_cap := 0


func begin(at: Vector3, fps_cap: int = 0) -> void:
	_fps_cap = fps_cap
	_start = at
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The frame rate is the variable that matters most here: mesh and collision
	# upload are rationed per frame, so at 30 fps the queue drains at half the
	# rate while the player still runs at 7.4 m/s.
	Engine.max_fps = _fps_cap
	set_process(true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		print("[walk] armed after %.1fs, backlog %d, columns %d" % [
			_wait, world.pending(), world.loaded_columns()])
		player.teleport(Vector3(_start.x, world.ground_m(_start.x, _start.z) + 0.5,
			_start.z), 0.0)
		return

	# Let the body settle onto the ground before believing anything it says.
	if _warm < 20:
		_warm += 1
		return

	_t += delta
	# Drive the real movement code rather than moving the body ourselves: the
	# thing under test is is_on_floor(), floor snapping and gravity, and pushing
	# the capsule around directly would skip all three.
	player.yaw = _t * TURN
	player.set_touch_move(Vector2(0.0, -1.0))

	var p := player.global_position

	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0),
		p - Vector3(0, 3.0, 0), 1)
	var hit := space.intersect_ray(q)

	_frames += 1
	_worst_backlog = maxi(_worst_backlog, world.pending())

	# Two separate questions. "No floor under me" is the cause; "I am below the
	# ground the heightmap says is here" is the symptom the player reports.
	var ground := world.ground_m(p.x, p.z)
	var drop := ground - p.y
	# Being below ground_m() is not the same as being buried. ground_m() reports
	# the top solid voxel of the column, which over a house is its roof, so
	# anyone standing indoors is four metres "under the surface" and perfectly
	# fine. The question that means something is whether the player's head is
	# inside rock.
	if world.is_solid(VoxelWorld.to_voxel(p + Vector3(0, 1.5, 0))):
		_fell += 1
		_worst_drop = maxf(_worst_drop, drop)

	if hit.is_empty():
		_unsupported += 1
		if _first_hole == Vector3.ZERO:
			_first_hole = p
		if not _in_run and _runs.size() < 14:
			_runs.append("  t=%5.1fs  drop %5.2f m  %s" % [
				_t, drop, world.debug_support(p - Vector3(0, 0.3, 0))])
		_in_run = true
	else:
		_in_run = false

	if _t >= SECONDS:
		_report()
		get_tree().quit(1 if (_unsupported > 0 or _fell > 0) else 0)


func _report() -> void:
	var pct := 100.0 * float(_unsupported) / maxf(float(_frames), 1.0)
	print("[walk] %.0f s of sprinting over %d physics frames, ending %.0f m out" % [
		_t, _frames, player.global_position.distance_to(_start)])
	print("[walk] frames with no floor under the player: %d (%.2f%%)" % [
		_unsupported, pct])
	print("[walk] frames with the head inside solid rock: %d (worst %.2f m below the surface)" % [
		_fell, _worst_drop])
	print("[walk] worst mesh backlog: %d chunks, %d synchronous rescues" % [
		_worst_backlog, world.stat_rescues])
	for r: String in _runs:
		print("[walk]" + r)
	if _unsupported > 0 or _fell > 0:
		print("[walk] FAIL")
	else:
		print("[walk] PASS — solid ground under every frame")
