extends RefCounted
class_name CreatureKit
## Every creature in the game, as measurements and colours.
##
## Three body plans — a quadruped, a bird and a fish — and a table of species
## that fills each one in. The plan does the geometry; the species says how
## long the neck is, which way it points, what colour the belly is and whether
## there are horns. That split is what lets twenty animals share a few hundred
## lines instead of twenty copies of a builder that differ in numbers.
##
## Everything is in metres and taken from the real animal: a Holstein cow is
## about 1.45 m at the shoulder and 2.4 m nose to rump, a red fox is 0.4 m tall
## with a tail nearly as long as its body, a carp is a deep-bodied half metre.
## Proportion is most of what makes a box read as a particular animal — the
## colour confirms it, and one or two features (a comb, antlers, a snout disc)
## settle it. Get the proportions wrong and no amount of paint helps.
##
## Coordinates: +Z is the front, Y is up, the origin is on the ground between
## the feet (for fish, at the centre of the body). Every animated part is a
## Node3D pivot, returned by name, so the movement code can swing a leg or flap
## a wing without knowing what it is attached to.

# ------------------------------------------------------------------ colours
# Named once, because the same brown is a cow's flank and a sparrow's back.
const C_INK := Color("#15140f")
const C_HOOF := Color("#2b2621")
const C_PINK := Color("#d9a3a0")
const C_CREAM := Color("#efe9dc")
const C_BEAK_Y := Color("#e0a02a")


