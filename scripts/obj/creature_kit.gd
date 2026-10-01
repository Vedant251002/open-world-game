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
##
## Optional quadruped keys, all with a sensible default: body_frac (depth of the
## barrel as a share of the height), head_down (how far the head points below the
## horizontal, radians), tail_rot (hang angle of the tail, 0 straight down,
## ~1.4 straight back, ~2.5 cocked up), neck_t (neck thickness), and the extra
## colours c_ear, c_tail, c_sock (lower leg), c_thigh (upper leg), c_hair.
const SPECIES := {
	# ---------------------------------------------------------- livestock
	"hen": {
		"plan": "bird", "move": "walk", "wild": false,
		"body": Vector3(0.24, 0.24, 0.36), "stand": 0.20, "head": 0.13,
		"beak": 0.06, "tail_up": true, "wingspan": 0.0, "legs": 0.16,
		"c_body": Color("#efe9dd"), "c_head": Color("#efe9dd"),
		"c_wing": Color("#d9d0bd"), "c_belly": Color("#f6f1e6"),
		"c_beak": C_BEAK_Y, "c_leg": Color("#d8973a"),
		"c_tail": Color("#cfc5b0"),
		"features": ["comb", "wattle", "earlobe"],
		"speed": 1.5, "flee": 3.2, "shy": 2.6, "fall": 2.2,
		"gives": "egg", "every": 9.0,
	},
	"rooster": {
		"plan": "bird", "move": "walk", "wild": false,
		"body": Vector3(0.27, 0.28, 0.42), "stand": 0.26, "head": 0.14,
		"beak": 0.06, "tail_up": true, "wingspan": 0.0, "legs": 0.20,
		"c_body": Color("#9a4a22"), "c_head": Color("#b5602a"),
		"c_neck": Color("#e0932f"),
		"c_wing": Color("#7a3518"), "c_belly": Color("#5a3420"),
		"c_beak": C_BEAK_Y, "c_leg": Color("#d8973a"),
		"c_tail": Color("#2c6a4a"),
		"features": ["comb", "wattle", "sickle_tail", "earlobe", "hackle"],
		"speed": 1.6, "flee": 3.4, "shy": 2.4, "fall": 2.2,
		"gives": "", "every": 0.0,
	},
	"sheep": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.3, "H": 0.85, "W": 0.50, "neck": 0.26, "neck_up": 0.35,
		"head": Vector3(0.20, 0.24, 0.30), "muzzle": Vector3(0.14, 0.13, 0.12),
		"ears": "side", "tail": 0.16, "tail_rot": 0.2, "leg": 0.06,
		"body_frac": 0.52, "head_down": 0.3, "neck_t": 0.9,
		"c_body": Color("#e9e3d3"), "c_belly": Color("#d8d1be"),
		"c_head": Color("#5a4a3d"), "c_muzzle": Color("#6b5a4b"),
		"c_leg": Color("#5a4a3d"), "c_hoof": Color("#2b2621"),
		"c_ear": Color("#6b5a4b"), "c_tail": Color("#e0dac8"),
		"features": ["fleece"],
		"speed": 1.1, "flee": 2.4, "shy": 2.2, "fall": 22.0,
		"gives": "wool", "every": 26.0,
	},
	"cow": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 2.4, "H": 1.45, "W": 0.70, "neck": 0.50, "neck_up": 0.15,
		"head": Vector3(0.30, 0.34, 0.46), "muzzle": Vector3(0.24, 0.20, 0.18),
		"ears": "side", "tail": 0.85, "tail_rot": 0.12, "leg": 0.095,
		"body_frac": 0.50, "head_down": 0.45, "neck_t": 1.15,
		"c_body": Color("#ece7dc"), "c_belly": Color("#e2dccd"),
		"c_head": Color("#ece7dc"), "c_muzzle": Color("#d9a99b"),
		"c_leg": Color("#ddd6c6"), "c_hoof": Color("#4a3f36"),
		"c_patch": Color("#4a4640"), "c_ear": Color("#4a4640"),
		"c_tail": Color("#4a4640"),
		"features": ["holstein", "horns_short", "udder", "tuft"],
		"speed": 1.0, "flee": 2.0, "shy": 2.0, "fall": 22.0,
		"gives": "milk", "every": 20.0,
	},
	"goat": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.2, "H": 0.80, "W": 0.38, "neck": 0.34, "neck_up": 0.65,
		"head": Vector3(0.17, 0.22, 0.28), "muzzle": Vector3(0.12, 0.12, 0.10),
		"ears": "side", "tail": 0.12, "tail_rot": 2.5, "leg": 0.05,
		"head_down": 0.25,
		"c_body": Color("#b09a7c"), "c_belly": Color("#e0d6c2"),
		"c_head": Color("#a08a6c"), "c_muzzle": Color("#e0d6c2"),
		"c_leg": Color("#7e6a52"), "c_hoof": Color("#2b2621"),
		"c_ear": Color("#8a7358"), "c_patch": Color("#5e4d3c"),
		"features": ["horns_back", "beard", "goat_stripe"],
		"speed": 1.4, "flee": 3.0, "shy": 2.2, "fall": 22.0,
		"gives": "milk", "every": 24.0,
	},
	"pig": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 1.6, "H": 0.85, "W": 0.62, "neck": 0.14, "neck_up": 0.0,
		"head": Vector3(0.32, 0.32, 0.34), "muzzle": Vector3(0.18, 0.15, 0.14),
		"ears": "floppy", "tail": 0.0, "tail_rot": 0.0, "leg": 0.075,
		"body_frac": 0.54, "head_down": 0.35, "neck_t": 1.2,
		"c_body": Color("#e9b4aa"), "c_belly": Color("#f3cdc4"),
		"c_head": Color("#e9b4aa"), "c_muzzle": Color("#dd9890"),
		"c_leg": Color("#dfa59b"), "c_hoof": Color("#6f5450"),
		"c_patch": Color("#d79a92"), "c_ear": Color("#dc9a92"),
		"features": ["snout_disc", "curly_tail", "pig_spots"],
		"speed": 1.2, "flee": 2.6, "shy": 2.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"horse": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 2.4, "H": 1.60, "W": 0.56, "neck": 0.80, "neck_up": 0.85,
		"head": Vector3(0.22, 0.32, 0.60), "muzzle": Vector3(0.16, 0.19, 0.16),
		"ears": "up", "tail": 0.95, "tail_rot": 0.25, "leg": 0.07,
		"body_frac": 0.44, "head_down": 0.95, "neck_t": 1.15,
		"c_body": Color("#7a5236"), "c_belly": Color("#6c472f"),
		"c_head": Color("#76503a"), "c_muzzle": Color("#5a3a2a"),
		"c_leg": Color("#6a4430"), "c_hoof": Color("#3a3028"),
		"c_hair": Color("#33241c"), "c_ear": Color("#6a4430"),
		"c_sock": Color("#efe9dc"),
		"features": ["mane", "blaze", "long_tail", "socks", "forelock"],
		"speed": 1.9, "flee": 4.5, "shy": 2.6, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- about town
	"dog": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 0.9, "H": 0.55, "W": 0.26, "neck": 0.20, "neck_up": 0.55,
		"head": Vector3(0.16, 0.16, 0.22), "muzzle": Vector3(0.09, 0.09, 0.12),
		"ears": "floppy", "tail": 0.36, "tail_rot": 1.0, "leg": 0.04,
		"head_down": 0.15,
		"c_body": Color("#8a5a36"), "c_belly": Color("#eae2d2"),
		"c_head": Color("#8a5a36"), "c_muzzle": Color("#eae2d2"),
		"c_leg": Color("#eae2d2"), "c_hoof": Color("#eae2d2"),
		"c_patch": Color("#f1ebde"), "c_ear": Color("#4d3020"),
		"c_tail": Color("#8a5a36"),
		"features": ["collie_blaze", "bushy_tail", "white_tail_tip", "black_nose"],
		"speed": 2.4, "flee": 0.0, "shy": 0.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"cat": {
		"plan": "quadruped", "move": "walk", "wild": false,
		"L": 0.48, "H": 0.26, "W": 0.14, "neck": 0.08, "neck_up": 0.35,
		"head": Vector3(0.11, 0.10, 0.11), "muzzle": Vector3(0.05, 0.04, 0.04),
		"ears": "up", "tail": 0.30, "tail_rot": 2.7, "leg": 0.022,
		"head_down": 0.2,
		"c_body": Color("#b8956a"), "c_belly": Color("#e6d8bf"),
		"c_head": Color("#b8956a"), "c_muzzle": Color("#e6d8bf"),
		"c_leg": Color("#b8956a"), "c_hoof": Color("#e6d8bf"),
		"c_patch": Color("#6d5338"), "c_ear": Color("#d9a99b"),
		"features": ["tabby"],
		"speed": 1.6, "flee": 3.5, "shy": 1.6, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- the wild
	"deer": {
		"plan": "quadruped", "move": "walk", "wild": true,
		"L": 1.7, "H": 1.05, "W": 0.34, "neck": 0.52, "neck_up": 0.95,
		"head": Vector3(0.16, 0.22, 0.36), "muzzle": Vector3(0.10, 0.11, 0.12),
		"ears": "up", "tail": 0.14, "tail_rot": 2.4, "leg": 0.04,
		"body_frac": 0.44, "head_down": 0.6,
		"c_body": Color("#b07a44"), "c_belly": Color("#eadfca"),
		"c_head": Color("#a8723e"), "c_muzzle": Color("#d9c7a5"),
		"c_leg": Color("#8f6236"), "c_hoof": Color("#2b2621"),
		"c_patch": Color("#f0eadc"), "c_ear": Color("#d9c7a5"),
		"c_tail": Color("#b07a44"),
		"features": ["antlers", "white_rump", "black_nose", "deer_spots"],
		"speed": 1.6, "flee": 6.5, "shy": 9.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"rabbit": {
		"plan": "quadruped", "move": "hop", "wild": true,
		"L": 0.40, "H": 0.22, "W": 0.16, "neck": 0.05, "neck_up": 0.35,
		"head": Vector3(0.10, 0.10, 0.12), "muzzle": Vector3(0.05, 0.04, 0.04),
		"ears": "long", "tail": 0.0, "tail_rot": 2.0, "leg": 0.03,
		"head_down": 0.25,
		"c_body": Color("#9a8670"), "c_belly": Color("#e8e0d0"),
		"c_head": Color("#9a8670"), "c_muzzle": Color("#e8e0d0"),
		"c_leg": Color("#9a8670"), "c_hoof": Color("#e8e0d0"),
		"c_ear": Color("#d9a99b"),
		"features": ["puff_tail"],
		"speed": 2.2, "flee": 5.0, "shy": 6.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	"fox": {
		"plan": "quadruped", "move": "walk", "wild": true,
		"L": 0.72, "H": 0.40, "W": 0.20, "neck": 0.16, "neck_up": 0.35,
		"head": Vector3(0.13, 0.13, 0.20), "muzzle": Vector3(0.07, 0.06, 0.09),
		"ears": "up", "tail": 0.42, "tail_rot": 1.3, "leg": 0.03,
		"head_down": 0.12,
		"c_body": Color("#d9702a"), "c_belly": Color("#f3ead9"),
		"c_head": Color("#d9702a"), "c_muzzle": Color("#f3ead9"),
		"c_leg": Color("#4a3a30"), "c_hoof": Color("#4a3a30"),
		"c_patch": Color("#f3ead9"), "c_ear": Color("#3a2e27"),
		"c_tail": Color("#d9702a"),
		"features": ["bushy_tail", "white_tail_tip", "black_ear_tips", "black_nose"],
		"speed": 2.0, "flee": 6.0, "shy": 8.0, "fall": 22.0,
		"gives": "", "every": 0.0,
	},
	# ---------------------------------------------------------- birds
	"crow": {
		"plan": "bird", "move": "fly", "wild": true,
		"body": Vector3(0.14, 0.14, 0.30), "stand": 0.09, "head": 0.10,
		"beak": 0.07, "tail_up": false, "wingspan": 0.95, "legs": 0.07,
		"c_body": Color("#2e3340"), "c_head": Color("#343a48"),
		"c_wing": Color("#3a4254"), "c_belly": Color("#3a3f4c"),
		"c_beak": Color("#4a4a52"), "c_leg": Color("#4a4448"),
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
	# Every box of a limb is welded into one mesh (see BoxKit.Batch), so a hen
	# is seven meshes rather than sixty, all on the one material.
	_batch = BoxKit.Batch.new()
	match str(s["plan"]):
		"quadruped": out = _quadruped(s, root)
		"bird": out = _bird(s, kind, root)
		"fish": out = _fish(s, kind, root)
	_batch.flush()
	_batch = null
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


static var _batch: BoxKit.Batch


static func _box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color,
		rough: float = 0.9) -> void:
	_batch.box(parent, origin, size, colour, rough)


## A hash in [0, 1) from a small integer, for the scatter of wool and patches:
## the same animal always has the same coat.
static func _h(i: int) -> float:
	return float(hash(i * 7919 + 13) & 0xffff) / 65536.0


# ------------------------------------------------------------- quadrupeds

## Barrel, neck, head, four legs and a tail, in the proportions given.
##
## The neck is the part that makes the animal. A horse's rises at fifty
## degrees; a pig hardly has one; a deer's is nearly vertical and it is why a
## deer looks alert and a cow does not. So the neck is a pivot rotated by the
## species' angle, and the head hangs off the end of it and drops back toward
## the ground by `head_down`, which is what necks do.
static func _quadruped(s: Dictionary, root: Node3D) -> Dictionary:
	var L: float = s["L"]
	var H: float = s["H"]
	var W: float = s["W"]
	var body_h := H * float(s.get("body_frac", 0.46))   ## depth of the barrel
	var belly_y := H - body_h                           ## underside of the barrel
	var body_l := L * 0.58                              ## barrel, without neck and head
	var c_body: Color = s["c_body"]
	var c_belly: Color = s["c_belly"]
	var feats: Array = s.get("features", [])
	var out := {}

	var torso := Node3D.new()
	torso.position.y = belly_y
	root.add_child(torso)
	out["torso"] = torso

	_quad_barrel(s, torso, W, body_h, body_l, c_body, c_belly, feats)

	# --- neck and head ---
	var neck_len: float = s["neck"]
	var neck_up: float = s["neck_up"]
	var neck := Node3D.new()
	neck.position = Vector3(0.0, body_h * 0.78, body_l * 0.5 - 0.03)
	neck.rotation.x = -neck_up
	torso.add_child(neck)
	out["neck"] = neck
	var nt := float(s.get("neck_t", 1.0))
	var nw := W * 0.5 * nt
	var nh := W * 0.62 * nt
	# A neck is deep at the shoulder and slim at the head: two boxes do it.
	_box(neck, Vector3(-nw * 0.5, -nh * 0.5, -0.04), Vector3(nw, nh, neck_len * 0.55 + 0.04), c_body)
	_box(neck, Vector3(-nw * 0.4, -nh * 0.4, neck_len * 0.5), Vector3(nw * 0.8, nh * 0.8,
		neck_len * 0.5 + 0.02), s["c_head"] if "holstein" in feats else c_body)
	var c_hair: Color = s.get("c_hair", c_body)
	if "mane" in feats:
		# A ridge of hair, each tuft a different height, down the crest.
		var segs := 6
		for i in segs:
			var seg_l := neck_len / segs
			var hgt := nh * (0.34 + _h(i + 40) * 0.2)
			_box(neck, Vector3(-nw * 0.17, nh * 0.5 - 0.01, -0.04 + i * seg_l),
				Vector3(nw * 0.34, hgt, seg_l * 1.05), c_hair if i % 2 == 0 else c_hair.lightened(0.1), 0.95)

	var hd: Vector3 = s["head"]
	var head := Node3D.new()
	head.position = Vector3(0.0, 0.0, neck_len)
	var head_rest := neck_up + float(s.get("head_down", 0.4))
	head.rotation.x = head_rest
	out["head_rest"] = head_rest
	neck.add_child(head)
	out["head"] = head
	_quad_head(s, head, hd, feats)

	# --- legs: hip and shoulder pivots, a thick upper, a slim cannon, a hoof ---
	var leg_r: float = s["leg"]
	var legs: Array = []
	var lx := W * 0.5 - leg_r * 1.5
	var lz_f := body_l * 0.38
	var lz_b := -body_l * 0.38
	var leg_h := belly_y + body_h * 0.2
	var c_leg: Color = s["c_leg"]
	var c_thigh: Color = s.get("c_thigh", c_body if ("deer_spots" in feats or "mane" in feats)
		else c_leg)
	var c_sock: Color = s.get("c_sock", c_leg)
	if "holstein" in feats:
		c_thigh = c_body
	var paw := leg_r < 0.045
	for i in 4:
		var n := Node3D.new()
		var x := lx * (1.0 if i % 2 == 0 else -1.0)
		var hind := i >= 2
		n.position = Vector3(x, belly_y + body_h * 0.2, lz_b if hind else lz_f)
		root.add_child(n)
		var depth := leg_r * (3.5 if hind else 2.8)
		_box(n, Vector3(-leg_r * 1.4, -leg_h * 0.46, -depth * 0.5),
			Vector3(leg_r * 2.8, leg_h * 0.5, depth), c_thigh)
		# Hocks bend back and knees forward, which reads as a leg, not a pole.
		var back := -leg_r * 0.5 if hind else 0.0
		if "socks" in feats:
			# A white sock on the lower third only; the cannon above stays coat.
			_box(n, Vector3(-leg_r, -leg_h * 0.9, -leg_r + back),
				Vector3(leg_r * 2.0, leg_h * 0.3, leg_r * 2.0), c_leg)
			_box(n, Vector3(-leg_r * 1.05, -leg_h * 0.9, -leg_r * 1.05 + back),
				Vector3(leg_r * 2.1, leg_h * 0.16, leg_r * 2.1), c_sock)
		else:
			_box(n, Vector3(-leg_r, -leg_h * 0.9, -leg_r + back),
				Vector3(leg_r * 2.0, leg_h * 0.46, leg_r * 2.0),
				c_sock if "holstein" in feats else c_leg)
		if paw:
			_box(n, Vector3(-leg_r * 1.15, -leg_h, -leg_r * 1.1 + back),
				Vector3(leg_r * 2.3, leg_h * 0.14, leg_r * 3.2), s["c_hoof"])
		else:
			_box(n, Vector3(-leg_r * 1.15, -leg_h, -leg_r * 1.15 + back),
				Vector3(leg_r * 2.3, leg_h * 0.12, leg_r * 2.3), s["c_hoof"], 0.5)
		legs.append(n)
	out["legs"] = legs

	_quad_tail(s, root, out, W, belly_y, body_h, body_l, leg_r, feats)
	return out


## Barrel, shoulders and rump, plus whatever the coat is doing.
static func _quad_barrel(s: Dictionary, torso: Node3D, W: float, body_h: float,
		body_l: float, c_body: Color, c_belly: Color, feats: Array) -> void:
	var fleece := "fleece" in feats
	# The barrel, with a paler belly slab slung under it: real animals are
	# darker on top and lighter below almost without exception.
	_box(torso, Vector3(-W * 0.5, body_h * 0.2, -body_l * 0.5), Vector3(W, body_h * 0.78, body_l), c_body)
	_box(torso, Vector3(-W * 0.44, 0.0, -body_l * 0.44), Vector3(W * 0.88, body_h * 0.3, body_l * 0.88), c_belly)
	# Withers, chest and rump: deeper at each end than in the middle.
	_box(torso, Vector3(-W * 0.46, body_h * 0.72, body_l * 0.1), Vector3(W * 0.92, body_h * 0.3, body_l * 0.34), c_body)
	_box(torso, Vector3(-W * 0.42, body_h * 0.04, body_l * 0.38), Vector3(W * 0.84, body_h * 0.94, body_l * 0.16), c_body)
	_box(torso, Vector3(-W * 0.45, body_h * 0.3, -body_l * 0.55), Vector3(W * 0.9, body_h * 0.68, body_l * 0.12), c_body)
	# Haunches: the hind thigh stands proud of the flank.
	for side in [-1.0, 1.0]:
		var x0: float = (W * 0.5 - W * 0.13) if side > 0.0 else (-W * 0.5 - 0.008)
		_box(torso, Vector3(x0, body_h * 0.1, -body_l * 0.47), Vector3(W * 0.13 + 0.008, body_h * 0.68, body_l * 0.28),
			c_body.darkened(0.04) if not fleece else c_body)
	# A shade darker down the spine: coats are never one tone.
	if not ("fleece" in feats or "holstein" in feats):
		_box(torso, Vector3(-W * 0.3, body_h * 0.99, -body_l * 0.46), Vector3(W * 0.6, body_h * 0.045, body_l * 0.92),
			c_body.darkened(0.12))
		# And the flank lighter than the back, shading into the belly.
		for side in [-1.0, 1.0]:
			_box(torso, Vector3((W * 0.5 - 0.004) if side > 0.0 else (-W * 0.5 - 0.008), body_h * 0.2, -body_l * 0.36),
				Vector3(0.012, body_h * 0.26, body_l * 0.7), c_body.lerp(c_belly, 0.45))
	if fleece:
		_quad_fleece(torso, W, body_h, body_l, c_body)
	if "holstein" in feats:
		var p: Color = s["c_patch"]
		# Patches that differ side to side and wrap over the back, as a
		# Holstein's do: no two flanks alike. The coat is mostly white.
		for side in [-1.0, 1.0]:
			for k in 4:
				var h0 := _h(k * 7 + (3 if side > 0.0 else 0))
				var h1 := _h(k * 5 + (11 if side > 0.0 else 2))
				var h2 := _h(k * 3 + (17 if side > 0.0 else 5))
				var z0 := -body_l * 0.5 + (k * 0.26 + h0 * 0.08) * body_l
				var zl := body_l * (0.15 + h1 * 0.12)
				var y0 := body_h * (0.28 + h2 * 0.2)
				var yl := minf(body_h * (0.3 + h1 * 0.4), body_h * 0.98 - y0)
				var x0: float = (W * 0.5 - 0.004) if side > 0.0 else (-W * 0.5 - 0.012)
				_box(torso, Vector3(x0, y0, z0), Vector3(0.016, yl, zl), p)
				if yl > body_h * 0.5 and k % 2 == 0:
					# Over the top of the back, a cap that joins the side patch.
					var cx: float = (W * 0.05) if side > 0.0 else (-W * 0.5)
					_box(torso, Vector3(cx, body_h * 0.99, z0), Vector3(W * 0.45, 0.012, zl), p)
		_box(torso, Vector3(-W * 0.3, body_h * 0.99, body_l * 0.25), Vector3(W * 0.5, 0.012, body_l * 0.1), p)
	if "udder" in feats:
		_box(torso, Vector3(-W * 0.22, -body_h * 0.18, -body_l * 0.36), Vector3(W * 0.44, body_h * 0.22, body_l * 0.22), C_PINK)
		for sx in [-1.0, 1.0]:
			_box(torso, Vector3(sx * W * 0.1 - 0.012, -body_h * 0.3, -body_l * 0.31), Vector3(0.024, body_h * 0.14, 0.024), C_PINK.darkened(0.1))
	if "tabby" in feats:
		var p2: Color = s["c_patch"]
		for i in 5:
			_box(torso, Vector3(-W * 0.5 - 0.004, body_h * 0.5, -body_l * 0.42 + i * body_l * 0.19),
				Vector3(W * 1.01, body_h * 0.5, body_l * 0.07), p2)
	if "collie_blaze" in feats:
		var p3: Color = s["c_patch"]
		# A white ruff and chest, and white shirt-front.
		_box(torso, Vector3(-W * 0.5 - 0.004, body_h * 0.15, body_l * 0.3), Vector3(W * 1.01, body_h * 0.85, body_l * 0.15), p3)
		_box(torso, Vector3(-W * 0.4, body_h * 0.0, body_l * 0.2), Vector3(W * 0.8, body_h * 0.4, body_l * 0.3), p3)
		# A saddle patch of the dark coat only ever reads against pale legs.
		_box(torso, Vector3(-W * 0.5 - 0.004, body_h * 0.05, -body_l * 0.5), Vector3(W * 1.01, body_h * 0.2, body_l * 0.24), p3)
	if "white_rump" in feats:
		var p4: Color = s["c_patch"]
		_box(torso, Vector3(-W * 0.5 - 0.004, body_h * 0.15, -body_l * 0.52), Vector3(W * 1.01, body_h * 0.62, body_l * 0.1), p4)
	if "deer_spots" in feats:
		var sp: Color = s["c_patch"].darkened(0.08)
		for i in 10:
			var side2 := 1.0 if i % 2 == 0 else -1.0
			var sz := 0.03 + _h(i + 90) * 0.02
			_box(torso, Vector3((W * 0.5 - 0.004) if side2 > 0.0 else (-W * 0.5 - 0.008),
				body_h * (0.5 + _h(i + 70) * 0.4), -body_l * 0.4 + _h(i + 80) * body_l * 0.7),
				Vector3(0.012, sz, sz), sp)
	if "pig_spots" in feats:
		var ps: Color = s["c_patch"]
		for i in 5:
			var side3 := 1.0 if i % 2 == 0 else -1.0
			_box(torso, Vector3((W * 0.5 - 0.004) if side3 > 0.0 else (-W * 0.5 - 0.012),
				body_h * (0.3 + _h(i + 50) * 0.35), -body_l * 0.4 + _h(i + 60) * body_l * 0.7),
				Vector3(0.016, body_h * (0.22 + _h(i + 30) * 0.2), body_l * (0.12 + _h(i + 20) * 0.12)), ps)
	if "goat_stripe" in feats:
		var gs: Color = s["c_patch"]
		_box(torso, Vector3(-W * 0.12, body_h * 0.995, -body_l * 0.5), Vector3(W * 0.24, 0.012, body_l * 1.0), gs)


## Wool: a core, then lumps of different sizes and tones standing proud of it,
## so a sheep reads as a fleece rather than a white box.
static func _quad_fleece(torso: Node3D, W: float, body_h: float, body_l: float, c: Color) -> void:
	_box(torso, Vector3(-W * 0.56, body_h * 0.14, -body_l * 0.54), Vector3(W * 1.12, body_h * 0.96, body_l * 1.08),
		c.darkened(0.04), 1.0)
	var n := 0
	# Rows of clumps along the back, and down both flanks.
	for iz in 7:
		for ix in 3:
			var cs := W * (0.26 + _h(n * 5 + 1) * 0.12)
			var z := -body_l * 0.46 + iz * body_l * 0.152 + (_h(n * 7) - 0.5) * 0.04
			var x := (ix - 1) * W * 0.34 + (_h(n * 3) - 0.5) * 0.03
			var tone := c.lightened(0.04 + _h(n * 11) * 0.08) if n % 3 != 0 else c.darkened(0.06 + _h(n * 13) * 0.05)
			_box(torso, Vector3(x - cs * 0.5, body_h * 1.02 - cs * 0.25, z - cs * 0.5), Vector3(cs, cs * 0.6, cs * 1.05), tone, 1.0)
			n += 1
	for side in [-1.0, 1.0]:
		for iz in 6:
			for iy in 2:
				var cs2 := W * (0.2 + _h(n * 5 + 2) * 0.1)
				var z2 := -body_l * 0.44 + iz * body_l * 0.17 + (_h(n * 7) - 0.5) * 0.04
				var y2 := body_h * (0.34 + iy * 0.36) + (_h(n * 3) - 0.5) * 0.03
				var tone2 := c.lightened(0.03 + _h(n * 11) * 0.08) if n % 3 != 0 else c.darkened(0.07)
				var x2: float = (W * 0.56 - cs2 * 0.3) if side > 0.0 else (-W * 0.56 - cs2 * 0.7)
				_box(torso, Vector3(x2, y2 - cs2 * 0.5, z2 - cs2 * 0.5), Vector3(cs2, cs2, cs2 * 1.05), tone2, 1.0)
				n += 1
	# A ruff of wool at the shoulder where the neck goes in, and a bustle.
	_box(torso, Vector3(-W * 0.4, body_h * 0.5, body_l * 0.42), Vector3(W * 0.8, body_h * 0.6, body_l * 0.14), c.lightened(0.05), 1.0)
	_box(torso, Vector3(-W * 0.4, body_h * 0.4, -body_l * 0.6), Vector3(W * 0.8, body_h * 0.6, body_l * 0.1), c.lightened(0.03), 1.0)


## The head, from the skull forward: cranium, a narrower face, the muzzle and a
## chin, then eyes, nostrils, ears and whatever grows out of the top.
static func _quad_head(s: Dictionary, head: Node3D, hd: Vector3, feats: Array) -> void:
	var c_head: Color = s["c_head"]
	var c_muz: Color = s["c_muzzle"]
	var mz: Vector3 = s["muzzle"]
	_box(head, Vector3(-hd.x * 0.5, -hd.y * 0.45, -hd.z * 0.15), Vector3(hd.x, hd.y, hd.z * 0.5), c_head)
	_box(head, Vector3(-hd.x * 0.39, -hd.y * 0.45, hd.z * 0.3), Vector3(hd.x * 0.78, hd.y * 0.74, hd.z * 0.28), c_head)
	_box(head, Vector3(-mz.x * 0.5, -hd.y * 0.42, hd.z * 0.55), mz, c_muz)
	# The chin, a hair paler and tucked under the muzzle.
	_box(head, Vector3(-mz.x * 0.4, -hd.y * 0.42 - mz.y * 0.16, hd.z * 0.52), Vector3(mz.x * 0.8, mz.y * 0.2, mz.z * 0.9),
		c_muz.lightened(0.06))
	var nose: Color = C_INK if "black_nose" in feats else c_muz.darkened(0.35)
	if "snout_disc" in feats:
		# A pig's snout: a broad flat disc with two big nostrils.
		_box(head, Vector3(-mz.x * 0.6, -hd.y * 0.42 - mz.y * 0.05, hd.z * 0.55 + mz.z - 0.005),
			Vector3(mz.x * 1.2, mz.y * 1.15, 0.03), c_muz.darkened(0.08), 0.5)
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(sx * mz.x * 0.24 - mz.x * 0.09, -hd.y * 0.42 + mz.y * 0.28, hd.z * 0.55 + mz.z + 0.022),
				Vector3(mz.x * 0.18, mz.y * 0.34, 0.012), c_muz.darkened(0.5), 0.3)
	else:
		_box(head, Vector3(-mz.x * 0.38, -hd.y * 0.42 + mz.y * 0.5, hd.z * 0.55 + mz.z - 0.01),
			Vector3(mz.x * 0.76, mz.y * 0.4, 0.02), nose, 0.35)
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(sx * mz.x * 0.2 - mz.x * 0.06, -hd.y * 0.42 + mz.y * 0.62, hd.z * 0.55 + mz.z + 0.006),
				Vector3(mz.x * 0.12, mz.y * 0.14, 0.014), C_INK, 0.3)

	# Eyes: dark, with a socket around them and a bright glint in the corner.
	var ey := maxf(hd.x * 0.17, 0.016)
	var ey_c := Color("#d9a43a") if "horns_back" in feats else C_INK
	var ez := hd.z * 0.26
	var eyy := hd.y * 0.14
	for side in [-1.0, 1.0]:
		var xo: float = (hd.x * 0.5 - 0.004) if side > 0.0 else (-hd.x * 0.5 - 0.006)
		var xg: float = (hd.x * 0.5 + 0.002) if side > 0.0 else (-hd.x * 0.5 - 0.012)
		_box(head, Vector3(xo, eyy - ey * 0.2, ez - ey * 0.2), Vector3(0.01, ey * 1.4, ey * 1.4), c_head.darkened(0.3), 0.5)
		_box(head, Vector3(xg, eyy, ez), Vector3(0.008, ey, ey), ey_c, 0.2)
		if "horns_back" in feats:
			# Goats have a slit pupil, set sideways.
			_box(head, Vector3(xg + (0.004 if side > 0.0 else -0.004), eyy + ey * 0.32, ez), Vector3(0.006, ey * 0.36, ey), C_INK, 0.2)
		_box(head, Vector3(xg + (0.004 if side > 0.0 else -0.004), eyy + ey * 0.55, ez + ey * 0.5),
			Vector3(0.006, ey * 0.38, ey * 0.38), Color("#fffaf0"), 0.15)
	if "blaze" in feats:
		_box(head, Vector3(-hd.x * 0.1, -hd.y * 0.35, hd.z * 0.02), Vector3(hd.x * 0.2, hd.y * 0.8, hd.z * 0.01 + 0.008), C_CREAM)
		_box(head, Vector3(-hd.x * 0.1, -hd.y * 0.35, hd.z * 0.02), Vector3(hd.x * 0.2, 0.01, hd.z * 0.6), C_CREAM)
		_box(head, Vector3(-hd.x * 0.1, hd.y * 0.54, -hd.z * 0.1), Vector3(hd.x * 0.2, 0.008, hd.z * 0.5), C_CREAM)
	if "collie_blaze" in feats:
		var cp: Color = s["c_patch"]
		_box(head, Vector3(-hd.x * 0.14, hd.y * 0.54, -hd.z * 0.1), Vector3(hd.x * 0.28, 0.01, hd.z * 0.7), cp)
		_box(head, Vector3(-hd.x * 0.14, -hd.y * 0.35, hd.z * 0.28), Vector3(hd.x * 0.28, hd.y * 0.9, 0.012), cp)
		_box(head, Vector3(-hd.x * 0.5 - 0.004, -hd.y * 0.5, hd.z * 0.05), Vector3(hd.x * 1.01, hd.y * 0.35, hd.z * 0.5), cp)
	if "holstein" in feats:
		# A dark eye patch and a dark crown: no two cows' faces are the same.
		var cp2: Color = s["c_patch"]
		_box(head, Vector3(-hd.x * 0.5 - 0.004, -hd.y * 0.05, -hd.z * 0.14), Vector3(hd.x * 1.01, hd.y * 0.55, hd.z * 0.42), cp2)
		_box(head, Vector3(-hd.x * 0.5, hd.y * 0.54, -hd.z * 0.14), Vector3(hd.x, 0.01, hd.z * 0.3), cp2)
		_box(head, Vector3(-hd.x * 0.12, -hd.y * 0.1, hd.z * 0.3), Vector3(hd.x * 0.24, hd.y * 0.65, 0.012), C_CREAM)
	if "beard" in feats:
		_box(head, Vector3(-mz.x * 0.2, -hd.y * 0.45 - hd.y * 0.4, hd.z * 0.5), Vector3(mz.x * 0.4, hd.y * 0.44, mz.z * 0.5),
			s["c_patch"])
	if "fleece" in feats:
		# A topknot and woolly cheeks: the face is a dark window in the wool.
		var wc: Color = Color("#e9e3d3")
		_box(head, Vector3(-hd.x * 0.56, hd.y * 0.35, -hd.z * 0.18), Vector3(hd.x * 1.12, hd.y * 0.3, hd.z * 0.4), wc, 1.0)
		_box(head, Vector3(-hd.x * 0.4, hd.y * 0.55, -hd.z * 0.05), Vector3(hd.x * 0.8, hd.y * 0.18, hd.z * 0.25), wc.lightened(0.04), 1.0)

	# Ears: the shape of the ear is a third of the silhouette.
	var c_ear: Color = s.get("c_ear", c_head.darkened(0.08))
	var e_w := hd.x * 0.3
	match str(s["ears"]):
		"up":
			for side in [-1.0, 1.0]:
				var ex: float = side * hd.x * 0.3 - e_w * 0.5
				_box(head, Vector3(ex, hd.y * 0.45, -hd.z * 0.08), Vector3(e_w, hd.y * 0.6, e_w * 0.6), c_head)
				_box(head, Vector3(ex + e_w * 0.15, hd.y * 0.5, -hd.z * 0.08 + e_w * 0.5), Vector3(e_w * 0.7, hd.y * 0.46, 0.008), c_ear.lightened(0.15))
				if "black_ear_tips" in feats:
					_box(head, Vector3(ex - 0.002, hd.y * 0.45 + hd.y * 0.44, -hd.z * 0.08 - 0.002), Vector3(e_w + 0.004, hd.y * 0.17, e_w * 0.6 + 0.004), c_ear)
		"long":
			for side in [-1.0, 1.0]:
				var ex2: float = side * hd.x * 0.3 - e_w * 0.5
				_box(head, Vector3(ex2, hd.y * 0.4, -hd.z * 0.1), Vector3(e_w, hd.y * 1.4, e_w * 0.5), c_head)
				_box(head, Vector3(ex2 + e_w * 0.15, hd.y * 0.5, -hd.z * 0.1 + e_w * 0.46), Vector3(e_w * 0.7, hd.y * 1.1, 0.008), c_ear)
		"floppy":
			# Hangs down beside the face from the top of the head.
			for side in [-1.0, 1.0]:
				var x0: float = side * hd.x * 0.5 + (0.0 if side > 0 else -e_w * 0.9)
				_box(head, Vector3(x0, -hd.y * 0.1, -hd.z * 0.02), Vector3(e_w * 0.9, hd.y * 0.55, e_w * 1.3), c_ear)
				_box(head, Vector3(x0 + (0.0 if side > 0 else -0.004), hd.y * 0.35, -hd.z * 0.02), Vector3(e_w * 0.9 + 0.004, hd.y * 0.12, e_w * 1.3), c_ear.darkened(0.12))
		_:
			# "side": sticks straight out, the way a cow's or a sheep's does.
			for side in [-1.0, 1.0]:
				var x1: float = side * hd.x * 0.5 + (0.0 if side > 0 else -e_w * 1.6)
				_box(head, Vector3(x1, hd.y * 0.08, hd.z * 0.0), Vector3(e_w * 1.6, hd.y * 0.18, e_w * 1.1), c_ear)
				_box(head, Vector3(x1 + (e_w * 0.2 if side > 0 else e_w * 0.2), hd.y * 0.08 + hd.y * 0.18, hd.z * 0.0 + 0.01),
					Vector3(e_w * 1.2, 0.006, e_w * 0.9), c_ear.lightened(0.18))
	if "forelock" in feats:
		var hair: Color = s["c_hair"]
		_box(head, Vector3(-hd.x * 0.24, hd.y * 0.4, hd.z * 0.02), Vector3(hd.x * 0.48, hd.y * 0.2, hd.z * 0.22), hair, 0.95)

	if "horns_short" in feats:
		# Out, then up: a cow's horn is two short boxes, not one stick.
		for side in [-1.0, 1.0]:
			var hx: float = side * hd.x * 0.5
			_box(head, Vector3(hx - (0.0 if side > 0 else 0.07), hd.y * 0.46, -hd.z * 0.03), Vector3(0.07, 0.04, 0.05), C_CREAM, 0.5)
			_box(head, Vector3(hx + side * 0.07 - 0.02, hd.y * 0.46, -hd.z * 0.03 - 0.0), Vector3(0.04, 0.11, 0.05), C_CREAM.darkened(0.05), 0.5)
	if "horns_back" in feats:
		for side in [-1.0, 1.0]:
			var horn := Node3D.new()
			horn.position = Vector3(side * hd.x * 0.28, hd.y * 0.5, -hd.z * 0.02)
			horn.rotation.x = -0.4
			horn.rotation.z = -side * 0.15
			head.add_child(horn)
			_box(horn, Vector3(-0.022, 0.0, -0.022), Vector3(0.044, hd.y * 0.45, 0.044), Color("#6a5f52"), 0.6)
			var tip := Node3D.new()
			tip.position = Vector3(0.0, hd.y * 0.45, 0.0)
			tip.rotation.x = 0.9
			horn.add_child(tip)
			_box(tip, Vector3(-0.017, 0.0, -0.017), Vector3(0.034, hd.y * 0.5, 0.034), Color("#8a7f70"), 0.6)
	if "antlers" in feats:
		var bone := Color("#c9b690")
		for side in [-1.0, 1.0]:
			var beam := Node3D.new()
			beam.position = Vector3(side * hd.x * 0.28, hd.y * 0.5, -hd.z * 0.05)
			beam.rotation.x = 0.3
			beam.rotation.z = -side * 0.4
			head.add_child(beam)
			_box(beam, Vector3(-0.02, 0.0, -0.02), Vector3(0.04, 0.4, 0.04), bone.darkened(0.12), 0.6)
			_box(beam, Vector3(-0.015, 0.4, -0.015), Vector3(0.03, 0.1, 0.03), bone, 0.6)
			# Tines off the main beam, forward and up.
			for i in 3:
				var tine := Node3D.new()
				tine.position = Vector3(0.0, 0.1 + i * 0.11, 0.0)
				tine.rotation.x = -0.9
				tine.rotation.z = side * 0.25
				beam.add_child(tine)
				_box(tine, Vector3(-0.012, 0.0, -0.012), Vector3(0.024, 0.16 - i * 0.03, 0.024), bone, 0.6)


## The tail: a pivot at the rump that hangs, cocks or trails by `tail_rot`.
static func _quad_tail(s: Dictionary, root: Node3D, out: Dictionary, W: float, belly_y: float,
		body_h: float, body_l: float, leg_r: float, feats: Array) -> void:
	var tail_len: float = s["tail"]
	var rot := float(s.get("tail_rot", 0.3))
	var tail := Node3D.new()
	tail.position = Vector3(0.0, belly_y + body_h * 0.9, -body_l * 0.5 - 0.01)
	tail.rotation.x = rot
	root.add_child(tail)
	out["tail"] = tail
	# Straight down swings side to side; trailing straight back swings about Y.
	out["tail_axis"] = "y" if (rot > 1.0 and rot < 1.9) else "z"
	var c_tail: Color = s.get("c_tail", s["c_body"])
	if tail_len > 0.0:
		var tw := leg_r * 1.1
		if "bushy_tail" in feats:
			tw = W * 0.4
			# Thin at the root, fat in the middle, tapering to the tip.
			_box(tail, Vector3(-tw * 0.3, -tail_len * 0.3, -tw * 0.3), Vector3(tw * 0.6, tail_len * 0.3, tw * 0.6), c_tail)
			_box(tail, Vector3(-tw * 0.5, -tail_len * 0.78, -tw * 0.5), Vector3(tw, tail_len * 0.5, tw), c_tail.lightened(0.04), 0.95)
			_box(tail, Vector3(-tw * 0.32, -tail_len, -tw * 0.32), Vector3(tw * 0.64, tail_len * 0.24, tw * 0.64), c_tail, 0.95)
			if "white_tail_tip" in feats:
				_box(tail, Vector3(-tw * 0.34, -tail_len - 0.02, -tw * 0.34), Vector3(tw * 0.68, tail_len * 0.3, tw * 0.68), s["c_patch"], 0.95)
		elif "long_tail" in feats:
			# Dock, then a fall of hair that widens as it hangs.
			var hair: Color = s["c_hair"]
			_box(tail, Vector3(-W * 0.07, -tail_len * 0.3, -W * 0.07), Vector3(W * 0.14, tail_len * 0.3, W * 0.14), s["c_body"].darkened(0.1))
			_box(tail, Vector3(-W * 0.12, -tail_len * 0.7, -W * 0.1), Vector3(W * 0.24, tail_len * 0.45, W * 0.2), hair, 0.95)
			_box(tail, Vector3(-W * 0.09, -tail_len, -W * 0.08), Vector3(W * 0.18, tail_len * 0.35, W * 0.16), hair.lightened(0.08), 0.95)
		else:
			_box(tail, Vector3(-tw * 0.5, -tail_len, -tw * 0.5), Vector3(tw, tail_len, tw), c_tail)
		if "tuft" in feats:
			var tuft: Color = s["c_patch"]
			_box(tail, Vector3(-tw * 1.1, -tail_len - 0.16, -tw * 1.1), Vector3(tw * 2.2, 0.18, tw * 2.2), tuft, 0.95)
		if "white_tail_tip" in feats and not ("bushy_tail" in feats):
			_box(tail, Vector3(-tw * 0.52, -tail_len, -tw * 0.52), Vector3(tw * 1.04, tail_len * 0.3, tw * 1.04), s["c_patch"])
	if "deer_spots" in feats:
		# The flag: a white underside that shows when the tail lifts.
		_box(tail, Vector3(-0.05, -tail_len, -0.03), Vector3(0.1, tail_len, 0.03), s["c_patch"])
	if "tabby" in feats:
		for i in 4:
			_box(tail, Vector3(-leg_r * 1.1 * 0.5 - 0.004, -tail_len + i * tail_len * 0.24, -leg_r * 1.1 * 0.5 - 0.004),
				Vector3(leg_r * 1.1 + 0.008, tail_len * 0.1, leg_r * 1.1 + 0.008), s["c_patch"])
	if "puff_tail" in feats:
		_box(tail, Vector3(-W * 0.18, -W * 0.3, -W * 0.14), Vector3(W * 0.36, W * 0.34, W * 0.34), C_CREAM, 1.0)
	if "curly_tail" in feats:
		# A pig's corkscrew: three stubby steps, curling up and over.
		var q := leg_r * 0.5
		var cc: Color = s["c_body"].darkened(0.05)
		_box(tail, Vector3(-q, 0.0, -q), Vector3(q * 2, q * 2, q * 2), cc)
		_box(tail, Vector3(-q, q * 1.5, -q * 3.0), Vector3(q * 2, q * 2, q * 3.0), cc)
		_box(tail, Vector3(-q, q * 3.0, -q * 3.0), Vector3(q * 2, q * 2, q * 2), cc)


# ------------------------------------------------------------------ birds

## Body, head, beak, tail, two wings on shoulder pivots, two legs. A hen and a
## crow are the same plan; the hen has no wingspan worth drawing and a comb.
static func _bird(s: Dictionary, kind: String, root: Node3D) -> Dictionary:
	var b: Vector3 = s["body"]
	var stand: float = s["stand"]
	var feats: Array = s.get("features", [])
	var c_body: Color = s["c_body"]
	var c_belly: Color = s["c_belly"]
	var out := {}

	var torso := Node3D.new()
	torso.position.y = stand
	root.add_child(torso)
	out["torso"] = torso
	# The body tapers: a deeper, rounder chest at the front, narrower behind.
	_box(torso, Vector3(-b.x * 0.5, 0.0, -b.z * 0.42), Vector3(b.x, b.y, b.z * 0.84), c_body)
	_box(torso, Vector3(-b.x * 0.42, -b.y * 0.12, -b.z * 0.3), Vector3(b.x * 0.84, b.y * 0.3, b.z * 0.7), c_belly)
	_box(torso, Vector3(-b.x * 0.36, b.y * 0.15, -b.z * 0.6), Vector3(b.x * 0.72, b.y * 0.6, b.z * 0.22), c_body.darkened(0.06))
	# Breast, pushed out in front of the wings.
	var c_breast: Color = s["c_chest"] if "mallard_chest" in feats else c_belly.lerp(c_body, 0.3)
	_box(torso, Vector3(-b.x * 0.4, -b.y * 0.05, b.z * 0.3), Vector3(b.x * 0.8, b.y * 0.85, b.z * 0.2), c_breast)
	# Rows of feathers across the back, each a shade off the last.
	for i in 4:
		var shade := -0.06 + (i % 2) * 0.10
		_box(torso, Vector3(-b.x * 0.5 - 0.004, b.y * 0.3, -b.z * 0.38 + i * b.z * 0.18),
			Vector3(b.x * 1.008, b.y * 0.7, b.z * 0.09), c_body.lightened(shade) if shade > 0
			else c_body.darkened(-shade))
	if "mallard_chest" in feats:
		_box(torso, Vector3(-b.x * 0.5 - 0.005, b.y * 0.15, b.z * 0.18), Vector3(b.x * 1.01, b.y * 0.7, b.z * 0.26), s["c_chest"])
	if "streaked_back" in feats:
		for i in 3:
			_box(torso, Vector3(-b.x * 0.3 + i * b.x * 0.3 - 0.005, b.y + 0.001, -b.z * 0.35),
				Vector3(0.01, 0.004, b.z * 0.6), s["c_wing"].darkened(0.3))
	# A neck between the shoulders and the head, so the head is not a ball
	# balanced on a box. Land birds only; a duck's is the same colour as its head.
	var hs: float = s["head"]
	var c_neck: Color = s.get("c_neck", s["c_head"] if "neck_ring" in feats else c_body)
	if str(s["move"]) == "walk" or str(s["move"]) == "float":
		_box(torso, Vector3(-hs * 0.36, b.y * 0.5, b.z * 0.28), Vector3(hs * 0.72, b.y * 0.62, hs * 0.7), c_neck)
	if "hackle" in feats:
		# A rooster's gold cape over the shoulders and the saddle feathers.
		_box(torso, Vector3(-b.x * 0.56, b.y * 0.62, b.z * 0.04), Vector3(b.x * 1.12, b.y * 0.42, b.z * 0.28), c_neck, 0.9)
		_box(torso, Vector3(-b.x * 0.52, b.y * 0.6, -b.z * 0.42), Vector3(b.x * 1.04, b.y * 0.4, b.z * 0.22), c_neck.darkened(0.12), 0.9)

	# Tail: flat, either cocked up (a hen, a duck) or trailing (everything that flies).
	var tail := Node3D.new()
	tail.position = Vector3(0.0, b.y * 0.55, -b.z * 0.42)
	tail.rotation.x = (0.35 if "sickle_tail" in feats else 0.7) if bool(s["tail_up"]) else -0.15
	torso.add_child(tail)
	out["tail"] = tail
	var tail_c: Color = s.get("c_tail", c_body.darkened(0.1))
	if "sickle_tail" in feats:
		# A rooster's tail: a fan of green-black plumes arching over.
		for i in 3:
			var lean := (i - 1) * 0.35
			var plume := Node3D.new()
			plume.rotation.y = lean
			tail.add_child(plume)
			var tc := tail_c.lightened(0.1 * (i % 2))
			_box(plume, Vector3(-0.014, -0.012, -b.z * 0.5), Vector3(0.028, 0.03, b.z * 0.5), tc, 0.5)
			var arc := Node3D.new()
			arc.position = Vector3(0.0, 0.0, -b.z * 0.48)
			arc.rotation.x = 0.7 + i * 0.1
			plume.add_child(arc)
			_box(arc, Vector3(-0.012, -0.012, -b.z * 0.4), Vector3(0.024, 0.026, b.z * 0.4), tc.lightened(0.08), 0.5)
	else:
		# A hen's tail: a small fan of short feathers.
		for i in 3:
			var fan := Node3D.new()
			fan.rotation.y = (i - 1) * 0.3
			tail.add_child(fan)
			_box(fan, Vector3(-b.x * 0.14, -0.012, -b.z * 0.36), Vector3(b.x * 0.28, 0.022, b.z * 0.36),
				tail_c.lightened(0.04 * i) if i != 1 else tail_c, 0.9)

	# Head, on the neck at the front.
	var head := Node3D.new()
	head.position = Vector3(0.0, b.y * 0.75, b.z * 0.42)
	torso.add_child(head)
	out["head"] = head
	_box(head, Vector3(-hs * 0.5, -hs * 0.2, -hs * 0.2), Vector3(hs, hs, hs * 0.95), s["c_head"])
	if "neck_ring" in feats:
		_box(head, Vector3(-hs * 0.5 - 0.005, -hs * 0.25, -hs * 0.2), Vector3(hs * 1.01, hs * 0.1, hs * 0.9), C_CREAM)
	# Beak: two halves, so it opens at a glance; the lower one is a shade paler.
	var bk: float = s["beak"]
	_box(head, Vector3(-hs * 0.18, hs * 0.14, hs * 0.72), Vector3(hs * 0.36, hs * 0.16, bk), s["c_beak"], 0.4)
	_box(head, Vector3(-hs * 0.15, hs * 0.0, hs * 0.72), Vector3(hs * 0.3, hs * 0.14, bk * 0.8), s["c_beak"].lightened(0.1), 0.4)
	if bk > 0.05:
		_box(head, Vector3(-hs * 0.1, hs * 0.18, hs * 0.72 + bk - 0.01), Vector3(hs * 0.2, hs * 0.1, bk * 0.35), s["c_beak"].darkened(0.12), 0.4)
	# Eyes
	var eye := hs * 0.2 if "big_eyes" in feats else hs * 0.15
	var eye_c := Color("#e8b030") if "big_eyes" in feats else C_INK
	if "face_disc" in feats:
		_box(head, Vector3(-hs * 0.5 - 0.005, -hs * 0.15, hs * 0.55), Vector3(hs * 1.01, hs * 0.85, 0.02), s["c_belly"])
	for side in [-1.0, 1.0]:
		var ex: float = side * hs * 0.5
		var eo: float = (0.0 if side > 0 else -0.01)
		if "face_disc" in feats:
			_box(head, Vector3(side * hs * 0.22 - eye * 0.5, hs * 0.25, hs * 0.55 + 0.015), Vector3(eye, eye, 0.01), eye_c)
			_box(head, Vector3(side * hs * 0.22 - eye * 0.25, hs * 0.25 + eye * 0.25, hs * 0.55 + 0.02), Vector3(eye * 0.5, eye * 0.5, 0.01), C_INK)
		else:
			# A warm iris ring round the pupil, and a glint.
			_box(head, Vector3(ex + eo - (0.001 if side < 0 else 0.0), hs * 0.33, hs * 0.33), Vector3(0.011, eye * 1.25, eye * 1.25),
				Color("#c9822a") if str(s["move"]) == "walk" else eye_c, 0.25)
			_box(head, Vector3(ex + eo * 1.2 + (0.002 if side > 0 else -0.002), hs * 0.36, hs * 0.36), Vector3(0.011, eye * 0.8, eye * 0.8), eye_c, 0.2)
			_box(head, Vector3(ex + eo * 1.6 + (0.004 if side > 0 else -0.004), hs * 0.35 + eye * 0.6, hs * 0.35 + eye * 0.6),
				Vector3(0.008, eye * 0.35, eye * 0.35), C_CREAM, 0.15)
	if "earlobe" in feats:
		for side in [-1.0, 1.0]:
			_box(head, Vector3(side * hs * 0.5 - (0.0 if side > 0 else 0.008), -hs * 0.12, hs * 0.1), Vector3(0.008, hs * 0.22, hs * 0.2),
				Color("#efe8dc"), 0.7)
	if "comb" in feats:
		# A serrated comb: a base strip with five points of uneven height, and
		# the whole thing running from the beak back over the crown.
		var comb := Color("#d4382f")
		_box(head, Vector3(-hs * 0.06, hs * 0.7, -hs * 0.05), Vector3(hs * 0.12, hs * 0.14, hs * 0.85), comb, 0.45)
		for i in 4:
			_box(head, Vector3(-hs * 0.06, hs * 0.84, hs * 0.0 + i * hs * 0.2),
				Vector3(hs * 0.12, hs * (0.22 - (i % 2) * 0.08), hs * 0.14), comb.lightened(0.06), 0.45)
	if "wattle" in feats:
		_box(head, Vector3(-hs * 0.1, -hs * 0.4, hs * 0.58), Vector3(hs * 0.2, hs * 0.3, hs * 0.1), Color("#d4382f"), 0.45)

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
			# A darker leading edge and a row of paler covert feathers.
			_box(w, Vector3(origin_x, -0.006, chord * 0.35), Vector3(half, 0.03, chord * 0.12), s["c_wing"].darkened(0.18))
			_box(w, Vector3(origin_x, 0.0, -chord * 0.1), Vector3(half * 0.6, 0.028, chord * 0.2), s["c_wing"].lightened(0.1))
			# Primaries: long separate feathers at the tip, with gaps between.
			for k in 4:
				var px := (half * 0.6 + k * half * 0.1) if side > 0 else -(half * 0.6 + k * half * 0.1) - half * 0.1
				_box(w, Vector3(px, -0.01, -chord * 0.55 - 0.02 - (k % 2) * 0.02), Vector3(half * 0.09, 0.02, chord * 0.5),
					s["c_wing"].darkened(0.1 + 0.03 * k))
			if "black_wingtips" in feats:
				var tip_x := (half - half * 0.22) if side > 0 else -half
				_box(w, Vector3(tip_x, -0.014, -chord * 0.58), Vector3(half * 0.22, 0.028, chord * 0.86), s["c_wingtip"])
			if "speculum" in feats:
				var sx := (half * 0.4) if side > 0 else (-half * 0.6)
				_box(w, Vector3(sx, 0.012, -chord * 0.35), Vector3(half * 0.2, 0.01, chord * 0.3), Color("#2b4c9c"))
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
		var panel := BoxKit.add(torso, Vector3(x0, b.y * 0.28, -b.z * 0.42), Vector3(0.02, b.y * 0.5, b.z * 0.74), s["c_wing"])
		folded.append(panel)
		# Layered feather rows stepping down and back, lightest on top.
		var shoulder := BoxKit.add(torso, Vector3(x0 + (0.002 if side > 0 else -0.004), b.y * 0.5, -b.z * 0.2),
			Vector3(0.024, b.y * 0.3, b.z * 0.5), s["c_wing"].lightened(0.08))
		folded.append(shoulder)
		var quills := BoxKit.add(torso, Vector3(x0 + (0.002 if side > 0 else -0.004), b.y * 0.26, -b.z * 0.5),
			Vector3(0.024, b.y * 0.22, b.z * 0.3), s["c_wing"].darkened(0.14))
		folded.append(quills)
		if "black_wingtips" in feats:
			var tip := BoxKit.add(torso, Vector3(x0 - 0.002, b.y * 0.3, -b.z * 0.44), Vector3(0.024, b.y * 0.3, b.z * 0.16), s["c_wingtip"])
			folded.append(tip)
		if "speculum" in feats:
			var sp := BoxKit.add(torso, Vector3(x0 - 0.002, b.y * 0.42, -b.z * 0.2), Vector3(0.024, b.y * 0.16, b.z * 0.22), Color("#2b4c9c"))
			folded.append(sp)
	out["folded"] = folded

	# Legs: a thigh feathered into the body, a bare shank, and three toes
	# forward with a spur behind.
	var legs: Array = []
	var ll: float = s["legs"]
	for side in [-1.0, 1.0]:
		var n := Node3D.new()
		n.position = Vector3(side * b.x * 0.22, stand, b.z * 0.02)
		root.add_child(n)
		_box(n, Vector3(-0.016, -ll * 0.3, -0.02), Vector3(0.032, ll * 0.34, 0.04), c_body.darkened(0.04))
		_box(n, Vector3(-0.011, -ll, -0.011), Vector3(0.022, ll * 0.74, 0.022), s["c_leg"], 0.5)
		var toe := maxf(ll * 0.35, 0.05)
		_box(n, Vector3(-0.012, -ll, 0.0), Vector3(0.024, 0.01, toe), s["c_leg"], 0.5)
		_box(n, Vector3(-0.03, -ll, 0.0), Vector3(0.022, 0.01, toe * 0.8), s["c_leg"], 0.5)
		_box(n, Vector3(0.008, -ll, 0.0), Vector3(0.022, 0.01, toe * 0.8), s["c_leg"], 0.5)
		_box(n, Vector3(-0.01, -ll, -0.035), Vector3(0.02, 0.01, 0.04), s["c_leg"], 0.5)
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
	# A lateral line and a pale flank, a gill cover behind the eye, a mouth and
	# a lower fin pair: the details that make a block a fish.
	for side in [-1.0, 1.0]:
		var fx: float = (Wd * 0.5 - 0.003) if side > 0.0 else (-Wd * 0.5 - 0.005)
		_box(torso, Vector3(fx, -D * 0.02, -L * 0.28), Vector3(0.008, D * 0.05, L * 0.62), back.lightened(0.18), 0.5)
		_box(torso, Vector3(fx, -D * 0.34, -L * 0.2), Vector3(0.008, D * 0.26, L * 0.5), belly.lerp(back, 0.15), 0.55)
		var gx: float = (Wd * 0.5 - 0.002) if side > 0.0 else (-Wd * 0.5 - 0.006)
		_box(torso, Vector3(gx, -D * 0.38, L * 0.27), Vector3(0.008, D * 0.8, L * 0.035), back.darkened(0.3), 0.5)
		if "scales" in feats:
			for i in 6:
				for j in 2:
					_box(torso, Vector3(fx, D * (0.12 - j * 0.2), -L * 0.26 + i * L * 0.08 + (j % 2) * L * 0.04),
						Vector3(0.008, D * 0.14, L * 0.045), back.lightened(0.12 if (i + j) % 2 == 0 else -0.0), 0.45)
	_box(torso, Vector3(-Wd * 0.3, -D * 0.12, L * 0.5 - 0.004), Vector3(Wd * 0.6, D * 0.1, 0.01), C_INK, 0.5)
	for side in [-1.0, 1.0]:
		var q := Node3D.new()
		q.position = Vector3(side * Wd * 0.3, -D * 0.5, L * 0.0)
		q.rotation.x = 0.0
		torso.add_child(q)
		_box(q, Vector3(-0.005, -D * 0.2, -L * 0.04), Vector3(0.01, D * 0.2, L * 0.08), s["c_fin"], 0.6)
	_box(torso, Vector3(-0.005, -D * 0.5 - D * 0.18, -L * 0.22), Vector3(0.01, D * 0.2, L * 0.1), s["c_fin"], 0.6)
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
	# Forked: two lobes off a narrow stalk.
	_box(tailfin, Vector3(-0.006, -D * 0.1, -L * 0.1), Vector3(0.012, D * 0.2, L * 0.1), s["c_tail"], 0.6)
	_box(tailfin, Vector3(-0.006, D * 0.02, -L * 0.24), Vector3(0.012, D * 0.46, L * 0.15), s["c_tail"], 0.6)
	_box(tailfin, Vector3(-0.006, -D * 0.48, -L * 0.24), Vector3(0.012, D * 0.46, L * 0.15), s["c_tail"].darkened(0.06), 0.6)
	_box(tailfin, Vector3(-0.006, -D * 0.3, -L * 0.12), Vector3(0.012, D * 0.6, L * 0.06), s["c_tail"].lightened(0.05), 0.6)
	_box(tailfin, Vector3(-0.005, -D * 0.2, -L * 0.1), Vector3(0.01, D * 0.4, L * 0.1), back)
	return out
