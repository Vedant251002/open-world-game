extends Node
## What the buildings make, and who makes it.
##
## A bakery with nobody in it is a shape. Put a citizen in it and every
## morning some of the larder comes out as bread, and the citizen gets a
## little better at baking. That is the whole of industry: a table of what
## each kind of building turns into what, a record of who works where, and a
## daily pass over both. The player never has to run it — empty buildings
## staff themselves from whoever is idle — but can move anyone anywhere with
## a sentence, and can ask any building how it is getting on.
##
## Everything goes through Town's stock and coins so the inventory screen and
## the purse show the result without knowing this file exists.

## Per staffed worker per day. "in" is taken from the stores, "out" put back,
## "coins" added to the purse; a chain with no inputs is a trade that only
## needs a pair of hands. "job" is the RoleBook id the work counts as, which
## is also the skill that grows with it.
const CHAINS := {
	"bakery": {"in": {"food": 2}, "out": {"meals": 3}, "coins": 0,
		"job": "cook", "does": "bakes bread from the larder"},
	"smokehouse": {"in": {"meat": 2}, "out": {"food": 5}, "coins": 0,
		"job": "cook", "does": "smokes meat into keeping food"},
	"workshop": {"in": {"timber": 4}, "out": {"tools": 1}, "coins": 0,
		"job": "toolmaker", "does": "makes tools out of timber"},
	"store": {"in": {}, "out": {}, "coins": 40,
		"job": "shopkeeper", "does": "sells what the town has spare"},
	"tavern": {"in": {"food": 3}, "out": {}, "coins": 45,
		"job": "innkeeper", "does": "turns food into ale money and good cheer"},
	"barn": {"in": {}, "out": {"food": 4}, "coins": 0,
		"job": "shepherd", "does": "keeps fodder and the beasts fed"},
	"mill": {"in": {"food": 3}, "out": {"food": 5}, "coins": 0,
		"job": "cook", "does": "grinds the harvest into flour"},
	"forge": {"in": {"timber": 2, "cobble": 4}, "out": {"tools": 1}, "coins": 10,
		"job": "toolmaker", "does": "hammers iron and stone into tools"},
	"brickworks": {"in": {"sand": 3}, "out": {"brick": 6}, "coins": 0,
		"job": "miner", "does": "fires clay into brick"},
	"granary": {"in": {}, "out": {}, "coins": 0,
		"job": "farmer", "does": "keeps the harvest dry"},
	"inn": {"in": {"food": 2}, "out": {}, "coins": 35,
		"job": "innkeeper", "does": "puts up travellers for coin"},
}
## Hands a building can use before the next one is standing idle.
const STAFF_MAX := 2
## Somebody with no workplace still brings something home.
const LABOUR := {"timber": 2, "cobble": 1}

var realm: Realm
## building id -> what it made yesterday, for "how is the bakery doing".
var _made: Dictionary = {}
## building id -> the input it ran out of yesterday, or absent.
var _starved: Dictionary = {}


func setup(r: Realm) -> void:
	realm = r
	if realm.town != null:
		realm.town.building_removed.connect(_on_removed)


# ------------------------------------------------------------------ records

func chain_for(rec: Dictionary) -> Dictionary:
	return CHAINS.get(str(rec.get("archetype", "")), {})


func staff_of(bid: int) -> Array:
	var out: Array = []
	for c: Population.Citizen in realm.population.alive():
		if c.workplace_id == bid:
			out.append(c)
	return out


func workplace_of(c: Population.Citizen) -> Dictionary:
	if c == null or c.workplace_id < 0:
		return {}
	for rec: Dictionary in realm.town.buildings:
		if int(rec["id"]) == c.workplace_id:
			return rec
	return {}


func assign(c: Population.Citizen, rec: Dictionary) -> bool:
	var chain := chain_for(rec)
	if chain.is_empty():
		return false
	c.workplace_id = int(rec["id"])
	c.job = str(chain["job"])
	return true


func release(c: Population.Citizen) -> void:
	c.workplace_id = -1
	c.job = ""


func _on_removed(rec: Dictionary) -> void:
	var bid := int(rec.get("id", -1))
	for c: Population.Citizen in realm.population.alive():
		if c.workplace_id == bid:
			release(c)
	_made.erase(bid)
	_starved.erase(bid)


# --------------------------------------------------------------------- work

