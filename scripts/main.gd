extends Node3D
## DELEGATE — boot.
##
## The world has no edges: chunks stream in around the player and forget
## themselves behind him. Only the village is pinned, because it is the one
## place the game is actually about.

## 64 m of vertical range at 0.25 m. Six chunks was 48 m, and with the ground
## sitting around twelve there was not room over it for the tall archetypes —
## a ten-floor block is 32 m of wall before the roof goes on. The extra layer
## is almost all empty sky, which the mesher skips and the streamer barely
## notices.
const WORLD_HEIGHT_CHUNKS := 8

var world: VoxelWorld
var gen: WorldGen
var village: Village
var streamer: ChunkStreamer
var far: FarTerrain
var sky: SkyEnv
var player: Player
var map: MapScreen
var inventory: InventoryScreen
var touch: TouchControls
var props_root: Node3D
var clock: GameClock
var nav: NavGrid
var town: Town
var crew: Crew
var dispatch: Dispatcher
var hud: Hud
var title: TitleScreen
var pause_menu: PauseMenu
var farm: Farm
var livestock: Livestock
var wildlife: Wildlife
var warfare: Warfare
var realm: Realm
var audio: AudioDirector
# Features: photo mode and the weekly challenge (see _raise_extras).
var photo: PhotoMode
var challenge: Challenge
var challenge_screen: ChallengeScreen
## Village identity, milestones and the guided first day (see _raise_village_life).
var identity: VillageIdentity
var progression: Progression
var milestones_ui: MilestonesUi
var tutorial: Tutorial

var _world_seed := 0
var showcase_views: Array[Dictionary] = []
var showcase_patches: Array[VoxelPatch] = []
var _interior_shots := false
var _room_shots := false
## The save being loaded, until the town is stood up from it; then empty.
var _save: Dictionary = {}
const AUTOSAVE_SECONDS := 120.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_world_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	for arg in args:
		if arg.begins_with("--seed="):
			_world_seed = int(arg.substr(7))

	# Tests, benches and screenshots never touch a real save: they neither
	# start from one nor leave one behind.
	for arg2 in args:
		if arg2.find("test") >= 0 or arg2.find("bench") >= 0 or arg2.find("shot") >= 0 \
				or arg2 == "--nosave" or arg2 == "--probe" or arg2.find("probe") >= 0:
			SaveGame.enabled = false
	# Except the save test, which is the one test that is about saves. It gets
	# a scratch file of its own, wiped before its first boot so a stale one
	# from a crashed run cannot pass for a fresh save.
	if "--savetest" in args:
		SaveGame.path = "user://save/_savetest.save"
		SaveGame.enabled = true
		if not SaveTest.second_boot:
			SaveGame.erase()
	# Weekly challenge: which save slot this boot uses (see Challenge.boot).
	Challenge.boot(args)
	# The seed is the world; a save carries its own and overrides the clock's.
	if "--fresh" not in args:
		_save = SaveGame.read()
		if not _save.is_empty():
			_world_seed = int(_save.get("seed", _world_seed))
			print("[delegate] loading the town saved %s" % str(_save.get("written", "?")))
	if Challenge.mode and _save.is_empty():
		var cw := Challenge.current_week()
		_world_seed = int(Challenge.for_week(int(cw["year"]), int(cw["week"]))["world_seed"])

	# Who is founding this village, and on what land. A save carries its own; a
	# new game takes what the title screen left (see VillageIdentity.pending).
	if not _save.is_empty():
		identity = VillageIdentity.from_dict(_save.get("identity", {}))
	elif VillageIdentity.pending != null:
		identity = VillageIdentity.pending
	else:
		identity = VillageIdentity.new()
		if _is_interactive_launch(args):
			identity.landscape = "meadow"     # tests and tools keep the classic terrain
	for arg3 in args:
		if arg3.begins_with("--landscape=") and VillageIdentity.LANDSCAPES.has(arg3.substr(12)):
			identity.landscape = arg3.substr(12)
		elif arg3.begins_with("--vname="):
			identity.village_name = VillageIdentity.sanitise(arg3.substr(8))

	sky = SkyEnv.new()
	add_child(sky)

	village = Village.new()
	village.build(_world_seed)

	gen = WorldGen.new()
	gen.landscape = identity.landscape
	gen.setup(_world_seed, village)

	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	add_child(world)
	world.configure(WORLD_HEIGHT_CHUNKS)
	if not _save.is_empty():
		# Before prime(): every changed chunk is then simply picked up as its
		# column comes in, the same way a building survives being walked
		# away from.
		world.import_edits(_save.get("world", {}))

	Ambience.clear_sources()      # smoke/sparks registry is static; start clean
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

	# Sound (scripts/audio/): created here so the title screen's buttons click;
	# bound to the game's systems in _raise_audio() once they exist.
	if "--nosound" not in args:
		audio = AudioDirector.new()
		audio.name = "Audio"
		add_child(audio)

	# The front door, only on a plain interactive launch: no test, bench, shot
	# or other dev flag. It holds the clock and the player until "Begin".
	# A reload into or out of a challenge goes straight to the village.
	if _is_interactive_launch(args) and not Challenge.skip_title:
		PauseMenu.start_fullscreen(args)
		title = TitleScreen.new()
		title.name = "Title"
		add_child(title)
		title.setup(player, clock)
		title.configure(identity, gen.landscape, not _save.is_empty(), _world_seed)

	town = Town.new()

	map = MapScreen.new()
	map.name = "Map"
	add_child(map)
	map.setup(world, gen, village, player)

	inventory = InventoryScreen.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.setup(town, player, map)

	touch = TouchControls.new()
	touch.name = "Touch"
	touch.player = player
	touch.map = map
	touch.inventory = inventory
	add_child(touch)

	if "--streamtest" in args:
		var st := StreamTest.new()
		st.world = world
		st.gen = gen
		st.village = village
		add_child(st)
		get_tree().quit(st.run())
		return
	if "--plantest" in args:
		await streamer.first_load_done
		var pt := PlanTest.new()
		pt.world = world
		pt.village = village
		pt.gen = gen
		add_child(pt)
		get_tree().quit(pt.run())
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


