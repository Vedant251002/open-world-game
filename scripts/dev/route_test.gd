extends Node
class_name RouteTest
## The router, live, against the real gateway: a list of sentences, one at
## a time, and what the small model made of each.
##
## Nothing here checks content — a model answers differently every time —
## only that every sentence comes back as a plan, a chat or a question, and
## that the plans name verbs the town has. Run with:
##
##   godot4 --headless --path . -- --routetest --nofar --nosave
##
## Pass --say="..." to route one sentence of your own instead of the list.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock
var town: Town
var world: VoxelWorld

var _armed := false
var _wait := 0.0
var _t := 0.0
var _i := -1
var _waiting := false
var _sentences: Array[String] = []
var _fails: Array[String] = []
var _results: Array[String] = []
var _t0 := 0.0

const LIST := [
	"bring some fish",
	"get me some stone",
	"follow me",
	"wait here",
	"every morning, water the field",
	"hire %s as a guard",
	"no, I want thatch roofs",
	"you are my shepherd now",
	"go and stand at the well until noon",
	"sell forty bricks",
	"what are you doing?",
	"set the tax to 15 percent",
	"how many bricks do we have?",
	"declare a curfew",
	"fence the corner and put six hens in it",
	"save the game",
	"build a small bakery with a big window facing the street",
]


func begin(say: String) -> void:
	if say != "":
		_sentences = [say]
	else:
		for s: String in LIST:
			_sentences.append(s)
	dispatch.llm.routed.connect(_on_routed)
	dispatch.llm.plan_ready.connect(func(_id: String, plan: Dictionary) -> void:
		print("[route]   designer -> %s" % JSON.stringify(Steps.normalise(plan)).substr(0, 200)))
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		print("[route]   %s (%s): %s" % [w.display_name(), kind, line]))
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		clock.speed = 1.0
		print("[route] provider: %s" % dispatch.describe_ai())
		if not dispatch.ai_online():
			_fails.append("no API key, or --offline: there is nothing live to test")
			_finish()
		return
	_t += delta
	if _waiting:
		if _t - _t0 > 60.0:
			_fails.append("timed out: %s" % _sentences[_i])
			_waiting = false
		return
	_i += 1
	if _i >= _sentences.size():
		_finish()
		return
	var s := _sentences[_i]
	if s.find("%s") >= 0:
		var name := ""
		for w: Worker in crew.workers:
			if not w.hired:
				name = w.display_name()
				break
		s = s % (name if name != "" else "Ada")
		_sentences[_i] = s
	var mira := crew.get_worker("mira")
	print("[route] Mira <- \"%s\"" % s)
	_waiting = true
	_t0 = _t
	dispatch.instruct(mira, s)


func _on_routed(_id: String, reply: Dictionary) -> void:
	var took := _t - _t0
	var kind := str(reply.get("kind", ""))
	var line := ""
	match kind:
		"plan":
			var steps := Steps.normalise(reply)
			var shape: Array[String] = []
			for st: Dictionary in steps:
				var fields := st.duplicate()
				fields.erase("do")
				shape.append("%s %s" % [str(st.get("do", "")), JSON.stringify(fields)])
				if not Steps.known(str(st.get("do", ""))):
					_fails.append("unknown verb %s for: %s" % [st.get("do", ""), _sentences[_i]])
			line = " ; ".join(shape)
		"chat":
			line = "(chat)"
		"question":
			line = "? " + str(reply.get("question", ""))
		_:
			line = "%s: %s" % [kind, str(reply.get("reason", ""))]
			_fails.append("%s: %s" % [kind, _sentences[_i]])
	print("[route]   -> %s   (%.1fs)" % [line, took])
	_results.append("%-58s -> %s" % [_sentences[_i], line])
	# Let the dispatcher act on it before the next sentence — and stay under
	# the free tier's tokens-a-minute, which a list of orders fired back to
	# back will exhaust in four. A player types one order at a time; this is
	# the only place in the game that does not.
	var settle := 30.0 if line.begins_with("build") else 26.0
	await get_tree().create_timer(settle).timeout
	# A worker on an errand cannot take the next order; call them back.
	var mira := crew.get_worker("mira")
	if mira.busy():
		mira.drop_everything()
	_waiting = false


func _finish() -> void:
	print("[route] ---")
	for r: String in _results:
		print("[route] " + r)
	print("[route] %s" % dispatch.llm.stats_text())
	for f: String in _fails:
		print("[route] FAIL: " + f)
	print("[route] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
