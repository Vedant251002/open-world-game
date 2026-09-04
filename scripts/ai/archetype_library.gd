extends RefCounted
class_name ArchetypeLibrary
## Cached archetype specs, per game-design-doc.md §5.4 and §13.
##
## Two jobs. It is the offline fallback — with no key, no network, or a model
## that has produced two bad outputs in a row, the game degrades instead of
## breaking. And it is the cache: a spec is keyed by
## hash(archetype, tier, plot_class, preference_fingerprint), so popular
## buildings stop hitting the API entirely.

const BASE := {
	"hut": {
		"footprint": [7, 6], "stories": 1, "roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "small", "priority": "required"},
			{"type": "bed_area", "wall": "left", "size": "medium", "priority": "preferred"},
			{"type": "storage", "wall": "right", "size": "small", "priority": "optional"},
		],
	},
	"cottage": {
		"footprint": [9, 7], "stories": 1, "roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "medium", "priority": "required"},
			{"type": "bed_area", "wall": "left", "size": "medium", "priority": "required"},
			{"type": "storage", "wall": "right", "size": "small", "priority": "preferred"},
		],
	},
	"bakery": {
		"footprint": [11, 9], "stories": 1, "roof": "gable",
		"materials": {"walls": "plank", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "oven", "wall": "back", "size": "medium", "needs": ["chimney"],
				"adjacent_to": "storage", "priority": "required"},
			{"type": "counter", "wall": "front", "size": "medium", "priority": "required"},
			{"type": "storage", "wall": "right", "size": "small", "priority": "preferred"},
			{"type": "seating", "wall": "left", "size": "medium", "priority": "optional"},
		],
		"sign": "BREAD",
	},
	"workshop": {
		"footprint": [10, 9], "stories": 1, "roof": "shed",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "gravel"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "workbench", "wall": "right", "size": "large", "priority": "required"},
			{"type": "storage", "wall": "back", "size": "medium", "priority": "preferred"},
		],
		"sign": "WORKSHOP",
	},
	"store": {
		"footprint": [9, 8], "stories": 1, "roof": "gable",
		"materials": {"walls": "sandstone", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "counter", "wall": "front", "size": "medium", "priority": "required"},
			{"type": "storage", "wall": "back", "size": "large", "priority": "required"},
		],
		"sign": "STORE",
	},
	"tavern": {
		"footprint": [13, 10], "stories": 2, "roof": "hip",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "story": "ground", "priority": "required"},
			{"type": "seating", "story": "ground", "size": "large", "priority": "required"},
			{"type": "hearth", "wall": "back", "story": "ground", "size": "medium",
				"priority": "required"},
			{"type": "counter", "wall": "left", "story": "ground", "size": "medium",
				"priority": "preferred"},
			{"type": "bed_area", "story": "top", "size": "medium", "priority": "preferred"},
		],
		"sign": "THE REST",
	},
	"barn": {
		"footprint": [12, 9], "stories": 1, "roof": "gable",
		"materials": {"walls": "plank", "roof": "thatch", "trim": "dark_oak",
			"foundation": "gravel"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "storage", "size": "large", "priority": "required"},
			{"type": "stable", "wall": "back", "size": "large", "priority": "preferred"},
		],
	},
	"stable": {
		"footprint": [11, 8], "stories": 1, "roof": "shed",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "gravel"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "stable", "size": "large", "needs": ["road_access"], "priority": "required"},
			{"type": "storage", "wall": "back", "size": "small", "priority": "preferred"},
		],
	},
	"smokehouse": {
		"footprint": [7, 7], "stories": 1, "roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "medium", "needs": ["chimney"],
				"priority": "required"},
			{"type": "storage", "wall": "left", "size": "small", "priority": "preferred"},
		],
	},
	"guard_post": {
		"footprint": [6, 6], "stories": 1, "roof": "hip",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "window_bank", "wall": "front", "size": "medium", "priority": "preferred"},
			{"type": "storage", "wall": "back", "size": "small", "priority": "optional"},
		],
	},
	"shrine": {
		"footprint": [7, 7], "stories": 1, "roof": "hip",
		"materials": {"walls": "sandstone", "roof": "clay_tile", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "small", "priority": "preferred"},
		],
	},
	"well_house": {
		"footprint": [6, 6], "stories": 1, "roof": "hip",
		"materials": {"walls": "cobble", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "well", "wall": "centre", "size": "small", "needs": ["water"],
				"priority": "required"},
		],
	},
}