## How often the nav grid is asked whether any more of the world has arrived.
## Twice a second: the streamer cannot load faster than that in any case, and a
## pass that finds nothing new costs a dictionary lookup per column.
const NAV_CATCH_UP := 0.5
var _nav_due := 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	if far != null:
		far.refresh(player.global_position)
	if nav != null:
		_nav_due -= delta
		if _nav_due <= 0.0:
			_nav_due = NAV_CATCH_UP
			nav.catch_up(player.global_position)


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
		# Everyone who walks and is not the player needs a floor: the crew,
		# the army, the raiders, and the animals out past the streets. The
		# world only carries collision near the player otherwise, and a body
		# stood on ground with no collision under it falls out of the game.
		var here: Array[Vector3] = []
		for w: Worker in crew.workers:
			here.append(w.global_position)
		if warfare != null:
			for f: Fighter in warfare.soldiers:
				if is_instance_valid(f):
					here.append(f.global_position)
			for f: Fighter in warfare.raiders:
				if is_instance_valid(f):
					here.append(f.global_position)
		if wildlife != null:
			for a: Animal in wildlife.beasts:
				if is_instance_valid(a) and a.is_physics_processing():
					here.append(a.global_position)
		if livestock != null:
			for a: Animal in livestock.animals:
				if is_instance_valid(a) and a.is_physics_processing():
					here.append(a.global_position)
		world.set_agents(here)
		# And the same guarantee the player gets: a chunk whose collision has
		# not been baked yet is built on the spot. set_agents only attaches
		# shapes that already exist, which out past the streets is none of
		# them, and a raider stood on an unbaked chunk fell out of the game.
		for p: Vector3 in here:
			world.ensure_support(p)


## True for a normal player launch. Any flag other than the harmless ones
## (seed, fresh, windowed) marks a test, bench or capture run.
func _is_interactive_launch(args: PackedStringArray) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for a in args:
		if not (a.begins_with("--seed=") or a == "--fresh" or a == "--windowed" or a == "--touchui" or a == "--titleshot" or a.begins_with("--uishotdir=")):
			return false
	return true


