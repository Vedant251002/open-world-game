extends Node
class_name AudioDirector
## The hub of the soundscape. Owns the buses, the player pools, the
## "what is the world like right now" state the layers read, and the UI sounds.
##
## Three layers live beneath it, each its own node so none grows into a heap:
##   Ambience       - wind, rain, thunder, birds, crickets, owls, water, murmur
##   MusicConductor - sparse generative music
##   WorldSfx       - footsteps, hammer/saw at work sites, animals
##
## Created early in Main._ready (so the title screen's buttons already click)
## and bound to the game's systems once they exist (bind()). Every system
## reference is optional: a test that boots half the game still runs.
##
## Browsers refuse to start audio until the player has touched the page; until
## the first press or key the director stays silent and schedules nothing.

const NOTIFY_GAP_MS := 3200
const NOTIFY_GAP_MAJOR_MS := 1500
const MAX_3D := 16
const LEAF_TYPES := [35, 43, 44, 45, 46, 47]   ## VoxelTypes foliage: canopy is not a roof

var player: Player
var world: VoxelWorld
var clock: GameClock
var realm: Realm
var crew: Crew
var livestock: Livestock
var warfare: Warfare
var map: Node
var inventory: Node
var pause_menu: Node

var unlocked := false

## World state, refreshed ENV_DT apart, read by the layers.
var hour := 12.0
var night := 0.0                  ## 0 day .. 1 full night, smooth through dusk and dawn
var daylight := 1.0               ## 1 in daytime birdsong hours
var wx_state := "clear"           ## clear overcast rain storm fog snow
var season := "summer"
var indoor := 0.0                 ## 0 under open sky .. 1 under a roof (smoothed)

var ambience: Ambience
var music: MusicConductor
var world_sfx: WorldSfx

