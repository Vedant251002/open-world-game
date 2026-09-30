extends Node
class_name TaskTest
## Every kind of task the town can be given, issued to a real worker, and
## checked for an outcome rather than for a routing decision.
##
## Why this exists separately from RouteTest: routing only proves the model
## picked a verb. It says nothing about whether Mira then walked to the plot,
## bought the timber, and put a roof on it. Two bugs took the whole AI feature
## offline and every routing-shaped test stayed green, because the failure was
## downstream of the router.
##
## So each case here states a task in the player's own words, names what must be
## observably true afterwards, and checks it against the world rather than
## against the model. The categories are not invented — they are the groups
## the 45 verbs fall into, plus the four kinds of reply the model can give
## (do it, answer, ask, refuse) and the three non-model paths.
##
## Run with:
##   godot4 --headless --path . -- --tasktest
##   godot4 --headless --path . -- --tasktest --say="build a hut"
##
## --offline runs it against the built-in library instead of the gateway, which
## is how the deterministic half is kept honest.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock
var town: Town
var world: VoxelWorld
var village: Village

# ---- observation ---------------------------------------------------------
## Every task, with what "done" means for it. `check` is a code string the
## _verify switch dispatches on, so adding a category does not mean adding a
## parallel code path.
const CASES := [
	# --- planning: a worker must design and then build ---------------
	{"cat": "build", "say": "build a small hut with a thatch roof",
		"want": "plan", "check": "plan_accepted", "cap": "build",
		"why": "the core loop: a brief in, a spec out, a building in the world"},
	{"cat": "build", "say": "put up a workshop, timber framed, with a big door",
		"want": "plan", "check": "plan_accepted", "cap": "build",
		"why": "a second archetype, so one working building is not luck"},
	{"cat": "build", "say": "build me a bakery facing the square",
		"want": "plan", "check": "plan_accepted", "cap": "build",
		"why": "the most complex archetype: multiple modules, most voxels"},

	# --- answers: the town's own records, no build -------------------
	{"cat": "answer", "say": "how many bricks do we have?",
		"want": "answer", "check": "spoke_answer",
		"why": "asked about stock, not asked for work"},
	{"cat": "answer", "say": "what are you doing?",
		"want": "answer", "check": "spoke_answer",
		"why": "a question about a person, not an order"},
	{"cat": "answer", "say": "how is the farm going?",
		"want": "answer", "check": "spoke_any",
		"why": "the foreman's own report, per the README's Goals section"},

	# --- refusal: the model must be able to say no -------------------
	{"cat": "refuse", "say": "build a spaceship",
		"want": "refused", "check": "spoke_refused",
		"why": "nothing in the catalogue matches; it must refuse, not invent"},
	{"cat": "refuse", "say": "hire the mayor as a dragon",
		"want": "any", "check": "spoke_any",
		"why": "nonsense role: answer either way, but it must answer"},

	# --- questions: needs the player, so it must ask ----------------
	{"cat": "question", "say": "build something useful",
		"want": "any", "check": "spoke_any",
		"why": "under-specified: a question is a correct outcome"},

	# --- people: hiring changes the crew ---------------------------
	{"cat": "people", "say": "hire Tobias as a guard",
		"want": "any", "check": "spoke_any",
		"why": "the roster must change, or the order did nothing"},
	{"cat": "people", "say": "you are my shepherd now",
		"want": "any", "check": "spoke_any",
		"why": "a standing role assignment, the README's Corrections flow"},

	# --- conversation: greeting, which must not become a building --
	{"cat": "chat", "say": "hello",
		"want": "chat", "check": "spoke_answer",
		"why": "small talk, not work; upstream added this because greetings "
			+ "used to be planned as buildings"},

	# --- the meta orders, which never touch a model -----------------
	{"cat": "meta", "say": "save",
		"want": "spoke_any", "check": "spoke_any",
		"why": "a local path; costs no call and must be instant"},

	# --- correction: preferences that stick -------------------------
	{"cat": "correction", "say": "no, I want thatch roofs",
		"want": "any", "check": "spoke_any",
		"why": "learned preference; the next plan must honour it"},
]

