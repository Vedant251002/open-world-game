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
	VoxelTypes.FARMLAND: SCATTER, VoxelTypes.WET_FARMLAND: SCATTER,
	VoxelTypes.EMBER: SCATTER,
	VoxelTypes.IRON_ORE: MASONRY, VoxelTypes.CLAY: SCATTER,
}

static var _cache: Dictionary = {}


## Builds every material up front, on the main thread.
##
## Mesh jobs run on worker threads and look materials up by id; without this the
## first chunk of a given material would race several threads through the same
## lazy construction.
static func prewarm() -> void:
	# The texture arrays must exist before any material references a layer, and
	# this is the one call that is guaranteed to run on the main thread before
	# the first chunk is meshed.
	VoxelTextures.load_all()
	for id in VoxelTypes.COUNT:
		if id != VoxelTypes.AIR:
			get_material(id)


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

	# The baked PBR maps. The layer is looked up by name because ORDER is the
	# only thing that knows the layout, and the material table is indexed by id.
	if VoxelTextures.ready():
		var layer := VoxelTextures.layer_of(VoxelTypes.name_of(id))
		if layer >= 0:
			m.set_shader_parameter("tex_layer", layer)
			m.set_shader_parameter("tex_scale", TEX_SCALE.get(id, 1.0))
			m.set_shader_parameter("normal_strength", NORMAL_STRENGTH.get(id, 1.0))
			m.set_shader_parameter("ao_strength", AO_STRENGTH.get(id, 1.0))
		m.set_shader_parameter("albedo_array", VoxelTextures.albedo_array())
		m.set_shader_parameter("normal_array", VoxelTextures.normal_array())
		m.set_shader_parameter("orm_array", VoxelTextures.orm_array())

	var emission := float(props[3])
	if emission > 0.0:
		m.set_shader_parameter("emission_color", Vector3(lin.r, lin.g, lin.b))
		m.set_shader_parameter("emission_energy", emission)

	# Painted and glazed surfaces want less procedural noise than natural ones.
	var strength := 0.16
	var bump := 0.25
	var jitter := 0.10
	match PATTERN.get(id, PLAIN):
		GLASS:
			strength = 0.04
			bump = 0.0
			jitter = 0.02
		NEON:
			strength = 0.05
			bump = 0.0
			jitter = 0.0
		SCATTER:
			strength = 0.24
			bump = 0.0
			jitter = 0.20
		MASONRY:
			strength = 0.14
			bump = 0.0
			jitter = 0.10
		THATCH:
			strength = 0.20
			bump = 0.0
			jitter = 0.12
		TILE:
			strength = 0.10
			bump = 0.0
			jitter = 0.08
		CORRUGATED:
			strength = 0.08
			bump = 0.0
			jitter = 0.04
		PANEL:
			strength = 0.06
			bump = 0.0
			jitter = 0.04
		GRAIN:
			strength = 0.12
			bump = 0.0
			jitter = 0.09

	m.set_shader_parameter("detail_strength", strength)
	m.set_shader_parameter("bump_strength", bump)
	m.set_shader_parameter("hue_jitter", jitter)

	if see_through:
		m.render_priority = 1

	_cache[id] = m
	return m


## How many times the baked tile repeats across one voxel face.
##
## A voxel face is 0.25 m. At 1.0 the whole 1024px texture lands on a single
## face, which means 4096 texels per metre — far more than the screen can ever
## resolve, so the mip chain throws almost all of it away and the wall reads
## smooth. The number that matters is texels per screen pixel at the distance
## the player actually looks at things from: roughly 2 m for a wall you are
## standing next to.
##
# These were measured, not guessed. The first pass used 1.0 everywhere and the
# close-up frames measured 6.4 detail against the shader packs' 5.9-9.2, while
# the aerial frame measured 7.9. Halving the repeat roughly doubled close-up
# detail and cost nothing, because the mip chain was discarding the extra
# resolution regardless.
const TEX_SCALE := {
	VoxelTypes.BRICK: 2.2, VoxelTypes.SANDSTONE: 1.6, VoxelTypes.GRANITE: 1.4,
	VoxelTypes.COBBLE: 2.4, VoxelTypes.STONE: 1.8, VoxelTypes.ROCK: 1.6,
	VoxelTypes.CONCRETE: 1.2, VoxelTypes.REBAR_CONCRETE: 1.2,
	VoxelTypes.CONCRETE_SLAB: 1.8,
	VoxelTypes.TIMBER: 2.4, VoxelTypes.PLANK: 2.6, VoxelTypes.DARK_OAK: 2.4,
	VoxelTypes.BARK: 3.5,
	VoxelTypes.THATCH: 3.0, VoxelTypes.CLAY_TILE: 2.6, VoxelTypes.ASPHALT_SHINGLE: 2.4,
	VoxelTypes.CORRUGATED_STEEL: 2.0,
	VoxelTypes.GRAVEL: 4.0, VoxelTypes.GRASS: 3.4, VoxelTypes.SAND: 2.8,
	VoxelTypes.DIRT: 2.6, VoxelTypes.CLAY: 2.4, VoxelTypes.LEAF: 3.2,
	VoxelTypes.FARMLAND: 2.6, VoxelTypes.WET_FARMLAND: 2.6,
	VoxelTypes.IRON_ORE: 2.4, VoxelTypes.ASPHALT: 1.6, VoxelTypes.EMBER: 3.0,
	VoxelTypes.CARBON_COMPOSITE: 4.0, VoxelTypes.SOLAR_PANEL: 1.0,
	VoxelTypes.SHEET_METAL: 1.2, VoxelTypes.STEEL_FRAME: 1.2,
	VoxelTypes.PLASTIC_PANEL: 1.2,
}