func on_day(_day: int) -> void:
	_auto_staff()
	_made.clear()
	_starved.clear()
	var law: Node = realm.system("Law")
	var rate := 1.0
	if law != null and law.has_method("work_rate"):
		rate = float(law.call("work_rate"))
	var ale_ok := true
	if law != null and law.has_method("ale_allowed"):
		ale_ok = bool(law.call("ale_allowed"))
	var town := realm.town
	for rec: Dictionary in town.buildings:
		var chain := chain_for(rec)
		if chain.is_empty():
			continue
		var bid := int(rec["id"])
		var arch := str(rec["archetype"])
		if arch == "tavern" and not ale_ok:
			continue
		for c: Population.Citizen in staff_of(bid):
			var skill := float(c.skills.get(str(chain["job"]), 0.0))
			var batches := int(floor((1.0 + skill) * rate))
			if batches <= 0:
				continue
			var did := batches
			var inputs: Dictionary = chain["in"]
			var outputs: Dictionary = chain["out"]
			if not inputs.is_empty():
				did = town.convert(inputs, outputs, batches)
				if did < batches:
					for k: String in inputs:
						if int(town.stock.get(k, 0)) < int(inputs[k]):
							_starved[bid] = k
							break
			else:
				for k: String in outputs:
					town.stock[k] = int(town.stock.get(k, 0)) + int(outputs[k]) * did
			if did > 0:
				town.coins += int(chain["coins"]) * did
				c.skills[str(chain["job"])] = minf(skill + 0.04 * did, 1.0)
				var tally: Dictionary = _made.get(bid, {})
				for k: String in outputs:
					tally[k] = int(tally.get(k, 0)) + int(outputs[k]) * did
				if int(chain["coins"]) > 0:
					tally["coins"] = int(tally.get("coins", 0)) + int(chain["coins"]) * did
				_made[bid] = tally
				if arch == "tavern":
					for other: Population.Citizen in realm.population.alive():
						other.mood = minf(other.mood + 0.01, 1.0)
	for c: Population.Citizen in realm.population.alive():
		if c.workplace_id < 0:
			for k: String in LABOUR:
				town.stock[k] = int(town.stock.get(k, 0)) + int(LABOUR[k])
	for bid: int in _starved:
		var rec := realm.population._building_by_id(bid)
		realm.note("industry", "The %s stood idle for want of %s." % [
			str(rec.get("archetype", "building")).replace("_", " "), _starved[bid]])


## Empty workplaces take on whoever is idle and best at it, one each, so the
## town runs without being told to. The player's own placements stand.
func _auto_staff() -> void:
	for rec: Dictionary in realm.town.buildings:
		var chain := chain_for(rec)
		if chain.is_empty() or not staff_of(int(rec["id"])).is_empty():
			continue
		var best: Population.Citizen = null
		var best_skill := -1.0
		for c: Population.Citizen in realm.population.alive():
			if c.workplace_id >= 0:
				continue
			var s := float(c.skills.get(str(chain["job"]), 0.0))
			if s > best_skill:
				best = c
				best_skill = s
		if best != null:
			assign(best, rec)


# ------------------------------------------------------------------ talking

