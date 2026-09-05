extends Node3D
## DELEGATE — boot.
##
## The world has no edges: chunks stream in around the player and forget
## themselves behind him. Only the village is pinned, because it is the one
## place the game is actually about.

const WORLD_HEIGHT_CHUNKS := 6      ## 48 m of vertical range at 0.25 m

var world: VoxelWorld
var gen: WorldGen
var village: Village
var streamer: ChunkStreamer
var far: FarTerrain
var sky: SkyEnv
var player: Player
var map: MapScreen
var touch: TouchControls
var props_root: Node3D
var clock: GameClock
var nav: NavGrid
var town: Town
var crew: Crew
var dispatch: Dispatcher
var hud: Hud
var farm: Farm
var livestock: Livestock

var _world_seed := 0
var showcase_views: Array[Dictionary] = []
var showcase_patches: Array[VoxelPatch] = []
var _interior_shots := false
var _room_shots := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_world_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	for arg in args:
		if arg.begins_with("--seed="):
			_world_seed = int(arg.substr(7))

	sky = SkyEnv.new()
	add_child(sky)

	village = Village.new()
	village.build(_world_seed)

	gen = WorldGen.new()
	gen.setup(_world_seed, village)

	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	add_child(world)
	world.configure(WORLD_HEIGHT_CHUNKS)

	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)

	player = Player.new()
	player.world = world
	add_child(player)
	player.teleport(village.spawn_pos + Vector3(0, 1.2, 0), PI)

	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	add_child(streamer)
	streamer.setup(world, gen, village, player)

	# Before prime(): the streaming radii have to be right when the first ring
	# of columns is queued, or the handheld build pays for the wide load once
	# regardless and only saves on every load after it.
	Quality.apply(get_viewport(), player, streamer)

	if "--nofar" not in args:
		far = FarTerrain.new()
		far.name = "FarTerrain"
		add_child(far)
		far.setup(gen)
		far.build_now(village.spawn_pos)

	var t0 := Time.get_ticks_msec()
	var columns := streamer.prime(village.spawn_pos)
	print("[delegate] seed %d, %d plots, priming %d columns" % [
		_world_seed, village.plots.size(), columns])
	streamer.first_load_done.connect(_on_world_ready.bind(t0))

	clock = GameClock.new()
	clock.name = "Clock"
	add_child(clock)

	town = Town.new()

	map = MapScreen.new()
	map.name = "Map"
	add_child(map)
	map.setup(world, gen, village, player)

	touch = TouchControls.new()
	touch.name = "Touch"
	touch.player = player
	touch.map = map
	add_child(touch)

	if "--streamtest" in args:
		var st := StreamTest.new()
		st.world = world
		st.gen = gen
		st.village = village
		add_child(st)
		get_tree().quit(st.run())
		return
	if "--gentest" in args:
		await streamer.first_load_done
		var gt := GenTest.new()
		gt.world = world
		gt.village = village
		gt.gen = gen
		add_child(gt)
		get_tree().quit(gt.run())
		return


func _process(_delta: float) -> void:
	if player == null:
		return
	if far != null:
		far.refresh(player.global_position)


## Collision is a physics concern, so it is kept current on the physics tick
## rather than the render one: _process can run several times between physics
## steps, or not at all before one, and the frame the player moves is exactly
## the frame the floor has to already be there.
func _physics_process(_delta: float) -> void:
	if player == null:
		return
	world.refresh_collision(player.global_position)
	world.ensure_support(player.global_position)
	if crew != null:
		var here: Array[Vector3] = []
		for w: Worker in crew.workers:
			here.append(w.global_position)
		world.set_agents(here)


