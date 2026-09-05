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
	"apartment": {
		"footprint": [13, 11], "stories": 3, "roof": "flat",
		"materials": {"walls": "brick", "roof": "clay_tile", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "stairwell", "wall": "centre", "priority": "required"},
			{"type": "bed_area", "story": "top", "size": "medium", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "small", "needs": ["chimney"],
				"priority": "preferred"},
			{"type": "storage", "wall": "right", "size": "small", "priority": "optional"},
		],
	},
	"tower_block": {
		"footprint": [13, 13], "stories": 6, "roof": "flat",
		"materials": {"walls": "concrete", "roof": "concrete", "trim": "steel_frame",
			"foundation": "rebar_concrete"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "stairwell", "wall": "centre", "priority": "required"},
			{"type": "bed_area", "story": "top", "size": "large", "priority": "required"},
			{"type": "office", "size": "medium", "priority": "preferred"},
			{"type": "storage", "size": "small", "priority": "optional"},
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
## Words to archetypes, longest first so "tower block" beats "tower".
##
## This table is not a nicety on the shipped build — it is the only brain
## there is when no API key is present, which is every exported build. A
## word missing from here does not degrade gracefully: it silently becomes
## a hut, which is how asking for a ten-floor apartment produced a shed.
const KEYWORDS := {
	"tower block": "tower_block", "apartment block": "apartment",
	"aircraft hangar": "aircraft_hangar", "control tower": "control_tower",
	"fire station": "fire_station", "market hall": "market_hall",
	"power house": "power_house", "guard post": "guard_post",
	"well house": "well_house",
	"apartment": "apartment", "apartments": "apartment", "flat": "apartment",
	"flats": "apartment", "tenement": "apartment", "block of": "apartment",
	"skyscraper": "tower_block", "highrise": "tower_block",
	"high rise": "tower_block", "tower": "tower_block",
	"airport": "aircraft_hangar", "hangar": "aircraft_hangar",
	"airfield": "aircraft_hangar", "terminal": "aircraft_hangar",
	"runway": "aircraft_hangar", "aerodrome": "aircraft_hangar",
	"factory": "fabrication_plant", "plant": "fabrication_plant",
	"reactor": "reactor_house", "laboratory": "clean_lab", "lab": "clean_lab",
	"warehouse": "warehouse", "depot": "depot", "garage": "garage",
	"office": "office", "library": "library", "school": "school",
	"clinic": "clinic", "hospital": "clinic", "station": "station",
	"mill": "mill", "brickworks": "brickworks", "foundry": "foundry",
	"pottery": "pottery", "tannery": "tannery",
	"hut": "hut", "shack": "hut", "cabin": "hut", "house": "cottage",
	"home": "cottage", "cottage": "cottage", "dwelling": "cottage",
	"bakery": "bakery", "baker": "bakery", "bread": "bakery",
	"workshop": "workshop", "smithy": "workshop", "forge": "forge",
	"shop": "store", "store": "store", "market": "store",
	"tavern": "tavern", "inn": "inn", "pub": "tavern", "alehouse": "tavern",
	"barn": "barn", "granary": "granary", "stable": "stable",
	"stables": "stable", "smokehouse": "smokehouse",
	"guard": "guard_post", "watch": "guard_post",
	"shrine": "shrine", "temple": "shrine", "chapel": "shrine",
	"well": "well_house",
}

## Number words, for "a ten floor building". Digits are read directly.
const NUMBER_WORDS := {
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
	"seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
	"twelve": 12, "single": 1, "double": 2, "triple": 3,
}

static var _cache: Dictionary = {}


static func guess_archetype(instruction: String) -> String:
	var text := instruction.to_lower()
	# Longest match wins, so "tower block" is not read as "tower" and an
	# "apartment block" is not read as a "block of".
	var best := ""
	var best_len := 0
	for word: String in KEYWORDS:
		if word.length() > best_len and text.find(word) >= 0:
			best = KEYWORDS[word]
			best_len = word.length()
	return best if best != "" else "hut"


## How many floors the instruction asked for, or 0 if it did not say.
##
## Reads the number next to floor/storey, so "a ten floor building" and
## "3-storey" both land. Ignoring this was how a request for ten floors
## came back as one.
static func floors_in(instruction: String) -> int:
	var text := instruction.to_lower().replace("-", " ").replace(",", " ")
	var words := text.split(" ", false)
	for i in words.size():
		var w := String(words[i])
		if not (w.begins_with("floor") or w.begins_with("stor")
				or w.begins_with("level")):
			continue
		# The count sits just before the word, as a digit or as English.
		for back in range(1, 3):
			var j := i - back
			if j < 0:
				break
			var n := String(words[j])
			if n.is_valid_int():
				return clampi(int(n), 1, 40)
			if NUMBER_WORDS.has(n):
				return int(NUMBER_WORDS[n])
	return 0


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
	# Honour what the instruction actually asked for. The clamp is deliberate
	# and only downward to the range the generator can build: exceeding what
	# the TIER allows is not clamped here at all, because the validator
	# refuses it and the worker says why, which is the useful answer.
	var asked := floors_in(instruction)
	if asked > 0:
		spec["stories"] = asked
	var text := instruction.to_lower()
	var fp: Array = spec["footprint"]
	if text.find("big") >= 0 or text.find("large") >= 0:
		spec["footprint"] = [float(fp[0]) * 1.35, float(fp[1]) * 1.35]
	elif text.find("small") >= 0 or text.find("tiny") >= 0 or text.find("little") >= 0:
		spec["footprint"] = [float(fp[0]) * 0.75, float(fp[1]) * 0.75]

	_fit_to_plot(spec, plot)
	_apply_preferences(spec, mem)
	var dropped := _trim_to_fit(spec)

	var assumptions: Array = [
		"You did not say which way it should face, so I put the door toward %s."
			% plot.street_word(),
	]
	if asked > 0:
		assumptions.append("You asked for %d floors, so that is what I planned."
			% asked)
	if not dropped.is_empty():
		assumptions.append("It would not all fit at that size, so I left out the %s."
			% " and the ".join(dropped))
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


## Drops rooms until the plan fits inside its own walls, and says which.
##
## A builder asked for something small does not refuse; they leave the
## storeroom out and mention it. Without this, "build a small bakery" came
## back as a refusal about floor area, which is arithmetic the player never
## asked to be involved in. Required rooms are never dropped — if those
## alone will not fit then the request really is impossible and the
## validator should say so.
static func _trim_to_fit(spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var fp: Array = spec["footprint"]
	var envelope := float(fp[0]) * float(fp[1]) * float(int(spec.get("stories", 1)))
	for pass_priority: String in ["optional", "preferred"]:
		for _guard in 8:
			if _module_area(spec) <= envelope * 0.8:
				return out
			var cut := -1
			var mods: Array = spec.get("modules", [])
			for i in mods.size():
				if str((mods[i] as Dictionary).get("priority", "preferred")) == pass_priority:
					cut = i
			if cut < 0:
				break
			var gone := str((mods[cut] as Dictionary).get("type", "room"))
			out.append(gone.replace("_", " "))
			mods.remove_at(cut)
			# Anything that wanted to be beside the room we just removed no
			# longer wants anything. Leaving the reference behind made the
			# validator reject the plan for naming a room that is not in it.
			for m: Variant in mods:
				if str((m as Dictionary).get("adjacent_to", "")) == gone:
					(m as Dictionary).erase("adjacent_to")
	return out


static func _module_area(spec: Dictionary) -> float:
	var total := 0.0
	for m: Variant in spec.get("modules", []):
		total += Vocabulary.size_area(str((m as Dictionary).get("size", "medium")))
	return total


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
