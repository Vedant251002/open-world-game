extends Node
## The royal house: the king, a consort, heirs, and who comes next.
##
## The player is the king, but the king is a record — a name, an age, a
## spouse, children — so that when the king falls the crown passes rather
## than the game ending, and so that later, when there is more than one
## player in a world, "the king" can be one of them and not a global. A
## wedding is a day the whole town turns out for; a child is a line in the
## chronicle who, sixteen years of game days on, walks into town as a
## citizen with the family name. Citizens marry among themselves too, which
## is most of what makes a town a town rather than a barracks.

const DAYS_PER_YEAR := 48
const START_AGE := 25
const COMING_OF_AGE := 16
const WEDDING_WAIT_DAYS := 2

var realm: Realm
var king := {"name": "the King", "title": "King", "born_day": 0, "consort": "", "wed_day": -1}
var children: Array[Dictionary] = []   ## {name, born_day, alive, came_of_age}
var wedding: Dictionary = {}           ## {who, day}
var regent := ""
var _rng := RandomNumberGenerator.new()
var _last_child_day := -100


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	king["born_day"] = -START_AGE * DAYS_PER_YEAR


# ------------------------------------------------------------------- public

func king_age() -> int:
	return (realm.clock.day - int(king["born_day"])) / DAYS_PER_YEAR


func heirs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in children:
		if bool(c["alive"]):
			out.append(c)
	return out


func heir_name() -> String:
	var h := heirs()
	return str(h[0]["name"]) if not h.is_empty() else ""


func child_age(c: Dictionary) -> int:
	return (realm.clock.day - int(c["born_day"])) / DAYS_PER_YEAR


## Two citizens marry, with the town's blessing. Court calls this for a
## granted petition; the daily roll calls it for couples who did not ask.
func wed_citizens(a_name: String, b_name: String) -> bool:
	var a := realm.population.by_name(a_name)
	var b := realm.population.by_name(b_name)
	if a == null or b == null or a == b or a.spouse_id >= 0 or b.spouse_id >= 0:
		return false
	a.spouse_id = b.id
	b.spouse_id = a.id
	a.mood = clampf(a.mood + 0.2, 0.0, 1.0)
	b.mood = clampf(b.mood + 0.2, 0.0, 1.0)
	if a.home_id >= 0 and b.home_id < 0:
		b.home_id = a.home_id
	elif b.home_id >= 0 and a.home_id < 0:
		a.home_id = b.home_id
	realm.note("wedding", "%s and %s were married." % [a.name, b.name])
	realm.say("%s and %s were married today." % [a.name, b.name])
	return true


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	# The royal wedding.
	if not wedding.is_empty() and day >= int(wedding["day"]):
		var who := str(wedding["who"])
		wedding = {}
		king["consort"] = who
		king["wed_day"] = day
		var c := realm.population.by_name(who)
		if c != null:
			c.mood = 1.0
		for other: Population.Citizen in realm.population.alive():
			other.mood = clampf(other.mood + 0.1, 0.0, 1.0)
		var faith: Node = realm.system("Faith")
		if faith != null and faith.has_method("feast"):
			faith.call("feast", "the royal wedding")
		realm.say("The %s has married %s. The whole town turned out." % [str(king["title"]).to_lower(), who])
		realm.note("wedding", "The %s married %s." % [str(king["title"]).to_lower(), who])
	# Children come, and come of age.
	if str(king["consort"]) != "" and day - _last_child_day >= 10 and day - int(king["wed_day"]) >= 10 \
			and _rng.randf() < 0.05:
		var name := _free_name()
		if name != "":
			children.append({"name": name, "born_day": day, "alive": true, "came_of_age": false})
			_last_child_day = day
			realm.say("A child is born to the royal house: %s." % name)
			realm.note("birth", "%s was born to the %s and %s." % [name, str(king["title"]).to_lower(), king["consort"]])
	for c2: Dictionary in children:
		if bool(c2["alive"]) and not bool(c2["came_of_age"]) and child_age(c2) >= COMING_OF_AGE:
			c2["came_of_age"] = true
			_come_of_age(str(c2["name"]))
	# Citizens marry among themselves.
	if _rng.randf() < 0.06:
		var single: Array[Population.Citizen] = []
		for c3: Population.Citizen in realm.population.alive():
			if c3.spouse_id < 0 and c3.mood > 0.6 and c3.name != str(king["consort"]):
				single.append(c3)
		if single.size() >= 2:
			var a: Population.Citizen = single[_rng.randi() % single.size()]
			var b: Population.Citizen = single[_rng.randi() % single.size()]
			if a != b:
				wed_citizens(a.name, b.name)


