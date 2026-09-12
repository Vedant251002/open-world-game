extends RefCounted
class_name ArchetypeLibrary
## Cached archetype specs, per game-design-doc.md §5.4 and §13.
##
## Two jobs. It is the offline fallback — with no key, no network, or a model
## that has produced two bad outputs in a row, the game degrades instead of
## breaking. And it is the cache: a spec is keyed by
## hash(archetype, tier, plot_class, preference_fingerprint), so popular
## buildings stop hitting the API entirely.

## Footprints are in metres, and they are deliberately generous. The town is
## laid out on thirty metre plots; a nine metre cottage on one of those looks
## less like a house than like something left there.
const BASE := {
	"hut": {
		"footprint": [11, 9], "stories": 1, "roof": "gable",
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
		"footprint": [18, 15], "stories": 3, "roof": "flat",
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
		"footprint": [18, 18], "stories": 6, "roof": "flat",
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
		"footprint": [13, 11], "stories": 1, "roof": "gable",
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
		"footprint": [16, 13], "stories": 1, "roof": "gable",
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
		"footprint": [15, 13], "stories": 1, "roof": "shed",
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
		"footprint": [14, 12], "stories": 1, "roof": "gable",
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
		"footprint": [19, 15], "stories": 2, "roof": "hip",
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
		"footprint": [18, 14], "stories": 1, "roof": "gable",
		"materials": {"walls": "plank", "roof": "thatch", "trim": "dark_oak",
			"foundation": "gravel"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "storage", "size": "large", "priority": "required"},
			{"type": "stable", "wall": "back", "size": "large", "priority": "preferred"},
		],
	},
	"stable": {
		"footprint": [16, 12], "stories": 1, "roof": "shed",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "gravel"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "stable", "size": "large", "needs": ["road_access"], "priority": "required"},
			{"type": "storage", "wall": "back", "size": "small", "priority": "preferred"},
		],
	},
	"smokehouse": {
		"footprint": [11, 10], "stories": 1, "roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "medium", "needs": ["chimney"],
				"priority": "required"},
			{"type": "storage", "wall": "left", "size": "small", "priority": "preferred"},
		],
	},
	"armoury": {
		"footprint": [15, 12], "stories": 1, "roof": "hip",
		"materials": {"walls": "sandstone", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "workbench", "wall": "back", "size": "large", "priority": "required"},
			{"type": "storage", "wall": "right", "size": "large", "priority": "required"},
			{"type": "counter", "wall": "front", "size": "medium", "priority": "preferred"},
		],
		"sign": "ARMOURY",
	},
	"barracks": {
		"footprint": [18, 12], "stories": 1, "roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "bed_area", "wall": "left", "size": "large", "priority": "required"},
			{"type": "bed_area", "wall": "right", "size": "large", "priority": "required"},
			{"type": "storage", "wall": "back", "size": "medium", "priority": "preferred"},
		],
		"sign": "BARRACKS",
	},
	"watchtower": {
		"footprint": [8, 8], "stories": 3, "roof": "hip",
		"materials": {"walls": "sandstone", "roof": "plank", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "stairwell", "wall": "centre", "priority": "required"},
			{"type": "window_bank", "wall": "front", "story": "top", "size": "medium",
				"priority": "required"},
		],
	},
	"guard_post": {
		"footprint": [9, 9], "stories": 1, "roof": "hip",
		"materials": {"walls": "timber", "roof": "thatch", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "window_bank", "wall": "front", "size": "medium", "priority": "preferred"},
			{"type": "storage", "wall": "back", "size": "small", "priority": "optional"},
		],
	},
	"shrine": {
		"footprint": [11, 11], "stories": 1, "roof": "hip",
		"materials": {"walls": "sandstone", "roof": "clay_tile", "trim": "dark_oak",
			"foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "hearth", "wall": "back", "size": "small", "priority": "preferred"},
		],
	},
	"well_house": {
		"footprint": [9, 9], "stories": 1, "roof": "hip",
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
	"ammunition shop": "armoury", "ammo shop": "armoury", "gun shop": "armoury",
	"weapon shop": "armoury", "weapons shop": "armoury", "arsenal": "armoury",
	"armoury": "armoury", "armory": "armoury", "magazine": "armoury",
	"barracks": "barracks", "garrison": "barracks", "army camp": "barracks",
	"watchtower": "watchtower", "watch tower": "watchtower", "lookout": "watchtower",
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


# -------------------------------------------------------------- land orders

## Word lists for the land verbs, and the offline planner's only way of hearing
## them.
##
## These used to live in Dispatcher, one branch each, ahead of the model. That
## was the wrong place for two reasons: they answered before the model got a
## look in, so an order with a fence AND hens in it was heard as only the hens;
## and they were not the offline planner, so the two paths could disagree about
## what an instruction meant.
##
## Here, they are what they always were — a crude planner for when there is no
## real one — and the real model composes freely without going through them.
const FIELD_WORDS := ["field", "farm", "plant", "sow", "crop", "wheat",
	"carrot", "garden", "plough", "plow", "allotment"]
const STOCK_WORDS := ["hen", "hens", "chicken", "chickens", "sheep", "cow",
	"cows", "cattle", "livestock", "poultry"]
const PEN_WORDS := ["pen", "coop", "cage", "fence", "enclosure", "paddock",
	"hutch", "sty"]


static func _has_word(text: String, words: Array) -> bool:
	var t := " %s " % text.to_lower().replace(",", " ").replace(".", " ")
	for w: String in words:
		if t.find(" %s " % w) >= 0:
			return true
	return false


## An order about the land rather than a building, as a step plan — or {} if
## this is not one.
##
## The composite case is the point. "Build a cage for the hens and put them in
## it" comes back here as two steps with the second pointing at the first,
## which is the same plan the model would have produced and the same plan the
## validator checks. Offline is a worse planner, not a different game.
static func land_plan(instruction: String, tier: int) -> Dictionary:
	var text := instruction.to_lower()
	var wants_pen := _has_word(text, PEN_WORDS)
	var wants_stock := _has_word(text, STOCK_WORDS)
	var wants_field := _has_word(text, FIELD_WORDS)
	if not (wants_pen or wants_stock or wants_field):
		return {}
	# A named building wins. "Build a barn for the cows" is a barn, and hearing
	# it as a pen because it said "cows" is exactly the mistake this replaces.
	if _names_a_building(text):
		return {}

	var steps: Array = []
	var assumptions: Array = []

	if wants_pen:
		var side := 8
		var deep := 6
		if _has_word(text, ["big", "large", "huge"]):
			side = 12
			deep = 10
		elif _has_word(text, ["small", "little", "tiny"]):
			side = 5
			deep = 4
		steps.append({"do": "enclose", "id": "pen", "size": [side, deep],
			"material": "timber", "gate": "worker_choice"})
		assumptions.append(
			"You did not say how big, so I fenced %d by %d metres in timber."
				% [side, deep])
		assumptions.append("I put the gate where there was room to stand.")

	if wants_field:
		var crop := "carrot" if text.find("carrot") >= 0 else "wheat"
		var m := 5
		if _has_word(text, ["big", "large", "huge"]):
			m = 9
		elif _has_word(text, ["small", "little", "tiny"]):
			m = 3
		steps.append({"do": "sow", "id": "field", "crop": crop, "size": [m, m]})
		assumptions.append("You did not say what to sow, so I put in %s." % crop
			if text.find(crop) < 0 else "Sowing %s, as you said." % crop)
		assumptions.append("You did not say how big, so I made it %d metres a side." % m)

	if wants_stock:
		var species := "hen"
		if _has_word(text, ["sheep"]):
			species = "sheep"
		elif _has_word(text, ["cow", "cows", "cattle"]):
			species = "cow"
		var count := 6 if species == "hen" else 4
		if _has_word(text, ["few"]):
			count = 3
		for token: String in text.replace(",", " ").split(" ", false):
			if token.is_valid_int():
				count = clampi(int(token), 1, Steps.COUNT_MAX)
				break
		var step := {"do": "stock", "species": species, "count": count}
		if wants_pen:
			step["into"] = "pen"
			assumptions.append("I put them in the pen rather than turning them loose.")
		else:
			assumptions.append("I turned them out where you were standing; "
				+ "they will not stray far.")
		steps.append(step)
		assumptions.append("You did not say how many, so I went for %d." % count)

	if steps.is_empty() or steps.size() > Steps.MAX_STEPS:
		return {}
	return {
		"kind": "plan",
		"steps": steps,
		"assumptions": assumptions,
		"confidence": 0.4,
		"worker_line": "Right — I know how that goes.",
		"cost_estimate": {},
		"source": "fallback",
	}


## Whether the instruction names an actual building, which outranks any land
## word in it.
##
## Whole words only, and a keyword that is also a land word decides nothing.
## "plant" is a fabrication plant in KEYWORDS and also the verb in "plant a big
## wheat field" — matching on the substring turned that order into a refusal
## about fabrication plants, which is a strange thing to be told when you asked
## for wheat.
static func _names_a_building(text: String) -> bool:
	for word: String in KEYWORDS:
		if _has_word(word, FIELD_WORDS) or _has_word(word, STOCK_WORDS) \
				or _has_word(word, PEN_WORDS):
			continue
		if _has_word(text, [word]):
			return true
	return false


# ------------------------------------------------------------------ roles

## Composing a role without a model: score every capability against the name
## and the description by its tags, keep the ones that scored, and give
## everybody go, wait and speak. Cruder than the model — it has no idea what
## a "night watchman" is beyond the words — but "shepherd" still comes out as
## stock, enclose, collect and follow, which is what an exported build with no
## key has to manage.
##
## Returns the same shape the model does, so the dispatcher does not care
## which composer answered. `character` is left empty: a paragraph written by
## a keyword matcher would be worse than none, and the planning prompt falls
## back to the builder's line when there is no character.
static func role_fallback(name: String, description: String) -> Dictionary:
	var text := "%s %s %s" % [name, name, description]
	var scores := Capabilities.match_description(text)
	var caps: Array = ["go", "wait", "speak"]
	# Highest score first, then by name so the same words give the same role.
	var ranked: Array = scores.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		if int(scores[a]) != int(scores[b]):
			return int(scores[a]) > int(scores[b])
		return a < b)
	for id: Variant in ranked:
		if caps.size() >= 9:
			break
		if str(id) not in caps:
			caps.append(str(id))
	# Nothing matched at all: a name nobody has heard of and no description.
	# They can still be taken on to run errands, which is honest, and the
	# roster will say the job is thin.
	return {
		"kind": "role",
		"name": name.strip_edges().to_lower(),
		"capabilities": caps,
		"character": "",
		"standing": "",
		"line": "I can do that, or near enough.",
	}


