extends Node
class_name WorldSfx
## Sounds that belong to things happening in the world:
##   - the player's footsteps, by what is underfoot (grass, dirt, sand, stone,
##     wood), a thud on landing and a splash in water
##   - hammering, sawing and chiselling from every worker who is building,
##     placed at the worker so you can hear a site before you see it
##   - hens, sheep, goats and cows, at the animals themselves

const STEP_VARIANTS := {"grass": 3, "dirt": 3, "stone": 3, "wood": 3, "sand": 2, "splash": 2}
const WORK_HEARD_M := 42.0
const ANIMAL_HEARD_M := 40.0

var dir: AudioDirector

var _stride := 0.0
var _foot := 0
var _was_floor := true
var _was_water := false
var _fall_v := 0.0
var _step_pool: Array[AudioStreamPlayer] = []
var _sites: Dictionary = {}           ## worker instance id -> {t, mode, left}
var _animal_wait := 6.0
static var _surface: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if dir == null or not dir.unlocked or dir.player == null or dir.is_paused():
		return
	_footsteps(delta)
	_construction(delta)
	_animals(delta)


# ---------------------------------------------------------------- footsteps

static func _surface_table() -> Dictionary:
	if not _surface.is_empty():
		return _surface
	var t := {}
	for v: int in [VoxelTypes.GRASS, VoxelTypes.LEAF, VoxelTypes.LEAF_LIGHT, VoxelTypes.LEAF_BIRCH,
			VoxelTypes.PINE_NEEDLES, VoxelTypes.LEAF_AUTUMN, VoxelTypes.BLOSSOM,
			VoxelTypes.FLOWER_RED, VoxelTypes.FLOWER_YELLOW, VoxelTypes.THATCH]:
		t[v] = "grass"
	for v: int in [VoxelTypes.DIRT, VoxelTypes.GRAVEL, VoxelTypes.CLAY, VoxelTypes.FARMLAND,
			VoxelTypes.WET_FARMLAND, VoxelTypes.IRON_ORE]:
		t[v] = "dirt"
	t[VoxelTypes.SAND] = "sand"
	for v: int in [VoxelTypes.PLANK, VoxelTypes.TIMBER, VoxelTypes.DARK_OAK, VoxelTypes.BARK,
			VoxelTypes.BIRCH_BARK, VoxelTypes.PAINTED_WHITE, VoxelTypes.PAINTED_RED]:
		t[v] = "wood"
	for v: int in [VoxelTypes.COBBLE, VoxelTypes.STONE, VoxelTypes.ROCK, VoxelTypes.GRANITE,
			VoxelTypes.BRICK, VoxelTypes.SANDSTONE, VoxelTypes.CONCRETE, VoxelTypes.CONCRETE_SLAB,
			VoxelTypes.ASPHALT, VoxelTypes.CLAY_TILE, VoxelTypes.REBAR_CONCRETE]:
		t[v] = "stone"
	t[VoxelTypes.WATER] = "splash"
	_surface = t
	return t


func _underfoot() -> String:
	var w := dir.world
	if w == null:
		return "dirt"
	var tbl := _surface_table()
	var v := VoxelWorld.to_voxel(dir.player.global_position + Vector3(0, -0.12, 0))
	for k in 3:
		var t := w.get_voxel(v + Vector3i(0, -k, 0))
		if t != VoxelTypes.AIR:
			return str(tbl.get(t, "dirt"))
	return "dirt"


func _step_voice() -> AudioStreamPlayer:
	for p in _step_pool:
		if not p.playing:
			return p
	if _step_pool.size() >= 4:
		return null
	var np := AudioStreamPlayer.new()
	np.bus = AudioBuses.SFX
	add_child(np)
	_step_pool.append(np)
	return np


func _step(kind: String, db: float, pitch: float) -> void:
	var s := AudioLib.get_stream(AudioLib.variant("step_" + kind, int(STEP_VARIANTS.get(kind, 1))))
	var p := _step_voice()
	if s == null or p == null:
		return
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _footsteps(delta: float) -> void:
	var p := dir.player
	if p.mount != null:
		return
	var vel := p.velocity
	var planar := Vector2(vel.x, vel.z).length()
	if p.in_water:
		if not _was_water:
			_step("splash", -6.0, 0.9)
		_was_water = true
		_was_floor = false
		_stride += planar * delta
		if _stride > 1.6:
			_stride = 0.0
			_step("splash", -17.0, randf_range(0.9, 1.1))
		return
	_was_water = false
	var on_floor := p.is_on_floor()
	if on_floor and not _was_floor and _fall_v < -5.0:
		_step(_underfoot(), clampf(-14.0 - _fall_v * 0.5, -10.0, -3.0), 0.8)
	if not on_floor:
		_fall_v = vel.y
	_was_floor = on_floor
	if not on_floor or not p.input_enabled or planar < 0.8:
		if planar < 0.3:
			_stride = 1.2                  # the first step comes quickly
		return
	_stride += planar * delta
	var sprint := planar > 5.5
	if _stride >= (2.1 if sprint else 1.7):
		_stride = 0.0
		_foot = 1 - _foot
		var kind := _underfoot()
		_step(kind, (-9.0 if sprint else -13.0) + randf_range(-1.5, 1.0),
			randf_range(0.93, 1.07) * (1.03 if _foot == 0 else 0.97))


