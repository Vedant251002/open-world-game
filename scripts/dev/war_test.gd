extends Node
class_name WarTest
## Does the fighting work, end to end?
##
## An armoury and a barracks go up, the stores are given steel, and then:
## ammunition is made from it, soldiers are recruited and armed, a raid is
## called and fought, a blast takes a hole out of a hill, a grenade bounces
## and goes off, a rocket flies to where it was pointed, and the player fires
## a rifle. Each of those is a thing that can fail on its own.
##
## Run with:  godot --path . -- --wartest

var world: VoxelWorld
var village: Village
var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var player: Player
var warfare: Warfare
var props_root: Node3D
var farm: Farm
var livestock: Livestock
var wildlife: Wildlife

var _wait := 0.0
var _t := 0.0
var _phase := 0
var _fails: Array[String] = []
var _solid_before := 0
var _crater_at := Vector3.ZERO
var _blasts_before := 0
var _rocket_target := Vector3.ZERO
var _shots_at_raid := 0
var _trace := 0.0
var _shots := false
var _snap := 0.0
var _snaps := 0
var _flight_shot := false
var _strike_shot := false


func begin() -> void:
	_shots = "--shots" in OS.get_cmdline_user_args()
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy() and _wait < 15.0:
		_wait += delta
		return
	_t += delta
	match _phase:
		0:
			_arm_the_town()
			_phase = 1
			_t = 0.0
		1:
			# The raid: let it run, watch for shots and for it to resolve.
			_trace -= delta
			if _trace <= 0.0:
				_trace = 8.0
				for r: Fighter in warfare.raiders:
					print("[war]   raider at %s mode %s hp %d ammo %d target %s" % [
						str(r.global_position.round()), Fighter.Mode.keys()[r._mode],
						int(r.health), r.ammo, str(r._target)])
				for so: Fighter in warfare.soldiers:
					print("[war]   soldier at %s mode %s hp %d weapon %s target %s" % [
						str(so.global_position.round()), Fighter.Mode.keys()[so._mode],
						int(so.health), so.weapon, str(so._target)])
			if _shots and _t > 3.0:
				_snap -= delta
				if _snap <= 0.0 and _snaps < 3 and not warfare.raiders.is_empty():
					_snap = 2.5
					_frame_the_fight()
					_capture("war_fight_%d" % _snaps)
					_snaps += 1
			if warfare.raiders.is_empty() and _t > 2.0:
				print("[war] raid over after %.0f s: %d shots, %d hits, %d raiders down, %d soldiers down"
					% [_t, warfare.shots_fired, warfare.hits_landed, warfare.raiders_fallen,
					warfare.soldiers_fallen])
				_after_raid()
				_phase = 2
				_t = 0.0
			elif _t > 60.0:
				print("[war] raid still going after 120 s: %d shots, %d hits, %d raiders left, %d down"
					% [warfare.shots_fired, warfare.hits_landed, warfare.raiders.size(),
					warfare.raiders_fallen])
				if warfare.shots_fired == 0:
					_fails.append("nobody fired a shot in two minutes of raid")
				if warfare.raiders_fallen == 0 and warfare.soldiers_fallen == 0:
					_fails.append("two minutes of fighting and nobody fell")
				_after_raid()
				_phase = 2
				_t = 0.0
		2:
			# A grenade thrown at a wall, and a rocket at the hill.
			if _t > 0.5:
				_throw_and_launch()
				_phase = 3
				_t = 0.0
		3:
			if _shots and not _flight_shot and _t > 0.55:
				_flight_shot = true
				_capture("war_rocket_flight")
			if _shots and not _strike_shot and _t > 1.3:
				_strike_shot = true
				_capture("war_rocket_strike")
			if _t > 6.0:
				_check_explosives()
				_phase = 4
				_t = 0.0
		4:
			_report()


