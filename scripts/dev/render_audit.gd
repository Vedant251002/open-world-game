extends Node
class_name RenderAudit
## A framed sweep of the world designed to expose rendering faults rather than
## to look nice: face winding, chunk seams, AO banding, z-fighting between the
## world grid and Tier B props, transparency sorting, and the day cycle.
##
## Run with:  godot --path . -- --buildtest --audit

var world: VoxelWorld
var village: Village
var player: Player
var sky: SkyEnv
var out_dir := "user://audit"

var views: Array[Dictionary] = []
var _i := 0
var _settle := 0
var _placed := false
var _ready_at := 0
var _report: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	set_process(true)


## Builds the view list once the world exists. `focus` is a finished building.
func compose(focus_patch: VoxelPatch, well: Vector3) -> void:
	views.clear()
	if focus_patch != null:
		var fr := focus_patch.footprint
		var c := Vector3((fr.position.x + fr.size.x * 0.5) * 0.25, 0.0,
			(fr.position.y + fr.size.y * 0.5) * 0.25)
		var span := maxf(fr.size.x, fr.size.y) * 0.25

		# Four compass elevations. Any face-winding fault shows up as a wall
		# that is invisible from exactly one side.
		var dirs := {
			"north": Vector3(0, 0, -1), "south": Vector3(0, 0, 1),
			"east": Vector3(1, 0, 0), "west": Vector3(-1, 0, 0),
		}
		for name: String in dirs:
			var d: Vector3 = dirs[name]
			_add("elev_" + name, c + d * (span * 0.5 + 12.0), atan2(d.x, d.z), 0.06, 10.5)

		# Two metres from a wall: window trim, mullions, plank grain, and any
		# z-fighting on the wall face.
		_add("detail_wall", c + Vector3(0, 0, -1) * (span * 0.5 + 2.2), PI, 0.10, 11.0)
		# Looking up at the eaves, where the roof meets the wall.
		_add("detail_eaves", c + Vector3(0, 0, -1) * (span * 0.5 + 3.0), PI, 0.55, 11.0)
		# Above the ridge: roof stepping and thatch pattern.
		_add("detail_roof", c + Vector3(0, 9.0, -1.0), PI, -0.8, 12.0)

	# The plaza and the well: masonry pattern, a curved structure, contact AO.
	_add("well_close", well + Vector3(0, 0, 7.0), 0.0, 0.05, 10.0)
	_add("well_high", well + Vector3(0, 12.0, 16.0), 0.0, -0.5, 12.0)

	# Straight down at the street: ground pattern scale and kerb transition.
	_add("ground_down", well + Vector3(9.0, 1.4, 9.0), 0.0, -1.35, 12.0)

	# Long view down a street: chunk seams show as lines across the road.
	_add("street_long", well + Vector3(0, 0, 30.0), 0.0, 0.0, 12.0)

	# Out past the last street: the join between streamed voxels and the distant
	# terrain mesh, which is the seam most likely to look wrong.
	_add("outskirts", well + Vector3(0, 0, 70.0), 0.0, 0.02, 12.0)
	_add("horizon", well + Vector3(0, 24.0, 40.0), PI, -0.12, 12.0)

	# Under a tree: foliage AO and alpha behaviour.
	var tree := _find_tree(well)
	if tree != Vector3.ZERO:
		_add("tree", tree + Vector3(0, 0, 7.0), 0.0, 0.35, 12.0)

	# Aerial: overall composition, LOD popping, shadow cascades.
	_add("aerial", well + Vector3(0, 40.0, 62.0), 0.0, -0.5, 13.0)

	# The day cycle at four points. Night is where emissive and moonlight fail.
	_add("time_dawn", well + Vector3(0, 0, 9.0), 0.0, 0.06, 6.4)
	_add("time_noon", well + Vector3(0, 0, 9.0), 0.0, 0.06, 12.0)
	_add("time_dusk", well + Vector3(0, 0, 9.0), 0.0, 0.06, 19.2)
	_add("time_night", well + Vector3(0, 0, 9.0), 0.0, 0.06, 23.0)


