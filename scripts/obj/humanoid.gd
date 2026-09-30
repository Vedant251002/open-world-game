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

const REST_Y := 0.72

var _batch: BoxKit.Batch
var _phase := 0.0
var _t := 0.0
var _carrying := false

## The kit they hold, and only while they are using it. A builder carrying a
## hammer through dinner is a builder who never puts anything down.
var _sheet: Node3D
var _tool: Node3D


func _ready() -> void:
	_build()


## The palette the cast is handed is bright on purpose, so the three of them
## are told apart in a screenshot; on a person it is fancy dress. Pulled
## toward dyed cloth: less saturated, a little darker, and never pure.
static func _natural(c: Color, sat: float = 0.72, val: float = 0.92) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * sat, 0.0, 0.85), clampf(c.v * val, 0.05, 0.92))


func _build() -> void:
	_batch = BoxKit.Batch.new()
	# Everybody is one of a few dozen different people, and the same person
	# every time: the choices below come from what they were dressed in.
	var seed_i := int(hash(str(cloth_colour.to_rgba32()) + str(hair_colour.to_rgba32())
		+ str(body_colour.to_rgba32())))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i

	var cloth := _natural(cloth_colour)
	var accent := _natural(accent_colour, 0.65, 0.95)
	# Deep skin tones are lifted a touch: under a hat brim in shade a face
	# that dark loses its eyes, and eyes are the whole of a face at this size.
	var skin := body_colour.lightened(0.10) if body_colour.get_luminance() < 0.22 else body_colour
	var skin_dk := skin.darkened(0.16)
	var hair := hair_colour
	var boot := Color("#54392a").lerp(hair_colour, 0.1)
	var trouser := _natural(cloth_colour.darkened(0.15), 0.5, 0.85)
	var leather := Color("#5a3d27")
	var brass := Color("#b48a3c")
	var linen := Color("#d9d0bc")

	# What they wear over the shirt. The three principals keep the outfit that
	# says what they do; everybody else is dealt one.
	var outfit := "shirt"
	if long_coat:
		outfit = "coat"
	elif accessory == "scarf" and rolled_sleeves:
		outfit = "apron"
	elif accessory == "brim" and rolled_sleeves == false and hair_colour.get_luminance() < 0.15:
		outfit = "overalls"
	else:
		outfit = ["shirt", "vest", "apron", "overalls", "shirt"][rng.randi() % 5]
	var female := rolled_sleeves or (outfit != "coat" and rng.randf() < 0.45)
	var style := 1 if female else rng.randi() % 3     # hair: 0 crop, 1 long, 2 mop
	if female and rng.randf() < 0.4:
		style = 3                                     # a bun
	var bearded := long_coat and hair.get_luminance() > 0.35
	if not female and not bearded and rng.randf() < 0.2:
		bearded = true
	var shirt := cloth
	if outfit == "apron" or outfit == "overalls" or outfit == "vest":
		shirt = cloth.lerp(linen, 0.35)
	if outfit == "overalls":
		trouser = Color("#5b6d88") if accessory == "brim" else _natural(cloth_colour.darkened(0.15), 0.4, 0.85)

	# ------------------------------------------------------------- torso
	torso = Node3D.new()
	torso.position.y = REST_Y
	add_child(torso)
	# The shirt, and a slightly wider shoulder yoke: it is the shoulders that
	# make a block into somebody with somewhere to carry a load.
	_box(torso, Vector3(-0.17, 0.0, -0.10), Vector3(0.34, 0.46, 0.20), shirt)
	_box(torso, Vector3(-0.175, 0.36, -0.105), Vector3(0.35, 0.09, 0.21), shirt.darkened(0.10))
	# Neck, and a shirt collar around it.
	_box(torso, Vector3(-0.05, 0.44, -0.05), Vector3(0.10, 0.10, 0.10), skin_dk, 0.6)
	_box(torso, Vector3(-0.085, 0.41, -0.09), Vector3(0.17, 0.045, 0.18), linen.darkened(0.05))
	_box(torso, Vector3(-0.045, 0.34, 0.095), Vector3(0.09, 0.09, 0.012), skin_dk, 0.6)
	# Belt with a buckle, on everyone; the rest is on top of it.
	var belt_y := 0.04
	_box(torso, Vector3(-0.175, belt_y, -0.105), Vector3(0.35, 0.05, 0.21), leather, 0.55)
	_box(torso, Vector3(-0.025, belt_y - 0.003, 0.103), Vector3(0.05, 0.056, 0.012), brass, 0.35)

	match outfit:
		"coat":
			var coat := cloth.darkened(0.04)
			# Front panels either side of an open shirt, a skirt to the thigh,
			# lapels, buttons: a coat has a great many small edges.
			_box(torso, Vector3(-0.18, 0.02, 0.085), Vector3(0.14, 0.40, 0.03), coat)
			_box(torso, Vector3(0.04, 0.02, 0.085), Vector3(0.14, 0.40, 0.03), coat)
			_box(torso, Vector3(-0.18, -0.20, -0.11), Vector3(0.36, 0.22, 0.22), coat.darkened(0.06))
			_box(torso, Vector3(-0.185, -0.22, -0.115), Vector3(0.37, 0.03, 0.23), coat.darkened(0.25))
			_box(torso, Vector3(-0.03, 0.02, 0.09), Vector3(0.06, 0.34, 0.02), linen.darkened(0.08))
			_box(torso, Vector3(-0.115, 0.22, 0.10), Vector3(0.05, 0.20, 0.02), coat.lightened(0.10))
			_box(torso, Vector3(0.065, 0.22, 0.10), Vector3(0.05, 0.20, 0.02), coat.lightened(0.10))
			for i in 3:
				_box(torso, Vector3(-0.145, 0.09 + i * 0.09, 0.112), Vector3(0.022, 0.022, 0.012),
					brass, 0.35)
			# A hammer through the belt and a pouch, the builder's whole trade.
			_box(torso, Vector3(0.12, -0.08, 0.02), Vector3(0.05, 0.13, 0.07), leather.darkened(0.1), 0.55)
			_box(torso, Vector3(0.135, -0.16, 0.035), Vector3(0.022, 0.14, 0.022), Color("#7a5a36"))
			_box(torso, Vector3(-0.19, -0.06, 0.02), Vector3(0.03, 0.10, 0.07), leather, 0.55)
		"apron":
			var apr := linen.lerp(accent, 0.12)
			_box(torso, Vector3(-0.115, 0.20, 0.10), Vector3(0.23, 0.20, 0.014), apr)
			_box(torso, Vector3(-0.15, -0.16, 0.10), Vector3(0.30, 0.36, 0.014), apr)
			_box(torso, Vector3(-0.155, -0.16, 0.100), Vector3(0.31, 0.03, 0.02), accent, 0.9)
			_box(torso, Vector3(-0.095, -0.06, 0.112), Vector3(0.19, 0.10, 0.01), apr.darkened(0.10))
			_box(torso, Vector3(-0.115, 0.38, 0.10), Vector3(0.03, 0.10, 0.014), leather, 0.55)
			_box(torso, Vector3(0.085, 0.38, 0.10), Vector3(0.03, 0.10, 0.014), leather, 0.55)
			_box(torso, Vector3(-0.175, 0.39, -0.105), Vector3(0.35, 0.03, 0.03), leather, 0.55)
			_box(torso, Vector3(0.10, -0.03, -0.11), Vector3(0.05, 0.10, 0.012), leather, 0.55)
		"overalls":
			var den := trouser
			_box(torso, Vector3(-0.13, 0.03, 0.098), Vector3(0.26, 0.29, 0.016), den, 0.9)
			_box(torso, Vector3(-0.09, 0.15, 0.108), Vector3(0.18, 0.10, 0.012), den.darkened(0.12))
			_box(torso, Vector3(-0.12, 0.30, 0.098), Vector3(0.04, 0.10, 0.016), den, 0.9)
			_box(torso, Vector3(0.08, 0.30, 0.098), Vector3(0.04, 0.10, 0.016), den, 0.9)
			_box(torso, Vector3(-0.115, 0.31, -0.108), Vector3(0.04, 0.10, 0.016), den, 0.9)
			_box(torso, Vector3(0.075, 0.31, -0.108), Vector3(0.04, 0.10, 0.016), den, 0.9)
			_box(torso, Vector3(-0.13, 0.03, -0.108), Vector3(0.26, 0.11, 0.016), den, 0.9)
			_box(torso, Vector3(-0.112, 0.31, 0.106), Vector3(0.025, 0.025, 0.012), brass, 0.35)
			_box(torso, Vector3(0.088, 0.31, 0.106), Vector3(0.025, 0.025, 0.012), brass, 0.35)
		"vest":
			var vst := accent.darkened(0.15)
			_box(torso, Vector3(-0.175, 0.06, 0.085), Vector3(0.13, 0.34, 0.03), vst)
			_box(torso, Vector3(0.045, 0.06, 0.085), Vector3(0.13, 0.34, 0.03), vst)
			_box(torso, Vector3(-0.175, 0.06, -0.11), Vector3(0.35, 0.34, 0.03), vst)
			for i in 3:
				_box(torso, Vector3(-0.012, 0.10 + i * 0.09, 0.115), Vector3(0.024, 0.024, 0.01), brass, 0.35)
		_:
			# A plain shirt gets a pouch and a neckerchief instead.
			_box(torso, Vector3(0.09, -0.04, 0.05), Vector3(0.10, 0.10, 0.07), leather.lightened(0.05), 0.55)
			_box(torso, Vector3(-0.09, 0.33, 0.08), Vector3(0.18, 0.06, 0.03), accent)
			_box(torso, Vector3(-0.03, 0.26, 0.09), Vector3(0.06, 0.08, 0.02), accent.darkened(0.12))

	# -------------------------------------------------------------- head
	head = Node3D.new()
	head.position.y = 0.50
	torso.add_child(head)
	_box(head, Vector3(-0.14, 0.0, -0.13), Vector3(0.28, 0.28, 0.26), skin, 0.6)
	# Ears, and a jaw a touch narrower than the cranium.
	_box(head, Vector3(-0.158, 0.08, -0.03), Vector3(0.02, 0.08, 0.06), skin_dk, 0.6)
	_box(head, Vector3(0.138, 0.08, -0.03), Vector3(0.02, 0.08, 0.06), skin_dk, 0.6)
	# Eyes: white, iris, a lid line above and a brow over that. At 0.05 m a
	# face is a handful of boxes; it is enough to make them look at you.
	var brow := hair.lerp(Color.BLACK, 0.25)
	var iris := Color("#2b2119") if body_colour.get_luminance() < 0.5 else Color("#3d5a78")
	for sx in [-1.0, 1.0]:
		var x0: float = -0.10 if sx < 0.0 else 0.04
		_box(head, Vector3(x0, 0.125, 0.128), Vector3(0.06, 0.05, 0.010), Color("#efeae0"), 0.35)
		_box(head, Vector3(x0 + (0.03 if sx < 0.0 else 0.0), 0.125, 0.135),
			Vector3(0.03, 0.05, 0.008), iris, 0.3)
		_box(head, Vector3(x0 + (0.038 if sx < 0.0 else 0.012), 0.132, 0.140),
			Vector3(0.014, 0.028, 0.006), Color("#0c0b0b"), 0.3)
		_box(head, Vector3(x0 - 0.005, 0.178, 0.128), Vector3(0.07, 0.014, 0.012), skin_dk.darkened(0.1), 0.6)
		_box(head, Vector3(x0 - 0.008, 0.198, 0.126), Vector3(0.076, 0.022, 0.014), brow)
		# Cheeks, with a little colour in them.
		_box(head, Vector3(x0 - 0.01 if sx < 0.0 else x0 + 0.02, 0.055, 0.128),
			Vector3(0.05, 0.035, 0.006), skin.lerp(Color("#d9756a"), 0.14), 0.6)
	# Nose, then the mouth: a line with the corners lifted.
	_box(head, Vector3(-0.022, 0.07, 0.128), Vector3(0.044, 0.066, 0.034), skin.lightened(0.05), 0.55)
	_box(head, Vector3(-0.022, 0.066, 0.146), Vector3(0.044, 0.02, 0.012), skin.darkened(0.22), 0.55)
	var lip := skin.lerp(Color("#9c4a44"), 0.55)
	_box(head, Vector3(-0.045, 0.028, 0.128), Vector3(0.09, 0.016, 0.010), lip, 0.5)
	_box(head, Vector3(-0.058, 0.038, 0.128), Vector3(0.016, 0.014, 0.010), lip, 0.5)
	_box(head, Vector3(0.042, 0.038, 0.128), Vector3(0.016, 0.014, 0.010), lip, 0.5)
	if bearded:
		_box(head, Vector3(-0.115, -0.03, 0.09), Vector3(0.23, 0.07, 0.05), hair, 0.95)
		_box(head, Vector3(-0.14, 0.02, 0.02), Vector3(0.028, 0.10, 0.10), hair, 0.95)
		_box(head, Vector3(0.112, 0.02, 0.02), Vector3(0.028, 0.10, 0.10), hair, 0.95)
		_box(head, Vector3(-0.07, 0.048, 0.132), Vector3(0.14, 0.024, 0.02), hair, 0.95)
		_box(head, Vector3(-0.04, 0.008, 0.132), Vector3(0.08, 0.036, 0.02), hair, 0.95)

	# Hair, by style: a skull-cap of it always, and then what hangs from it.
	_box(head, Vector3(-0.15, 0.20, -0.14), Vector3(0.30, 0.10, 0.28), hair, 0.9)
	_box(head, Vector3(-0.15, 0.06, -0.14), Vector3(0.30, 0.16, 0.05), hair, 0.9)
	_box(head, Vector3(-0.152, 0.14, -0.10), Vector3(0.026, 0.10, 0.16), hair, 0.9)
	_box(head, Vector3(0.126, 0.14, -0.10), Vector3(0.026, 0.10, 0.16), hair, 0.9)
	# The fringe: a swept edge across the forehead rather than a ruler line.
	_box(head, Vector3(-0.15, 0.225, 0.10), Vector3(0.30, 0.05, 0.05), hair, 0.9)
	_box(head, Vector3(-0.15, 0.20, 0.11), Vector3(0.14, 0.03, 0.04), hair.lightened(0.04), 0.9)
	match style:
		0:
			pass
		1:
			# Long: down over the shoulders at the back and in two locks either side.
			_box(head, Vector3(-0.15, -0.16, -0.16), Vector3(0.30, 0.34, 0.06), hair, 0.9)
			_box(head, Vector3(-0.17, -0.04, -0.13), Vector3(0.03, 0.16, 0.20), hair, 0.9)
			_box(head, Vector3(0.14, -0.04, -0.13), Vector3(0.03, 0.16, 0.20), hair, 0.9)
		2:
			_box(head, Vector3(-0.16, 0.18, -0.15), Vector3(0.32, 0.06, 0.30), hair.lightened(0.05), 0.9)
			_box(head, Vector3(-0.09, 0.26, 0.02), Vector3(0.18, 0.05, 0.14), hair, 0.9)
		3:
			_box(head, Vector3(-0.07, 0.24, -0.20), Vector3(0.14, 0.12, 0.10), hair, 0.9)
			_box(head, Vector3(-0.08, 0.10, -0.16), Vector3(0.16, 0.12, 0.04), hair, 0.9)
	_add_accessory(hair, cloth, accent, leather)

	# -------------------------------------------------------------- arms
	var sleeve := 0.24 if rolled_sleeves else 0.36
	var cuff := shirt.lightened(0.06) if rolled_sleeves else cloth.darkened(0.2)
	arm_l = _arm(Vector3(-0.225, 0.42, 0.0), cloth if outfit != "coat" else cloth.darkened(0.04),
		skin, cuff, sleeve)
	arm_r = _arm(Vector3(0.225, 0.42, 0.0), cloth if outfit != "coat" else cloth.darkened(0.04),
		skin, cuff, sleeve)
	torso.add_child(arm_l)
	torso.add_child(arm_r)

	# -------------------------------------------------------------- legs
	leg_l = _leg(Vector3(-0.085, REST_Y, 0.0), trouser, boot)
	leg_r = _leg(Vector3(0.085, REST_Y, 0.0), trouser, boot)
	add_child(leg_l)
	add_child(leg_r)

	_build_kit()
	_batch.flush()
	_batch = null


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

	# The hammer, in the right hand — the limb hangs to y = -0.42, so this
	# hangs on past it and the head is out where a swing can be read.
	_tool = Node3D.new()
	_tool.position = Vector3(0.0, -0.40, 0.02)
	_tool.visible = false
	arm_r.add_child(_tool)
	_box(_tool, Vector3(-0.022, -0.24, -0.022), Vector3(0.044, 0.32, 0.044),
		Color("#6d4a2c"))
	_box(_tool, Vector3(-0.052, -0.30, -0.046), Vector3(0.104, 0.075, 0.092),
		Color("#474c55"), 0.4)
	_box(_tool, Vector3(0.052, -0.285, -0.030), Vector3(0.030, 0.045, 0.060),
		Color("#5b616b"), 0.4)