func _arm_the_town() -> void:
	# Buildings, stood up at once the way the founding town is.
	var mem: WorkerMemory = crew.workers[0].memory
	for arch: String in ["armoury", "barracks"]:
		var plot := _free_plot()
		if plot == null:
			_fails.append("no free plot for the %s" % arch)
			continue
		var spec: Dictionary = ArchetypeLibrary.fallback("build a %s" % arch, mem, plot, 1)["spec"]
		var res := BuildingGenerator.build(spec, 77, plot, _ctx())
		if not res["ok"]:
			_fails.append("the %s would not generate: %s" % [arch, str(res["error"]["code"])])
			print("[war] %s refused: %s" % [arch, str(res["error"])])
			continue
		var patch: VoxelPatch = res["patch"]
		var c := Construction.new(patch, world, props_root)
		c.complete_now()
		town.register(patch, plot, "", clock.day)
		print("[war] %s stood up on %s" % [arch, plot.street_name])
	if warfare.armoury_stand() == Vector3.INF or warfare.barracks_stand() == Vector3.INF:
		_fails.append("armoury or barracks not on the register")

	# Steel in the stores, as if somebody had been to the ore seam.
	town.stock["steel_frame"] = 80
	var before := town.units_of("steel_frame")
	var made := warfare.craft_now("powder", 30)
	if town.units_of("powder") < 30:
		_fails.append("making powder did not put powder in the stores")
	made = warfare.craft_now("shot", 96)
	print("[war] made %d shot; steel %d -> %d" % [made, before, town.units_of("steel_frame")])
	if town.units_of("steel_frame") >= before:
		_fails.append("making shot cost no steel")
	warfare.craft_now("rifle", 4)
	warfare.craft_now("grenade", 8)
	warfare.craft_now("rocket", 2)
	if town.units_of("rifle") < 4 or town.units_of("grenade") < 8 or town.units_of("rocket") < 2:
		_fails.append("the armoury did not make what was asked: rifles %d grenades %d rockets %d"
			% [town.units_of("rifle"), town.units_of("grenade"), town.units_of("rocket")])

	# Short of something: asking for a mortar with no steel left must refuse.
	town.stock["steel_frame"] = 2
	var short := warfare.short_for("mortar", 1)
	if short.is_empty():
		_fails.append("a mortar with two steel in the stores should be short of steel")

	# The army.
	var coins := town.coins
	var r := warfare.recruit(3)
	print("[war] recruit: %s" % str(r["line"]))
	if warfare.soldiers.size() != 3:
		_fails.append("asked for three soldiers, got %d" % warfare.soldiers.size())
	if town.coins >= coins:
		_fails.append("recruiting cost nothing")
	var armed := 0
	for s: Fighter in warfare.soldiers:
		if s.weapon == "rifle":
			armed += 1
	if armed != 3:
		_fails.append("three rifles in the stores and %d soldiers carry one" % armed)

	# The player takes one too.
	warfare.craft_now("rifle", 1)
	var take := warfare.arm_player("rifle")
	if not take["ok"] or warfare.player_weapon() != "rifle":
		_fails.append("the player could not take a rifle: %s" % str(take["line"]))

	# Defend the well, then a raid.
	warfare.defend(village.well_pos)
	_shots_at_raid = warfare.shots_fired
	warfare.raid(3)
	print("[war] raid called: %d raiders, %d soldiers" % [warfare.raiders.size(), warfare.soldiers.size()])
	if warfare.raiders.size() != 3:
		_fails.append("asked for three raiders, got %d" % warfare.raiders.size())


func _after_raid() -> void:
	if warfare.shots_fired - _shots_at_raid == 0:
		_fails.append("no shots were fired during the raid")


func _throw_and_launch() -> void:
	# A hill to hit: open ground forty metres out, whatever direction has some.
	var well := village.well_pos
	_rocket_target = well + Vector3(0, 0, 70.0)
	_rocket_target.y = world.ground_m(_rocket_target.x, _rocket_target.z)
	_crater_at = _rocket_target
	_solid_before = _solid_count(_crater_at, 5.0)
	_blasts_before = warfare.blasts

	# The rocket, fired from the air above the point so the flight is the
	# guidance and the landing and not whichever roof was in the way.
	var from := _rocket_target + Vector3(0, 28.0, -24.0)
	if _shots:
		# Stand where the strike can be seen: off to the side, looking at it.
		var eye := _rocket_target + Vector3(16.0, 0.0, -10.0)
		eye.y = world.ground_m(eye.x, eye.z) + 1.6
		player.set_input_enabled(false)
		var look := _rocket_target - eye
		player.teleport(eye, atan2(-look.x, -look.z))
		player.pitch = -atan2(eye.y - _rocket_target.y - 2.0, Vector2(look.x, look.z).length())
	var spec := Arsenal.weapon("launcher")
	town.stock["rocket"] = maxi(town.units_of("rocket"), 1)
	warfare.player_weapons.append("launcher")
	warfare.player_weapon_i = warfare.player_weapons.size() - 1
	var dir := (_rocket_target + Vector3(0, 0.5, 0) - from).normalized()
	var ok := warfare.fire(player, "launcher", from, _rocket_target + Vector3(0, 0.5, 0), null)
	print("[war] rocket away: %s, toward %s" % [str(ok), str(_rocket_target.round())])
	if not ok:
		_fails.append("the launcher would not fire")

	# A grenade at the nearest wall of the armoury.
	var stand := warfare.armoury_stand()
	if stand == Vector3.INF:
		stand = well + Vector3(6.0, 0.0, 6.0)
		stand.y = world.ground_m(stand.x, stand.z)
	var gfrom := stand + Vector3(0, 1.2, 0)
	town.stock["grenade"] = maxi(town.units_of("grenade"), 1)
	warfare.player_weapons.append("grenade")
	warfare.player_weapon_i = warfare.player_weapons.size() - 1
	var wall := stand - Vector3(0, 0, 3.0)
	var ok2 := warfare.fire(player, "grenade", gfrom, wall + Vector3(0, 0.5, 0), null)
	if not ok2:
		_fails.append("the grenade would not throw")

	# And a plain rifle shot from the player, which must cost one shot.
	warfare.player_weapon_i = warfare.player_weapons.find("rifle")
	town.stock["shot"] = maxi(town.units_of("shot"), 10)
	var shot_before := town.units_of("shot")
	if not _shots:
		player.teleport(well + Vector3(0, 0.5, 8.0), 0.0)
	warfare.player_reload = 0.0
	var fired := warfare.player_fire()
	if not fired or town.units_of("shot") != shot_before - 1:
		_fails.append("the player's rifle did not fire and cost one shot (fired=%s, %d -> %d)"
			% [str(fired), shot_before, town.units_of("shot")])


