extends Node
class_name AttendShot
## Two frames of a hired hand at work: one with the player out of range, one
## stood beside them. The first should show the activity line and progress bar
## over their name with their eyes on the job; the second, the head turned
## round to the camera.
##
##   godot --path . -- --attendshot --fresh --nosound --nosave

var world: VoxelWorld
var player: Player
var crew: Crew
var village: Village
var sky: SkyEnv
var out_dir := "user://shots"

var _wait := 0.0
var _step := 0
var _t := 0.0


func begin() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	player.set_input_enabled(false)
	set_process(true)


func _process(delta: float) -> void:
	if _step == 0:
		_wait += delta
		if world.busy() and _wait < 20.0:
			return
		if sky != null:
			sky.hour = 11.0
		var w: Worker = crew.workers[0]
		w.employer = null
		var at := village.well_pos + Vector3(0.0, 0.0, 15.0)
		at.y = world.ground_m(at.x, at.z) + 0.2
		w.global_position = at
		w.take_errand_job("station", at, 8.0, "", {"where": "the road", "doing": "hammer"})
		_look(at + Vector3(0.0, 1.6, -9.0), at + Vector3(0.0, 1.2, 0.0))
		_step = 1
		_t = 0.0
		return
	_t += delta
	if _t < 3.0:
		return
	_t = 0.0
	var w: Worker = crew.workers[0]
	match _step:
		1:
			await _snap("attend_far")
			var at := w.global_position
			# Off to one side, so a head turned to the camera is visible as one.
			_look(at + Vector3(2.4, 1.6, -2.2), at + Vector3(0.0, 1.3, 0.0))
			_step = 2
		2:
			print("[attend] attending=%s status=%s" % [w.attending, w.status_text()])
			await _snap("attend_near")
			get_tree().quit()
			_step = 3


func _look(from: Vector3, at: Vector3) -> void:
	var d := at - from
	player.teleport(from, atan2(-d.x, -d.z))
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, shot_name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[attend] %s" % path)
