extends Node
## Petitions, counsel, and the names things go by.
##
## Being a king is mostly being asked for things. Each morning a citizen or
## two comes with a petition drawn from what is actually wrong — bread when
## the larder is short, a roof when they are sleeping rough, a pardon for a
## brother on the wanted list — and the king grants or refuses it by saying
## so. Granting does the concrete thing where there is one; refusing is
## remembered by the one refused. Advisers are the hired people with the
## roles for it, and their advice is one line about the thing that most
## needs doing, never a proverb.
##
## The kingdom's name and the titles the king hands out live here too: they
## are court business, and they are the first thing a player wants to say.

const EXPIRE_DAYS := 3
const MAX_OPEN := 6

var realm: Realm
var petitions: Array[Dictionary] = []   ## {id, from, kind, text, day, detail}
var titles: Dictionary = {}             ## citizen name -> title
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	for p: Dictionary in petitions.duplicate():
		if day - int(p["day"]) >= EXPIRE_DAYS:
			petitions.erase(p)
			var c := realm.population.by_name(str(p["from"]))
			if c != null:
				c.mood = clampf(c.mood - 0.05, 0.0, 1.0)
			realm.note("court", "%s's petition went unanswered." % p["from"])
	var n := _rng.randi_range(0, 2)
	for i in n:
		if petitions.size() >= MAX_OPEN:
			break
		var p := _draw()
		if not p.is_empty():
			_file(p)


func _file(p: Dictionary) -> void:
	for have: Dictionary in petitions:
		if have["kind"] == p["kind"] and have["from"] == p["from"]:
			return
	p["id"] = _next_id
	p["day"] = realm.clock.day
	_next_id += 1
	petitions.append(p)
	realm.say("%s asks to see you: %s" % [p["from"], p["text"]])


## One petition drawn from the state of the town, or {} when there is
## nothing anyone would ask for.
func _draw() -> Dictionary:
	var pop := realm.population
	var people := pop.alive()
	if people.is_empty():
		return {}
	var pool: Array[Dictionary] = []
	for c: Population.Citizen in people:
		if float(c.needs["fed"]) < 0.5:
			pool.append({"from": c.name, "kind": "bread", "text": "\"We have not eaten properly in days. Bread, my lord.\""})
		if c.home_id < 0:
			pool.append({"from": c.name, "kind": "roof", "text": "\"A roof, before the cold. Anywhere with a bed.\""})
	var mk: Node = realm.system("Market")
	if mk != null and float(mk.get("rate")) > 0.15:
		var who: Population.Citizen = people[_rng.randi() % people.size()]
		pool.append({"from": who.name, "kind": "tax", "text": "\"The tax takes more than we can spare. Ease it.\""})
	var law: Node = realm.system("Law")
	if law != null:
		var wanted: Array = law.get("wanted")
		if not wanted.is_empty():
			var w: Dictionary = wanted[_rng.randi() % wanted.size()]
			var kin: Population.Citizen = people[_rng.randi() % people.size()]
			if kin.name != str(w["name"]):
				pool.append({"from": kin.name, "kind": "pardon", "detail": str(w["name"]),
					"text": "\"%s did wrong, but it was hunger. Pardon them.\"" % w["name"]})
	var up: Node = realm.system("Upkeep")
	if up != null and up.has_method("worst"):
		var worst: Dictionary = up.call("worst")
		if not worst.is_empty():
			var who2: Population.Citizen = people[_rng.randi() % people.size()]
			pool.append({"from": who2.name, "kind": "repair", "detail": str(worst.get("archetype", "")),
				"text": "\"The %s is falling apart. Send someone to mend it.\"" % str(worst.get("archetype", "building")).replace("_", " ")})
	# Couples asking leave to marry.
	var single: Array[Population.Citizen] = []
	for c2: Population.Citizen in people:
		if c2.spouse_id < 0 and c2.mood > 0.6:
			single.append(c2)
	if single.size() >= 2 and _rng.randf() < 0.3:
		var a: Population.Citizen = single[_rng.randi() % single.size()]
		var b: Population.Citizen = single[_rng.randi() % single.size()]
		if a != b:
			pool.append({"from": a.name, "kind": "marry", "detail": b.name,
				"text": "\"%s and I would marry, with your blessing.\"" % b.name})
	# Always something small to ask for.
	if _rng.randf() < 0.4:
		var who3: Population.Citizen = people[_rng.randi() % people.size()]
		var small: Dictionary = [
			{"kind": "road", "text": "\"The lane by my door is mud to the knee. Cobbles, my lord?\""},
			{"kind": "market", "text": "\"A market day more often would do us all good.\""},
			{"kind": "well", "text": "\"The well is a long walk from the far row. A second one?\""},
		][_rng.randi() % 3]
		pool.append({"from": who3.name, "kind": small["kind"], "text": small["text"]})
	if pool.is_empty():
		return {}
	return pool[_rng.randi() % pool.size()]


