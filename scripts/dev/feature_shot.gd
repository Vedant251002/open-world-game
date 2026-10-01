extends Node
class_name FeatureShot
## Pictures of photo mode and the weekly challenge, for review.
##
##   xvfb-run -a godot4 --path . --rendering-driver opengl3 -- --featureshot --featureshotdir=/abs/dir

var main: Node
var dir := "/tmp/featureshot"


func begin() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--featureshotdir="):
			dir = a.substr(17)
	DirAccess.make_dir_recursive_absolute(dir)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[featureshot] %s %dx%d" % [name, img.get_width(), img.get_height()])


func _run() -> void:
	Challenge.scores_path = "user://_featureshot_scores.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Challenge.scores_path))
	await _secs(9.0)
	var m: Node = main
	var photo: PhotoMode = m.photo
	var ch: Challenge = m.challenge
	var screen: ChallengeScreen = m.challenge_screen
	m.clock.hour = 16.5
	m.sky.hour = 16.5
	# A little history so the board and the caption have something to say.
	Challenge.add_score({"year": 2026, "week": 38, "success": true, "days": 6, "orders": 17,
		"score": Challenge.score(true, 6, 17), "progress": 5, "target": 5, "when": "2026-09-20"})
	Challenge.add_score({"year": 2026, "week": 39, "success": false, "days": 9, "orders": 12,
		"score": 0, "progress": 8, "target": 12, "when": "2026-09-27"})

	# ---- the card, in the HUD
	Challenge.mode = true
	var spec := {"year": 2026, "week": 40, "id": "build", "kind": "buildings", "target": 6,
		"deadline": 8, "max_orders": 18, "per_order": 3, "world_seed": 1}
	spec["text"] = Challenge.goal_text(spec)
	ch.begin(spec)
	for i in 7:
		m.dispatch.plan_accepted.emit(m.crew.workers[0], [])
	ch.progress = 3
	ch.changed.emit()
	await _frames(6)
	await _shot("challenge_card_hud")

	# ---- the page
	screen.open_screen()
	await _frames(6)
	await _shot("challenge_screen")
	screen.close_screen()
	Challenge.mode = true

	# ---- the result
	ch.progress = 6
	ch._finish(true, "")
	await _frames(6)
	await _shot("challenge_result")
	screen.close_screen()
	Challenge.mode = false

	# ---- photo mode
	m.clock.hour = 17.8
	photo.open()
	await _frames(4)
	photo._cam.global_position += Vector3(0, 9, 6)
	photo._pitch = -0.38
	photo._set_filter(3)
	photo._set_frame(2)
	photo._time_slider.value = 17.8
	await _frames(8)
	await _shot("photo_mode_ui")
	await photo.capture()
	_copy_last(photo, "photo_vintage_polaroid")
	photo._set_filter(4)
	photo._set_frame(3)
	await _frames(4)
	await photo.capture()
	_copy_last(photo, "photo_bw_postcard")
	photo._set_filter(1)
	photo._set_frame(1)
	await _frames(4)
	await photo.capture()
	_copy_last(photo, "photo_warm_classic")
	photo.close()
	print("[featureshot] done")
	get_tree().quit(0)


func _copy_last(photo: PhotoMode, name: String) -> void:
	if photo.last_path == "":
		return
	DirAccess.copy_absolute(photo.last_path, "%s/%s.png" % [dir, name])
	print("[featureshot] capture -> %s" % photo.last_path)
