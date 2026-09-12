class_name Quality
## One place where the game admits it is running on a phone.
##
## The desktop build is tuned for a discrete GPU: 4x MSAA, high-quality soft
## shadows, a whisper of far-field depth of field. On a handheld — which in
## practice means the web build under gl_compatibility — most of that is either
## unaffordable or silently unsupported, and the parts that do survive cost
## frames the streaming world needs. So we strip it once, at boot, instead of
## scattering `if mobile` through the render code.

const HANDHELD_RENDER_SCALE := 0.8   ## render at 80%, present at native
const HANDHELD_LOAD_RADIUS := 7      ## 56 m of full-detail voxels, down from 80
const HANDHELD_KEEP_RADIUS := 9
const HANDHELD_PRIME_RADIUS := 4


## Call before ChunkStreamer.prime(): the streaming radii have to be right
## before the first ring of columns is queued, or we pay for the wide load once
## anyway and only save on the ones after it.
static func apply(viewport: Viewport, plr: Player, streamer: ChunkStreamer) -> void:
	if not Platform.is_handheld():
		_trim_desktop(viewport)
		return

	# Screen-space AA does not exist under gl_compatibility and MSAA on a tile
	# GPU costs more bandwidth than the aliasing costs us. Render below native
	# and let the panel upscale; at phone pixel densities it reads as soft, not
	# as broken.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = HANDHELD_RENDER_SCALE

	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_HARD)

	if plr != null:
		plr.set_low_spec(true)

	if streamer != null:
		streamer.load_radius = HANDHELD_LOAD_RADIUS
		streamer.keep_radius = HANDHELD_KEEP_RADIUS
		streamer.prime_radius = HANDHELD_PRIME_RADIUS

	print("[delegate] handheld profile: render %.0f%%, load radius %d" % [
		HANDHELD_RENDER_SCALE * 100.0, HANDHELD_LOAD_RADIUS])


## Everything that is not a phone, which is two rather different machines.
##
## The native build runs Vulkan on a desktop GPU and can afford almost anything
## — except that what it was asking for included both 4x MSAA and temporal
## anti-aliasing. Those do the same job. TAA resolves edges over time and is
## already paid for; MSAA on top of it is four samples of colour and depth per
## pixel for an improvement nobody has ever been able to point at in a
## screenshot. Dropping it is the single cheapest frame in the project.
##
## The web build is the one that was actually being neglected. A desktop
## browser is not "handheld" by any test here — no touchscreen, no mobile
## feature flag — so it fell through to the full desktop profile and then ran
## it through gl_compatibility, where TAA does not exist, MSAA costs a great
## deal more than it does under Vulkan, and every draw call is a WebGL call.
## That is the configuration most likely to be behind "it lags", because it is
## the one anybody can reach by opening a link.
static func _trim_desktop(viewport: Viewport) -> void:
	viewport.msaa_3d = Viewport.MSAA_DISABLED

	if not Platform.is_web():
		print("[delegate] desktop profile: TAA, no MSAA")
		return

	viewport.use_taa = false
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	print("[delegate] desktop web profile: FXAA, no MSAA, cheap shadows")
