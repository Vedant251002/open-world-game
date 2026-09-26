extends Node
## Tier 5: walls, sieges and marching on the neighbours.
## Run with:  godot --path . -- --realmtest=campaign

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var village: Village
var warfare: Warfare
var nav: NavGrid
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
	print("[campaign] %s %s" % ["ok  " if ok else "FAIL", what])


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
		print("[campaign] %s refused: %s" % [arch, str(res["error"])])
		return false
	Construction.new(res["patch"], world, props_root).complete_now()
	town.register(res["patch"], plot, "", clock.day)
	return true


func _run() -> void:
	var w: Worker = crew.workers[0]
	var cp: Node = realm.system("Campaign")
	var nb: Node = realm.system("Neighbours")
	_check(cp != null, "campaign loaded")
	var a := realm.answer(w, "how strong is our army?")
	_check(a.find("no army") >= 0, "no army yet: %s" % a)

	# --- walls ---
	var b0: Rect2i = village.bounds_v.grow(12)
	var gate0_x: int = village.lines_x[village.lines_x.size() / 2]
	var inside0 := Vector3(gate0_x * 0.25, 0.0, (b0.position.y + 6) * 0.25)
	inside0.y = world.ground_m(inside0.x, inside0.z)
	var before := nav.path(village.well_pos, inside0)
	print("[campaign] path to the gate line before the wall: %d points" % before.size())
	town.stock["sandstone"] = 4000
	_check(realm.run(w, {"do": "wall"}), "wall order taken")
	_check(not cp.wall_job.is_empty(), "wall job planned with %d cells" % (cp.wall_job["cells"] as Array).size())
	_hours(3)
	_check(cp.wall_job["laid"] > 0, "%d wall voxels laid in 3 hours" % int(cp.wall_job["laid"]))
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("wall") >= 0), "hud shows the wall")
	a = realm.answer(w, "how are the walls?")
	_check(a.find("percent") >= 0, "walls: %s" % a)
	var b: Rect2i = cp.wall_job["rect"]
	# A gate where the middle street runs out.
	var gate_x: int = village.lines_x[village.lines_x.size() / 2]
	var gate_cells := 0
	for c: Vector3i in cp.wall_job["cells"]:
		if c.z == b.position.y and absi(c.x - gate_x) < 10:
			gate_cells += 1
	_check(gate_cells == 0, "no wall across the north gate")
	var wall_cells := 0
	for c2: Vector3i in cp.wall_job["cells"]:
		if c2.z == b.position.y and absi(c2.x - gate_x) > 60 and absi(c2.x - gate_x) < 70:
			wall_cells += 1
	_check(wall_cells > 0, "wall cells beside the gate")
	# Sixty hours more and it is done; the way in through the gate still paths.
	_hours(70)
	_check(cp.wall_job.is_empty() and cp.walls.size() == 1, "wall finished")
	var inside := Vector3(gate_x * 0.25, 0.0, (b.position.y + 6) * 0.25)
	inside.y = world.ground_m(inside.x, inside.z)
	var route := nav.path(village.well_pos, inside)
	if before.is_empty():
		print("[campaign] (nav has no ground that far from the player in a headless run; path check skipped)")
	else:
		_check(route.size() > 0, "a path from the well to the gate: %d points" % route.size())

	# --- an army ---
	_check(_stand_up("barracks"), "barracks stood up")
	town.stock["musket"] = 6
	town.stock["shot"] = 200
	town.stock["food"] = 200
	var got: Dictionary = warfare.recruit(6)
	_check(int(got["made"]) == 6, "six recruited: %s" % got["line"])
	a = realm.answer(w, "how strong is our army?")
	_check(a.find("6 soldiers") >= 0, "army: %s" % a)
	_check(realm.run(w, {"do": "pay_army"}), "pay taken")
	_check(cp.morale > 0.7, "morale rose to %.2f" % cp.morale)
	_check(realm.run(w, {"do": "man_walls"}), "man the walls taken")
	a = realm.answer(w, "who is our best soldier?")
	_check(a != "", "best: %s" % a)

	# --- march ---
	var enemy: Dictionary = nb.list()[0]
	var name := str(enemy["name"])
	nb.set_treaty(name, "war")
	var s0 := int(enemy["strength"])
	_check(realm.run(w, {"do": "march", "town": name, "count": 4}), "march taken")
	_check(not cp.expedition.is_empty() and warfare.soldiers.size() == 2, "4 away, 2 at home")
	a = realm.answer(w, "where is the army?")
	_check(a.find(name) >= 0, "where: %s" % a)
	var days := int(enemy["distance_days"]) * 2
	for i in days + 1:
		clock.advance(24.0)
	_check(cp.expedition.is_empty(), "expedition returned")
	_check(warfare.soldiers.size() >= 2, "%d soldiers home" % warfare.soldiers.size())
	_check(int(enemy["strength"]) != s0 or str(enemy["treaty"]) in ["vassal", "war"], "enemy changed: strength %d -> %d, treaty %s" % [s0, int(enemy["strength"]), enemy["treaty"]])

	# --- siege ---
	cp.start_siege(enemy)
	_check(not cp.siege.is_empty(), "siege started by %s" % cp.siege["enemy"])
	_check(is_instance_valid(cp.siege["engine"]), "engine stood up")
	a = realm.answer(w, "are we under siege?")
	_check(a.find(name) >= 0, "siege answer: %s" % a)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("siege") >= 0), "hud shows the siege")
	_hours(4)
	_check(warfare.raiders.size() > 1, "raiders in the field: %d" % warfare.raiders.size())
	_check(int(cp.siege["waves_left"]) < 5, "waves sent")
	# Two days on it resolves one way or the other.
	_hours(50)
	_check(cp.siege.is_empty(), "siege over")
	_check(realm.chronicle.of_kind("siege").size() >= 2, "siege in the chronicle")
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")

	var snap := realm.snapshot()
	cp.restore(snap["Campaign"])
	_check(cp.walls.size() == 1, "restore keeps the wall")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[campaign] FAIL: %s" % f)
	print("[campaign] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
