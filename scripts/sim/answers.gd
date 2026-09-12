extends RefCounted
class_name Answers
## What a worker says when asked a question rather than given an order.
##
## Pillar P1 makes the text field the only control in the game, and until now
## everything typed into it was treated as work: "where did you put the store"
## went to the model as a building request and came back as a plan for a
## store. Workers who cannot be asked anything are not people you are
## delegating to, they are a build menu with a face.
##
## The answers here come from the town's own records and nowhere else. The
## model could answer most of these, and would be wrong about a fifth of them —
## it works from prose and rounds numbers to feelings. "How many bricks have
## we got" has one correct answer and the dictionary holding it is right there,
## so the model is never asked. It is only consulted for the questions this
## file has no pattern for, and then it is handed the same facts and told to
## stick to them.
##
## Every reply is one worker talking, in the register the rest of their
## dialogue uses: plain sentences, numbers as numbers, no bullet points.

## Openers that mean the player wants to know something, not have something
## done. Deliberately narrow. "Can you build a hut" and "could you fetch some
## stone" are orders with manners on them, and go where orders go.
const ASKING := ["what", "where", "when", "who", "whose", "how", "which", "why",
	"is there", "are there", "do we", "does the", "did you", "have you",
	"have we", "tell me", "remind me", "do you remember", "do you know",
	"any idea", "status"]
const ORDERING := ["what about", "how about", "can you", "could you",
	"would you", "will you", "why not", "why don't", "how are you"]

## Words for buildings that are not archetype names.
const BUILDING_WORDS := {
	"house": ["cottage", "hut"], "home": ["cottage", "hut"], "houses": ["cottage", "hut"],
	"pub": ["tavern"], "bar": ["tavern"], "inn": ["inn", "tavern"],
	"shop": ["store", "shop"], "shops": ["store", "shop"],
	"church": ["shrine"], "temple": ["shrine"],
	"storehouse": ["warehouse", "store"], "stables": ["stable"],
	"smithy": ["forge"], "blacksmith": ["forge"],
}
## Things the town counts that are not materials.
const LARDER_WORDS := {
	"food": "food", "grain": "food", "wheat": "food", "bread": "food",
	"crops": "food", "harvest": "food",
	"cloth": "cloth", "wool": "cloth", "fleece": "cloth", "fleeces": "cloth",
}
const MONEY_WORDS := ["money", "coin", "coins", "gold", "purse", "cash", "funds"]
const ANIMAL_WORDS := {
	"hen": "hen", "hens": "hen", "chicken": "hen", "chickens": "hen",
	"rooster": "rooster", "roosters": "rooster", "cockerel": "rooster",
	"sheep": "sheep", "lamb": "sheep", "lambs": "sheep", "ewe": "sheep",
	"cow": "cow", "cows": "cow", "cattle": "cow",
	"goat": "goat", "goats": "goat",
	"pig": "pig", "pigs": "pig", "hog": "pig", "hogs": "pig",
	"horse": "horse", "horses": "horse",
	"dog": "dog", "dogs": "dog", "cat": "cat", "cats": "cat",
	"deer": "deer", "stag": "deer", "rabbit": "rabbit", "rabbits": "rabbit",
	"fox": "fox", "foxes": "fox",
	"crow": "crow", "crows": "crow", "sparrow": "sparrow", "sparrows": "sparrow",
	"gull": "gull", "gulls": "gull", "seagull": "gull", "seagulls": "gull",
	"duck": "duck", "ducks": "duck", "owl": "owl", "owls": "owl",
	"bird": "birds", "birds": "birds",
	"fish": "fish", "fishes": "fish", "carp": "carp", "trout": "trout", "perch": "perch",
	"animals": "*", "livestock": "*", "flock": "*", "herd": "*",
}
const COMPASS := ["north", "north-east", "east", "south-east", "south",
	"south-west", "west", "north-west"]


