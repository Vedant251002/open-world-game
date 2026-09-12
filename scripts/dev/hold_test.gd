extends Node
class_name HoldTest
## What a worker does between being given an order and receiving the plan for it.
##
## That gap is the better part of a minute on a free model, and for the whole of
## it the worker used to be reported as "idle" and behave like it: _tick_idle
## never asked whether they were in the middle of anything, so they set off on a
## random wander around the well while the plan was being written. From where
## the player stands that is indistinguishable from having been ignored.
##
## So this asserts the two halves of the fix, which are separate things and can
## fail separately: that they go to the plot and stay on it, and that the roster
## says so in words that mean something.
##
## Run with:  godot --path . -- --holdtest

var world: VoxelWorld
var village: Village
var crew: Crew
var clock: GameClock
var player: Player

var _wait := 0.0
var _t := 0.0
var _armed := false
var _worker: Worker = null
var _plot: Plot = null
## Where the worker is meant to end up: off the plot edge, on the street side.
var _post := Vector3.ZERO
var _fails: Array[String] = []
var _saw_status: Dictionary = {}
## How far the worker strayed from the plot after arriving on it.
var _worst_drift := 0.0
var _arrived := false

## Long enough that the old wander timer — four to eleven seconds — would have
## fired several times over.
const WATCH_SECONDS := 34.0


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy() and _wait < 15.0:
		_wait += delta
		return
	if not _armed:
		_arm()
		return

	_t += delta
	_saw_status[_worker.status_text()] = true

	# Measured against where they are actually meant to stand, not against the
	# middle of the plot. A worker stands clear of their own building site, and
	# on a thirty metre plot that is a good twenty metres from its centre —
	# which is what makes "distance to centre" a useless test.
	var to_post := _flat(_worker.global_position - _post)
	if not _arrived and to_post < 4.0:
		_arrived = true
		print("[hold] reached the standing place after %.0f s" % _t)
	if _arrived:
		_worst_drift = maxf(_worst_drift, to_post)

	if _t >= WATCH_SECONDS:
		_report()


func _arm() -> void:
	_armed = true
	if crew == null or crew.workers.is_empty():
		_fails.append("no crew to test")
		_report()
		return
	_worker = crew.workers[0]
	# The plot the dispatcher would have picked, chosen the same way.
	var best_d := INF
	for p: Plot in village.plots:
		if p.occupied_by >= 0 or p.reserved:
			continue
		var d := p.centre_m().distance_squared_to(_worker.global_position)
		if d < best_d:
			best_d = d
			_plot = p
	if _plot == null:
		_fails.append("no free plot to send anybody to")
		_report()
		return
	_plot.reserved = true
	# The same sum Worker._stand_for does: off the street side of the plot,
	# clear of the margin the nav grid blocks around a building site.
	var dir := _plot.street_dir
	var half: float = (_plot.size_m().x if absi(dir.x) > 0 else _plot.size_m().y) * 0.5
	_post = _plot.centre_m() + Vector3(dir) * (half + Worker.STAND_CLEAR_M)
	# Deliberately without the dispatcher and without the model: this is about
	# what the worker does while nothing answers, which is the case the player
	# actually waits through.
	_worker.start_thinking("build a hut", _plot)
	print("[hold] %s given an order, plot %d on %s, %.0f m away" % [
		_worker.display_name(), _plot.id, _plot.street_name,
		_flat(_worker.global_position - _plot.centre_m())])


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _report() -> void:
	set_process(false)
	if _worker != null:
		var from_well := _flat(_worker.global_position - village.well_pos)
		var from_post := _flat(_worker.global_position - _post)
		print("[hold] after %.0f s: %.1f m from the standing place, %.0f m from the well"
			% [_t, from_post, from_well])
		print("[hold] statuses seen: %s" % ", ".join(_saw_status.keys()))

		if not _arrived:
			_fails.append("never reached the standing place in %.0f s"
				% WATCH_SECONDS)
		elif _worst_drift > 6.0:
			# The old behaviour: wander off toward the well and back again.
			_fails.append("drifted %.0f m off the standing place while waiting"
				% _worst_drift)

		if _worker.status_text() == "idle":
			_fails.append("still reported as idle while holding an order")
		if not _worker.busy():
			_fails.append("not counted as busy while holding an order")

		var said_something := false
		for line: String in _saw_status:
			if line.find("heading to") >= 0 or line.find("sizing up") >= 0:
				said_something = true
		if not said_something:
			_fails.append("roster never said what they were doing: %s"
				% ", ".join(_saw_status.keys()))

	for f: String in _fails:
		print("[hold] FAIL: %s" % f)
	print("[hold] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
