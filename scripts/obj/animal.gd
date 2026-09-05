extends CharacterBody3D
class_name Animal
## A hen, a sheep or a cow, built from the same boxes as everything else.
##
## Deliberately simple: wander, avoid whatever is walking at you, and produce
## something on a timer. There is no hunger, no breeding tree and no mob AI
## here, because livestock is scenery that pays — the game is about the three
## workers, and an animal that needs managing would compete with them for the
## player's attention.
##
## The one piece of real physics is the fall. A hen flutters; a cow does not.

signal produced(kind: String, at: Vector3)

const U := 0.05
const GRAVITY := 22.0

## kind -> everything that makes one species different from another.
const SPECIES := {
	"hen": {
		"speed": 1.5, "wander": 3.0, "flee": 3.2, "shy": 2.6,
		"fall": 2.2,                       ## terminal speed: hens flutter down
		"gives": "egg", "every": 9.0,      ## in-game hours
		"body": Color("#e8e4dc"), "trim": Color("#c8352c"),
		"beak": Color("#e0a02a"), "leg": Color("#d8973a"),
		"size": Vector3(0.30, 0.28, 0.42), "stand": 0.20, "cap": 0.42,
	},
	"sheep": {
		"speed": 1.1, "wander": 4.5, "flee": 2.4, "shy": 2.2,
		"fall": 22.0,
		"gives": "wool", "every": 26.0,
		"body": Color("#e6e2d6"), "trim": Color("#2f2b26"),
		"beak": Color("#2f2b26"), "leg": Color("#3a342c"),
		"size": Vector3(0.56, 0.52, 1.05), "stand": 0.42, "cap": 0.96,
	},
	"cow": {
		"speed": 1.0, "wander": 5.5, "flee": 2.0, "shy": 2.0,
		"fall": 22.0,
		"gives": "milk", "every": 20.0,
		"body": Color("#4a3a2c"), "trim": Color("#e8e4dc"),
		"beak": Color("#c99a86"), "leg": Color("#33281f"),
		"size": Vector3(0.76, 0.78, 1.90), "stand": 0.72, "cap": 1.52,
	},
}

var kind := "hen"
var world: VoxelWorld
var clock: GameClock
var avoid: Node3D = null            ## the player; livestock keeps its distance
var home := Vector3.ZERO
var roam := 11.0

var _spec: Dictionary = {}
var _target := Vector3.ZERO
var _rest := 0.0
var _phase := 0.0
var _since_produced := 0.0
var _legs: Array[Node3D] = []
var _head: Node3D
var _torso: Node3D


func setup(species: String, w: VoxelWorld, c: GameClock, at: Vector3) -> void:
	kind = species if SPECIES.has(species) else "hen"
	_spec = SPECIES[kind]
	world = w
	clock = c
	home = at
	global_position = at

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(_spec["size"].x) * 0.5
	cap.height = float(_spec["cap"])
	cs.shape = cap
	cs.position.y = float(_spec["cap"]) * 0.5
	add_child(cs)

	# Livestock does not push the player about and the player does not herd it
	# by walking into it, so it collides with the world and nothing else.
	collision_layer = 0
	collision_mask = 1

	_build()
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.4
	_rest = randf_range(0.5, 3.0)
	_since_produced = randf_range(0.0, float(_spec["every"]))