func _check_explosives() -> void:
	var after := _solid_count(_crater_at, 5.0)
	print("[war] solid voxels within 5 m of the rocket's target: %d -> %d; blasts %d -> %d"
		% [_solid_before, after, _blasts_before, warfare.blasts])
	if warfare.blasts < _blasts_before + 2:
		_fails.append("expected the rocket and the grenade both to go off; %d blasts"
			% (warfare.blasts - _blasts_before))
	if after >= _solid_before - 40:
		_fails.append("the rocket left no crater where it was aimed (%d -> %d solid)"
			% [_solid_before, after])


## Puts the player behind the soldiers, looking at the raiders.
func _frame_the_fight() -> void:
	if warfare.soldiers.is_empty() or warfare.raiders.is_empty():
		return
	var s := Vector3.ZERO
	for f: Fighter in warfare.soldiers:
		s += f.global_position
	s /= warfare.soldiers.size()
	var r := Vector3.ZERO
	for f: Fighter in warfare.raiders:
		r += f.global_position
	r /= warfare.raiders.size()
	var back := (s - r)
	back.y = 0.0
	back = back.normalized()
	var eye := s + back * 4.5 + Vector3(back.z, 0.0, -back.x) * 2.0
	eye.y = world.ground_m(eye.x, eye.z) + 1.4
	var look := r - eye
	player.set_input_enabled(false)
	player.teleport(eye, atan2(-look.x, -look.z))
	player.pitch = -atan2(eye.y - r.y - 1.0, Vector2(look.x, look.z).length()) * 0.8


func _capture(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, view_name]))
	print("[war] %s/%s.png" % [dir, view_name])


func _solid_count(at: Vector3, r: float) -> int:
	var c := VoxelWorld.to_voxel(at)
	var rv := int(r / 0.25)
	var n := 0
	for dy in range(-rv, rv + 1):
		for dz in range(-rv, rv + 1):
			for dx in range(-rv, rv + 1):
				var v := Vector3i(c.x + dx, c.y + dy, c.z + dz)
				if VoxelWorld.centre_metres(v).distance_to(at) <= r and world.is_solid(v):
					n += 1
	return n


func _free_plot() -> Plot:
	var best: Plot = null
	var best_d := INF
	for p: Plot in village.plots:
		if p.occupied_by >= 0 or p.reserved:
			continue
		var d := p.centre_m().distance_to(village.well_pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func _ctx() -> Dictionary:
	var rects: Array = []
	var fronts := {}
	for rec: Dictionary in town.buildings:
		var patch: VoxelPatch = rec["patch"]
		rects.append(patch.footprint)
		fronts[int(rec["plot_id"])] = patch.front
	return {"world": world, "village": village, "tier": town.tier,
		"occupied_rects": rects, "built_fronts": fronts}


func _report() -> void:
	set_process(false)
	# The workers can answer for the army.
	var a := Answers.reply("how many soldiers do we have?", crew.workers[0], town, village,
		clock, player, farm, livestock, wildlife, warfare)
	print("[war] \"how many soldiers do we have?\" -> %s" % a)
	if a.find("soldier") < 0:
		_fails.append("the crew cannot say how many soldiers there are: %s" % a)
	var b := Answers.reply("how much powder is there?", crew.workers[0], town, village,
		clock, player, farm, livestock, wildlife, warfare)
	print("[war] \"how much powder is there?\" -> %s" % b)
	if b.find("powder") < 0:
		_fails.append("the crew cannot say how much powder there is: %s" % b)
	for f: String in _fails:
		print("[war] FAIL: %s" % f)
	print("[war] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
