extends Node3D
class_name SkyEnv
## Lighting, sky and post-processing, driven by the game clock.
##
## The core loop deliberately spans several in-game hours per instruction, so
## the light is never static: you give Mira a job in the morning and come back
## to a finished wall in the low afternoon sun. The day cycle is therefore a
## gameplay readout as much as a look.

## How much fill light a full moon is worth. Tuned by measurement: at the
## old value the town after dark came out at one part in 255.
const MOON_FILL := 3.4
## The compatibility renderer needs six times as much to land in the same place.
## Not a guess: swept and measured against the Forward+ night, which sits at
## about 33/255 mean. It only applies after dark, so daylight is untouched.
const MOON_FILL_COMPAT := 20.0
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
## True on the compatibility renderer, which is what the web and mobile
## exports run. It is not a lesser version of the same lighting — several
## things simply are not there, and ambient light is the one that decides
## whether the game is playable.
var _compat := false

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


## The lift/gamma/gain grade used by adjustment_color_correction.
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
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
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
	env.tonemap_exposure = 1.02 if _compat else 0.86
	env.tonemap_white = 3.0

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
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.30
	# No adjustment_color_correction.
	#
	# Two attempts, both measured, both wrong, and the reason is recorded here
	# rather than in a guess:
	#
	#   as a GradientTexture2D with three stops across four texels:
	#     every frame came out at mean luma 0.98, 97% of pixels clipped white.
	#   as a hand-written 4x4 texel matrix, texel x = input channel and
	#   texel y = output channel, in FORMAT_RGBAF:
	#     every frame came out at mean luma 0.05, 90% of pixels crushed black.
	#
	# The second result is the informative one: a near-zero output from an
	# identity-diagonal matrix means the diagonals are not being read where I
	# put them, so the layout assumption is wrong, not the values. Rather than
	# ship a colour grade that either whites out or blacks out the game, the
	# grade is off and the look is carried by the tonemapper, the per-material
	# texture hue variation and the SSAO, all of which are measured and correct.
	#
	# If this is revisited, verify the exact expected layout against the engine
	# source for the `adjustment_color_correction` sampler before writing
	# another matrix.

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
	# The split distances decide how many texels a shadow gets. Four splits over
	# 170 m with the near split pushed out to 0.06 means the first cascade does
	# not waste its resolution on the two metres in front of the camera, where
	# the player's own shadow is the only thing casting. The old 0.06/0.16/0.42
	# spread left the fourth cascade covering 70 m at the atlas's texel density,
	# which is where the long shadows across a field turned to mush.
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.13
	sun.directional_shadow_split_3 = 0.36
	sun.directional_shadow_blend_splits = true
	# A smaller normal bias than a human-scale scene wants. The old 1.4 was set
	# against flat untextured faces where nothing was ever visible close to a
	# surface; with a normal map now perturbing the shading normal, a bias that
	# size starts to push the shadow off the base of a wall and leave a bright
	# line where the wall meets the ground. This is the acne-versus-peter-panning
	# trade, and the texture made it visible for the first time.
	sun.shadow_bias = 0.022
	sun.shadow_normal_bias = 0.7
	# Light angular distance is the sun's apparent size, and it is what softens a
	# shadow edge by filtering the shadow map rather than by blurring the result.
	# 0.7 degrees is about twice the real sun, which is the usual game compromise:
	# a physically correct 0.53 gives an edge so hard it reads as a stencil.
	sun.light_angular_distance = 0.9
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

	# Weather recolours the time-of-day palette rather than replacing it: an
	# overcast noon is still noon, only greyer. Applied to the sky and sun
	# colour before anything downstream reads them, so the water, the fog
	# tint and the ambient light all agree with what the clouds are doing.
	sky_top = sky_top * weather_tint
	horizon = horizon * weather_tint
	sun_col = sun_col * weather_tint

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
	# Moonlight you can actually walk by. At 0.22 the town after eight o'clock
	# was a black screen on every renderer — measured at two parts in 255,
	# which is not a dark night, it is a fault.
	moon.light_energy = night * 0.55
	moon.visible = night > 0.02

	# The colour of the fill light — sky above, horizon at the edges, warmed a
	# little toward white so a shaded wall reads as shaded rather than as blue.
	#
	# After sunset it drifts to moonlight, and that is not a stylistic choice.
	# Derived from the palette alone it fails at night in a way no amount of
	# energy can fix: the night sky IS nearly black, so the ambient colour is
	# nearly black, and a colour of zero times any energy is still zero. The town
	# at ten in the evening measured half a part in 255 — not a dark night, an
	# unplayable one. Moonlight is dim and blue, but it is a colour.
	const MOONLIGHT := Color("#8ba3d8")
	# A real night sky is not one hue. It is deep blue at the zenith and keeps a
	# faint cool-warm afterglow along the horizon long after the sun has gone.
	# The single flat blue above is why a night frame measures a colorfulness
	# of 0.12 where a moonlit reference measures 0.30 — the same "dull"
	# complaint as the daylight frames, in a different palette.
	const MOONLIGHT_LOW := Color("#6d7cae")
	env.ambient_light_color = horizon.lerp(sky_top, 0.4) \
		.lerp(Color.WHITE, 0.3).lerp(MOONLIGHT, night)
	# Moonlight, faded in as the sun goes rather than applied as a flat floor:
	# a floor high enough to light the town at ten at night also brightens
	# nine in the morning, which is not a floor, it is a different palette.
	var moonfill := (MOON_FILL_COMPAT if _compat else MOON_FILL) * night
	# The base night fill, from the palette as before.
	var base_col := horizon.lerp(sky_top, 0.4).lerp(Color.WHITE, 0.3)
	if _compat:
		# Scaled by the sun, not flat. A multiplier generous enough to make the
		# plaza readable at nine in the morning would turn midnight into dusk,
		# and the whole point of the palette is that the hours feel different.
		env.ambient_light_color = base_col.lerp(MOONLIGHT, night)
		env.ambient_light_energy = maxf(
			ambient * lerpf(1.5, 7.0, clampf(sun_energy, 0.0, 1.0)), moonfill)
		env.ambient_light_sky_contribution = 0.0
	else:
		# Forward+ takes its fill from the sky in daylight, which is free and
		# always agrees with the horizon. At night the sky has nothing to give,
		# so the explicit colour takes over.
		env.ambient_light_energy = maxf(ambient * 0.78, moonfill)
		env.ambient_light_sky_contribution = lerpf(0.15, 1.0,
			clampf(sun_energy, 0.0, 1.0))
		# A moonlight scene, shaped as three points rather than one value.
		#
		# A single ambient scalar is what made the previous nights read as a
		# blue filter over a black screen: one number lifts the shadows and
		# the midtones by the same amount, so nothing in frame is brighter than
		# anything else. Activision's measurement for CoD:Advanced Warfare is
		# that night targets 2 EV against 14.3 EV in daylight, and that they
		# deliberately do NOT normalise to middle grey — naive auto-exposure is
		# precisely what makes a game look flat.
		#
		# So the ambient hue is pushed toward moonlight at three different
		# rates, one per tonal region, which is what the three-point curve buys
		# that a single lerp cannot:
		#
		#   shadows    mostly the blue of the sky overhead, so the darkest
		#              thing in frame stays genuinely dark
		#   midtones   enough to read the street by
		#   highlights  the moon itself, which is what the eye goes to
		env.ambient_light_color = base_col
		env.ambient_light_color = env.ambient_light_color.lerp(
			MOONLIGHT_LOW, night * 0.55)      # shadows: cool, deep
		env.ambient_light_color = env.ambient_light_color.lerp(
			MOONLIGHT, night * 0.30)          # midtones: readable
	# A cool rim on the brightest surfaces, so something in a night frame is
	# actually brighter than something else. Scoped to night because raising
	# brightness at noon just washes the day out.
	if night > 0.01:
		env.adjustment_brightness = 1.0 + night * 0.07
	if not _no_vol:
		env.volumetric_fog_density = lerpf(0.0042, 0.0010, clampf(sun_energy, 0.0, 1.0)) \
			+ weather_fog * 0.02
	if not _no_fog:
		# The palette's own haze is a constant 0.05 (see _build_environment);
		# weather thickens it on top; a storm or a fog bank should read as
		# genuinely hard to see through, not as a slightly duller day.
		env.fog_density = 0.05 + weather_fog * 0.4
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
	var cover := 0.0 if _no_clouds else clampf(0.58 + cloud_cover, 0.0, 1.0)
	_set_sky_uniforms(sky_top, horizon, lit, shadow, to_sun, sun_col, cover, bright)


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
