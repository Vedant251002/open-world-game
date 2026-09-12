extends Node
class_name ZooShot
## Every creature in the kit, stood in rows in the plaza, photographed.
##
## The only way to know whether a box reads as a goat is to look at it. This
## builds one of everything at real size, birds perched and fish held up in
## the air where they can be seen, and takes a few frames from eye level.
## Driven by `-- --zoo`.

var player: Player
var world: VoxelWorld
var village: Village
var sky: SkyEnv
var clock: GameClock
var livestock: Livestock
var wildlife: Wildlife
var crew: Crew

var _t := 0.0
var _shot := 0
var _built := false
var _views: Array[Dictionary] = []

## Rows, front to back, left to right. Real animals in real sizes, so the
## spacing is by the biggest thing in the row.
const ROWS := [
	["hen", "rooster", "sheep", "goat", "pig", "cow", "horse"],
	["cat", "dog", "rabbit", "fox", "deer"],
	["sparrow", "crow", "gull", "duck", "owl"],
	["perch", "trout", "carp"],
]


func _process(delta: float) -> void:
	_t += delta
	if world != null and world.busy() and _t < 15.0:
		return
	if not _built:
		_build()
		_built = true
		_t = 0.0
		return
	if _t < 0.8:
		return
	if _shot >= _views.size():
		get_tree().quit()
		return
	var v := _views[_shot]
	if _t < 1.2:
		player.set_input_enabled(false)
		player.teleport(v["pos"], v["yaw"])
		player.pitch = v["pitch"]
		if sky != null:
			sky.hour = 11.0
		return
	_capture(str(v["name"]))
	_shot += 1
	_t = 0.8


func _build() -> void:
	# The crew and the flock out of the frame.
	if livestock != null:
		for a: Animal in livestock.animals:
			if is_instance_valid(a):
				a.visible = false
				a.set_physics_process(false)
	if wildlife != null:
		wildlife.set_process(false)
	if crew != null:
		for w: Worker in crew.workers:
			w.employer = null
			w.visible = false
			w.set_physics_process(false)

	# Each row is centred on the same x and photographed from straight in
	# front, close enough to fill the frame with the row and no closer.
	var centre := village.well_pos + Vector3(-2.0, 0.0, 16.0)
	var z := centre.z
	for row_i in ROWS.size():
		var row: Array = ROWS[row_i]
		# Space by each animal's real width, plus elbow room.
		var widths: Array[float] = []
		var total := 0.0
		for kind: String in row:
			var wdt := _width(kind) + 0.7
			widths.append(wdt)
			total += wdt
		var x := centre.x - total * 0.5
		var tallest := 0.0
		for k in row.size():
			var kind: String = row[k]
			x += widths[k] * 0.5
			var at := Vector3(x, world.ground_m(x, z) + 0.05, z)
			var spec := CreatureKit.spec(kind)
			match str(spec["plan"]):
				"fish":
					var f := Fish.new()
					add_child(f)
					f.setup(kind, world, at + Vector3(0, 0.6, 0))
					f.set_process(false)
					f.rotation.y = PI * 0.5
					tallest = maxf(tallest, 0.9)
				"bird":
					if str(spec["move"]) == "walk":
						_stand(kind, at)
					else:
						var b := Bird.new()
						add_child(b)
						b.setup(kind, world, at)
						b.set_process(false)
						b.rotation.y = 0.3
					tallest = maxf(tallest, _height(kind))
				_:
					_stand(kind, at)
					tallest = maxf(tallest, _height(kind))
			x += widths[k] * 0.5
		# Camera: far enough back that the row fits a 75 degree lens.
		var dist := maxf(total * 0.62, 1.6) + 0.8
		var eye := Vector3(centre.x, 0.0, z + dist)
		eye.y = world.ground_m(eye.x, eye.z) + maxf(tallest * 0.75, 0.55)
		_views.append({"name": "zoo_row%d" % row_i, "pos": eye, "yaw": 0.0,
			"pitch": -atan2(eye.y - world.ground_m(eye.x, z) - tallest * 0.45, dist)})
		z -= 4.0

	var wide := Vector3(centre.x, 0.0, centre.z + 9.0)
	wide.y = world.ground_m(wide.x, wide.z) + 3.2
	_views.push_front({"name": "zoo_wide", "pos": wide, "yaw": 0.0, "pitch": -0.32})


func _width(kind: String) -> float:
	var s := CreatureKit.spec(kind)
	match str(s["plan"]):
		"quadruped": return float(s["W"])
		"bird": return maxf((s["body"] as Vector3).x, 0.2)
		"fish": return float(s["length"]) * 0.5
	return 0.5


func _height(kind: String) -> float:
	var s := CreatureKit.spec(kind)
	match str(s["plan"]):
		"quadruped": return float(s["H"]) * 1.3
		"bird": return float(s["stand"]) + (s["body"] as Vector3).y * 1.6
	return 0.8


func _stand(kind: String, at: Vector3) -> void:
	var a := Animal.new()
	add_child(a)
	a.setup(kind, world, clock, at)
	a.rotation.y = 0.35
	a.set_physics_process(false)


func _capture(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, view_name]))
	print("[zoo] %s/%s.png" % [dir, view_name])