func _on_world_ready(t0: int) -> void:
	print("[delegate] world ready in %d ms: %d columns, %d chunks, %d mesh nodes" % [
		Time.get_ticks_msec() - t0, world.loaded_columns(),
		world.chunk_count(), world.mesh_node_count()])
	var g := world.ground_m(player.global_position.x, player.global_position.z)
	player.teleport(Vector3(player.global_position.x, g + 0.4,
		player.global_position.z), PI)

	var args := OS.get_cmdline_user_args()
	_room_shots = "--rooms" in args or "--flicker" in args
	_interior_shots = "--inside" in args or _room_shots
	if "--empty" not in args:
		_found_town()

	# After the founding buildings: the nav grid reads the world as it stands,
	# and a crew that pathed through the bakery would look ridiculous.
	if "--nocrew" not in args:
		_raise_crew()
	if "--nostream" in args:
		streamer.set_process(false)
	if "--nomap" in args:
		map.set_process(false)
	if "--noworld" in args:
		world.set_process(false)
	if "--aitest" in args:
		var at := AiTest.new()
		at.dispatch = dispatch
		at.crew = crew
		at.clock = clock
		at.town = town
		at.world = world
		add_child(at)
		var say := ""
		for a in args:
			if a.begins_with("--say="):
				say = a.substr(6)
		at.begin(say)
		return
	if "--crewtest" in args:
		var ct := CrewTest.new()
		ct.world = world
		ct.gen = gen
		ct.village = village
		ct.crew = crew
		ct.dispatch = dispatch
		ct.clock = clock
		ct.town = town
		ct.player = player
		ct.farm = farm
		ct.livestock = livestock
		ct.hud = hud
		add_child(ct)
		ct.begin()
		return
	if "--walktest" in args:
		var wt := WalkTest.new()
		wt.world = world
		wt.player = player
		wt.streamer = streamer
		add_child(wt)
		var cap := 0
		for a in args:
			if a.begins_with("--fps="):
				cap = int(a.substr(6))
		wt.begin(village.spawn_pos, cap)
		return
	if "--bench" in args:
		var b := Bench.new()
		b.player = player
		b.world = world
		b.sky = sky
		b.streamer = streamer
		add_child(b)
		b.start(village.well_pos)
		return
	if "--audit" in args:
		var ra := RenderAudit.new()
		ra.world = world
		ra.village = village
		ra.player = player
		ra.sky = sky
		add_child(ra)
		var focus: VoxelPatch = null
		for pa in showcase_patches:
			if pa.archetype == "bakery":
				focus = pa
		if focus == null and not showcase_patches.is_empty():
			focus = showcase_patches[0]
		ra.compose(focus, village.well_pos)
		return
	if "--mapshot" in args:
		map.capture_and_quit()
		return
	if "--flicker" in args:
		var ft := FlickerTest.new()
		ft.world = world
		ft.player = player
		ft.sky = sky
		ft.hud = hud
		add_child(ft)
		ft.views = showcase_views.duplicate()
		ft.begin()
		return
	if "--cast" in args:
		_line_up_cast()
	for flag in ["--shot", "--inside", "--rooms", "--cast"]:
		if flag in args:
			_install_shotter()
			break


## Brings the three of them on. They spawn at the well and then follow you
## about, because an instruction you have to walk home to give is an instruction
## you do not give.
func _raise_crew() -> void:
	nav = NavGrid.new()
	nav.build(world, village.nav_bounds_v(64))

	crew = Crew.new()
	crew.name = "Crew"
	add_child(crew)
	crew.spawn(world, nav, clock, town, player, village.well_pos)

	farm = Farm.new()
	farm.name = "Farm"
	add_child(farm)
	farm.setup(world, gen, clock, town)

	livestock = Livestock.new()
	livestock.name = "Livestock"
	add_child(livestock)
	livestock.setup(world, clock, town, player)
	# A few hens about the well from the start, so the town is inhabited before
	# anyone gives an order.
	livestock.stock_area("hen", village.well_pos + Vector3(6, 0, -5), 5, 7.0)
	livestock.stock_area("sheep", village.well_pos + Vector3(-13, 0, 9), 3, 8.0)

	if "--demo" in OS.get_cmdline_user_args():
		_demo_field()

	dispatch = Dispatcher.new()
	dispatch.name = "Dispatcher"
	add_child(dispatch)
	dispatch.setup(world, village, gen, town, clock, nav, props_root, map)
	dispatch.farm = farm
	dispatch.livestock = livestock
	dispatch.player = player

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(player, crew, clock, town)

	hud.farm = farm
	hud.harvest_wanted.connect(_on_harvest)
	hud.instruction_given.connect(func(w: Worker, t: String) -> void:
		dispatch.instruct(w, t))
	hud.answer_given.connect(func(w: Worker, t: String) -> void:
		dispatch.answer(w, t))
	dispatch.plan_accepted.connect(func(w: Worker, a: Array) -> void:
		hud.show_assumptions(w, a))
	dispatch.status.connect(func(t: String) -> void: hud.toast(t))
	crew.job_done.connect(_on_job_done)
	crew.job_failed.connect(func(w: Worker, e: Dictionary) -> void:
		hud.toast("%s: %s" % [w.display_name(), str(e.get("code", "refused"))], 5.0))

	print("[delegate] crew: %s   (AI: %s)" % [", ".join(crew.by_id.keys()),
		dispatch.describe_ai()])


