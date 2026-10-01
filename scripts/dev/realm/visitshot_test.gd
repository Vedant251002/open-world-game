extends Node
## Pictures of a visited village.  Start in a village with --visitfile=code.txt
## (see diplomacy_test --writecode=):
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --visitfile=/abs/code.txt --realmtest=visitshot --visitshotdir=/abs/dir

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var village: Village
var player: Player
var hud: Hud
var dispatch: Dispatcher

var dir := "/tmp/visitshot"


func begin() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--visitshotdir="):
			dir = a.substr(15)
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[visitshot] %s %dx%d" % [name, img.get_width(), img.get_height()])


func _run() -> void:
	await get_tree().create_timer(8.0, true).timeout
	var main: Node = get_parent()
	clock.hour = 10.5
	player.teleport(village.well_pos + Vector3(3.0, 1.5, 12.0), 0.15, -0.09)
	await _frames(30)
	await _shot("visit_overview")
	# Somebody close enough to read, and a question put to them.
	var w: Worker = crew.workers[0]
	w.global_position = player.global_position + Vector3(0.6, -0.9, -3.2)
	w.stop_wandering()
	hud._on_looked_at(w)
	hud.chat.log_line(w, "you", "tell me about your village")
	VillageVisit.talk(main, w, "tell me about your village")
	await _frames(20)
	await _shot("visit_talking")
	var w2: Worker = crew.workers[1]
	w2.global_position = player.global_position + Vector3(-1.4, -0.9, -4.0)
	VillageVisit.talk(main, w2, "please build me a bakery")
	await _frames(20)
	await _shot("visit_no_orders")
	get_tree().quit(0)
