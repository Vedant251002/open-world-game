extends Node3D
class_name Humanoid
## A worker body, built from Tier B object voxels at 0.05 m.
##
## Seven voxels wide and twenty-eight tall in world-voxel terms, which is the
## human scale reference in voxel-module-spec.md §1. Limbs are separate nodes so
## the walk cycle is a rotation rather than a skeleton — nobody is going to
## critique an NPC's animation blending, and this costs nothing.

const U := 0.05

var body_colour := Color("#8a5a3c")
var cloth_colour := Color("#5d6f8a")
var hair_colour := Color("#3b2a1c")
var accent_colour := Color("#b8552f")

var head: Node3D
var torso: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D

var _phase := 0.0
var _carrying := false


func _ready() -> void:
	_build()


func _build() -> void:
	torso = Node3D.new()
	torso.position.y = 0.72
	add_child(torso)
	_box(torso, Vector3(-0.17, 0.0, -0.10), Vector3(0.34, 0.46, 0.20), cloth_colour)
	# A leather apron, so a worker reads as a builder at fifty metres.
	_box(torso, Vector3(-0.15, 0.02, -0.13), Vector3(0.30, 0.30, 0.04), accent_colour)

	head = Node3D.new()
	head.position.y = 0.50
	torso.add_child(head)
	_box(head, Vector3(-0.13, 0.0, -0.12), Vector3(0.26, 0.26, 0.24), body_colour)
	_box(head, Vector3(-0.14, 0.18, -0.13), Vector3(0.28, 0.10, 0.26), hair_colour)
	# Eyes, at 0.05 m each. Small, but they are what makes a box a person.
	_box(head, Vector3(-0.09, 0.10, -0.13), Vector3(0.05, 0.05, 0.02), Color("#1b1b1f"))
	_box(head, Vector3(0.04, 0.10, -0.13), Vector3(0.05, 0.05, 0.02), Color("#1b1b1f"))

	arm_l = _limb(Vector3(-0.21, 0.42, 0.0), cloth_colour, body_colour, 0.40)
	arm_r = _limb(Vector3(0.21, 0.42, 0.0), cloth_colour, body_colour, 0.40)
	torso.add_child(arm_l)
	torso.add_child(arm_r)

	leg_l = _limb(Vector3(-0.09, 0.0, 0.0), Color("#4a4438"), Color("#3a3128"), 0.44)
	leg_r = _limb(Vector3(0.09, 0.0, 0.0), Color("#4a4438"), Color("#3a3128"), 0.44)
	add_child(leg_l)
	add_child(leg_r)
	leg_l.position.y = 0.72
	leg_r.position.y = 0.72


func _limb(at: Vector3, upper: Color, lower: Color, length: float) -> Node3D:
	var n := Node3D.new()
	n.position = at
	_box(n, Vector3(-0.06, -length, -0.06), Vector3(0.12, length * 0.6, 0.12), upper)
	_box(n, Vector3(-0.06, -length, -0.06), Vector3(0.12, length * 0.35, 0.12), lower)
	return n


func _box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = origin + size * 0.5
	parent.add_child(mi)


## speed is metres per second; 0 stands still.
func animate(delta: float, speed: float, carrying: bool = false) -> void:
	_carrying = carrying
	if speed > 0.1:
		_phase += delta * speed * 3.4
		var swing := sin(_phase) * clampf(speed / 3.0, 0.2, 1.0) * 0.9
		leg_l.rotation.x = swing
		leg_r.rotation.x = -swing
		if not carrying:
			arm_l.rotation.x = -swing * 0.75
			arm_r.rotation.x = swing * 0.75
		torso.position.y = 0.72 + absf(sin(_phase)) * 0.02
		torso.rotation.z = sin(_phase) * 0.03
	else:
		_phase = 0.0
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 9.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 9.0)
		torso.position.y = lerpf(torso.position.y, 0.72, delta * 9.0)
		torso.rotation.z = lerpf(torso.rotation.z, 0.0, delta * 9.0)
		if not carrying:
			arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, delta * 9.0)
			arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, delta * 9.0)

	if carrying:
		arm_l.rotation.x = -1.35
		arm_r.rotation.x = -1.35


## Hammering, for the building state.
func work(delta: float) -> void:
	_phase += delta * 7.0
	arm_r.rotation.x = -1.1 + sin(_phase) * 0.8
	arm_l.rotation.x = -0.5
	torso.rotation.x = 0.12 + sin(_phase) * 0.05
