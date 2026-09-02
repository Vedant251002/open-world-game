extends Node3D
## NEON BAY CITY — procedural Vice-City-style city generator.
## Roads (asphalt + lane dashes + zebra crossings), raised sidewalks,
## 36 blocks of buildings with neon signs, park, beach + ocean,
## enterable shops with furnished + lit interiors, lamps & traffic lights.

const BLOCK := 48.0          # distance between road centerlines
const HALF_ROAD := 6.0       # road half-width (12m roads)
const SIDEWALK := 3.0
const GRID := 7              # 7 road lines -> 6x6 blocks
const CITY_SCALE := 12.0     # Kenney city-kit uniform scale

const A := "res://assets/"

const PASTELS := ["#ff6ea9", "#4dd7ff", "#ffe14d", "#9dff6e", "#ff9d5c", "#c49bff", "#7de3c8", "#ff5f6d"]
const NEON := ["#ff2d95", "#00e5ff", "#ffd400", "#39ff88", "#ff7b00", "#b967ff", "#ff4d6d", "#4dfff0"]
const SHOP_NAMES := ["DINER", "CAFE", "ARCADE", "RECORDS", "SURF SHOP", "PIZZA"]

const Tint := preload("res://scripts/building_tint.gd")

var growing: Array = []   # buildings animating in: {node, t}

var spawn_point := Vector3.ZERO
var spawn_yaw := 180.0
var lane_circuits: Array = []      # traffic lanes
var ped_rings: Array = []          # sidewalk loops per block
var shop_entries: Array = []       # {outside: Vector3, inside: Vector3, yaw: float, name: String}

var _rng := RandomNumberGenerator.new()
var _scene_cache := {}
var _dash_boxes: Array = []
var _zebra_boxes: Array = []
var _pulse_signs: Array = []   # {mat, base_energy} — animated neon pulse
var _neon_phase := 0.0


func generate() -> void:
	_rng.seed = 20260830
	_build_ground_and_ocean()
	_build_roads()
	_build_sidewalks()
	_build_blocks()
	_build_beach()
	_register_graph()
	spawn_point = Vector3(7.5, 1.05, -30.0)
	spawn_yaw = 180.0


func _process(delta: float) -> void:
	# city grow-in transition: each new building pops/scales in with a bounce
	if not growing.is_empty():
		var done := []
		for g in growing:
			g["t"] += delta * 2.2
			var t: float = g["t"]
			var overshoot: float = 1.0 + 0.18 * sin(clampf(t, 0.0, PI) * 1.0) * (1.0 - t / PI)
			var s: float = clampf(t, 0.0, 1.0) * overshoot
			g["node"].scale = (g["base"] as Vector3) * s
			if t >= 1.0:
				g["node"].scale = g["base"]
				done.append(g)
		for d in done:
			growing.erase(d)
	# neon pulse: signs breathe between 60% and 130% brightness
	_neon_phase += delta
	if not _pulse_signs.is_empty():
		var pulse: float = 0.6 + 0.35 * (sin(_neon_phase * 2.0) * 0.5 + 0.5) + 0.35 * (sin(_neon_phase * 5.3) * 0.5 + 0.5)
		for s in _pulse_signs:
			(s["mat"] as StandardMaterial3D).emission_energy_multiplier = s["base"] * pulse


# ------------------------------------------------------------- helpers
func _load(path: String) -> Node3D:
	if not _scene_cache.has(path):
		var ps: PackedScene = load(path)
		if ps == null:
			push_warning("missing asset: " + path)
			_scene_cache[path] = null
			return Node3D.new()
		_scene_cache[path] = ps
	var ps2: PackedScene = _scene_cache[path]
	if ps2 == null:
		return Node3D.new()
	return ps2.instantiate()


func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _flat_mat(color: String, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = rough
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	var col: Color = color if color is Color else Color(String(color))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _collider(parent: Node, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	sb.add_child(cs)
	parent.add_child(sb)


func _neon(parent: Node, text: String, pos: Vector3, yaw_deg: float, col: String) -> void:
	# glowing sign board + readable text
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.6, 1.1)
	board.mesh = pm
	board.rotation = Vector3(-90, 0, 0) if false else Vector3(0, deg_to_rad(yaw_deg), 0)
	board.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#141428")
	m.emission_enabled = true
	m.emission = Color(col)
	m.emission_energy_multiplier = 2.6
	board.material_override = m
	parent.add_child(board)

	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.012
	l.modulate = Color(col)
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = pos + Vector3(0, 0, 0.12).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	l.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	parent.add_child(l)
	# register for the pulse animation
	_pulse_signs.append({"mat": m, "base": 2.6})


func _pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]