## Whether this is something to answer rather than something to do.
static func is_question(text: String) -> bool:
	var t := _clean(text)
	if t == "":
		return false
	for o: String in ORDERING:
		if t.begins_with(o):
			return false
	if text.strip_edges().ends_with("?"):
		return true
	for a: String in ASKING:
		if t == a or t.begins_with(a + " "):
			return true
	return false


## The answer, or "" when nothing here knows. The caller decides what to do
## with "" — ask the model, or say so.
static func reply(text: String, worker: Worker, town: Town, village: Village,
		clock: GameClock, player: Node3D, farm: Farm, livestock: Livestock,
		wildlife: Wildlife = null, warfare: Node = null) -> String:
	var t := _clean(text)
	var mem := worker.memory
	var here: Vector3 = player.global_position if player != null \
		else worker.global_position

	# Reasons and opinions are not in any record. A "why" that happens to
	# mention the bakery is still a why, and the first version of this answered
	# one with how far along the bakery was.
	if t.begins_with("why") or _any(t, ["do you think", "what do you make of",
			"how do you feel", "your opinion", "would you have", "do you like",
			"what would you", "should we", "should i"]):
		return ""

	# --- about the worker, and what they were told ---
	if _any(t, ["what are you doing", "what you doing", "what are you up to",
			"status", "what is your status", "how is it going", "how goes it",
			"are you busy", "what are you working on"]):
		return _doing(worker)

	if _any(t, ["what did i ask", "what did i tell", "what did i say",
			"what have i asked", "what was my order", "what was the order",
			"what was the last order", "what was the last thing",
			"do you remember what", "remind me what", "what were you told",
			"what did i order", "what were you asked", "what was your task",
			"what is your task", "what task", "what job", "what is your job",
			"what jobs", "what orders"]):
		return _orders(worker, town, clock)

	if _any(t, ["what have you built", "what did you build", "what have you done",
			"what have you made", "what did you make", "what did you do",
			"what have you been doing", "what did you get done",
			"what have you finished"]):
		return _built(worker, town, here, village)

	if _any(t, ["where are you", "where you at"]):
		return _where_is(worker.global_position, here, village, "I am")

	if _any(t, ["where am i", "where are we", "what street", "which street"]):
		return _where_is(here, worker.global_position, village, "You are")

	if _any(t, ["what day", "what time", "what hour", "how late", "is it late",
			"what is the time", "what is the date"]):
		var h := int(clock.hour)
		var m := int((clock.hour - h) * 60.0)
		return "It is %02d:%02d on day %d — %s." % [
			h, m, clock.day, clock.part_of_day(clock.hour)]

	if _any(t, ["what tier", "which tier", "how advanced"]):
		return _tier(town)

	# --- the army and the armoury ---
	if warfare != null:
		if _any(t, ["soldier", "army", "militia", "troops", "the men", "garrison"]) \
				and _any(t, ["how many", "how big", "do we have", "have we", "is there",
				"are there", "what", "where"]):
			return str(warfare.army_line())
		if _any(t, ["raider", "bandit", "enemy", "attack", "raid"]) \
				and _any(t, ["any", "how many", "are there", "is there", "when", "coming"]):
			var n: int = warfare.raiders.size()
			if n == 0:
				return "None about. They come at first light when there is something worth taking."
			return "%d raiders about the place right now." % n
		var arm := Arsenal.find_in(t)
		if arm != "" and _any(t, ["how many", "how much", "do we have", "have we",
				"is there", "are there", "any", "left", "enough"]):
			var n2: int = town.units_of(arm)
			if n2 <= 0:
				return "No %s. The armoury makes them — say \"make some %s\"." % [
					Arsenal.label(arm), Arsenal.label(arm)]
			return "%d %s in the stores." % [n2, Arsenal.label(arm)]

	# --- money and the larder ---
	if _has_word(t, MONEY_WORDS) and _any(t, ["how much", "how many", "what", "do we have", "have we"]):
		return _money(town)

	# --- animals ---
	var species := _find_word(t, ANIMAL_WORDS)
	if species != "" and livestock != null and _any(t, ["how many", "how much", "count",
			"do we have", "have we", "are there", "is there", "any", "seen"]):
		return _animals(species, livestock, wildlife)

	# --- the field ---
	if _any(t, ["field", "crop", "crops", "sown", "planted", "harvest"]) and farm != null \
			and _any(t, ["how", "what", "is the", "are the", "any"]):
		return _field(farm)

	# --- buildings: where, who, how many ---
	var archs := _find_buildings(t)
	if not archs.is_empty():
		if _any(t, ["where", "which street", "what street", "find the", "show me"]):
			return _where_building(archs, town, village, here)
		if _any(t, ["who built", "who made", "who put up", "whose"]):
			return _who_built(archs, town, worker)
		if _any(t, ["how many", "do we have", "have we got", "is there", "are there",
				"have we a", "have we any", "got a", "got any"]):
			return _count_building(archs, town)
		if _any(t, ["is the", "how is the", "hows the", "coming along",
				"finished yet", "done yet", "ready yet", "how far"]):
			return _progress(archs, worker, town)

	if _any(t, ["what have we built", "what buildings", "what is in the town",
			"what is in town", "what have we got in town", "what stands",
			"what is built", "how many buildings", "how many houses"]):
		return _town(town)

	# --- materials ---
	var mat := _find_material(t)
	if mat != "":
		if _any(t, ["how many", "how much", "do we have", "have we", "is there",
				"are there", "got any", "any left", "how are we for", "what about",
				"enough", "count", "stock", "left"]):
			return _material(mat, town)
		if _any(t, ["where", "get more", "find more", "come from", "comes from",
				"source", "dig"]):
			return _source(mat, town)
	if _any(t, ["what do we have", "what have we got", "what is in the stores",
			"what is in stock", "what materials", "what is in the yard",
			"how are the stores", "how are we for materials", "what supplies"]):
		return _stores(town)

	return ""


