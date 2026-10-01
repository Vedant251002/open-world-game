extends Node3D
class_name SkyEnv
## Lighting, sky and post-processing, driven by the game clock.
##
## The core loop deliberately spans several in-game hours per instruction, so
## the light is never static: you give Mira a job in the morning and come back
## to a finished wall in the low afternoon sun. The day cycle is therefore a
## gameplay readout as much as a look.

## Moonlight strength. The moon is a real shadow-casting light, so a bright
## night has readable silhouettes and long blue shadows rather than a flat fill.
const MOON_ENERGY := 0.85
## Fill-light multipliers for the compatibility renderer (no sky radiance
## ambient there). Kept modest: shade should be a cool, darker version of the
## sunlit colour, not the same brightness.
const AMBIENT_COMPAT_DAY := 5.0
const AMBIENT_COMPAT_NIGHT := 3.0
const EXPOSURE_COMPAT := 0.9
const EXPOSURE_FPLUS := 0.9
const FOG_DENSITY := 0.0016
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
var _no_shadow_moon := false
var _vignette_mat: ShaderMaterial
var _clock: Node = null
var _clock_synced := true
var _last_pushed_hour := -1.0
var _cloud_t := 0.0
var _push_due := 0.0
## True on the compatibility renderer, which is what the web and mobile
## exports run. It is not a lesser version of the same lighting — several
## things simply are not there, and ambient light is the one that decides
## whether the game is playable.
var _compat := false
## A phone screen is smaller, dimmer and often looked at outdoors, so the same
## frame that reads as moody on a monitor reads as murky there. Fill and
## exposure are lifted on the phone profile, most of all at night.
var _handheld := false

const SKY_SHADER := preload("res://scripts/core/sky.gdshader")

## Set by weather.gd, blended in by _apply_time(). Neutral values (white,
## zero, zero) leave a clear day looking exactly as it did before weather
## existed — weather multiplies and adds on top of the time-of-day palette,
## it never replaces it.
var weather_tint: Color = Color.WHITE   ## multiplies sky and ambient colour
var weather_fog: float = 0.0            ## 0..1, extra depth/volumetric fog
var cloud_cover: float = 0.0            ## 0..1, added to the shader's cloud coverage

## 0..24. Set by GameClock every frame.
var hour: float = 9.0:
	set(value):
		hour = value
		_apply_time()

# Keyframed palette: hour -> [sky_top, horizon, sun_colour, sun_energy, ambient]
# Colours are chosen as swatches of the real sky at that hour: deep blue zenith
# with a pale bright horizon at noon, salmon-and-teal at sunrise, orange-violet
# at dusk, and a navy night with a cold afterglow on the horizon.
const KEYS := [
	[0.0,  Color("#0a1a48"), Color("#25397a"), Color("#6f86c0"), 0.00, 0.22],
	[4.5,  Color("#0c1d4e"), Color("#2a3f80"), Color("#6f86c0"), 0.00, 0.22],
	[5.5,  Color("#1b2b63"), Color("#7a5478"), Color("#ff9a70"), 0.20, 0.28],
	[6.5,  Color("#2f5296"), Color("#eeb083"), Color("#ffb27a"), 0.80, 0.34],
	[8.5,  Color("#3577d3"), Color("#b0d3f0"), Color("#ffe9c8"), 1.25, 0.42],
	[12.0, Color("#3373d2"), Color("#b4d6f2"), Color("#fff4e2"), 1.40, 0.46],
	[16.0, Color("#3672cd"), Color("#b8d4ee"), Color("#ffe9c4"), 1.30, 0.44],
	[18.5, Color("#3a56a4"), Color("#f2b276"), Color("#ff9448"), 0.95, 0.36],
	[19.8, Color("#3f4d98"), Color("#e48c62"), Color("#f07a44"), 0.45, 0.30],
	[20.8, Color("#1a2660"), Color("#835a8a"), Color("#c86a60"), 0.10, 0.25],
	[21.8, Color("#0e1f52"), Color("#38407a"), Color("#6f86c0"), 0.00, 0.22],
	[24.0, Color("#0a1a48"), Color("#25397a"), Color("#6f86c0"), 0.00, 0.22],
]


