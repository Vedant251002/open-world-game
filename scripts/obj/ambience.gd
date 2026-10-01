extends Node3D
class_name Ambience
## The things that make a town look lived in rather than merely built: smoke
## from chimneys (more of it in the evening, leaning with the wind), sparks off
## the forge, steam from the bakery oven, butterflies over the flowers by day,
## fireflies by night, and dust kicked up when somebody runs.
##
## Everything is drawn through three FxPools (one MultiMesh each), emitted
## only near the camera and capped, so it is the same handful of draw calls
## whether the town has two chimneys or forty — and the same on the web build,
## which is why none of it is GPUParticles3D. Sources register themselves
## statically (a building's Construction does it when its props appear, which
## also covers buildings restored from a save), so this node can be created
## before or after them.

const NEAR_M := 75.0          ## nobody sees a chimney's smoke further off than this
const FIREFLIES := 26
const BUTTERFLIES := 7

## {owner:int, kind:String, pos:Vector3, phase:float, acc:float}
static var sources: Array[Dictionary] = []

var world: VoxelWorld
var player: Node3D
var clock: GameClock
var realm: Node = null          ## looked at lazily for the weather

var _smoke: FxPool
var _glow: FxPool
var _day: FxPool
var _t := 0.0
var _weather: Node = null
var _weather_look := 0.0
var _wind := Vector3(0.6, 0.0, 0.25)
var _fly_acc := 0.0
var _bfly_acc := 0.0
var _dust_acc := 0.0
var _scan_acc := 0.0


static func add_source(owner_id: int, kind: String, pos: Vector3) -> void:
	sources.append({"owner": owner_id, "kind": kind, "pos": pos,
		"phase": randf() * 10.0, "acc": randf()})


static func remove_owner(owner_id: int) -> void:
	sources = sources.filter(func(s: Dictionary) -> bool: return s["owner"] != owner_id)


static func clear_sources() -> void:
	sources.clear()


func setup(w: VoxelWorld, p: Node3D, c: GameClock) -> void:
	world = w
	player = p
	clock = c
	_smoke = FxPool.new().setup(320)
	_smoke.name = "Smoke"
	add_child(_smoke)
	_glow = FxPool.new().setup(160, true)
	_glow.name = "Glow"
	add_child(_glow)
	_day = FxPool.new().setup(80)
	_day.name = "Critters"
	add_child(_day)


## 0 at midday, 1 around dusk and night: how much the hearths are lit.
func _evening() -> float:
	if clock == null:
		return 0.3
	var h := clock.hour
	if h >= 17.0 and h < 20.0:
		return remap(h, 17.0, 20.0, 0.4, 1.0)
	if h >= 20.0 or h < 5.0:
		return 1.0
	if h < 8.0:
		return remap(h, 5.0, 8.0, 1.0, 0.5)
	return 0.3


func _is_dark() -> bool:
	if clock == null:
		return false
	return clock.hour >= 19.5 or clock.hour < 4.8


func _raining() -> bool:
	if _weather != null and is_instance_valid(_weather):
		return bool(_weather.call("is_raining"))
	return false


func _find_weather() -> void:
	if realm == null or not is_instance_valid(realm):
		return
	for n in realm.get_children():
		if n.has_method("is_raining") and n.has_method("season"):
			_weather = n
			return


func _process(delta: float) -> void:
	if player == null or world == null or not is_instance_valid(player):
		return
	delta = minf(delta, 0.1)
	_t += delta
	_weather_look -= delta
	if _weather == null and _weather_look <= 0.0:
		_weather_look = 5.0
		_find_weather()
	# A breeze that wanders, plus the weather's own wind when there is one.
	var w2 := Vector2(sin(_t * 0.07) * 0.5 + 0.6, cos(_t * 0.05) * 0.4 + 0.2)
	if _weather != null and is_instance_valid(_weather):
		var wv: Variant = _weather.get("_wind")
		if wv is Vector2:
			w2 = (wv as Vector2) * 0.9 + w2 * 0.3
	_wind = Vector3(w2.x, 0.0, w2.y)
	_smoke.wind = _wind
	_glow.wind = _wind * 0.3
	_day.wind = _wind * 0.4

	var cam := get_viewport().get_camera_3d()
	var here := player.global_position
	if cam != null:
		here = cam.global_position
	_emit_sources(delta, here)
	_critters(delta, here)
	_run_dust(delta)


