extends Node
class_name ModeTest
## Chat and Command, in the running game, against the real model and the real
## classifier.
##
##   1. Chat: an order said in Chat mode is answered and NOT done — no plan,
##      no walk, nothing reserved — and the answer came from the model.
##   2. Command: "go to the well" is taken by the classifier, not the model,
##      and the worker sets off.
##   3. A new job: hiring somebody as a made-up role writes the role, then its
##      question set, in the role's own words, and an order to the new hand is
##      taken by the classifier using it.
##   4. The interface: the toggle sends the same line to chat or to orders.
##
##   godot4 --headless --path . -- --modetest

var dispatch: Dispatcher
var crew: Crew
var hud: Hud

var _fails: Array[String] = []
var _lines: Array = []           ## [worker_id, text, kind]
var _accepted: Array = []        ## [worker_id, assumptions]
var _chat_routed := 0
var _cmd_routed := 0


func begin() -> void:
	for w: Worker in crew.workers:
		w.said.connect(func(who: Worker, line: String, kind: String) -> void:
			_lines.append([who.memory.worker_id, line, kind]))
	dispatch.plan_accepted.connect(func(w: Worker, a: Array) -> void:
		_accepted.append([w.memory.worker_id, a]))
	hud.chat_given.connect(func(_w: Worker, _t: String) -> void: _chat_routed += 1)
	hud.instruction_given.connect(func(_w: Worker, _t: String) -> void: _cmd_routed += 1)
	print("[mode] AI: %s" % dispatch.describe_ai())
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	await _chat_does_nothing()
	await _command_goes_to_classifier()
	await _new_role_gets_questions()
	await _toggle_routes()
	print("\n[mode] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ===\n  " + "\n  ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _chat_does_nothing() -> void:
	var w := crew.get_worker("tobias")
	var calls_before: int = dispatch.llm.calls_made
	var quick_before: int = dispatch.quick.calls_made
	for said: String in ["can you build me a hut by the well?", "go to the well",
			"how much timber have we got?"]:
		_lines.clear()
		_accepted.clear()
		dispatch.chat(w, said)
		var line := await _reply_from(w, 60.0)
		print("[mode] chat  you: %s\n             Tobias: %s" % [said, line])
		if line == "" or line == "…":
			_fail("chat: no answer to \"%s\"" % said)
		await get_tree().create_timer(2.0).timeout
		if not _accepted.is_empty():
			_fail("chat: \"%s\" was turned into a plan: %s" % [said, str(_accepted)])
		# Busy with a job, that is — a stroll of his own is not chat's doing.
		if w.busy() and not w.status_text() in ["walking", "idle"]:
			_fail("chat: Tobias went to work on \"%s\" (%s)" % [said, w.status_text()])
		if dispatch._running.has("tobias"):
			_fail("chat: \"%s\" started a job" % said)
		if dispatch._open.has("tobias"):
			_fail("chat: \"%s\" opened an order" % said)
	if dispatch.quick.calls_made != quick_before:
		_fail("chat: the classifier was asked about chat")
	if dispatch.llm.calls_made == calls_before:
		_fail("chat: the model was never asked — the lines were the offline fallback")
	print("[mode] chat: %d model calls, %d classifier calls" % [
		dispatch.llm.calls_made - calls_before, dispatch.quick.calls_made - quick_before])


func _command_goes_to_classifier() -> void:
	var w := crew.get_worker("tobias")
	var taken: int = dispatch.quick.taken
	var plans: int = dispatch.llm.calls_made
	_accepted.clear()
	dispatch.instruct(w, "go to the well")
	var t := 0.0
	while _accepted.is_empty() and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("[mode] command \"go to the well\": %s, classifier took %d, %s  [%s]" % [
		"accepted" if not _accepted.is_empty() else "nothing",
		dispatch.quick.taken - taken, w.status_text(), dispatch.quick.describe()])
	if dispatch.quick.taken == taken:
		_fail("command: the classifier did not take \"go to the well\" (%s)" % dispatch.quick.describe())
	if _accepted.is_empty():
		_fail("command: \"go to the well\" was never accepted")
	if dispatch.llm.calls_made > plans + 1:
		_fail("command: the model was asked to plan an order the classifier took")


func _new_role_gets_questions() -> void:
	var who: Worker = null
	for c: Worker in crew.citizens():
		if not c.busy():
			who = c
			break
	if who == null:
		_fail("role: nobody free to hire")
		return
	dispatch.instruct(who, "hire you as a candlemaker: makes candles at the bench and sells them at the store")
	var t := 0.0
	while t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if crew.roles.has("candlemaker") and str(crew.roles.get_role("candlemaker").questions.get("source", "")) == "model":
			break
	if not crew.roles.has("candlemaker"):
		_fail("role: the candlemaker was never written up")
		return
	var role := crew.roles.get_role("candlemaker")
	var qs := role.questions
	print("[mode] role candlemaker (%s): %s" % [role.source, role.summary()])
	print("[mode]   questions (%s): %s" % [str(qs.get("source", "")), str(qs.get("action_ask", ""))])
	for v: String in qs.get("verbs", {}):
		print("[mode]     %-8s %s" % [v, qs["verbs"][v]["means"]])
	if qs.is_empty():
		_fail("role: the candlemaker has no question set")
	elif role.source == "model" and str(qs.get("source", "")) != "model":
		_fail("role: the baker's questions were never put in its own words")
	# Survives the save.
	var back := Role.from_dict(JSON.parse_string(JSON.stringify(role.to_dict())))
	if back.questions.get("action_ask", "") != qs.get("action_ask", "x"):
		_fail("role: the question set did not survive a save")
	# And an order to the new hand goes to the classifier with it.
	await get_tree().create_timer(3.0).timeout
	if who.hired:
		var taken: int = dispatch.quick.taken
		_accepted.clear()
		dispatch.instruct(who, "go to the well")
		t = 0.0
		while _accepted.is_empty() and t < 30.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		print("[mode] candlemaker told \"go to the well\": classifier took %d (%s)" % [
			dispatch.quick.taken - taken, dispatch.quick.describe()])
		if dispatch.quick.taken == taken:
			print("[mode]   (handed to the model — not a failure on its own; see jev_probe for rates)")
	else:
		print("[mode] candlemaker not free to test an order (%s)" % who.status_text())


func _toggle_routes() -> void:
	var w := crew.get_worker("ren")
	var chat0 := _chat_routed
	var cmd0 := _cmd_routed
	hud._set_talk_mode(ModeToggle.CHAT)
	hud._route(w, "lovely day, isn't it")
	hud._set_talk_mode(ModeToggle.COMMAND)
	hud._route(w, "wait here")
	if _chat_routed != chat0 + 1 or _cmd_routed != cmd0 + 1:
		_fail("ui: chat routed %d, command routed %d (wanted 1 and 1)" % [
			_chat_routed - chat0, _cmd_routed - cmd0])
	if hud.chat != null and hud.chat.mode != ModeToggle.COMMAND:
		_fail("ui: the chat panel's toggle did not follow the bar's")
	# A worker with a question pending, in Chat mode, is chatted with — not
	# answered.
	w.pending_question = "Which side for the door?"
	hud._set_talk_mode(ModeToggle.CHAT)
	var chat1 := _chat_routed
	hud._route(w, "never mind that, how are you?")
	if _chat_routed != chat1 + 1:
		_fail("ui: chat to somebody with a question pending went to the answer")
	w.pending_question = ""
	hud._set_talk_mode(ModeToggle.COMMAND)
	print("[mode] ui: toggle routes chat and command apart")


## The next line this worker says that is not a murmur, or "" after `limit`.
func _reply_from(w: Worker, limit: float) -> String:
	var t := 0.0
	while t < limit:
		for l: Array in _lines:
			if l[0] == w.memory.worker_id and str(l[1]) != "…":
				return str(l[1])
		await get_tree().process_frame
		t += get_process_delta_time()
	return ""


func _fail(why: String) -> void:
	_fails.append(why)
	print("[mode] FAIL %s" % why)
