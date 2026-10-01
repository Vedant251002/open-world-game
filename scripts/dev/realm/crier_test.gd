extends Node
## Headless test for the Village Crier and the daily requests.
## Run with:  godot --headless --path . -- --realmtest=crier --nosave

var world: VoxelWorld
var town: Town
var clock: GameClock
var crew: Crew
var realm: Realm
var hud: Hud

var _fails := 0
var _checks := 0


func begin() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run()
	print("[crier_test] %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("[crier_test] FAIL: %s" % what)
	else:
		print("[crier_test] ok: %s" % what)


func _day() -> void:
	clock.advance(24.0)


func _run() -> void:
	var main := get_parent()
	var crier: Crier = main.get("crier")
	var req: Requests = main.get("requests")
	_ok(crier != null and req != null, "main raised the crier and requests")
	if crier == null or req == null:
		return
	_ok(crier.issues.size() >= 1, "a first issue exists at once")

	# --- the paper ---------------------------------------------------------
	realm.note("raid", "Raiders came out of the hills and were beaten off at the north gate.")
	var heads: Array[String] = []
	var gossips: Array[String] = []
	var notices: Array[String] = []
	var n0 := crier.issues.size()
	for i in 8:
		if i == 3:
			realm.note("birth", "A daughter was born to Ada.")
		_day()
		var iss := crier.latest()
		heads.append(str(iss["headline"]))
		gossips.append(str(iss["gossip"]))
		notices.append(str(iss["notice"]))
		_ok(str(iss["headline"]) != "" and str(iss["lede"]) != "" and str(iss["gossip"]) != ""
			and str(iss["forecast"]) != "" and str(iss["notice"]) != "",
			"issue day %d has every section" % int(iss["day"]))
		_ok((iss["items"] as Array).size() >= 3,
			"issue day %d has 3+ items (%d)" % [int(iss["day"]), (iss["items"] as Array).size()])
	_ok(crier.issues.size() == n0 + 8, "one issue per day")
	var uniq := {}
	for h in heads:
		uniq[h] = true
	_ok(uniq.size() >= 4, "headlines vary over a week (%d distinct)" % uniq.size())
	var rep := false
	for i in range(1, 8):
		if heads[i] == heads[i - 1] or gossips[i] == gossips[i - 1] or notices[i] == notices[i - 1]:
			rep = true
	_ok(not rep, "no headline, gossip or notice repeats day to day")
	var lead := str(crier.issues[n0]["headline"])
	var raid_words := ["RAID", "GATE", "TROUBLE", "GROUND", "STEEL", "BLADES"]
	var hit := false
	for wd: String in raid_words:
		if lead.find(wd) >= 0:
			hit = true
	_ok(hit, "the raid made the front page: %s" % lead)
	print("[crier_test] sample: ", JSON.stringify(crier.latest(), "  "))
	_ok(crier.unread_count() > 0, "unread issues are counted")
	crier.mark_read(crier.latest())

	# an LLM-style rewrite
	var iss2 := crier.latest()
	var okr := crier.apply_rewrite(iss2,
		"HEADLINE: Big Day\nLEDE: Things happened.\nITEM: One.\nITEM: Two.\nGOSSIP: Hush.\nFORECAST: Rain.\nNOTICE: Wanted: tea.")
	_ok(okr and str(iss2["headline"]) == "BIG DAY" and str(iss2["source"]) == "llm", "a rewrite is folded in")
	_ok(not crier.apply_rewrite(iss2, "garbage"), "garbage is ignored")

	# save round trip
	var snap := crier.snapshot()
	var c2 := Crier.new()
	add_child(c2)
	c2.restore(snap)
	_ok(c2.issues.size() == crier.issues.size() and str(c2.latest()["headline"]) == str(crier.latest()["headline"]),
		"the crier saves and restores its back issues")
	c2.queue_free()

	# --- requests -----------------------------------------------------------
	req.active.clear()
	var made := req.generate(clock.day + 20)
	_ok(made.size() >= 1 and made.size() <= 3, "1-3 requests generated (%d)" % made.size())
	for r: Dictionary in made:
		_ok(str(r["text"]) != "" and str(r["say"]) != "" and int(r["reward"]) > 0,
			"request '%s' has text, voice and reward" % str(r["text"]))
		print("[crier_test]   ", r["name"], ": ", r["say"])

	# fulfil each by changing real state
	var coins0 := town.coins
	for r: Dictionary in req.active.duplicate():
		var w := crew.get_worker(str(r["who"]))
		var morale0 := float(w.memory.disposition["morale"])
		match str(r["kind"]):
			"build", "home":
				var arch := str(r["arch"]) if str(r["kind"]) == "build" else "cottage"
				var rec := {"id": 9000 + int(r["id"]), "archetype": arch, "street": "Test Lane",
					"builder": "tobias", "day": clock.day}
				town.buildings.append(rec)
				town.building_added.emit(rec)
			"stock":
				town.stock[str(r["item"])] = int(r["n"]) + 1
			"hire":
				var extra := crew.citizens()
				if not extra.is_empty():
					extra[0].hired = true
		req.check()
		_ok(not (r in req.active), "request '%s' is fulfilled by real state" % str(r["text"]))
		_ok(float(w.memory.disposition["morale"]) >= morale0, "asker's morale did not fall")
	_ok(town.coins > coins0, "fulfilled requests paid coins")
	_ok(req.history.size() >= 1 and str(req.history[req.history.size() - 1]["status"]) == "done",
		"history records it")

	# expiry
	var made2 := req.generate(clock.day + 30)
	_ok(not made2.is_empty(), "more requests generated")
	var before := req.active.size()
	var coins1 := town.coins
	var due := 0
	for r: Dictionary in req.active:
		due = maxi(due, int(r["due"]))
		if str(r["kind"]) == "stock":
			town.stock[str(r["item"])] = 0
	clock.day = due + 1
	req.on_day(clock.day)
	var lapsed := 0
	for h: Dictionary in req.history:
		if str(h["status"]) == "expired":
			lapsed += 1
	_ok(lapsed >= 1 and town.coins == coins1, "unmet requests expire without pay (%d of %d)" % [lapsed, before])

	# phrasing + save
	var ms := req.generate(clock.day + 40)
	if not ms.is_empty():
		var id := int(ms[0]["id"])
		_ok(req.apply_phrasing("%d | Mind the roof, friend." % id) == 1
			and str(ms[0]["say"]) == "Mind the roof, friend.", "LLM phrasing applies")
		var rsnap := req.snapshot()
		var r2 := Requests.new()
		add_child(r2)
		r2.restore(rsnap)
		_ok(r2.active.size() == req.active.size(), "requests save and restore")
		r2.queue_free()