func _on_world_ready(t0: int) -> void:
	print("[delegate] world ready in %d ms: %d columns, %d chunks, %d mesh nodes" % [
		Time.get_ticks_msec() - t0, world.loaded_columns(),
		world.chunk_count(), world.mesh_node_count()])
	if title != null:
		title.ready_to_play()
		if "--titleshot" in OS.get_cmdline_user_args():
			var ts := UiShot.new()
			add_child(ts)
			ts.run_title()
	var g := world.ground_m(player.global_position.x, player.global_position.z)
	player.teleport(Vector3(player.global_position.x, g + 0.4,
		player.global_position.z), PI)

	var args := OS.get_cmdline_user_args()
	_room_shots = "--rooms" in args or "--flicker" in args
	_interior_shots = "--inside" in args or _room_shots
	# A saved town has its founding buildings in the world already, and their
	# records in the save; founding it again would put a second bakery in the
	# first one.
	if "--empty" not in args and _save.is_empty():
		_found_town()
	elif not _save.is_empty():
		_restore_town()

	# After the founding buildings: the nav grid reads the world as it stands,
	# and a crew that pathed through the bakery would look ridiculous.
	if "--nocrew" not in args:
		_raise_crew()
		if not _save.is_empty():
			_restore_people()
		_arm_saving()
		if Challenge.mode and challenge != null and challenge.spec.is_empty():
			var w := Challenge.current_week()
			challenge.begin(Challenge.for_week(int(w["year"]), int(w["week"])))
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
	if "--routetest" in args:
		var rt := RouteTest.new()
		rt.dispatch = dispatch
		rt.crew = crew
		rt.clock = clock
		rt.town = town
		rt.world = world
		add_child(rt)
		var say2 := ""
		for a in args:
			if a.begins_with("--say="):
				say2 = a.substr(6)
		rt.begin(say2)
		return
	if "--uiflow" in args:
		# The game driven through its interface: talk, type, tap a phrase,
		# open and close every screen. See scripts/dev/ui_flow.gd.
		var uf := UiFlow.new()
		uf.hud = hud
		uf.crew = crew
		uf.player = player
		uf.map = map
		uf.inventory = inventory
		uf.pause = pause_menu
		add_child(uf)
		uf.begin()
		return
	if "--featureshot" in args:
		var fs := FeatureShot.new()
		fs.main = self
		add_child(fs)
		fs.begin()
		return
	if "--challengetest" in args:
		var cht := ChallengeTest.new()
		cht.clock = clock
		cht.town = town
		cht.dispatch = dispatch
		cht.realm = realm
		cht.crew = crew
		add_child(cht)
		get_tree().quit(cht.run())
		return
	if "--costrun" in args:
		# A scripted first session, for reading the cost of each thing a
		# player does off the gateway's log. See scripts/dev/cost_run.gd.
		var cr := CostRun.new()
		cr.dispatch = dispatch
		cr.crew = crew
		cr.clock = clock
		add_child(cr)
		cr.begin()
		return
	if "--playertest" in args:
		# PlayerTest is the adversarial one: nonsense, insults, empty input,
		# impossible orders, the same order three times, and every worker told
		# to build at the same moment. See the file for the three rules.
		var pt := PlayerTest.new()
		pt.dispatch = dispatch
		pt.crew = crew
		pt.clock = clock
		pt.town = town
		pt.world = world
		pt.village = village
		add_child(pt)
		var say4 := ""
		for a in args:
			if a.begins_with("--say="):
				say4 = a.substr(6)
		pt.begin(say4)
		return
	if "--tasktest" in args:
		# TaskTest is the one that checks outcomes rather than routing: a
		# sentence goes to a real worker and the harness watches for the
		# effect. See the file for why that is not the same as RouteTest.
		var tt := TaskTest.new()
		tt.dispatch = dispatch
		tt.crew = crew
		tt.clock = clock
		tt.town = town
		tt.world = world
		tt.village = village
		add_child(tt)
		var say3 := ""
		for a in args:
			if a.begins_with("--say="):
				say3 = a.substr(6)
		tt.begin(say3)
		return
	if "--sitefx" in args:
		var sf := SiteFxShot.new()
		sf.world = world
		sf.player = player
		sf.crew = crew
		sf.dispatch = dispatch
		sf.clock = clock
		sf.town = town
		sf.sky = sky
		sf.village = village
		add_child(sf)
		sf.begin()
		return
	if "--gestures" in args:
		var gt := GestureTest.new()
		gt.world = world
		gt.player = player
		gt.sky = sky
		gt.crew = crew
		gt.village = village
		add_child(gt)
		gt.begin()
		return
	if "--econtest" in args:
		var et := EconomyTest.new()
		et.world = world
		et.gen = gen
		et.village = village
		et.crew = crew
		et.dispatch = dispatch
		et.nav = nav
		et.clock = clock
		et.town = town
		add_child(et)
		et.begin()
		return
	if "--savetest" in args:
		var svt := SaveTest.new()
		svt.main = self
		svt.crew = crew
		svt.dispatch = dispatch
		svt.clock = clock
		svt.town = town
		svt.player = player
		svt.livestock = livestock
		svt.world = world
		add_child(svt)
		svt.begin()
		return
	if "--roletest" in args:
		var rt := RoleTest.new()
		rt.crew = crew
		rt.dispatch = dispatch
		rt.clock = clock
		rt.town = town
		rt.player = player
		rt.farm = farm
		rt.livestock = livestock
		rt.world = world
		add_child(rt)
		rt.begin()
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
	if "--floorprobe" in args:
		var fp := FloorProbe.new()
		fp.world = world
		fp.village = village
		fp.warfare = warfare
		fp.nav = nav
		add_child(fp)
		return
	if "--wartest" in args:
		var wt2 := WarTest.new()
		wt2.world = world
		wt2.village = village
		wt2.crew = crew
		wt2.dispatch = dispatch
		wt2.clock = clock
		wt2.town = town
		wt2.player = player
		wt2.warfare = warfare
		wt2.props_root = props_root
		wt2.farm = farm
		wt2.livestock = livestock
		wt2.wildlife = wildlife
		add_child(wt2)
		wt2.begin()
		return
	if "--wildprobe" in args:
		var wp := WildProbe.new()
		wp.player = player
		wp.world = world
		wp.village = village
		wp.sky = sky
		wp.wildlife = wildlife
		add_child(wp)
		return
	if "--zoo" in args:
		var zs := ZooShot.new()
		zs.player = player
		zs.world = world
		zs.village = village
		zs.sky = sky
		zs.clock = clock
		zs.livestock = livestock
		zs.wildlife = wildlife
		zs.crew = crew
		add_child(zs)
		return
	if "--chatprobe" in args:
		var cp := ChatProbe.new()
		cp.dispatch = dispatch
		cp.crew = crew
		cp.world = world
		add_child(cp)
		var ask := ""
		for a in args:
			if a.begins_with("--say="):
				ask = a.substr(6)
		cp.begin(ask)
		return
	# One door for the kingdom's own tests: `--realmtest=market` loads
	# res://scripts/dev/realm/market_test.gd, hands it everything, and lets it
	# run. A system's test lives beside the system and needs no line here.
	for a in args:
		if a.begins_with("--realmtest="):
			_run_realm_test(a.substr(12))
			return
	if "--asktest" in args:
		var qt := AskTest.new()
		qt.world = world
		qt.village = village
		qt.crew = crew
		qt.dispatch = dispatch
		qt.clock = clock
		qt.town = town
		qt.player = player
		qt.farm = farm
		qt.livestock = livestock
		add_child(qt)
		qt.begin()
		return
	if "--holdtest" in args:
		var ht := HoldTest.new()
		ht.world = world
		ht.village = village
		ht.crew = crew
		ht.clock = clock
		ht.player = player
		add_child(ht)
		ht.begin()
		return
	if "--invshot" in args:
		var iv := InvShot.new()
		iv.player = player
		iv.inventory = inventory
		iv.town = town
		add_child(iv)
		return
	if "--audiotest" in args:
		# Sound: the soundscape driven through a day, a storm and a night.
		var aut := AudioTest.new()
		aut.main = self
		add_child(aut)
		aut.begin()
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
		b.nav = nav
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
	if "--uishot" in args:
		var us := UiShot.new()
		us.hud = hud
		us.map = map
		us.inventory = inventory
		us.pause = pause_menu
		us.player = player
		us.crew = crew
		us.clock = clock
		add_child(us)
		us.run()
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
		if "--openbar" in args and not crew.workers.is_empty():
			hud.open_for(crew.workers[0])
	for flag in ["--shot", "--inside", "--rooms", "--cast"]:
		if flag in args:
			_install_shotter()
			break


