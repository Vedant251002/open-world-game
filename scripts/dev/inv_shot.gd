extends Node
class_name InvShot
## Opens the inventory, points at a slot, and saves a frame of it.
##
## The screen is a single _draw call over the live stores, so the only way to
## know it is right is to look at one — a headless run can tell you it parses
## and nothing more. Driven by `-- --invshot`.

var player: Player
var inventory: InventoryScreen
var town: Town

var _t := 0.0
var _shot := 0


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.6:
		return
	if _shot == 0:
		# Something in every category, so no row is drawn from an empty
		# dictionary and the counts are not all the starting numbers.
		town.stock["granite"] = 260
		town.stock["food"] = 48
		town.stock["cloth"] = 12
		town.stock["steel_frame"] = 0
		inventory.set_open(true)
		_shot = 1
		_t = 0.0
		return
	if _t < 0.5:
		return
	match _shot:
		1:
			_capture("inventory")
		2:
			# The detail column, with a slot under the pointer.
			inventory._picked = 3
			inventory._hover = 3
			_capture("inventory_picked")
		3:
			# And one nobody can work yet, which is the other thing the column
			# has to be able to say.
			inventory._picked = 12
			inventory._hover = 12
			_capture("inventory_locked")
		_:
			get_tree().quit()
	_t = 0.0


func _capture(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, view_name]))
	print("[inv] %s/%s.png" % [dir, view_name])
	_shot += 1
