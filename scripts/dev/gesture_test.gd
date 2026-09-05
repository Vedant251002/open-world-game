extends Node
class_name GestureTest
## One frame of each thing a worker does on a site, so they can be looked at.
##
## The build gestures are the only part of this game that cannot be checked by
## asserting on a number: "does that read as somebody reading the drawings" is
## a question about a silhouette, and the only way to answer it is to put the
## picture in front of somebody. So this stands the three of them in a row,
## holds one gesture, and saves a frame of it.
##
## Held rather than sampled: every pose has a cycle, and a screenshot taken at
## a random point in it is as likely to catch the bottom of a hammer swing as
## the top. Each gesture gets a fixed number of frames at a fixed rate, so the
## same picture comes out every run and a change to a pose is visible as a
## change to the image.

## Long enough for the settle lerps to finish and for every cycle to reach a
## point worth photographing: at these rates 44 frames puts the hammer near the
## top of its swing and the lift at the top of its lift.
const HOLD_FRAMES := 30
const SETTLE_FRAMES := 14

var world: VoxelWorld
var player: Player
var sky: SkyEnv
var crew: Crew
var village: Village
var out_dir := "user://shots"

var _ready_wait := 0.0
var _armed := false
var _i := 0
var _frame := 0
var _placed := false


func begin() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_ready_wait += delta
		if world.busy() and _ready_wait < 20.0:
			return
		_armed = true
		_line_up()
		print("[gesture] %d poses to capture" % Humanoid.GESTURES.size())
		return

	if _i >= Humanoid.GESTURES.size():
		print("[gesture] done, %d poses" % Humanoid.GESTURES.size())
		get_tree().quit()
		return

	# The workers' own _physics_process is off, so nothing drives the body but
	# this: a fixed delta, so the pose is at the same point of its cycle in
	# every run and the images are comparable between them.
	var gesture: String = Humanoid.GESTURES[_i]
	if _frame == 0:
		for w: Worker in crew.workers:
			w.body.reset_cycle()
	for w: Worker in crew.workers:
		w.body.work(1.0 / 60.0, gesture)

	if not _placed:
		_frame += 1
		if _frame >= SETTLE_FRAMES + HOLD_FRAMES:
			_placed = true
		return

	await RenderingServer.frame_post_draw
	var path := "%s/gesture_%d_%s.png" % [out_dir, _i, gesture]
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(path))
	print("[gesture] %s" % path)
	_i += 1
	_frame = 0
	_placed = false


## The same line-up the cast sheet uses, minus the livestock: three of them
## side on to nothing, lit at eleven in the morning, close enough that an arm
## is readable and far enough that the silhouette still is.
func _line_up() -> void:
	# Out on the open road rather than at the well: the well is a waist-high
	# ring of stone and it stands in front of whoever is on the right.
	var base := village.well_pos + Vector3(0.0, 0.0, 15.0)
	base.y = world.ground_m(base.x, base.z) + 0.1
	for i in crew.workers.size():
		var w: Worker = crew.workers[i]
		w.employer = null
		w.set_physics_process(false)
		w.set_process(false)
		w.global_position = base + Vector3((i - 1) * 1.7, 0.0, 0.0)
		# Three-quarters on, not square to the camera. Every one of these
		# gestures reaches forward, and face-on the camera looks straight down
		# the arm and sees nothing at all — which is not a flaw in the pose but
		# it is a useless way to check one.
		w.rotation.y = PI - 0.78

	if sky != null:
		sky.hour = 11.0
	if player != null:
		player.set_input_enabled(false)
		player.teleport(base + Vector3(0.0, 1.05, -4.0), PI)
		player.pitch = -0.05
