extends Node3D
class_name SeasonFx
## What the season looks like: snow settled on grass, thatch and treetops;
## the leaves going orange in autumn; a fresher green in spring; and the leaves
## (or blossom petals) drifting down around the player while it lasts.
##
## All of it is cheap on purpose. The colour work is four shader parameters set
## on the handful of shared voxel materials (no chunk is re-meshed: every chunk
## already points at those materials), done at most once an hour. The drifting
## leaves are one small FxPool emitted only around the viewer.
##
## The Seasons system calls set_look() as the days pass; nothing here keeps
## state worth saving, because the look is a pure function of the date.

## Materials the snow settles on (the upward faces of them, see snow_cover in
## voxel_common.gdshaderinc).
const SNOWY := [VoxelTypes.GRASS, VoxelTypes.TALL_GRASS, VoxelTypes.MOSS, VoxelTypes.THATCH,
	VoxelTypes.CLAY_TILE, VoxelTypes.LEAF, VoxelTypes.LEAF_LIGHT, VoxelTypes.LEAF_BIRCH,
	VoxelTypes.LEAF_AUTUMN, VoxelTypes.PINE_NEEDLES, VoxelTypes.FERN, VoxelTypes.DIRT,
	VoxelTypes.SAND, VoxelTypes.GRAVEL]
const DECIDUOUS := [VoxelTypes.LEAF, VoxelTypes.LEAF_LIGHT, VoxelTypes.LEAF_BIRCH]
const GROUND := [VoxelTypes.GRASS, VoxelTypes.TALL_GRASS, VoxelTypes.MOSS, VoxelTypes.FERN]

var viewer: Node3D = null
var wind := Vector3(0.9, 0.0, 0.35)

var snow := 0.0         ## 0..1 how white the world is
var autumn := 0.0       ## 0..1 how far the leaves have turned
var spring := 0.0       ## 0..1 how fresh the green is
var season := "summer"

var _fall: FxPool
var _acc := 0.0
var _originals: Dictionary = {}     ## material id -> its authored albedo_tint


func _ready() -> void:
	_fall = FxPool.new().setup(220)
	_fall.name = "Falling"
	add_child(_fall)


## The look of a given date. day_of_season is 1..12.
static func look_for(season_name: String, day_of_season: int) -> Dictionary:
	var d := float(day_of_season)
	var snow_v := 0.0
	var autumn_v := 0.0
	var spring_v := 0.0
	match season_name:
		"spring":
			snow_v = clampf((3.0 - d) / 3.0, 0.0, 1.0) * 0.5   # the last of the melt
			autumn_v = clampf((3.0 - d) / 3.0, 0.0, 1.0) * 0.4
			spring_v = clampf(d / 4.0, 0.0, 1.0)
		"summer":
			spring_v = clampf((8.0 - d) / 8.0, 0.0, 1.0) * 0.6
		"autumn":
			autumn_v = clampf(d / 6.0, 0.0, 1.0)
		"winter":
			autumn_v = 0.7
			snow_v = clampf(d / 3.0, 0.0, 1.0)
			if d > 9.0:
				snow_v = clampf(1.0 - (d - 9.0) * 0.12, 0.5, 1.0)
	return {"snow": snow_v, "autumn": autumn_v, "spring": spring_v}


func set_look(season_name: String, day_of_season: int) -> void:
	season = season_name
	var look := look_for(season_name, day_of_season)
	snow = float(look["snow"])
	autumn = float(look["autumn"])
	spring = float(look["spring"])
	_apply()


func _original(id: int, m: ShaderMaterial) -> Vector3:
	if not _originals.has(id):
		var v: Variant = m.get_shader_parameter("albedo_tint")
		_originals[id] = v if v is Vector3 else Vector3.ONE
	return _originals[id]


func _apply() -> void:
	for id: int in SNOWY:
		var m := VoxelMaterials.get_material(id)
		if m == null:
			continue
		m.set_shader_parameter("snow_cover", snow)
	for id2: int in DECIDUOUS:
		var m2 := VoxelMaterials.get_material(id2)
		if m2 == null:
			continue
		var base := _original(id2, m2)
		var leaf := Vector3(1.0, 1.0, 1.0).lerp(Vector3(2.7, 0.95, 0.18), autumn)
		leaf = leaf.lerp(Vector3(0.92, 1.1, 0.9), spring * (1.0 - autumn))
		m2.set_shader_parameter("albedo_tint", Vector3(base.x * leaf.x, base.y * leaf.y, base.z * leaf.z))
	for id3: int in GROUND:
		var m3 := VoxelMaterials.get_material(id3)
		if m3 == null:
			continue
		var base3 := _original(id3, m3)
		var g := Vector3(1.0, 1.0, 1.0).lerp(Vector3(1.3, 0.98, 0.62), autumn)
		g = g.lerp(Vector3(0.9, 1.12, 0.88), spring * (1.0 - autumn))
		m3.set_shader_parameter("albedo_tint", Vector3(base3.x * g.x, base3.y * g.y, base3.z * g.z))


## Puts every material back as authored (a test, or leaving the world).
func reset_materials() -> void:
	snow = 0.0
	autumn = 0.0
	spring = 0.0
	_apply()


func _process(delta: float) -> void:
	if viewer == null or not is_instance_valid(viewer):
		return
	_fall.wind = wind
	var rate := 0.0
	if autumn > 0.05 and season in ["autumn", "winter"] and snow < 0.6:
		rate = 9.0 * autumn * (1.0 if season == "autumn" else 0.3)
	elif season == "spring" and spring > 0.2:
		rate = 5.0 * spring
	if rate <= 0.0:
		return
	_acc += delta * rate
	var vp := viewer.global_position
	while _acc >= 1.0:
		_acc -= 1.0
		var ang := randf() * TAU
		var at := vp + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(2.0, 16.0)
		at.y = vp.y + randf_range(4.0, 9.0)
		var col: Color
		if season == "spring":
			col = Color("#f4c6d6").lerp(Color("#ffffff"), randf() * 0.6)
		else:
			col = [Color("#cf7a2a"), Color("#b3471f"), Color("#e0a830"), Color("#a05a22")][randi() % 4]
		var p := _fall.emit(at, Vector3(0.0, -randf_range(0.7, 1.3), 0.0), col,
			randf_range(0.08, 0.14), randf_range(6.0, 10.0))
		if p != null:
			p.wind = 1.4
			p.wobble = 1.1
			p.spin = randf_range(-3.0, 3.0)
			p.flap = true


## A burst of coloured paper over the well: the harvest festival.
func confetti(at: Vector3) -> void:
	var cols := [Color("#e8c14a"), Color("#d9573a"), Color("#6aa84f"), Color("#4a86c8"), Color("#f4c6d6")]
	for i in 120:
		var a := randf() * TAU
		var v := Vector3(cos(a) * randf_range(0.5, 3.0), randf_range(3.0, 7.0), sin(a) * randf_range(0.5, 3.0))
		var p := _fall.emit(at + Vector3(0, 1.5, 0), v, cols[randi() % cols.size()],
			randf_range(0.08, 0.15), randf_range(3.0, 5.0), 6.0, 0.6)
		if p != null:
			p.spin = randf_range(-8.0, 8.0)
			p.flap = true
