extends Node3D
class_name SkyEnv
## Lighting, sky and post-processing, driven by the game clock.
##
## The core loop deliberately spans several in-game hours per instruction, so
## the light is never static: you give Mira a job in the morning and come back
## to a finished wall in the low afternoon sun. The day cycle is therefore a
## gameplay readout as much as a look.

const SUNRISE := 6.0
const SUNSET := 20.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var sea_material: StandardMaterial3D

var _no_vol := false
var _no_fog := false
var _no_ssao := false
var _no_ssr := false
var _no_sea := false
var _no_gi := false
var _no_clouds := false

const SKY_SHADER := preload("res://scripts/core/sky.gdshader")

## 0..24. Set by GameClock every frame.
var hour: float = 9.0:
	set(value):
		hour = value
		_apply_time()

# Keyframed palette: hour -> [sky_top, horizon, sun_colour, sun_energy, ambient]
const KEYS := [
	[0.0,  Color("#050a18"), Color("#0d1424"), Color("#5a6a90"), 0.04, 0.10],
	[5.0,  Color("#0b1430"), Color("#2a2740"), Color("#7a6a80"), 0.07, 0.16],
	[6.5,  Color("#2a3f74"), Color("#d98a5e"), Color("#ffb07a"), 0.50, 0.30],
	[8.5,  Color("#3f77c4"), Color("#a9c6e0"), Color("#ffeed2"), 0.88, 0.46],
	[12.0, Color("#2f6fd0"), Color("#bcd6ec"), Color("#fff8ec"), 1.00, 0.52],
	[16.0, Color("#3a72c8"), Color("#c0d4e6"), Color("#fff0d6"), 0.92, 0.50],
	[18.5, Color("#3a548f"), Color("#f0984f"), Color("#ff9e57"), 0.68, 0.36],
	[20.0, Color("#22305e"), Color("#c4633c"), Color("#dd8153"), 0.34, 0.24],
	[21.5, Color("#0d1631"), Color("#3a3450"), Color("#6a6a92"), 0.07, 0.14],
	[24.0, Color("#050a18"), Color("#0d1424"), Color("#5a6a90"), 0.04, 0.10],
]


## Debug switches, so an effect can be bisected without editing code:
##   -- --novol   volumetric fog off
##   -- --nofog   depth fog off
##   -- --nossao  screen-space AO and IL off
##   -- --nossr   screen-space reflections off
##   -- --nogi    SDFGI bounce light off
##   -- --noclouds  cloud layer off (clear sky)
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_no_vol = "--novol" in args
	_no_fog = "--nofog" in args
	_no_ssao = "--nossao" in args
	_no_ssr = "--nossr" in args
	_no_sea = "--nosea" in args
	_no_gi = "--nogi" in args
	_no_clouds = "--noclouds" in args
	_build_environment()
	_build_lights()
	_apply_time()


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.78
	env.tonemap_white = 3.0

	# Contact shadows and bounce. This is what stops a voxel town from reading
	# as a pile of flat coloured boxes.
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.5
	env.ssao_power = 1.4
	env.ssao_detail = 0.7
	env.ssao_horizon = 0.10

	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.32
	env.ssil_sharpness = 0.98

	# Real-time bounce light: sunlight scattered off ground and walls fills the
	# shadowed facades direct light can never reach. The map is ~160 m wide so
	# the default cascade layout covers it several times over; cost is small.
	# SDFGI defaults are laid out for kilometre-scale landscapes: four cascades
	# reaching hundreds of metres. On a 160 m island that is mostly empty space
	# being re-voxelised every time the camera moves, and it showed up as 50 ms
	# frame spikes. Two tight cascades cover the whole map and cost about a
	# third as much.
	env.sdfgi_enabled = true
	env.sdfgi_energy = 1.0
	env.sdfgi_cascades = 2
	env.sdfgi_min_cell_size = 0.5
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_use_occlusion = true

	env.ssr_enabled = false
	env.ssr_max_steps = 24
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0

	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Depth haze plus aerial perspective so the far shore melts into the horizon
	# instead of ending in a hard line. Kept shallow: a 160 m map turns to soup
	# if the fog works as hard as it does on a kilometre-scale landscape.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 0.05
	env.fog_sky_affect = 0.08
	env.fog_aerial_perspective = 0.35
	env.fog_depth_begin = 130.0
	env.fog_depth_end = 900.0
	env.fog_depth_curve = 1.6

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0018
	env.volumetric_fog_albedo = Color(0.92, 0.94, 1.0)
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.4

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.18

	if _no_vol:
		env.volumetric_fog_enabled = false
	if _no_fog:
		env.fog_enabled = false
	if _no_ssao:
		env.ssao_enabled = false
		env.ssil_enabled = false
	if _no_gi:
		env.sdfgi_enabled = false
	if _no_ssr:
		env.ssr_enabled = false

	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 0.7
	sun.light_specular = 0.6
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color("#8fa8d8")
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)


