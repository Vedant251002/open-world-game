extends Node
## Each crisis is forced, starts (alarm, banner, suggested order), is resolved by
## the order the banner suggests, and leaves an aftermath in the chronicle.
## Run with:  godot --headless --path . -- --realmtest=crisis --nosave --noquick

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var warfare: Warfare
var wildlife: Wildlife
var livestock: Livestock
var farm: Farm
var realm: Realm

var _wait := 0.0
var _fails: Array[String] = []


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy() and _wait < 15.0:
		_wait += delta
		return
	set_process(false)
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("[crisis] %s %s" % ["ok  " if ok else "FAIL", what])


func _hours(n: int) -> void:
	for i in n:
		clock.advance(1.0)


func _aftermaths() -> int:
	return realm.chronicle.of_kind("aftermath").size()


## How many crises of a kind have ended (the weather may start a stray one of
## another kind while the clock runs, so tests count their own kind).
func _ended(kind: String) -> int:
	var cr: Node = realm.system("Crisis")
	return int(cr.ended_count.get(kind, 0))


func _last_aftermath() -> String:
	return str(realm.chronicle.of_kind("aftermath").back()["text"])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var w: Worker = crew.workers[0]
	var cr: Node = realm.system("Crisis")
	var wx: Node = realm.system("Weather")
	var ev: Node = realm.system("Events")
	_check(cr != null and wx != null and ev != null, "crisis, weather, events loaded")
	if cr == null or wx == null or ev == null:
		_finish()
		return
	_check(not cr.any() and cr.banner().is_empty(), "quiet town: no banner")

	# Nothing befalls the town before day 3.
	for e: Dictionary in ev._events:
		if str(e["id"]) in ["fire", "wolves", "plague", "bandits", "storm"]:
			_check(int(e["min_day"]) >= 3, "%s waits for day 3 (min_day %d)" % [e["id"], int(e["min_day"])])

	await _fire(w, cr, wx)
	await _wolves(w, cr, ev)
	await _raid(w, cr)
	await _sickness(w, cr)
	await _famine(w, cr)
	await _storm(w, cr, wx)

	# The state survives a save.
	var snap := realm.snapshot()
	_check(snap.has("Crisis") and snap.has("Seasons"), "crisis and seasons are in the snapshot")
	cr.restore(snap["Crisis"])
	_check(int(cr.started_count.get("fire", 0)) >= 2, "counters survive a restore")
	_finish()


# ---------------------------------------------------------------------- fire

