extends Node
class_name UiShot
## Dev capture for the interface (--uishot): stands the HUD in a busy state,
## then walks through every full-screen view saving a PNG of each. Output goes
## to --uishotdir=<abs path> (default user://uishots). Add --touchui to see the
## phone layout; pass a smaller window with Godot's own --resolution flag.

var hud: Hud
var map: MapScreen
var inventory: InventoryScreen
var pause: PauseMenu
var player: Player
var crew: Crew
var clock: GameClock
var out_dir := "user://uishots"


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uishotdir="):
			out_dir = a.substr(12)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await _frames(30)

	var well: Vector3 = player.global_position
	var main: Node = get_parent()
	if main != null and main.get("village") != null:
		well = (main.get("village") as Village).well_pos
	player.teleport(well + Vector3(3.0, 1.5, 11.0), 0.15, -0.09)
	clock.hour = 9.5
	var w: Worker = crew.workers[0]
	w.pending_question = ""
	hud._on_looked_at(w)
	hud.toast("Tobias: I need timber. Somebody should fetch some.", 600.0)
	hud.subtitle(w, "Morning! The bakery is up on the north side, past the well.", "talk")
	hud._subtitle_left = 600.0
	hud.show_assumptions(w, ["a small hut, three metres by four", "timber walls, thatch roof",
		"on the nearest free plot"])
	await _frames(20)
	await _save("01_hud_day")

	clock.hour = 21.5
	await _frames(6)
	await _save("02_hud_night")
	clock.hour = 9.5

	hud.chat.log_line(w, "you", "how many people live here?")
	hud.chat.log_line(w, "them", "Twelve, counting the children. Most of us are in the north houses.", "talk")
	hud.chat.log_line(w, "you", "build a wall around the town")
	hud.chat.log_line(w, "them", "That is a lot of stone. Do you want it low or high?", "question")
	hud.toggle_chat()
	await _frames(10)
	await _save("03_chat")
	hud.chat.hide_panel()

	hud.open_for(w)
	await _frames(12)
	await _save("04_bar")
	hud._close_bar()

	map.set_open(true)
	for _i in 300:
		await get_tree().process_frame
		if not map._pending and map._land.texture != null:
			break
	await _frames(8)
	await _save("05_map")
	map.set_open(false)

	inventory.set_open(true)
	await _frames(8)
	await _save("06_stores")
	inventory.set_open(false)

	pause.set_open(true)
	await _frames(8)
	await _save("07_pause")
	pause.set_open(false)

	print("[uishot] done -> %s" % ProjectSettings.globalize_path(out_dir))
	get_tree().quit()


## The title screen, captured over the streamed-in world (--titleshot).
func run_title() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uishotdir="):
			out_dir = a.substr(12)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await _frames(40)
	await _save("00_title")
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, name]))
	print("[uishot] %s" % name)