func try_order(worker: Worker, text: String) -> bool:
	var t := text.to_lower()
	# Building orders are the planner's, whatever else they mention.
	if Realm.has_phrase(t, ["build", "put up", "construct", "erect", "make a", "make me",
			"plant", "sow", "demolish", "knock down"]):
		return false
	var rec := _building_in(t)
	# "take Ada off the bakery", "Ada, stop working at the store"
	if Realm.has_phrase(t, [" off the ", " off work", "stop working", "out of the "]):
		var c := _person_in(t)
		if c != null and c.workplace_id >= 0:
			var was := workplace_of(c)
			release(c)
			worker.speak("%s is off the %s." % [c.name, str(was.get("archetype", "work")).replace("_", " ")])
			return true
		if c != null:
			worker.speak("%s was not working anywhere." % c.name)
			return true
	if rec.is_empty():
		return false
	var chain := chain_for(rec)
	# "assign Ada to the bakery", "send Bram to work at the tavern", "put two people in the workshop"
	if Realm.has_word(t, ["assign", "put", "send", "move", "set", "station"]) \
			or Realm.has_phrase(t, ["to work", "work at", "work in"]):
		if chain.is_empty():
			worker.speak("Nobody works a %s — it is a place to live, not a trade." % str(rec["archetype"]).replace("_", " "))
			return true
		var c := _person_in(t)
		var arch := str(rec["archetype"]).replace("_", " ")
		if c != null:
			if staff_of(int(rec["id"])).size() >= STAFF_MAX:
				worker.speak("The %s is full — two is all it can use." % arch)
				return true
			assign(c, rec)
			worker.speak("%s will work the %s from tomorrow." % [c.name, arch])
			realm.note("industry", "%s was set to work at the %s." % [c.name, arch])
			return true
		var n := Realm.count_in(t, 1)
		var placed: Array[String] = []
		for other: Population.Citizen in realm.population.alive():
			if placed.size() >= n or staff_of(int(rec["id"])).size() >= STAFF_MAX:
				break
			if other.workplace_id < 0:
				assign(other, rec)
				placed.append(other.name)
		if placed.is_empty():
			worker.speak("Nobody is free to work the %s." % arch)
		else:
			worker.speak("%s will work the %s." % [" and ".join(placed), arch])
			realm.note("industry", "%s went to work at the %s." % [" and ".join(placed), arch])
		return true
	return false


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["what are people working on", "what is everyone doing",
			"who is working", "what is everyone working", "what are the people doing"]):
		return _everyone_line()
	var rec := _building_in(t)
	if rec.is_empty():
		var c := _person_in(t)
		if c != null and Realm.has_phrase(t, ["where does", "where is", "work"]) \
				and Realm.has_word(t, ["work", "works", "working"]):
			var wp := workplace_of(c)
			if wp.is_empty():
				return "%s has no trade — labouring, mostly." % c.name
			return "%s works at the %s." % [c.name, str(wp["archetype"]).replace("_", " ")]
		return ""
	var arch := str(rec["archetype"]).replace("_", " ")
	var chain := chain_for(rec)
	if Realm.has_phrase(t, ["who works", "who is working", "who is at the", "who runs"]):
		var names: Array[String] = []
		for c: Population.Citizen in staff_of(int(rec["id"])):
			names.append(c.name)
		if names.is_empty():
			return "Nobody works the %s just now." % arch
		return "%s %s the %s." % [" and ".join(names), "works" if names.size() == 1 else "work", arch]
	if Realm.has_phrase(t, ["what does", "what do they make", "what is made", "produce", "need"]):
		if chain.is_empty():
			return "The %s makes nothing — people live there." % arch
		var needs: Array[String] = []
		for k: String in chain["in"]:
			needs.append("%d %s" % [int(chain["in"][k]), k])
		var line := "The %s %s" % [arch, str(chain["does"])]
		if not needs.is_empty():
			line += ", using %s a day per pair of hands" % ", ".join(needs)
		return line + "."
	if Realm.has_phrase(t, ["how is the", "how's the", "hows the", "doing"]):
		var bid := int(rec["id"])
		if chain.is_empty():
			return "The %s is a home; %d live there." % [arch, realm.population._occupants(bid)]
		if staff_of(bid).is_empty():
			return "The %s has nobody in it." % arch
		if _starved.has(bid):
			return "The %s stood idle yesterday — no %s." % [arch, str(_starved[bid])]
		var made: Dictionary = _made.get(bid, {})
		if made.is_empty():
			return "The %s is staffed; give it a day." % arch
		var bits: Array[String] = []
		for k: String in made:
			bits.append("%d %s" % [int(made[k]), k])
		return "The %s made %s yesterday." % [arch, ", ".join(bits)]
	return ""


func _everyone_line() -> String:
	var by_place: Dictionary = {}
	var idle := 0
	for c: Population.Citizen in realm.population.alive():
		var wp := workplace_of(c)
		if wp.is_empty():
			idle += 1
		else:
			var arch := str(wp["archetype"]).replace("_", " ")
			by_place[arch] = int(by_place.get(arch, 0)) + 1
	var bits: Array[String] = []
	for arch: String in by_place:
		bits.append("%d at the %s" % [int(by_place[arch]), arch])
	if idle > 0:
		bits.append("%d labouring" % idle)
	if bits.is_empty():
		return "Nobody is working anything yet."
	var line := "; ".join(bits)
	return line[0].to_upper() + line.substr(1) + "."


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	for bid: int in _starved:
		var rec := realm.population._building_by_id(bid)
		if not rec.is_empty():
			out.append("%s idle · no %s" % [str(rec["archetype"]).replace("_", " "), str(_starved[bid])])
		if out.size() >= 2:
			break
	return out


# ------------------------------------------------------------------ helpers

## The building a sentence names, by the same words the planner uses.
func _building_in(t: String) -> Dictionary:
	var best := ""
	var best_len := 0
	for word: String in ArchetypeLibrary.KEYWORDS:
		if word.length() > best_len and Realm.has_word(t, [word]):
			best = str(ArchetypeLibrary.KEYWORDS[word])
			best_len = word.length()
	if best == "":
		return {}
	return realm.building(best)


func _person_in(t: String) -> Population.Citizen:
	for c: Population.Citizen in realm.population.alive():
		if Realm.has_word(t, [c.name.to_lower()]):
			return c
	return null


func snapshot() -> Dictionary:
	return {"made": _made, "starved": _starved}


func restore(d: Dictionary) -> void:
	_made.clear()
	_starved.clear()
	for k: Variant in d.get("made", {}):
		_made[int(k)] = d["made"][k]
	for k: Variant in d.get("starved", {}):
		_starved[int(k)] = str(d["starved"][k])