func _fire(w: Worker, cr: Node, wx: Node) -> void:
	var rec := realm.building("bakery")
	if rec.is_empty():
		rec = town.buildings[0]
	var name := str(rec["archetype"]).replace("_", " ")
	var before := _aftermaths()
	wx.force("clear")
	wx.ignite(rec, "the test")
	cr.scan()
	_check(cr.has("fire"), "fire crisis begins")
	var b: Dictionary = cr.banner()
	_check(str(b.get("title", "")).find("FIRE") >= 0 and str(b.get("tone", "")) == "alert", "banner: %s" % str(b.get("title", "")))
	_check(str(b.get("action", "")).find("buckets") >= 0, "banner suggests an order: %s" % str(b.get("action", "")))
	_check(str(b.get("status", "")).find("Nobody") >= 0, "status: %s" % str(b.get("status", "")))
	_check(realm.situation().find("CRISIS") >= 0, "the router is told: %s" % realm.situation().left(60))
	_check(not realm.answer(w, "what should we do?").is_empty(), "asked, they answer")

	# The player's order, as typed.
	_check(realm.handle(w, "everyone to the %s with buckets" % name), "order 'everyone to the %s with buckets' is understood" % name)
	await _frames(2)
	var line: Array = wx.fighters_of(wx.fires()[0])
	_check(line.size() >= 2, "%d on the bucket line" % line.size())
	var legs: Array = w.job_errand.get("legs", [])
	_check(legs.size() == 2, "they walk well-to-door (legs %d)" % legs.size())
	cr.scan()
	_check(str(cr.crisis_of("fire").get("status", "")).find("bucket line") >= 0, "status now: %s" % str(cr.crisis_of("fire").get("status", "")))
	var first_id := int(wx.fires()[0]["id"])
	var hours := 0
	while not wx.fires().is_empty() and hours < 24:
		clock.advance(1.0)
		hours += 1
		# The fire may jump next door; each new one wants its own bucket line.
		for f: Dictionary in wx.fires():
			if wx.fighters_of(f).is_empty():
				var other := str(f["rec"]["archetype"]).replace("_", " ")
				realm.handle(w, "everyone to the %s with buckets" % other)
	_check(wx.fires().is_empty(), "put out after %d hours" % hours)
	cr.scan()
	_check(not cr.has("fire"), "fire crisis ended")
	_check(_ended("fire") >= 1 and _aftermaths() > before, "aftermath recorded: %s" % _last_aftermath())
	var saved_report: Dictionary = (wx.fire_reports as Dictionary).get(first_id, {})
	_check(bool(saved_report["by_hand"]), "marked as put out by hand")
	var burnt_fought := float(saved_report["lost"])

	# The same fire left alone burns longer and takes more.
	var embers_before: int = wx.fire_reports.size()
	var rec2 := realm.building("hut") if not realm.building("hut").is_empty() else town.buildings[town.buildings.size() - 1]
	if rec2 == rec and town.buildings.size() > 1:
		rec2 = town.buildings[1]
	wx.ignite(rec2, "the test again")
	var second_id := int(wx.fires()[0]["id"])
	cr.scan()
	hours = 0
	while not wx.fires().is_empty() and hours < 30:
		clock.advance(1.0)
		hours += 1
	cr.scan()
	_check(wx.fires().is_empty(), "an unfought fire burns itself out in %d hours" % hours)
	var report2: Dictionary = (wx.fire_reports as Dictionary)[second_id]
	_check(not bool(report2["by_hand"]) and float(report2["lost"]) > burnt_fought,
		"unfought fire took more (%.0f%% vs %.0f%%)" % [float(report2["lost"]) * 100.0, burnt_fought * 100.0])
	_check(float(report2["lost"]) > 0.25, "and a real share of the building (%.0f%%)" % (float(report2["lost"]) * 100.0))
	_check(wx.fire_reports.size() >= embers_before + 1 and _aftermaths() >= before + 2, "second aftermath recorded")
	# Nothing left glowing.
	var glowing := 0
	var patch: VoxelPatch = rec2["patch"]
	for x in patch.size.x:
		for y in patch.size.y:
			for z in patch.size.z:
				if world.get_voxel(patch.origin + Vector3i(x, y, z)) == VoxelTypes.EMBER:
					glowing += 1
	_check(glowing == 0, "no embers left glowing (%d)" % glowing)
	# A crisis forced through the front door, put out with the plainest order.
	var ended0 := _ended("fire")
	_check(cr.trigger("fire"), "fire triggered through the crisis system (the event's own door)")
	_check(realm.handle(w, "put out the fire"), "order 'put out the fire' understood")
	hours = 0
	while not wx.fires().is_empty() and hours < 16:
		clock.advance(1.0)
		hours += 1
	cr.scan()
	_check(wx.fires().is_empty() and _ended("fire") > ended0, "plain 'put out the fire' puts it out (%d hours)" % hours)
	_check(realm.handle(w, "put out the fire"), "and with nothing burning the order is still understood")


# --------------------------------------------------------------------- wolves

func _wolves(w: Worker, cr: Node, ev: Node) -> void:
	var before := _aftermaths()
	_check(cr.trigger("wolves"), "wolves triggered")
	_check(cr.has("wolves"), "wolf crisis begins")
	var b: Dictionary = cr.crisis_of("wolves")
	_check(str(b.get("title", "")).find("WOLVES") >= 0, "banner: %s" % str(b.get("title", "")))
	_check(str(b.get("action", "")).find("hunt the wolves") >= 0, "suggested: %s" % str(b.get("action", "")))
	_check(realm.handle(w, "hunt the wolves"), "order understood")
	_check(ev.pending.is_empty(), "the event's own question is settled by the order")
	# They are driven off.
	for a: Variant in (ev.live["wolves"]["pack"] as Array):
		if is_instance_valid(a):
			(a as Node).queue_free()
	await _frames(2)
	cr.scan()
	_check(not cr.has("wolves"), "wolf crisis ended")
	_check(_aftermaths() > before, "aftermath: %s" % _last_aftermath())
	ev.live.erase("wolves")


# ----------------------------------------------------------------------- raid

