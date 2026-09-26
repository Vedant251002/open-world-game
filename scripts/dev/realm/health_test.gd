extends Node
## Tier 4b: the sick and the worn.
## Run with:  godot --path . -- --realmtest=health

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var warfare: Warfare
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
	print("[health] %s %s" % ["ok  " if ok else "FAIL", what])


func _hours(n: int) -> void:
	for i in n:
		clock.advance(1.0)


func _missing(rec: Dictionary) -> int:
	var patch: VoxelPatch = rec["patch"]
	var n := 0
	for y in patch.size.y:
		for x in patch.size.x:
			for z in patch.size.z:
				var want := patch.peek(x, y, z)
				if want == VoxelPatch.UNTOUCHED or want == VoxelTypes.AIR:
					continue
				if world.get_voxel(patch.local_to_world(x, y, z)) != want:
					n += 1
	return n


func _run() -> void:
	var w: Worker = crew.workers[0]
	var hl: Node = realm.system("Health")
	var up: Node = realm.system("Upkeep")
	_check(hl != null and up != null, "health and upkeep loaded")

	# --- health ---
	var cit: Worker = crew.citizens()[0]
	var a := realm.answer(w, "who is sick?")
	_check(a.find("Nobody") >= 0, "nobody sick: %s" % a)
	hl.infect(cit, "fever")
	_check(hl.is_sick(cit), "%s has a fever" % cit.display_name())
	a = realm.answer(w, "who is sick?")
	_check(a.find(cit.display_name()) >= 0, "sick listed: %s" % a)
	a = realm.answer(w, "how is %s?" % cit.display_name())
	_check(a.find("fever") >= 0, "how is: %s" % a)
	var hp0 := cit.health
	clock.advance(24.0)
	_check(cit.health < hp0, "fever drained health %d -> %d" % [int(hp0), int(cit.health)])
	town.stock["herb"] = 0
	_check(realm.run(w, {"do": "treat"}), "treat without herbs answered")
	_check(hl.is_sick(cit), "still sick without herbs")
	town.stock["herb"] = 10
	_check(realm.run(w, {"do": "treat"}), "treat taken")
	_hours(2)
	_check(not hl.is_sick(cit) and town.units_of("herb") < 10, "cured with herbs (%d left)" % town.units_of("herb"))
	# A hired worker takes to bed and refuses orders.
	var w2: Worker = crew.workers[1]
	hl.infect(w2, "flux")
	w2.health = 5.0
	clock.advance(24.0)
	_check(hl.is_bedridden(w2), "%s is bedridden" % w2.display_name())
	_check(realm.cannot_work(w2) != "", "bedridden worker refuses everything")
	for i in 4:
		clock.advance(24.0)
	_check(not hl.is_bedridden(w2), "up again after bed rest")
	hl.sick.erase(w2.memory.worker_id)
	# The player eats and sleeps.
	warfare.player_health = 40.0
	town.stock["food"] = 30
	_check(realm.run(w, {"do": "eat"}), "meal taken")
	_check(is_equal_approx(warfare.player_health, 70.0) and town.units_of("food") == 25, "meal healed 30 for 5 food")
	a = realm.answer(w, "how am I?")
	_check(a.find("70") >= 0, "health answer: %s" % a)
	var c0 := town.coins
	_check(realm.run(w, {"do": "lodge"}), "inn taken")
	_check(is_equal_approx(warfare.player_health, 100.0) and absf(clock.hour - 7.0) < 0.01,
		"slept to morning for 10 coins (health %d, coins %d -> %d, hour %.2f)" % [int(warfare.player_health), c0, town.coins, clock.hour])
	_check(realm.run(w, {"do": "name_healer", "who": cit.display_name()}), "healer named")
	_check(hl.healer() == cit, "healer is %s" % cit.display_name())

	# --- upkeep ---
	var bakery := realm.building("bakery")
	var bid := int(bakery["id"])
	_check(is_equal_approx(up.condition_of(bid), 0.85) or up.condition_of(bid) < 0.85, "founding condition %.2f" % up.condition_of(bid))
	a = realm.answer(w, "what state is the bakery in?")
	_check(a.find("percent") >= 0, "state: %s" % a)
	up.set_condition(bid, 0.2)
	var miss0: int = up.missing_count(bakery)
	clock.advance(24.0)
	_check(up.missing_count(bakery) > miss0, "decay took voxels: %d -> %d missing" % [miss0, up.missing_count(bakery)])
	a = realm.answer(w, "which buildings need repair?")
	_check(a.find("bakery") >= 0, "needs repair: %s" % a)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("repair") >= 0), "hud warns")
	a = realm.answer(w, "how much does upkeep cost?")
	_check(a.find("coins") >= 0, "upkeep: %s" % a)
	_check(realm.run(w, {"do": "repair", "place": "bakery"}), "repair taken")
	_check(not w.job_errand.is_empty(), "worker is on the repair errand")
	# Put the worker at the door so the hourly pass counts them as on site.
	w.global_position = realm.door_of(bakery)
	_hours(12)
	_check(up.condition_of(bid) >= 0.9, "condition back to %.2f" % up.condition_of(bid))
	_check(up.missing_count(bakery) == 0, "voxels put back (%d missing)" % up.missing_count(bakery))
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")

	var snap := realm.snapshot()
	hl.restore(snap["Health"])
	up.restore(snap["Upkeep"])
	_check(hl.healer_id == cit.memory.worker_id and up.condition_of(bid) >= 0.9, "restore round trip")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[health] FAIL: %s" % f)
	print("[health] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
