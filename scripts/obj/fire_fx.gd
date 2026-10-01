extends Node3D
class_name FireFx
## A burning building, drawn: flames licking over the roof, a column of smoke
## leaning with the wind, a flickering orange light on the neighbours, and the
## water the bucket line throws at it.
##
## Like VillageAmbience it is two FxPools (one MultiMesh each) rather than
## particle nodes, so the web build draws a burning town in the same two draw
## calls as a quiet one. The Weather system owns the fire itself (its hit
## points, its voxels); this only draws what it is told.
##
##   add_fire(id, centre, half_extent_m, top_y_m)   a fire has started
##   set_intensity(id, 0..1)                        it grows / is beaten down
##   set_fighters(id, [Vector3])                    where the bucket line stands
##   remove_fire(id)                                it is out

const MAX_LIGHTS := 3
const FAR_M := 170.0

var viewer: Node3D = null
var wind := Vector3(0.9, 0.0, 0.35)

var _flame: FxPool
var _smoke: FxPool
var _water: FxPool
## id -> {centre, half: Vector2, top: float, k: float, acc_f, acc_s, fighters: Array, light}
var _fires: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	_flame = FxPool.new().setup(420)   # plain alpha: additive washes out against a bright sky
	_flame.name = "Flames"
	add_child(_flame)
	_smoke = FxPool.new().setup(520)
	_smoke.name = "FireSmoke"
	add_child(_smoke)
	_water = FxPool.new().setup(160)
	_water.name = "Water"
	add_child(_water)


func is_burning() -> bool:
	return not _fires.is_empty()


func add_fire(id: int, centre: Vector3, half_extent: Vector2, top_y: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color("#ff8a3a")
	light.omni_range = 14.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(centre.x, top_y + 1.2, centre.z)
	if _fires.size() < MAX_LIGHTS:
		add_child(light)
	else:
		light.free()
		light = null
	_fires[id] = {"centre": centre, "half": half_extent, "top": top_y, "k": 0.3,
		"acc_f": 0.0, "acc_s": 0.0, "fighters": [], "light": light}


func set_intensity(id: int, k: float) -> void:
	if _fires.has(id):
		_fires[id]["k"] = clampf(k, 0.0, 1.0)


func set_fighters(id: int, spots: Array) -> void:
	if _fires.has(id):
		_fires[id]["fighters"] = spots


func remove_fire(id: int) -> void:
	if not _fires.has(id):
		return
	var f: Dictionary = _fires[id]
	var light: OmniLight3D = f["light"]
	if light != null and is_instance_valid(light):
		light.queue_free()
	# A last gout of steam as it goes out.
	var c: Vector3 = f["centre"]
	for i in 18:
		var p := _smoke.emit(Vector3(c.x + randf_range(-1.5, 1.5), float(f["top"]) + 0.6,
			c.z + randf_range(-1.5, 1.5)), Vector3(randf_range(-0.3, 0.3), randf_range(1.0, 2.0),
			randf_range(-0.3, 0.3)), Color(0.9, 0.9, 0.92, 0.55), 0.9, randf_range(2.0, 3.4))
		if p != null:
			p.grow = 0.7
			p.wind = 1.0
	_fires.erase(id)


func clear() -> void:
	for id: int in _fires.keys():
		remove_fire(id)
	_flame.clear()
	_smoke.clear()
	_water.clear()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	_flame.wind = wind
	_smoke.wind = wind
	var vpos := viewer.global_position if viewer != null and is_instance_valid(viewer) else Vector3.INF
	for id: int in _fires:
		var f: Dictionary = _fires[id]
		var k: float = f["k"]
		var c: Vector3 = f["centre"]
		var light: OmniLight3D = f["light"]
		if light != null:
			light.light_energy = k * (2.2 + sin(_t * 17.0 + id) * 0.5 + sin(_t * 31.0) * 0.3)
		if vpos != Vector3.INF and vpos.distance_to(c) > FAR_M:
			continue
		var half: Vector2 = f["half"]
		var top: float = f["top"]
		# Flames: more of them the bigger the building and the fiercer the fire.
		f["acc_f"] += delta * (26.0 + half.x * half.y * 1.2) * k
		while f["acc_f"] >= 1.0:
			f["acc_f"] -= 1.0
			var at := Vector3(c.x + randf_range(-half.x, half.x), top + randf_range(-0.3, 0.5),
				c.z + randf_range(-half.y, half.y))
			var warm := randf()
			var col := Color("#ff4a12").lerp(Color("#ffc233"), warm)
			col.a = 0.95
			var p := _flame.emit(at, Vector3(randf_range(-0.4, 0.4), randf_range(1.6, 3.2) * (0.6 + k),
				randf_range(-0.4, 0.4)), col, randf_range(0.22, 0.5) * (0.6 + 0.6 * k),
				randf_range(0.45, 0.95))
			if p != null:
				p.grow = -0.45
				p.wind = 0.5
				p.flicker = 22.0
				p.drag = 0.4
		# Smoke: slower, bigger, dark, rising a long way.
		f["acc_s"] += delta * (9.0 + half.x * half.y * 0.5) * k
		while f["acc_s"] >= 1.0:
			f["acc_s"] -= 1.0
			var at2 := Vector3(c.x + randf_range(-half.x, half.x) * 0.7, top + 0.8,
				c.z + randf_range(-half.y, half.y) * 0.7)
			var g := randf_range(0.18, 0.32)
			var p2 := _smoke.emit(at2, Vector3(randf_range(-0.2, 0.2), randf_range(1.8, 3.0),
				randf_range(-0.2, 0.2)), Color(g, g, g * 1.03, 0.62), randf_range(0.8, 1.4),
				randf_range(4.0, 6.5))
			if p2 != null:
				p2.grow = 0.55
				p2.wind = 1.0
				p2.drag = 0.15
				p2.fade_in = 0.4
		# The bucket line: arcs of water from where each of them stands.
		for spot: Variant in f["fighters"]:
			var sp := spot as Vector3
			if randf() < delta * 14.0:
				var aim := Vector3(c.x, top - 0.5, c.z) + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
				var from := sp + Vector3(0.0, 1.3, 0.0)
				var dist := Vector2(aim.x - from.x, aim.z - from.z).length()
				if dist > 14.0:
					continue
				var vel := (aim - from) / 0.7
				vel.y = (aim.y - from.y) / 0.7 + 0.5 * 9.0 * 0.7
				var w := _water.emit(from, vel, Color(0.55, 0.75, 1.0, 0.85), 0.14, 0.7, 9.0)
				if w != null:
					w.spin = 4.0
				if randf() < 0.35:
					var st := _smoke.emit(aim, Vector3(0, 1.2, 0), Color(0.95, 0.95, 0.97, 0.5),
						0.6, 1.8)
					if st != null:
						st.grow = 0.8
						st.wind = 1.0