# ---------------------------------------------------------------- decisions

func grant(p: Dictionary, worker: Worker) -> String:
	var c := realm.population.by_name(str(p["from"]))
	var line := ""
	match str(p["kind"]):
		"bread":
			var food := int(realm.town.stock.get("food", 0))
			if food < 20:
				return "We have only %d food in the larder; there is nothing to give." % food
			realm.town.stock["food"] = food - 20
			if c != null:
				c.needs["fed"] = 1.0
			line = "%s goes home with bread." % p["from"]
		"roof":
			if c != null:
				for rec: Dictionary in realm.town.buildings:
					if realm.population._beds_in(rec) > realm.population._occupants(int(rec["id"])):
						c.home_id = int(rec["id"])
						line = "%s has a bed in the %s." % [p["from"], str(rec["archetype"]).replace("_", " ")]
						break
			if line == "":
				return "There is no bed free anywhere. Build a cottage and ask me again."
		"tax":
			var mk: Node = realm.system("Market")
			if mk != null:
				mk.set("rate", maxf(float(mk.get("rate")) - 0.05, 0.0))
				line = "The tax eases to %d percent." % int(round(float(mk.get("rate")) * 100.0))
			else:
				line = "The tax will be eased."
		"pardon":
			var law: Node = realm.system("Law")
			if law != null and law.has_method("pardon"):
				law.call("pardon", str(p["detail"]))
			line = "%s is pardoned." % p["detail"]
		"repair":
			var up: Node = realm.system("Upkeep")
			if up != null and up.has_method("try_order"):
				up.call("try_order", worker, "repair the %s" % str(p["detail"]).replace("_", " "))
			line = "The %s will be mended." % str(p["detail"]).replace("_", " ")
		"marry":
			var dy: Node = realm.system("Dynasty")
			if dy != null and dy.has_method("wed_citizens"):
				dy.call("wed_citizens", str(p["from"]), str(p["detail"]))
			else:
				var b := realm.population.by_name(str(p["detail"]))
				if c != null and b != null:
					c.spouse_id = b.id
					b.spouse_id = c.id
			line = "%s and %s have your blessing." % [p["from"], p["detail"]]
		_:
			line = "%s is told it will be seen to." % p["from"]
	if c != null:
		c.mood = clampf(c.mood + 0.15, 0.0, 1.0)
	petitions.erase(p)
	realm.note("court", "Granted %s's petition: %s" % [p["from"], line])
	return line


func refuse(p: Dictionary) -> String:
	var c := realm.population.by_name(str(p["from"]))
	if c != null:
		c.mood = clampf(c.mood - 0.1, 0.0, 1.0)
	petitions.erase(p)
	realm.note("court", "Refused %s's petition." % p["from"])
	return "%s is sent away with nothing." % p["from"]


# ------------------------------------------------------------------ talking

const TITLES := ["steward", "marshal", "treasurer", "chancellor", "sheriff", "captain",
	"reeve", "bailiff", "chamberlain", "healer", "master"]