func on_hour(_hour: float, _day: int) -> void:
	# Warfare puts the player back to a hundred when they fall; the death is
	# seen here as the health having just been reset from a hit. The
	# warfare status line says "knocked down"; this decides who wears the
	# crown after.
	if realm.warfare == null:
		return
	if bool(realm.warfare.get("player_fell")) and realm.warfare.has_method("clear_fell"):
		realm.warfare.call("clear_fell")
		_succession()


func _come_of_age(name: String) -> void:
	if realm.crew == null:
		return
	var before := realm.crew.citizens().size()
	realm.crew.spawn_citizens(1, hash(name) ^ realm.clock.day, realm.village.bounds_v)
	var after := realm.crew.citizens()
	if after.size() > before:
		var w: Worker = after[after.size() - 1]
		var old_id: String = w.memory.worker_id
		w.memory.display_name = name
		w.memory.worker_id = "cit_" + name.to_lower() + "_r"
		w.name = name
		realm.crew.by_id.erase(old_id)
		realm.crew.by_id[w.memory.worker_id] = w
		realm.population._sync()
		var c := realm.population.for_worker(w)
		if c != null:
			c.name = name
			c.age = COMING_OF_AGE
	realm.say("%s of the royal house has come of age." % name)
	realm.note("dynasty", "%s came of age and took a place in the town." % name)


## The crown passes to the eldest living child; failing that, a regent
## holds it and the line is noted as ended. The player plays on either way.
func _succession() -> void:
	var old := str(king["name"])
	realm.note("death", "The %s %s fell." % [str(king["title"]).to_lower(), old])
	var h := heirs()
	if not h.is_empty():
		var heir: Dictionary = h[0]
		heir["alive"] = true
		children.erase(heir)
		king["name"] = str(heir["name"])
		king["born_day"] = int(heir["born_day"])
		king["consort"] = ""
		king["wed_day"] = -1
		realm.say("%s is dead. Long live %s %s!" % [old, king["title"], king["name"]])
		realm.note("succession", "%s took the crown." % king["name"])
	else:
		var mayor := ""
		for w: Worker in realm.crew.hired():
			if w.role != null and w.role.id == "mayor":
				mayor = w.display_name()
		regent = mayor if mayor != "" else "the council"
		realm.say("%s is dead, and there is no heir. %s holds the town for now." % [old, regent.capitalize()])
		realm.note("succession", "The line ended; %s rules as regent." % regent)
	if realm.player != null and realm.player.has_method("teleport"):
		realm.player.teleport(realm.village.spawn_pos + Vector3(0, 1.0, 0), PI)


func _free_name() -> String:
	var used := {}
	for c: Population.Citizen in realm.population.people:
		used[c.name] = true
	for ch: Dictionary in children:
		used[ch["name"]] = true
	var pool := Crew.CITIZEN_NAMES.duplicate()
	pool.shuffle()
	for n: String in pool:
		if not used.has(n):
			return n
	return ""


# ------------------------------------------------------------------ talking

