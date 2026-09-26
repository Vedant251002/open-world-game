extends Node
## Decrees, and what happens at night when nobody is watching.
##
## A king's word becomes a standing rule: a curfew, a ban on ale, longer
## hours, open borders. Each is a switch with a real effect somewhere else in
## the kingdom (the market reads the tax holiday, industry the working
## hours, the population the borders) and a cost in how the people feel
## about it. Anything the player decrees that nothing here has a lever for is
## kept as a law all the same — remembered, listed, repealable — because a
## rule the king made and the town forgot is worse than one with no teeth.
##
## Crime is the other half. Hungry, homeless, unhappy people steal from the
## yard and fight in the street; soldiers and a watch-house make them think
## twice. A culprit gets a name, and the king decides what to do with it.

const KNOWN := {
	"curfew": {"words": ["curfew"], "line": "a curfew after dark"},
	"no_ale": {"words": ["ale", "drink", "drinking", "beer"], "line": "no ale in the tavern"},
	"long_hours": {"words": ["long hours", "longer hours", "work longer", "work harder", "more hours"], "line": "long working hours"},
	"short_hours": {"words": ["short hours", "shorter hours", "work less", "fewer hours", "rest day"], "line": "short working hours"},
	"conscription": {"words": ["conscription", "conscript", "levy", "draft"], "line": "conscription"},
	"closed_borders": {"words": ["close the borders", "closed borders", "border closed", "no newcomers", "shut the gates",
		"open the borders", "reopen the borders", "open the gates", "borders open"], "line": "closed borders"},
	"free_bread": {"words": ["free bread", "bread for all", "feed everyone", "free food"], "line": "free bread for all"},
	"tax_holiday": {"words": ["tax holiday", "no taxes this", "suspend the tax", "suspend taxes"], "line": "a tax holiday"},
}
const JAIL_DAYS := 3
const JAIL_ARCHETYPES := ["barracks", "guard_post", "watchtower"]

var realm: Realm
var decrees: Dictionary = {}       ## id -> {on, text, day}
var wanted: Array[Dictionary] = [] ## {name, crime, day}
var jailed: Dictionary = {}        ## name -> release day
var _rng := RandomNumberGenerator.new()
var _last_night := ""


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()


# ------------------------------------------------------------------- levers

func is_on(id: String) -> bool:
	return decrees.has(id) and bool(decrees[id]["on"])


func work_rate() -> float:
	if is_on("long_hours"):
		return 1.25
	if is_on("short_hours"):
		return 0.8
	return 1.0


func ale_allowed() -> bool:
	return not is_on("no_ale")


func recruit_discount() -> float:
	return 0.5 if is_on("conscription") else 1.0


func borders_open() -> bool:
	return not is_on("closed_borders")


func tax_holiday() -> bool:
	return is_on("tax_holiday")


func pardon(name: String) -> bool:
	var hit := false
	for w: Dictionary in wanted.duplicate():
		if str(w["name"]).to_lower() == name.to_lower():
			wanted.erase(w)
			hit = true
	for j: String in jailed.keys():
		if j.to_lower() == name.to_lower():
			jailed.erase(j)
			_send_home(j)
			hit = true
	if hit:
		realm.note("law", "%s was pardoned." % name.capitalize())
	return hit


func guarded() -> bool:
	for a: String in JAIL_ARCHETYPES:
		if not realm.building(a).is_empty():
			return true
	return false


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	_last_night = ""
	# Releases.
	for name: String in jailed.keys():
		if day >= int(jailed[name]):
			jailed.erase(name)
			_send_home(name)
			realm.note("law", "%s was let out." % name)
	# What the decrees cost, felt a little each day.
	var pop := realm.population
	var nudge := 0.0
	if is_on("curfew"):
		nudge -= 0.01
	if is_on("no_ale"):
		nudge -= 0.01
	if is_on("long_hours"):
		nudge -= 0.015
	if is_on("short_hours"):
		nudge += 0.01
	if is_on("free_bread"):
		var extra := pop.count() / 2
		var food := int(realm.town.stock.get("food", 0))
		if food >= extra:
			realm.town.stock["food"] = food - extra
			nudge += 0.02
	for c: Population.Citizen in pop.alive():
		c.mood = clampf(c.mood + nudge, 0.0, 1.0)
	_night(day)


