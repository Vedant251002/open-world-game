extends Node
## Tier 1: buildings make things, prices move, tax comes in, people get homes.
## Run with:  godot --path . -- --realmtest=industry

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
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
	print("[industry] %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var w: Worker = crew.workers[0]
	var ind: Node = realm.system("Industry")
	var mk: Node = realm.system("Market")
	_check(ind != null and mk != null, "industry and market loaded")
	var people: Array = realm.population.alive()
	_check(people.size() >= 3, "%d citizens to work with" % people.size())
	var ada: Population.Citizen = people[0]
	var bram: Population.Citizen = people[1]

	# --- staffing by hand ---
	_check(realm.run(w, {"do": "assign", "who": ada.name, "place": "bakery"}), "assign order taken")
	_check(ada.workplace_id == realm.building("bakery")["id"], "%s works the bakery" % ada.name)
	var a := realm.answer(w, "who works at the bakery?")
	_check(a.find(ada.name) >= 0, "who works: %s" % a)
	a = realm.answer(w, "where does %s work?" % ada.name)
	_check(a.find("bakery") >= 0, "where works: %s" % a)
	a = realm.answer(w, "what does the bakery make?")
	_check(a.find("bread") >= 0, "what it makes: %s" % a)
	_check(realm.run(w, {"do": "assign", "place": "workshop", "count": 2}), "put two people taken")
	_check(ind.staff_of(realm.building("workshop")["id"]).size() == 2, "workshop has two")
	_check(realm.run(w, {"do": "release", "who": ada.name}), "take off taken")
	_check(ada.workplace_id < 0, "%s released" % ada.name)
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")
	_check(not realm.run(w, {"do": "enclose"}), "enclose is not the realm's")

	# --- a day of work ---
	town.stock["food"] = 40
	var timber0 := town.units_of("timber")
	var coins0 := town.coins
	clock.advance(24.0)
	_check(town.units_of("meals") > 0, "bakery made %d meals (auto-staffed)" % town.units_of("meals"))
	_check(town.units_of("tools") > 0, "workshop made %d tools" % town.units_of("tools"))
	_check(town.units_of("timber") != timber0, "timber moved: %d -> %d" % [timber0, town.units_of("timber")])
	a = realm.answer(w, "how is the bakery doing?")
	_check(a.find("made") >= 0, "bakery report: %s" % a)
	a = realm.answer(w, "what are people working on?")
	_check(a.find("at the") >= 0, "everyone: %s" % a)
	_check(town.coins > coins0, "purse rose with trade and tax: %d -> %d" % [coins0, town.coins])

	# --- market ---
	a = realm.answer(w, "what is the price of brick?")
	_check(a.find("fetches") >= 0, "price: %s" % a)
	var brick0 := town.units_of("brick")
	var c0 := town.coins
	_check(realm.dispatch.run_step_for_test(w, {"do": "trade", "action": "sell", "kind": "brick", "count": 50}), "sell order taken")
	clock.advance(1.0)
	_check(town.units_of("brick") == brick0 - 50 and town.coins > c0, "sold 50 brick for %d" % (town.coins - c0))
	c0 = town.coins
	var plank0 := town.units_of("plank")
	_check(realm.dispatch.run_step_for_test(w, {"do": "trade", "action": "buy", "kind": "plank", "count": 30}), "buy order taken")
	clock.advance(3.0)
	_check(town.units_of("plank") == plank0 + 30 and town.coins < c0, "bought 30 plank for %d" % (c0 - town.coins))
	a = realm.answer(w, "what sells well?")
	_check(a != "", "sells well: %s" % a)

	# --- tax ---
	_check(realm.run(w, {"do": "tax", "change": "set", "rate": 20}), "tax order taken")
	_check(is_equal_approx(mk.rate, 0.2), "rate is 0.2")
	c0 = town.coins
	clock.advance(24.0)
	_check(mk.tax_yesterday > 0, "collected %d tax" % mk.tax_yesterday)
	a = realm.answer(w, "how much tax do we collect?")
	_check(a.find("20 percent") >= 0, "tax answer: %s" % a)
	_check(realm.run(w, {"do": "tax", "change": "abolish"}), "abolish taken")
	_check(mk.rate == 0.0, "rate is 0")
	a = realm.answer(w, "when is market day?")
	_check(a != "", "market day: %s" % a)

	# --- homes ---
	bram.home_id = -1
	_check(realm.run(w, {"do": "house", "who": bram.name, "place": "hut"}), "home order taken")
	a = realm.answer(w, "who lives in the hut?")
	_check(a.find("hut") >= 0, "who lives: %s" % a)

	# --- save ---
	var snap := realm.snapshot()
	mk.rate = 0.3
	mk.restore(snap["Market"])
	_check(mk.rate == 0.0, "market restore keeps the rate")
	ind.restore(snap["Industry"])
	_check(true, "industry restore ran")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[industry] FAIL: %s" % f)
	print("[industry] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
