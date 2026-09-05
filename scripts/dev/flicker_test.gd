extends Node
class_name FlickerTest
## Finds flicker by looking for it, rather than by squinting.
##
## Parks the camera somewhere, lets the scene settle, then captures a run of
## consecutive frames of a world in which nothing is moving. Anything that is
## not still between one frame and the next is flicker by definition, and where
## it is on screen usually says what it is: a broad shimmering rectangle on the
## floor is two coplanar surfaces fighting, a halo round a lamp is the lighting,
## an even wash over everything is the temporal antialiasing jittering.
##
## Writes a heat image beside the plain capture so the shape of it is visible.

const FRAMES := 10
const WARMUP := 20        ## frames thrown away before measuring
const NOISE := 6          ## per-channel 0-255 difference worth calling a change

var world: VoxelWorld
var player: Player
var sky: SkyEnv
var views: Array = []             ## [{pos, yaw, pitch, hour, name}]
var out_dir := "user://shots"

var _i := 0
var _settle := 0
var _placed := false
var _armed := false
var _wait := 0.0
## _measure() awaits, so _process keeps firing while it runs and would start a
## second measurement of the same view on top of the first.
var _busy := false
## The clock in the corner ticks, which is a change but not a flicker.
var hud: CanvasLayer


func begin() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	set_process(true)


func _process(delta: float) -> void:
	if _busy:
		return
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 20.0:
			return
		_armed = true
		_settle = 60
		if player != null:
			player.set_input_enabled(false)
		if hud != null:
			hud.visible = false
		return
	if _settle > 0:
		_settle -= 1
		return
	if _i >= views.size():
		print("[flicker] done, %d views" % views.size())
		get_tree().quit()
		return

	var v: Dictionary = views[_i]
	if not _placed:
		player.teleport(v["pos"], float(v.get("yaw", 0.0)))
		player.pitch = float(v.get("pitch", 0.0))
		if sky != null and v.has("hour"):
			sky.hour = float(v["hour"])
		_placed = true
		# Temporal antialiasing needs a good second to converge after the camera
		# jumps. Measured too early it reports the convergence as flicker, which
		# is how three rooms came back at seventy per cent while sitting still.
		_settle = 90
		return

	_busy = true
	await _measure(str(v.get("name", "view")))
	_i += 1
	_placed = false
	_settle = 20
	_busy = false


func _measure(view_name: String) -> void:
	var shots: Array[Image] = []
	for _f in WARMUP:
		await RenderingServer.frame_post_draw
	for _f in FRAMES:
		await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())

	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var heat := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var changed := 0
	var worst := 0
	var worst_at := Vector2i.ZERO
	# Sampled every second pixel: a quarter of the work, and flicker large
	# enough to see is never one pixel wide.
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var lo := 999
			var hi := -1
			for img: Image in shots:
				var c := img.get_pixel(x, y)
				var lum := int((c.r * 0.3 + c.g * 0.6 + c.b * 0.1) * 255.0)
				lo = mini(lo, lum)
				hi = maxi(hi, lum)
			var span := hi - lo
			if span > worst:
				worst = span
				worst_at = Vector2i(x, y)
			if span > NOISE:
				changed += 1
			var t := clampf(float(span) / 40.0, 0.0, 1.0)
			heat.set_pixel(x, y, Color(t, t * 0.35, 0.10 if t > 0.05 else 0.0))

	var sampled := int(ceil(float(w) / 2.0)) * int(ceil(float(h) / 2.0))
	var pct := 100.0 * float(changed) / maxf(float(sampled), 1.0)
	print("[flicker] %-22s %5.2f%% of pixels move, worst swing %d/255 at %s" % [
		view_name, pct, worst, str(worst_at)])
	heat.save_png(ProjectSettings.globalize_path(
		"%s/flicker_%s.png" % [out_dir, view_name]))
	shots[0].save_png(ProjectSettings.globalize_path(
		"%s/plain_%s.png" % [out_dir, view_name]))