## Brings the three of them on. They spawn at the well and then follow you
## about, because an instruction you have to walk home to give is an instruction
## you do not give.
func _raise_crew() -> void:
	nav = NavGrid.new()
	# 160 voxels — forty metres of open country outside the last plot. The crew
	# never needed it when all they did was build, but fetching stone is a walk
	# out of town and back, and there has to be a town to be out of.
	# The flood fill that keeps the crew off the rooftops needs one piece of
	# ground it can trust. The plaza is it.
	nav.set_ground_seed(village.well_pos)
	var t_nav := Time.get_ticks_msec()
	nav.build(world, village.nav_bounds_v(160))
	print("[delegate] nav grid %d x %d cells in %d ms" % [
		nav.size.x, nav.size.y, Time.get_ticks_msec() - t_nav])

	crew = Crew.new()
	crew.name = "Crew"
	add_child(crew)
	crew.spawn(world, nav, clock, town, player, village.well_pos)
	# People in the streets. --nocitizens for the benches, which time the crew
	# and not the crowd.
	if "--nocitizens" not in OS.get_cmdline_user_args():
		crew.spawn_citizens(Crew.CITIZENS, _world_seed ^ 0x5EED, village.bounds_v)

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
	livestock.stock_area("rooster", village.well_pos + Vector3(8, 0, -3), 1, 2.0)
	livestock.stock_area("sheep", village.well_pos + Vector3(-13, 0, 9), 3, 8.0)
	livestock.stock_area("goat", village.well_pos + Vector3(-16, 0, -6), 2, 5.0)

	# Everything nobody owns: birds on the ridges, fish in the water, deer past
	# the last street, a dog by the well. Kept stocked around the player and
	# nowhere else.
	wildlife = Wildlife.new()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.setup(world, clock, town, village, player)

	# The army and the enemy. Nothing hostile exists until the town has an
	# armoury or a barracks to be worth raiding.
	warfare = Warfare.new()
	warfare.name = "Warfare"
	add_child(warfare)
	warfare.setup(world, nav, town, village, clock, player, crew, livestock, wildlife)
	player.warfare = warfare

	if "--demo" in OS.get_cmdline_user_args():
		_demo_field()

	dispatch = Dispatcher.new()
	dispatch.name = "Dispatcher"
	add_child(dispatch)
	dispatch.setup(world, village, gen, town, clock, nav, props_root, map)
	dispatch.farm = farm
	dispatch.livestock = livestock
	dispatch.wildlife = wildlife
	dispatch.warfare = warfare
	dispatch.player = player
	# The dispatcher needs the whole crew, not just whoever was spoken to: a
	# shortfall is answered by sending somebody *else* out to dig.
	dispatch.crew = crew

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(player, crew, clock, town)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(player, title != null)
	# Nothing of the game's own interface shows through the front door.
	if title != null:
		hud.visible = false
		touch.visible = false
		NameTag.hidden = true
		title.begun.connect(func() -> void:
			hud.visible = true
			touch.visible = true
			NameTag.hidden = false)

	hud.show_minimap(village, map, crew, inventory)
	# The town trades overnight. Connected here rather than inside Town so the
	# clock stays something Town is handed rather than something it listens to.
	clock.day_passed.connect(func(_d: int) -> void: town.market_day())
	hud.harvest_wanted.connect(_on_harvest)
	hud.instruction_given.connect(func(w: Worker, t: String) -> void:
		dispatch.instruct(w, t))
	hud.answer_given.connect(func(w: Worker, t: String) -> void:
		dispatch.answer(w, t))
	dispatch.plan_accepted.connect(func(w: Worker, a: Array) -> void:
		hud.show_assumptions(w, a))
	dispatch.status.connect(func(t: String) -> void: hud.toast(t))
	warfare.status.connect(func(t: String) -> void: hud.toast(t, 6.0))
	hud.warfare = warfare

	# The kingdom: everything that makes the town a place rather than a
	# building site. One hub; every system of it plugs into that.
	if "--norealm" not in OS.get_cmdline_user_args():
		_raise_realm()
	# --- village ambience: chimney smoke, forge sparks, fireflies, butterflies ---
	if "--noambience" not in OS.get_cmdline_user_args():
		var amb := Ambience.new()
		amb.name = "Ambience"
		add_child(amb)
		amb.setup(world, player, clock)
		amb.realm = realm
	_raise_village_life()
	crew.worker_spoke.connect(hud.subtitle)
	# A held plan is the one refusal the player can act on, so it goes up as an
	# assumption panel rather than a toast that scrolls away.
	dispatch.short_of.connect(func(w: Worker, missing: Dictionary) -> void:
		var lines: Array = ["The stores cannot cover this yet."]
		for mat: String in missing:
			lines.append("Short %d %s." % [int(missing[mat]),
				mat.replace("_", " ")])
		lines.append("%s is holding the plan until it is in."
			% w.display_name())
		hud.show_assumptions(w, lines))
	crew.job_done.connect(_on_job_done)
	crew.job_failed.connect(func(w: Worker, e: Dictionary) -> void:
		hud.toast("%s: %s" % [w.display_name(),
			str(e.get("question", e.get("code", "refused")))], 5.0))

	print("[delegate] crew: %s   (AI: %s)" % [", ".join(crew.by_id.keys()),
		dispatch.describe_ai()])
	_raise_audio()
	_raise_extras()


