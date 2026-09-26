extends Node
## Tier 3: law, court, dynasty and faith, by talking.
## Run with:  godot --path . -- --realmtest=law

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var warfare: Warfare
var realm: Realm

var _wait := 0.0
var _fails: Array[String] = []


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy() and _wait < 15.0:
		_wait += delta
		return
	set_process(false)
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("[law] %s %s" % ["ok  " if ok else "FAIL", what])


func _days(n: int) -> void:
	for i in n:
		clock.advance(24.0)


func _run() -> void:
	var w: Worker = crew.workers[0]
	var law: Node = realm.system("Law")
	var court: Node = realm.system("Court")
	var dyn: Node = realm.system("Dynasty")
	var faith: Node = realm.system("Faith")
	_check(law != null and court != null and dyn != null and faith != null, "all four loaded")
	var people: Array = realm.population.alive()
	var ada: Population.Citizen = people[0]
	var bram: Population.Citizen = people[1]

	# --- law ---
	_check(realm.run(w, {"do": "decree", "law": "curfew"}), "curfew decreed")
	_check(law.is_on("curfew"), "curfew is on")
	var a := realm.answer(w, "is there a curfew?")
	_check(a.find("after dark") >= 0, "curfew answer: %s" % a)
	_check(realm.run(w, {"do": "decree", "law": "no_ale"}), "ale banned")
	_check(not law.ale_allowed(), "ale is banned")
	_check(realm.run(w, {"do": "repeal", "law": "no_ale"}), "ale allowed")
	_check(law.ale_allowed(), "ale is back")
	_check(realm.run(w, {"do": "decree", "law": "custom", "text": "nobody works on the seventh day"}), "custom law kept")
	a = realm.answer(w, "what are the laws?")
	_check(a.find("curfew") >= 0 and a.find("seventh") >= 0, "laws listed: %s" % a)
	_check(realm.run(w, {"do": "repeal", "law": "curfew"}), "curfew lifted")
	_check(not law.is_on("curfew"), "curfew off")
	_check(realm.run(w, {"do": "decree", "law": "closed_borders"}), "borders closed")
	_check(not law.borders_open(), "borders are closed")
	_check(realm.run(w, {"do": "repeal", "law": "closed_borders"}), "borders opened")
	_check(realm.run(w, {"do": "fine", "who": ada.name, "coins": 50}), "fine taken")
	law.wanted.append({"name": bram.name, "crime": "stole 10 bricks", "day": clock.day})
	a = realm.answer(w, "who is wanted?")
	_check(a.find(bram.name) >= 0, "wanted: %s" % a)
	_check(realm.run(w, {"do": "jail", "who": bram.name, "days": 2}), "jail order taken")
	if realm.building("barracks").is_empty() and realm.building("guard_post").is_empty():
		_check(law.jailed.is_empty(), "no cells, so nobody jailed (said so)")
	else:
		_check(law.jailed.has(bram.name), "jailed")
	_check(realm.run(w, {"do": "pardon", "who": bram.name}), "pardon taken")
	_check(law.wanted.is_empty(), "wanted list cleared")
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")

	# --- court ---
	_check(realm.run(w, {"do": "name_kingdom", "name": "Ashford"}), "kingdom named")
	_check(realm.kingdom_name == "Ashford", "kingdom_name is Ashford")
	a = realm.answer(w, "what is this kingdom called?")
	_check(a.find("Ashford") >= 0, "kingdom name answer: %s" % a)
	_check(realm.run(w, {"do": "appoint", "who": ada.name, "title": "steward"}), "steward appointed")
	a = realm.answer(w, "who is the steward?")
	_check(a.find(ada.name) >= 0, "steward: %s" % a)
	court.petitions.clear()
	court._file({"from": bram.name, "kind": "bread", "text": "\"Bread, my lord.\""})
	town.stock["food"] = 60
	a = realm.answer(w, "any petitions?")
	_check(a.find(bram.name) >= 0, "petitions listed: %s" % a)
	var m0 := bram.mood
	_check(realm.run(w, {"do": "petition", "answer": "grant"}), "grant taken")
	_check(court.petitions.is_empty() and town.units_of("food") == 40 and bram.mood > m0, "bread given, mood up")
	court._file({"from": ada.name, "kind": "road", "text": "\"Cobbles?\""})
	_check(realm.run(w, {"do": "petition", "answer": "refuse", "who": ada.name}), "refuse taken")
	_check(court.petitions.is_empty(), "petition gone")
	a = realm.answer(w, "what do you advise?")
	_check(a.find(":") >= 0, "advice: %s" % a)

	# --- dynasty ---
	_check(realm.run(w, {"do": "name_ruler", "name": "Edric", "title": "King"}), "king named")
	_check(dyn.king["name"] == "Edric", "king is Edric")
	ada.mood = 0.9
	ada.spouse_id = -1
	_check(realm.run(w, {"do": "marry", "who": ada.name}), "proposal taken")
	_check(not dyn.wedding.is_empty(), "wedding set for day %d" % int(dyn.wedding.get("day", -1)))
	town.stock["food"] = 200
	_days(1)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("wedding") >= 0), "hud says wedding tomorrow")
	_days(1)
	_check(dyn.king["consort"] == ada.name, "married to %s" % ada.name)
	a = realm.answer(w, "who is my wife?")
	_check(a.find(ada.name) >= 0, "wife: %s" % a)
	a = realm.answer(w, "who is my heir?")
	_check(a.find("No children") >= 0, "heir: %s" % a)
	dyn.children.append({"name": "Osric", "born_day": clock.day - 48 * 15, "alive": true, "came_of_age": false})
	a = realm.answer(w, "tell me about my family")
	_check(a.find("Osric") >= 0, "family: %s" % a)
	town.stock["food"] = 2000
	_days(48)
	_check(dyn.children[0]["came_of_age"] and realm.population.by_name("Osric") != null, "Osric came of age and joined the town")
	warfare.player_fell = true
	clock.advance(1.0)
	_check(dyn.king["name"] == "Osric", "succession: %s rules" % dyn.king["name"])
	var single: Array = []
	for c: Population.Citizen in realm.population.alive():
		if c.spouse_id < 0 and c.name != ada.name:
			single.append(c)
	var s1: Population.Citizen = single[0]
	var s2: Population.Citizen = single[1]
	_check(realm.run(w, {"do": "marry", "who": s1.name, "to": s2.name}), "citizens wed")
	_check(s1.spouse_id == s2.id and s2.spouse_id == s1.id, "spouse ids set")

	# --- faith ---
	town.stock["food"] = 200
	town.coins = 5000
	_check(realm.run(w, {"do": "feast", "reason": "the harvest"}), "feast called")
	_check(faith.feast_day == clock.day + 1, "feast tomorrow")
	var mood0 := realm.population.mood_avg()
	_days(1)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("feast") >= 0), "hud says feast today")
	_check(realm.population.mood_avg() > mood0, "mood rose %.2f -> %.2f" % [mood0, realm.population.mood_avg()])
	a = realm.answer(w, "how is morale?")
	_check(a.find("People are") >= 0, "morale: %s" % a)
	a = realm.answer(w, "when is the next feast?")
	_check(a != "", "next feast: %s" % a)

	var snap := realm.snapshot()
	law.restore(snap["Law"])
	court.restore(snap["Court"])
	dyn.restore(snap["Dynasty"])
	faith.restore(snap["Faith"])
	_check(court.titles.has(ada.name) and dyn.king["name"] == "Osric" and faith.feasts_held >= 1,
		"restore round trip (titles %s, king %s, feasts %d)" % [str(court.titles), dyn.king["name"], faith.feasts_held])
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[law] FAIL: %s" % f)
	print("[law] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