## An errand, offline: go somewhere, work a shift, walk a round, bring in the
## harvest, and the rest of what a hired person who is not a builder gets
## asked. Word patterns, because without a model that is all there is — and
## without this, "go to the well" fell through to the building planner and
## came back as a hut, which for a shepherd was then refused as not their
## trade. Two wrong answers to a four-word order.
const GO_WORDS := ["go to", "walk to", "head to", "get to", "go over to", "run to"]
const STATION_WORDS := ["work at", "shift at", "work the", "man the", "mind the",
	"run the", "work in", "keep the", "tend the", "serve at", "stand at"]
const PATROL_WORDS := ["patrol", "walk the round", "keep watch", "do the rounds",
	"walk between", "guard the"]
const HARVEST_WORDS := ["harvest", "bring in the", "reap", "bring in what",
	"bring in whatever", "whatever is ripe", "what is ripe", "pick the crop",
	"gather the crop", "bring the harvest"]
const COLLECT_WORDS := ["collect the", "pick up the", "gather the eggs",
	"get the eggs", "collect eggs", "go round the animals", "milk", "shear"]
const REST_WORDS := ["rest", "sleep", "go home", "take a break", "turn in", "have a lie down"]
const SCOUT_WORDS := ["scout", "explore", "look north", "look south", "look east",
	"look west", "see what is", "see what's", "have a look", "survey"]


