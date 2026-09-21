extends Node
class_name QuickFlow
## The front door, end to end, inside the running game.
##
## quick_test.gd checks the parsing in isolation. This checks the part that
## isolation cannot: that a sentence typed at a worker becomes a real HTTP
## request, that the answer comes back through _on_quick_decided into
## _on_plan_ready, that the validator passes it, and that the worker actually
## walks off with the right job. Every one of those is a join between two
## pieces that were tested apart.
##
## It needs something answering on the other end, which is what
## --classifier=http://127.0.0.1:PORT/v1/classify is for. Pointed at a stand-in
## that speaks classifier.dev's format, the whole journey is exercised without
## depending on a third party being up, or on what it happens to think today.
##
## The last case is the one that matters most for shipping: with the endpoint
## pointed somewhere that refuses the connection, every order must still be
## carried out, by the model or the offline library, exactly as before. That is
## the state a browser with no CORS permission will be in.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock
var town: Town
var world: VoxelWorld

## say -> what the worker should end up doing.
##   verb  — the errand the worker must actually start
##   quick — true if the front door should have answered it
const CASES := [
	# A plain order with the verb in it.
	{"say": "go to the well", "verb": "go", "quick": true},
	# The case the whole thing exists for: no keyword anywhere in it.
	{"say": "nip over to the well", "verb": "go", "quick": true},
	# Two jobs in one sentence: must never be taken here, whatever the
	# classifier would have said, because half of it would be dropped.
	{"say": "go to the well and wait there", "verb": "", "quick": false},
	# A building is described, not chosen. Straight to the model.
	{"say": "build a small bakery", "verb": "", "quick": false},
]

var _armed := false
var _wait := 0.0
var _t := 0.0
var _phase := 0
var _fails: Array[String] = []
var _spoke: Array[String] = []
var _assumptions: Array = []
var _took_before := 0
## The errand the worker actually started, caught the frame it started.
## Sampling it later is a race: a walk to the well can be over inside the
## window, and an errand that finished looks exactly like one that never began.
var _seen_job := ""


func begin() -> void:
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		_spoke.append("%s|%s" % [kind, line])
		print("      %s (%s): %s" % [w.display_name(), kind, line]))
	dispatch.plan_accepted.connect(func(_w: Worker, a: Array) -> void:
		_assumptions = a)
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 20.0:
			return
		_armed = true
		clock.speed = 60.0
		print("\n[flow] endpoint: %s" % dispatch.quick.endpoint)
		print("[flow] %s\n" % dispatch.describe_ai())
		return

	_t += delta
	if _phase >= CASES.size():
		_finish()
		return

	var case: Dictionary = CASES[_phase].duplicate()
	# The degraded runs: with the front door switched off, or pointed at
	# something that refuses the connection, NOTHING may be taken here and
	# every order must still be carried out. That is the state a browser with
	# no CORS permission is in, so it is the state that has to be tested.
	if "--expect-none" in QuickIntent.args():
		case["quick"] = false
	var worker: Worker = crew.hired()[0]

	# Wait for them to be free first. An order given to somebody mid-job is
	# refused before it ever reaches the front door, and a test that scores
	# that as "handed to the model" is a test that passes for the wrong
	# reason — which is exactly what the first run of this did.
	if not has_meta("sent_%d" % _phase):
		if worker.busy() or worker.pondering != "" or not worker.job_errand.is_empty():
			if _t > 60.0:
				_fails.append("\"%s\": %s never became free" % [str(case["say"]),
					worker.display_name()])
				_phase += 1
				_t = 0.0
			return

	# Fire the order once per phase.
	if not has_meta("sent_%d" % _phase):
		set_meta("sent_%d" % _phase, true)
		_spoke.clear()
		_assumptions = []
		_took_before = dispatch.quick.taken
		_seen_job = ""
		worker.job_errand = {}
		print("[flow] \"%s\"" % str(case["say"]))
		dispatch.instruct(worker, str(case["say"]))
		_t = 0.0
		return

	var running := str(worker.job_errand.get("kind", ""))
	if running != "" and _seen_job == "":
		_seen_job = running

	# Give the round trip time, then judge it.
	if _t < 6.0:
		return
	_judge(case, worker)
	_phase += 1
	_t = 0.0


func _judge(case: Dictionary, worker: Worker) -> void:
	var say := str(case["say"])
	var want_quick: bool = case["quick"]
	var took: bool = dispatch.quick.taken > _took_before
	var thought := false
	for s: String in _spoke:
		if s.find("let me think about that") >= 0:
			thought = true

	if want_quick:
		if not took:
			_fails.append("\"%s\": the front door did not take it (%s)"
				% [say, dispatch.quick.describe()])
		elif thought:
			_fails.append("\"%s\": taken, but the worker still said they were thinking" % say)
		else:
			var got := _seen_job
			if got != str(case["verb"]):
				_fails.append("\"%s\": job was \"%s\", wanted \"%s\"" % [say, got, str(case["verb"])])
			else:
				var said_so := false
				for a: Variant in _assumptions:
					if str(a).find("without having to think") >= 0:
						said_so = true
				if not said_so:
					_fails.append("\"%s\": taken silently — the player was never told" % say)
				else:
					print("      OK  taken by the front door -> %s\n" % got)
	else:
		if took:
			_fails.append("\"%s\": the front door took it and should not have" % say)
		else:
			print("      OK  handed to the model\n")


func _finish() -> void:
	set_process(false)
	print("[flow] %s" % dispatch.quick.describe())
	if _fails.is_empty():
		print("[flow] all good")
	else:
		for f: String in _fails:
			print("[flow] FAIL %s" % f)
	get_tree().quit(1 if not _fails.is_empty() else 0)
