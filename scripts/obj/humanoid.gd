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

## The kit they hold, and only while they are using it. A builder carrying a
## hammer through dinner is a builder who never puts anything down.
var _sheet: Node3D
var _tool: Node3D


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

	_build_kit()


## The two things they hold on a site. Both start hidden; the gesture that uses
## one turns it on for as long as it is being used.
func _build_kit() -> void:
	# The drawings, held open in both hands and tipped up to be read. Two rules
	# and a plan of a building is enough to say "these are the drawings" at the
	# distance anybody will ever see it from.
	_sheet = Node3D.new()
	_sheet.position = Vector3(0.0, 0.26, 0.26)
	_sheet.rotation.x = -0.62
	_sheet.visible = false
	torso.add_child(_sheet)
	_box(_sheet, Vector3(-0.20, -0.14, 0.0), Vector3(0.40, 0.28, 0.012),
		Color("#c3d2e4"))
	# Everything drawn on it stands proud of the sheet rather than sitting flush
	# with it: two coplanar faces is a flicker, and this one would be held up in
	# front of the camera.
	var ink := Color("#22406e")
	_box(_sheet, Vector3(-0.17, 0.075, -0.006), Vector3(0.34, 0.022, 0.012), ink)
	_box(_sheet, Vector3(-0.17, -0.115, -0.006), Vector3(0.34, 0.022, 0.012), ink)
	# A plan of a building on it, which is the bit that says what kind of paper
	# this is rather than just that there is some.
	_box(_sheet, Vector3(-0.12, -0.07, -0.006), Vector3(0.022, 0.13, 0.012), ink)
	_box(_sheet, Vector3(0.10, -0.07, -0.006), Vector3(0.022, 0.13, 0.012), ink)
	_box(_sheet, Vector3(-0.12, -0.07, -0.006), Vector3(0.24, 0.022, 0.012), ink)
	_box(_sheet, Vector3(-0.12, 0.038, -0.006), Vector3(0.24, 0.022, 0.012), ink)

	# The hammer, in the right hand — the limb hangs to y = -0.40, so this
	# hangs on past it and the head is out where a swing can be read.
	_tool = Node3D.new()
	_tool.position = Vector3(0.0, -0.40, 0.02)
	_tool.visible = false
	arm_r.add_child(_tool)
	_box(_tool, Vector3(-0.022, -0.24, -0.022), Vector3(0.044, 0.32, 0.044),
		Color("#6d4a2c"))
	_box(_tool, Vector3(-0.052, -0.30, -0.046), Vector3(0.104, 0.075, 0.092),
		Color("#474c55"))
	_box(_tool, Vector3(0.052, -0.285, -0.030), Vector3(0.030, 0.045, 0.060),
		Color("#5b616b"))


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
	# Whatever a work gesture was holding has to be let go of here, or a worker
	# who was bent over a course walks to the next corner still bent over it,
	# with the trowel still in his hand.
	_drop_kit(delta * 8.0)
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


## What somebody actually does on a building site.
##
## A site is not one motion repeated for a day. Watch a real one and the same
## few things come round: somebody has the drawings open and is looking from
## the page to the wall and back; somebody is sighting along a line with an arm
## out; somebody is bent over a course with a trowel; somebody is nailing;
## somebody has stopped, put their hands on their hips and is looking at what
## they have done. The reading and the standing back are not idling — they are
## most of the job, and they are what makes the hammering look like work rather
## than a loop.
##
## Every pose here has to be legible in silhouette from across the plaza, since
## that is the only distance anyone will see it from. That rules out anything
## in the wrists and puts the whole burden on the shoulders, the spine and
## whether there is something in their hands.
const GESTURES: Array[String] = ["plan", "hammer", "saw", "lay", "lift",
	"measure", "survey"]

## How fast each one cycles. Nailing is quick, lifting a block is not, and
## reading a page barely moves at all.
const GESTURE_RATE := {
	"plan": 1.1, "hammer": 7.0, "saw": 5.2, "lay": 3.4,
	"lift": 1.9, "measure": 1.3, "survey": 0.8,
}


## Puts a gesture back to the start of its cycle. Only the capture harness
## uses it, so a screenshot lands at the same point of every swing.
func reset_cycle() -> void:
	_phase = 0.0


func work(delta: float, gesture: String = "hammer") -> void:
	_phase += delta * float(GESTURE_RATE.get(gesture, 4.0))
	_settle(delta)
	match gesture:
		"plan":
			_pose_plan(delta)
		"saw":
			_pose_saw()
		"lay":
			_pose_lay()
		"lift":
			_pose_lift()
		"measure":
			_pose_measure(delta)
		"survey":
			_pose_survey(delta)
		_:
			_pose_hammer()


## Everything the next pose is not going to drive goes back to rest first, so
## no gesture can leave an arm stuck out sideways when another one starts.
func _settle(delta: float) -> void:
	var k := delta * 8.0
	arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, k)
	head.rotation.x = lerpf(head.rotation.x, 0.0, k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, k)
	torso.position.y = lerpf(torso.position.y, 0.72, k)
	torso.rotation.y = lerpf(torso.rotation.y, 0.0, k)
	torso.rotation.z = lerpf(torso.rotation.z, 0.0, k)
	if _sheet != null:
		_sheet.visible = false
	if _tool != null:
		_tool.visible = false


