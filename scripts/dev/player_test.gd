extends Node
class_name PlayerTest
## How a real player breaks this game.
##
## The other harnesses ask whether a sentence is understood. This one asks
## what happens when a player is not being sensible: nonsense, insults, empty
## input, a sentence repeated forty times, a command aimed at the wrong person,
## two people given the same job at once, a question about something that does
## not exist. None of that is in steps.gd. All of it is what a player does in
## the first ten minutes.
##
## Three rules shape the cases:
##
##   1. A crash is a failure. A wrong or silly answer is not. The town is
##      allowed to say no, or to say something odd, as long as it answers and
##      the game keeps running.
##   2. Silence is a failure. A player who typed something and got nothing back
##      has hit a wall, and that is the bug worth finding.
##   3. The same sentence twice must not cost a player their job. Repeated
##      orders are how players actually talk to a village.
##
## Run with:
##   godot4 --headless --path . -- --playertest
##   godot4 --headless --path . -- --playertest --say="..." --provider=orcarouter
##
## Writes user://player_results.json. One process per group, so a crash in
## one group is recorded rather than taking the rest of the run with it.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock
var town: Town
var world: VoxelWorld
var village: Village

# kind: what the player is doing, NOT what should happen.
# hard: must be answered. soft: a plausible shrug counts.
const CASES := [
	# --- nonsense: the first thing anyone types -------------------------
	{"kind": "nonsense", "say": "asdfghjkl", "hard": false,
		"why": "keyboard mash. anything but silence is fine"},
	{"kind": "nonsense", "say": "???", "hard": false,
		"why": "punctuation only"},
	{"kind": "nonsense", "say": "¯\\_(ツ)_/¯", "hard": false,
		"why": "emoticon, the oldest test in the book"},
	{"kind": "nonsense", "say": "flibbertigibbet the wombat", "hard": false,
		"why": "a real word that means nothing to a village"},

	# --- empty and whitespace: crash bait -------------------------------
	{"kind": "empty", "say": "", "hard": false,
		"why": "empty submit. the classic null crash"},
	{"kind": "empty", "say": "   ", "hard": false,
		"why": "whitespace only, which is not the same as empty"},
	{"kind": "empty", "say": "?!.", "hard": false,
		"why": "punctuation that _clean() strips to nothing"},

	# --- hostile: players are rude to NPCs ------------------------------
	{"kind": "hostile", "say": "you are useless and I hate you", "hard": true,
		"why": "insult. a worker must answer, not crash or hang"},
	{"kind": "hostile", "say": "SHUT UP", "hard": true,
		"why": "all caps. _clean() lowercases, so check it still routes"},
	{"kind": "hostile", "say": "go away", "hard": true,
		"why": "a dismissal, which might be a standing order to leave"},
	{"kind": "hostile", "say": "I hate this village, burn it down", "hard": true,
		"why": "destructive and impossible. must refuse, not comply"},

	# --- impossible: real requests the game cannot do -------------------
	{"kind": "impossible", "say": "build a space elevator", "hard": true,
		"why": "far past the catalogue"},
	{"kind": "impossible", "say": "make it rain gold", "hard": true,
		"why": "not a thing the town can do"},
	{"kind": "impossible", "say": "give Mira a sword", "hard": true,
		"why": "a real name and an item that does not exist here"},
	{"kind": "impossible", "say": "build a castle with a moat and a drawbridge",
		"hard": true, "why": "plausible in a game, not in this one"},

	# --- repetition: players repeat themselves ---------------------------
	{"kind": "repeat", "say": "build a bakery", "hard": true, "times": 3,
		"why": "the same order three times. must not corrupt the plot queue"},

	# --- volume: long input --------------------------------------------
	{"kind": "long", "hard": true,
		"say": "I would like it if you could perhaps build me a small bakery "
			+ "facing the square with a big window and a thatch roof and a door "
			+ "that faces the street please and thank you very much indeed",
		"why": "a rambling real sentence, 240 characters"},

	# --- rapid: two people, same moment ---------------------------------
	{"kind": "rapid", "say": "build a bakery", "hard": true, "all": true,
		"why": "every worker told the same order at once. the plot queue must "
			+ "not hand the same plot to two people"},
	{"kind": "rapid", "say": "stand at the well", "hard": true, "all": true,
		"why": "everyone told to stand in one place at once"},
]