func verbs() -> Dictionary:
	return {
		"name_ruler": {
			"says": "your employer says what to call them: their name, and king or queen",
			"optional": ["name", "title"],
			"types": {"title": ["King", "Queen"]},
			"instant": true,
		},
		"marry": {
			"says": "a wedding: your employer to a named citizen, or two named citizens to each other",
			"required": ["who"],
			"optional": ["to"],
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"name_ruler":
			if step.has("title"):
				king["title"] = str(step["title"])
			var name := str(step.get("name", "")).strip_edges()
			if name != "" and name.to_lower() not in ["king", "queen", "the king", "the queen"]:
				king["name"] = name
			worker.speak("%s %s. As you say." % [king["title"], king["name"]])
			realm.note("court", "The ruler is %s %s." % [king["title"], king["name"]])
			return "done"
		"marry":
			var first := realm.population.by_name(str(step.get("who", "")))
			if first == null:
				return "Marry whom? Name someone in the town."
			var other := str(step.get("to", "")).strip_edges().to_lower()
			if other != "" and other not in ["me", "you", "the king", "the queen", "king", "queen"]:
				var second := realm.population.by_name(other)
				if second == null:
					return "There is nobody here called %s." % other.capitalize()
				# "marry Ada to Bram" is the town's business, not the crown's.
				if wed_citizens(first.name, second.name):
					worker.speak("%s and %s are wed." % [first.name, second.name])
				else:
					worker.speak("One of them is already married.")
				return "done"
			if str(king["consort"]) != "":
				return "You are married to %s already." % king["consort"]
			if first.spouse_id >= 0:
				return "%s is married already." % first.name
			if first.mood < 0.5:
				worker.speak("%s thanks you, but no. Not as things stand." % first.name)
				realm.note("court", "%s declined the %s's hand." % [first.name, str(king["title"]).to_lower()])
				return "done"
			wedding = {"who": first.name, "day": realm.clock.day + WEDDING_WAIT_DAYS}
			worker.speak("%s says yes. The wedding is in %d days." % [first.name, WEDDING_WAIT_DAYS])
			realm.note("court", "%s accepted the %s's hand; a wedding in %d days." % [first.name, str(king["title"]).to_lower(), WEDDING_WAIT_DAYS])
			return "done"
	return "failed"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["who is my heir", "my heir", "who comes after me", "who succeeds me", "the succession"]):
		var h := heirs()
		if h.is_empty():
			return "You have no heir. Marry, and the line may come." if str(king["consort"]) == "" else "No children yet."
		var bits: Array[String] = []
		for c: Dictionary in h:
			bits.append("%s, %d" % [c["name"], child_age(c)])
		return "Your heir is %s. Then %s." % [bits[0], ", ".join(bits.slice(1))] if bits.size() > 1 else "Your heir is %s." % bits[0]
	if Realm.has_phrase(t, ["my wife", "my husband", "my consort", "my queen", "my king", "am i married"]):
		if str(king["consort"]) == "":
			return "You are not married."
		return "You married %s on day %d." % [king["consort"], int(king["wed_day"])]
	if Realm.has_phrase(t, ["my family", "the royal house", "my children", "my line", "my house"]):
		var out := "%s %s, %d" % [king["title"], king["name"], king_age()]
		if str(king["consort"]) != "":
			out += ", married to %s" % king["consort"]
		var h2 := heirs()
		if h2.is_empty():
			out += "; no children"
		else:
			var kids: Array[String] = []
			for c2: Dictionary in h2:
				kids.append("%s (%d)" % [c2["name"], child_age(c2)])
			out += "; children %s" % ", ".join(kids)
		if regent != "":
			out += "; %s rules as regent" % regent
		return out + "."
	if Realm.has_phrase(t, ["how old am i", "my age"]):
		return "You are %d." % king_age()
	if Realm.has_phrase(t, ["who am i", "what is my name", "who is the king", "who is the queen", "who rules"]):
		return "%s %s rules here." % [king["title"], king["name"]] if regent == "" else "%s rules as regent." % regent.capitalize()
	if Realm.has_phrase(t, ["is anyone married", "who is married", "any couples"]):
		var pairs: Array[String] = []
		var seen := {}
		for c3: Population.Citizen in realm.population.alive():
			if c3.spouse_id >= 0 and not seen.has(c3.id):
				var sp := realm.population._by_id(c3.spouse_id)
				if sp != null:
					seen[c3.id] = true
					seen[sp.id] = true
					pairs.append("%s and %s" % [c3.name, sp.name])
		return "No couples yet." if pairs.is_empty() else "Married: %s." % "; ".join(pairs)
	return ""


func hud_lines() -> Array[String]:
	if not wedding.is_empty() and int(wedding["day"]) - realm.clock.day == 1:
		return ["wedding tomorrow"]
	return []


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
	if rest.to_lower().begins_with("the "):
		rest = rest.substr(4)
	if rest == "" or rest.length() > 24:
		return ""
	return rest.capitalize()


func snapshot() -> Dictionary:
	return {"king": king, "children": children, "wedding": wedding, "regent": regent,
		"last_child_day": _last_child_day}


func restore(d: Dictionary) -> void:
	if d.has("king"):
		king = d["king"]
	children.clear()
	for c: Variant in d.get("children", []):
		if c is Dictionary:
			children.append(c)
	wedding = d.get("wedding", {})
	regent = str(d.get("regent", ""))
	_last_child_day = int(d.get("last_child_day", -100))