func _emit_sources(delta: float, here: Vector3) -> void:
	var eve := _evening()
	var rain := _raining()
	for s: Dictionary in sources:
		var pos: Vector3 = s["pos"]
		var dx := pos.x - here.x
		var dz := pos.z - here.z
		if dx * dx + dz * dz > NEAR_M * NEAR_M:
			continue
		var kind: String = s["kind"]
		s["acc"] = float(s["acc"]) + delta
		match kind:
			"smoke", "steam":
				# A hearth burns all day but harder at night.
				var gap := lerpf(0.55, 0.26, eve)
				if rain:
					gap *= 1.3
				if float(s["acc"]) >= gap and _smoke.count() < 270:
					s["acc"] = 0.0
					var grey := lerpf(0.86, 0.62, eve)
					if kind == "steam":
						grey = 0.97
					var p := _smoke.emit(pos + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12)),
						Vector3(randf_range(-0.06, 0.06), randf_range(0.7, 1.0), randf_range(-0.06, 0.06)),
						Color(grey, grey, grey * 1.02, lerpf(0.26, 0.36, eve)),
						randf_range(0.18, 0.28), randf_range(4.2, 6.0), -0.05, 0.25)
					if p != null:
						p.grow = 0.12
						p.wind = 0.8
						p.fade_in = 0.5
			"forge":
				if float(s["acc"]) >= randf_range(0.18, 0.55):
					s["acc"] = 0.0
					for k in randi_range(2, 5):
						var v := Vector3(randf_range(-0.9, 0.9), randf_range(1.4, 3.0), randf_range(-0.9, 0.9))
						_glow.emit(pos, v, Color(1.0, randf_range(0.5, 0.78), 0.22, 1.0),
							randf_range(0.03, 0.055), randf_range(0.5, 0.95), 6.5, 0.2)
			"oven":
				if float(s["acc"]) >= 0.6:
					s["acc"] = 0.0
					if randf() < 0.5:
						_glow.emit(pos - Vector3(0, 0.1, 0), Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.0), randf_range(-0.3, 0.3)),
							Color(1.0, 0.55, 0.2, 1.0), 0.03, 0.7, 3.0, 0.5)


## Where a creature could be: a point above grass near the camera. Flowers are
## preferred, since that is where a butterfly would be.
func _meadow_point(here: Vector3, r_min: float, r_max: float) -> Variant:
	for attempt in 6:
		var a := randf() * TAU
		var r := randf_range(r_min, r_max)
		var x := here.x + cos(a) * r
		var z := here.z + sin(a) * r
		var vx := floori(x / VoxelChunk.VOXEL_M)
		var vz := floori(z / VoxelChunk.VOXEL_M)
		var h := world.height_at(vx, vz)
		if h < 0:
			continue
		var top := world.get_voxel(Vector3i(vx, h, vz))
		if top != VoxelTypes.GRASS:
			continue
		var above := world.get_voxel(Vector3i(vx, h + 1, vz))
		var flower := above >= VoxelTypes.FLOWER_RED and above <= VoxelTypes.FLOWER_PURPLE
		if flower or attempt >= 3:
			return Vector3(x, float(h + 1) * VoxelChunk.VOXEL_M, z)
	return null


func _critters(delta: float, here: Vector3) -> void:
	var rain := _raining()
	if _is_dark() and not rain:
		_fly_acc += delta
		# Replace them as they drift off: a steady population, not a burst.
		var want_gap := 7.5 / float(FIREFLIES)
		while _fly_acc >= want_gap:
			_fly_acc -= want_gap
			var pt: Variant = _meadow_point(here, 4.0, 32.0)
			if pt == null:
				break
			var at: Vector3 = pt
			at.y += randf_range(0.4, 1.8)
			var p := _glow.emit(at, Vector3(randf_range(-0.15, 0.15), randf_range(-0.05, 0.1), randf_range(-0.15, 0.15)),
				Color(0.78, 1.0, 0.35, 0.95), 0.07, randf_range(6.0, 9.5))
			if p != null:
				p.flicker = randf_range(2.2, 4.0)
				p.fade_in = 1.2
				p.wobble = 0.55
	elif clock != null and clock.hour >= 8.0 and clock.hour < 18.5 and not rain:
		_bfly_acc += delta
		var gap2 := 9.0 / float(BUTTERFLIES)
		while _bfly_acc >= gap2:
			_bfly_acc -= gap2
			var pt2: Variant = _meadow_point(here, 5.0, 28.0)
			if pt2 == null:
				break
			var at2: Vector3 = pt2
			at2.y += randf_range(0.5, 1.4)
			var pal := [Color("#f0c53c"), Color("#f4f0e4"), Color("#e8743f"), Color("#7fb2e8")]
			var p2 := _day.emit(at2, Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35)),
				pal[randi() % pal.size()], 0.1, randf_range(7.0, 11.0))
			if p2 != null:
				p2.fade_in = 1.0
				p2.wobble = 1.1
				p2.flap = true


## Dust at the heels of whoever is running.
func _run_dust(delta: float) -> void:
	_dust_acc += delta
	if _dust_acc < 0.16:
		return
	_dust_acc = 0.0
	var pl := player as CharacterBody3D
	if pl == null or not pl.is_on_floor():
		return
	var sp := Vector2(pl.velocity.x, pl.velocity.z).length()
	if sp < 6.0:
		return
	var back := Vector3(pl.velocity.x, 0.0, pl.velocity.z).normalized() * -0.35
	for k in 2:
		var p := _day.emit(pl.global_position + back + Vector3(randf_range(-0.15, 0.15), 0.08, randf_range(-0.15, 0.15)),
			Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 0.8), randf_range(-0.3, 0.3)) + back * 1.5,
			Color(0.72, 0.65, 0.52, 0.55), randf_range(0.1, 0.16), randf_range(0.5, 0.8), 0.6, 2.0)
		if p != null:
			p.grow = 0.25