## kind -> species. "plan" picks the builder; "move" picks the behaviour.
const SPECIES := {
	# ---------------------------------------------------------- livestock
	"hen": {
		"plan": "bird", "move": "walk", "wild": false,
		"body": Vector3(0.24, 0.24, 0.36), "stand": 0.20, "head": 0.13,
		"beak": 0.06, "tail_up": true, "wingspan": 0.0, "legs": 0.16,
		"c_body": Color("#e8e4dc"), "c_head": Color("#e8e4dc"),
		"c_wing": Color("#d8d2c4"), "c_belly": Color("#efe9dc"),
		"c_beak": C_BEAK_Y, "c_leg": Color("#d8973a"),
		"features": ["comb", "wattle"],
		"speed": 1.5, "flee": 3.2, "shy": 2.6, "fall": 2.2,
		"gives": "egg", "every": 9.0,
	},
	"rooster": {
		"plan": "bird", "move": "walk", "wild": false,
		"body": Vector3(0.27, 0.28, 0.42), "stand": 0.26, "head": 0.14,
		"beak": 0.06, "tail_up": true, "wingspan": 0.0, "legs": 0.20,
		"c_body": Color("#8f3d1c"), "c_head": Color("#c8352c"),
		"c_wing": Color("#5e2a14"), "c_belly": Color("#2f2a25"),
		"c_beak": C_BEAK_Y, "c_leg": Color("#d8973a"),
		"c_tail": Color("#1e3b2a"),
		"features": ["comb", "wattle", "sickle_tail"],
		"speed": 1.6, "flee": 3.4, "shy": 2.4, "fall": 2.2,
		"gives": "", "every": 0.0,
	},
	"sheep": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.3, "H": 0.85, "W": 0.50, "neck": 0.28, "neck_up": 0.25,
		"head": Vector3(0.20, 0.24, 0.30), "muzzle": Vector3(0.14, 0.13, 0.12),
		"ears": "side", "tail": 0.16, "tail_up": false, "leg": 0.075,
		"c_body": Color("#e6e2d6"), "c_belly": Color("#d9d3c4"),
		"c_head": Color("#2f2b26"), "c_muzzle": Color("#3b3630"),
		"c_leg": Color("#3a342c"), "c_hoof": C_HOOF,
		"features": ["fleece"],
		"speed": 1.1, "flee": 2.4, "shy": 2.2, "fall": 22.0,
		"gives": "wool", "every": 26.0,
	},
	"cow": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 2.4, "H": 1.45, "W": 0.64, "neck": 0.50, "neck_up": 0.15,
		"head": Vector3(0.28, 0.32, 0.46), "muzzle": Vector3(0.22, 0.20, 0.18),
		"ears": "side", "tail": 0.85, "tail_up": false, "leg": 0.095,
		"c_body": Color("#1d1b19"), "c_belly": Color("#1d1b19"),
		"c_head": Color("#1d1b19"), "c_muzzle": Color("#c99a86"),
		"c_leg": Color("#1d1b19"), "c_hoof": C_HOOF,
		"c_patch": Color("#eeeae2"),
		"features": ["holstein", "horns_short", "udder"],
		"speed": 1.0, "flee": 2.0, "shy": 2.0, "fall": 22.0,
		"gives": "milk", "every": 20.0,
	},
	"goat": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.2, "H": 0.80, "W": 0.38, "neck": 0.34, "neck_up": 0.55,
		"head": Vector3(0.17, 0.22, 0.28), "muzzle": Vector3(0.12, 0.12, 0.10),
		"ears": "side", "tail": 0.10, "tail_up": true, "leg": 0.06,
		"c_body": Color("#8a7f70"), "c_belly": Color("#c9bfae"),
		"c_head": Color("#8a7f70"), "c_muzzle": Color("#c9bfae"),
		"c_leg": Color("#6c6357"), "c_hoof": C_HOOF,
		"features": ["horns_back", "beard"],
		"speed": 1.4, "flee": 3.0, "shy": 2.2, "fall": 22.0,
		"gives": "milk", "every": 24.0,
	},
	"pig": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.6, "H": 0.85, "W": 0.62, "neck": 0.12, "neck_up": -0.15,
		"head": Vector3(0.30, 0.30, 0.34), "muzzle": Vector3(0.16, 0.14, 0.14),
		"ears": "floppy", "tail": 0.0, "tail_up": true, "leg": 0.075,
		"c_body": Color("#e4b0a6"), "c_belly": Color("#efc7bf"),
		"c_head": Color("#e4b0a6"), "c_muzzle": Color("#d98f86"),
		"c_leg": Color("#d9a39a"), "c_hoof": Color("#8c6a66"),
		"features": ["snout_disc", "curly_tail"],
		"speed": 1.2, "flee": 2.6, "shy": 2.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"horse": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 2.4, "H": 1.60, "W": 0.56, "neck": 0.85, "neck_up": 0.80,
		"head": Vector3(0.22, 0.30, 0.58), "muzzle": Vector3(0.16, 0.18, 0.16),
		"ears": "up", "tail": 0.95, "tail_up": false, "leg": 0.075,
		"c_body": Color("#7a4a2a"), "c_belly": Color("#7a4a2a"),
		"c_head": Color("#7a4a2a"), "c_muzzle": Color("#4a2d1a"),
		"c_leg": Color("#5b3620"), "c_hoof": C_HOOF,
		"c_mane": Color("#2e1d12"),
		"features": ["mane", "blaze", "long_tail"],
		"speed": 1.9, "flee": 4.5, "shy": 2.6, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- about town
	"dog": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 0.9, "H": 0.55, "W": 0.26, "neck": 0.20, "neck_up": 0.45,
		"head": Vector3(0.16, 0.16, 0.22), "muzzle": Vector3(0.09, 0.09, 0.12),
		"ears": "floppy", "tail": 0.36, "tail_up": true, "leg": 0.045,
		"c_body": Color("#1f1c1a"), "c_belly": Color("#eae6de"),
		"c_head": Color("#1f1c1a"), "c_muzzle": Color("#eae6de"),
		"c_leg": Color("#eae6de"), "c_hoof": Color("#1f1c1a"),
		"c_patch": Color("#eae6de"),
		"features": ["collie_blaze", "bushy_tail"],
		"speed": 2.4, "flee": 0.0, "shy": 0.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"cat": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 0.48, "H": 0.26, "W": 0.14, "neck": 0.08, "neck_up": 0.30,
		"head": Vector3(0.11, 0.10, 0.11), "muzzle": Vector3(0.05, 0.04, 0.04),
		"ears": "up", "tail": 0.30, "tail_up": true, "leg": 0.025,
		"c_body": Color("#8c7a62"), "c_belly": Color("#d9cdb8"),
		"c_head": Color("#8c7a62"), "c_muzzle": Color("#d9cdb8"),
		"c_leg": Color("#8c7a62"), "c_hoof": Color("#6f5f4b"),
		"c_patch": Color("#5a4b39"),
		"features": ["tabby"],
		"speed": 1.6, "flee": 3.5, "shy": 1.6, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- the wild
	"deer": {
		"plan": "quadruped", "move": "walk", "wild": true,
		"L": 1.7, "H": 1.05, "W": 0.34, "neck": 0.55, "neck_up": 0.95,
		"head": Vector3(0.16, 0.22, 0.36), "muzzle": Vector3(0.10, 0.11, 0.12),
		"ears": "up", "tail": 0.14, "tail_up": true, "leg": 0.045,
		"c_body": Color("#a3743f"), "c_belly": Color("#e6dcc8"),
		"c_head": Color("#a3743f"), "c_muzzle": Color("#8c6236"),
		"c_leg": Color("#8c6236"), "c_hoof": C_HOOF,
		"c_patch": Color("#eeeae0"),
		"features": ["antlers", "white_rump", "black_nose"],
		"speed": 1.6, "flee": 6.5, "shy": 9.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"rabbit": {
		"plan": "quadruped", "move": "hop", "wild": true,
		"L": 0.40, "H": 0.22, "W": 0.16, "neck": 0.05, "neck_up": 0.35,
		"head": Vector3(0.10, 0.10, 0.12), "muzzle": Vector3(0.05, 0.04, 0.04),
		"ears": "long", "tail": 0.0, "tail_up": true, "leg": 0.03,
		"c_body": Color("#8b7a66"), "c_belly": Color("#e2d9c9"),
		"c_head": Color("#8b7a66"), "c_muzzle": Color("#e2d9c9"),
		"c_leg": Color("#8b7a66"), "c_hoof": Color("#6f5f4d"),
		"features": ["puff_tail"],
		"speed": 2.2, "flee": 5.0, "shy": 6.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"fox": {
		"plan": "quadruped", "move": "walk", "wild": true,
		"L": 0.72, "H": 0.40, "W": 0.20, "neck": 0.16, "neck_up": 0.30,
		"head": Vector3(0.13, 0.13, 0.20), "muzzle": Vector3(0.07, 0.06, 0.09),
		"ears": "up", "tail": 0.42, "tail_up": false, "leg": 0.035,
		"c_body": Color("#c9601f"), "c_belly": Color("#efe6d8"),
		"c_head": Color("#c9601f"), "c_muzzle": Color("#efe6d8"),
		"c_leg": Color("#2a2421"), "c_hoof": Color("#2a2421"),
		"c_patch": Color("#efe6d8"),
		"features": ["bushy_tail", "white_tail_tip", "black_ear_tips", "black_nose"],
		"speed": 2.0, "flee": 6.0, "shy": 8.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- birds
	"crow": {
		"plan": "bird", "move": "fly", "wild": true,
		"body": Vector3(0.14, 0.14, 0.30), "stand": 0.09, "head": 0.10,
		"beak": 0.07, "tail_up": false, "wingspan": 0.95, "legs": 0.07,
		"c_body": Color("#17181c"), "c_head": Color("#17181c"),
		"c_wing": Color("#101114"), "c_belly": Color("#1d1e23"),
		"c_beak": Color("#17181c"), "c_leg": Color("#17181c"),
		"features": [],
		"cruise": 7.0, "altitude": Vector2(7.0, 14.0), "perch_time": Vector2(8.0, 30.0),
	},
	"sparrow": {
		"plan": "bird", "move": "fly", "wild": true,
		"body": Vector3(0.07, 0.07, 0.14), "stand": 0.04, "head": 0.05,
		"beak": 0.02, "tail_up": false, "wingspan": 0.24, "legs": 0.03,
		"c_body": Color("#7d5b3c"), "c_head": Color("#6b4d34"),
		"c_wing": Color("#5a3f28"), "c_belly": Color("#c8bfae"),
		"c_beak": Color("#3d3128"), "c_leg": Color("#8c7256"),
		"features": ["streaked_back"],
		"cruise": 6.0, "altitude": Vector2(3.0, 8.0), "perch_time": Vector2(5.0, 20.0),
	},
	"gull": {
		"plan": "bird", "move": "fly", "wild": true,
		"body": Vector3(0.16, 0.15, 0.40), "stand": 0.12, "head": 0.11,
		"beak": 0.08, "tail_up": false, "wingspan": 1.35, "legs": 0.09,
		"c_body": Color("#f2f1ee"), "c_head": Color("#f2f1ee"),
		"c_wing": Color("#a9adb3"), "c_belly": Color("#f7f6f3"),
		"c_beak": Color("#e8b62a"), "c_leg": Color("#e8b0a0"),
		"c_wingtip": Color("#1d1e22"),
		"features": ["black_wingtips"],
		"cruise": 8.5, "altitude": Vector2(9.0, 18.0), "perch_time": Vector2(6.0, 25.0),
	},
	"duck": {
		"plan": "bird", "move": "float", "wild": true,
		"body": Vector3(0.18, 0.16, 0.42), "stand": 0.10, "head": 0.11,
		"beak": 0.08, "tail_up": true, "wingspan": 0.80, "legs": 0.06,
		"c_body": Color("#8f8677"), "c_head": Color("#1f6b3a"),
		"c_wing": Color("#6f665a"), "c_belly": Color("#cfc7b6"),
		"c_beak": Color("#e0c040"), "c_leg": Color("#e07a30"),
		"c_chest": Color("#5a3323"),
		"features": ["neck_ring", "mallard_chest", "speculum"],
		"cruise": 1.0, "altitude": Vector2(0.0, 0.0), "perch_time": Vector2(4.0, 12.0),
	},
	"owl": {
		"plan": "bird", "move": "fly", "wild": true,
		"body": Vector3(0.18, 0.20, 0.30), "stand": 0.10, "head": 0.16,
		"beak": 0.03, "tail_up": false, "wingspan": 1.0, "legs": 0.05,
		"c_body": Color("#8a6b48"), "c_head": Color("#9c7d58"),
		"c_wing": Color("#6f5335"), "c_belly": Color("#d6c7ad"),
		"c_beak": Color("#3d3128"), "c_leg": Color("#8a6b48"),
		"features": ["face_disc", "big_eyes"],
		"cruise": 5.0, "altitude": Vector2(5.0, 10.0), "perch_time": Vector2(20.0, 60.0),
		"night_only": true,
	},
	# ---------------------------------------------------------- fish
	"carp": {
		"plan": "fish", "move": "swim", "wild": true,
		"length": 0.50, "depth": 0.18, "width": 0.09,
		"c_back": Color("#6e5a2a"), "c_belly": Color("#c9b478"),
		"c_fin": Color("#8f7433"), "c_tail": Color("#8f7433"),
		"features": ["scales"],
		"cruise": 0.9, "dart": 3.5, "jumps": false,
	},
	"trout": {
		"plan": "fish", "move": "swim", "wild": true,
		"length": 0.42, "depth": 0.11, "width": 0.06,
		"c_back": Color("#4e6a5a"), "c_belly": Color("#d9d6c8"),
		"c_fin": Color("#5e5a48"), "c_tail": Color("#5e5a48"),
		"c_stripe": Color("#c9807a"),
		"features": ["pink_stripe", "spots"],
		"cruise": 1.3, "dart": 4.5, "jumps": true,
	},
	"perch": {
		"plan": "fish", "move": "swim", "wild": true,
		"length": 0.30, "depth": 0.11, "width": 0.05,
		"c_back": Color("#5f7a2e"), "c_belly": Color("#d9cf8c"),
		"c_fin": Color("#c8552a"), "c_tail": Color("#c8552a"),
		"c_stripe": Color("#2f3a1a"),
		"features": ["bars", "spiny_dorsal"],
		"cruise": 0.8, "dart": 3.0, "jumps": false,
	},
}


static func has(kind: String) -> bool:
	return SPECIES.has(kind)


static func spec(kind: String) -> Dictionary:
	return SPECIES.get(kind, SPECIES["hen"])


## Builds the body under `root`. Returns the pivots that move:
##   torso, head, neck, legs (Array), tail, wings (Array), tailfin
## Whatever a plan does not have is simply absent from the dictionary.
static func build(kind: String, root: Node3D) -> Dictionary:
	var s := spec(kind)
	var out := {}
	match str(s["plan"]):
		"quadruped": out = _quadruped(s, root)
		"bird": out = _bird(s, kind, root)
		"fish": out = _fish(s, kind, root)
	_trim(root, s)
	return out


## What each box costs the renderer, cut to what the creature is worth.
##
## A sparrow is fourteen centimetres long. Drawn from sixty metres it is a
## pixel, and its shadow is nothing at all — but every one of its twenty boxes
## was still a draw call in the colour pass and another in each shadow split.
## So small creatures stop being drawn at a distance that matches their size,
## and birds and fish cast no shadow: a fish is under water and a bird is
## either tiny or in the sky, and a shadow on the ground from either is a
## thing nobody has ever noticed missing.
static func _trim(root: Node3D, s: Dictionary) -> void:
	var plan := str(s["plan"])
	var size := 1.0
	match plan:
		"quadruped": size = float(s["H"])
		"bird": size = (s["body"] as Vector3).z
		"fish": size = float(s["length"])
	# Roughly: visible out to a hundred times its height, capped both ways.
	var reach := clampf(size * 100.0, 35.0, 140.0)
	var shadow := plan == "quadruped" and size > 0.3
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color) -> MeshInstance3D:
	return BoxKit.add(parent, origin, size, colour)


# ------------------------------------------------------------- quadrupeds

## Barrel, neck, head, four legs and a tail, in the proportions given.
##
## The neck is the part that makes the animal. A horse's rises at fifty
## degrees; a pig hardly has one; a deer's is nearly vertical and it is why a
## deer looks alert and a cow does not. So the neck is a pivot rotated by the
## species' angle, and the head hangs off the end of it and levels itself back
## most of the way, which is what necks do.
static func _quadruped(s: Dictionary, root: Node3D) -> Dictionary:
	var L: float = s["L"]
	var H: float = s["H"]
	var W: float = s["W"]
	var body_h := H * 0.46                      ## depth of the barrel
	var belly_y := H - body_h                   ## underside of the barrel
	var body_l := L * 0.58                      ## barrel, without neck and head
	var c_body: Color = s["c_body"]
	var c_belly: Color = s["c_belly"]
	var feats: Array = s.get("features", [])
	var out := {}

	var torso := Node3D.new()
	torso.position.y = belly_y
	root.add_child(torso)
	out["torso"] = torso

	# The barrel: back and flank, with a lighter belly slab under it. Real
	# animals are darker on top and paler below almost without exception, and
	# a box painted one colour all round reads as a toy.
	_box(torso, Vector3(-W * 0.5, body_h * 0.28, -body_l * 0.5),
		Vector3(W, body_h * 0.72, body_l), c_body)
	_box(torso, Vector3(-W * 0.44, 0.0, -body_l * 0.46),
		Vector3(W * 0.88, body_h * 0.3, body_l * 0.92), c_belly)
	# Chest and rump: a little deeper at each end than the middle.
	_box(torso, Vector3(-W * 0.42, body_h * 0.1, body_l * 0.36),
		Vector3(W * 0.84, body_h * 0.75, body_l * 0.16), c_body)
	_box(torso, Vector3(-W * 0.40, body_h * 0.35, -body_l * 0.5 - 0.01),
		Vector3(W * 0.80, body_h * 0.62, body_l * 0.12), c_body)

	if "fleece" in feats:
		# Wool stands proud of the body and hides the neck.
		_box(torso, Vector3(-W * 0.58, body_h * 0.2, -body_l * 0.55),
			Vector3(W * 1.16, body_h * 0.95, body_l * 1.1), c_body.lightened(0.04))
	if "holstein" in feats:
		var p: Color = s["c_patch"]
		_box(torso, Vector3(-W * 0.5 - 0.01, body_h * 0.32, -body_l * 0.5),
			Vector3(W * 1.02, body_h * 0.6, body_l * 0.28), p)
		_box(torso, Vector3(-W * 0.5 - 0.01, body_h * 0.5, body_l * 0.02),
			Vector3(W * 1.02, body_h * 0.5, body_l * 0.22), p)
		_box(torso, Vector3(-W * 0.5 - 0.01, body_h * 0.28, body_l * 0.32),
			Vector3(W * 0.5, body_h * 0.4, body_l * 0.18), p)
	if "udder" in feats:
		_box(torso, Vector3(-W * 0.22, -body_h * 0.22, -body_l * 0.36),
			Vector3(W * 0.44, body_h * 0.24, body_l * 0.26), C_PINK)
	if "tabby" in feats:
		var p2: Color = s["c_patch"]
		for i in 4:
			_box(torso, Vector3(-W * 0.5 - 0.005, body_h * 0.55,
				-body_l * 0.4 + i * body_l * 0.22),
				Vector3(W * 1.01, body_h * 0.45, body_l * 0.06), p2)
	if "collie_blaze" in feats:
		var p3: Color = s["c_patch"]
		# A white collar and a white chest.
		_box(torso, Vector3(-W * 0.5 - 0.005, body_h * 0.2, body_l * 0.3),
			Vector3(W * 1.01, body_h * 0.8, body_l * 0.14), p3)
	if "white_rump" in feats:
		var p4: Color = s["c_patch"]
		_box(torso, Vector3(-W * 0.5 - 0.005, body_h * 0.15, -body_l * 0.5 - 0.02),
			Vector3(W * 1.01, body_h * 0.6, body_l * 0.1), p4)

	# --- neck and head ---
	var neck_len: float = s["neck"]
	var neck_up: float = s["neck_up"]
	var neck := Node3D.new()
	neck.position = Vector3(0.0, body_h * 0.8, body_l * 0.5 - 0.02)
	neck.rotation.x = -neck_up
	torso.add_child(neck)
	out["neck"] = neck
	var neck_w := W * 0.5
	_box(neck, Vector3(-neck_w * 0.5, -neck_w * 0.45, 0.0),
		Vector3(neck_w, neck_w * 0.9, neck_len + 0.02), c_body)
	if "mane" in feats:
		_box(neck, Vector3(-neck_w * 0.18, neck_w * 0.4, -0.04),
			Vector3(neck_w * 0.36, neck_w * 0.45, neck_len), s["c_mane"])

	var hd: Vector3 = s["head"]
	var head := Node3D.new()
	head.position = Vector3(0.0, 0.0, neck_len)
	head.rotation.x = neck_up * 0.75
	neck.add_child(head)
	out["head"] = head
	_box(head, Vector3(-hd.x * 0.5, -hd.y * 0.45, -hd.z * 0.15),
		Vector3(hd.x, hd.y, hd.z * 0.72), s["c_head"])
	var mz: Vector3 = s["muzzle"]
	_box(head, Vector3(-mz.x * 0.5, -hd.y * 0.42, hd.z * 0.55),
		Vector3(mz.x, mz.y, mz.z), s["c_muzzle"])
	var nose: Color = C_INK if "black_nose" in feats else (s["c_muzzle"] as Color).darkened(0.35)
	_box(head, Vector3(-mz.x * 0.22, -hd.y * 0.42 + mz.y * 0.55, hd.z * 0.55 + mz.z - 0.01),
		Vector3(mz.x * 0.44, mz.y * 0.32, 0.02), nose)
	# Eyes, on the sides where a prey animal keeps them.
	var ey := hd.x * 0.16
	_box(head, Vector3(-hd.x * 0.5 - 0.005, hd.y * 0.12, hd.z * 0.28),
		Vector3(0.01, ey, ey), C_INK)
	_box(head, Vector3(hd.x * 0.5 - 0.005, hd.y * 0.12, hd.z * 0.28),
		Vector3(0.01, ey, ey), C_INK)
	if "blaze" in feats:
		_box(head, Vector3(-hd.x * 0.12, -hd.y * 0.2, hd.z * 0.57),
			Vector3(hd.x * 0.24, hd.y * 0.6, 0.01), C_CREAM)
	if "beard" in feats:
		_box(head, Vector3(-mz.x * 0.2, -hd.y * 0.45 - hd.y * 0.35, hd.z * 0.45),
			Vector3(mz.x * 0.4, hd.y * 0.36, mz.z * 0.5), s["c_body"].darkened(0.2))
	if "snout_disc" in feats:
		_box(head, Vector3(-mz.x * 0.55, -hd.y * 0.45, hd.z * 0.55 + mz.z - 0.005),
			Vector3(mz.x * 1.1, mz.y * 1.1, 0.02), s["c_muzzle"].darkened(0.15))
	# Ears: the shape of the ear is a third of the silhouette.
	var e_w := hd.x * 0.28
	match str(s["ears"]):
		"up":
			for side in [-1.0, 1.0]:
				_box(head, Vector3(side * hd.x * 0.32 - e_w * 0.5, hd.y * 0.45, -hd.z * 0.05),
					Vector3(e_w, hd.y * 0.55, e_w * 0.6), s["c_head"])
				if "black_ear_tips" in feats:
					_box(head, Vector3(side * hd.x * 0.32 - e_w * 0.5, hd.y * 0.85, -hd.z * 0.05),
						Vector3(e_w, hd.y * 0.16, e_w * 0.6), C_INK)
		"long":
			for side in [-1.0, 1.0]:
				_box(head, Vector3(side * hd.x * 0.3 - e_w * 0.5, hd.y * 0.4, -hd.z * 0.1),
					Vector3(e_w, hd.y * 1.3, e_w * 0.5), s["c_head"])
		"floppy":
			# Hangs down beside the face from the top of the head.
			for side in [-1.0, 1.0]:
				var x0: float = side * hd.x * 0.5 + (0.0 if side > 0 else -e_w * 0.9)
				_box(head, Vector3(x0, -hd.y * 0.1, -hd.z * 0.02),
					Vector3(e_w * 0.9, hd.y * 0.5, e_w * 1.2), s["c_head"].darkened(0.08))
		_:
			# "side": sticks straight out, the way a cow's or a sheep's does.
			for side in [-1.0, 1.0]:
				var x0: float = side * hd.x * 0.5 + (0.0 if side > 0 else -e_w * 1.6)
				_box(head, Vector3(x0, hd.y * 0.05, hd.z * 0.05),
					Vector3(e_w * 1.6, hd.y * 0.2, e_w * 0.9), s["c_head"].darkened(0.08))

	if "horns_short" in feats:
		for side in [-1.0, 1.0]:
			_box(head, Vector3(side * hd.x * 0.36 - 0.02, hd.y * 0.45, hd.z * 0.05),
				Vector3(0.04, hd.y * 0.35, 0.04), C_CREAM)
	if "horns_back" in feats:
		for side in [-1.0, 1.0]:
			var horn := Node3D.new()
			horn.position = Vector3(side * hd.x * 0.28, hd.y * 0.45, -hd.z * 0.05)
			horn.rotation.x = 0.9
			head.add_child(horn)
			_box(horn, Vector3(-0.015, 0.0, -0.015), Vector3(0.03, hd.y * 0.8, 0.03),
				Color("#5c534a"))
	if "antlers" in feats:
		for side in [-1.0, 1.0]:
			var beam := Node3D.new()
			beam.position = Vector3(side * hd.x * 0.3, hd.y * 0.5, -hd.z * 0.05)
			beam.rotation.x = 0.35
			beam.rotation.z = -side * 0.35
			head.add_child(beam)
			var bone := Color("#b9a78a")
			_box(beam, Vector3(-0.015, 0.0, -0.015), Vector3(0.03, 0.42, 0.03), bone)
			# Tines off the main beam, forward and up.
			for i in 3:
				var tine := Node3D.new()
				tine.position = Vector3(0.0, 0.12 + i * 0.12, 0.0)
				tine.rotation.x = -0.9
				beam.add_child(tine)
				_box(tine, Vector3(-0.012, 0.0, -0.012), Vector3(0.024, 0.16 - i * 0.03, 0.024), bone)

	# --- legs: hip and shoulder pivots, two segments, a hoof or paw ---
	var leg_r: float = s["leg"]
	var legs: Array = []
	var lx := W * 0.5 - leg_r * 1.4
	var lz_f := body_l * 0.36
	var lz_b := -body_l * 0.36
	for i in 4:
		var n := Node3D.new()
		var x := lx * (1.0 if i % 2 == 0 else -1.0)
		var z := lz_f if i < 2 else lz_b
		n.position = Vector3(x, belly_y + body_h * 0.2, z)
		root.add_child(n)
		var leg_h := belly_y + body_h * 0.2
		# Upper leg, thicker; lower leg, thinner; hoof.
		_box(n, Vector3(-leg_r * 1.3, -leg_h * 0.5, -leg_r * 1.3),
			Vector3(leg_r * 2.6, leg_h * 0.52, leg_r * 2.6), s["c_leg"])
		_box(n, Vector3(-leg_r, -leg_h, -leg_r),
			Vector3(leg_r * 2.0, leg_h * 0.52, leg_r * 2.0), s["c_leg"])
		_box(n, Vector3(-leg_r * 1.1, -leg_h, -leg_r * 1.1),
			Vector3(leg_r * 2.2, leg_h * 0.12, leg_r * 2.2), s["c_hoof"])
		legs.append(n)
	out["legs"] = legs

	# --- tail ---
	var tail_len: float = s["tail"]
	var tail := Node3D.new()
	tail.position = Vector3(0.0, belly_y + body_h * 0.85, -body_l * 0.5)
	root.add_child(tail)
	out["tail"] = tail
	if tail_len > 0.0:
		var tw := leg_r * 1.2
		if "bushy_tail" in feats:
			tw = W * 0.42
		tail.rotation.x = (-0.9 if bool(s["tail_up"]) else 0.35) \
			if not ("bushy_tail" in feats and not bool(s["tail_up"])) else 0.55
		var c_tail: Color = s["c_body"] if "bushy_tail" in feats else s["c_leg"]
		if "long_tail" in feats:
			c_tail = s["c_mane"]
		_box(tail, Vector3(-tw * 0.5, -tw * 0.5, -tail_len), Vector3(tw, tw, tail_len), c_tail)
		if "white_tail_tip" in feats:
			_box(tail, Vector3(-tw * 0.52, -tw * 0.52, -tail_len - 0.01),
				Vector3(tw * 1.04, tw * 1.04, tail_len * 0.3), s["c_patch"])
	if "puff_tail" in feats:
		_box(tail, Vector3(-W * 0.18, -W * 0.12, -W * 0.28), Vector3(W * 0.36, W * 0.34, W * 0.3),
			C_CREAM)
	if "curly_tail" in feats:
		var q := leg_r * 0.6
		_box(tail, Vector3(-q, -q, -q * 3.0), Vector3(q * 2, q * 2, q * 3.0), s["c_body"])
		_box(tail, Vector3(-q, -q, -q * 4.5), Vector3(q * 2, q * 3.5, q * 2), s["c_body"])
		_box(tail, Vector3(-q, q * 1.5, -q * 3.0), Vector3(q * 2, q * 2, q * 2), s["c_body"])
	return out


# ------------------------------------------------------------------ birds

## Body, head, beak, tail, two wings on shoulder pivots, two legs. A hen and a
## crow are the same plan; the hen has no wingspan worth drawing and a comb.
static func _bird(s: Dictionary, kind: String, root: Node3D) -> Dictionary:
	var b: Vector3 = s["body"]
	var stand: float = s["stand"]
	var feats: Array = s.get("features", [])
	var out := {}

	var torso := Node3D.new()
	torso.position.y = stand
	root.add_child(torso)
	out["torso"] = torso
	# The body tapers: a deeper chest at the front, narrower behind.
	_box(torso, Vector3(-b.x * 0.5, 0.0, -b.z * 0.42), Vector3(b.x, b.y, b.z * 0.84), s["c_body"])
	_box(torso, Vector3(-b.x * 0.42, -b.y * 0.12, -b.z * 0.3),
		Vector3(b.x * 0.84, b.y * 0.3, b.z * 0.7), s["c_belly"])
	_box(torso, Vector3(-b.x * 0.36, b.y * 0.15, -b.z * 0.6),
		Vector3(b.x * 0.72, b.y * 0.6, b.z * 0.22), s["c_body"].darkened(0.06))
	if "mallard_chest" in feats:
		_box(torso, Vector3(-b.x * 0.5 - 0.005, b.y * 0.15, b.z * 0.18),
			Vector3(b.x * 1.01, b.y * 0.7, b.z * 0.26), s["c_chest"])
	if "streaked_back" in feats:
		for i in 3:
			_box(torso, Vector3(-b.x * 0.3 + i * b.x * 0.3 - 0.005, b.y + 0.001, -b.z * 0.35),
				Vector3(0.01, 0.004, b.z * 0.6), s["c_wing"].darkened(0.3))

	# Tail: flat, either cocked up (a hen, a duck) or trailing (everything that flies).
	var tail := Node3D.new()
	tail.position = Vector3(0.0, b.y * 0.55, -b.z * 0.42)
	tail.rotation.x = 0.9 if bool(s["tail_up"]) else -0.15
	torso.add_child(tail)
	out["tail"] = tail
	var tail_c: Color = s.get("c_tail", s["c_body"].darkened(0.1))
	if "sickle_tail" in feats:
		# A rooster's tail: long, curved over, green-black.
		_box(tail, Vector3(-b.x * 0.2, -0.01, -b.z * 0.55), Vector3(b.x * 0.4, 0.03, b.z * 0.55), tail_c)
		var arc := Node3D.new()
		arc.position = Vector3(0.0, 0.0, -b.z * 0.5)
		arc.rotation.x = 1.3
		tail.add_child(arc)
		_box(arc, Vector3(-b.x * 0.15, -0.01, -b.z * 0.4), Vector3(b.x * 0.3, 0.03, b.z * 0.4), tail_c)
	else:
		_box(tail, Vector3(-b.x * 0.35, -0.01, -b.z * 0.36), Vector3(b.x * 0.7, 0.02, b.z * 0.36), tail_c)

	# Head, on a short neck at the front.
	var hs: float = s["head"]
	var head := Node3D.new()
	head.position = Vector3(0.0, b.y * 0.75, b.z * 0.42)
	torso.add_child(head)
	out["head"] = head
	_box(head, Vector3(-hs * 0.5, -hs * 0.2, -hs * 0.2), Vector3(hs, hs, hs * 0.95), s["c_head"])
	if "neck_ring" in feats:
		_box(head, Vector3(-hs * 0.5 - 0.005, -hs * 0.25, -hs * 0.2),
			Vector3(hs * 1.01, hs * 0.1, hs * 0.9), C_CREAM)
	# Beak: a wedge that narrows toward the tip.
	var bk: float = s["beak"]
	_box(head, Vector3(-hs * 0.18, hs * 0.12, hs * 0.72),
		Vector3(hs * 0.36, hs * 0.22, bk), s["c_beak"])
	if bk > 0.05:
		_box(head, Vector3(-hs * 0.1, hs * 0.16, hs * 0.72 + bk - 0.01),
			Vector3(hs * 0.2, hs * 0.14, bk * 0.35), s["c_beak"].darkened(0.1))
	# Eyes
	var eye := hs * 0.2 if "big_eyes" in feats else hs * 0.13
	var eye_c := Color("#e8b030") if "big_eyes" in feats else C_INK
	if "face_disc" in feats:
		_box(head, Vector3(-hs * 0.5 - 0.005, -hs * 0.15, hs * 0.55),
			Vector3(hs * 1.01, hs * 0.85, 0.02), s["c_belly"])
	for side in [-1.0, 1.0]:
		var ex: float = side * hs * 0.5
		var eo: float = (0.0 if side > 0 else -0.01)
		if "face_disc" in feats:
			_box(head, Vector3(side * hs * 0.22 - eye * 0.5, hs * 0.25, hs * 0.55 + 0.015),
				Vector3(eye, eye, 0.01), eye_c)
			_box(head, Vector3(side * hs * 0.22 - eye * 0.25, hs * 0.25 + eye * 0.25, hs * 0.55 + 0.02),
				Vector3(eye * 0.5, eye * 0.5, 0.01), C_INK)
		else:
			_box(head, Vector3(ex + eo, hs * 0.35, hs * 0.35), Vector3(0.01, eye, eye), eye_c)
	if "comb" in feats:
		var comb := Color("#c8352c")
		for i in 3:
			_box(head, Vector3(-hs * 0.08, hs * 0.75 + (i % 2) * hs * 0.1, hs * 0.05 + i * hs * 0.2),
				Vector3(hs * 0.16, hs * 0.28, hs * 0.16), comb)
	if "wattle" in feats:
		_box(head, Vector3(-hs * 0.1, -hs * 0.35, hs * 0.55), Vector3(hs * 0.2, hs * 0.24, hs * 0.14),
			Color("#c8352c"))

	# Wings: two flat plates hinged at the shoulder. Folded (rotation.z ~0)
	# they lie along the flank; spread they stick straight out.
	var span: float = s["wingspan"]
	var wings: Array = []
	if span > 0.0:
		var half := span * 0.5 - b.x * 0.5
		var chord := b.z * 0.62
		for side in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(side * b.x * 0.5, b.y * 0.85, b.z * 0.05)
			torso.add_child(w)
			var origin_x := 0.0 if side > 0 else -half
			_box(w, Vector3(origin_x, -0.012, -chord * 0.55), Vector3(half, 0.024, chord), s["c_wing"])
			# A darker leading edge and, for a gull, black tips.
			_box(w, Vector3(origin_x, -0.006, chord * 0.35), Vector3(half, 0.03, chord * 0.12),
				s["c_wing"].darkened(0.18))
			if "black_wingtips" in feats:
				var tip_x := (half - half * 0.22) if side > 0 else -half
				_box(w, Vector3(tip_x, -0.014, -chord * 0.5), Vector3(half * 0.22, 0.028, chord * 0.8),
					s["c_wingtip"])
			if "speculum" in feats:
				var sx := (half * 0.4) if side > 0 else (-half * 0.6)
				_box(w, Vector3(sx, 0.012, -chord * 0.35), Vector3(half * 0.2, 0.01, chord * 0.3),
					Color("#2b4c9c"))
			wings.append(w)
	out["wings"] = wings
	# Folded wings, as a panel lying along each flank with the tip toward the
	# tail. Shown when the bird is on the ground and swapped for the flight
	# wings in the air: a flat plate pivoted about a shoulder cannot be made to
	# lie against the body convincingly, and a folded wing is a shape of its
	# own in any case.
	var folded: Array = []
	for side in [-1.0, 1.0]:
		var x0: float = side * b.x * 0.5 + (0.0 if side > 0 else -0.02)
		var panel := _box(torso, Vector3(x0, b.y * 0.28, -b.z * 0.42),
			Vector3(0.02, b.y * 0.5, b.z * 0.74), s["c_wing"])
		folded.append(panel)
		if "black_wingtips" in feats:
			var tip := _box(torso, Vector3(x0 - 0.002, b.y * 0.3, -b.z * 0.44),
				Vector3(0.024, b.y * 0.3, b.z * 0.16), s["c_wingtip"])
			folded.append(tip)
		if "speculum" in feats:
			var sp := _box(torso, Vector3(x0 - 0.002, b.y * 0.42, -b.z * 0.2),
				Vector3(0.024, b.y * 0.16, b.z * 0.22), Color("#2b4c9c"))
			folded.append(sp)
	out["folded"] = folded

	# Legs
	var legs: Array = []
	var ll: float = s["legs"]
	for side in [-1.0, 1.0]:
		var n := Node3D.new()
		n.position = Vector3(side * b.x * 0.22, stand, b.z * 0.02)
		root.add_child(n)
		_box(n, Vector3(-0.012, -ll, -0.012), Vector3(0.024, ll, 0.024), s["c_leg"])
		_box(n, Vector3(-0.03, -ll, -0.02), Vector3(0.06, 0.012, 0.07), s["c_leg"])
		legs.append(n)
	out["legs"] = legs
	return out


# ------------------------------------------------------------------- fish

## A body flattened side to side, tapering to a tail on a pivot, with a dorsal
## fin, two pectorals and an eye. Origin at the body centre; +Z is the nose.
static func _fish(s: Dictionary, kind: String, root: Node3D) -> Dictionary:
	var L: float = s["length"]
	var D: float = s["depth"]
	var Wd: float = s["width"]
	var feats: Array = s.get("features", [])
	var back: Color = s["c_back"]
	var belly: Color = s["c_belly"]
	var out := {}

	var torso := Node3D.new()
	root.add_child(torso)
	out["torso"] = torso
	# Three sections, each narrower than the last toward the tail, so the
	# silhouette is a fish and not a bar of soap.
	_box(torso, Vector3(-Wd * 0.5, -D * 0.5, -L * 0.1), Vector3(Wd, D, L * 0.45), back)
	_box(torso, Vector3(-Wd * 0.42, -D * 0.5, 0.0), Vector3(Wd * 0.84, D * 0.55, L * 0.45), belly)
	_box(torso, Vector3(-Wd * 0.4, -D * 0.4, L * 0.35), Vector3(Wd * 0.8, D * 0.8, L * 0.15), back)
	_box(torso, Vector3(-Wd * 0.35, -D * 0.35, -L * 0.3), Vector3(Wd * 0.7, D * 0.7, L * 0.22), back)
	_box(torso, Vector3(-Wd * 0.3, -D * 0.38, -L * 0.3), Vector3(Wd * 0.6, D * 0.35, L * 0.2), belly)
	if "pink_stripe" in feats:
		for side in [-1.0, 1.0]:
			_box(torso, Vector3(side * Wd * 0.5 - (0.0 if side > 0 else 0.006), -D * 0.08, -L * 0.28),
				Vector3(0.006, D * 0.16, L * 0.7), s["c_stripe"])
	if "spots" in feats:
		for side in [-1.0, 1.0]:
			for i in 5:
				_box(torso, Vector3(side * Wd * 0.5 - (0.0 if side > 0 else 0.007),
					D * 0.12 + (i % 2) * D * 0.15, -L * 0.25 + i * L * 0.13),
					Vector3(0.007, D * 0.08, D * 0.08), C_INK)
	if "bars" in feats:
		for side in [-1.0, 1.0]:
			for i in 5:
				_box(torso, Vector3(side * Wd * 0.5 - (0.0 if side > 0 else 0.007),
					-D * 0.3, -L * 0.28 + i * L * 0.15),
					Vector3(0.007, D * 0.75, L * 0.05), s["c_stripe"])
	# Eye
	for side in [-1.0, 1.0]:
		_box(torso, Vector3(side * Wd * 0.4 - (0.0 if side > 0 else 0.008), D * 0.08, L * 0.36),
			Vector3(0.008, D * 0.18, D * 0.18), C_CREAM)
		_box(torso, Vector3(side * Wd * 0.4 - (0.0 if side > 0 else 0.012), D * 0.11, L * 0.39),
			Vector3(0.012, D * 0.1, D * 0.1), C_INK)
	# Dorsal fin
	var fin: Color = s["c_fin"]
	var dorsal_h := D * (0.7 if "spiny_dorsal" in feats else 0.45)
	_box(torso, Vector3(-0.006, D * 0.5 - 0.01, -L * 0.15), Vector3(0.012, dorsal_h, L * 0.3), fin)
	if "spiny_dorsal" in feats:
		for i in 4:
			_box(torso, Vector3(-0.004, D * 0.5 + dorsal_h - 0.01, -L * 0.15 + i * L * 0.075),
				Vector3(0.008, D * 0.2, 0.01), fin.darkened(0.3))
	# Pectoral fins, angled back
	for side in [-1.0, 1.0]:
		var p := Node3D.new()
		p.position = Vector3(side * Wd * 0.5, -D * 0.15, L * 0.18)
		p.rotation.y = side * 0.6
		torso.add_child(p)
		_box(p, Vector3(0.0 if side > 0 else -L * 0.14, -0.005, -L * 0.05),
			Vector3(L * 0.14, 0.01, L * 0.1), fin)
	# Tail fin on a pivot at the end of the body
	var tailfin := Node3D.new()
	tailfin.position = Vector3(0.0, 0.0, -L * 0.3)
	torso.add_child(tailfin)
	out["tailfin"] = tailfin
	_box(tailfin, Vector3(-0.006, -D * 0.45, -L * 0.22), Vector3(0.012, D * 0.9, L * 0.22), s["c_tail"])
	_box(tailfin, Vector3(-0.005, -D * 0.2, -L * 0.1), Vector3(0.01, D * 0.4, L * 0.1), back)
	return out