## The one thing you actually recognise them by from a distance.
func _add_accessory(_hair: Color, cloth: Color, accent: Color, leather: Color) -> void:
	match accessory:
		"scarf":
			# A kerchief over the crown, knotted at the back with two tails.
			var k := accent
			_box(head, Vector3(-0.155, 0.235, -0.145), Vector3(0.31, 0.07, 0.29), k)
			_box(head, Vector3(-0.155, 0.19, -0.145), Vector3(0.31, 0.05, 0.03), k.darkened(0.1))
			_box(head, Vector3(-0.155, 0.19, 0.12), Vector3(0.31, 0.03, 0.03), k.darkened(0.1))
			_box(head, Vector3(-0.045, 0.14, -0.19), Vector3(0.09, 0.09, 0.05), k.darkened(0.12))
			_box(head, Vector3(-0.07, 0.06, -0.19), Vector3(0.04, 0.09, 0.03), k)
			_box(head, Vector3(0.03, 0.05, -0.19), Vector3(0.04, 0.10, 0.03), k)
		"cap":
			var c := cloth.darkened(0.32)
			_box(head, Vector3(-0.155, 0.235, -0.145), Vector3(0.31, 0.06, 0.29), c)
			_box(head, Vector3(-0.14, 0.29, -0.13), Vector3(0.28, 0.03, 0.26), c.lightened(0.05))
			_box(head, Vector3(-0.155, 0.20, -0.145), Vector3(0.31, 0.04, 0.29), c.darkened(0.1))
			# The peak, at the front, which is what makes it a cap and not a box.
			_box(head, Vector3(-0.115, 0.225, 0.13), Vector3(0.23, 0.025, 0.11), c.darkened(0.25), 0.6)
		"brim":
			var straw := Color("#c9aa66")
			_box(head, Vector3(-0.235, 0.235, -0.235), Vector3(0.47, 0.022, 0.47), straw, 0.95)
			_box(head, Vector3(-0.16, 0.255, -0.16), Vector3(0.32, 0.10, 0.31), straw.darkened(0.06), 0.95)
			_box(head, Vector3(-0.165, 0.255, -0.165), Vector3(0.33, 0.035, 0.32), leather.darkened(0.1), 0.6)
			_box(head, Vector3(-0.165, 0.29, -0.165), Vector3(0.33, 0.012, 0.32), straw.darkened(0.25), 0.95)


