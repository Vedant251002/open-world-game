extends Node
## Tier 4a: horses under the player, and the land picked over.
## Run with:  godot --path . -- --realmtest=riding

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var village: Village
var player: Player
var livestock: Livestock
var props_root: Node3D
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
	print("[riding] %s %s" % ["ok  " if ok else "FAIL", what])


func _hours(n: int) -> void:
	for i in n:
		clock.advance(1.0)


func _stand_up(arch: String) -> bool:
	var plot: Plot = null
	var best := INF
	for p: Plot in village.plots:
		if p.occupied_by < 0 and not p.reserved and p.centre_m().distance_to(village.well_pos) < best:
			best = p.centre_m().distance_to(village.well_pos)
			plot = p
	if plot == null:
		return false
	var spec: Dictionary = ArchetypeLibrary.fallback("build a %s" % arch, crew.workers[0].memory, plot, 1)["spec"]
	var rects: Array = []
	var fronts := {}
	for rec: Dictionary in town.buildings:
		rects.append((rec["patch"] as VoxelPatch).footprint)
		fronts[int(rec["plot_id"])] = (rec["patch"] as VoxelPatch).front
	var res := BuildingGenerator.build(spec, 77, plot, {"world": world, "village": village,
		"tier": town.tier, "occupied_rects": rects, "built_fronts": fronts})
	if not res["ok"]:
		print("[riding] %s refused: %s" % [arch, str(res["error"])])
		return false
	Construction.new(res["patch"], world, props_root).complete_now()
	town.register(res["patch"], plot, "", clock.day)
	return true


func _run() -> void:
	var w: Worker = crew.workers[0]
	var ride: Node = realm.system("Riding")
	var forage: Node = realm.system("Foraging")
	_check(ride != null and forage != null, "riding and foraging loaded")

	# --- horses ---
	var a := realm.answer(w, "how many horses do we have?")
	_check(a.find("No horses") >= 0, "no horses yet: %s" % a)
	_check(realm.run(w, {"do": "buy_horse"}), "buy without a stable is answered")
	_check(ride.horses().is_empty(), "no horse without a stable")
	_check(_stand_up("stable"), "stable stood up")
	var c0 := town.coins
	_check(realm.run(w, {"do": "buy_horse"}), "buy taken")
	_check(ride.horses().size() == 1 and town.coins < c0, "one horse for %d coins" % (c0 - town.coins))
	a = realm.answer(w, "how many horses do we have?")
	_check(a.find("1 horse") >= 0, "horses: %s" % a)
	var h: Animal = (ride.horses() as Array)[0]
	_check(ride.mount_horse(h), "mounted")
	_check(is_equal_approx(player.speed_scale, 2.2) and player.eye_offset > 0.5 and player.mount == h, "player rides faster and higher")
	_check(realm.hud_lines().has("riding"), "hud says riding")
	ride.tick(0.016)
	_check(h.global_position.distance_to(player.global_position) < 2.0, "horse sits under the player")
	ride.dismount()
	_check(is_equal_approx(player.speed_scale, 1.0) and player.mount == null and h.is_physics_processing(), "dismounted, horse is its own again")
	_check(realm.run(w, {"do": "hitch_cart"}), "cart hitched")
	_check(ride.has_cart() and ride.cart_capacity() == 200, "cart follows with room for 200")
	_check(realm.run(w, {"do": "unhitch_cart"}), "cart unhitched")
	_check(not ride.has_cart(), "cart gone")
	# A worker borrows the horse for an errand and gives it back.
	w.take_errand_job("wait", village.well_pos + Vector3(20, 0, 0), 2.0, "", {"where": "the field", "doing": "survey"})
	_check(ride.lend(w), "horse lent to %s" % w.display_name())
	ride.tick(0.016)
	_check(h.global_position.distance_to(w.global_position) < 2.0, "horse under the worker")
	w.drop_everything()
	ride.on_hour(clock.hour, clock.day)
	_check(ride.free_horse(village.well_pos) == h, "horse returned when the errand ended")

	# --- foraging ---
	_check(forage.spots.size() == 18, "18 forage spots seeded")
	# Spots live past the last street; pull one in beside the well so the
	# player (who is not walking anywhere in a headless run) can reach it.
	var near: Dictionary = forage.nearest("berries", village.well_pos)
	near["x"] = village.well_pos.x + 27.0
	near["z"] = village.well_pos.z + 27.0
	forage.tick(1.1)
	var spawned := 0
	for s: Dictionary in forage.spots:
		if s["node"] != null:
			spawned += 1
	_check(spawned > 0, "%d spots stood up near the player" % spawned)
	var berries: Dictionary = forage.nearest("berries", village.well_pos)
	_check(not berries.is_empty(), "a berry bush exists")
	var f0 := town.units_of("food")
	var got: int = forage.pick(berries)
	_check(got >= 3 and town.units_of("berries") == got and town.units_of("food") == f0 + got * 2, "picked %d berries into the larder" % got)
	_check(forage.pick(berries) == 0 and not forage.ripe(berries), "picked bush is bare")
	for i in 3:
		clock.advance(24.0)
	_check(forage.ripe(berries), "ripe again after three days")
	a = realm.answer(w, "where can I find herbs?")
	_check(a.find("metres") >= 0, "herbs where: %s" % a)
	a = realm.answer(w, "is there anywhere to fish?")
	_check(a != "", "fishing where: %s" % a)
	var w2: Worker = crew.workers[1]
	var herb0 := town.units_of("herb")
	_check(realm.run(w2, {"do": "forage", "what": "herb"}), "gather herbs taken")
	_hours(3)
	_check(town.units_of("herb") > herb0, "worker brought %d herbs" % (town.units_of("herb") - herb0))
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")

	var snap := realm.snapshot()
	forage.restore(snap["Foraging"])
	_check(forage.spots.size() == 18, "forage restore")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[riding] FAIL: %s" % f)
	print("[riding] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