var _cases: Array = []
var _i := -1
var _wait := 0.0
var _timeout := 0.0
var _settle := 0.0
var _busy := false
var _t0 := 0.0
var _saw: Dictionary = {}
var _results: Array[Dictionary] = []
var _fails: Array[String] = []
var _errors: Array[String] = []
var _say := ""


func begin(say: String = "") -> void:
	_say = say
	if say != "":
		_cases = [{"kind": "adhoc", "say": say, "hard": true,
			"why": "one sentence of your own"}]
	else:
		_cases = CASES.duplicate(true)
	set_process(true)


func _ready() -> void:
	if dispatch != null:
		dispatch.spoke.connect(_on_spoke)
		dispatch.plan_accepted.connect(_on_plan)
		dispatch.refused.connect(_on_refused)
		dispatch.short_of.connect(_on_short)


func _process(delta: float) -> void:
	if _i < 0:
		# Wait for the town. Same reason as TaskTest: an order given before the
		# crew exists is dropped and every case reads as silence.
		if world != null and world.busy() and _wait < 30.0:
			_wait += delta
			return
		if crew == null or crew.hired().is_empty():
			_wait += delta
			if _wait > 30.0:
				_record(false, "the world never finished loading")
				_report()
			return
		_i = 0
		if clock != null:
			clock.speed = 90.0
		print("[player] provider: %s" % (dispatch.describe_ai()
			if dispatch != null else "none"))
		_start_case()
		return
	if _settle > 0.0:
		_settle -= delta
		if _settle <= 0.0:
			_finish_case()
		return
	if not _busy:
		return
	_timeout += delta
	if _timeout > 50.0:
		_saw["timeout"] = true
		_finish_case()


func _start_case() -> void:
	var c: Dictionary = _cases[_i]
	_timeout = 0.0
	_saw = {}
	_t0 = Time.get_ticks_msec()
	var say := str(c.get("say", ""))

	# --all: tell everybody at once. This is the case most likely to find a
	# real bug, because every worker reaches for the same plot at the same
	# moment and dispatcher keeps its queue in a plain Dictionary.
	if c.get("all", false):
		_busy = false
		var n := 0
		for w: Worker in crew.hired():
			if w.busy():
				continue
			dispatch.instruct(w, say)
			n += 1
		_saw["to"] = "%d workers" % n
		_saw["multi"] = true
		_settle = 3.0
		_busy = true
		return

	# times: the same order, repeated. --repeat is a single number, so the
	# case is rewritten into consecutive duplicates and _finish_case folds the
	# replies back into one result.
	var times := int(c.get("times", 1))
	_saw["repeat_left"] = times

	_busy = false
	var w: Worker = _pick()
	if w == null:
		_saw["no_worker"] = true
		_settle = 0.2
		return
	_saw["to"] = w.display_name()
	dispatch.instruct(w, say)
	_busy = true


func _pick() -> Worker:
	for wk: Worker in crew.hired():
		if not wk.busy():
			return wk
	return null


func _on_spoke(worker: Worker, line: String, kind: String) -> void:
	if _i < 0 or _settle > 0.0:
		return
	if _saw.has("to") and worker.display_name() != _saw["to"] \
			and not _saw.get("multi", false):
		return
	_saw["replies"] = int(_saw.get("replies", 0)) + 1
	_saw["line"] = line
	_settle = 0.7