func verbs() -> Dictionary:
	return {
		"name_kingdom": {
			"says": "give the kingdom its name",
			"required": ["name"],
			"instant": true,
		},
		"appoint": {
			"says": "give a named person a title at court",
			"required": ["who", "title"],
			"types": {"title": TITLES},
			"instant": true,
		},
		"hold_court": {
			"says": "hear the petitions waiting",
			"instant": true,
		},
		"petition": {
			"says": "grant or refuse a petition: the first waiting, one from a named person, or all of them",
			"required": ["answer"],
			"optional": ["who", "all"],
			"types": {"answer": ["grant", "refuse"], "all": ["yes", "no"]},
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"name_kingdom":
			var name := str(step.get("name", "")).strip_edges()
			if name == "":
				return "What is it to be called?"
			realm.kingdom_name = name
			worker.speak("%s. It has a ring to it." % name)
			realm.note("court", "The kingdom was named %s." % name)
			return "done"
		"appoint":
			var c := realm.population.by_name(str(step.get("who", "")))
			if c == null:
				return "There is nobody here called %s." % str(step.get("who", "")).capitalize()
			var title := str(step.get("title", "")).to_lower()
			for other: String in titles.keys():
				if titles[other] == title:
					titles.erase(other)
			titles[c.name] = title
			if title == "healer":
				var hl: Node = realm.system("Health")
				if hl != null:
					hl.set("healer_id", c.worker_id)
			worker.speak("%s is %s of %s." % [c.name, title.capitalize(), realm.kingdom_name])
			realm.note("court", "%s was made %s." % [c.name, title])
			return "done"
		"hold_court":
			worker.speak(_list_line())
			return "done"
		"petition":
			if petitions.is_empty():
				worker.speak("There are no petitions waiting.")
				return "done"
			var granting := str(step.get("answer", "grant")) == "grant"
			var targets: Array[Dictionary] = []
			if str(step.get("all", "no")) == "yes":
				targets = petitions.duplicate()
			else:
				var who := str(step.get("who", "")).strip_edges().to_lower()
				for p: Dictionary in petitions:
					if who != "" and str(p["from"]).to_lower() == who:
						targets = [p]
						break
				if targets.is_empty():
					targets = [petitions[0]]
			var lines: Array[String] = []
			for p2: Dictionary in targets:
				lines.append(grant(p2, worker) if granting else refuse(p2))
			worker.speak(" ".join(lines))
			return "done"
	return "failed"


func try_answer(worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["any petitions", "who wants to see me", "petitions waiting", "what do people ask",
			"anyone asking", "what petitions", "who is asking"]):
		return _list_line()
	if Realm.has_phrase(t, ["what do you advise", "any advice", "what should i do", "what would you do",
			"your counsel", "advise me", "what needs doing"]):
		return _advice(worker)
	if Realm.has_phrase(t, ["kingdom called", "name of the kingdom", "name of this place", "what is this kingdom",
			"what is this place called", "kingdom's name"]):
		return "This is %s." % realm.kingdom_name if realm.kingdom_name != "the town" else "The kingdom has no name yet. Give it one."
	for title: String in ["steward", "marshal", "treasurer", "chancellor", "sheriff", "captain", "reeve",
			"bailiff", "chamberlain", "healer", "master"]:
		if Realm.has_phrase(t, ["who is the " + title, "who is " + title, "who is my " + title]):
			for name: String in titles:
				if titles[name] == title:
					return "%s is the %s." % [name, title]
			return "Nobody holds that office. Appoint someone."
	return ""


func _list_line() -> String:
	if petitions.is_empty():
		return "Nobody is waiting on you."
	var bits: Array[String] = []
	for p: Dictionary in petitions:
		bits.append("%s: %s" % [p["from"], p["text"]])
	return "%d waiting. %s" % [petitions.size(), " ".join(bits)]


## The one thing that most needs doing, from the numbers.
func _advice(worker: Worker) -> String:
	var pop := realm.population
	var town := realm.town
	var who := worker.display_name()
	if town.coins < 0:
		return "%s: the purse is %d in debt. Sell timber or set a tax before anything else." % [who, -town.coins]
	if int(town.stock.get("food", 0)) < pop.count() * 2:
		return "%s: the larder holds %d food for %d people. A field, a barn, or buy grain." % [who, int(town.stock.get("food", 0)), pop.count()]
	if pop.homeless() > 0:
		return "%s: %d people sleep rough. A cottage holds three." % [who, pop.homeless()]
	if realm.warfare != null and realm.warfare.soldiers.is_empty():
		var raid_day := int(realm.warfare.get("_next_raid_day"))
		if raid_day > 0:
			return "%s: no soldiers, and riders are due about day %d. A barracks and a few recruits." % [who, raid_day]
	var ind: Node = realm.system("Industry")
	if ind != null:
		for rec: Dictionary in town.buildings:
			if not (ind.call("chain_for", rec) as Dictionary).is_empty() and (ind.call("staff_of", int(rec["id"])) as Array).is_empty():
				return "%s: the %s has nobody working it." % [who, str(rec["archetype"]).replace("_", " ")]
	if pop.mood_avg() < 0.5:
		return "%s: people are %s. A feast, or ease the tax." % [who, pop.mood_word()]
	return "%s: things are in hand. Build outward, and keep the larder full." % who


func _person_in(t: String) -> Population.Citizen:
	for c: Population.Citizen in realm.population.alive():
		if Realm.has_word(t, [c.name.to_lower()]):
			return c
	return null


static func _tail(text: String, anchors: Array) -> String:
	var low := text.to_lower()
	var best := -1
	for a: String in anchors:
		var i := low.rfind(" " + a + " ")
		if i >= 0 and i + a.length() + 2 > best:
			best = i + a.length() + 2
	if best < 0:
		return ""
	var rest := text.substr(best).strip_edges().trim_suffix(".").trim_suffix("!")
	for lead: String in ["shall be called ", "is called ", "will be called ", "as ", "the "]:
		if rest.to_lower().begins_with(lead):
			rest = rest.substr(lead.length())
	if rest == "" or rest.length() > 30:
		return ""
	return rest.capitalize()


func snapshot() -> Dictionary:
	return {"petitions": petitions, "titles": titles, "next_id": _next_id}


func restore(d: Dictionary) -> void:
	petitions.clear()
	for p: Variant in d.get("petitions", []):
		if p is Dictionary:
			petitions.append(p)
	titles = {}
	for k: Variant in d.get("titles", {}):
		titles[str(k)] = str(d["titles"][k])
	_next_id = int(d.get("next_id", petitions.size() + 1))