# ------------------------------------------------------------- the answers

static func _doing(w: Worker) -> String:
	var s := w.status_text()
	if w.pending_question != "":
		return "Waiting on you — I asked: %s" % w.pending_question
	if w.pondering != "":
		return "Working out how to %s. I am %s." % [
			w.pondering.to_lower().trim_suffix("."), s]
	if w.job_patch != null:
		var pct := int(w.progress() * 100.0)
		return "Building the %s on %s — about %d%% of the way through." % [
			w.job_patch.archetype.replace("_", " "), w.job_where, pct]
	if w.job_field != null:
		return "Working the field. %s" % s.capitalize()
	if w.job_quarry != null:
		return "Out fetching material. %s" % s.capitalize()
	if w.waiting_for != "":
		return "Holding a plan until we have %s." % w.waiting_for
	if s == "idle":
		return "Nothing at the moment. Give me something."
	return s.capitalize() + "."


static func _orders(w: Worker, town: Town, clock: GameClock) -> String:
	var orders := w.memory.orders()
	if orders.is_empty():
		return "You have not asked me for anything yet."
	var last: Dictionary = orders[orders.size() - 1]
	var said := str(last.get("instruction", ""))
	var fate := _fate(w, last, town, clock)
	var out := "The last thing you asked me was \"%s\" — %s" % [said, fate]
	if orders.size() >= 2:
		var before: Dictionary = orders[orders.size() - 2]
		out += " Before that, \"%s\" — %s" % [
			str(before.get("instruction", "")), _fate(w, before, town, clock)]
	if orders.size() > 2:
		out += " That is %d orders in all." % orders.size()
	return out


