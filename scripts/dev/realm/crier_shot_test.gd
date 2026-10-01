extends Node
## Screenshots of the Village Crier page and the requests widget.
## Run with:  godot --path . --rendering-driver opengl3 -- --realmtest=crier_shot --nosave --shotdir=/abs/dir

var world: VoxelWorld
var town: Town
var clock: GameClock
var crew: Crew
var realm: Realm
var hud: Hud
var _t := 0.0
var _done := false
var dir := "/tmp/crier_shot"


func begin() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	set_process(true)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[crier_shot] %s %dx%d" % [name, img.get_width(), img.get_height()])


func _process(delta: float) -> void:
	_t += delta
	if _t < 7.0 or _done:
		return
	_done = true
	var main := get_parent()
	var crier: Crier = main.get("crier")
	var req: Requests = main.get("requests")
	var screen: CrierScreen = main.get("crier_screen")
	clock.advance(24.0 * 4.0)
	realm.note("wedding", "Ada and Bram were married under the old oak, with half the town in attendance.")
	town.building_added.emit({"id": 555, "archetype": "bakery", "street": "Mill Lane", "builder": "tobias"})
	crier._on_harvest("wheat", 14)
	clock.advance(24.0)
	req.active.clear()
	req.generate(clock.day + 11)
	req.generate(clock.day + 11)
	req.active.append({"id": 77, "who": "ren", "name": "Ren", "kind": "build", "arch": "barn",
		"item": "", "n": 0, "baseline": 0, "issued": clock.day, "due": clock.day + 4, "reward": 300,
		"text": "a barn before day %d" % (clock.day + 5), "say": "A barn, please.", "thanks": "Thanks."})
	req.changed.emit()
	for i in 4:
		await get_tree().process_frame
	await _shot("requests_hud")
	screen.open_screen()
	for i in 6:
		await get_tree().process_frame
	await _shot("crier_page")
	screen.browse(-2)
	for i in 4:
		await get_tree().process_frame
	await _shot("crier_back_issue")
	get_tree().quit()
