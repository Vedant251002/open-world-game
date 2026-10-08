class_name GraphicsSettings
## The player's graphics choices on a desktop build: a quality preset, render
## scale, view distance, vsync and a frame cap.
##
## Quality.apply() decides what a platform can do at all; this decides what the
## person in front of it wants. It runs after Quality.apply() at boot, and
## again whenever a setting changes in the pause menu, so every knob here has to
## be safe to turn while the world is running.
##
## The first boot has no saved choice, so the preset is picked from the GPU:
## an integrated or software adapter starts on Medium or Low rather than on the
## settings a discrete card was tuned for. That one decision is most of the
## difference between "runs" and "lags" on a laptop.
##
## Stored in user://settings.cfg, [graphics], beside the audio and voice rows.
## Handheld and web builds keep the Quality profile and never read this.

const PATH := "user://settings.cfg"

enum Preset { LOW, MEDIUM, HIGH, ULTRA }
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]

## Chunk columns of full-detail voxels around the player, per view distance
## step. Each column is 8 m; keep is the unload hysteresis.
const VIEW_LOAD: Array[int] = [6, 8, 10, 12]
const VIEW_KEEP: Array[int] = [8, 11, 13, 15]
const VIEW_NAMES: Array[String] = ["Short", "Medium", "Far", "Very far"]

const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144, 240]

static var preset := Preset.HIGH
static var render_scale := 1.0
static var view := 2
static var vsync := true
static var max_fps := 0

static var _loaded := false
static var _viewport: Viewport
static var _sky: SkyEnv
static var _streamer: ChunkStreamer


## True where the settings apply: a native desktop build. The phone and browser
## profiles in Quality are tuned for hardware these presets would overwhelm.
static func applies() -> bool:
	return not Platform.is_handheld() and not Platform.is_web() \
		and DisplayServer.get_name() != "headless"


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var auto := _auto_preset()
	_set_preset_values(auto)
	# -- --quality=low|medium|high|ultra: a one-run override for benches and
	# for anybody whose saved settings will not let the game start.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			var i := PRESET_NAMES.find(a.substr(10).capitalize())
			if i >= 0:
				_set_preset_values(i)
				return
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK or not cf.has_section("graphics"):
		return
	preset = clampi(int(cf.get_value("graphics", "preset", auto)), 0, 3) as Preset
	render_scale = clampf(float(cf.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	view = clampi(int(cf.get_value("graphics", "view", view)), 0, VIEW_LOAD.size() - 1)
	vsync = bool(cf.get_value("graphics", "vsync", vsync))
	max_fps = maxi(int(cf.get_value("graphics", "max_fps", max_fps)), 0)


static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("graphics", "preset", int(preset))
	cf.set_value("graphics", "render_scale", render_scale)
	cf.set_value("graphics", "view", view)
	cf.set_value("graphics", "vsync", vsync)
	cf.set_value("graphics", "max_fps", max_fps)
	cf.save(PATH)


## Picking a preset resets the other knobs to what that preset implies; they
## can be moved individually afterwards.
static func choose_preset(p: int) -> void:
	_set_preset_values(clampi(p, 0, 3))
	apply()


static func _set_preset_values(p: int) -> void:
	preset = p as Preset
	match preset:
		Preset.LOW:
			render_scale = 0.67
			view = 0
		Preset.MEDIUM:
			render_scale = 0.85
			view = 1
		Preset.HIGH:
			render_scale = 1.0
			view = 2
		Preset.ULTRA:
			render_scale = 1.0
			view = 3


## A guess for the first boot only. Integrated GPUs share memory bandwidth with
## the CPU, which is exactly what SSR, SSAO and four shadow cascades eat.
static func _auto_preset() -> int:
	if not applies():
		return Preset.HIGH
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_CPU:
			return Preset.LOW
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return Preset.MEDIUM
	return Preset.HIGH


## Called once at boot, after Quality.apply() and before the streamer primes.
static func attach(viewport: Viewport, sky: SkyEnv, streamer: ChunkStreamer) -> void:
	_viewport = viewport
	_sky = sky
	_streamer = streamer
	load_settings()
	if not applies():
		return
	apply()
	print("[delegate] graphics: %s, render %d%%, view %s, vsync %s, fps cap %s" % [
		PRESET_NAMES[preset], int(render_scale * 100.0), VIEW_NAMES[view],
		"on" if vsync else "off", str(max_fps) if max_fps > 0 else "none"])


static func apply() -> void:
	if not applies():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync
		else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps

	if _viewport != null and is_instance_valid(_viewport):
		var vp := _viewport
		# FSR 1 rather than bilinear below native: it sharpens the upscale, so a
		# render scale of 0.67 reads as soft rather than as blurred.
		vp.scaling_3d_scale = render_scale
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.999 \
			else Viewport.SCALING_3D_MODE_BILINEAR
		var low := preset == Preset.LOW
		vp.use_taa = not low
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low \
			else Viewport.SCREEN_SPACE_AA_DISABLED

	var shadow_q := RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	var atlas := 4096
	match preset:
		Preset.LOW:
			shadow_q = RenderingServer.SHADOW_QUALITY_HARD
			atlas = 2048
		Preset.MEDIUM:
			shadow_q = RenderingServer.SHADOW_QUALITY_SOFT_LOW
			atlas = 2048
		Preset.ULTRA:
			shadow_q = RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_q)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_q)
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)

	if _sky != null and is_instance_valid(_sky):
		_sky.apply_quality(int(preset))

	if _streamer != null and is_instance_valid(_streamer):
		_streamer.load_radius = VIEW_LOAD[view]
		_streamer.keep_radius = VIEW_KEEP[view]
		_streamer.prime_radius = mini(5, VIEW_LOAD[view] - 2)