## Sound (scripts/audio/): hands the audio director the finished game.
func _raise_audio() -> void:
	if audio == null:
		return
	audio.bind({"player": player, "world": world, "clock": clock, "realm": realm,
		"crew": crew, "livestock": livestock, "warfare": warfare, "map": map,
		"inventory": inventory, "pause_menu": pause_menu, "town": town})


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
		hud.toast("Picked %s.   sold for %d." % [kind, 3 * int(Town.PRICE["food"])], 2.5)


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


## Photo mode (key P, pause menu, touch button) and the weekly challenge
## (pause menu, `--challenge`). Both are self-contained; this only wires them.
func _raise_extras() -> void:
	photo = PhotoMode.new()
	photo.name = "PhotoMode"
	photo.player = player
	photo.hud = hud
	photo.clock = clock
	photo.sky = sky
	photo.realm = realm
	photo.town = town
	photo.crew = crew
	photo.world = world
	photo.dispatch = dispatch
	photo.touch = touch
	photo.pause_menu = pause_menu
	add_child(photo)
	photo.setup()

	challenge = Challenge.new()
	challenge.name = "Challenge"
	add_child(challenge)
	challenge.bind(clock, town, dispatch, realm, crew)
	challenge_screen = ChallengeScreen.new()
	challenge_screen.name = "ChallengeScreen"
	add_child(challenge_screen)
	challenge_screen.setup(challenge, player)
	challenge_screen.start_requested.connect(_switch_world.bind(true))
	challenge_screen.leave_requested.connect(func() -> void: _switch_world(false, false))
	hud.challenge_card.bind(challenge, clock)
	pause_menu.photo_requested.connect(photo.open_from_pause)
	pause_menu.challenge_requested.connect(challenge_screen.open_screen)
	pause_menu.set_challenge_label(Challenge.mode)
	challenge.finished.connect(func(res: Dictionary) -> void:
		_save_now("challenge")
		hud.toast("Weekly challenge: %s" % ("complete!" if bool(res["success"])
			else "not this time."), 6.0)
		if not photo.active:
			challenge_screen.open_screen())