## A sleeve with a shoulder on it, a cuff, and a hand.
func _arm(at: Vector3, sleeve_c: Color, skin: Color, cuff: Color, sleeve: float) -> Node3D:
	var n := Node3D.new()
	n.position = at
	_box(n, Vector3(-0.058, -sleeve, -0.062), Vector3(0.116, sleeve + 0.04, 0.124), sleeve_c)
	# Skin from the end of the sleeve to the wrist, and a hand a little wider.
	_box(n, Vector3(-0.048, -0.36, -0.048), Vector3(0.096, 0.36 - sleeve + 0.005, 0.096), skin, 0.6)
	_box(n, Vector3(-0.062, -sleeve - 0.005, -0.066), Vector3(0.124, 0.04, 0.132), cuff)
	_box(n, Vector3(-0.052, -0.43, -0.056), Vector3(0.104, 0.08, 0.112), skin.lightened(0.02), 0.6)
	_box(n, Vector3(-0.012, -0.40, 0.05), Vector3(0.024, 0.04, 0.02), skin, 0.6)
	return n


## Trousers, a turned-up cuff, and a boot with a toe and a sole.
func _leg(at: Vector3, trouser: Color, boot: Color) -> Node3D:
	var n := Node3D.new()
	n.position = at
	_box(n, Vector3(-0.066, -0.32, -0.068), Vector3(0.132, 0.32, 0.136), trouser)
	_box(n, Vector3(-0.07, -0.335, -0.072), Vector3(0.14, 0.035, 0.144), trouser.darkened(0.15))
	_box(n, Vector3(-0.068, -0.44, -0.07), Vector3(0.136, 0.11, 0.14), boot, 0.55)
	_box(n, Vector3(-0.07, -0.44, 0.06), Vector3(0.14, 0.06, 0.09), boot.lightened(0.05), 0.55)
	_box(n, Vector3(-0.072, -0.44, -0.074), Vector3(0.144, 0.025, 0.21), boot.darkened(0.5), 0.7)
	return n