## A field already in the ground, ripened, for screenshots and for anyone who
## wants to see the farming without waiting three in-game days for it.
func _demo_field() -> void:
	var found := farm.find_field(village.well_pos + Vector3(16, 0, 4), Vector2i(28, 24))
	if found.is_empty():
		return
	var rect: Rect2i = found["rect"]
	var work := FieldWork.new(farm, rect, "wheat")
	work.complete_now()
	farm.advance_days(9.0)
	print("[delegate] demo field: %s, %d ripe" % [work.summary(), farm.ripe_count()])
	var c := rect.get_center()
	var fx := float(c.x) * 0.25
	var fz := float(c.y) * 0.25
	showcase_views.append({
		"pos": Vector3(fx, world.ground_m(fx, fz) + 1.6, fz - 7.5),
		"yaw": PI, "pitch": -0.16, "hour": 10.0, "name": "field"})


## Picking a ripe crop. The only physical act the player has in the game, and
## deliberately so: pillar P1 forbids building, not living in the place.
func _on_harvest(tile: Vector2i) -> void:
	var kind := farm.harvest(tile)
	if kind != "":
		hud.toast("Picked %s.   food %d" % [kind, int(town.stock.get("food", 0))], 2.5)


## A finished building joins the town register, which is what the next prompt
## describes to the model as "what is already here".
func _on_job_done(worker: Worker, patch: VoxelPatch) -> void:
	var plot: Plot = null
	for p: Plot in village.plots:
		if p.id == patch.plot_id:
			plot = p
	if plot == null:
		return
	town.register(patch, plot, worker.memory.worker_id, clock.day)
	town.try_advance()


func build_context() -> Dictionary:
	return {
		"world": world, "village": village, "worldgen": gen, "tier": 1,
		"occupied_rects": [], "built_fronts": {},
	}


## Stands the founding buildings on the plots nearest the well.
##
## Temporary: once the workers are wired up they build these in response to
## instructions, which is the whole game. Until then an empty grid of streets is
## not something anyone can look at and judge.
func _found_town() -> void:
	var ctx := build_context()
	var specs := GenTest.specs()
	var near: Array[Plot] = village.plots.duplicate()
	near.sort_custom(func(a: Plot, b: Plot) -> bool:
		return a.centre_m().distance_to(village.well_pos) \
			< b.centre_m().distance_to(village.well_pos))

	var placed := 0
	for i in near.size():
		if placed >= specs.size():
			break
		var plot: Plot = near[i]
		var res := BuildingGenerator.build(specs[placed], 4242, plot, ctx)
		if not res["ok"]:
			print("[showcase] plot %d refused %s: %s" % [plot.id,
				specs[placed]["archetype"], res["error"]["code"]])
			continue
		var patch: VoxelPatch = res["patch"]
		var c := Construction.new(patch, world, props_root)
		c.complete_now()
		plot.occupied_by = placed
		ctx["occupied_rects"].append(patch.footprint)
		ctx["built_fronts"][plot.id] = patch.front
		map.note_building(patch, str(specs[placed]["archetype"]))
		print("[showcase] %s on plot %d" % [specs[placed]["archetype"], plot.id])
		if "--furniture" in OS.get_cmdline_user_args():
			_report_furniture(patch)
		if _room_shots:
			_record_room_views(str(specs[placed]["archetype"]), patch)
		elif _interior_shots:
			_record_interior_view(str(specs[placed]["archetype"]), patch)
		else:
			_record_view(str(specs[placed]["archetype"]), patch)
		showcase_patches.append(patch)
		placed += 1


