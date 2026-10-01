extends Node3D
class_name SiteFx
## Everything you see of a building going up that is not the building: the
## string-and-stake outline on the ground, the scaffold that climbs with the
## walls, a dust puff where each course lands, a flag whose banner fills as the
## work does (with a percentage you can read from across the green), piles of
## fetched material, and a small celebration when it is done.
##
## Owned by Construction, which is a RefCounted and so cannot be in the tree.
## Pure presentation: nothing here is saved or read back by the simulation, and
## a building put up by complete_now() (a save load, a test) never makes one.

const VOXEL_M := 0.25
const NO_SCAFFOLD := ["road", "levelled ground", "tree", "grove", "demolition", "fence", "pen"]

var _dust: FxPool
var _scaffold: Scaffolding = null
var _marker: Node3D
var _flag: Node3D
var _banner: MeshInstance3D
var _banner_mat: StandardMaterial3D
var _label: Label3D
var _name_label: Label3D = null
var _piles: Array[Node3D] = []
var _rect := Rect2()
var _ground := 0.0
var _height := 0.0
var _progress := 0.0
var _dying := -1.0              ## seconds left once finished
var _tint := Color("#cdbd9a")
var _flag_h := 5.0


func setup(patch: VoxelPatch, world: VoxelWorld) -> void:
	_rect = Rect2(Vector2(patch.footprint.position) * VOXEL_M, Vector2(patch.footprint.size) * VOXEL_M)
	var c := _rect.get_center()
	_ground = world.ground_m(c.x, c.y)
	_height = maxf(0.0, float(patch.origin.y + patch.size.y) * VOXEL_M - _ground)
	_dust = FxPool.new().setup(220)
	add_child(_dust)

	# The dust takes the colour of what is going up.
	var best := -1
	var most := -1
	for mat_name: String in patch.cost:
		if int(patch.cost[mat_name]) > most:
			most = int(patch.cost[mat_name])
			best = VoxelTypes.id_of(mat_name)
	if best >= 0:
		var pc: Color = VoxelTypes.PROPS[best][0]
		_tint = Color(pc.r, pc.g, pc.b).lerp(Color("#d8cdb4"), 0.55)

	_build_marker()
	var big_enough := _rect.size.x >= 3.0 and _rect.size.y >= 3.0 and _height >= 2.2
	if big_enough and not NO_SCAFFOLD.has(patch.archetype):
		_scaffold = Scaffolding.new()
		add_child(_scaffold)
		_scaffold.build(_rect, _ground, _height)
	_flag_h = clampf(_height + 2.2, 4.5, 14.0)
	if _scaffold != null:
		_scaffold.set_height(0.0)
	_build_flag()
	# The stake-out puffs in when it is set.
	_puff_ring(_rect, 0.12, 14, 0.9)


func ground_y() -> float:
	return _ground


func _build_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var b := BoxKit.Batch.new()
	var r := _rect.grow(0.35)
	var y := _ground + 0.03
	var rope := Color("#e8dcc0")
	var t := 0.05
	b.box(_marker, Vector3(r.position.x, y + 0.28, r.position.y), Vector3(r.size.x, t, t), rope, 0.9)
	b.box(_marker, Vector3(r.position.x, y + 0.28, r.end.y), Vector3(r.size.x, t, t), rope, 0.9)
	b.box(_marker, Vector3(r.position.x, y + 0.28, r.position.y), Vector3(t, t, r.size.y), rope, 0.9)
	b.box(_marker, Vector3(r.end.x, y + 0.28, r.position.y), Vector3(t, t, r.size.y), rope, 0.9)
	# A pale line on the ground itself, so the outline reads from above.
	var line := Color("#e9e3c8")
	b.box(_marker, Vector3(r.position.x, y, r.position.y), Vector3(r.size.x, 0.02, 0.09), line, 0.95)
	b.box(_marker, Vector3(r.position.x, y, r.end.y - 0.09), Vector3(r.size.x, 0.02, 0.09), line, 0.95)
	b.box(_marker, Vector3(r.position.x, y, r.position.y), Vector3(0.09, 0.02, r.size.y), line, 0.95)
	b.box(_marker, Vector3(r.end.x - 0.09, y, r.position.y), Vector3(0.09, 0.02, r.size.y), line, 0.95)
	# Corner stakes, tipped red.
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		b.box(_marker, Vector3(p.x - 0.04, y, p.y - 0.04), Vector3(0.08, 0.42, 0.08), Color("#7d5a3c"), 0.95)
		b.box(_marker, Vector3(p.x - 0.045, y + 0.34, p.y - 0.045), Vector3(0.09, 0.09, 0.09), Color("#c2452f"), 0.9)
	b.flush()


