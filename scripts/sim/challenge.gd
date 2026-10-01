extends Node
class_name Challenge
## The weekly challenge: the same village and the same goal for everybody who
## plays this ISO week, scored on how fast and how few orders.
##
## Everything that decides the week is a pure function of (ISO year, ISO week),
## so two players — or two machines — get the same world seed and the same
## goal without talking to anybody: see for_week(). A run is the player's
## attempt at it. Runs play in a world of their own, with their own save slot,
## so a challenge never touches the town you have been looking after; the
## static `mode` and request()/leave() below are how the game switches between
## the two (main.gd reloads the scene, and boot() points the save at the right
## file).
##
## Score is "days taken / orders given" in the sense that those are the two
## numbers that matter and both are shown and shared; the points figure used
## to rank the local leaderboard is score() — lower of either is better.

signal changed
signal finished(result: Dictionary)

## What a week can ask. `lo`/`hi`/`step` pick the target; `dl` the deadline day.
const GOALS := [
	{"id": "fed", "kind": "fed", "lo": 8, "hi": 14, "step": 2, "dl_lo": 7, "dl_hi": 9},
	{"id": "build", "kind": "buildings", "lo": 4, "hi": 6, "step": 1, "dl_lo": 6, "dl_hi": 9,
		"per_order": 3},
	{"id": "rank", "kind": "tier", "lo": 2, "hi": 3, "step": 1, "dl_lo": 0, "dl_hi": 1},
]
const RANKS := ["Hamlet", "Village", "Town", "City", "Capital"]
## A person counts as fed at this level of the Population "fed" need.
const FED_AT := 0.6

const DEFAULT_SAVE := "user://save/town.save"
const CHALLENGE_SAVE := "user://save/challenge.save"
static var scores_path := "user://challenge_scores.json"
static var meta_path := "user://save/challenge_meta.json"

# ------------------------------------------------------------ process state
## True while this process is playing the challenge world (set before the scene
## is reloaded, read by boot()).
static var mode := false
## True when the next boot must discard any earlier challenge save.
static var new_attempt := false
## For tests and `--week=N`: pretend it is this ISO week of the current year.
static var week_override := 0
## Set once a world switch has happened: the reload goes straight to the village.
static var skip_title := false
static var _flag_used := false

# ---------------------------------------------------------------- run state
var clock: GameClock
var town: Town
var dispatch: Dispatcher
var realm: Realm
var crew: Crew

var spec: Dictionary = {}
var active := false
var done := false
var success := false
var reason := ""
var start_day := 1
var end_day := 0
var orders := 0
var baseline := 0
var progress := 0
var recorded := false


# ======================================================================== week

## 0 = Sunday .. 6 = Saturday, as Time reports it, to ISO 1 = Monday .. 7.
static func _iso_weekday(godot_weekday: int) -> int:
	return (godot_weekday + 6) % 7 + 1


static func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func _day_of_year(y: int, m: int, d: int) -> int:
	var cum := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	var n: int = int(cum[m - 1]) + d
	if m > 2 and _is_leap(y):
		n += 1
	return n


## Weeks in an ISO year: 53 when it starts on a Thursday, or a leap year that
## starts on a Wednesday — expressed the usual way through p(year).
static func weeks_in_year(y: int) -> int:
	var p := func(yy: int) -> int:
		return (yy + yy / 4 - yy / 100 + yy / 400) % 7
	return 53 if int(p.call(y)) == 4 or int(p.call(y - 1)) == 3 else 52


## {year, week} of an ISO date. `godot_weekday` is Time's: 0 = Sunday.
static func iso_week(y: int, m: int, d: int, godot_weekday: int) -> Dictionary:
	var wd := _iso_weekday(godot_weekday)
	var week := (_day_of_year(y, m, d) - wd + 10) / 7
	var year := y
	if week < 1:
		year = y - 1
		week = weeks_in_year(year)
	elif week > weeks_in_year(y):
		year = y + 1
		week = 1
	return {"year": year, "week": week}


static func iso_week_from_unix(unix: float) -> Dictionary:
	var dt := Time.get_date_dict_from_unix_time(int(unix))
	return iso_week(int(dt["year"]), int(dt["month"]), int(dt["day"]), int(dt["weekday"]))


## The week being played: today's, unless a test or --week=N says otherwise.
static func current_week() -> Dictionary:
	var w := iso_week_from_unix(Time.get_unix_time_from_system())
	if week_override > 0:
		w["week"] = week_override
	return w