## A camera standing in the middle of the biggest ground-floor room, at eye
## height. Interiors are the half of a building nobody sees in a hero shot and
## the half the player spends time in.
## One view per ground-floor room, from a corner looking across it. This is the
## only way to actually inspect furniture: a shot through the front door shows
## the entrance hall and nothing else.
## Every room and what ended up in it. A screenshot of one corner cannot
## answer "is any room bare", and a bare room is the thing that reads as
## unfinished.
func _report_furniture(patch: VoxelPatch) -> void:
	var by_module: Dictionary = {}
	for pr: Dictionary in patch.props:
		var m := str(pr.get("module", "?"))
		if not by_module.has(m):
			by_module[m] = []
		(by_module[m] as Array).append(str(pr.get("type", "?")))
	for mod: Dictionary in patch.modules:
		var t := str(mod.get("type", "?"))
		var r: Rect2i = mod["rect"]
		var items: Array = by_module.get(t, [])
		print("[furniture]   %-14s %4.1f x %4.1f m  story %d : %s" % [
			t, r.size.x * 0.25, r.size.y * 0.25, int(mod.get("story", 0)),
			"BARE" if items.is_empty() else ", ".join(items)])
		if int(mod.get("story", 0)) == 0:
			print("[furniture]                  floor: %s" % _floor_report(r))


## What the player is actually standing on in a room, counted across it.
## A room whose floor is grass is a room with no floor.
func _floor_report(r: Rect2i) -> String:
	var tally: Dictionary = {}
	for z in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			# The surface underfoot: the highest solid voxel that is not part
			# of the furniture, found from the terrain upward.
			var land := gen.height_at(x, z)
			var top := land
			for dy in range(0, 4):
				if world.is_solid(Vector3i(x, land + dy, z)):
					top = land + dy
			var name := VoxelTypes.name_of(world.get_voxel(Vector3i(x, top, z)))
			tally[name] = int(tally.get(name, 0)) + 1
	var parts: Array[String] = []
	for k: String in tally:
		parts.append("%s %d" % [k, int(tally[k])])
	return ", ".join(parts)


func _record_room_views(view_name: String, patch: VoxelPatch) -> void:
	for m: Dictionary in patch.modules:
		if int(m.get("story", 0)) != 0:
			continue
		var r: Rect2i = m["rect"]
		if r.size.x < 6 or r.size.y < 6:
			continue
		var cx := (r.position.x + r.size.x * 0.5) * 0.25
		var cz := (r.position.y + r.size.y * 0.5) * 0.25
		var floor_y := float(gen.height_at(int(cx / 0.25), int(cz / 0.25)) + 1) * 0.25
		# Stand at one end of the room's long axis looking down it. From a
		# corner you see two walls and a table leg.
		var along_x := r.size.x >= r.size.y
		var half := (r.size.x if along_x else r.size.y) * 0.25 * 0.5
		var step := maxf(half - 0.5, 0.4)
		var back := Vector3(-step, 0, 0) if along_x else Vector3(0, 0, -step)
		var eye := Vector3(cx, floor_y + 1.62, cz) + back
		var to := Vector3(cx, floor_y + 0.75, cz) - eye
		showcase_views.append({
			"pos": eye, "yaw": atan2(-to.x, -to.z),
			"pitch": atan2(to.y, Vector2(to.x, to.z).length()),
			"hour": 12.0,
			"name": "%s_%s" % [view_name, str(m.get("type", "room"))]})


