extends AnimatableBody3D
## Traffic car: drives back and forth along a lane circuit on the road grid.

const Tint := preload("res://scripts/building_tint.gd")

var circuit: Dictionary = {}
var speed := 10.0
var _t := 0.0
static var _idx := 0


func setup_from_graph(gen: Node3D, i: int) -> void:
	if gen.lane_circuits.is_empty():
		return
	circuit = gen.lane_circuits[(i * 7 + 3) % gen.lane_circuits.size()]
	speed = 8.0 + (i % 5) * 1.7
	_t = -140.0 + fmod(float(i) * 37.0, 280.0)


func _ready() -> void:
	var idx := (_idx % 8) + 1
	_idx += 1
	var car := Node3D.new()
	var mesh: Node3D = load("res://assets/cars/car_%d.glb" % idx).instantiate()
	mesh.position = Vector3(0, 0.45, 0)
	car.add_child(mesh)
	var s := 1.5
	car.scale = Vector3.ONE * s
	add_child(car)
	# per-car paint color (Vice City traffic rainbow)
	var paints := [
		Color("#ff5f6d"), Color("#4dd7ff"), Color("#ffe14d"), Color("#9dff6e"),
		Color("#c49bff"), Color("#ff9d5c"), Color("#ff2d95"), Color("#7de3c8"),
	]
	Tint.tint(mesh, paints[_idx % paints.size()], 0.55)

	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.0, 1.3, 4.2)
	cs.shape = sh
	cs.position = Vector3(0, 0.65, 0)
	add_child(cs)


func _physics_process(delta: float) -> void:
	if circuit.is_empty():
		return
	_t += circuit["dir"] * speed * delta
	if _t > circuit["to"]:
		_t = circuit["from"]
	elif _t < circuit["from"]:
		_t = circuit["to"]
	var pos: Vector3
	var yaw := 0.0
	if circuit["axis"] == "z":
		pos = Vector3(circuit["coord"] + circuit["off"], 0.02, _t)
		yaw = 0.0 if circuit["dir"] > 0.0 else 180.0
	else:
		pos = Vector3(_t, 0.02, circuit["coord"] + circuit["off"])
		yaw = 90.0 if circuit["dir"] > 0.0 else -90.0
	global_position = pos
	rotation.y = deg_to_rad(yaw)
