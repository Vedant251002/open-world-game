extends Node
## A screenshot of the HUD with the kingdom's lines on it, for the eye.
## Run with:  godot --path . -- --realmtest=hudshot --shot=<path>

var world: VoxelWorld
var clock: GameClock
var realm: Realm
var hud: Node
var _t := 0.0
var _done := false


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t < 6.0 or _done:
		return
	_done = true
	var wx: Node = realm.system("Weather")
	if wx != null:
		wx.force("rain")
		clock.advance(1.0)
	var ev: Node = realm.system("Events")
	if ev != null:
		ev.trigger("merchant")
	await get_tree().process_frame
	await get_tree().process_frame
	var path := "user://hudshot.png"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			path = a.substr(7)
	get_viewport().get_texture().get_image().save_png(path)
	print("[hudshot] saved %s; lines %s" % [path, str(realm.hud_lines())])
	get_tree().quit()
