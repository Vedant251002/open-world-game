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

var _world_seed := 0
var showcase_views: Array[Dictionary] = []
var showcase_patches: Array[VoxelPatch] = []


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
		far.refresh(village.spawn_pos, true)

	var t0 := Time.get_ticks_msec()
	var columns := streamer.prime(village.spawn_pos)
	print("[delegate] seed %d, %d plots, priming %d columns" % [
		_world_seed, village.plots.size(), columns])
	streamer.first_load_done.connect(_on_world_ready.bind(t0))

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
	if far != null and player != null:
		far.refresh(player.global_position)


func _on_world_ready(t0: int) -> void:
	print("[delegate] world ready in %d ms: %d columns, %d chunks, %d mesh nodes" % [
		Time.get_ticks_msec() - t0, world.loaded_columns(),
		world.chunk_count(), world.mesh_node_count()])
	var g := world.ground_m(player.global_position.x, player.global_position.z)
	player.teleport(Vector3(player.global_position.x, g + 0.4,
		player.global_position.z), PI)

	var args := OS.get_cmdline_user_args()
	if "--buildtest" in args:
		_build_showcase()
	if "--nostream" in args:
		streamer.set_process(false)
	if "--nomap" in args:
		map.set_process(false)
	if "--noworld" in args:
		world.set_process(false)
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
	if "--shot" in args:
		_install_shotter()


func build_context() -> Dictionary:
	return {
		"world": world, "village": village, "worldgen": gen, "tier": 1,
		"occupied_rects": [], "built_fronts": {},
	}


## Drops the acceptance specs onto real plots so the geometry can be looked at
## rather than only asserted about.
func _build_showcase() -> void:
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
		_record_view(str(specs[placed]["archetype"]), patch)
		showcase_patches.append(patch)
		placed += 1


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


func _install_shotter() -> void:
	var s := Shotter.new()
	s.world = world
	s.player = player
	s.sky = sky
	var well := village.well_pos
	s.views = showcase_views.duplicate()
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