## Into a challenge world (`into` true; `fresh` per the button) or back to the
## village. The current slot is saved first, then the scene is reloaded and
## Challenge.boot points the save at the right file.
func _switch_world(fresh: bool, into: bool) -> void:
	_save_now("switch")
	if into:
		Challenge.request(fresh)
	else:
		Challenge.leave()
	get_tree().paused = false
	get_tree().reload_current_scene()

# ------------------------------------------------------------ village life

## The village's name and banner, its rank and milestones, and the guided first
## day. Built once the HUD, dispatcher and (optionally) realm exist.
func _raise_village_life() -> void:
	var args := OS.get_cmdline_user_args()
	if identity.village_name == "" and _save.is_empty():
		identity.village_name = VillageIdentity.default_name(_world_seed)
	map.identity = identity

	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.setup(town, crew, clock, farm, realm, dispatch)
	if not _save.is_empty():
		# People are restored one signal at a time; nothing is paid for that.
		progression.begin_silent()

	milestones_ui = MilestonesUi.new()
	milestones_ui.name = "MilestonesUi"
	add_child(milestones_ui)
	milestones_ui.setup(progression, identity, player, hud, map, inventory)

	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	tutorial.setup(hud, crew, dispatch, town, map, player, clock, milestones_ui)
	tutorial.village_name = identity.village_name
	# The first day is for a brand-new game that a person is actually playing.
	if _save.is_empty() and (title != null or "--tutorial" in args):
		if title != null:
			title.begun.connect(func() -> void:
				tutorial.village_name = identity.village_name
				tutorial.start())
		else:
			tutorial.start()
	else:
		tutorial.complete = true

	_apply_identity()
	if title != null:
		title.begun.connect(_apply_identity)


## The name in the kingdom (which the villagers' prompts already read), on the
## HUD card and on the map.
func _apply_identity() -> void:
	if identity.village_name == "" and _save.is_empty():
		identity.village_name = VillageIdentity.default_name(_world_seed)
	if realm != null and identity.village_name != "":
		realm.kingdom_name = identity.village_name
	if milestones_ui != null:
		milestones_ui.refresh()


## After the crew and realm are restored from a save.
func _restore_village_life() -> void:
	if progression == null:
		return
	if _save.has("progression"):
		progression.restore(_save["progression"])
	else:
		progression.end_silent()       # an older save: no fanfare for what it already did
	tutorial.restore(_save.get("tutorial", {}))
	_apply_identity()


# ------------------------------------------------------------------ saving

