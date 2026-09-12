extends RefCounted
class_name Arsenal
## Everything that shoots, explodes or is loaded into something that does.
##
## Two tables. WEAPONS is what a hand holds and how it behaves — a rifle is a
## fast, flat, accurate shot with a slow reload; a mortar lobs a shell that
## comes down somewhere near where it was pointed; a launcher sends a rocket
## that steers itself. ITEMS is what the armoury makes, out of what, and how
## long it takes: powder from charcoal and sand, shot from steel, and the guns
## themselves from steel and timber.
##
## The chain is deliberately short. Iron comes out of the ore seam by the
## existing errand and becomes steel frame in the stores; the armoury turns
## that and timber into a musket. There is no separate barrel, stock and lock,
## because a crafting tree with intermediate goods is a second game bolted
## onto this one, and the only decision that matters is "do we have the steel".
##
## Numbers are metres, seconds and metres per second. A musket ball really
## does leave the muzzle at four or five hundred metres a second; here it is
## sixty-five, because at real speed you cannot see it and the physics of it
## is the point.

## kind -> how it fires. "ammo" is the ITEMS key it consumes per shot; a
## grenade is its own ammunition.
const WEAPONS := {
	"pistol": {
		"ammo": "shot", "speed": 55.0, "damage": 24.0, "reload": 0.9,
		"spread": 3.0, "range": 26.0, "projectile": "bullet", "hands": 1,
		"label": "pistol",
	},
	"musket": {
		"ammo": "shot", "speed": 65.0, "damage": 42.0, "reload": 3.2,
		"spread": 2.4, "range": 48.0, "projectile": "bullet", "hands": 2,
		"label": "musket",
	},
	"rifle": {
		"ammo": "shot", "speed": 92.0, "damage": 48.0, "reload": 1.7,
		"spread": 0.9, "range": 75.0, "projectile": "bullet", "hands": 2,
		"label": "rifle",
	},
	"grenade": {
		"ammo": "grenade", "speed": 15.0, "damage": 0.0, "reload": 1.4,
		"spread": 4.0, "range": 22.0, "projectile": "grenade", "hands": 1,
		"blast": 3.6, "power": 75.0, "fuse": 2.8, "label": "grenades",
	},
	"mortar": {
		"ammo": "shell", "speed": 46.0, "damage": 0.0, "reload": 6.0,
		"spread": 3.5, "range": 110.0, "projectile": "shell", "hands": 2,
		"blast": 4.5, "power": 115.0, "label": "mortar",
	},
	"launcher": {
		"ammo": "rocket", "speed": 18.0, "damage": 0.0, "reload": 5.0,
		"spread": 1.0, "range": 140.0, "projectile": "rocket", "hands": 2,
		"blast": 5.5, "power": 150.0, "label": "launcher",
	},
}

## key -> what the armoury makes in one batch, from what, in how many hours.
## "kind" says whether it is a weapon, ammunition or a stage in between.
const ITEMS := {
	"powder": {
		"kind": "stuff", "batch": 10, "hours": 1.0,
		"from": {"timber": 6, "sand": 4},
		"label": "powder", "price": 6,
	},
	"shot": {
		"kind": "ammo", "batch": 24, "hours": 0.8,
		"from": {"steel_frame": 3},
		"label": "shot", "price": 3,
	},
	"grenade": {
		"kind": "ammo", "batch": 4, "hours": 1.2,
		"from": {"powder": 4, "brick": 2},
		"label": "grenades", "price": 22,
	},
	"shell": {
		"kind": "ammo", "batch": 4, "hours": 1.5,
		"from": {"powder": 6, "steel_frame": 4},
		"label": "shells", "price": 30,
	},
	"rocket": {
		"kind": "ammo", "batch": 2, "hours": 2.0,
		"from": {"powder": 8, "steel_frame": 4, "glass": 1},
		"label": "rockets", "price": 70,
	},
	"pistol": {
		"kind": "weapon", "batch": 1, "hours": 1.5,
		"from": {"steel_frame": 3, "timber": 1},
		"label": "pistol", "price": 90,
	},
	"musket": {
		"kind": "weapon", "batch": 1, "hours": 2.0,
		"from": {"steel_frame": 4, "timber": 3},
		"label": "musket", "price": 140,
	},
	"rifle": {
		"kind": "weapon", "batch": 1, "hours": 3.0,
		"from": {"steel_frame": 6, "timber": 3},
		"label": "rifle", "price": 220,
	},
	"mortar": {
		"kind": "weapon", "batch": 1, "hours": 5.0,
		"from": {"steel_frame": 12, "cobble": 4},
		"label": "mortar", "price": 600,
	},
	"launcher": {
		"kind": "weapon", "batch": 1, "hours": 5.0,
		"from": {"steel_frame": 10, "glass": 2},
		"label": "rocket launcher", "price": 800,
	},
}

## What a player calls a thing, mapped onto an ITEMS key.
const WORDS := {
	"powder": "powder", "gunpowder": "powder", "black powder": "powder",
	"shot": "shot", "bullet": "shot", "bullets": "shot", "ball": "shot",
	"balls": "shot", "musket balls": "shot", "ammo": "shot", "ammunition": "shot",
	"rounds": "shot", "cartridges": "shot",
	"grenade": "grenade", "grenades": "grenade", "bomb": "grenade", "bombs": "grenade",
	"shell": "shell", "shells": "shell", "mortar shells": "shell",
	"rocket": "rocket", "rockets": "rocket", "missile": "rocket", "missiles": "rocket",
	"pistol": "pistol", "pistols": "pistol", "handgun": "pistol", "handguns": "pistol",
	"musket": "musket", "muskets": "musket",
	"rifle": "rifle", "rifles": "rifle", "gun": "rifle", "guns": "rifle",
	"mortar": "mortar", "mortars": "mortar", "cannon": "mortar", "cannons": "mortar",
	"artillery": "mortar",
	"launcher": "launcher", "launchers": "launcher", "rocket launcher": "launcher",
	"bazooka": "launcher", "missile launcher": "launcher",
}


static func is_weapon(key: String) -> bool:
	return WEAPONS.has(key)


static func is_item(key: String) -> bool:
	return ITEMS.has(key)


static func weapon(key: String) -> Dictionary:
	return WEAPONS.get(key, {})


static func item(key: String) -> Dictionary:
	return ITEMS.get(key, {})


static func label(key: String) -> String:
	if ITEMS.has(key):
		return str(ITEMS[key]["label"])
	return key.replace("_", " ")


## The item named in a sentence, or "". Longest phrase first so "rocket
## launcher" is a launcher and not a rocket.
static func find_in(text: String) -> String:
	var t := " " + text.to_lower().strip_edges() + " "
	var keys: Array = WORDS.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for w: String in keys:
		if t.find(" " + w + " ") >= 0:
			return str(WORDS[w])
	return ""


## The stock keys the armoury deals in, weapons first, in a sensible order.
static func all_keys() -> PackedStringArray:
	return PackedStringArray(["pistol", "musket", "rifle", "grenade", "mortar",
		"launcher", "shot", "shell", "rocket", "powder"])


## What one batch costs, as a bill the stores can be asked about.
static func bill(key: String, batches: int) -> Dictionary:
	var out := {}
	var it := item(key)
	for mat: String in it.get("from", {}):
		out[mat] = int(it["from"][mat]) * batches
	return out


## "20 shot" -> how many batches to make, rounded up.
static func batches_for(key: String, count: int) -> int:
	var b := int(item(key).get("batch", 1))
	return maxi(int(ceil(float(count) / float(b))), 1)
