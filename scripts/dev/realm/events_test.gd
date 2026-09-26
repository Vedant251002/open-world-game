extends Node
## The world talks back, and the king answers.
## Run with:  godot --path . -- --realmtest=events

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var warfare: Warfare
var wildlife: Wildlife
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
	print("[events] %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var w: Worker = crew.workers[0]
	var ev: Node = realm.system("Events")
	_check(ev != null, "events loaded")
	var a := realm.answer(w, "is anything going on?")
	_check(a.find("Nothing") >= 0, "quiet: %s" % a)

	# Merchant: buy.
	town.coins = 5000
	_check(ev.trigger("merchant"), "merchant triggered")
	a = realm.answer(w, "what does the merchant have?")
	_check(a.find("at") >= 0 and a.find("buy") >= 0, "merchant answer: %s" % a)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("decide") >= 0), "hud asks for a decision")
	var goods: String = ev.pending["data"]["goods"]
	var had := town.units_of(goods)
	_check(realm.run(w, {"do": "decide", "choice": "buy"}), "buy taken")
	_check(town.units_of(goods) > had and ev.pending.is_empty(), "bought %d %s" % [town.units_of(goods) - had, goods])

	# Refugees: let in.
	var pop0 := realm.population.count()
	_check(ev.trigger("refugees"), "refugees triggered")
	_check(realm.run(w, {"do": "decide", "choice": "let in"}), "let in taken")
	_check(realm.population.count() > pop0, "population %d -> %d" % [pop0, realm.population.count()])

	# Bandits: refuse, and they come.
	_check(ev.trigger("bandits"), "bandits triggered")
	_check(realm.run(w, {"do": "decide", "choice": "refuse"}), "refuse taken")
	_check(ev.live.has("bandits"), "bandits are due")
	var raiders0 := warfare.raiders.size()
	clock.advance(24.0)
	clock.advance(24.0)
	_check(warfare.raiders.size() > raiders0, "bandits came: %d raiders" % warfare.raiders.size())

	# Wolves, then hunt.
	var beasts0 := wildlife.beasts.size()
	_check(ev.trigger("wolves"), "wolves triggered")
	_check(wildlife.beasts.size() > beasts0, "pack in the field")
	_check(realm.run(w, {"do": "decide", "choice": "hunt"}), "hunt taken")

	# Plague, quarantine.
	_check(ev.trigger("plague"), "plague triggered")
	var hl: Node = realm.system("Health")
	_check(hl == null or (hl.get("sick") as Dictionary).size() > 0, "people fell sick")
	_check(realm.run(w, {"do": "decide", "choice": "quarantine"}), "quarantine taken")

	# Harvest and blight move the larder.
	var f0 := town.units_of("food")
	_check(ev.trigger("harvest"), "harvest triggered")
	_check(town.units_of("food") > f0, "food up to %d" % town.units_of("food"))
	f0 = town.units_of("food")
	_check(ev.trigger("blight"), "blight triggered")
	_check(town.units_of("food") <= f0, "food down to %d" % town.units_of("food"))

	# Lost child, treasure, visitor, players, storm, omen.
	_check(ev.trigger("lost_child"), "lost child triggered")
	_check(realm.run(w, {"do": "decide", "choice": "search"}), "search taken")
	_check(ev.trigger("treasure"), "treasure triggered")
	_check(realm.run(w, {"do": "decide", "choice": "dig"}), "dig taken")
	_check(ev.trigger("visitor"), "visitor triggered")
	_check(realm.run(w, {"do": "decide", "choice": "grant"}), "grant taken")
	_check(ev.trigger("players"), "players triggered")
	var c0 := town.coins
	_check(realm.run(w, {"do": "decide", "choice": "let them perform"}), "perform taken")
	_check(town.coins == c0 - 20, "20 coins paid")
	_check(ev.trigger("storm"), "storm triggered")
	_check(ev.trigger("omen"), "omen triggered")

	# A decision left alone expires to the safe default.
	_check(ev.trigger("refugees"), "refugees again")
	clock.advance(24.0)
	clock.advance(24.0)
	clock.advance(24.0)
	_check(ev.pending.is_empty(), "undecided petition expired")
	_check(realm.chronicle.of_kind("event").size() >= 10, "%d event lines in the chronicle" % realm.chronicle.of_kind("event").size())
	_check(not realm.run(w, {"do": "build"}), "build is not the realm's")

	var snap := realm.snapshot()
	ev.restore(snap["Events"])
	_check(ev.last_fired.has("omen"), "restore keeps the record")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[events] FAIL: %s" % f)
	print("[events] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