func _raise_realm() -> void:
	realm = Realm.new()
	realm.name = "Realm"
	add_child(realm)
	realm.setup({
		"world": world, "village": village, "town": town, "clock": clock,
		"player": player, "crew": crew, "livestock": livestock,
		"wildlife": wildlife, "warfare": warfare, "nav": nav,
		"props_root": props_root, "farm": farm, "dispatch": dispatch, "hud": hud,
		"sky": sky, "map": map, "inventory": inventory,
	})
	realm.status.connect(func(t: String) -> void: hud.toast(t, 6.0))
	dispatch.realm = realm
	hud.realm = realm
	# The map's directory of buildings and people reads from the realm.
	map.realm = realm


func _run_realm_test(which: String) -> void:
	var path := "res://scripts/dev/realm/%s_test.gd" % which
	if not ResourceLoader.exists(path):
		printerr("[delegate] no such realm test: %s" % path)
		get_tree().quit(2)
		return
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		printerr("[delegate] realm test %s does not compile" % path)
		get_tree().quit(2)
		return
	var t: Node = script.new()
	for key in ["world", "village", "town", "clock", "player", "crew", "livestock",
			"wildlife", "warfare", "nav", "farm", "dispatch", "hud", "realm", "map",
			"sky", "props_root", "inventory"]:
		if key in t:
			t.set(key, get(key))
	add_child(t)
	if t.has_method("begin"):
		t.call("begin")


## Everything worth keeping, as one dictionary. See SaveGame for what is and
## is not in it.
func _snapshot() -> Dictionary:
	# Pay anything already earned first, so the purse and the milestone record
	# written below agree and a load never pays the same reward again.
	if progression != null:
		progression.evaluate()
	var state := {
		"seed": _world_seed,
		"clock": {"day": clock.day, "hour": clock.hour},
		"player": {"pos": player.global_position, "yaw": player.yaw},
		"town": town.snapshot(),
		"world": world.export_edits(),
	}
	if crew != null:
		state["crew"] = crew.snapshot()
		state["roles"] = crew.roles.to_dict()
	if farm != null:
		state["farm"] = farm.snapshot()
	if livestock != null:
		state["livestock"] = livestock.snapshot()
	if realm != null:
		state["realm"] = realm.snapshot()
	if hud != null and hud.chat != null:
		state["chat"] = hud.chat.snapshot()
	# Weekly challenge run in progress (absent from an ordinary town's save).
	if challenge != null and not challenge.spec.is_empty():
		state["challenge"] = challenge.snapshot()
	if identity != null:
		state["identity"] = identity.to_dict()
	if progression != null:
		state["progression"] = progression.snapshot()
	if tutorial != null:
		state["tutorial"] = tutorial.snapshot()
	return state


func _save_now(why: String) -> void:
	if not SaveGame.enabled or crew == null:
		return
	var t0 := Time.get_ticks_msec()
	var state := _snapshot()
	var t1 := Time.get_ticks_msec()
	if SaveGame.write(state):
		if Challenge.mode:
			Challenge.write_meta(challenge)
		print("[delegate] saved (%s) in %d ms: %d gathering, %d writing" % [
			why, Time.get_ticks_msec() - t0, t1 - t0, Time.get_ticks_msec() - t1])
		if hud != null and why != "morning":
			hud.toast("Saved.", 2.0)


## The register and the furniture. The buildings' voxels are already in the
## world, restored with the chunks; this puts the records back so the town
## knows what they are, and the props back so they are not empty shells.
func _restore_town() -> void:
	town.restore(_save.get("town", {}), village)
	for rec: Dictionary in town.buildings:
		var patch: VoxelPatch = rec["patch"]
		Construction.new(patch, world, props_root).respawn_props()
		map.note_building(patch, str(rec["archetype"]))
		showcase_patches.append(patch)
	var c: Dictionary = _save.get("clock", {})
	clock.day = int(c.get("day", clock.day))
	clock.hour = float(c.get("hour", clock.hour))
	print("[delegate] restored %d buildings, day %d" % [town.buildings.size(), clock.day])


## The people, their jobs and memories, the fields and the flock. After the
## crew is raised from the seed, so the same seed gives the same people and
## each is then told who they had become.
func _restore_people() -> void:
	crew.roles.from_dict(_save.get("roles", {}))
	crew.restore(_save.get("crew", []))
	if farm != null:
		farm.restore(_save.get("farm", []))
	if livestock != null:
		livestock.restore(_save.get("livestock", []))
	if realm != null:
		realm.restore(_save.get("realm", {}))
	if hud != null and hud.chat != null:
		hud.chat.restore(_save.get("chat", {}))
	if challenge != null:
		challenge.restore(_save.get("challenge", {}))
	_restore_village_life()
	var pl: Dictionary = _save.get("player", {})
	if pl.has("pos"):
		var at: Vector3 = pl["pos"]
		player.teleport(Vector3(at.x, world.ground_m(at.x, at.z) + 0.4, at.z),
			float(pl.get("yaw", PI)))
	print("[delegate] restored %d people (%d hired), %d roles, %d tiles, %d animals" % [
		crew.workers.size(), crew.hired().size(), crew.roles.custom().size(),
		farm.tile_count() if farm != null else 0,
		livestock.total() if livestock != null else 0])
	_save = {}