## A theft or a brawl, with odds that read the town.
func _night(day: int) -> void:
	var pop := realm.population
	if pop.count() < 2:
		return
	var chance := 0.06 + 0.02 * pop.hungry() + 0.02 * pop.homeless()
	if pop.mood_avg() < 0.4:
		chance += 0.1
	if realm.warfare != null:
		chance -= 0.03 * realm.warfare.soldiers.size()
	if guarded():
		chance -= 0.08
	if is_on("curfew"):
		chance -= 0.05
	chance = clampf(chance, 0.0, 0.5)
	if _rng.randf() >= chance:
		return
	var people := pop.alive()
	var culprit: Population.Citizen = people[_rng.randi() % people.size()]
	if jailed.has(culprit.name):
		return
	if _rng.randf() < 0.65:
		var kinds: Array[String] = []
		for k: String in realm.town.stock:
			if int(realm.town.stock[k]) > 20:
				kinds.append(k)
		if kinds.is_empty():
			return
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var n := _rng.randi_range(5, 30)
		realm.town.stock[kind] = int(realm.town.stock[kind]) - n
		wanted.append({"name": culprit.name, "crime": "stole %d %s" % [n, kind], "day": day})
		_last_night = "%d %s went missing from the yard in the night — %s, they say." % [n, kind, culprit.name]
	else:
		var victim: Population.Citizen = people[_rng.randi() % people.size()]
		if victim == culprit:
			return
		var vw := victim.worker(realm.crew)
		if vw != null:
			vw.health = maxf(vw.health - 20.0, 5.0)
		wanted.append({"name": culprit.name, "crime": "beat %s in the street" % victim.name, "day": day})
		_last_night = "%s and %s fought in the street; %s came off worse." % [culprit.name, victim.name, victim.name]
	if wanted.size() > 8:
		wanted = wanted.slice(wanted.size() - 8)
	realm.say(_last_night)
	realm.note("crime", _last_night)


func _send_home(name: String) -> void:
	var c := realm.population.by_name(name)
	var w := c.worker(realm.crew) if c != null else null
	if w != null:
		if not w.job_errand.is_empty():
			w.drop_everything()
		w.walk_to(w.home, "idle")


# ------------------------------------------------------------------ talking