## What became of one order, as a clause.
static func _fate(w: Worker, order: Dictionary, town: Town, clock: GameClock) -> String:
	var id := int(order.get("id", -1))
	var day := int(order.get("day", clock.day))
	var when := "today" if day == clock.day else ("yesterday" if day == clock.day - 1
		else "on day %d" % day)
	var done := w.memory.outcome_of(id)
	if not done.is_empty():
		var kind := str(done.get("kind", ""))
		if kind == "done":
			if done.has("archetype"):
				return "and the %s is up on %s, finished %s." % [
					str(done["archetype"]).replace("_", " "), str(done["street"]), when]
			if done.has("species"):
				return "and I brought %d %s back %s." % [
					int(done["count"]), str(done["species"]), when]
			if done.has("errand"):
				return "and I came back with %s %s." % [str(done["errand"]), when]
			if done.has("field"):
				return "and the field is sown, %s." % when
			return "and it is done, %s." % when
		if kind == "asked":
			return "and I had to ask you something about it: %s" % str(done["question"])
		if kind == "plan":
			return "and I am building the %s on %s now." % [
				str(done["archetype"]).replace("_", " "), str(done["street"])]
	if w.current_order == id:
		if w.pondering != "":
			return "and I am still working out how, %s." % when
		if w.job_patch != null:
			return "and I am building it on %s right now, about %d%% done." % [
				w.job_where, int(w.progress() * 100.0)]
		if w.waiting_for != "":
			return "and I am holding it until we have %s." % w.waiting_for
	return "given %s." % when


static func _built(w: Worker, town: Town, here: Vector3, village: Village) -> String:
	var mine: Array[Dictionary] = []
	for b: Dictionary in town.buildings:
		if str(b.get("builder", "")) == w.memory.worker_id:
			mine.append(b)
	if mine.is_empty():
		var errands := w.memory.of_kind("done")
		if errands.is_empty():
			return "Nothing yet. I have been waiting for you to ask."
		var e: Dictionary = errands[errands.size() - 1]
		return "No buildings so far, but %s" % str(e.get("summary", "")).to_lower()
	var parts: Array[String] = []
	for b: Dictionary in mine:
		parts.append("the %s on %s" % [
			str(b["archetype"]).replace("_", " "), str(b["street"])])
	var last: Dictionary = mine[mine.size() - 1]
	var where := _whereabouts(here, _building_centre(last))
	if mine.size() == 1:
		return "Just the one so far: %s, %s." % [parts[0], where]
	return "%d buildings: %s. The latest is %s." % [
		mine.size(), _join(parts), where]


static func _where_building(archs: Array[String], town: Town, village: Village,
		here: Vector3) -> String:
	var found := _standing(archs, town)
	var noun := str(archs[0]).replace("_", " ")
	if found.is_empty():
		return "There is no %s in the town yet. Say the word and I will put one up." % noun
	if found.size() == 1:
		var b: Dictionary = found[0]
		return "The %s is on %s, %s — %s." % [
			str(b["archetype"]).replace("_", " "), str(b["street"]),
			_whereabouts(here, _building_centre(b)),
			_credit(str(b["builder"]), int(b["day"]))]
	var parts: Array[String] = []
	for b: Dictionary in found:
		parts.append("the %s on %s, %s" % [str(b["archetype"]).replace("_", " "),
			str(b["street"]), _whereabouts(here, _building_centre(b))])
	return "There are %d: %s." % [found.size(), _join(parts)]


static func _who_built(archs: Array[String], town: Town, w: Worker) -> String:
	var found := _standing(archs, town)
	if found.is_empty():
		return "Nobody has built a %s here yet." % str(archs[0]).replace("_", " ")
	var b: Dictionary = found[0]
	var noun := str(b["archetype"]).replace("_", " ")
	var who := str(b["builder"])
	if who == "":
		return "The %s on %s was standing before any of us got here." % [
			noun, str(b["street"])]
	if who == w.memory.worker_id:
		return "I did — the %s on %s, day %d." % [noun, str(b["street"]), int(b["day"])]
	return "%s did — the %s on %s, day %d." % [
		who.capitalize(), noun, str(b["street"]), int(b["day"])]


