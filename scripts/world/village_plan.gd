extends RefCounted
class_name VillagePlan
## What the town is founded with: the essentials and nothing more.
##
## Three households and the trades that keep them. Each of the three people
## you start with lives in a house of their own with their partner, and each
## partner has somewhere to work. The rest of the plots stay empty on purpose:
## building is the game, and a town that arrives finished has nothing left to
## ask anybody for.
##
##   - the tavern on the square, where the evenings happen (Anselm keeps it);
##   - the store, which is Mira's;
##   - the bakery, which is Greta's;
##   - the workshop, Tobias's yard;
##   - the barn, beside Ren's fields, which Lena looks after;
##   - three houses, one per couple.
##
## Ordered by how central each should be: the plots are filled nearest the
## well first, so the trades face the square and the homes sit behind them.

## The couples. The first of each pair is one of the founding crew; the second
## is their partner, who lives in the town rather than working for you.
const HOUSEHOLDS := {
	"tobias": ["tobias", "greta"],
	"ren": ["ren", "lena"],
	"mira": ["mira", "anselm"],
}

## Where each partner works by day. Matched to a building by archetype.
const WORKPLACE := {
	"greta": "bakery",
	"lena": "barn",
	"anselm": "tavern",
	"mira": "store",
	"tobias": "workshop",
	"ren": "barn",
}


static func specs() -> Array[Dictionary]:
	return [
		{
			"kind": "building", "archetype": "tavern", "tech_tier": 1,
			"footprint": [18, 14], "stories": 2, "orientation": "face_plaza",
			"roof": "hip",
			"materials": {"walls": "timber", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "entrance", "wall": "front", "story": "ground",
					"size": "small", "priority": "required"},
				{"type": "seating", "story": "ground", "size": "large", "priority": "required"},
				{"type": "counter", "wall": "left", "story": "ground",
					"size": "medium", "priority": "required"},
				{"type": "hearth", "wall": "back", "story": "ground",
					"size": "medium", "priority": "required"},
				{"type": "bed_area", "story": "top", "size": "medium", "priority": "preferred"},
				{"type": "storage", "story": "top", "size": "small", "priority": "optional"},
			],
			"sign": "THE LONG REST",
		},
		{
			"kind": "building", "archetype": "store", "tech_tier": 1,
			"footprint": [13, 12], "stories": 1, "orientation": "face_plaza",
			"roof": "gable",
			"materials": {"walls": "sandstone", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "counter", "wall": "front", "size": "large", "priority": "required"},
				{"type": "storage", "wall": "back", "size": "medium", "priority": "required"},
			],
			"sign": "STORE",
		},
		{
			"kind": "building", "archetype": "bakery", "tech_tier": 1,
			"footprint": [14, 12], "stories": 1, "orientation": "face_plaza",
			"roof": "gable",
			"materials": {"walls": "plank", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "counter", "wall": "front", "size": "medium", "priority": "required"},
				{"type": "oven", "wall": "back", "size": "medium",
					"needs": ["chimney"], "adjacent_to": "storage", "priority": "required"},
				{"type": "storage", "wall": "right", "size": "small", "priority": "preferred"},
			],
			"sign": "BREAD",
		},
		{
			"kind": "building", "archetype": "workshop", "tech_tier": 1,
			"footprint": [14, 12], "stories": 1, "orientation": "face_plaza",
			"roof": "shed",
			"materials": {"walls": "timber", "roof": "thatch",
				"trim": "dark_oak", "foundation": "gravel"},
			"modules": [
				{"type": "workbench", "wall": "back", "size": "large", "priority": "required"},
				{"type": "storage", "wall": "right", "size": "small", "priority": "preferred"},
			],
			"sign": "WORKSHOP",
		},
		_house("tobias", "granite", "TOBIAS & GRETA", [12, 10]),
		_house("ren", "timber", "REN & LENA", [12, 10]),
		_house("mira", "plank", "MIRA & ANSELM", [12, 10]),
		{
			"kind": "building", "archetype": "barn", "tech_tier": 1,
			"footprint": [14, 11], "stories": 1, "orientation": "face_street",
			"roof": "gable",
			"materials": {"walls": "plank", "roof": "thatch",
				"trim": "dark_oak", "foundation": "gravel"},
			"modules": [
				{"type": "stable", "wall": "back", "size": "large", "priority": "required"},
				{"type": "storage", "wall": "left", "size": "small", "priority": "preferred"},
			],
			"sign": "",
		},
	]


## A home for two: the kitchen with the fire in it, the bedroom, and a pantry.
## The front door opens into the kitchen, which is how a cottage is entered.
static func _house(owner: String, walls: String, sign: String, fp: Array) -> Dictionary:
	return {
		"kind": "building", "archetype": "cottage", "tech_tier": 1,
		"footprint": fp, "stories": 1, "orientation": "face_street",
		"roof": "gable",
		"materials": {"walls": walls, "roof": "thatch",
			"trim": "dark_oak", "foundation": "cobble"},
		"modules": [
			{"type": "hearth", "wall": "front", "size": "large", "priority": "required"},
			{"type": "bed_area", "wall": "back", "size": "medium", "priority": "required"},
			{"type": "storage", "wall": "back", "size": "small", "priority": "optional"},
		],
		"sign": sign,
		"household": owner,
	}