const TRADE_WORDS := ["sell", "buy"]
const COOK_WORDS := ["cook", "bake", "make meals", "get the oven", "make food"]
const CRAFT_WORDS := ["craft", "make tools", "make some tools", "forge", "smith"]
const FISH_WORDS := ["fish", "go fishing", "catch some fish"]
const HUNT_WORDS := ["hunt", "go hunting"]
const TREE_WORDS := ["plant a tree", "plant trees", "plant some trees", "plant an orchard",
	"put in a tree", "put in some trees"]
const ROAD_WORDS := ["pave", "lay a road", "build a road", "make a road", "lay a path",
	"build a path", "make a path", "road from", "path from"]
const LEVEL_WORDS := ["level the ground", "flatten", "level off", "level it", "flat ground",
	"level the"]
const WATER_WORDS := ["water the", "water them", "irrigate"]
const TEND_WORDS := ["feed the", "tend the", "see to the", "look after the", "tend to the"]
const TEACH_WORDS := ["teach", "train", "show him", "show her", "show them"]
const DEMOLISH_WORDS := ["demolish", "tear down", "knock down", "pull down", "take down",
	"remove the"]
const DECORATE_WORDS := ["decorate", "dress up", "smarten up", "spruce up", "make it look",
	"tidy up the front"]