func _record_interior_view(view_name: String, patch: VoxelPatch) -> void:
	if patch.doors.is_empty():
		return
	# Stand just inside the front door looking in — the way anyone actually
	# arrives in the room. Picking the biggest room and standing in the middle
	# of it kept putting the camera against a wall.
	var d: Vector3i = patch.doors[0]
	var f := Vector3(patch.front)
	var pos := VoxelWorld.centre_metres(d) - f * 1.1
	# Terrain height, not world height: ground_m() reports the top solid voxel in
	# the column, which for a building is its roof.
	var floor_y := float(gen.height_at(d.x, d.z) + 1) * 0.25
	showcase_views.append({
		"pos": Vector3(pos.x, floor_y + 1.55, pos.z), "yaw": atan2(f.x, f.z),
		"pitch": -0.05, "hour": 12.0, "name": "in_" + view_name})


func _record_view(view_name: String, patch: VoxelPatch) -> void:
	var f := Vector3(patch.front)
	var fr := patch.footprint
	var cx := (fr.position.x + fr.size.x * 0.5) * 0.25
	var cz := (fr.position.y + fr.size.y * 0.5) * 0.25
	var depth := (fr.size.x if absf(f.x) > 0.5 else fr.size.y) * 0.25
	var yaw := atan2(f.x, f.z)

	var stand := Vector3(cx, 0.0, cz) + f * (depth * 0.5 + 13.0)
	stand.y = world.ground_m(stand.x, stand.z) + 0.1
	showcase_views.append({"pos": stand, "yaw": yaw, "pitch": 0.05,
		"hour": 10.5, "name": view_name})


## Stands the whole cast in a row facing the camera. Purely for looking at
## them: three workers and three species is the entire population of the
## game, and they have to be tellable apart at a glance.
func _line_up_cast() -> void:
	var base := village.well_pos + Vector3(0, 0, 14.0)
	base.y = world.ground_m(base.x, base.z) + 0.2
	for i in crew.workers.size():
		var w: Worker = crew.workers[i]
		w.employer = null
		w.global_position = base + Vector3((i - 1) * 1.5, 0.0, 0.0)
		w.rotation.y = PI
		w.set_physics_process(false)
	var species := ["hen", "sheep", "cow"]
	for i in species.size():
		var spot := base + Vector3((i - 1) * 2.4, 0.0, -2.6)
		livestock.stock_area(str(species[i]), spot, 1, 0.1)
	for a: Animal in livestock.animals:
		if a.global_position.distance_to(base) < 6.0:
			a.avoid = null
			a.rotation.y = PI
			a.set_physics_process(false)
	# A camera at yaw 0 looks toward -Z, so one standing behind the line at -Z
	# has to be turned right round to see it. Livestock in front, crew behind,
	# so one frame holds the entire population of the game.
	showcase_views = [
		{"pos": base + Vector3(0, 1.35, -8.5), "yaw": PI, "pitch": -0.10,
			"hour": 11.0, "name": "cast"},
		{"pos": base + Vector3(0, 0.75, -5.0), "yaw": PI, "pitch": -0.05,
			"hour": 11.0, "name": "cast_close"},
	]


func _install_shotter() -> void:
	var s := Shotter.new()
	s.world = world
	s.player = player
	s.sky = sky
	var well := village.well_pos
	s.views = showcase_views.duplicate()
	if _interior_shots or "--cast" in OS.get_cmdline_user_args():
		add_child(s)
		return
	# The crew and the livestock live round the well, so that is the shot that
	# shows the game rather than the architecture.
	s.views.push_front({"pos": well + Vector3(3.0, 1.5, 11.0), "yaw": 0.15,
		"pitch": -0.09, "hour": 9.5, "name": "crew"})
	s.views.append({"pos": well + Vector3(0, 34.0, 54), "yaw": 0.0,
		"pitch": -0.45, "hour": 14.0, "name": "aerial"})
	if s.views.size() < 3:
		s.views = [
			{"pos": well + Vector3(0, 0.2, 13), "yaw": 0.0, "pitch": 0.02,
				"hour": 9.0, "name": "well"},
			{"pos": well + Vector3(0, 34.0, 54), "yaw": 0.0, "pitch": -0.45,
				"hour": 14.0, "name": "aerial"},
		]
	add_child(s)