## The whole of a week's challenge, from nothing but its number. Same input,
## same output, on every machine.
static func for_week(year: int, week: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (year * 100 + week) * 2654435761 + 97
	var g: Dictionary = GOALS[rng.randi() % GOALS.size()]
	var steps := (int(g["hi"]) - int(g["lo"])) / int(g["step"]) + 1
	var target := int(g["lo"]) + (rng.randi() % steps) * int(g["step"])
	var deadline := int(g["dl_lo"]) + rng.randi() % (int(g["dl_hi"]) - int(g["dl_lo"]) + 1)
	if str(g["kind"]) == "tier":
		deadline += 4 + target * 2          # rank 2: day 8-9, rank 3: day 10-11
	var s := {
		"year": year, "week": week, "id": g["id"], "kind": g["kind"],
		"target": target, "deadline": deadline,
		"max_orders": target * int(g.get("per_order", 0)),
		"per_order": int(g.get("per_order", 0)),
		"world_seed": int(rng.randi() & 0x7FFFFFFF),
	}
	s["text"] = goal_text(s)
	return s


static func rank_name(tier: int) -> String:
	return RANKS[clampi(tier - 1, 0, RANKS.size() - 1)]


static func goal_text(s: Dictionary) -> String:
	match str(s["kind"]):
		"fed":
			return "Feed %d people by day %d" % [int(s["target"]), int(s["deadline"])]
		"buildings":
			return "Build %d buildings with only %d orders each, by day %d" % [
				int(s["target"]), int(s["per_order"]), int(s["deadline"])]
		"tier":
			return "Reach %s rank by day %d" % [rank_name(int(s["target"])), int(s["deadline"])]
	return "?"


## What the target is, as a noun phrase: "6 buildings", "14 people fed".
static func target_phrase(s: Dictionary) -> String:
	match str(s["kind"]):
		"fed":
			return "%d people fed" % int(s["target"])
		"buildings":
			return "%d buildings" % int(s["target"])
		"tier":
			return "%s rank" % rank_name(int(s["target"]))
	return "?"


## What the player is shown beside the bar.
static func progress_phrase(s: Dictionary, have: int) -> String:
	match str(s["kind"]):
		"fed":
			return "%d / %d fed" % [have, int(s["target"])]
		"buildings":
			return "%d / %d built" % [have, int(s["target"])]
		"tier":
			return "rank %s (%d / %d)" % [rank_name(have), have, int(s["target"])]
	return "?"


## Points for the local leaderboard. Zero for a run that did not finish; for
## one that did, fewer days and fewer orders each cost points.
static func score(did_succeed: bool, days: int, order_count: int) -> int:
	if not did_succeed:
		return 0
	return maxi(50, 1000 - 60 * days - 12 * order_count)


## "DELEGATE weekly #40 — 6 buildings in 5 days, 14 orders"
static func share_line(s: Dictionary, did_succeed: bool, days: int, order_count: int,
		have: int) -> String:
	var head := "DELEGATE weekly #%d" % int(s["week"])
	if did_succeed:
		return "%s — %s in %d %s, %d %s" % [head, target_phrase(s), days,
			"day" if days == 1 else "days", order_count,
			"order" if order_count == 1 else "orders"]
	return "%s — %s by day %d, %d %s (not finished)" % [head,
		progress_phrase(s, have), int(s["deadline"]), order_count,
		"order" if order_count == 1 else "orders"]


# ====================================================================== flow

## Reads the launch flags and points the save at the right slot. Called by
## main.gd before the save is read, on every boot (a reload included).
static func boot(args: PackedStringArray) -> void:
	for a: String in args:
		if a.begins_with("--week="):
			week_override = int(a.substr(7))
	if not _flag_used and ("--challenge" in args):
		_flag_used = true
		var w := current_week()
		request(not saved_run_matches(for_week(int(w["year"]), int(w["week"]))))
	if mode:
		SaveGame.path = CHALLENGE_SAVE
		if new_attempt:
			SaveGame.erase()
			new_attempt = false
	elif SaveGame.path == CHALLENGE_SAVE:
		SaveGame.path = DEFAULT_SAVE


## Asks the next boot to be a challenge world. The caller reloads the scene.
static func request(fresh: bool) -> void:
	mode = true
	new_attempt = fresh
	skip_title = true


## Asks the next boot to be your own village again.
static func leave() -> void:
	mode = false
	new_attempt = false
	skip_title = true


static func write_meta(c: Challenge) -> void:
	if c == null or c.spec.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://save"))
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"year": c.spec["year"], "week": c.spec["week"],
		"done": c.done}))
	f.close()


## Whether an unfinished run of this very week sits in the challenge slot.
static func saved_run_matches(s: Dictionary) -> bool:
	if not FileAccess.file_exists(CHALLENGE_SAVE) or not FileAccess.file_exists(meta_path):
		return false
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	return int(d.get("year", 0)) == int(s["year"]) and int(d.get("week", 0)) == int(s["week"]) \
		and not bool(d.get("done", false))


# ============================================================== leaderboard

static func scores() -> Array:
	if not FileAccess.file_exists(scores_path):
		return []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(scores_path))
	return (v as Array) if v is Array else []


static func add_score(entry: Dictionary) -> void:
	var all := scores()
	all.append(entry)
	if all.size() > 60:
		all = all.slice(all.size() - 60)
	var f := FileAccess.open(scores_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all))
		f.close()


