extends RefCounted
class_name VoxelMaterials
## Builds one ShaderMaterial per world material, all sharing voxel.gdshader.
##
## Materials are created once and handed to every chunk mesh, so a chunk with
## six materials costs six surfaces and zero extra shader compiles.

const SHADER := preload("res://scripts/core/voxel.gdshader")
const SHADER_GLASS := preload("res://scripts/core/voxel_glass.gdshader")

## Detail pattern per material. See voxel.gdshader.
const PLAIN := 0
const MASONRY := 1
const GRAIN := 2
const CORRUGATED := 3
const TILE := 4
const THATCH := 5
const SCATTER := 6
const GLASS := 7
const PANEL := 8
const NEON := 9

const PATTERN := {
	VoxelTypes.TIMBER: GRAIN, VoxelTypes.PLANK: GRAIN,
	VoxelTypes.DARK_OAK: GRAIN, VoxelTypes.BARK: GRAIN,
	VoxelTypes.BRICK: MASONRY, VoxelTypes.SANDSTONE: MASONRY,
	VoxelTypes.GRANITE: MASONRY, VoxelTypes.COBBLE: MASONRY,
	VoxelTypes.STONE: MASONRY, VoxelTypes.ROCK: PLAIN,
	VoxelTypes.CONCRETE: PLAIN, VoxelTypes.REBAR_CONCRETE: PLAIN,
	VoxelTypes.CONCRETE_SLAB: PLAIN, VoxelTypes.PLASTIC_PANEL: PANEL,
	VoxelTypes.STEEL_FRAME: PANEL, VoxelTypes.SHEET_METAL: PANEL,
	VoxelTypes.CHROME: PANEL, VoxelTypes.CARBON_COMPOSITE: PANEL,
	VoxelTypes.CORRUGATED_STEEL: CORRUGATED,
	VoxelTypes.CLAY_TILE: TILE, VoxelTypes.ASPHALT_SHINGLE: TILE,
	VoxelTypes.SOLAR_PANEL: PANEL,
	VoxelTypes.THATCH: THATCH, VoxelTypes.LEAF: THATCH,
	VoxelTypes.GLASS: GLASS, VoxelTypes.REINFORCED_GLASS: GLASS,
	VoxelTypes.WATER: GLASS,
	VoxelTypes.DIRT: SCATTER, VoxelTypes.GRAVEL: SCATTER,
	VoxelTypes.GRASS: SCATTER, VoxelTypes.SAND: SCATTER,
	VoxelTypes.ASPHALT: SCATTER,
	VoxelTypes.PAINTED_WHITE: PLAIN, VoxelTypes.PAINTED_RED: PLAIN,
	VoxelTypes.MATTE_BLACK: PLAIN, VoxelTypes.NEON_STRIP: NEON,
}

static var _cache: Dictionary = {}


static func get_material(id: int) -> ShaderMaterial:
	if _cache.has(id):
		return _cache[id]

	var props: Array = VoxelTypes.PROPS[id]
	var albedo: Color = props[0]
	# The palette is authored in sRGB, which is how anyone picking colours thinks
	# about them, but the shader works in linear light. Convert here rather than
	# relying on a source_color hint, which Godot only honours for Color values
	# and silently ignores for the vec3 we actually pass.
	var lin := albedo.srgb_to_linear()
	var see_through := VoxelTypes.is_transparent(id)
	var m := ShaderMaterial.new()
	m.shader = SHADER_GLASS if see_through else SHADER
	m.set_shader_parameter("base_albedo", Vector3(lin.r, lin.g, lin.b))
	m.set_shader_parameter("base_roughness", float(props[1]))
	m.set_shader_parameter("base_metallic", float(props[2]))
	m.set_shader_parameter("alpha", albedo.a)
	m.set_shader_parameter("water_mode", 1 if id == VoxelTypes.WATER else 0)
	m.set_shader_parameter("pattern", PATTERN.get(id, PLAIN))
	m.set_shader_parameter("grain", float(VoxelTypes.GRAIN.get(id, 0.5)))

	var emission := float(props[3])
	if emission > 0.0:
		m.set_shader_parameter("emission_color", Vector3(lin.r, lin.g, lin.b))
		m.set_shader_parameter("emission_energy", emission)

	# Painted and glazed surfaces want less procedural noise than natural ones.
	var strength := 0.38
	var bump := 0.7
	var jitter := 0.10
	match PATTERN.get(id, PLAIN):
		GLASS:
			strength = 0.10
			bump = 0.0
			jitter = 0.02
		NEON:
			strength = 0.12
			bump = 0.0
			jitter = 0.0
		SCATTER:
			strength = 0.62
			bump = 0.30
			jitter = 0.22
		MASONRY:
			strength = 0.62
			bump = 0.30
			jitter = 0.10
		THATCH:
			strength = 0.60
			bump = 0.9
			jitter = 0.12
		TILE:
			strength = 0.48
			bump = 1.0
			jitter = 0.08
		CORRUGATED:
			strength = 0.40
			bump = 1.2
			jitter = 0.04
		PANEL:
			strength = 0.22
			bump = 0.5
			jitter = 0.04
		GRAIN:
			strength = 0.52
			bump = 0.55
			jitter = 0.09

	m.set_shader_parameter("detail_strength", strength)
	m.set_shader_parameter("bump_strength", bump)
	m.set_shader_parameter("hue_jitter", jitter)

	if see_through:
		m.render_priority = 1

	_cache[id] = m
	return m


## Pushes the sun/sky state into every live material. Called by SkyEnv whenever
## the time of day changes; only the WATER shading branch reads these.
static func set_sky(to_sun: Vector3, tint: Color, glitter: float, reflect: Color) -> void:
	var lin_tint := tint.srgb_to_linear()
	var lin_reflect := reflect.srgb_to_linear()
	for id in _cache:
		var m: ShaderMaterial = _cache[id]
		m.set_shader_parameter("sun_dir", to_sun)
		m.set_shader_parameter("sun_tint", Vector3(lin_tint.r, lin_tint.g, lin_tint.b))
		m.set_shader_parameter("sun_glitter", glitter)
		m.set_shader_parameter("sky_reflect", Vector3(lin_reflect.r, lin_reflect.g, lin_reflect.b))