## The channels only a work gesture ever touches, released back to standing.
func _drop_kit(k: float) -> void:
	arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, k)
	head.rotation.x = lerpf(head.rotation.x, 0.0, k)
	torso.rotation.x = lerpf(torso.rotation.x, 0.0, k)
	torso.rotation.y = lerpf(torso.rotation.y, 0.0, k)
	if _sheet != null:
		_sheet.visible = false
	if _tool != null:
		_tool.visible = false


## Reading the drawings, and looking up at the thing they are drawings of.
##
## The glance up is the whole gesture. Held flat it is a person holding a card;
## the moment the head comes up to check the wall and goes back down to the
## page, it is somebody working out whether it is right.
func _pose_plan(delta: float) -> void:
	_sheet.visible = true
	arm_l.rotation.x = 1.34
	arm_r.rotation.x = 1.34
	arm_l.rotation.z = 0.26
	arm_r.rotation.z = -0.26
	torso.rotation.x = 0.12
	var up := sin(_phase) > 0.62
	head.rotation.x = lerpf(head.rotation.x, -0.20 if up else 0.44, delta * 5.0)
	torso.rotation.y = lerpf(torso.rotation.y, 0.24 if up else 0.0, delta * 3.0)


## Nailing. The arm has to go right up past the shoulder and come down hard —
## a swing that stays below horizontal reads as somebody waving, and from most
## angles it does not read as anything at all.
func _pose_hammer() -> void:
	_tool.visible = true
	var swing := sin(_phase)
	arm_r.rotation.x = 1.55 + swing * 0.74
	arm_r.rotation.z = -0.12
	arm_l.rotation.x = 0.62
	arm_l.rotation.z = 0.22
	# Leaning into the strike, straightening on the backswing.
	torso.rotation.x = -0.05 - maxf(-swing, 0.0) * 0.02 + maxf(swing, 0.0) * 0.14


## Sawing: both hands on it, a long push and a short recovery, the whole body
## rocking with the stroke rather than the arm working alone.
func _pose_saw() -> void:
	var stroke := sin(_phase)
	arm_r.rotation.x = 1.06 + stroke * 0.44
	arm_l.rotation.x = 0.92 + stroke * 0.32
	arm_l.rotation.z = 0.24
	arm_r.rotation.z = -0.08
	torso.rotation.x = 0.24 + stroke * 0.07
	torso.position.y = 0.70


## Laying a course. Bent over the work with the trowel sweeping — and bent
## rather than kneeling, because the legs are single rigid limbs and a real
## kneel would lift the boots off the ground.
func _pose_lay() -> void:
	_tool.visible = true
	var sweep := sin(_phase)
	torso.position.y = 0.62
	torso.rotation.x = 0.60
	arm_r.rotation.x = 1.02 + sweep * 0.32
	arm_r.rotation.z = -0.22 - sweep * 0.34
	arm_l.rotation.x = 0.88
	arm_l.rotation.z = 0.18
	head.rotation.x = 0.26


## Lifting a block onto the course: down, take the weight, up, place it. Slow,
## because weight is slow, and the hold at the top is most of what sells it.
func _pose_lift() -> void:
	var down := maxf(-sin(_phase), 0.0)
	torso.rotation.x = 0.18 + down * 0.58
	torso.position.y = 0.72 - down * 0.11
	arm_l.rotation.x = 1.38 - down * 0.34
	arm_r.rotation.x = 1.38 - down * 0.34
	arm_l.rotation.z = 0.14
	arm_r.rotation.z = -0.14
	head.rotation.x = down * 0.34


## Sighting a line. One arm straight out along the wall, the other back at the
## corner, and the head tracking slowly down the length of it.
func _pose_measure(delta: float) -> void:
	arm_r.rotation.x = 1.54
	arm_r.rotation.z = -0.12
	arm_l.rotation.x = 0.90
	arm_l.rotation.z = 0.46
	torso.rotation.x = 0.04
	torso.rotation.y = lerpf(torso.rotation.y, sin(_phase * 0.7) * 0.34,
		delta * 3.0)
	head.rotation.x = -0.08


## Standing back to look at it: a hand up to shade the eyes, weight back, chin
## up, turning slowly along the length of the thing. Twenty times a day on any
## real site, and the pose that makes the others read as a person choosing what
## to do next rather than an animation on a timer.
##
## The hand at the brow rather than on the hip, which is what this was first,
## because these arms are one rigid piece from shoulder to fingers: on the hip
## the hand ends up inside the torso and the whole pose disappears into the
## silhouette. Raised, it is unmistakable from across the plaza.
func _pose_survey(delta: float) -> void:
	arm_r.rotation.x = 2.36
	arm_r.rotation.z = -0.28
	arm_l.rotation.x = 0.22
	arm_l.rotation.z = -0.30
	torso.rotation.x = -0.17
	head.rotation.x = lerpf(head.rotation.x, -0.30, delta * 4.0)
	torso.rotation.y = lerpf(torso.rotation.y, sin(_phase) * 0.34, delta * 2.0)