# ----------------------------------------------------------- work sites

func _construction(delta: float) -> void:
	var c := dir.crew
	if c == null:
		return
	var pp := dir.player.global_position
	var alive := {}
	for w: Worker in c.workers:
		if not is_instance_valid(w) or w.state != Worker.State.BUILDING:
			continue
		if not w.job_errand.is_empty() or w.job_field != null:
			continue
		if w.global_position.distance_to(pp) > WORK_HEARD_M:
			continue
		var id := w.get_instance_id()
		alive[id] = true
		var st: Dictionary = _sites.get(id, {})
		if st.is_empty():
			st = {"t": randf_range(0.2, 1.4), "mode": "hammer", "left": randi_range(3, 6)}
			_sites[id] = st
		st["t"] = float(st["t"]) - delta
		if float(st["t"]) <= 0.0:
			_strike(w, st)
	for id: int in _sites.keys():
		if not alive.has(id):
			_sites.erase(id)


func _strike(w: Worker, st: Dictionary) -> void:
	var at := w.global_position + Vector3(0, 1.0, 0)
	var left: int = int(st["left"]) - 1
	st["left"] = left
	if w.job_quarry != null:
		dir.play3d(AudioLib.variant("stone", 2), at, randf_range(-8.0, -5.0), randf_range(0.92, 1.1), 7.0)
		st["t"] = randf_range(0.55, 0.95)
		if left <= 0:
			st["left"] = randi_range(3, 7)
			st["t"] = float(st["t"]) + randf_range(1.5, 4.0)
		return
	if st["mode"] == "saw":
		dir.play3d(AudioLib.variant("saw", 2), at, randf_range(-9.0, -6.0), randf_range(0.95, 1.05), 7.0)
		st["t"] = randf_range(1.75, 2.0)
		if left <= 0:
			st["mode"] = "hammer"
			st["left"] = randi_range(3, 7)
			st["t"] = float(st["t"]) + randf_range(1.0, 3.0)
		return
	dir.play3d(AudioLib.variant("hammer", 3), at, randf_range(-6.0, -3.0), randf_range(0.92, 1.08), 7.0)
	st["t"] = randf_range(0.38, 0.72)
	if left <= 0:
		if randf() < 0.45:
			st["mode"] = "saw"
			st["left"] = randi_range(2, 4)
		else:
			st["left"] = randi_range(3, 7)
		st["t"] = float(st["t"]) + randf_range(1.0, 3.0)


# ----------------------------------------------------------------- animals

func _animals(delta: float) -> void:
	var lv := dir.livestock
	if lv == null:
		return
	_animal_wait -= delta
	if _animal_wait > 0.0:
		return
	# Farm animals are quieter in the dark and in the rain.
	var quiet := 1.0 - 0.8 * dir.night - 0.4 * dir.raining()
	_animal_wait = randf_range(3.0, 9.0) / maxf(quiet, 0.1)
	var pp := dir.player.global_position
	var near: Array[Animal] = []
	for a: Animal in lv.animals:
		if is_instance_valid(a) and a.global_position.distance_to(pp) < ANIMAL_HEARD_M:
			near.append(a)
	if near.is_empty():
		return
	var a: Animal = near[randi() % near.size()]
	var sound := ""
	var pitch := randf_range(0.94, 1.06)
	var db := randf_range(-9.0, -4.0)
	match a.kind:
		"hen", "rooster":
			sound = AudioLib.variant("hen", 3)
			if a.kind == "rooster":
				pitch *= 0.8
		"sheep":
			sound = AudioLib.variant("sheep", 2)
		"goat":
			sound = AudioLib.variant("sheep", 2)
			pitch *= 1.18
		"cow":
			sound = AudioLib.variant("cow", 2)
			db += 1.0
		_:
			return
	dir.play3d(sound, a.global_position + Vector3(0, 0.6, 0), db, pitch, 6.0)
