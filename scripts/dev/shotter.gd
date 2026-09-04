extends Node
class_name Shotter
## Development capture rig: waits for the world to finish meshing, takes a set
## of framed screenshots, prints timings, and quits. Driven by `-- --shot`.

var world: VoxelWorld
var player: Player
var sky: SkyEnv
var out_dir := "user://shots"
var views: Array = []          ## [{pos, yaw, pitch, hour, name}]

var _t_start := 0
var _t_ready := 0
var _i := 0
var _settle := 0
var _placed := false


func _ready() -> void:
	_t_start = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	set_process(true)


func _process(_delta: float) -> void:
	if world != null and world.busy():
		return
	if _t_ready == 0:
		_t_ready = Time.get_ticks_msec()
		print("[shot] world ready after %d ms" % (_t_ready - _t_start))
		_settle = 40
		return
	if _settle > 0:
		_settle -= 1
		return
	if _i >= views.size():
		print("[shot] done, %d frames" % views.size())
		get_tree().quit()
		return

	var v: Dictionary = views[_i]
	if not _placed:
		if player != null:
			player.set_input_enabled(false)
			player.teleport(v["pos"], v.get("yaw", 0.0))
			player.pitch = v.get("pitch", 0.0)
		if sky != null and v.has("hour"):
			sky.hour = v["hour"]
		_placed = true
		_settle = 14
		return

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _i, v.get("name", "view")]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[shot] %s  fps=%d  tris=%d" % [
		path, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_i += 1
	_placed = false
	_settle = 4