func _add(name: String, pos: Vector3, yaw: float, pitch: float, hour: float) -> void:
	var p := pos
	p.y = world.ground_m(p.x, p.z) + 0.15 if pos.y < 2.0 else pos.y
	views.append({"pos": p, "yaw": yaw, "pitch": pitch, "hour": hour, "name": name})


## The world has no edges to stay inside any more; the only limit is how far
## the streamer has loaded, and height_at reports -1 outside that.
func _find_tree(from: Vector3) -> Vector3:
	for r in range(20, 140, 6):
		for a in 16:
			var ang := a * TAU / 16.0
			var x := int((from.x + cos(ang) * r) / 0.25)
			var z := int((from.z + sin(ang) * r) / 0.25)
			var h := world.height_at(x, z)
			if h > 0 and world.get_voxel(Vector3i(x, h, z)) == VoxelTypes.LEAF:
				return Vector3(x * 0.25, 0.0, z * 0.25)
	return Vector3.ZERO


func _process(_delta: float) -> void:
	if world != null and world.busy():
		return
	if _ready_at == 0:
		_ready_at = Time.get_ticks_msec()
		_diagnostics()
		_settle = 45
		return
	if _settle > 0:
		_settle -= 1
		return
	if _i >= views.size():
		_write_report()
		get_tree().quit()
		return

	var v: Dictionary = views[_i]
	if not _placed:
		player.set_input_enabled(false)
		player.teleport(v["pos"], v.get("yaw", 0.0))
		player.pitch = v.get("pitch", 0.0)
		sky.hour = v["hour"]
		_placed = true
		_settle = 16
		return

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _i, v["name"]]
	img.save_png(ProjectSettings.globalize_path(path))
	_report.append("%-16s fps %3d  tris %7d  %s" % [
		v["name"], Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		_exposure_note(img)])
	_i += 1
	_placed = false
	_settle = 5


## Cheap objective checks on the frame: a frame that is mostly pure black or
## pure white is a rendering fault, not an artistic choice.
func _exposure_note(img: Image) -> String:
	var w := img.get_width()
	var h := img.get_height()
	var black := 0
	var white := 0
	var total := 0
	var lum_sum := 0.0
	for y in range(0, h, 12):
		for x in range(0, w, 12):
			var c := img.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			lum_sum += l
			total += 1
			if l < 0.02:
				black += 1
			elif l > 0.985:
				white += 1
	var note := "mean %.2f" % (lum_sum / maxf(total, 1))
	if float(black) / total > 0.35:
		note += "  CRUSHED-BLACK %d%%" % int(float(black) / total * 100.0)
	if float(white) / total > 0.25:
		note += "  BLOWN-WHITE %d%%" % int(float(white) / total * 100.0)
	return note


func _diagnostics() -> void:
	var surfaces := 0
	var nodes := 0
	for child in world.get_children():
		if child is MeshInstance3D:
			nodes += 1
			var m: Mesh = (child as MeshInstance3D).mesh
			if m == null:
				continue
			surfaces += m.get_surface_count()
	_report.append("--- world ---")
	_report.append("chunks %d, mesh nodes %d, surfaces %d, quads %d" % [
		world.chunk_count(), nodes, surfaces, world.stat_quads])
	var holes := world.unrendered_chunks()
	if holes.is_empty():
		_report.append("no unrendered chunks: every meshable chunk has geometry")
	else:
		_report.append("UNRENDERED CHUNKS: %d (first %v)" % [holes.size(), holes[0]])
	_report.append("--- frames ---")


func _write_report() -> void:
	var text := "\n".join(_report)
	print("\n" + text + "\n")
	var f := FileAccess.open(out_dir + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
