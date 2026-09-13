extends Node
## Tier 2: neighbours, envoys and land.
## Run with:  godot --path . -- --realmtest=neighbours

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var village: Village
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
	print("[neighbours] %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var w: Worker = crew.workers[0]
	var w2: Worker = crew.workers[1]
	var nb: Node = realm.system("Neighbours")
	var ex: Node = realm.system("Expansion")
	_check(nb != null and ex != null, "neighbours and expansion loaded")
	var towns: Array = nb.list()
	_check(towns.size() >= 3, "%d neighbours" % towns.size())
	var first: Dictionary = towns[0]
	var name := str(first["name"])

	var a := realm.answer(w, "who are our neighbours?")
	_check(a.find(name) >= 0, "neighbours: %s" % a)
	a = realm.answer(w, "tell me about %s" % name)
	_check(a.find(str(first["leader"])) >= 0, "about: %s" % a)
	a = realm.answer(w, "where is %s?" % name)
	_check(a.find("days") >= 0, "where: %s" % a)
	a = realm.answer(w, "what does %s sell?" % name)
	_check(a.find("sells") >= 0, "sells: %s" % a)
	a = realm.answer(w, "are we at war?")
	_check(a.find("peace") >= 0, "at war: %s" % a)

	# An envoy goes and comes back.
	var d0 := float(first["disposition"])
	_check(realm.handle(w, "send an envoy to %s" % name), "envoy order taken")
	_check(not w.job_errand.is_empty(), "envoy is on the road")
	a = realm.answer(w2, "when will the envoy be back?")
	_check(a.find("back on day") >= 0, "envoy eta: %s" % a)
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find(name) >= 0), "hud shows the envoy")
	var days := int(first["distance_days"]) * 2
	clock.advance(24.0 * days + 1.0)
	_check(float(first["disposition"]) > d0, "disposition rose %.2f -> %.2f" % [d0, float(first["disposition"])])
	_check(w.job_errand.is_empty(), "envoy came home")

	# A gift, then peace, then war, by a second worker while the first rests.
	var c0 := town.coins
	print("[neighbours] w2=%s busy=%s state=%s pondering=%s holding=%s errand=%s hired=%s" % [
		w2.display_name(), w2.busy(), w2.state, w2.pondering, w2._holding, w2.job_errand.get("kind", ""), w2.hired])
	_check(realm.handle(w2, "send %s a gift of 200 coins" % name), "gift taken")
	_check(town.coins == c0 - 200, "200 coins left the purse")
	clock.advance(24.0 * days + 1.0)
	_check(realm.handle(w2, "declare war on %s" % name), "war taken")
	clock.advance(24.0 * days + 1.0)
	_check(str(first["treaty"]) == "war", "treaty is war")
	a = realm.answer(w, "are we at war?")
	_check(a.find(name) >= 0, "at war now: %s" % a)
	_check(nb.hostile().size() >= 1, "hostile list has them")
	nb.set_treaty(name, "peace")
	_check(str(first["treaty"]) == "peace", "set_treaty works")
	_check(realm.handle(w2, "trade with %s" % name), "caravan taken")
	clock.advance(24.0 * days + 1.0)
	_check(str(first["treaty"]) in ["trade", "peace"], "caravan came back (treaty %s)" % first["treaty"])

	# Land.
	var plots0 := village.plots.size()
	c0 = town.coins
	_check(realm.handle(w, "claim the land to the north"), "claim taken")
	_check(village.plots.size() > plots0, "plots grew %d -> %d" % [plots0, village.plots.size()])
	_check(town.coins < c0, "claim cost %d" % (c0 - town.coins))
	a = realm.answer(w, "how big is our land?")
	_check(a.find("north") >= 0, "land: %s" % a)
	_check(realm.handle(w, "name the north side Mill Quarter"), "district named")
	a = realm.answer(w, "where is the Mill Quarter?")
	_check(a.find("Mill Quarter") >= 0, "district where: %s" % a)

	# A road, laid over hours.
	var cob0 := town.units_of("cobble")
	_check(realm.handle(w2, "build a road to the east edge"), "road order taken")
	clock.advance(2.0)
	_check(town.units_of("cobble") < cob0, "cobble spent on the road: %d" % (cob0 - town.units_of("cobble")))
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("road") >= 0), "hud shows the road")
	clock.advance(60.0)
	_check(ex._road.is_empty(), "road finished")
	_check(not realm.handle(w, "build a hut on the corner"), "build order left alone")

	var snap := realm.snapshot()
	nb.restore(snap["Neighbours"])
	_check(nb.list().size() == towns.size() and str(nb.list()[0]["name"]) == name, "neighbours restore")
	ex.restore(snap["Expansion"])
	_check(ex.districts.size() == 1, "expansion restore")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[neighbours] FAIL: %s" % f)
	print("[neighbours] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
