extends Node3D
class_name Humanoid
## A worker body, built from Tier B object voxels at 0.05 m.
##
## Seven voxels wide and twenty-eight tall in world-voxel terms, which is the
## human scale reference in voxel-module-spec.md §1. Limbs are separate nodes so
## the walk cycle is a rotation rather than a skeleton — nobody is going to
## critique an NPC's animation blending, and this costs nothing.
##
## The body faces +Z. That is the same convention every prop uses, and it is not
## arbitrary: the movement code turns a character so that +Z points along its
## velocity, so a model built facing -Z walks backwards everywhere it goes,
## which is exactly what all six characters used to do.
##
## Three of these are the whole cast, so each one has to be recognisable from
## across the plaza at a glance. The colours do some of that; the silhouette
## does the rest, which is what `accessory` is for — a headscarf, a flat cap and
## a broad-brimmed hat read differently at forty metres, and three differently
## coloured identical boxes do not.

const U := 0.05

var body_colour := Color("#8a5a3c")
var cloth_colour := Color("#5d6f8a")
var hair_colour := Color("#3b2a1c")
var accent_colour := Color("#b8552f")
## "scarf", "cap", "brim" or "" — the thing you recognise them by.
var accessory := ""
## Bare forearms rather than sleeves to the wrist.
var rolled_sleeves := false
## A long coat that falls past the hips.
var long_coat := false

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
	var boot := hair_colour.darkened(0.45)
	var trouser := cloth_colour.darkened(0.42)

	torso = Node3D.new()
	torso.position.y = 0.72
	add_child(torso)
	_box(torso, Vector3(-0.17, 0.0, -0.10), Vector3(0.34, 0.46, 0.20), cloth_colour)
	# A leather apron on the front, so a worker reads as a builder at fifty
	# metres rather than as a person in a shirt.
	_box(torso, Vector3(-0.15, 0.02, 0.09), Vector3(0.30, 0.30, 0.04), accent_colour)
	# Collar and shoulder yoke, which is most of what makes a box look tailored.
	_box(torso, Vector3(-0.18, 0.38, -0.11), Vector3(0.36, 0.08, 0.22),
		cloth_colour.darkened(0.18))
	if long_coat:
		_box(torso, Vector3(-0.18, -0.16, -0.11), Vector3(0.36, 0.20, 0.22),
			cloth_colour.darkened(0.10))
		_box(torso, Vector3(-0.19, 0.00, -0.12), Vector3(0.04, 0.40, 0.24),
			cloth_colour.darkened(0.28))
		_box(torso, Vector3(0.15, 0.00, -0.12), Vector3(0.04, 0.40, 0.24),
			cloth_colour.darkened(0.28))
	else:
		# A belt, and a pouch on the hip.
		_box(torso, Vector3(-0.18, 0.03, -0.11), Vector3(0.36, 0.05, 0.22),
			hair_colour.darkened(0.2))
		_box(torso, Vector3(0.10, -0.02, 0.05), Vector3(0.10, 0.11, 0.07),
			accent_colour.darkened(0.25))

	head = Node3D.new()
	head.position.y = 0.50
	torso.add_child(head)
	_box(head, Vector3(-0.13, 0.0, -0.12), Vector3(0.26, 0.26, 0.24), body_colour)
	# Hair: a cap of it, with a fringe at the front rather than a flat slab.
	_box(head, Vector3(-0.14, 0.18, -0.13), Vector3(0.28, 0.10, 0.26), hair_colour)
	_box(head, Vector3(-0.14, 0.13, 0.10), Vector3(0.28, 0.06, 0.04), hair_colour)
	# Eyes, nose and mouth, at 0.05 m each. Small, but they are what makes a box
	# a person — and they are what tells you which way it is looking.
	_box(head, Vector3(-0.09, 0.10, 0.12), Vector3(0.05, 0.05, 0.02), Color("#1b1b1f"))
	_box(head, Vector3(0.04, 0.10, 0.12), Vector3(0.05, 0.05, 0.02), Color("#1b1b1f"))
	_box(head, Vector3(-0.02, 0.06, 0.12), Vector3(0.04, 0.05, 0.03),
		body_colour.darkened(0.12))
	_box(head, Vector3(-0.05, 0.02, 0.12), Vector3(0.10, 0.02, 0.02),
		body_colour.darkened(0.35))
	_add_accessory()

	var sleeve := 0.24 if rolled_sleeves else 0.40
	arm_l = _limb(Vector3(-0.21, 0.42, 0.0), cloth_colour, body_colour, 0.40, sleeve)
	arm_r = _limb(Vector3(0.21, 0.42, 0.0), cloth_colour, body_colour, 0.40, sleeve)
	torso.add_child(arm_l)
	torso.add_child(arm_r)

	leg_l = _limb(Vector3(-0.09, 0.0, 0.0), trouser, boot, 0.44, 0.30)
	leg_r = _limb(Vector3(0.09, 0.0, 0.0), trouser, boot, 0.44, 0.30)
	add_child(leg_l)
	add_child(leg_r)
	leg_l.position.y = 0.72
	leg_r.position.y = 0.72


## The one thing you actually recognise them by from a distance.
func _add_accessory() -> void:
	match accessory:
		"scarf":
			_box(head, Vector3(-0.145, 0.16, -0.135), Vector3(0.29, 0.13, 0.27),
				accent_colour)
			_box(head, Vector3(-0.05, 0.10, -0.16), Vector3(0.10, 0.12, 0.04),
				accent_colour.darkened(0.15))
		"cap":
			_box(head, Vector3(-0.145, 0.24, -0.135), Vector3(0.29, 0.07, 0.27),
				cloth_colour.darkened(0.35))
			# The peak, at the front, which is what makes it a cap and not a box.
			_box(head, Vector3(-0.11, 0.24, 0.13), Vector3(0.22, 0.03, 0.09),
				cloth_colour.darkened(0.45))
		"brim":
			_box(head, Vector3(-0.22, 0.23, -0.21), Vector3(0.44, 0.03, 0.44),
				hair_colour.darkened(0.15))
			_box(head, Vector3(-0.13, 0.24, -0.12), Vector3(0.26, 0.11, 0.24),
				hair_colour.darkened(0.3))
			_box(head, Vector3(-0.13, 0.29, -0.125), Vector3(0.26, 0.03, 0.25),
				accent_colour)


func _limb(at: Vector3, upper: Color, lower: Color, length: float,
		sleeve: float) -> Node3D:
	var n := Node3D.new()
	n.position = at
	# Upper covering (sleeve or trouser) hangs from the joint; what is left
	# below it is skin or boot. Rolling the sleeves up is a shorter covering.
	_box(n, Vector3(-0.06, -sleeve, -0.06), Vector3(0.12, sleeve, 0.12), upper)
	_box(n, Vector3(-0.055, -length, -0.055),
		Vector3(0.11, length - sleeve, 0.11), lower)
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
		arm_l.rotation.x = 1.35
		arm_r.rotation.x = 1.35


## Hammering, for the building state.
func work(delta: float) -> void:
	_phase += delta * 7.0
	arm_r.rotation.x = 1.1 - sin(_phase) * 0.8
	arm_l.rotation.x = 0.5
	torso.rotation.x = -0.12 - sin(_phase) * 0.05