static func _count_building(archs: Array[String], town: Town) -> String:
	var found := _standing(archs, town)
	var noun := str(archs[0]).replace("_", " ")
	if found.is_empty():
		return "No %s yet." % noun
	if found.size() == 1:
		var b: Dictionary = found[0]
		return "One — the %s on %s." % [str(b["archetype"]).replace("_", " "),
			str(b["street"])]
	var parts: Array[String] = []
	for b: Dictionary in found:
		parts.append("the %s on %s" % [str(b["archetype"]).replace("_", " "),
			str(b["street"])])
	return "%d: %s." % [found.size(), _join(parts)]


static func _progress(archs: Array[String], w: Worker, town: Town) -> String:
	var noun := str(archs[0]).replace("_", " ")
	if w.job_patch != null and w.job_patch.archetype in archs:
		return "The %s on %s is about %d%% up." % [
			w.job_patch.archetype.replace("_", " "), w.job_where,
			int(w.progress() * 100.0)]
	var found := _standing(archs, town)
	if not found.is_empty():
		var b: Dictionary = found[found.size() - 1]
		return "The %s on %s is finished — %s." % [
			str(b["archetype"]).replace("_", " "), str(b["street"]),
			_credit(str(b["builder"]), int(b["day"]))]
	return "Nobody is working on a %s." % noun


static func _town(town: Town) -> String:
	if town.buildings.is_empty():
		return "Nothing but the well and the streets, so far."
	var parts: Array[String] = []
	for b: Dictionary in town.buildings:
		parts.append("a %s on %s" % [
			str(b["archetype"]).replace("_", " "), str(b["street"])])
	return "%d buildings: %s." % [town.buildings.size(), _join(parts)]


static func _material(mat: String, town: Town) -> String:
	var n := town.units_of(mat)
	var noun := mat.replace("_", " ")
	if not town.knows(mat):
		if n > 0:
			return "%d units of %s in the yard, but nobody here can work it yet." % [n, noun]
		return "None, and nobody here could work %s if we had it — the town is not there yet." % noun
	if n <= 0:
		var src := Resources.source_of(mat)
		if src < 0:
			return "None. There is nowhere to get %s either." % noun
		return "None at all. It comes out of %s — say the word and somebody will go." % \
			Resources.place_of(src)
	var feel := "plenty" if n >= 460 else ("some" if n >= 140 else "not much")
	return "%d units of %s — %s, about %d coins' worth." % [
		n, noun, feel, n * int(Town.PRICE.get(mat, Town.DEFAULT_PRICE))]


static func _source(mat: String, town: Town) -> String:
	var src := Resources.source_of(mat)
	var noun := mat.replace("_", " ")
	if src < 0:
		return "There is nowhere to dig for %s. What the town has is all it will have." % noun
	return "%s comes out of %s. A voxel of it is worth %d units, and we have %d in the yard." % [
		noun.capitalize(), Resources.place_of(src), Resources.yield_of(src),
		town.units_of(mat)]


static func _stores(town: Town) -> String:
	var have: Array[Dictionary] = []
	for k: String in town.stock:
		var n := int(town.stock[k])
		if n > 0:
			have.append({"m": k, "n": n})
	if have.is_empty():
		return "The yard is empty."
	have.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["n"]) > int(b["n"]))
	var parts: Array[String] = []
	for i in mini(have.size(), 6):
		parts.append("%d %s" % [int(have[i]["n"]), str(have[i]["m"]).replace("_", " ")])
	var out := "Mostly %s" % _join(parts)
	if have.size() > 6:
		out += ", and a little of %d other things" % (have.size() - 6)
	return out + ". Worth about %s coins all told, and %s coins in the purse." % [
		Town.grouped(town.stock_worth()), town.coin_line()]


