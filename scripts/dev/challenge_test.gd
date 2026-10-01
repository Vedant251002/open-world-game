extends Node
class_name ChallengeTest
## Weekly challenge and postcard: seed determinism, ISO weeks, scoring, a
## whole run against the live clock/town/dispatcher, the leaderboard and the
## save round-trip.
##
##   godot4 --headless --path . -- --challengetest

var clock: GameClock
var town: Town
var dispatch: Dispatcher
var realm: Realm
var crew: Crew

var _fails: Array[String] = []
var _n := 0


func _check(ok: bool, what: String) -> void:
	_n += 1
	if not ok:
		_fails.append(what)
		printerr("[challenge]   FAIL: %s" % what)


func run() -> int:
	_weeks()
	_seeds()
	_scoring()
	_postcard()
	_run_success()
	_run_failures()
	_leaderboard()
	_snapshot()
	print("[challenge] %d checks, %d failed" % [_n, _fails.size()])
	return 0 if _fails.is_empty() else 1


func _weeks() -> void:
	# [year, month, day, godot weekday (0 = Sunday), expected year, expected week]
	for c: Array in [[2026, 10, 1, 4, 2026, 40], [2021, 1, 3, 0, 2020, 53],
			[2024, 12, 30, 1, 2025, 1], [2020, 12, 31, 4, 2020, 53],
			[2026, 1, 1, 4, 2026, 1], [2018, 12, 31, 1, 2019, 1],
			[2023, 1, 1, 0, 2022, 52], [2026, 12, 28, 1, 2026, 53]]:
		var w := Challenge.iso_week(c[0], c[1], c[2], c[3])
		_check(int(w["year"]) == c[4] and int(w["week"]) == c[5],
			"ISO week of %d-%d-%d is %d/%d, got %s" % [c[0], c[1], c[2], c[4], c[5], str(w)])
	# And through unix time: 2026-10-01 12:00 UTC.
	var u := Challenge.iso_week_from_unix(1790856000.0)
	_check(int(u["week"]) == 40 and int(u["year"]) == 2026, "unix 2026-10-01 is week 40: %s" % str(u))


func _seeds() -> void:
	var a := Challenge.for_week(2026, 40)
	var b := Challenge.for_week(2026, 40)
	_check(a == b, "the same week gives the same challenge")
	_check(Challenge.for_week(2026, 41)["world_seed"] != a["world_seed"]
		or Challenge.for_week(2026, 41)["id"] != a["id"], "another week differs")
	var ids := {}
	var seeds := {}
	for wk in range(1, 53):
		var s := Challenge.for_week(2026, wk)
		ids[s["id"]] = true
		seeds[s["world_seed"]] = true
		_check(int(s["target"]) > 0 and int(s["deadline"]) >= 6, "week %d has a sane goal: %s" % [wk, str(s)])
		_check(int(s["world_seed"]) >= 0, "world seed is non-negative")
		if str(s["kind"]) == "buildings":
			_check(int(s["max_orders"]) == 3 * int(s["target"]), "3 orders per building")
		else:
			_check(int(s["max_orders"]) == 0, "no order cap for %s" % s["id"])
	_check(ids.size() == Challenge.GOALS.size(), "a year of weeks uses every goal (%d)" % ids.size())
	_check(seeds.size() >= 50, "world seeds are distinct (%d of 52)" % seeds.size())
	print("[challenge] week 40: %s (world seed %d)" % [a["text"], a["world_seed"]])


func _scoring() -> void:
	_check(Challenge.score(false, 3, 3) == 0, "no points for an unfinished run")
	_check(Challenge.score(true, 4, 10) > Challenge.score(true, 5, 10), "fewer days score more")
	_check(Challenge.score(true, 5, 10) > Challenge.score(true, 5, 14), "fewer orders score more")
	_check(Challenge.score(true, 5, 14) == 532, "points for 5 days / 14 orders: %d" % Challenge.score(true, 5, 14))
	_check(Challenge.score(true, 99, 99) >= 50, "points never go below the floor")
	var spec := {"week": 40, "kind": "buildings", "target": 6, "deadline": 8, "per_order": 3,
		"max_orders": 18}
	var line := Challenge.share_line(spec, true, 5, 14, 6)
	_check(line == "DELEGATE weekly #40 — 6 buildings in 5 days, 14 orders", "share line: %s" % line)
	_check(Challenge.share_line(spec, true, 1, 1, 6) == "DELEGATE weekly #40 — 6 buildings in 1 day, 1 order",
		"singular share line")
	var fail := Challenge.share_line(spec, false, 8, 18, 4)
	_check(fail == "DELEGATE weekly #40 — 4 / 6 built by day 8, 18 orders (not finished)",
		"failed share line: %s" % fail)