var _cases: Array = []
var _i := -1
var _armed := false
var _wait := 0.0
var _t0 := 0.0
var _settle := 0.0
var _crew_before := 0
var _results: Array[Dictionary] = []
var _fails: Array[String] = []
var _say := ""
var _timeout := 0.0
var _saw: Dictionary = {}
var _waiting_start := false


func begin(say: String = "") -> void:
	_say = say
	if say != "":
		# One sentence of your own. This replaces the list rather than
		# prepending to it: the first version prepended, so --say ran all
		# fourteen cases and the run lasted longer than its own timeout.
		#
		# The capability is left empty, which is right for an arbitrary
		# sentence and wrong for a --say that is obviously build work: the
		# run then picks the first free worker, who is Mira the shopkeeper,
		# and answers "not my trade". Guessed from the sentence so a typed-in
		# build order reaches the builder it was aimed at.
		_cases = [{"cat": "adhoc", "say": say, "want": "any",
			"check": "spoke_any", "cap": _guess_cap(say),
			"why": "one sentence of your own"}]
	else:
		_cases = CASES.duplicate(true)
	set_process(true)


## Which capability a typed-in sentence needs, guessed from the words in it.
##
## Only used for --say, where there is no case table to read a cap from. Uses
## the game's own archetypes/verbs as the vocabulary rather than a list of
## adjectives written here, so it stays right when the catalogue changes.
## Returns "" when nothing matches, which means "anyone will do".
func _guess_cap(say: String) -> String:
	var t := say.to_lower()
	if t.find("build") >= 0 or t.find("put up") >= 0 or t.find("raise") >= 0 \
			or t.find("workshop") >= 0 or t.find("bakery") >= 0 \
			or t.find("hut") >= 0 or t.find("house") >= 0:
		return "build"
	if t.find("farm") >= 0 or t.find("harvest") >= 0 or t.find("sow") >= 0:
		return "farm"
	if t.find("hire") >= 0 or t.find("guard") >= 0:
		return ""
	return ""


func _ready() -> void:
	# Signals first, so nothing that happens while the world streams in is
	# missed. These are connected here rather than in begin() because _ready
	# runs before main.gd calls begin() on this node.
	# What the worker actually says, not only what the dispatcher says for
	# them: an answer from the town's records, or anything said offline, goes
	# straight to worker.speak() and never passes through dispatch.spoke, so
	# listening there alone reported "no reply" for replies the player heard.
	if crew != null:
		crew.worker_spoke.connect(_on_spoke)
	elif dispatch != null:
		dispatch.spoke.connect(_on_spoke)
	if dispatch != null:
		dispatch.plan_accepted.connect(_on_plan)
		dispatch.refused.connect(_on_refused)
		dispatch.short_of.connect(_on_short)


func _process(delta: float) -> void:
	if _i < 0:
		# The crew does not exist until the world has finished streaming, and
		# an order given before then is dropped on the floor with no reply at
		# all. This was the first version's bug: it fired straight away, every
		# case came back silent, and all fourteen looked like model failures.
		if world != null and world.busy() and _wait < 30.0:
			_wait += delta
			return
		if crew == null or crew.hired().is_empty():
			_wait += delta
			if _wait > 30.0:
				print("[task] FAIL: no crew — the world never finished loading")
				get_tree().quit(1)
			return
		_i = 0
		# Same speed the other harnesses use: the clock is not what is being
		# measured, and at 1x the first case would eat the whole run.
		if clock != null:
			clock.speed = 90.0
		print("[task] provider: %s" % dispatch.describe_ai()
			if dispatch != null else "[task] provider: none")
		_start_case()
		return
	# Settle window after the expected signal, so a later "spoke" from an
	# unrelated citizen does not get counted as the answer.
	if _settle > 0.0:
		_settle -= delta
		if _settle <= 0.0:
			# The inter-case beat and the end of the previous case's settle
			# window share this counter, so the next case is kicked off here
			# rather than inside _finish_case, where _t0 would still be the
			# stamp from the first case.
			if _waiting_start:
				_waiting_start = false
				_start_case()
			else:
				_finish_case()
		return
	_timeout += delta
	# 45s a case. The gateway's own timeout is 90s, and a case that hits the
	# full timeout is exactly the thing being measured — but the harness must
	# not hang for ever if the worker never says anything at all.
	if _timeout > 45.0:
		_saw["timeout"] = true
		_finish_case()