const DELEGATE_WORDS := ["tell ", "have ", "get ", "ask ", "send "]
const RECRUIT_WORDS := ["recruit", "find somebody", "find someone", "take somebody on",
	"take someone on", "hire a ", "hire an ", "hire somebody", "hire someone"]
const REPORT_WORDS := ["report", "how are we doing", "how do we stand", "give me an account",
	"give an account", "an account of", "the books", "how are the stores"]


static func errand_plan(instruction: String) -> Dictionary:
	var text := instruction.to_lower().strip_edges().rstrip(".!")
	var steps: Array = []
	var assumptions: Array = []

	if _has_any(text, REPORT_WORDS):
		steps.append({"do": "report"})
	elif _starts_with_any(text, TRADE_WORDS):
		var action := "buy" if text.begins_with("buy") else "sell"
		# Longest name first, or "sandstone" is read as "sand".
		var kinds: Array = Town.PRICE.keys()
		kinds.sort_custom(func(a: String, b: String) -> bool:
			return a.length() > b.length())
		var kind := ""
		for k: String in kinds:
			if text.find(k.replace("_", " ")) >= 0 or text.find(k) >= 0:
				kind = k
				break
		if kind == "":
			return {}
		var n := 0
		for token: String in text.replace(",", " ").split(" ", false):
			if token.is_valid_int():
				n = int(token)
				break
		var step := {"do": "trade", "action": action, "kind": kind}
		if n > 0:
			step["count"] = n
		else:
			assumptions.append("You did not say how many, so I will %s what seems sensible." % action)
		steps.append(step)
	elif _starts_with_any(text, RECRUIT_WORDS) or _has_any(text, ["recruit "]):
		var role := _place_after(text, ["as a ", "as an ", "as ", "hire a ", "hire an ",
			"recruit a ", "recruit an ", "recruit "])
		if role == "":
			return {}
		steps.append({"do": "recruit", "role": role})
	elif _starts_with_any(text, DELEGATE_WORDS) and text.find(" to ") > 0:
		# "tell mira to build a hut" -> who = mira, order = build a hut
		var body := text
		for w: String in DELEGATE_WORDS:
			if body.begins_with(w):
				body = body.substr(w.length())
				break
		var cut := body.find(" to ")
		var who := body.substr(0, cut).strip_edges()
		var order := body.substr(cut + 4).strip_edges()
		if who == "" or order == "" or who.find(" ") >= 0:
			return {}
		# "send mira to the well" is an order to go there, not a building
		# called "the well" — which is what the planner made of it unaided.
		if order.begins_with("the ") or order in ["home", "you", "here", "me"]:
			order = "go to " + order
		steps.append({"do": "delegate", "who": who, "order": order})
	elif _has_any(text, TEACH_WORDS) and not text.begins_with("teach me"):
		var who2 := _place_after(text, ["teach ", "train ", "show "])
		var skill := ""
		for sk: String in Steps.SKILLS:
			if text.find(sk) >= 0:
				skill = sk
		if skill == "":
			skill = "carpentry"
			assumptions.append("You did not say what, so I will teach carpentry.")
		var name := who2.split(" ", false)[0] if who2 != "" else ""
		if name == "" or name in ["me", "him", "her", "them", "some", "a"]:
			return {}
		steps.append({"do": "teach", "who": name, "skill": skill, "hours": _hours_in(text, 3)})
	elif _has_any(text, DEMOLISH_WORDS):
		var place := _place_after(text, DEMOLISH_WORDS)
		if place == "":
			return {}
		steps.append({"do": "demolish", "place": place})
	elif _has_any(text, DECORATE_WORDS):
		var place2 := _place_after(text, DECORATE_WORDS + [" the front of ", " front of "])
		if place2 == "":
			return {}
		steps.append({"do": "decorate", "place": place2})
	elif _has_any(text, ROAD_WORDS):
		var a := _between(text, ["from "], [" to "])
		var b := _place_after(text, [" to "])
		if a == "" or b == "":
			return {}
		steps.append({"do": "pave", "from": a, "to": b})
	elif _has_any(text, LEVEL_WORDS):
		var step2 := {"do": "level"}
		var place3 := _place_after(text, [" at ", " by ", " near ", " behind ", " outside "])
		if place3 != "":
			step2["place"] = place3
		steps.append(step2)
	elif _has_any(text, TREE_WORDS) or (_has_any(text, ["tree", "trees", "orchard",
			"sapling", "saplings"]) and _has_any(text, ["plant", "put in", "grow", "put"])):
		var n2 := 1
		for token2: String in text.replace(",", " ").split(" ", false):
			if token2.is_valid_int():
				n2 = clampi(int(token2), 1, 12)
			elif NUMBER_WORDS.has(token2):
				n2 = clampi(int(NUMBER_WORDS[token2]), 1, 12)
		if text.find("trees") >= 0 and n2 == 1:
			n2 = 4
			assumptions.append("You did not say how many, so I will put in four.")
		var step3 := {"do": "plant_tree", "count": n2}
		var place4 := _place_after(text, [" at ", " by ", " near ", " behind ", " outside ", " around "])
		if place4 != "":
			step3["place"] = place4
		steps.append(step3)
	elif _has_any(text, WATER_WORDS):
		steps.append({"do": "water"})
	elif _has_any(text, TEND_WORDS) and _has_any(text, ["animal", "hen", "sheep", "cow", "flock", "herd", "stock"]):
		steps.append({"do": "tend"})
	elif _has_any(text, COOK_WORDS):
		steps.append({"do": "cook", "hours": _hours_in(text, 4)})
	elif _has_any(text, CRAFT_WORDS):
		steps.append({"do": "craft", "hours": _hours_in(text, 4)})
	elif _has_any(text, FISH_WORDS):
		steps.append({"do": "fish", "hours": _hours_in(text, 4)})
	elif _has_any(text, HUNT_WORDS):
		steps.append({"do": "hunt", "hours": _hours_in(text, 4)})
	elif _starts_with_any(text, PATROL_WORDS) or text.find("patrol") >= 0:
		var places := _places_in(text)
		if places.size() < 2:
			places = ["the well", "the edge of town"]
			assumptions.append("You did not say where, so I will walk between the well and the edge of town.")
		steps.append({"do": "patrol", "places": places, "hours": _hours_in(text, 8)})
	elif _starts_with_any(text, STATION_WORDS) or text.find("shift") >= 0:
		var place := _place_after(text, STATION_WORDS)
		if place == "":
			return {}
		steps.append({"do": "station", "place": place, "hours": _hours_in(text, 6)})
		assumptions.append("You did not say how long, so I will work %d hours." % _hours_in(text, 6))
	elif _has_any(text, HARVEST_WORDS):
		steps.append({"do": "harvest"})
	elif _has_any(text, COLLECT_WORDS):
		steps.append({"do": "collect"})
	elif _has_any(text, SCOUT_WORDS):
		var dir := ""
		for d: String in Steps.DIRECTIONS:
			if text.find(d) >= 0:
				dir = d
				break
		if dir == "":
			dir = "north"
			assumptions.append("You did not say which way, so I will go north.")
		steps.append({"do": "scout", "direction": dir, "distance": 60})
	elif _has_any(text, REST_WORDS) and not text.find("rest of") >= 0:
		steps.append({"do": "rest", "hours": _hours_in(text, 4)})
	elif _starts_with_any(text, GO_WORDS):
		var place2 := _place_after(text, GO_WORDS)
		if place2 == "":
			return {}
		steps.append({"do": "go", "place": place2})
	else:
		return {}

	return {
		"kind": "plan",
		"steps": steps,
		"assumptions": assumptions,
		"confidence": 0.4,
		"worker_line": "",
		"cost_estimate": {},
		"source": "fallback",
	}