func _build_flag() -> void:
	_flag = Node3D.new()
	# Outside the scaffold at the near corner, so it is never inside the walls.
	var r := _rect.grow(1.6)
	_flag.position = Vector3(r.position.x, _ground, r.position.y)
	add_child(_flag)
	var b := BoxKit.Batch.new()
	b.box(_flag, Vector3(-0.07, 0, -0.07), Vector3(0.14, _flag_h, 0.14), Color("#a9733f"), 0.95)
	b.box(_flag, Vector3(-0.08, _flag_h, -0.08), Vector3(0.16, 0.16, 0.16), Color("#d9b052"), 0.5)
	b.flush()
	# The banner is a plain box scaled along its length: it fills as the walls
	# rise. Unshaded so it is never lost in shadow.
	_banner_mat = StandardMaterial3D.new()
	_banner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_banner_mat.albedo_color = Color("#e8a93a")
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.42, 0.04)
	_banner = MeshInstance3D.new()
	_banner.mesh = bm
	_banner.material_override = _banner_mat
	_banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flag.add_child(_banner)
	_label = _make_label("0%", 44)
	_label.position = Vector3(0.0, _flag_h + 0.75, 0.0)
	_flag.add_child(_label)
	_set_banner(0.0)


func _make_label(text: String, font: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.0075
	l.outline_size = 12
	l.modulate = Color("#fff3d2")
	l.outline_modulate = Color("#2a1c10")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.shaded = false
	l.double_sided = true
	return l


func _set_banner(p: float) -> void:
	var w := 1.9
	var s := maxf(p, 0.03)
	_banner.scale = Vector3(s * w, 1.0, 1.0)
	_banner.position = Vector3(s * w * 0.5 + 0.05, _flag_h - 0.3, 0.0)
	_banner_mat.albedo_color = Color("#e8a93a").lerp(Color("#7fc15a"), clampf((p - 0.6) / 0.4, 0.0, 1.0))
	_label.text = "%d%%" % int(round(p * 100.0))


## Called by Construction after every batch of voxels: the fraction done, and
## the height of the course just laid (metres above ground).
func progress(p: float, laid_top_m: float) -> void:
	if _dying >= 0.0:
		return
	_progress = p
	_set_banner(p)
	if _scaffold != null:
		_scaffold.set_height(laid_top_m)


## One course landing: a few dust puffs, at most a handful per call however
## many voxels went down, so a time-lapse costs the same as a stroll.
func pop(voxel: Vector3i, mat: int) -> void:
	if _dust == null or _dying >= 0.0:
		return
	var at := Vector3(voxel.x + 0.5, voxel.y + 0.5, voxel.z + 0.5) * VOXEL_M
	var base := _tint
	if mat >= 0 and mat < 255 and VoxelTypes.PROPS.has(mat):
		var pc: Color = VoxelTypes.PROPS[mat][0]
		base = Color(pc.r, pc.g, pc.b).lerp(Color("#d8cdb4"), 0.45)
	for k in 2:
		var v := Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 1.2), randf_range(-0.5, 0.5))
		var p := _dust.emit(at, v, Color(base, 0.75), randf_range(0.07, 0.13), randf_range(0.5, 0.9), 1.2, 1.5)
		if p != null:
			p.grow = 0.18