## How hard the baked normal map pushes. Stone and brick are read at arm's
## length and want their relief; painted trim is not, and overdriving it makes
## a wall look wet.
const NORMAL_STRENGTH := {
	VoxelTypes.BRICK: 1.0, VoxelTypes.SANDSTONE: 0.85, VoxelTypes.GRANITE: 0.8,
	VoxelTypes.COBBLE: 1.1, VoxelTypes.STONE: 0.8, VoxelTypes.ROCK: 1.0,
	VoxelTypes.CONCRETE: 0.6, VoxelTypes.REBAR_CONCRETE: 0.8,
	VoxelTypes.CONCRETE_SLAB: 0.6,
	VoxelTypes.TIMBER: 0.8, VoxelTypes.PLANK: 0.8, VoxelTypes.DARK_OAK: 0.8,
	VoxelTypes.BARK: 1.2,
	VoxelTypes.THATCH: 1.2, VoxelTypes.CLAY_TILE: 1.0, VoxelTypes.ASPHALT_SHINGLE: 1.0,
	VoxelTypes.CORRUGATED_STEEL: 1.0,
	VoxelTypes.GRAVEL: 1.2, VoxelTypes.GRASS: 1.0, VoxelTypes.SAND: 0.7,
	VoxelTypes.DIRT: 0.9, VoxelTypes.CLAY: 0.8, VoxelTypes.LEAF: 1.1,
	VoxelTypes.FARMLAND: 0.9, VoxelTypes.WET_FARMLAND: 0.7,
	VoxelTypes.IRON_ORE: 1.0, VoxelTypes.ASPHALT: 0.5, VoxelTypes.EMBER: 0.8,
	VoxelTypes.CARBON_COMPOSITE: 0.7, VoxelTypes.SOLAR_PANEL: 0.5,
	VoxelTypes.PAINTED_WHITE: 0.4, VoxelTypes.PAINTED_RED: 0.4,
	VoxelTypes.MATTE_BLACK: 0.4, VoxelTypes.CHROME: 0.4, VoxelTypes.SHEET_METAL: 0.5,
	VoxelTypes.STEEL_FRAME: 0.5, VoxelTypes.PLASTIC_PANEL: 0.5,
}

## How much the texture's own cavity darkening is allowed to bite. Ground
## materials lean on it because a flat field is the worst case for this shader;
## painted and glazed surfaces do not, since grime in a paint joint reads as dirt
## when the material is meant to be clean.
const AO_STRENGTH := {
	VoxelTypes.GRASS: 0.9, VoxelTypes.DIRT: 0.9, VoxelTypes.SAND: 0.7,
	VoxelTypes.GRAVEL: 0.9, VoxelTypes.COBBLE: 0.8, VoxelTypes.CLAY: 0.8,
	VoxelTypes.FARMLAND: 0.8, VoxelTypes.WET_FARMLAND: 0.7,
	VoxelTypes.BRICK: 0.8, VoxelTypes.STONE: 0.8, VoxelTypes.ROCK: 0.85,
	VoxelTypes.GRANITE: 0.75, VoxelTypes.SANDSTONE: 0.75,
	VoxelTypes.THATCH: 0.7, VoxelTypes.LEAF: 0.7, VoxelTypes.BARK: 0.8,
	VoxelTypes.IRON_ORE: 0.8,
	VoxelTypes.PAINTED_WHITE: 0.35, VoxelTypes.PAINTED_RED: 0.35,
	VoxelTypes.CHROME: 0.2, VoxelTypes.MATTE_BLACK: 0.3,
	VoxelTypes.GLASS: 0.1, VoxelTypes.REINFORCED_GLASS: 0.1,
	VoxelTypes.NEON_STRIP: 0.1, VoxelTypes.WATER: 0.1,
	VoxelTypes.CARBON_COMPOSITE: 0.4, VoxelTypes.SOLAR_PANEL: 0.3,
	VoxelTypes.SHEET_METAL: 0.4, VoxelTypes.STEEL_FRAME: 0.5,
	VoxelTypes.PLASTIC_PANEL: 0.45,
}


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