## Whole phrases only: " bake " is not in " build a small bakery ", and the
## day it was, every bakery order became a shift at the oven.
static func _has_any(text: String, words: Array) -> bool:
	var t := " %s " % text.replace(",", " ").replace(".", " ")
	for w: String in words:
		if t.find(" %s " % w.strip_edges()) >= 0:
			return true
	return false


static func _starts_with_any(text: String, words: Array) -> bool:
	for w: String in words:
		if text.begins_with(w):
			return true
	return false


## "work at the bakery for 6 hours" -> "bakery"
static func _place_after(text: String, leads: Array) -> String:
	for w: String in leads:
		var i := text.find(w)
		if i < 0:
			continue
		var rest := text.substr(i + w.length()).strip_edges()
		for stop: String in [" for ", " until ", " till ", " and ", ",", " then ",
				" each ", " every ", " all "]:
			var j := rest.find(stop)
			if j >= 0:
				rest = rest.substr(0, j)
		return rest.strip_edges().trim_prefix("the ").trim_prefix("a ").strip_edges()
	return ""


## The words between the first of `lefts` and the first of `rights` after it.
static func _between(text: String, lefts: Array, rights: Array) -> String:
	for l: String in lefts:
		var i := text.find(l)
		if i < 0:
			continue
		var rest := text.substr(i + l.length())
		for r: String in rights:
			var j := rest.find(r)
			if j >= 0:
				return rest.substr(0, j).strip_edges().trim_prefix("the ")
		return rest.strip_edges().trim_prefix("the ")
	return ""


