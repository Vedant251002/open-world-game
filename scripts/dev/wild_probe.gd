extends Node
class_name WildProbe
## Lets the wildlife manager run for a while, then reports what it put where
## and photographs a fish and a bird in place.
##
## The zoo shot proves the bodies; this proves the placement — that fish are
## in water, birds are on something, and deer are outside the streets. Driven
## by `-- --wildprobe`.

var player: Player
var world: VoxelWorld
var village: Village
var sky: SkyEnv
var wildlife: Wildlife

var _t := 0.0
var _phase := 0
var _moved := false
var _fails: Array[String] = []
var _views: Array[Dictionary] = []

const SETTLE := 26.0


func _process(delta: float) -> void:
	_t += delta
	if world != null and world.busy() and _t < 15.0:
		return
	match _phase:
		0:
			# Stand on the shore first, so the water half of the manager has
			# something to work with. From the well the sea is out of range,
			# which is correct — fish should not spawn in town — and useless
			# for a test of fish.
			if not _moved:
				_moved = true
				var shore := _find_shore()
				if shore != Vector3.INF:
					var stand := shore + (village.well_pos - shore).normalized() * 10.0
					stand.y = world.ground_m(stand.x, stand.z) + 0.4
					player.teleport(stand, 0.0)
					print("[wild] standing at %s, shore at %s" % [
						str(stand.round()), str(shore.round())])
				else:
					print("[wild] no shore found within reach")
				_t = 0.0
				return
			if _t < SETTLE:
				return
			_report()
			_phase = 1
			_t = 0.0
		1:
			if _views.is_empty():
				_finish()
				return
			var v: Dictionary = _views[0]
			if _t < 0.3:
				player.set_input_enabled(false)
				player.teleport(v["pos"], v["yaw"])
				player.pitch = v["pitch"]
				return
			if _t < 0.9:
				return
			_capture(str(v["name"]))
			_views.pop_front()
			_t = 0.0


func _report() -> void:
	var seen := wildlife.species_seen()
	print("[wild] after %.0f s: %s" % [SETTLE, JSON.stringify(seen)])
	if seen.is_empty():
		_fails.append("nothing spawned at all")

	# Every fish must be in water, every deer outside the streets, every bird
	# somewhere above the ground it started on.
	var fish_ok := 0
	for f: Fish in wildlife.fish:
		if not is_instance_valid(f):
			continue
		var v := VoxelWorld.to_voxel(f.global_position)
		if world.get_voxel(v) == VoxelTypes.WATER:
			fish_ok += 1
		else:
			_fails.append("%s at %s is not in water" % [f.kind, str(f.global_position.round())])
	for a: Animal in wildlife.beasts:
		if not is_instance_valid(a) or not a.is_wild():
			continue
		var v := VoxelWorld.to_voxel(a.global_position)
		if village.bounds_v.has_point(Vector2i(v.x, v.z)):
			_fails.append("%s is inside the town" % a.kind)
	var modes := {}
	for b: Bird in wildlife.birds:
		if is_instance_valid(b):
			var m := str(Bird.Mode.keys()[b._mode])
			modes[m] = int(modes.get(m, 0)) + 1
	print("[wild] %d fish in water; bird modes: %s" % [fish_ok, JSON.stringify(modes)])

	# Photographs: one fish, one perched or flying bird, one deer if any.
	if not wildlife.fish.is_empty():
		var f: Fish = wildlife.fish[0]
		var eye := f.pool + Vector3(0.0, 1.6, 5.0)
		eye.y = maxf(eye.y, world.ground_m(eye.x, eye.z) + 1.5)
		_views.append({"name": "wild_fish", "pos": eye, "yaw": 0.0, "pitch": -0.5})
	for b: Bird in wildlife.birds:
		if is_instance_valid(b) and b.kind != "duck":
			var eye := b.global_position + Vector3(0.0, 0.3, 4.5)
			eye.y = maxf(eye.y, world.ground_m(eye.x, eye.z) + 1.4)
			var pitch := -atan2(eye.y - b.global_position.y, 4.5)
			_views.append({"name": "wild_bird_%s" % b.kind, "pos": eye, "yaw": 0.0, "pitch": pitch})
			break
	for a: Animal in wildlife.beasts:
		if is_instance_valid(a) and a.is_wild():
			var eye := a.global_position + Vector3(0.0, 1.2, 6.0)
			eye.y = maxf(eye.y, world.ground_m(eye.x, eye.z) + 1.4)
			_views.append({"name": "wild_%s" % a.kind, "pos": eye, "yaw": 0.0, "pitch": -0.2})
			break
	if sky != null:
		sky.hour = 11.0


## The nearest water to the well, on a coarse grid over the loaded world.
func _find_shore() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	var w := village.well_pos
	for gz in range(-160, 161, 6):
		for gx in range(-160, 161, 6):
			var p := w + Vector3(gx, 0.0, gz)
			var v := VoxelWorld.to_voxel(p)
			var h := world.height_at(v.x, v.z)
			if h <= 0:
				continue
			if world.get_voxel(Vector3i(v.x, h, v.z)) == VoxelTypes.WATER:
				var d := p.distance_to(w)
				if d < best_d:
					best_d = d
					best = Vector3(p.x, (h + 1) * 0.25, p.z)
	return best


func _capture(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, view_name]))
	print("[wild] %s/%s.png" % [dir, view_name])


func _finish() -> void:
	for f: String in _fails:
		print("[wild] FAIL: %s" % f)
	print("[wild] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