func _sample(h: float) -> Array:
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = inverse_lerp(a[0], b[0], h)
			t = smoothstep(0.0, 1.0, t)
			return [
				(a[1] as Color).lerp(b[1], t),
				(a[2] as Color).lerp(b[2], t),
				(a[3] as Color).lerp(b[3], t),
				lerpf(a[4], b[4], t),
				lerpf(a[5], b[5], t),
			]
	var last: Array = KEYS[KEYS.size() - 1]
	return [last[1], last[2], last[3], last[4], last[5]]


func _apply_time() -> void:
	if sun == null:
		return
	var k := _sample(fposmod(hour, 24.0))
	var sky_top: Color = k[0]
	var horizon: Color = k[1]
	var sun_col: Color = k[2]
	var sun_energy: float = k[3]
	var ambient: float = k[4]

	# Sun rides an arc from east to west between sunrise and sunset.
	var day_t := clampf(inverse_lerp(SUNRISE, SUNSET, hour), 0.0, 1.0)
	var elevation := sin(day_t * PI) * 68.0 + 2.0
	var azimuth := lerpf(-95.0, 95.0, day_t)
	sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	sun.light_color = sun_col
	sun.light_energy = sun_energy
	sun.visible = sun_energy > 0.02

	var night := clampf(1.0 - sun_energy / 0.4, 0.0, 1.0)
	moon.rotation_degrees = Vector3(-55.0, azimuth + 180.0, 0.0)
	moon.light_energy = night * 0.22
	moon.visible = night > 0.02

	env.ambient_light_energy = ambient * 0.58
	env.ambient_light_sky_contribution = 1.0
	if not _no_vol:
		env.volumetric_fog_density = lerpf(0.0042, 0.0010, clampf(sun_energy, 0.0, 1.0))
	env.fog_light_color = horizon

	env.glow_intensity = lerpf(1.00, 0.50, clampf(sun_energy, 0.0, 1.0))

	# Direction from any surface back to the sun, for the water glitter and the
	# cloud shading. The sun node shines down its -Z, so +Z points at the sun.
	var to_sun := (sun.global_transform.basis * Vector3(0, 0, 1)).normalized()
	# Water follows the palette: horizon-tinted reflections, glitter that wakes
	# up as the sun drops and the specular path stretches across the sea.
	var reflect := horizon.lerp(Color("#1d4a63"), 0.45)
	var glitter := 1.0 + (1.0 - clampf(sun_energy, 0.0, 1.0)) * 1.5
	VoxelMaterials.set_sky(to_sun, sun_col, glitter, reflect)
	# The sky shader paints gradient, sun halo, clouds and sea haze from the
	# same palette, so dusk skies and dusk clouds always agree.
	var lit := sun_col.lerp(Color.WHITE, 0.35)
	var shadow := horizon.lerp(Color("#5a6a86"), 0.45)
	var bright := clampf(sun_energy * 1.25 + 0.10, 0.0, 1.0)
	_set_sky_uniforms(sky_top, horizon, lit, shadow, to_sun, sun_col,
		0.0 if _no_clouds else 0.58, bright)


## Pushes the palette into the sky shader. Colours arrive sRGB and are
## converted to linear because the shader takes raw vec3 uniforms that Godot
## will not convert for us.
func _set_sky_uniforms(top: Color, hor: Color, lit: Color, shadow: Color,
		to_sun: Vector3, tint: Color, cover: float, bright: float) -> void:
	var t := top.srgb_to_linear()
	var h := hor.srgb_to_linear()
	var li := lit.srgb_to_linear()
	var sh := shadow.srgb_to_linear()
	var ti := tint.srgb_to_linear()
	sky_mat.set_shader_parameter("sky_top", Vector3(t.r, t.g, t.b))
	sky_mat.set_shader_parameter("sky_horizon", Vector3(h.r, h.g, h.b))
	sky_mat.set_shader_parameter("cloud_lit", Vector3(li.r, li.g, li.b))
	sky_mat.set_shader_parameter("cloud_shadow", Vector3(sh.r, sh.g, sh.b))
	sky_mat.set_shader_parameter("sun_dir", to_sun)
	sky_mat.set_shader_parameter("sun_tint", Vector3(ti.r, ti.g, ti.b))
	sky_mat.set_shader_parameter("coverage", cover)
	sky_mat.set_shader_parameter("brightness", bright)


## Kept as a no-op hook: the far-field sea is painted by the sky shader's
## below-horizon haze in _apply_time, which costs nothing and does not have to
## be depth-sorted against 400 chunk meshes.
func add_horizon(_water_y_m: float, _centre: Vector3) -> void:
	pass


func is_night() -> bool:
	return hour < SUNRISE - 0.5 or hour > SUNSET + 0.5