func _on_plan(worker: Worker, _a: Array) -> void:
	if _i < 0 or _settle > 0.0:
		return
	if _saw.has("to") and worker.display_name() != _saw["to"] \
			and not _saw.get("multi", false):
		return
	_saw["plan"] = true
	_settle = 0.7


func _on_refused(worker: Worker, err: Dictionary) -> void:
	if _i < 0 or _settle > 0.0:
		return
	_saw["refused"] = true
	_saw["why"] = str(err.get("question", err.get("why",
		err.get("code", "refused"))))
	_settle = 0.7


func _on_short(worker: Worker, _m: Dictionary) -> void:
	_saw["short"] = true


## A repeat case sends the order again each time a reply lands, so the third
## reply is the one that matters: the same plot asked for three times.
func _finish_case() -> void:
	var c: Dictionary = _cases[_i]
	var left := int(_saw.get("repeat_left", 1)) - 1
	if left > 0 and not _saw.get("multi", false):
		_saw["repeat_left"] = left
		_settle = 0.4
		var w: Worker = _pick()
		if w != null:
			_saw["to"] = w.display_name()
			dispatch.instruct(w, str(c.get("say", "")))
			_timeout = 0.0
		return

	var took := float(Time.get_ticks_msec() - _t0) / 1000.0
	var answered: bool = _saw.has("replies") or _saw.has("plan") or _saw.has("refused")
	# The rule: silence is a failure for anything marked hard, a shrug is not
	# required for the rest, and a crash anywhere is a failure always.
	var ok := answered or not bool(c.get("hard", false))
	_record(ok, "" if answered else "no reply at all", took, c)

	_i += 1
	if _i < _cases.size():
		_settle = 0.5
	else:
		_report()


func _record(ok: bool, why: String, secs := 0.0, c: Dictionary = {}) -> void:
	# Sliced into a local: GDScript will not subscript a function call's
	# result, so str(...)[:120] is a parse error.
	var line := str(_saw.get("line", ""))
	if line.length() > 120:
		line = line.substr(0, 120)
	var rec := {
		"kind": c.get("kind", "adhoc"), "say": c.get("say", ""),
		"ok": ok, "why": c.get("why", why), "seconds": secs,
		"to": _saw.get("to", ""), "line": line,
		"replies": int(_saw.get("replies", 0)),
		"hard": bool(c.get("hard", false)),
		"refused": _saw.has("refused"), "plan": _saw.has("plan"),
	}
	_results.append(rec)
	var tag := "ok  " if ok else "FAIL"
	var say_txt := str(rec["say"])
	if say_txt.length() > 44:
		say_txt = say_txt.substr(0, 44)
	print("[player] %s %-10s %-46s %5.1fs %s" % [
		tag, rec["kind"], say_txt, secs,
		(rec["line"] if rec["line"] != "" else (why or "(silent)"))])
	if not ok:
		_fails.append("%s: %s" % [rec["kind"], rec["say"]])


func _report() -> void:
	var by_kind := {}
	for r: Dictionary in _results:
		var d: Dictionary = by_kind.get(r["kind"], {"n": 0, "ok": 0})
		d["n"] = int(d["n"]) + 1
		d["ok"] = int(d["ok"]) + (1 if r["ok"] else 0)
		by_kind[r["kind"]] = d
	print("[player] ==== by kind ====")
	for k: String in by_kind:
		var d: Dictionary = by_kind[k]
		print("[player]   %-10s %d/%d" % [k, int(d["ok"]), int(d["n"])])
	var ok := _results.size() - _fails.size()
	print("[player] ==== %d/%d answered ====" % [ok, _results.size()])
	for f: String in _fails:
		print("[player] FAIL: %s" % f)
	print("[player] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
	var out := FileAccess.open("user://player_results.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"results": _results}))
		out.close()
		print("[player] wrote user://player_results.json")
	get_tree().quit(1 if not _fails.is_empty() else 0)