func _puff_ring(r: Rect2, y_off: float, n: int, scale_f: float) -> void:
	var per := 2.0 * (r.size.x + r.size.y)
	for k in n:
		var d := float(k) / float(n) * per
		var pt := Vector2.ZERO
		if d < r.size.x:
			pt = r.position + Vector2(d, 0)
		elif d < r.size.x + r.size.y:
			pt = Vector2(r.end.x, r.position.y + d - r.size.x)
		elif d < 2.0 * r.size.x + r.size.y:
			pt = Vector2(r.end.x - (d - r.size.x - r.size.y), r.end.y)
		else:
			pt = Vector2(r.position.x, r.end.y - (d - 2.0 * r.size.x - r.size.y))
		var at := Vector3(pt.x, _ground + y_off, pt.y)
		var v := Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 0.9), randf_range(-0.4, 0.4))
		var p := _dust.emit(at, v, Color(_tint, 0.7), randf_range(0.12, 0.22) * scale_f, randf_range(0.8, 1.4), 0.2, 1.2)
		if p != null:
			p.grow = 0.25


## Material put down by a worker who has walked it over.
func drop_pile(kind: String, at: Vector3) -> void:
	if _piles.size() >= 4 or _dying >= 0.0:
		return
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = randf() * TAU
	add_child(holder)
	var item := CarriedItem.new()
	item.build(kind)
	item.position = Vector3(0.0, 0.14, 0.0)
	holder.add_child(item)
	_piles.append(holder)
	for k in 5:
		_dust.emit(at + Vector3(0, 0.1, 0), Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.6), randf_range(-0.6, 0.6)),
			Color(_tint, 0.6), randf_range(0.08, 0.14), 0.7, 0.5, 1.5)


## The building is up: the frame comes down in a cloud, the flag lowers, and
## there is confetti and the building's name over the roof for a few seconds.
func celebrate(title: String) -> void:
	_dying = 7.0
	if _scaffold != null:
		var ring := _rect.grow(Scaffolding.STANDOFF_M)
		for k in 3:
			_puff_ring(ring, 0.4 + k * (_height * 0.45), 22, 1.1)
		_scaffold.queue_free()
		_scaffold = null
	_marker.queue_free()
	_marker = null
	_flag.queue_free()
	_flag = null
	_label = null
	for p in _piles:
		p.queue_free()
	_piles.clear()
	# Confetti: a fountain from the roof centre, in the village's own colours.
	var centre := _rect.get_center()
	var top := Vector3(centre.x, _ground + _height + 0.5, centre.y)
	var cols := [Color("#e8a93a"), Color("#d9573f"), Color("#7fc15a"), Color("#4f9bd6"),
		Color("#f4e6c8"), Color("#b06bd0")]
	for k in 90:
		var a := randf() * TAU
		var sp := randf_range(1.2, 3.4)
		var v := Vector3(cos(a) * sp, randf_range(4.0, 7.5), sin(a) * sp)
		var p := _dust.emit(top, v, cols[k % cols.size()], randf_range(0.07, 0.12),
			randf_range(2.2, 3.6), 5.5, 0.35)
		if p != null:
			p.spin = randf_range(-9.0, 9.0)
	if title != "":
		_name_label = _make_label(title, 56)
		_name_label.top_level = true
		add_child(_name_label)
		_name_label.global_position = Vector3(centre.x, _ground + _height + 2.2, centre.y)
	set_process(true)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if _dying >= 0.0:
		_dying -= delta
		if _name_label != null:
			_name_label.modulate.a = clampf(_dying / 1.5, 0.0, 1.0)
			_name_label.outline_modulate.a = _name_label.modulate.a
			_name_label.global_position.y += delta * 0.12
		if _dying <= 0.0:
			queue_free()
			return
	# The flag's number is read from far away: grow it with distance so it
	# stays about the same size on screen, and hide it beyond the point where
	# the town has stopped being something you can read.
	if cam != null and _label != null and _flag != null:
		var d := cam.global_position.distance_to(_flag.global_position)
		_label.visible = d < 220.0
		var s := clampf(d / 14.0, 1.0, 9.0)
		_label.scale = Vector3(s, s, s)
		_label.position.y = _flag_h + 0.6 + 0.2 * s
	if cam != null and _name_label != null:
		var d2 := cam.global_position.distance_to(_name_label.global_position)
		var s2 := clampf(d2 / 18.0, 1.0, 6.0)
		_name_label.scale = Vector3(s2, s2, s2)