## Justice and decrees, as verbs. A decree is one of the known levers by
## id, or a custom law in the king's own words; both are lifted the same way.
func verbs() -> Dictionary:
	var ids: Array = KNOWN.keys()
	ids.append("custom")
	return {
		"decree": {
			"says": "make a law: one of the known ones by name, or 'custom' with the law in words",
			"required": ["law"],
			"optional": ["text"],
			"types": {"law": ids},
			"instant": true,
		},
		"repeal": {
			"says": "lift a law: a known one by name, or 'custom' with enough of its words to find it",
			"required": ["law"],
			"optional": ["text"],
			"types": {"law": ids},
			"instant": true,
		},
		"jail": {
			"says": "lock a named person in the cells for some days",
			"required": ["who"],
			"optional": ["days"],
			"types": {"days": "int"},
			"instant": true,
		},
		"fine": {
			"says": "fine a named person some coins",
			"required": ["who"],
			"optional": ["coins"],
			"types": {"coins": "int"},
			"instant": true,
		},
		"pardon": {
			"says": "forgive a named person whatever they are accused of",
			"required": ["who"],
			"instant": true,
		},
		"banish": {
			"says": "send a named person out of the town for good",
			"required": ["who"],
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	var verb := str(step.get("do", ""))
	if verb in ["jail", "fine", "pardon", "banish"]:
		var who := str(step.get("who", "")).strip_edges()
		var c := realm.population.by_name(who)
		if c == null:
			return "There is nobody here called %s." % who.capitalize()
		match verb:
			"jail":
				return _jail(worker, c, int(step.get("days", JAIL_DAYS)))
			"fine":
				var n := int(step.get("coins", 20))
				realm.town.coins += n
				c.mood = clampf(c.mood - 0.15, 0.0, 1.0)
				_strike(c.name)
				worker.speak("%s pays %d coins to the purse." % [c.name, n])
				realm.note("law", "%s was fined %d coins." % [c.name, n])
				return "done"
			"pardon":
				if pardon(c.name):
					worker.speak("%s is forgiven." % c.name)
				else:
					worker.speak("%s was not accused of anything." % c.name)
				return "done"
			"banish":
				realm.note("law", "%s was banished from the town." % c.name)
				worker.speak("%s is banished. They leave today." % c.name)
				_strike(c.name)
				realm.population.kill(c, "banished")
				return "done"
	if verb == "decree" or verb == "repeal":
		var law := str(step.get("law", "")).strip_edges().to_lower()
		var on := verb == "decree"
		if KNOWN.has(law):
			if law in ["long_hours", "short_hours"] and on:
				decrees.erase("short_hours" if law == "long_hours" else "long_hours")
			_decree(worker, law, str(KNOWN[law]["line"]), on)
			return "done"
		var body := str(step.get("text", "")).strip_edges()
		if body == "":
			return "What is the law to be?" if on else "Which law?"
		if on:
			_decree(worker, "custom_" + str(hash(body.to_lower())), body, true)
			return "done"
		for id2: String in decrees:
			if id2.begins_with("custom_") and str(decrees[id2]["text"]).to_lower().find(body.to_lower().substr(0, 12)) >= 0:
				var text := str(decrees[id2]["text"])
				decrees.erase(id2)
				worker.speak("That law is struck out.")
				realm.note("law", "The law \"%s\" was repealed." % text)
				return "done"
		return "We have no such law."
	return "failed"


func _decree(worker: Worker, id: String, line: String, on: bool) -> bool:
	if on:
		decrees[id] = {"on": true, "text": line, "day": realm.clock.day}
		worker.speak("So decreed: %s." % line)
		realm.note("decree", "The king decreed %s." % line)
	else:
		if not decrees.has(id):
			worker.speak("There was no such rule.")
			return true
		decrees.erase(id)
		worker.speak("The rule is lifted: no more %s." % line)
		realm.note("decree", "The decree of %s was lifted." % line)
	return true


func _jail(worker: Worker, c: Population.Citizen, days: int) -> String:
	var cell: Dictionary = {}
	for a: String in JAIL_ARCHETYPES:
		cell = realm.building(a)
		if not cell.is_empty():
			break
	if cell.is_empty():
		return "We have nowhere to hold %s. A guard post or a barracks would do." % c.name
	var w := c.worker(realm.crew)
	jailed[c.name] = realm.clock.day + maxi(days, 1)
	_strike(c.name)
	if w != null:
		if not w.job_errand.is_empty():
			w.drop_everything()
		w.stop_wandering()
		w.take_errand_job("wait", realm.door_of(cell), float(days) * 24.0, "",
			{"where": "the cells", "doing": "plan"})
	worker.speak("%s goes to the cells for %d days." % [c.name, days])
	realm.note("law", "%s was jailed for %d days." % [c.name, days])
	return "done"


func _strike(name: String) -> void:
	for w: Dictionary in wanted.duplicate():
		if str(w["name"]) == name:
			wanted.erase(w)


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["what are the laws", "what laws", "which laws", "the decrees", "what have i decreed",
			"any laws", "list the laws", "what rules"]):
		if decrees.is_empty():
			return "No decrees stand. The town runs on custom."
		var bits: Array[String] = []
		for id: String in decrees:
			bits.append(str(decrees[id]["text"]))
		return "The law says: %s." % "; ".join(bits)
	if Realm.has_phrase(t, ["is there a curfew", "curfew"]):
		return "There is a curfew after dark." if is_on("curfew") else "No curfew."
	if Realm.has_phrase(t, ["who is wanted", "any criminals", "who is a criminal", "wanted list", "any thieves"]):
		if wanted.is_empty():
			return "Nobody is wanted for anything."
		var bits2: Array[String] = []
		for w: Dictionary in wanted:
			bits2.append("%s, who %s" % [w["name"], w["crime"]])
		return "Wanted: %s." % "; ".join(bits2)
	if Realm.has_phrase(t, ["who is in jail", "who is in the cells", "anyone in jail", "who is locked up"]):
		if jailed.is_empty():
			return "The cells are empty."
		var bits3: Array[String] = []
		for name: String in jailed:
			bits3.append("%s until day %d" % [name, int(jailed[name])])
		return "In the cells: %s." % ", ".join(bits3)
	if Realm.has_phrase(t, ["any crime", "last night", "any trouble in the night", "was anything stolen"]):
		return _last_night if _last_night != "" else "A quiet night."
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if is_on("curfew"):
		out.append("curfew")
	if not wanted.is_empty():
		out.append("%d wanted" % wanted.size())
	return out


func _person_in(t: String) -> Population.Citizen:
	for c: Population.Citizen in realm.population.alive():
		if Realm.has_word(t, [c.name.to_lower()]):
			return c
	return null


static func _after(text: String, anchors: Array) -> String:
	var low := text.to_lower()
	var best := -1
	for a: String in anchors:
		var i := low.find(" " + a + " ")
		if i >= 0 and (best < 0 or i + a.length() + 2 > best):
			best = i + a.length() + 2
	if best < 0:
		return ""
	return text.substr(best).strip_edges().trim_suffix(".")


func snapshot() -> Dictionary:
	return {"decrees": decrees, "wanted": wanted, "jailed": jailed}


func restore(d: Dictionary) -> void:
	decrees = {}
	for k: Variant in d.get("decrees", {}):
		decrees[str(k)] = d["decrees"][k]
	wanted.clear()
	for w: Variant in d.get("wanted", []):
		if w is Dictionary:
			wanted.append(w)
	jailed = {}
	for k2: Variant in d.get("jailed", {}):
		jailed[str(k2)] = int(d["jailed"][k2])
