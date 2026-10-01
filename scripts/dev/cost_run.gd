extends Node
class_name CostRun
## A scripted first session, played through the real dispatcher, so the cost
## of each thing a player does can be read off the gateway's log.
##
## Point the game at _tools/mock_gateway.py (or a real gateway) and run:
##   godot4 --headless --path . -- --costrun --noquick \
##     --proxy=http://127.0.0.1:8787/v1/chat/completions
##
## Each step is one thing a player would actually do in their first half hour,
## said to the person they would say it to. Every step is stamped with the wall
## clock as it goes out and when it settles, and the stamps are written to
## user://cost_run.json, which _tools/token_report.py joins with the gateway's
## log by time to say which calls each step cost.

var dispatch: Dispatcher
var crew: Crew
var clock: GameClock

## who: a crew id, or "citizen:N" for the Nth person in the street.
## kind: what sort of thing a player is doing, for the report's groups.
const STEPS := [
	{"who": "mira", "say": "hello Mira", "kind": "chat"},
	{"who": "mira", "say": "what can you do?", "kind": "question"},
	{"who": "mira", "say": "how many coins do we have?", "kind": "question"},
	{"who": "tobias", "say": "build a small hut near the well", "kind": "build"},
	{"who": "tobias", "say": "what are you doing?", "kind": "question"},
	{"who": "ren", "say": "plant a wheat field", "kind": "order"},
	{"who": "mira", "say": "sell 20 timber", "kind": "order"},
	{"who": "tobias", "say": "no, I wanted a thatch roof", "kind": "correction"},
	{"who": "citizen:0", "say": "hi there, how are you?", "kind": "chat"},
	{"who": "citizen:0", "say": "hire you as a shepherd", "kind": "hire"},
	{"who": "citizen:0", "say": "bring 4 sheep", "kind": "order"},
	{"who": "citizen:1", "say": "hire you as a beekeeper: keeps hives and collects honey",
		"kind": "hire"},
	{"who": "tobias", "say": "build a big bakery facing the square", "kind": "build"},
	{"who": "mira", "say": "tell me about yourself", "kind": "chat"},
	{"who": "ren", "say": "every morning, bring in the harvest", "kind": "standing"},
	{"who": "mira", "say": "asdfgh", "kind": "nonsense"},
	{"who": "tobias", "say": "you are useless", "kind": "chat"},
	{"who": "tobias", "say": "build a spaceship", "kind": "refuse"},
	{"who": "mira", "say": "where is the bakery?", "kind": "question"},
	{"who": "citizen:2", "say": "hire you as a foreman", "kind": "hire"},
	{"who": "citizen:2", "say": "your goal is to get a farm going", "kind": "goal"},
	{"who": "", "say": "(a new day: morning jobs and the foreman's round)", "kind": "morning"},
]

const SETTLE := 3.0          ## quiet seconds after the last line before moving on
const STEP_LIMIT := 40.0

var _i := -1
var _t := 0.0
var _quiet := 0.0
var _armed := false
var _wait := 0.0
var _who: Worker = null
var _lines: Array[String] = []
var _log: Array[Dictionary] = []
var _citizens: Array[Worker] = []


func begin() -> void:
	crew.worker_spoke.connect(func(w: Worker, line: String, _k: String) -> void:
		if _i >= 0 and _i < STEPS.size():
			_lines.append("%s: %s" % [w.display_name(), line])
			_quiet = 0.0)
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if _wait > 8.0:
			_armed = true
			# Fixed at the start: hiring moves people out of citizens().
			_citizens = crew.citizens().duplicate()
			_next()
		return
	_t += delta
	_quiet += delta
	var busy := _who != null and is_instance_valid(_who) and _who.pondering != ""
	if (_quiet > SETTLE and not busy and _t > 1.0) or _t > STEP_LIMIT:
		_close()
		_next()


func _next() -> void:
	_i += 1
	if _i >= STEPS.size():
		_finish()
		return
	var s: Dictionary = STEPS[_i]
	_t = 0.0
	_quiet = 0.0
	_lines.clear()
	_log.append({"i": _i, "kind": s["kind"], "say": s["say"], "who": s["who"],
		"t0": Time.get_unix_time_from_system()})
	if str(s["kind"]) == "morning":
		_who = null
		clock.advance(24.0 - clock.hour + 6.5)
		return
	_who = _resolve(str(s["who"]))
	if _who == null:
		_log[-1]["skipped"] = "nobody to say it to"
		return
	print("[cost] %2d %-10s %-8s %s" % [_i, s["kind"], _who.display_name(), s["say"]])
	dispatch.instruct(_who, str(s["say"]))


func _close() -> void:
	var rec: Dictionary = _log[-1]
	rec["t1"] = Time.get_unix_time_from_system()
	rec["lines"] = _lines.duplicate()
	print("[cost]      -> %s" % (" | ".join(_lines) if not _lines.is_empty() else "(silence)"))


func _resolve(who: String) -> Worker:
	if who.begins_with("citizen:"):
		var n := int(who.substr(8))
		return _citizens[n] if n < _citizens.size() else null
	return crew.get_worker(who)


func _finish() -> void:
	var path := "user://cost_run.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_log, "  "))
	f.close()
	print("[cost] wrote %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