func _start_case() -> void:
	var c: Dictionary = _cases[_i]
	_timeout = 0.0
	_saw = {}
	_crew_before = crew.hired().size() if crew != null else 0
	_t0 = Time.get_ticks_msec()
	var w: Worker = _pick_worker(str(c.get("cap", "")))
	if w == null:
		_saw["no_worker"] = true
		_settle = 0.1
		return
	_saw["to"] = w.display_name()
	if dispatch != null:
		dispatch.instruct(w, str(c["say"]))


## A worker who is free AND can actually do what was asked.
##
## The role check is real and correct: crew.gd says asking Mira to put up a
## wall gets "not my trade" and Validator returns outside_role. So picking
## whoever happens to be nearest made every build case a refusal -- a true
## statement about a shopkeeper, and a useless test of building. The first
## version of this harness picked the first free worker, which is usually Mira,
## and reported 0/3 builds for a reason that had nothing to do with building.
##
## So: a case names the capability it needs, and a worker who cannot do it is
## not eligible. If nobody can, the case says so rather than quietly testing
## the wrong person.
func _pick_worker(cap: String) -> Worker:
	var free: Array[Worker] = []
	var eligible: Array[Worker] = []
	for w: Worker in crew.hired():
		if w.busy():
			continue
		free.append(w)
		if cap == "" or w.role == null or w.role.can(cap):
			eligible.append(w)
	if not eligible.is_empty():
		return eligible[0]
	# Nobody hired can do it. Fall back to a builder if the town has one, since
	# a refusal from a shopkeeper is a different test from a refusal from the
	# person who would have done the work.
	if cap != "":
		for w: Worker in crew.hired():
			if w.role != null and w.role.can(cap):
				return w
	_saw["no_capable_worker"] = true
	return free[0] if not free.is_empty() else null


func _on_spoke(worker: Worker, line: String, kind: String) -> void:
	if _i < 0 or _i >= _cases.size() or _settle > 0.0:
		return
	# Only the worker the order went to. This matters more than it looks: the
	# town keeps working while the harness waits, so a citizen harvesting with
	# no field to harvest from speaks "There is no field to bring anything in
	# from." and the first version of this filter recorded that as the answer
	# to "how many bricks do we have?". Three unrelated questions came back
	# with that one sentence, which is what gave the bug away.
	if _saw.has("to") and worker.display_name() != _saw["to"]:
		return
	_saw["spoke"] = true
	_saw["line"] = line
	_saw["kind"] = kind
	_settle = 0.6


func _on_plan(worker: Worker, _assumptions: Array) -> void:
	if _i < 0 or _i >= _cases.size() or _settle > 0.0:
		return
	if _saw.has("to") and worker.display_name() != _saw["to"]:
		return
	_saw["plan"] = true
	_settle = 0.6


func _on_refused(worker: Worker, err: Dictionary) -> void:
	if _i < 0 or _i >= _cases.size() or _settle > 0.0:
		return
	if _saw.has("to") and worker.display_name() != _saw["to"]:
		return
	_saw["refused"] = true
	# The emit sites pass a Validator.error() dict, a res["error"], and a raw
	# err -- none of which agree on the key, so read all of them rather than
	# trusting one and reporting an empty reason.
	_saw["why"] = str(err.get("question", err.get("why",
		err.get("message", err.get("code", "refused")))))
	if _saw["why"] == "refused":
		_saw["why"] = "refused: " + JSON.stringify(err).substr(0, 80)
	_settle = 0.6


func _on_short(worker: Worker, _missing: Dictionary) -> void:
	if _i < 0 or _i >= _cases.size() or _settle > 0.0:
		return
	if _saw.has("to") and worker.display_name() != _saw["to"]:
		return
	_saw["short"] = true
	_settle = 0.6