# ------------------------------------------------------------- ground + ocean
func _build_ground_and_ocean() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	g.mesh = pm
	g.position = Vector3(0, -0.01, 0)
	g.material_override = _flat_mat("#8a7a5c")
	add_child(g)
	_collider(self, Vector3(1200, 0.4, 1200), Vector3(0, -0.22, 0))

	# ocean east of the beach, shader-animated
	var ocean := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(500, 1000)
	ocean.mesh = om
	ocean.position = Vector3(300 + 250, -0.3, 0)
	var wmat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 deep = vec3(0.03, 0.17, 0.28);
uniform vec3 shallow = vec3(0.12, 0.52, 0.58);
void fragment() {
	float w = sin(UV.x * 60.0 + TIME * 1.1) * 0.5 + 0.5;
	float w2 = sin(UV.y * 34.0 - TIME * 0.7) * 0.5 + 0.5;
	vec3 col = mix(deep, shallow, clamp(w * 0.6 + w2 * 0.4, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
}
"""
	wmat.shader = sh
	ocean.material_override = wmat
	add_child(ocean)

	# wet-sand strip between beach and water
	_box(self, Vector3(14, 0.06, 400), Vector3(300 - 6, -0.03, 0), "#c9b189")


# ------------------------------------------------------------- roads
func _build_roads() -> void:
	var asphalt := _flat_mat("#34353d", 0.95)
	var n := GRID
	var half := (n - 1) / 2.0
	for i in range(n):
		var c := (i - half) * BLOCK
		# vertical road (along Z) at x = c
		var pv := PlaneMesh.new()
		pv.size = Vector2(HALF_ROAD * 2.0, 300.0)
		_add_mesh(pv, Vector3(c, 0.02, 0), asphalt)
		# horizontal road (along X) at z = c
		var ph := PlaneMesh.new()
		ph.size = Vector2(300.0, HALF_ROAD * 2.0)
		_add_mesh(ph, Vector3(0, 0.025, c), asphalt)

		# center dashes
		var zz := -146.0
		while zz < 146.0:
			_dash_boxes.append(Vector3(c, 0.035, zz))
			_dash_boxes.append(Vector3(zz, 0.035, c))
			zz += 5.0

	# zebra crossings at every intersection edge
	for i in range(n):
		for j in range(n):
			var cx := (i - half) * BLOCK
			var cz := (j - half) * BLOCK
			for s in [-1.0, 1.0]:
				# across vertical road (stripes stacked along X)
				var xx := cx - 4.5
				while xx <= cx + 4.5:
					_zebra_boxes.append(Vector3(xx, 0.03, cz + s * 7.5))
					xx += 0.9
				# across horizontal road (stripes stacked along Z)
				var zz2 := cz - 4.5
				while zz2 <= cz + 4.5:
					_zebra_boxes.append(Vector3(cx + s * 7.5, 0.03, zz2))
					zz2 += 0.9

	_add_multimesh(_dash_boxes, Vector3(0.18, 0.01, 2.6), "#d9c98a")
	_add_multimesh(_zebra_boxes, Vector3(0.45, 0.01, 2.6), "#e8e8e8")


func _add_multimesh(boxes: Array, size: Vector3, color: String) -> void:
	if boxes.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = size
	mm.mesh = bm
	mm.instance_count = boxes.size()
	for i in range(boxes.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), boxes[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _flat_mat(color, 0.9)
	add_child(mmi)


# ------------------------------------------------------------- sidewalks
func _build_sidewalks() -> void:
	var concrete := _flat_mat("#9a9aa2", 0.92)
	var half := (GRID - 1) / 2.0
	for i in range(GRID - 1):
		for j in range(GRID - 1):
			var x0 := (i - half) * BLOCK
			var z0 := (j - half) * BLOCK
			var x1 := x0 + BLOCK
			var z1 := z0 + BLOCK
			# N/S edges (length 30 between corners)
			_box(self, Vector3(30, 0.15, 3), Vector3(x0 + 24, 0.075, z0 + 7.5), "#9a9aa2")
			_box(self, Vector3(30, 0.15, 3), Vector3(x0 + 24, 0.075, z1 - 7.5), "#9a9aa2")
			# E/W edges
			_box(self, Vector3(3, 0.15, 30), Vector3(x0 + 7.5, 0.075, z0 + 24), "#9a9aa2")
			_box(self, Vector3(3, 0.15, 30), Vector3(x1 - 7.5, 0.075, z0 + 24), "#9a9aa2")
			# corners
			for cx in [x0 + 7.5, x1 - 7.5]:
				for cz in [z0 + 7.5, z1 - 7.5]:
					_box(self, Vector3(3, 0.15, 3), Vector3(cx, 0.075, cz), "#9a9aa2")
	# colliders for all sidewalk boxes (one big ring collider per block edge)
	for i in range(GRID - 1):
		for j in range(GRID - 1):
			var x0 := (i - half) * BLOCK
			var z0 := (j - half) * BLOCK
			var x1 := x0 + BLOCK
			var z1 := z0 + BLOCK
			_collider(self, Vector3(36, 0.15, 3), Vector3(x0 + 24, 0.075, z0 + 7.5))
			_collider(self, Vector3(36, 0.15, 3), Vector3(x0 + 24, 0.075, z1 - 7.5))
			_collider(self, Vector3(3, 0.15, 36), Vector3(x0 + 7.5, 0.075, z0 + 24))
			_collider(self, Vector3(3, 0.15, 36), Vector3(x1 - 7.5, 0.075, z0 + 24))
	# boardwalk east of the city (east sidewalk of outer road)
	_box(self, Vector3(3, 0.15, 300), Vector3(151.5, 0.075, 0), "#a8a294")
	_collider(self, Vector3(3, 0.15, 300), Vector3(151.5, 0.075, 0))
	var _unused := concrete


# ------------------------------------------------------------- blocks
func _road_coord(i: int) -> float:
	return (i - (GRID - 1) / 2.0) * BLOCK


func _build_blocks() -> void:
	var parks := {Vector2i(4, 1): true, Vector2i(1, 4): true}
	for i in range(GRID - 1):
		for j in range(GRID - 1):
			if parks.has(Vector2i(i, j)):
				_build_park(i, j)
				continue
			_build_city_block(i, j)
	# enterable shops on fixed blocks
	_build_shop_row(2, 2, true)
	_build_shop_row(3, 3, false)


func _build_city_block(i: int, j: int) -> void:
	var x0 := _road_coord(i)
	var z0 := _road_coord(j)
	var x1 := x0 + BLOCK
	var z1 := z0 + BLOCK
	var bcount := 0
	for e in range(4):
		for k in range(2):
			var along := 0.31 if k == 0 else 0.69
			var px: float
			var pz: float
			var yaw: float
			var is_sky := false
			match e:
				0:  # south edge, faces -Z
					px = x0 + 9 + along * 30.0
					pz = z0 + 9 + 7.0
					yaw = 180.0
				1:  # north edge, faces +Z
					px = x0 + 9 + along * 30.0
					pz = z1 - 9 - 7.0
					yaw = 0.0
				2:  # west edge, faces -X
					px = x0 + 9 + 7.0
					pz = z0 + 9 + along * 30.0
					yaw = -90.0
				3:  # east edge, faces +X
					px = x1 - 9 - 7.0
					pz = z0 + 9 + along * 30.0
					yaw = 90.0
			# downtown blocks get occasional skyscrapers
			if (i == 2 or i == 3) and (j == 2 or j == 3) and _rng.randf() < 0.35:
				is_sky = true
			_spawn_building(Vector3(px, 0.0, pz), yaw, is_sky, bcount)
			bcount += 1


func _spawn_building(pos: Vector3, yaw: float, is_sky: bool, seed_idx: int) -> void:
	var path: String
	var height := 15.5
	var footprint := 11.0
	if is_sky:
		path = A + "buildings/sky_%d.glb" % _rng.randi_range(1, 3)
		height = 34.6
		footprint = 16.3
	else:
		var r := _rng.randf()
		if r < 0.22:
			path = A + "buildings/ind_%d.glb" % _rng.randi_range(1, 6)
			height = 13.0
		else:
			path = A + "buildings/bldg_%d.glb" % _rng.randi_range(1, 14)
	var inst := _load(path)
	inst.position = pos
	inst.rotation.y = deg_to_rad(yaw)
	inst.scale = Vector3.ONE * CITY_SCALE
	add_child(inst)
	# per-building pastel identity (Vice City vibe)
	var tint_col := Color(PASTELS[(pos.x * 3.0 + pos.z * 7.0) as int % PASTELS.size()]).lightened(0.18)
	Tint.tint(inst, tint_col, 0.45)
	# grow-in transition
	growing.append({"node": inst, "t": -float(seed_idx % 30) * 0.08, "base": Vector3.ONE * CITY_SCALE})
	# collider (approx from measured kit dims)
	var fw := footprint
	var fd := footprint
	if abs(yaw) > 45.0 and abs(yaw) < 135.0:
		var t := fw
		fw = fd
		fd = t
	_collider(self, Vector3(fw, height, fd), pos + Vector3(0, height / 2.0, 0))
	# neon sign on the road-facing side
	if _rng.randf() < 0.45:
		var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		var sign_pos := pos + fwd * (fd / 2.0 + 0.5) + Vector3(0, height * 0.55 + 1.2, 0)
		_neon(self, _pick(["MALIBU", "OCEAN VIEW", "HOTEL", "NEON", "CLUB", "TATTOO", "ARCADE", "RECORDS", "BAR", "PIZZA", "BAKERY", "JEWELERS", "SURF", "FLAMINGO", "GOLF"]), sign_pos, yaw, NEON[seed_idx % NEON.size()])
	# pastel awning near the entrance
	if _rng.randf() < 0.5:
		var fwd2 := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		var aw := _box(self, Vector3(4.5, 0.2, 1.4), pos + fwd2 * (fd / 2.0 + 0.6) + Vector3(0, 3.4, 0), PASTELS[seed_idx % PASTELS.size()])
		aw.rotation.y = deg_to_rad(yaw)


func _build_park(i: int, j: int) -> void:
	var x0 := _road_coord(i) + 9
	var z0 := _road_coord(j) + 9
	var cx := x0 + 15
	var cz := z0 + 15
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	grass.mesh = pm
	grass.position = Vector3(cx, 0.02, cz)
	grass.material_override = _flat_mat("#4d7d52")
	add_child(grass)
	for k in range(6):
		var p := _load(A + "palms/palm_%d.glb" % ((k % 5) + 1))
		p.position = Vector3(cx + _rng.randf_range(-12, 12), 0.0, cz + _rng.randf_range(-12, 12))
		p.scale = Vector3.ONE * _rng.randf_range(5.5, 8.0)
		add_child(p)
	# benches facing center
	for k in range(4):
		var ang := k * TAU / 4.0
		var bp := Vector3(cx + cos(ang) * 9.0, 0.02, cz + sin(ang) * 9.0)
		var b := _load(A + "furniture/furn_1.glb")
		b.position = bp
		b.scale = Vector3.ONE * 3.0
		b.rotation.y = ang + PI / 2.0
		add_child(b)


# ------------------------------------------------------------- enterable shops
func _build_shop_row(i: int, j: int, on_south: bool) -> void:
	var x0 := _road_coord(i)
	var z0 := _road_coord(j)
	var names := SHOP_NAMES
	var idx := 0
	for k in range(2):
		var sx := x0 + 15 + k * 18.0
		var sz: float
		var yaw: float
		if on_south:
			sz = z0 + 9 + 4.8
			yaw = 180.0   # door faces the south road
		else:
			sz = z0 + BLOCK - 9 - 4.8
			yaw = 0.0
		_build_shop(Vector3(sx, 0.0, sz), yaw, names[(i + j + k) % names.size()])
		idx += 1


func _build_shop(pos: Vector3, yaw_deg: float, shop_name: String) -> void:
	var W := 11.0
	var D := 9.0
	var H := 4.8
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = deg_to_rad(yaw_deg)
	add_child(root)
	var wall_col := Color(PASTELS[int(abs(pos.x + pos.z)) % PASTELS.size()]).lightened(0.22)

	# floor
	_box(root, Vector3(W, 0.12, D), Vector3(0, 0.06, 0), "#6b6b74")
	_collider(root, Vector3(W, 0.12, D), Vector3(0, 0.06, 0))
	# back wall
	_box(root, Vector3(W, H, 0.3), Vector3(0, H / 2.0, -D / 2.0 + 0.15), wall_col)
	_collider(root, Vector3(W, H, 0.3), Vector3(0, H / 2.0, -D / 2.0 + 0.15))
	# side walls
	_box(root, Vector3(0.3, H, D), Vector3(-W / 2.0 + 0.15, H / 2.0, 0), wall_col)
	_collider(root, Vector3(0.3, H, D), Vector3(-W / 2.0 + 0.15, H / 2.0, 0))
	_box(root, Vector3(0.3, H, D), Vector3(W / 2.0 - 0.15, H / 2.0, 0), wall_col)
	_collider(root, Vector3(0.3, H, D), Vector3(W / 2.0 - 0.15, H / 2.0, 0))
	# roof
	_box(root, Vector3(W, 0.3, D), Vector3(0, H + 0.15, 0), "#3a3a48")
	_collider(root, Vector3(W, 0.3, D), Vector3(0, H + 0.15, 0))
	# front wall with 3.2m door gap
	var segw := (W - 3.2) / 2.0
	_box(root, Vector3(segw, H, 0.3), Vector3(-(3.2 / 2.0 + segw / 2.0), H / 2.0, D / 2.0 - 0.15), wall_col)
	_collider(root, Vector3(segw, H, 0.3), Vector3(-(3.2 / 2.0 + segw / 2.0), H / 2.0, D / 2.0 - 0.15))
	_box(root, Vector3(segw, H, 0.3), Vector3(3.2 / 2.0 + segw / 2.0, H / 2.0, D / 2.0 - 0.15), wall_col)
	_collider(root, Vector3(segw, H, 0.3), Vector3(3.2 / 2.0 + segw / 2.0, H / 2.0, D / 2.0 - 0.15))
	_box(root, Vector3(3.2, H - 2.7, 0.3), Vector3(0, 2.7 + (H - 2.7) / 2.0, D / 2.0 - 0.15), wall_col)
	_collider(root, Vector3(3.2, H - 2.7, 0.3), Vector3(0, 2.7 + (H - 2.7) / 2.0, D / 2.0 - 0.15))

	# big neon sign above the door
	_neon(root, shop_name, Vector3(0, H + 0.7, D / 2.0 + 0.3), 0.0, NEON[int(abs(pos.x)) % NEON.size()])

	# interior: warm light + furniture ring
	var light := OmniLight3D.new()
	light.light_color = Color("#ffd9a0")
	light.light_energy = 1.7
	light.omni_range = 10.0
	light.position = Vector3(0, H - 0.8, 0)
	root.add_child(light)
	var spots := [
		[Vector3(-W / 2.0 + 1.2, 0.12, -D / 2.0 + 1.6), 90.0],
		[Vector3(W / 2.0 - 1.2, 0.12, -D / 2.0 + 1.6), -90.0],
		[Vector3(-W / 2.0 + 1.2, 0.12, 0.5), 90.0],
		[Vector3(W / 2.0 - 1.2, 0.12, 0.5), -90.0],
		[Vector3(0, 0.12, -D / 2.0 + 1.4), 180.0],
	]
	for s in range(5):
		var f := _load(A + "furniture/furn_%d.glb" % ((s % 14) + 1))
		f.position = spots[s][0]
		f.rotation.y = deg_to_rad(spots[s][1])
		f.scale = Vector3.ONE * 3.0
		root.add_child(f)

	# entry info for autocap / future AI worker tasks
	var fwd := Vector3(sin(deg_to_rad(yaw_deg)), 0, cos(deg_to_rad(yaw_deg)))
	shop_entries.append({
		"outside": pos + fwd * (D / 2.0 + 1.0),
		"inside": pos + fwd * (-1.5),
		"yaw": yaw_deg,
		"name": shop_name,
	})


# ------------------------------------------------------------- beach
func _build_beach() -> void:
	# parasols + towels: classic beach day colors
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var parasol_cols := ["#ff2d95", "#ffd400", "#00e5ff", "#39ff88"]
	for k in range(14):
		var px := 170.0 + (k % 7) * 9.0
		var pz := -60.0 + (k / 7) * 120.0 + rng.randf_range(-4, 4)
		var ps := _load(A + "props/parasol_%d.glb" % ((k % 2) + 1))
		ps.position = Vector3(px, 0.0, pz)
		ps.scale = Vector3.ONE * 4.0
		add_child(ps)
		Tint.tint(ps, Color(parasol_cols[k % parasol_cols.size()]), 0.6)
		# towel
		var tw := _box(self, Vector3(1.6, 0.03, 2.4), Vector3(px + rng.randf_range(-2.5, 2.5), 0.03, pz + rng.randf_range(2.0, 4.0)), parasol_cols[(k + 2) % parasol_cols.size()])
		tw.rotation.y = rng.randf_range(-0.4, 0.4)
	for k in range(44):
		var p := _load(A + "palms/palm_%d.glb" % ((k % 5) + 1))
		p.position = Vector3(_rng.randf_range(158.0, 292.0), 0.0, _rng.randf_range(-190.0, 190.0))
		p.scale = Vector3.ONE * _rng.randf_range(5.0, 8.5)
		add_child(p)
	# a few palms on city sidewalks
	var half := (GRID - 1) / 2.0
	for i in range(GRID):
		for j in range(GRID):
			if (i + j) % 3 == 0:
				var p2 := _load(A + "palms/palm_%d.glb" % (((i + j) % 5) + 1))
				p2.position = Vector3((i - half) * BLOCK + 7.5, 0.15, (j - half) * BLOCK + 7.5)
				p2.scale = Vector3.ONE * 6.0
				add_child(p2)
	# street lamps at intersections
	for i in range(GRID):
		for j in range(GRID):
			var cx := (i - half) * BLOCK
			var cz := (j - half) * BLOCK
			var lamp := _load(A + "props/lamp.glb")
			lamp.position = Vector3(cx - 7.5, 0.15, cz - 7.5)
			lamp.scale = Vector3.ONE * 12.0
			add_child(lamp)
			if (i + j) % 2 == 0:
				var lamp2 := _load(A + "props/lamp.glb")
				lamp2.position = Vector3(cx + 7.5, 0.15, cz + 7.5)
				lamp2.scale = Vector3.ONE * 12.0
				add_child(lamp2)
			# traffic lights in the inner city
			if i >= 2 and i <= 4 and j >= 2 and j <= 4:
				var tl := _load(A + "props/traffic_light.glb")
				tl.position = Vector3(cx + 7.5, 0.15, cz - 7.5)
				tl.scale = Vector3.ONE * 20.0
				add_child(tl)


# ------------------------------------------------------------- graphs
func _register_graph() -> void:
	var half := (GRID - 1) / 2.0
	# car lanes: every road line, both directions, right-hand lane offset 3m
	for i in range(GRID):
		var c := (i - half) * BLOCK
		lane_circuits.append({"axis": "z", "coord": c, "off": 3.0, "from": -146.0, "to": 146.0, "dir": 1.0})
		lane_circuits.append({"axis": "z", "coord": c, "off": -3.0, "from": -146.0, "to": 146.0, "dir": -1.0})
		lane_circuits.append({"axis": "x", "coord": c, "off": 3.0, "from": -146.0, "to": 146.0, "dir": 1.0})
		lane_circuits.append({"axis": "x", "coord": c, "off": -3.0, "from": -146.0, "to": 146.0, "dir": -1.0})
	# pedestrian sidewalk rings per block
	for i in range(GRID - 1):
		for j in range(GRID - 1):
			var x0 := (i - half) * BLOCK + 7.5
			var z0 := (j - half) * BLOCK + 7.5
			var x1 := x0 + BLOCK - 15.0
			var z1 := z0 + BLOCK - 15.0
			ped_rings.append([
				Vector3(x0, 0.15, z0),
				Vector3(x1, 0.15, z0),
				Vector3(x1, 0.15, z1),
				Vector3(x0, 0.15, z1),
			])
