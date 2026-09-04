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