static func _money(town: Town) -> String:
	if town.coins < 0:
		return "We are %s coins in debt. The yard would fetch about %s if it came to that." % [
			Town.grouped(-town.coins), Town.grouped(town.stock_worth())]
	return "%s coins in the purse, and the yard is worth about %s on top." % [
		town.coin_line(), Town.grouped(town.stock_worth())]


static func _animals(species: String, livestock: Livestock, wildlife: Wildlife) -> String:
	if species == "*":
		var parts: Array[String] = []
		for k: String in Steps.SPECIES:
			var c := livestock.count_of(k)
			if c > 0:
				parts.append("%d %s" % [c, _plural(k, c)])
		if parts.is_empty():
			return "No animals of our own. Ask for some hens."
		var out := "Ours: %s." % _join(parts)
		if wildlife != null:
			var seen := wildlife.species_seen()
			if not seen.is_empty():
				var wild: Array[String] = []
				for k: String in seen:
					wild.append("%d %s" % [int(seen[k]), _plural(k, int(seen[k]))])
				out += " About the place just now: %s." % _join(wild)
		return out
	if species == "birds" or species == "fish":
		if wildlife == null:
			return "None that I have seen."
		var group := ["crow", "sparrow", "gull", "duck", "owl"] if species == "birds" \
			else ["carp", "trout", "perch"]
		var parts2: Array[String] = []
		for k: String in group:
			var c2 := wildlife.count_of(k)
			if c2 > 0:
				parts2.append("%d %s" % [c2, _plural(k, c2)])
		if parts2.is_empty():
			return "None about at the moment." if species == "birds" \
				else "None that I can see — try the water's edge."
		return "%s." % _join(parts2).capitalize()
	var n := livestock.count_of(species)
	var wild_n := wildlife.count_of(species) if wildlife != null else 0
	if species in Steps.SPECIES:
		if n == 0:
			return "No %s. Say \"bring some %s\" and I will fetch a few." % [
				_plural(species, 2), _plural(species, 2)]
		return "%d %s." % [n, _plural(species, n)]
	if wild_n == 0:
		return "None about just now. They come and go."
	return "%d %s about the place at the moment." % [wild_n, _plural(species, wild_n)]


static func _plural(species: String, n: int) -> String:
	if n == 1:
		return species
	match species:
		"sheep", "deer", "fish", "carp", "trout", "perch": return species
		"fox": return "foxes"
	return species + "s"


static func _field(farm: Farm) -> String:
	if farm.tile_count() == 0:
		return "There is no field yet."
	return "%d tiles of field, %d sown and %d ripe for picking." % [
		farm.tile_count(), farm.planted_count(), farm.ripe_count()]


static func _tier(town: Town) -> String:
	var nxt := town.tier + 1
	var missing := town.needs_met_for(nxt)
	if missing.is_empty():
		return "Tier %d." % town.tier
	var names: Array[String] = []
	for m: String in missing:
		names.append("a " + m.replace("_", " "))
	return "Tier %d. To reach %d the town still wants %s." % [
		town.tier, nxt, _join(names)]


static func _where_is(who: Vector3, other: Vector3, village: Village,
		subject: String) -> String:
	var v := VoxelWorld.to_voxel(who)
	var plot := village.plot_at(who)
	if plot != null:
		return "%s on the plot on %s, %s." % [subject, plot.street_name,
			_whereabouts(other, who).replace("of you", "away")]
	if village.is_plaza(v.x, v.z):
		return "%s in the plaza by the well, %s." % [subject,
			_whereabouts(other, who).replace("of you", "away")]
	if village.is_road(v.x, v.z):
		return "%s in the street, %s." % [subject,
			_whereabouts(other, who).replace("of you", "away")]
	var from_well := _whereabouts(village.well_pos, who).replace("of you", "of the well")
	return "%s out past the streets, %s." % [subject, from_well]


