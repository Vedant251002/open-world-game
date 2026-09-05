extends Node
class_name AiTest
## The live AI path, end to end, against the real gateway.
##
## Everything else in this project can be tested deterministically. This cannot:
## it is a real HTTP call to a model that will answer differently every time, so
## what is checked is the shape of the journey rather than the content —
##
##   the call goes out, something comes back, it survives the schema check,
##   it survives the validator, the generator turns it into voxels, and the
##   worker walks off with it.
##
## It also reports whether the reply actually came from the model or whether the
## offline library quietly stood in, because a fallback that nobody noticed
## looks exactly like success.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock
var town: Town
var world: VoxelWorld

var _armed := false
var _wait := 0.0
var _t := 0.0
var _plan: Dictionary = {}
var _question := ""
var _refusal := ""
var _asked_first := ""
var _reached_model := 0
var _error := ""
var _assumptions: Array = []
var _fails: Array[String] = []
var _phase := 0
var _instruction := "build a small bakery with a big window facing the street"

const VAGUE := "put something useful up over there"
const ANSWER := "a workshop, timber walls, and keep it small"


func begin(instruction: String) -> void:
	if instruction != "":
		_instruction = instruction
	dispatch.llm.plan_ready.connect(func(_id: String, plan: Dictionary) -> void:
		_plan = plan)
	# A question only ever comes out of a reply the model actually sent — the
	# offline library never asks anything — so it counts as reaching the model
	# just as much as a plan does.
	dispatch.llm.question_ready.connect(func(_id: String, q: String, _l: String) -> void:
		_question = q
		_reached_model += 1)
	dispatch.llm.failed.connect(func(_id: String, why: String) -> void:
		_error = why)
	dispatch.plan_accepted.connect(func(_w: Worker, a: Array) -> void:
		_assumptions = a)
	dispatch.refused.connect(func(_w: Worker, err: Dictionary) -> void:
		_refusal = str(err.get("code", "refused")))
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		print("[ai]   %s (%s): %s" % [w.display_name(), kind, line]))
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		clock.speed = 90.0
		print("[ai] provider: %s" % dispatch.describe_ai())
		if not dispatch.ai_online():
			_fails.append("no API key, or --offline: there is nothing live to test")
			_finish()
		return

	_t += delta
	match _phase:
		0:
			print("[ai] Mira <- \"%s\"" % _instruction)
			dispatch.instruct(crew.get_worker("mira"), _instruction)
			_phase = 1
			_t = 0.0
		1:
			if not _plan.is_empty() or _question != "":
				_report_reply()
				_phase = 2
				_t = 0.0
			elif _t > 110.0:
				_fails.append("nothing came back in 110 s (error: %s)"
					% ("none" if _error == "" else _error))
				_finish()
		2:
			# A question is a valid outcome — it is the whole of pillar P3 —
			# whether it came from the model deciding to ask or from the
			# validator turning the plan down. Only wait for a building when the
			# plan was actually accepted.
			if _question != "" or _refusal != "":
				if _refusal != "":
					print("[ai] validator refused the plan (%s); Mira asked: %s"
						% [_refusal, crew.get_worker("mira").pending_question])
				_phase = 3
				_t = 0.0
			elif not town.buildings.is_empty():
				# Registered means the shell is finished. She is still walking
				# home to report, which is part of the loop but not part of
				# whether the AI path worked.
				_check_built()
				_phase = 3
				_t = 0.0
			elif _t > 90.0:
				_fails.append("Mira never finished: %s"
					% crew.get_worker("mira").status_text())
				_finish()
		3:
			# The other half of the loop: a worker who asks, and an employer who
			# answers. Tobias checks before nearly every job, so a vague word to
			# him is the reliable way to reach it.
			print("[ai] Tobias <- \"%s\"" % VAGUE)
			_question = ""
			_refusal = ""
			_plan = {}
			dispatch.instruct(crew.get_worker("tobias"), VAGUE)
			_phase = 4
			_t = 0.0
		4:
			var tob: Worker = crew.get_worker("tobias")
			if tob.pending_question != "":
				_asked_first = tob.pending_question
				print("[ai] Tobias asked: %s" % tob.pending_question)
				print("[ai] answering: \"%s\"" % ANSWER)
				_plan = {}
				dispatch.answer(tob, ANSWER)
				_phase = 5
				_t = 0.0
			elif not _plan.is_empty():
				print("[ai] Tobias did not ask — he went straight to a plan")
				_finish()
			elif _t > 110.0:
				_fails.append("Tobias neither asked nor planned in 110 s")
				_finish()
		5:
			# Tobias asking again is not a failure — it is the whole of him. In
			# testing he answered "a workshop, timber walls" with "we have almost
			# no timber, shall I use sandstone?", which is the character reading
			# the town's actual stock. What matters is that the answer got back
			# into the loop and produced a fresh reply of some kind.
			var t2: Worker = crew.get_worker("tobias")
			if t2.pending_question != "" and t2.pending_question != _asked_first:
				print("[ai] Tobias came back with another question: %s"
					% t2.pending_question)
				_finish()
			elif not _plan.is_empty():
				var src := str(_plan.get("source", "?"))
				if src == "model":
					_reached_model += 1
				print("[ai] after the answer: source %s, archetype %s" % [src,
					str((_plan.get("spec", {}) as Dictionary).get("archetype", "?"))])
				_finish()
			elif _t > 110.0:
				_fails.append("the answer produced neither a plan nor a question")
				_finish()