func _build() -> void:
	var s: Vector3 = _spec["size"]
	var stand := float(_spec["stand"])

	_torso = Node3D.new()
	_torso.position.y = stand
	add_child(_torso)
	_box(_torso, Vector3(-s.x * 0.5, 0.0, -s.z * 0.5), s, _spec["body"])

	# Markings, so a cow is not a brown box and a hen is not a white one.
	_box(_torso, Vector3(-s.x * 0.5 - 0.01, s.y * 0.35, -s.z * 0.18),
		Vector3(s.x + 0.02, s.y * 0.30, s.z * 0.34), _spec["trim"])
	# A tail at the back, which is the other half of reading which way an animal
	# is pointing.
	if kind == "hen":
		_box(_torso, Vector3(-s.x * 0.22, s.y * 0.55, -s.z * 0.62),
			Vector3(s.x * 0.44, s.y * 0.5, s.z * 0.18), _spec["body"].darkened(0.1))
	else:
		_box(_torso, Vector3(-0.03, s.y * 0.5, -s.z * 0.52),
			Vector3(0.06, 0.06, s.z * 0.1), _spec["leg"])
		_box(_torso, Vector3(-0.04, s.y * 0.12, -s.z * 0.55),
			Vector3(0.08, s.y * 0.4, 0.06), _spec["leg"])

	# The head is at +Z, because +Z is the front of everything in this project —
	# props, people and livestock alike. Built at -Z, as this was, the steering
	# code turns the animal so its tail leads and the whole flock reverses
	# around the field.
	_head = Node3D.new()
	_head.position = Vector3(0.0, s.y * 0.62, s.z * 0.5)
	_torso.add_child(_head)
	var hs := s.x * 0.72
	_box(_head, Vector3(-hs * 0.5, -hs * 0.4, -hs * 0.2), Vector3(hs, hs, hs * 0.9),
		_spec["body"])
	_box(_head, Vector3(-hs * 0.18, -hs * 0.1, hs * 0.65),
		Vector3(hs * 0.36, hs * 0.26, hs * 0.3), _spec["beak"])
	_box(_head, Vector3(-hs * 0.32, hs * 0.18, hs * 0.7),
		Vector3(hs * 0.14, hs * 0.14, 0.02), Color("#15140f"))
	_box(_head, Vector3(hs * 0.18, hs * 0.18, hs * 0.7),
		Vector3(hs * 0.14, hs * 0.14, 0.02), Color("#15140f"))
	if kind == "hen":
		# Comb along the crown and a wattle under the beak.
		_box(_head, Vector3(-hs * 0.08, hs * 0.44, hs * 0.1),
			Vector3(hs * 0.16, hs * 0.3, hs * 0.5), _spec["trim"])
		_box(_head, Vector3(-hs * 0.1, -hs * 0.3, hs * 0.62),
			Vector3(hs * 0.2, hs * 0.22, hs * 0.16), _spec["trim"])
	else:
		# Ears, which is most of the difference between a sheep and a brick.
		_box(_head, Vector3(-hs * 0.62, hs * 0.1, hs * 0.05),
			Vector3(hs * 0.2, hs * 0.12, hs * 0.34), _spec["body"].darkened(0.12))
		_box(_head, Vector3(hs * 0.42, hs * 0.1, hs * 0.05),
			Vector3(hs * 0.2, hs * 0.12, hs * 0.34), _spec["body"].darkened(0.12))
	if kind == "cow":
		_box(_head, Vector3(-hs * 0.58, hs * 0.34, hs * 0.2),
			Vector3(hs * 0.16, hs * 0.16, hs * 0.16), Color("#e8e0cc"))
		_box(_head, Vector3(hs * 0.42, hs * 0.34, hs * 0.2),
			Vector3(hs * 0.16, hs * 0.16, hs * 0.16), Color("#e8e0cc"))

	var lx := s.x * 0.30
	var lz := s.z * 0.30
	var legs := 2 if kind == "hen" else 4
	for i in legs:
		var n := Node3D.new()
		n.position = Vector3(lx * (1.0 if i % 2 == 0 else -1.0), stand,
			lz * (1.0 if i < 2 else -1.0) * (0.0 if legs == 2 else 1.0))
		_box(n, Vector3(-0.035, -stand, -0.035), Vector3(0.07, stand, 0.07),
			_spec["leg"])
		add_child(n)
		_legs.append(n)


func _box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.92
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = origin + size * 0.5
	parent.add_child(mi)


# ------------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		# Terminal velocity is the whole of the difference between a hen and a
		# cow falling off a wall.
		velocity.y = maxf(velocity.y - GRAVITY * delta, -float(_spec["fall"]))
	else:
		velocity.y = 0.0

	var speed := _decide(delta)
	move_and_slide()
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	_tick_produce(delta)
	if speed > 0.0 and is_on_wall() and is_on_floor():
		velocity.y = 3.6


func _decide(delta: float) -> float:
	# Somebody walking at it beats whatever it was doing.
	if avoid != null:
		var away := global_position - avoid.global_position
		away.y = 0.0
		var d := away.length()
		if d < float(_spec["shy"]) and d > 0.01:
			var dir := away / d
			var flee := float(_spec["flee"])
			velocity.x = dir.x * flee
			velocity.z = dir.z * flee
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 9.0)
			_rest = randf_range(0.3, 1.2)
			return flee

	_rest -= delta
	if _rest > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		return 0.0

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	if to.length() < 0.6:
		_pick_target()
		_rest = randf_range(1.4, 5.5)
		return 0.0

	var speed := float(_spec["speed"])
	var dir := to.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 5.0)
	return speed


func _pick_target() -> void:
	var a := randf() * TAU
	var r := randf() * roam
	_target = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if world != null:
		_target.y = world.ground_m(_target.x, _target.z)


func _animate(delta: float, speed: float) -> void:
	if speed > 0.05:
		_phase += delta * speed * 5.5
		var swing := sin(_phase) * 0.7
		for i in _legs.size():
			_legs[i].rotation.x = swing * (1.0 if i % 2 == 0 else -1.0)
		# The head bob is what makes a box look alive.
		_head.position.y = float(_spec["size"].y) * 0.62 + sin(_phase * 2.0) * 0.02
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, delta * 6.0)
		_torso.rotation.z = sin(_phase) * 0.02
	else:
		for l: Node3D in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, delta * 8.0)
		_torso.rotation.z = lerpf(_torso.rotation.z, 0.0, delta * 8.0)
		# Pecking at the ground while idle.
		_phase += delta * 1.3
		var peck := maxf(sin(_phase * 0.9), 0.0)
		_head.rotation.x = -peck * peck * 0.9


## Eggs, wool and milk arrive on the game clock, so a herd left alone for two
## in-game days has two days of produce waiting.
func _tick_produce(delta: float) -> void:
	if clock == null or clock.paused:
		return
	_since_produced += delta / 60.0 * GameClock.HOURS_PER_REAL_MINUTE * clock.speed
	if _since_produced < float(_spec["every"]):
		return
	_since_produced = 0.0
	produced.emit(str(_spec["gives"]), global_position)
