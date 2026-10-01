extends Node
## Headless test for the guided first day, milestones and village identity.
## Run with:  godot --headless --path . -- --realmtest=tutorial --nosave
##
## The tutorial is driven only by the signals the game really emits (the talk
## bar opening, an order accepted, a job done, the roster changing, the map
## opening), so this walks it through the whole day that way.

var world: VoxelWorld
var village: Village
var town: Town
var clock: GameClock
var player: Player
var crew: Crew
var hud: Hud
var dispatch: Dispatcher
var map: MapScreen
var inventory: InventoryScreen

var _fails := 0
var _checks := 0


func begin() -> void:
	await get_tree().process_frame
	await _run()
	print("[tutorial_test] %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("[tutorial_test] FAIL: %s" % what)
	else:
		print("[tutorial_test] ok: %s" % what)


func _run() -> void:
	var main := get_parent()
	var mira := crew.get_worker("mira")
	var tobias := crew.get_worker("tobias")
	var prog: Progression = main.get("progression")
	var ui: MilestonesUi = main.get("milestones_ui")
	_ok(mira != null and tobias != null, "crew present")
	_ok(prog != null and ui != null, "main raised progression and its ui")
	_ok(main.get("identity") != null and str(main.get("identity").village_name) != "",
		"main has a named village identity")

	# --- the first day ------------------------------------------------------
	var tut := Tutorial.new()
	add_child(tut)
	tut.setup(hud, crew, dispatch, town, map, player, clock, ui)
	var seen: Array[String] = []
	tut.step_changed.connect(func(id: String) -> void: seen.append(id))
	tut.start()
	_ok(tut.active and tut.current_id() == "talk", "starts on the talk step")

	# A phrase typed before the right step does nothing.
	tut.notify("plan", [tobias, []])
	_ok(tut.current_id() == "talk", "a plan before talking does not skip ahead")

	hud.talk_opened.emit(mira)
	_ok(tut.current_id() == "order", "talking to Mira advances to the order step")

	var coins0 := town.coins
	dispatch.plan_accepted.emit(tobias, ["a small hut", "timber walls"])
	_ok(tut.current_id() == "assume", "an accepted plan advances to the assumptions")
	_ok(prog.ordered_any, "an accepted plan counts for the first-order milestone")
	tut.notify("gotit")
	_ok(tut.current_id() == "build", "Got it advances to the build step")

	var patch := VoxelPatch.new(Vector3i.ZERO, Vector3i.ONE)
	crew.job_done.emit(tobias, patch)
	_ok(tut.current_id() == "ask", "a finished building advances to the question step")
	_ok(town.coins >= coins0 + Tutorial.REWARD_COINS, "the first building pays a reward")

	hud.instruction_given.emit(tobias, "build a wall")
	_ok(tut.current_id() == "ask", "an order is not a question")
	hud.instruction_given.emit(mira, "how is the town doing?")
	_ok(tut.current_id() == "hire", "a question advances to the hire step")

	crew.roster_changed.emit()
	_ok(tut.current_id() == "hire", "an unchanged roster does not advance")
	var stranger: Worker = null
	for w: Worker in crew.workers:
		if not w.hired:
			stranger = w
			break
	_ok(stranger != null, "there is somebody to hire")
	if stranger != null:
		stranger.hired = true
		crew.roster_changed.emit()
		_ok(tut.current_id() == "map", "hiring advances to the map step")
		stranger.hired = false
	map.set_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(tut.current_id() == "done", "opening the map advances to the end")
	map.set_open(false)
	_ok(seen == ["talk", "order", "assume", "build", "ask", "hire", "map", "done"],
		"steps came in order: %s" % str(seen))

	# --- save, restore and skip ---------------------------------------------
	var snap := tut.snapshot()
	var t2 := Tutorial.new()
	add_child(t2)
	t2.setup(hud, crew, dispatch, town, map, player, clock, ui)
	t2.restore({"step": 4, "complete": false, "skipped": false})
	_ok(t2.active and t2.current_id() == "ask", "a mid-tutorial save resumes at its step")
	t2.skip()
	_ok(t2.skipped and not t2.active, "skip ends it")
	_ok(bool(t2.snapshot()["skipped"]), "skip is remembered in the snapshot")
	var t3 := Tutorial.new()
	add_child(t3)
	t3.setup(hud, crew, dispatch, town, map, player, clock, ui)
	t3.restore({})
	_ok(t3.complete and not t3.active, "an older save with no record never shows it")
	t3.restore(t2.snapshot())
	_ok(not t3.active, "a skipped tutorial stays skipped")
	_ok(snap.has("step"), "snapshot has a step")

	# --- milestones ----------------------------------------------------------
	var got: Array[String] = []
	prog.milestone_reached.connect(func(id: String, _t: String, _r: int) -> void: got.append(id))
	var coins1 := town.coins
	prog.evaluate()
	prog.grant("first_harvest")
	_ok("first_harvest" in got and town.coins > coins1, "a milestone pays and announces itself")
	_ok(not prog.grant("first_harvest"), "a milestone is paid only once")
	var shot := prog.snapshot()
	var prog2 := Progression.new()
	add_child(prog2)
	prog2.setup(town, crew, clock, null, null, dispatch)
	prog2.restore(shot)
	_ok(prog2.is_done("first_harvest"), "milestones survive a save")
	_ok(prog.rank_name() == "Hamlet" and prog.rank_progress() >= 0.0 and prog.rank_progress() <= 1.0,
		"rank reads off the tier with a 0..1 bar")
	var tier_before := town.tier
	town.tier = 2
	prog.evaluate()
	_ok(prog.rank_name() == "Village" and prog.is_done("tier_2"), "a tier up raises the rank and its milestone")
	town.tier = tier_before

	# --- landscapes ----------------------------------------------------------
	# Averaged over a few seeds, because any one seed's own lakes and ridges
	# would drown the difference.
	var profile := {}
	for lid: String in VillageIdentity.LANDSCAPE_ORDER:
		var south_sea := 0.0
		var relief := 0.0
		var trees := 0.0
		for sd in [11, 2024, 31337, 99]:
			var g := WorldGen.new()
			g.landscape = lid
			g.setup(sd, village)
			var vb := village.bounds_v
			var south_n := 0
			var south_wet := 0
			var land_n := 0
			var sum := 0.0
			var sum2 := 0.0
			for z in range(vb.position.y - 320, vb.end.y + 320, 12):
				for x in range(vb.position.x - 320, vb.end.x + 320, 12):
					if vb.grow(8).has_point(Vector2i(x, z)):
						continue
					var h := g.height_at(x, z)
					var wet := h <= g.sea_voxel()
					if z > vb.end.y + 40 and absi(x - vb.get_center().x) < 300:
						south_n += 1
						south_wet += 1 if wet else 0
					if not wet:
						land_n += 1
						sum += h
						sum2 += float(h) * h
			var mean := sum / maxf(land_n, 1)
			south_sea += float(south_wet) / maxf(south_n, 1) / 4.0
			relief += sqrt(maxf(sum2 / maxf(land_n, 1) - mean * mean, 0.0)) / 4.0
			for cz in range(-10, 11):
				for cx in range(-10, 11):
					for f: Dictionary in g._cell_features(cx, cz):
						if f["type"] == "tree":
							trees += 0.25
			# The village shelf is intact whatever the landscape.
			if g.height_at(vb.position.x + 40, vb.position.y + 40) <= g.sea_voxel():
				_ok(false, "%s seed %d: the village stands on dry land" % [lid, sd])
		profile[lid] = {"south_sea": south_sea, "relief": relief, "trees": trees}
		print("[tutorial_test] %s: %s" % [lid, str(profile[lid])])
	_ok(profile["coast"]["south_sea"] > profile["meadow"]["south_sea"] + 0.5, "coast puts the sea to the south")
	_ok(profile["forest"]["trees"] > profile["meadow"]["trees"] * 1.4, "forest has far more trees than meadow")
	_ok(profile["hills"]["relief"] > profile["meadow"]["relief"] * 1.3, "hills have far more relief than meadow")

	# --- identity -------------------------------------------------------------
	var vi := VillageIdentity.new()
	vi.village_name = "  Thistlewick  "
	vi.colour_idx = 3
	vi.emblem_idx = 4
	vi.landscape = "coast"
	vi.village_name = VillageIdentity.sanitise(vi.village_name)
	var back := VillageIdentity.from_dict(vi.to_dict())
	_ok(back.village_name == "Thistlewick" and back.colour_idx == 3 and back.emblem_idx == 4
		and back.landscape == "coast", "identity round-trips through a save")
	_ok(VillageIdentity.from_dict({}).landscape == "", "an older save keeps the classic terrain")
	_ok(VillageIdentity.from_dict({"landscape": "volcano"}).landscape == "", "unknown landscape falls back")
	var snap_main: Dictionary = main.call("_snapshot")
	_ok(snap_main.has("identity") and snap_main.has("progression") and snap_main.has("tutorial"),
		"the save snapshot carries identity, progression and tutorial")