## "patrol the well and the bakery" -> ["well", "bakery"]
static func _places_in(text: String) -> Array:
	var t := text
	for w: String in PATROL_WORDS:
		t = t.replace(w, " ")
	for stop: String in [" for ", " until ", " till ", " tonight", " all night", " today"]:
		var j := t.find(stop)
		if j >= 0:
			t = t.substr(0, j)
	# "from the well to the edge of town" is two places as much as "the well
	# and the edge of town" is.
	var out: Array = []
	for part: String in t.replace(",", " and ").replace(" from ", " ").replace(" to ", " and ").split(" and ", false):
		var p := part.strip_edges().trim_prefix("the ").trim_prefix("between ") 			.trim_prefix("from ").strip_edges()
		if p != "" and p not in out:
			out.append(p)
	return out


static func _hours_in(text: String, default: int) -> int:
	var words := text.replace("-", " ").split(" ", false)
	for i in words.size():
		var w := String(words[i])
		var n := -1
		if w.is_valid_int():
			n = int(w)
		elif NUMBER_WORDS.has(w):
			n = int(NUMBER_WORDS[w])
		if n > 0 and i + 1 < words.size() and String(words[i + 1]).begins_with("hour"):
			return clampi(n, 1, Steps.SHIFT_MAX_HOURS)
	if text.find("all night") >= 0 or text.find("all day") >= 0:
		return Steps.SHIFT_MAX_HOURS
	return default


## The offline plan. It still produces assumptions, because a building with no
## visible reasoning behind it is the one thing the design forbids.
static func fallback(instruction: String, mem: WorkerMemory, plot: Plot,
		tier: int) -> Dictionary:
	var errand := errand_plan(instruction)
	if not errand.is_empty():
		return errand
	var land := land_plan(instruction, tier)
	if not land.is_empty():
		return land

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
		spec["footprint"] = [float(fp[0]) * 1.45, float(fp[1]) * 1.45]
	elif text.find("small") >= 0 or text.find("tiny") >= 0 or text.find("little") >= 0:
		spec["footprint"] = [float(fp[0]) * 0.72, float(fp[1]) * 0.72]

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
	# Four metres of yard, not two. The setback the generator uses is bigger
	# now, and a plan that fills the parcel to its last metre gets pushed back
	# out again by the clamp in _resolve_dimensions.
	spec["footprint"] = [
		int(maxf(minf(float(fp[0]), avail.x - 4.0), 7.0)),
		int(maxf(minf(float(fp[1]), avail.y - 4.0), 7.0)),
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