## Best first: points, then the newest. Optionally only one week's.
static func leaderboard(limit: int = 8, week: int = -1) -> Array:
	var rows: Array = []
	for e: Variant in scores():
		if e is Dictionary and (week < 0 or int((e as Dictionary).get("week", -1)) == week):
			rows.append(e)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return str(a.get("when", "")) > str(b.get("when", "")))
	return rows.slice(0, limit)


# ================================================================= the run

func bind(c: GameClock, t: Town, d: Dispatcher, r: Realm, cr: Crew) -> void:
	clock = c
	town = t
	dispatch = d
	realm = r
	crew = cr
	clock.hour_passed.connect(func(_h: float, _d: int) -> void: evaluate())
	clock.day_passed.connect(func(_d: int) -> void: evaluate())
	town.building_added.connect(func(_r: Dictionary) -> void: evaluate())
	town.tier_changed.connect(func(_t: int) -> void: evaluate())
	dispatch.plan_accepted.connect(_on_order)


## Starts a fresh attempt at `s` from this moment in the world.
func begin(s: Dictionary) -> void:
	spec = s
	active = true
	done = false
	success = false
	reason = ""
	recorded = false
	orders = 0
	start_day = clock.day if clock != null else 1
	end_day = 0
	baseline = town.buildings.size() if town != null else 0
	progress = 0
	evaluate()


func _on_order(_w: Worker, _assumptions: Array) -> void:
	if not active or done:
		return
	orders += 1
	evaluate()


## How far along it is, as the goal's own number.
func measure() -> int:
	match str(spec.get("kind", "")):
		"fed":
			if realm != null and realm.population != null:
				var n := 0
				for c: Population.Citizen in realm.population.alive():
					if float(c.needs["fed"]) >= FED_AT:
						n += 1
				return n
			return 0
		"buildings":
			return maxi(0, town.buildings.size() - baseline) if town != null else 0
		"tier":
			return town.tier if town != null else 1
	return 0


func evaluate() -> void:
	if not active or done:
		return
	progress = measure()
	var day := clock.day if clock != null else 1
	if progress >= int(spec["target"]):
		_finish(true, "")
	elif int(spec["max_orders"]) > 0 and orders > int(spec["max_orders"]):
		_finish(false, "out of orders")
	elif day > int(spec["deadline"]):
		_finish(false, "out of days")
	else:
		changed.emit()


func _finish(did_succeed: bool, why: String) -> void:
	done = true
	success = did_succeed
	reason = why
	end_day = clock.day if clock != null else start_day
	if not did_succeed:
		end_day = mini(end_day, int(spec["deadline"]))
	if not recorded:
		recorded = true
		add_score(result())
	changed.emit()
	finished.emit(result())


## Days the attempt ran, counting the day it started on as the first.
func days_taken() -> int:
	return maxi(1, (end_day if done else (clock.day if clock != null else start_day)) - start_day + 1)


func result() -> Dictionary:
	var days := days_taken()
	return {
		"year": int(spec["year"]), "week": int(spec["week"]), "goal": str(spec["text"]),
		"success": success, "days": days, "orders": orders, "progress": progress,
		"target": int(spec["target"]), "reason": reason,
		"score": score(success, days, orders),
		"when": Time.get_datetime_string_from_system(),
	}


func share_text() -> String:
	return share_line(spec, success, days_taken(), orders, progress)


## Copies the result: to the system clipboard, or on the web through the share
## sheet when the browser has one. Returns where it went.
static func share(text: String) -> String:
	if Platform.is_web() and Engine.has_singleton("JavaScriptBridge"):
		var js := "(function(t){ if (navigator.share) { navigator.share({text: t}).catch(function(){});" \
			+ " return 'shared'; } if (navigator.clipboard) { navigator.clipboard.writeText(t);" \
			+ " return 'copied'; } return 'none'; })(%s)" % JSON.stringify(text)
		var r: Variant = JavaScriptBridge.eval(js, true)
		if str(r) == "shared":
			return "shared"
		if str(r) == "copied":
			return "copied"
	DisplayServer.clipboard_set(text)
	return "copied"


# ============================================================== saving

func snapshot() -> Dictionary:
	if spec.is_empty():
		return {}
	return {"spec": spec.duplicate(), "active": active, "done": done, "success": success,
		"reason": reason, "start_day": start_day, "end_day": end_day, "orders": orders,
		"baseline": baseline, "progress": progress, "recorded": recorded}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	spec = (d.get("spec", {}) as Dictionary).duplicate()
	if spec.is_empty():
		return
	active = bool(d.get("active", false))
	done = bool(d.get("done", false))
	success = bool(d.get("success", false))
	reason = str(d.get("reason", ""))
	start_day = int(d.get("start_day", 1))
	end_day = int(d.get("end_day", 0))
	orders = int(d.get("orders", 0))
	baseline = int(d.get("baseline", 0))
	progress = int(d.get("progress", 0))
	recorded = bool(d.get("recorded", false))
	changed.emit()