# --------------------------------------------------------------- helpers

static func _clean(text: String) -> String:
	var t := text.strip_edges().to_lower()
	# Possessives before apostrophes, so "the store's" becomes "the store"
	# rather than "the stores", which is a different word here.
	for ch: String in ["?", "!", ".", ",", "'s", "'", "\""]:
		t = t.replace(ch, "")
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	return t.strip_edges()


static func _any(t: String, phrases: Array) -> bool:
	for p: String in phrases:
		if t.find(p) >= 0:
			return true
	return false


static func _has_word(t: String, words: Array) -> bool:
	for w: String in t.split(" ", false):
		if w in words:
			return true
	return false


static func _find_word(t: String, table: Dictionary) -> String:
	for w: String in t.split(" ", false):
		if table.has(w):
			return str(table[w])
	return ""


## The archetypes a question names, in any of the ways a player says them.
## Usually one; "house" is several, and a count of houses wants all of them.
static func _find_buildings(t: String) -> Array[String]:
	var spaced := " " + t + " "
	var out: Array[String] = []
	# Longest names first, so "tower block" is not caught as "tower".
	var names: Array[String] = []
	for tier: int in Vocabulary.ARCHETYPES:
		for a: String in Vocabulary.ARCHETYPES[tier]:
			names.append(a)
	names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for a: String in names:
		var said := a.replace("_", " ")
		if spaced.find(" " + said + " ") >= 0 or spaced.find(" " + said + "s ") >= 0:
			out.append(a)
			return out
	for w: String in t.split(" ", false):
		if BUILDING_WORDS.has(w):
			for a: Variant in (BUILDING_WORDS[w] as Array):
				out.append(str(a))
			return out
	return out


## A material named in the question. The dispatcher's table first, because it
## already knows that "stone" means cobble and "iron" means steel frame.
static func _find_material(t: String) -> String:
	var spaced := " " + t + " "
	for k: String in VoxelTypes.NAMES:
		var said := k.replace("_", " ")
		if spaced.find(" " + said + " ") >= 0 or spaced.find(" " + said + "s ") >= 0:
			return k
	for w: String in t.split(" ", false):
		if LARDER_WORDS.has(w):
			return str(LARDER_WORDS[w])
		if Dispatcher.MATERIAL_WORDS.has(w):
			return str(Dispatcher.MATERIAL_WORDS[w])
	return ""


static func _standing(archs: Array[String], town: Town) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in town.buildings:
		if str(b["archetype"]) in archs:
			out.append(b)
	return out


## Who to thank, as a clause. The founding buildings have no builder and were
## there on day zero, which is not a fact that reads well as "nobody, day 0".
static func _credit(builder: String, day: int) -> String:
	if builder == "":
		return "it was here before any of us"
	return "%s put it up on day %d" % [builder.capitalize(), day]


static func _building_centre(b: Dictionary) -> Vector3:
	var patch: VoxelPatch = b.get("patch", null)
	if patch == null:
		return Vector3.ZERO
	var fr := patch.footprint
	var v := VoxelChunk.VOXEL_M
	return Vector3((fr.position.x + fr.size.x * 0.5) * v, 0.0,
		(fr.position.y + fr.size.y * 0.5) * v)


## "about 40 metres north-east of you" — the bearing is from where the player
## is standing, because that is the only "where" a person can use.
static func _whereabouts(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var m := d.length()
	if m < 6.0:
		return "right here beside you"
	var ang := atan2(d.x, -d.y)
	var idx := roundi(ang / (PI / 4.0))
	idx = ((idx % 8) + 8) % 8
	var dist := roundi(m / 5.0) * 5
	return "about %d metres %s of you" % [maxi(dist, 5), COMPASS[idx]]


static func _join(parts: Array) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	var last: String = parts[parts.size() - 1]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + last