func _raid(w: Worker, cr: Node) -> void:
	var before := _aftermaths()
	var ok: bool = cr.trigger("raid")
	if not ok:
		_check(true, "raid could not spawn in this terrain (skipped)")
		return
	_check(cr.has("raid"), "raid crisis begins")
	var b: Dictionary = cr.crisis_of("raid")
	_check(str(b.get("title", "")).find("RAIDERS") >= 0 and str(b["action"]).find("defend the town") >= 0,
		"banner: %s / %s" % [str(b.get("title", "")), str(b.get("action", ""))])
	_check(realm.handle(w, "defend the town"), "order 'defend the town' understood")
	# Nobody to oppose them: they eventually take their spoils and go.
	var c: Dictionary = cr.active["raid"]
	c["since"] = float(c["since"]) - 11.0
	var coins := town.coins
	cr.scan()
	await _frames(2)
	cr.scan()
	_check(not cr.has("raid"), "raiders withdraw rather than lock the town")
	_check(town.coins <= coins, "and the town paid for it")
	_check(_aftermaths() > before, "aftermath: %s" % _last_aftermath())


# ------------------------------------------------------------------- sickness

func _sickness(w: Worker, cr: Node) -> void:
	var before := _aftermaths()
	_check(cr.trigger("sickness"), "sickness triggered")
	_check(cr.has("sickness"), "sickness crisis begins")
	var b: Dictionary = cr.crisis_of("sickness")
	_check(str(b.get("action", "")).find("quarantine") >= 0, "banner: %s" % str(b.get("action", "")))
	_check(realm.handle(w, "quarantine"), "order 'quarantine' understood")
	var hl: Node = realm.system("Health")
	for wid: String in hl.sick:
		_check(float(hl.sick[wid]["severity"]) <= 0.5, "quarantine eased the sickness")
		break
	hl.sick.clear()
	cr.scan()
	_check(not cr.has("sickness"), "sickness crisis ended when everyone was well")
	_check(_aftermaths() > before, "aftermath: %s" % _last_aftermath())


# --------------------------------------------------------------------- famine

func _famine(w: Worker, cr: Node) -> void:
	var before := _aftermaths()
	if realm.population.count() < 4:
		realm.crew.spawn_citizens(4, 99, realm.village.bounds_v)
		realm.population._sync()
	clock.day = maxi(clock.day, 8)
	town.coins = 5000
	_check(cr.trigger("famine"), "famine triggered (pop %d)" % realm.population.count())
	var b: Dictionary = cr.crisis_of("famine")
	_check(str(b.get("action", "")).find("buy food") >= 0, "banner: %s" % str(b.get("action", "")))
	_check(realm.handle(w, "buy 300 food"), "order 'buy food' understood")
	_check(town.units_of("food") > 0, "food bought: %d" % town.units_of("food"))
	cr.scan()
	_check(not cr.has("famine"), "famine ended once the larder was stocked")
	_check(_aftermaths() > before, "aftermath: %s" % _last_aftermath())
	_check(not realm.handle(w, "tell me a story"), "not every order is a crisis order")


# ---------------------------------------------------------------------- storm

func _storm(w: Worker, cr: Node, wx: Node) -> void:
	var before := _aftermaths()
	wx.force("storm")
	var hit: int = wx.storm_damage(30)
	if hit == 0:
		_check(true, "no thatch roof to tear in this town (skipped)")
		return
	cr.scan()
	_check(cr.has("storm"), "storm crisis begins (%d roofs)" % hit)
	var b: Dictionary = cr.crisis_of("storm")
	_check(str(b.get("action", "")).find("repair the roofs") >= 0, "banner: %s" % str(b.get("action", "")))
	wx.force("clear")
	_check(realm.handle(w, "repair the roofs"), "order 'repair the roofs' understood")
	# Hands arrive, one torn roof after another; the hour after they arrive
	# the thatch goes back on.
	for _round in 8:
		if wx.storm_damaged().is_empty():
			break
		for hand: Worker in crew.workers:
			var ids: Array = hand.job_errand.get("extra", {}).get("mend_ids", [])
			for bid: Variant in ids:
				if wx.storm_damaged().has(int(bid)):
					hand.global_position = realm.door_of(realm.population._building_by_id(int(bid)))
					break
		_hours(1)
	cr.scan()
	_check(not cr.has("storm"), "storm crisis ended once the roofs were mended")
	_check(wx.storm_damaged().is_empty(), "no torn roofs left")
	_check(_aftermaths() > before, "aftermath: %s" % _last_aftermath())


func _finish() -> void:
	for f: String in _fails:
		print("[crisis] FAIL: %s" % f)
	print("[crisis] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