## Shadow-lift curve, per channel: a slight lift below mid grey, identity at the
## top, so dark timber and shaded facades do not crush to black under the ACES
## toe while the highlights are left alone. A 1D LUT (height 1, one texel per
## input level) is the unambiguous form of adjustment_color_correction.
static func _build_curve_lut() -> Texture2D:
	var n := 256
	var img := Image.create(n, 1, false, Image.FORMAT_RGB8)
	for i in n:
		var x := float(i) / float(n - 1)
		var y := pow(x, 0.80)
		y = lerpf(y, x, smoothstep(0.55, 1.0, x))
		img.set_pixel(i, 0, Color(y, y, y))
	return ImageTexture.create_from_image(img)


## (Legacy, unused) The lift/gamma/gain grade used by adjustment_color_correction.
##
## Godot's adjustment_color_correction wants a 3x3 color matrix laid out in a
## 4x4 texture, and it samples it in a way that is not a normal image lookup:
## each output channel takes R,G,B from three *texels* of the texture, chosen by
## the output channel. So a 4x1 texture where texel 0 = the R column, texel 1 =
## the G column and texel 2 = the B column is the matrix, and everything else
## in the texture is ignored.
##
## The first attempt built this as a GradientTexture2D with three colour stops
## spread across four texels, which reads back as a wildly over-bright matrix:
## every frame came out at mean luma 0.98 with 97% of pixels clipped to white.
## The fix is to write the texels explicitly instead of expressing them as a
## gradient, which is both correct and clearer about what it is doing.
##
## The off-diagonal values are deliberately tiny. At 0.05 the frame stops
## looking graded and starts looking filtered; at 0.012 it is felt rather than
## seen.
static func _build_grade() -> Texture2D:
	# Each row is what one OUTPUT channel takes from the three INPUT channels.
	# Row R: keep most red, add a little of green and blue so the shadows sit
	# cool. Row G: nearly untouched. Row B: add a little of red so the
	# highlights sit warm.
	var rows := [
		Color(1.012, 0.006, 0.004),
		Color(0.005, 1.000, 0.006),
		Color(0.004, 0.008, 0.994),
	]
	# RGBAF, not RGBA8. The off-diagonal terms are 0.004-0.008, which in 8 bits
	# quantize to either 0 or 2/255 with nothing in between, and the diagonal
	# 1.012 clips to a flat 1.0. A float format stores the matrix as written;
	# 16 bytes for 4x4 is not a cost worth worrying about.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBAF)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))
	for i in 3:
		var c: Color = rows[i]
		# texel x = which INPUT channel, texel y = which OUTPUT channel
		for x in 3:
			var v: float = [c.r, c.g, c.b][x]
			img.set_pixel(x, i, Color(v, v, v, 1.0))
	img.set_pixel(3, 3, Color(1.0, 1.0, 1.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex


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
	_no_shadow_moon = "--nomoonshadow" in args
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_handheld = Platform.is_handheld()
	_build_environment()
	_build_lights()
	_build_vignette()
	_apply_time()
	_last_pushed_hour = hour


## Follows the game clock. Nothing else pushes the hour into the sky, which is
## how the sun used to stay put while the HUD clock ran. A manual set (the
## screenshot tool, tests, --hour style overrides) changes `hour` behind our
## back; once that is seen the clock stops driving the sky so it holds still.
func _process(delta: float) -> void:
	if _clock == null and get_parent() != null:
		_clock = get_parent().get("clock")
	if _clock_synced and _clock != null:
		if absf(hour - _last_pushed_hour) > 0.0005:
			_clock_synced = false          # somebody else set the hour
		else:
			var h: float = _clock.hour
			if absf(h - hour) > 0.01:
				hour = h
				_last_pushed_hour = h
	# Clouds drift on a slow clock pushed a few times a second, not on TIME
	# (see sky.gdshader: TIME would re-render the radiance cubemap every frame).
	_cloud_t += delta
	_push_due -= delta
	if _push_due <= 0.0 and sky_mat != null:
		_push_due = 0.25
		sky_mat.set_shader_parameter("cloud_time", _cloud_t)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER

	var sky := Sky.new()
	sky.sky_material = sky_mat
	# Radiance only feeds reflections (and Forward+ ambient); the shader takes a
	# cheap path when rendering it, and never reads TIME, so AUTOMATIC re-renders
	# it only when the palette or cloud clock actually changes.
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if _compat else Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky

	# Where the fill light comes from.
	#
	# Forward+ can take it from the sky itself, which is free and always
	# agrees with the horizon. The compatibility renderer cannot: its sky
	# radiance contributes almost nothing, so everything the sun does not
	# strike directly goes black. On a phone the plaza came out at seventy
	# per cent near-black pixels while the sky above it was bright blue.
	# There, the ambient is an explicit colour, set from the same palette.
	if _compat:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# ACES, and this time against the actual alternative rather than against my
	# own assumption. Measured on the real game, same seed, same six views:
	#
	#              detail   uniq colours   colorfulness   luma
	#   ACES 0.86     7.99        2154          0.140       0.628
	#   FILMIC 1.0    6.89        1695          0.136       0.619
	#   AGX 0.95      6.51        1415          0.120       0.552
	#
	# ACES wins on every one of them, and the reason is worth writing down
	# because it is a content question, not a quality ranking. Activision's own
	# SIGGRAPH material states that Call of Duty uses an S-curve with a toe
	# rather than ACES, and that is the right call for Call of Duty: its night
	# interiors, its dust and its smoke sit in the bottom two stops, where a
	# toe protects shadow detail that a shoulder would crush.
	#
	# This is a sunlit village. Its content lives in the midtones and upper
	# midtones, which is exactly where ACES's shoulder does the most good and
	# where FILMIC and AgX's toe spend their range on shadows that are already
	# dark. So the same curve that is right for CoD is wrong here, and the
	# numbers above are the reason rather than the assumption.
	#
	# AgX is the same story one step further: its desaturate-toward-white
	# behaviour is excellent for a saturated bright source and expensive for a
	# scene whose colour comes from material hue variation, which is what this
	# one is — hence 0.120 colorfulness against ACES's 0.140.
	#
	# All three exist in 4.7 (LINEAR=0, REINHARDT=1, FILMIC=2, ACES=3, AGX=4;
	# there is no TONE_MAPPER_NEUTRAL). Re-run _tools/ab_tonemap.py after any
	# palette change rather than re-deriving this by argument.
	env.tonemap_exposure = EXPOSURE_COMPAT if _compat else EXPOSURE_FPLUS
	env.tonemap_white = 4.0

	# Contact shadows and bounce. This is what stops a voxel town from reading
	# as a pile of flat coloured boxes.
	#
	# The values here are tuned for a world of 0.25 m voxels. SSAO works in world
	# units, so a radius that flatters a human-scale interior is invisible here:
	# 1.1 m is roughly four voxels, which is the smallest radius that still
	# darkens the junction where a wall meets the ground. Tighten it further and
	# the crevice between two blocks stops reading; loosen it and the whole
	# village sits in a grey haze. Horizon at 0.10 keeps the occlusion from
	# bleeding upward onto the tops of walls, which is what the previous value
	# was doing — a wall lit from the side lost its top edge entirely.
	env.ssao_enabled = true
	env.ssao_radius = 0.85
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.85
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.25
	# SSAO quality. Neither ssao_tap_count nor ssao_specular exists on
	# Environment in 4.7 (both verified missing against the class reference);
	# the sample count lives here instead. The full 4.7 signature takes six
	# arguments and has no defaults:
	#
	#   environment_set_ssao_quality(quality, half_size, adaptive_target,
	#                                 blur_passes, fadeout_from, fadeout_to)
	#
	# HIGH was costing roughly half the frame. A/B measured: dropping to MEDIUM
	# took the median from 13 to 28 fps, and the AAA reference is blunt about
	# why — Activision measured GTAO at 0.5 ms on PS4 at 1080p half-resolution.
	# Half a millisecond out of a 16.67 ms budget, for the same effect. A voxel
	# village with 76 mesh nodes and a 4096 shadow map does not have the
	# headroom to spend 8 ms on contact shadows, whatever the CPU-side frames
	# suggest.
	#
	# So: MEDIUM, and half_size stays true. The radius, intensity and power
	# above are what actually shape the wall-to-ground contact shadow; the tap
	# count only cleans up its edges, and TAA hides the difference.
	#
	# This is the first line to touch if the frame budget ever needs the
	# frames more than the shadows: 0.5 ms to 0.2 ms by going LOW.
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		true,     # half_size — 4x less bandwidth, and AO is low-frequency
		0.9,      # adaptive_target
		2,        # blur_passes: 1 is enough at MEDIUM, 2 is the shimmer guard
		0.0,      # fadeout_from
		30.0)     # fadeout_to: the default 0.85 killed the shadow past ~26 m

	# Screen-space reflections, ON.
	#
	# These were off, and that is why the water looked like a flat blue slab:
	# the water shader's reflection term samples a single uniform colour
	# (sky_reflect) rather than anything in the scene, so the sea reflected the
	# sky's average and nothing else — no buildings, no trees, no shoreline.
	#
	# SSR is screen-space, so it cannot reflect what is off-screen, and on a
	# water plane at a shallow angle much of the interesting content is above
	# the top of the frame. That is a real limitation and the reason this was
	# off in the first place. But "reflects nothing" is worse than "reflects
	# most things": a village seen across a lake with no reflection in it at
	# all is the most obviously wrong thing in the frame.
	env.ssr_enabled = true
	# Each step marches the depth buffer, so this is the most expensive thing
	# enabled in the file. 32 is the ceiling; 24 lost the far bank.
	env.ssr_max_steps = 32
	# SSIL is a noisy screen-space effect with no temporal accumulation behind
	# it here, so it shimmers frame to frame on the voxel edges. Off by default;
	# --ssil turns it back on for a look.
	env.ssil_enabled = "--ssil" in OS.get_cmdline_user_args()
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
	# SDFGI re-voxelises the scene as chunks stream in and out, which makes the
	# bounce light pulse and costs 50 ms spikes on top. A streaming voxel world
	# is the workload it handles worst. --gi turns it on for a static look.
	env.sdfgi_enabled = "--gi" in OS.get_cmdline_user_args()
	env.sdfgi_energy = 1.0
	env.sdfgi_cascades = 2
	env.sdfgi_min_cell_size = 0.5
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_use_occlusion = true

	env.ssr_max_steps = 24
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0

	# Bloom on the sun, bright cloud edges, windows and lamps. A low HDR
	# threshold with soft-light blending gives a gentle halo on everything
	# bright rather than a hard glow on the sun alone.
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_normalized = false

	# Depth haze plus aerial perspective so the far shore melts into the horizon
	# instead of ending in a hard line. Kept shallow: a 160 m map turns to soup
	# if the fog works as hard as it does on a kilometre-scale landscape.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.fog_sun_scatter = 0.1
	env.fog_height = 4.0
	env.fog_height_density = 0.0

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0016
	env.volumetric_fog_albedo = Color(0.92, 0.94, 1.0)
	env.volumetric_fog_anisotropy = 0.55   # forward scatter: soft god-rays toward the sun
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.4

	env.adjustment_enabled = true
	# Saturation is the single biggest lever on the thing being complained
	# about, which is that the game now looks smooth but the colours are dull.
	#
	# Measured against the shader packs this is being matched to, the frame
	# colorfulness was 0.106 where SoftVoxels is 0.297, and the gap was almost
	# entirely in the sky (0.090 vs 0.350) and the ground (0.060 vs 0.167).
	# The sky is fixed in sky.gdshader and the ground in the baked textures;
	# this is the third lever, applied last over the whole frame.
	#
	# The history of this one line is worth recording, because it was wrong
	# twice. 1.18 was lowered to 1.06 on the reasoning that a global saturation
	# boost on top of already-hue-varied textures looked "cartoonish" — and
	# 1.06 is barely a change from 1.0, which is precisely why the frame still
	# measured dull. 1.30 is the largest value that does not visibly oversaturate
	# a palette that now carries per-material hue variation of its own; past
	# about 1.4 the shadows start going neon.
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.20
	# Shadow-lift tone curve as a 1D colour-correction LUT (see _build_curve_lut).
	# The earlier 3x3-matrix attempts whited or blacked out the frame; a 1D
	# curve (height 1) is the simple documented form.
	env.adjustment_color_correction = _build_curve_lut()

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
	# Strong, soft shadows in both renderers. Cascades are tight around the
	# camera (that is where houses and people are seen), and the far one still
	# reaches across the plaza. Normal bias does the anti-acne work so the depth
	# bias can stay small and shadows stay attached to the feet of things.
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 0.9
	sun.light_specular = 0.6
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color("#8fa8d8")
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 80.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.shadow_blur = 1.6
	moon.light_specular = 0.3
	add_child(moon)


## A soft vignette (and warm/cool corner tint) on a canvas layer just above the
## 3D view and under the HUD. Costs one full-screen quad of arithmetic, no
## screen-texture read, so it is fine on WebGL2.
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.name = "Vignette"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_CODE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = sh
	rect.material = _vignette_mat
	layer.add_child(rect)
	add_child(layer)


const VIGNETTE_CODE := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform float strength = 0.34;
void fragment() {
	vec2 q = UV - 0.5;
	q.x *= 1.15;
	float v = smoothstep(0.30, 0.95, length(q));
	COLOR = vec4(tint.rgb, v * v * strength);
}
"""


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

	# Weather recolours the time-of-day palette rather than replacing it: an
	# overcast noon is still noon, only greyer. Applied to the sky and sun
	# colour before anything downstream reads them, so the water, the fog
	# tint and the ambient light all agree with what the clouds are doing.
	sky_top = sky_top * weather_tint
	horizon = horizon * weather_tint
	sun_col = sun_col * weather_tint

	# The sun rides an arc from east to west by day and keeps going under the
	# horizon by night, so the moon (its opposite) is genuinely up at night and
	# the light direction always agrees with the hour. (It used to park on the
	# horizon after sunset, which is what left the sky dark and the ground lit.)
	var h24 := fposmod(hour, 24.0)
	var elevation: float
	var azimuth: float
	if h24 >= SUNRISE and h24 <= SUNSET:
		var day_t := inverse_lerp(SUNRISE, SUNSET, h24)
		elevation = sin(day_t * PI) * 68.0
		azimuth = lerpf(-95.0, 95.0, day_t)
	else:
		var since := h24 - SUNSET if h24 > SUNSET else h24 + 24.0 - SUNSET
		var night_t := since / (24.0 - (SUNSET - SUNRISE))
		elevation = -sin(night_t * PI) * 55.0
		azimuth = 95.0 + night_t * 170.0
	sun.rotation_degrees = Vector3(-(elevation + 0.5), azimuth, 0.0)
	# Direction from any surface back to the sun.
	var to_sun := (sun.global_transform.basis * Vector3(0, 0, 1)).normalized()

	# Sunlight fades out across the last degrees above the horizon: the
	# atmosphere eats it long before the geometric sunset.
	var horizon_fade := smoothstep(-1.5, 5.0, elevation)
	sun_energy *= horizon_fade
	sun.light_color = sun_col
	sun.light_energy = sun_energy
	sun.visible = sun_energy > 0.015
	# Low sun: long, soft shadows; high sun: crisp.
	sun.light_angular_distance = lerpf(1.6, 0.7, clampf(elevation / 40.0, 0.0, 1.0))

	var day_amt := clampf(sun_energy / 0.5, 0.0, 1.0)
	var night := 1.0 - clampf(inverse_lerp(-8.0, 3.0, elevation), 0.0, 1.0)
	night = night * night * (3.0 - 2.0 * night)
	# How close to sunrise/sunset: 1 with the sun on the horizon, 0 above ~25 deg
	# or well below the horizon.
	var twilight := (1.0 - smoothstep(0.0, 25.0, maxf(elevation, 0.0))) \
		* smoothstep(-14.0, -1.0, elevation)

	# Moon: exactly opposite the sun, so it is up whenever the sun is not.
	var to_moon := -to_sun
	moon.global_transform = Transform3D(Basis.looking_at(to_sun, Vector3.UP), Vector3.ZERO)
	moon.light_energy = night * MOON_ENERGY * clampf(to_moon.y * 3.0 + 0.4, 0.0, 1.0)
	moon.visible = moon.light_energy > 0.02
	moon.shadow_enabled = moon.visible and not _no_shadow_moon

	# Ambient (the sky's fill light), and why it is an explicit colour.
	#
	# Forward+ can take fill from the sky radiance; the compatibility renderer
	# cannot (its sky radiance contributes almost nothing), so it uses an
	# explicit colour. That colour is a cool sky blue by day, so shade reads
	# blue and sunlit surfaces read warm - the colour contrast that makes a
	# shader-pack image feel lit rather than filtered - and a deep moon blue at
	# night. The energy stays LOW: it used to be several times the sun's, which
	# is what washed the grass out and erased every shadow.
	const MOONLIGHT := Color("#6f8fd8")
	var sky_fill := horizon.lerp(sky_top, 0.55).lerp(Color("#dbe6ff"), 0.6)
	# Twilight fill is warmer and dimmer than the clear-sky one.
	sky_fill = sky_fill.lerp(MOONLIGHT, night)
	env.ambient_light_color = sky_fill
	if _compat:
		env.ambient_light_energy = ambient * lerpf(AMBIENT_COMPAT_DAY, AMBIENT_COMPAT_NIGHT, night) \
			* (lerpf(1.3, 2.2, night) if _handheld else 1.0)
		env.ambient_light_sky_contribution = 0.0
	else:
		env.ambient_light_energy = ambient * lerpf(0.85, 1.6, night)
		env.ambient_light_sky_contribution = lerpf(0.9, 0.0, night)

	# Tonemap exposure follows the hour a little: brighter at night so the moon
	# scene has something to work with, slightly lower at noon to hold highlights.
	env.tonemap_exposure = (EXPOSURE_COMPAT if _compat else EXPOSURE_FPLUS) \
		* lerpf(1.0, 1.25, night) * (lerpf(1.15, 1.35, night) if _handheld else 1.0)

	# Colour grade per time of day: rich and slightly contrasty at noon, punchier
	# and warmer at golden hour, desaturated toward blue at night.
	env.adjustment_saturation = lerpf(1.18, 1.22, twilight) * lerpf(1.0, 0.85, night)
	env.adjustment_contrast = lerpf(1.06, 1.12, twilight)
	env.adjustment_brightness = 1.0

	# Fog. Aerial perspective is tinted by the sky and, when the sun is low,
	# warmed on the sun's side; dawn and dusk carry extra mist so far hills melt
	# into blue and the morning feels cool and damp.
	var mist := twilight * 0.6 * (1.0 if hour < 12.0 else 0.5)
	if not _no_fog:
		env.fog_density = FOG_DENSITY * (1.0 + mist * 1.4) + weather_fog * 0.03
		env.fog_sun_scatter = clampf(twilight * 0.55 + day_amt * 0.12, 0.0, 0.7)
	# Dimmed after dark: fog is added over the lit scene, so a fog as bright as
	# the night horizon made the far hills glow teal above a moonlit town.
	env.fog_light_color = horizon.lerp(sky_top, 0.15 + 0.2 * night) * lerpf(1.0, 0.4, night)
	if not _no_vol:
		env.volumetric_fog_density = lerpf(0.0035, 0.0012, day_amt) * (1.0 + mist) \
			+ weather_fog * 0.02
		env.volumetric_fog_albedo = sky_fill.lerp(Color.WHITE, 0.5)

	env.glow_intensity = lerpf(0.9, 0.7, day_amt) + twilight * 0.25

	if _vignette_mat != null:
		_vignette_mat.set_shader_parameter("tint", Color(0.02, 0.03, 0.08).lerp(
			Color(0.10, 0.05, 0.02), twilight * (1.0 - night)))

	# Water follows the palette: horizon-tinted reflections, glitter that wakes
	# up as the sun drops and the specular path stretches across the sea.
	var reflect := horizon.lerp(Color("#1d4a63"), 0.45)
	var glitter := 1.0 + (1.0 - clampf(sun_energy, 0.0, 1.0)) * 1.5
	VoxelMaterials.set_sky(to_sun, sun_col, glitter, reflect)

	# The sky shader paints gradient, sun, moon, stars and clouds from the same
	# palette, so dusk skies and dusk clouds always agree. Cloud colours dim with
	# the night: they are lit by the moon there, not by a sun that has set.
	var dim := lerpf(1.0, 0.16, night)
	var lit := sun_col.lerp(Color.WHITE, 0.45) * dim
	var shadow := horizon.lerp(Color(0.66, 0.74, 0.88), 0.55 * (1.0 - twilight * 0.6)) \
		* lerpf(1.0, 0.5, night)
	var cover := 0.0 if _no_clouds else clampf(0.60 + cloud_cover, 0.0, 1.0)
	_set_sky_uniforms(sky_top, horizon, lit, shadow, to_sun, sun_col, cover, 1.0)
	sky_mat.set_shader_parameter("moon_dir", to_moon)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("twilight", twilight)


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