func _postcard() -> void:
	var st := {"name": "Hollowmere", "day": 9, "buildings": 7, "people": 12,
		"chronicle": "A wedding was held at the tavern."}
	for v in 4:
		var t := Postcard.offline(st, v)
		_check(t.find("Hollowmere") >= 0 or t.find("day 9") >= 0 or t.find("Day 9") >= 0,
			"caption %d names the place or day: %s" % [v, t])
		_check(t.find("7") >= 0 and t.find("12") >= 0, "caption %d has the numbers: %s" % [v, t])
		_check(t.ends_with("tavern."), "caption %d ends with the chronicle line: %s" % [v, t])
	_check(Postcard.offline(st, 2) == Postcard.offline(st, 2), "captions are deterministic")
	var empty := Postcard.stats_for(null, null, null, null)
	_check(str(empty["name"]) == "My Village", "default village name")
	_check(Postcard.clean("  \"Hello there.\"\n ").length() > 0, "model reply is tidied")


func _fresh() -> Challenge:
	var c := Challenge.new()
	add_child(c)
	c.bind(clock, town, dispatch, realm, crew)
	return c


func _dummy_building() -> void:
	var rec := {"id": -1, "archetype": "hut", "plot_id": -1, "street": "", "builder": "",
		"day": clock.day, "materials": {}, "patch": null}
	town.buildings.append(rec)
	town.building_added.emit(rec)


func _run_success() -> void:
	var c := _fresh()
	var day0 := clock.day
	var spec := {"year": 2026, "week": 40, "id": "build", "kind": "buildings", "target": 2,
		"deadline": day0 + 5, "max_orders": 6, "per_order": 3, "world_seed": 1}
	spec["text"] = Challenge.goal_text(spec)
	Challenge.scores_path = "user://_challenge_test_scores.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Challenge.scores_path))
	c.begin(spec)
	_check(c.active and not c.done and c.orders == 0, "a run begins active")
	for i in 3:
		dispatch.plan_accepted.emit(crew.workers[0], [])
	_check(c.orders == 3, "orders are counted from accepted plans (%d)" % c.orders)
	clock.advance(24.0)
	_dummy_building()
	_check(not c.done and c.progress == 1, "one of two buildings is not done")
	_dummy_building()
	_check(c.done and c.success, "two buildings finishes it")
	_check(c.days_taken() == 2, "days taken %d" % c.days_taken())
	var res := c.result()
	_check(int(res["orders"]) == 3 and int(res["score"]) == Challenge.score(true, 2, 3), "result carries the score")
	_check(Challenge.scores().size() == 1, "the finished run is on the leaderboard")
	# Nothing after the end changes it.
	dispatch.plan_accepted.emit(crew.workers[0], [])
	_check(c.orders == 3, "orders stop counting once finished")
	c.queue_free()
	town.buildings.resize(maxi(0, town.buildings.size() - 2))


func _run_failures() -> void:
	# Over the order budget.
	var c := _fresh()
	var spec := {"year": 2026, "week": 41, "id": "build", "kind": "buildings", "target": 5,
		"deadline": clock.day + 6, "max_orders": 2, "per_order": 3, "world_seed": 1}
	spec["text"] = Challenge.goal_text(spec)
	c.begin(spec)
	for i in 3:
		dispatch.plan_accepted.emit(crew.workers[0], [])
	_check(c.done and not c.success and c.reason == "out of orders", "too many orders fails the run")
	c.queue_free()
	# Out of days.
	var d := _fresh()
	var spec2 := {"year": 2026, "week": 42, "id": "rank", "kind": "tier", "target": 9,
		"deadline": clock.day + 1, "max_orders": 0, "per_order": 0, "world_seed": 1}
	spec2["text"] = Challenge.goal_text(spec2)
	d.begin(spec2)
	_check(d.active and not d.done, "a rank run is open")
	clock.advance(24.0 * 3.0)
	_check(d.done and not d.success and d.reason == "out of days", "the deadline fails the run")
	_check(Challenge.score(d.success, d.days_taken(), d.orders) == 0, "a failed run scores nothing")
	d.queue_free()


func _leaderboard() -> void:
	for e: Array in [[41, true, 6, 20, 300], [42, true, 4, 9, 700], [43, false, 8, 12, 0]]:
		Challenge.add_score({"week": e[0], "success": e[1], "days": e[2], "orders": e[3],
			"score": e[4], "progress": 1, "target": 4, "when": "2026-10-0%d" % (e[0] - 40)})
	var top := Challenge.leaderboard(10)
	_check(top.size() >= 4, "the board holds every attempt (%d)" % top.size())
	_check(int(top[0]["score"]) >= int(top[1]["score"]) and int(top[1]["score"]) >= int(top[2]["score"]), "best first")
	_check(Challenge.leaderboard(10, 43).size() == 1, "filter by week")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Challenge.scores_path))


func _snapshot() -> void:
	var c := _fresh()
	var spec := Challenge.for_week(2026, 40)
	c.begin(spec)
	dispatch.plan_accepted.emit(crew.workers[0], [])
	var snap := c.snapshot()
	var d := Challenge.new()
	d.restore(snap)
	_check(d.spec == c.spec and d.orders == 1 and d.active and d.start_day == c.start_day,
		"a run survives a save round-trip")
	_check(Challenge.new().snapshot().is_empty(), "no run, no snapshot key")
	c.queue_free()
	d.free()