## When the town is written down: each morning, every couple of minutes, when
## asked, and on the way out.
func _arm_saving() -> void:
	if not SaveGame.enabled:
		return
	clock.day_passed.connect(func(_d: int) -> void: _save_now("morning"))
	var t := Timer.new()
	t.wait_time = AUTOSAVE_SECONDS
	t.autostart = true
	t.timeout.connect(func() -> void: _save_now("autosave"))
	add_child(t)
	dispatch.save_requested.connect(func() -> void: _save_now("asked"))
	dispatch.restart_requested.connect(func() -> void:
		SaveGame.erase()
		SaveGame.enabled = false            # do not write the old town on the way out
		get_tree().reload_current_scene())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and SaveGame.enabled:
		_save_now("quit")


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
		# On the register like anything the crew builds, with no builder and
		# day zero. Left off it — which is how this was — the workers could
		# not tell you where the bakery was, and the model was planning a town
		# it had been told was empty.
		town.register(patch, plot, "", 0)
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
	var cast := crew.hired()
	for i in cast.size():
		var w: Worker = cast[i]
		w.employer = null
		w.global_position = base + Vector3((i - 1) * 1.5, 0.0, 0.0)
		w.rotation.y = PI
		w.set_physics_process(false)
	# --ask="where is the bakery?" puts a question to Mira before the frame is
	# taken, so the crew shot shows an answer over her head.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ask=") and dispatch != null:
			dispatch.instruct(crew.workers[0], a.substr(6))
	var species := ["hen", "sheep", "cow"]
	for i in species.size():
		var spot := base + Vector3((i - 1) * 1.9, 0.0, -3.0)
		livestock.stock_area(str(species[i]), spot, 1, 0.1)
	# Livestock._process turns physics back on for anything near the player,
	# and on ground that has not streamed in yet the animal then falls through
	# the world. So the cast is taken out of the flock's hands: pinned to the
	# ground height, facing the camera, with physics off for good.
	var posed: Array[Animal] = []
	for a: Animal in livestock.animals:
		if a.global_position.distance_to(base) < 6.0:
			a.avoid = null
			a.rotation.y = PI
			a.set_physics_process(false)
			a.global_position.y = world.ground_m(a.global_position.x, a.global_position.z)
			a.visible = true
			posed.append(a)
	for a: Animal in posed:
		livestock.animals.erase(a)
	# A camera at yaw 0 looks toward -Z, so one standing behind the line at -Z
	# has to be turned right round to see it. Livestock in front, crew behind,
	# so one frame holds the entire population of the game.
	showcase_views = [
		{"pos": base + Vector3(0, 1.35, -9.5), "yaw": PI, "pitch": -0.10,
			"hour": 11.0, "name": "cast"},
		{"pos": base + Vector3(0, 0.75, -6.4), "yaw": PI, "pitch": -0.05,
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
	# The long view down the town, from the last street rather than from the
	# middle of it. Taken as a fraction of the shelf because the shelf moved:
	# the block pitch went from twenty-six metres to forty, and the old fixed
	# fifty-four metres is now a spot inside somebody's bakery. Kept just short
	# of the shelf edge, since a step past that is the lake.
	var span := village.bounds_v.size.x * VoxelChunk.VOXEL_M
	s.views.append({"pos": well + Vector3(0, 34.0, span * 0.46),
		"yaw": 0.0, "pitch": -0.2, "hour": 14.0, "name": "aerial"})
	# The same view after dark, because a fill light generous enough to make the
	# morning readable is exactly the one that ruins the night.
	s.views.append({"pos": well + Vector3(3.0, 1.5, 11.0), "yaw": 0.15,
		"pitch": -0.09, "hour": 22.0, "name": "night"})
	if s.views.size() < 3:
		s.views = [
			{"pos": well + Vector3(0, 0.2, 13), "yaw": 0.0, "pitch": 0.02,
				"hour": 9.0, "name": "well"},
			{"pos": well + Vector3(0, 34.0, 54), "yaw": 0.0, "pitch": -0.45,
				"hour": 14.0, "name": "aerial"},
		]
	add_child(s)