## Words a player is likely to use, mapped onto an archetype we can actually
## build. This is the offline path only — the model does its own mapping.
const KEYWORDS := {
	"hut": "hut", "shack": "hut", "cabin": "hut", "house": "cottage",
	"home": "cottage", "cottage": "cottage", "dwelling": "cottage",
	"bakery": "bakery", "baker": "bakery", "bread": "bakery",
	"workshop": "workshop", "shop": "store", "store": "store",
	"market": "store", "smithy": "workshop", "forge": "workshop",
	"tavern": "tavern", "inn": "tavern", "pub": "tavern", "alehouse": "tavern",
	"barn": "barn", "granary": "barn", "stable": "stable", "stables": "stable",
	"smokehouse": "smokehouse", "guard": "guard_post", "watch": "guard_post",
	"tower": "guard_post", "shrine": "shrine", "temple": "shrine",
	"chapel": "shrine", "well": "well_house",
}

static var _cache: Dictionary = {}


static func guess_archetype(instruction: String) -> String:
	var text := instruction.to_lower()
	for word: String in KEYWORDS:
		if text.find(word) >= 0:
			return KEYWORDS[word]
	return "hut"


## The offline plan. It still produces assumptions, because a building with no
## visible reasoning behind it is the one thing the design forbids.
static func fallback(instruction: String, mem: WorkerMemory, plot: Plot,
		tier: int) -> Dictionary:
	var arch := guess_archetype(instruction)
	var spec := (BASE.get(arch, BASE["hut"]) as Dictionary).duplicate(true)
	spec["kind"] = "building"
	spec["archetype"] = arch
	spec["orientation"] = "face_street"
	if not spec.has("sign"):
		spec["sign"] = ""
	_fit_to_plot(spec, plot)
	_apply_preferences(spec, mem)

	var assumptions: Array = [
		"You did not say which way it should face, so I put the door toward %s."
			% plot.street_word(),
	]
	if instruction.to_lower().find("big") < 0 and instruction.to_lower().find("small") < 0:
		assumptions.append("You did not say how big, so I built it the usual size for a %s."
			% arch.replace("_", " "))
	for p: Dictionary in mem.learned_preferences:
		if float(p["weight"]) > 0.5:
			assumptions.append("I went with what you usually want: %s." % str(p["text"]))
			break

	return {
		"kind": "plan",
		"spec": spec,
		"assumptions": assumptions,
		"confidence": 0.45,
		"worker_line": "I will use the standard plan for that.",
		"cost_estimate": {},
		"source": "fallback",
	}


static func _fit_to_plot(spec: Dictionary, plot: Plot) -> void:
	var m := plot.size_m()
	var avail := Vector2(m.x, m.y)
	if plot.street_dir.x != 0:
		avail = Vector2(m.y, m.x)
	var fp: Array = spec["footprint"]
	spec["footprint"] = [
		int(minf(float(fp[0]), avail.x - 2.0)),
		int(minf(float(fp[1]), avail.y - 2.0)),
	]


static func _apply_preferences(spec: Dictionary, mem: WorkerMemory) -> void:
	for p: Dictionary in mem.learned_preferences:
		if float(p["weight"]) < 0.4:
			continue
		var t := str(p["text"]).to_lower()
		if t.find("flat roof") >= 0 and t.find("dislike") >= 0 and spec["roof"] == "flat":
			spec["roof"] = "gable"
		if t.find("plaza") >= 0 and t.find("door") >= 0:
			spec["orientation"] = "face_plaza"
		for mat_name: String in VoxelTypes.NAMES:
			if t.find(mat_name) >= 0 and t.find("like") >= 0 \
					and mat_name in VoxelTypes.STRUCTURAL:
				(spec["materials"] as Dictionary)["walls"] = mat_name


# ------------------------------------------------------------------- caching

## hash(archetype, tier, plot_class, preference_fingerprint), per §5.4.
static func cache_key(archetype: String, tier: int, plot: Plot,
		mem: WorkerMemory) -> String:
	var fingerprint: Array[String] = []
	var sorted := mem.learned_preferences.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["text"]) < str(b["text"]))
	for p: Dictionary in sorted:
		if float(p["weight"]) > 0.4:
			fingerprint.append(str(p["text"]))
	var plot_class := "%dx%d/%s" % [
		int(plot.size_m().x / 4.0), int(plot.size_m().y / 4.0), plot.street_word()]
	return "%s|t%d|%s|%s|%d" % [archetype, tier, plot_class,
		"&".join(fingerprint), DetRng.hash_text(mem.worker_id) % 97]


static func cached(key: String) -> Dictionary:
	return _cache.get(key, {})


static func store(key: String, plan: Dictionary) -> void:
	_cache[key] = plan.duplicate(true)


static func cache_size() -> int:
	return _cache.size()


static func clear_cache() -> void:
	_cache.clear()