func _report_reply() -> void:
	if _question != "":
		print("[ai] the model asked back: %s" % _question)
		return

	# Read the assumptions off the plan itself, not off plan_accepted: a plan the
	# validator turns down never reaches that signal, and its assumptions are
	# still the thing pillar P3 is about.
	if _assumptions.is_empty():
		_assumptions = _plan.get("assumptions", [])
	var source := str(_plan.get("source", "?"))
	print("[ai] plan source: %s   confidence %.2f" % [
		source, float(_plan.get("confidence", 0.0))])
	# A single fallback is not a failure of this code. These free endpoints drop
	# a request now and then, and standing in for one is exactly what the plan
	# library is for. What would be a failure is nothing ever reaching the model
	# at all, which _finish() checks across the whole run.
	if source == "model":
		_reached_model += 1
	else:
		print("[ai] NOTE: that one fell back to the %s (%s)" % [
			source, "no error reported" if _error == "" else _error])

	var spec: Dictionary = _plan.get("spec", {})
	print("[ai] archetype %s, %s stories, footprint %s, roof %s" % [
		str(spec.get("archetype", "?")), str(spec.get("stories", "?")),
		str(spec.get("footprint", "?")), str(spec.get("roof", "?"))])
	print("[ai] materials: %s" % JSON.stringify(spec.get("materials", {})))
	var mods: Array = spec.get("modules", [])
	var names: Array[String] = []
	for m: Variant in mods:
		if m is Dictionary:
			names.append(str((m as Dictionary).get("type", "?")))
	print("[ai] modules: %s" % ", ".join(names))
	print("[ai] assumptions (%d):" % _assumptions.size())
	for a: Variant in _assumptions:
		print("[ai]   - %s" % str(a))
	if _assumptions.is_empty():
		_fails.append("the plan carried no assumptions — pillar P3 broken")


func _check_built() -> void:
	if town.buildings.is_empty():
		_fails.append("nothing was ever registered as built")
		return
	var rec: Dictionary = town.buildings[0]
	var patch: VoxelPatch = rec["patch"]
	var fr: Rect2i = patch.footprint
	var cx := fr.position.x + fr.size.x / 2
	var cz := fr.position.y + fr.size.y / 2
	print("[ai] built %s on plot %d, %d voxels, world column top %d" % [
		patch.archetype, patch.plot_id, patch.touched, world.height_at(cx, cz)])


func _finish() -> void:
	if _reached_model == 0:
		_fails.append("no call reached the model at all — the live path is dead "
			+ "(last error: %s)" % ("none reported" if _error == "" else _error))
	print("[ai] ---")
	print("[ai] calls that reached the model: %d" % _reached_model)
	for f: String in _fails:
		print("[ai] FAIL: %s" % f)
	print("[ai] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
	get_tree().quit(1 if not _fails.is_empty() else 0)