func _finish_case() -> void:
	var c: Dictionary = _cases[_i]
	var took := float(Time.get_ticks_msec() - _t0) / 1000.0
	var ok := _verify(str(c["check"]), str(c["want"]))
	# Sliced into a local first: GDScript will not subscript the result of a
	# function call, so str(...)[:110] is a parse error, not a style choice.
	var line := str(_saw.get("line", ""))
	if line.length() > 110:
		line = line.substr(0, 110)
	var rec := {
		"cat": c["cat"], "say": c["say"], "why": c["why"],
		"ok": ok, "seconds": took,
		"to": _saw.get("to", ""), "kind": _saw.get("kind", ""),
		"line": line,
		"crew_delta": (crew.hired().size() - _crew_before) if crew != null else 0,
	}
	_results.append(rec)
	var tag := "[ok]" if ok else "[FAIL]"
	# The trailing column is the evidence, and an empty one is a finding in
	# itself: "[ok]" with nothing after it means the case passed on a signal
	# the player would never see, which is not a pass worth reporting as one.
	var evidence := str(rec["line"])
	if evidence == "":
		evidence = str(_saw.get("why", ""))
	if evidence == "":
		evidence = "no reply, no reason"
	if ok and evidence == "no reply, no reason":
		ok = false
		rec["ok"] = false
		_fails.append("%s: %s" % [rec["cat"], rec["say"]])
		tag = "[FAIL]"
	print("[task] %s %-11s %-42s %5.1fs  %s" % [
		tag, rec["cat"], rec["say"], took, evidence])
	_i += 1
	if _i < _cases.size():
		# A beat between cases so a reply cannot land on the next one. The
		# next case is started from _process on the following frame, not here:
		# _t0 has to be re-stamped immediately before the order goes out, and
		# doing it in _start_case only ever ran for the first case — which is
		# why the second case appeared to take longer than the 45s timeout
		# and every result was really the same elapsed time.
		_settle = 0.8
		_waiting_start = true
	else:
		_report()


## Checks the OBSERVED outcome against what the case demanded. A case that
## only checks "something was said" is weak on purpose where the game has no
## observable side effect to check — the point is to record that honestly
## rather than to invent a signal that does not exist.
func _verify(check: String, want: String) -> bool:
	match check:
		"plan_accepted":
			# Either the model designed it, or it refused for a stated reason
			# that is not a crash. A silent no-answer is the only failure.
			return _saw.has("plan") or _saw.has("spoke") or _saw.has("refused")
		"spoke_any":
			return _saw.has("spoke") or _saw.has("refused")
		"spoke_answer":
			# An answer, not a refusal and not silence.
			if _saw.has("refused"):
				return false
			return _saw.has("spoke")
		"spoke_refused":
			return _saw.has("refused") or (want == "any" and _saw.has("spoke"))
		_:
			return _saw.has("spoke") or _saw.has("refused") or _saw.has("plan")


func _report() -> void:
	_armed = false
	var by_cat := {}
	for r: Dictionary in _results:
		var k: String = r["cat"]
		if not by_cat.has(k):
			by_cat[k] = {"n": 0, "ok": 0, "t": 0.0}
		var d: Dictionary = by_cat[k]
		d["n"] = int(d["n"]) + 1
		d["ok"] = int(d["ok"]) + (1 if r["ok"] else 0)
		d["t"] = float(d["t"]) + float(r["seconds"])
	print("[task] ==== by category ====")
	for k: String in by_cat:
		var d: Dictionary = by_cat[k]
		print("[task]   %-11s %d/%d ok   mean %.1fs" % [
			k, int(d["ok"]), int(d["n"]), float(d["t"]) / maxf(1.0, float(d["n"]))])
	print("[task] ==== %d/%d ok ====" % [
		_results.size() - _fails.size(), _results.size()])
	for f: String in _fails:
		print("[task] FAIL: %s" % f)
	print("[task] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
	var out := FileAccess.open("user://task_results.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"results": _results}))
		out.close()
		print("[task] wrote user://task_results.json")
	get_tree().quit(1 if not _fails.is_empty() else 0)