func _box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color,
		rough: float = 0.9) -> void:
	_batch.box(parent, origin, size, colour, rough)


## speed is metres per second; 0 stands still.
func animate(delta: float, speed: float, carrying: bool = false) -> void:
	_carrying = carrying
	_t += delta
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
		torso.position.y = REST_Y + absf(sin(_phase)) * 0.02
		torso.rotation.z = sin(_phase) * 0.03
		# Shoulders counter-rotate against the hips, the head holds level.
		torso.rotation.y = -sin(_phase) * 0.07
		head.rotation.y = sin(_phase) * 0.05
	else:
		_phase = 0.0
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 9.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 9.0)
		# Breathing: the chest rises a few millimetres, the arms hang a
		# little looser on the out-breath, the head drifts.
		var br := sin(_t * 1.9 + float(get_instance_id() % 7))
		torso.position.y = lerpf(torso.position.y, REST_Y + br * 0.004, delta * 9.0)
		torso.rotation.z = lerpf(torso.rotation.z, 0.0, delta * 9.0)
		head.rotation.y = lerpf(head.rotation.y, sin(_t * 0.37 + float(get_instance_id() % 5)) * 0.18, delta * 2.0)
		if not carrying:
			arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, delta * 9.0)
			arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, delta * 9.0)
			arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.03 + br * 0.012, delta * 9.0)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, -0.03 - br * 0.012, delta * 9.0)

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
	torso.position.y = lerpf(torso.position.y, REST_Y, k)
	head.rotation.y = lerpf(head.rotation.y, 0.0, k)
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