var _root3d: Node3D
var _pool3d: Array[AudioStreamPlayer3D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _env_t := 0.0
var _indoor_target := 0.0
var _wx: Node = null
var _last_notify_ms := -100000
var _seen_map := false
var _seen_inv := false
var _seen_pause := false
const ENV_DT := 0.25


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # sound carries on under the pause menu
	AudioBuses.ensure()
	Sfx.host = self
	_root3d = Node3D.new()
	_root3d.name = "Voices3D"
	_root3d.top_level = true
	add_child(_root3d)
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.bus = AudioBuses.UI
		add_child(p)
		_ui_pool.append(p)

	ambience = Ambience.new()
	ambience.name = "Ambience"
	ambience.dir = self
	add_child(ambience)
	music = MusicConductor.new()
	music.name = "Music"
	music.dir = self
	add_child(music)
	world_sfx = WorldSfx.new()
	world_sfx.name = "WorldSfx"
	world_sfx.dir = self
	add_child(world_sfx)

	# Desktop and headless can play at once; the web waits for a gesture.
	if not Platform.is_web():
		_unlock()


func _exit_tree() -> void:
	if Sfx.host == self:
		Sfx.host = null


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_unlock()


func _unlock() -> void:
	if unlocked:
		return
	unlocked = true
	AudioLib.warm(["wind_loop", "rain_loop", "water_loop", "murmur_loop", "crickets_loop",
		"pad_day", "ui_click", "ui_chime", "bird_tweet_1", "bird_trill_1", "bird_warble_1",
		"step_grass_1", "step_dirt_1", "step_stone_1", "step_wood_1", "hammer_1", "saw_1"])


## Hands the director the game's systems. Any key may be missing.
func bind(refs: Dictionary) -> void:
	player = refs.get("player")
	world = refs.get("world")
	clock = refs.get("clock")
	realm = refs.get("realm")
	crew = refs.get("crew")
	livestock = refs.get("livestock")
	warfare = refs.get("warfare")
	map = refs.get("map")
	inventory = refs.get("inventory")
	pause_menu = refs.get("pause_menu")
	var town: Town = refs.get("town")
	if realm != null:
		# Realm statements are the village's news; they get the soft chime.
		realm.status.connect(func(_t: String) -> void: notify("ui_chime"))
	if warfare != null:
		warfare.status.connect(func(_t: String) -> void: notify("ui_chime"))
		warfare.raid_began.connect(func(_n: int) -> void: notify("ui_alert", true))
		warfare.raid_over.connect(func(won: bool) -> void:
			if won:
				notify("ui_milestone", true))
	if town != null:
		town.tier_changed.connect(func(_t: int) -> void: notify("ui_milestone", true))
	if crew != null:
		crew.job_done.connect(func(_w: Worker, _p: VoxelPatch) -> void: ui("ui_built", -6.0))


# ----------------------------------------------------------------- one-shots

## A sound on the interface bus, not placed in the world.
func ui(sound: String, db: float = -6.0, pitch: float = 1.0) -> void:
	if not unlocked:
		return
	var s := AudioLib.get_stream(sound)
	if s == null:
		return
	for p in _ui_pool:
		if not p.playing:
			p.stream = s
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return


## Toasts and news. Rate limited: a burst of messages is one chime, not six.
func notify(sound: String, major: bool = false) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_notify_ms < (NOTIFY_GAP_MAJOR_MS if major else NOTIFY_GAP_MS):
		return
	_last_notify_ms = now
	ui(sound, -7.0 if not major else -5.0)


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	if _pool3d.size() >= MAX_3D:
		return null
	var np := AudioStreamPlayer3D.new()
	np.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	np.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_root3d.add_child(np)
	_pool3d.append(np)
	return np


## A one-shot placed in the world. Returns the player (or null if the pool is
## busy), so a caller can keep a handle.
func play3d(sound: String, pos: Vector3, db: float = -6.0, pitch: float = 1.0,
		unit: float = 8.0, bus: String = AudioBuses.SFX, max_d: float = 60.0) -> AudioStreamPlayer3D:
	if not unlocked:
		return null
	var s := AudioLib.get_stream(sound)
	if s == null:
		return null
	var p := _free_3d()
	if p == null:
		return null
	p.stream = s
	p.bus = bus
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_d
	p.global_position = pos
	p.play()
	return p


# --------------------------------------------------------------- world state

func is_paused() -> bool:
	return get_tree().paused or (clock != null and clock.paused)


func _process(delta: float) -> void:
	if not unlocked:
		return
	_env_t -= delta
	if _env_t <= 0.0:
		_env_t = ENV_DT
		_update_env()
	indoor = move_toward(indoor, _indoor_target, delta * 2.0)
	AudioBuses.set_muffle(indoor)
	_poll_screens()


func _update_env() -> void:
	hour = clock.hour if clock != null else 12.0
	# Night is 0 from 6:30 to 19, 1 from 21 to 4:30, smooth between.
	if hour < 12.0:
		night = 1.0 - smoothstep(4.5, 6.5, hour)
	else:
		night = smoothstep(19.0, 21.0, hour)
	daylight = smoothstep(4.8, 6.6, hour) * (1.0 - smoothstep(19.0, 20.8, hour))
	if realm != null and _wx == null:
		_wx = realm.system("Weather")
	if _wx != null and is_instance_valid(_wx):
		wx_state = str(_wx.get("_state"))
		season = str(_wx.call("season"))
	_indoor_target = 1.0 if _roof_above() else 0.0


## Roofed in? Looks up a few metres from the head for anything solid that is
## not foliage. Cheap: 14 voxel reads, four times a second.
func _roof_above() -> bool:
	if player == null or world == null:
		return false
	var v := VoxelWorld.to_voxel(player.global_position + Vector3(0, 1.8, 0))
	for k in range(1, 15):
		var t := world.get_voxel(v + Vector3i(0, k, 0))
		if t != VoxelTypes.AIR and t != VoxelTypes.WATER and VoxelTypes.is_solid(t) \
				and not LEAF_TYPES.has(t):
			return true
	return false


func raining() -> float:
	match wx_state:
		"rain":
			return 0.6
		"storm":
			return 1.0
	return 0.0


## Opening the map, the stores or the pause menu is a small sound of its own.
func _poll_screens() -> void:
	if map != null and "open" in map:
		var o: bool = map.open
		if o != _seen_map:
			_seen_map = o
			ui("ui_page", -7.0, 1.0 if o else 0.88)
	if inventory != null and "open" in inventory:
		var io: bool = inventory.open
		if io != _seen_inv:
			_seen_inv = io
			ui("ui_page", -11.0, 1.2 if io else 1.05)
	if pause_menu != null and "open" in pause_menu:
		var po: bool = pause_menu.open
		if po != _seen_pause:
			_seen_pause = po
			ui("ui_click", -8.0, 0.85 if po else 1.1)
