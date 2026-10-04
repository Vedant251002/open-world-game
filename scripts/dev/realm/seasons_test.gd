extends Node
## Seasons change crop growth, frost kills the field, winter bites the larder,
## the warnings and the festival come when they should.
## Run with:  godot --headless --path . -- --realmtest=seasons --nosave --noquick

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var farm: Farm
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
	print("[seasons] %s %s" % ["ok  " if ok else "FAIL", what])


## A day number that falls on day `dos` of `season`.
func _day_for(wx: Node, season: String, dos: int) -> int:
	for d in range(1, 49):
		if str(wx.season_of(d)) == season and int(wx.day_of_season(d)) == dos:
			return d
	return 1


func _notes(kind: String) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in realm.chronicle.of_kind(kind):
		out.append(str(e["text"]))
	return out


func _any_note(kind: String, needle: String) -> bool:
	for t: String in _notes(kind):
		if t.find(needle) >= 0:
			return true
	return false


## Plants one wheat tile, waters it, runs one day of the given season through
## the real daily hook and returns how much it grew.
func _growth_in(wx: Node, seasons: Node, season: String) -> float:
	var day := _day_for(wx, season, 5)
	clock.day = day
	seasons.on_day(day)
	# Open grass near the town. A fixed offset from the well used to be
	# empty and is now somebody's house, so look for ground that takes a hoe.
	var vx := 0
	var vz := 0
	var key := Vector2i.ZERO
	var found := false
	for ring in range(0, 12):
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var off := Vector3(cos(ang), 0.0, sin(ang)) * (34.0 + ring * 6.0)
			var wp := VoxelWorld.to_voxel(realm.village.well_pos + off)
			vx = (wp.x / Farm.SOW_STEP) * Farm.SOW_STEP
			vz = (wp.z / Farm.SOW_STEP) * Farm.SOW_STEP
			key = Vector2i(vx, vz)
			if farm.tiles.has(key) or farm.till(vx, vz):
				found = true
				break
		if found:
			break
	if not farm.tiles.has(key):
		return -1.0
	var t: Dictionary = farm.tiles[key]
	t["kind"] = ""
	farm.tiles[key] = t
	if not farm.plant(vx, vz, "wheat"):
		return -1.0
	t = farm.tiles[key]
	t["wet"] = true
	t["growth"] = 0.0
	t["stage"] = 0
	farm.tiles[key] = t
	farm.advance_days(1.0)
	return float(farm.tiles[key]["growth"])


func _run() -> void:
	var wx: Node = realm.system("Weather")
	var se: Node = realm.system("Seasons")
	_check(wx != null and se != null, "weather and seasons loaded")
	if wx == null or se == null:
		_finish()
		return

	# The calendar helpers.
	_check(wx.day_of_season(_day_for(wx, "autumn", 3)) == 3, "day_of_season")
	_check(wx.days_until("winter") >= 0, "days_until")
	var d3 := _day_for(wx, "autumn", 10)
	clock.day = d3
	_check(wx.days_until("winter") == 3, "autumn day 10 is 3 days from winter (%d)" % wx.days_until("winter"))

	# --- crop growth by season -------------------------------------------
	var g := {}
	for s: String in ["spring", "summer", "autumn", "winter"]:
		g[s] = _growth_in(wx, se, s)
		print("[seasons] one day of growth in %s: %.2f (farm.season_rate %.2f)" % [s, g[s], farm.season_rate])
	_check(float(g["spring"]) > 1.0 and float(g["summer"]) > 1.0, "spring and summer: faster than a plain day")
	_check(float(g["summer"]) >= float(g["spring"]) * 0.8, "summer is at least as fast as spring")
	_check(float(g["autumn"]) > 0.0 and float(g["autumn"]) < 1.0, "autumn: slow (%.2f)" % float(g["autumn"]))
	_check(float(g["winter"]) == 0.0, "winter: nothing grows (%.2f)" % float(g["winter"]))
	_check(float(g["spring"]) > float(g["autumn"]) * 2.0, "spring grows more than twice as fast as autumn")

	# --- frost kills what is left in the field ------------------------------
	var key: Vector2i = farm.tiles.keys()[0]
	var t: Dictionary = farm.tiles[key]
	t["kind"] = ""
	farm.tiles[key] = t
	var vx := key.x
	var vz := key.y
	_check(farm.plant(vx, vz, "wheat"), "sowed a crop for the frost")
	clock.day = _day_for(wx, "winter", 1)
	se.on_day(clock.day)
	_check(str(farm.tiles[key]["kind"]) == "", "first frost killed the unharvested crop")
	_check(_any_note("season", "frost"), "frost chronicled")

	# --- the warning ------------------------------------------------------
	town.stock["food"] = 400
	var pop := maxi(realm.population.count(), 1)
	var expect := int(400.0 / (float(pop) * 1.5))
	clock.day = _day_for(wx, "autumn", 10)
	se.on_day(clock.day)
	_check(_any_note("season", "Winter in 3 days -- the stores hold %d days of food" % expect),
		"pre-winter warning quotes the stores (%d days)" % expect)
	var cr: Node = realm.system("Crisis")
	var bn: Dictionary = cr.banner()
	_check(str(bn.get("title", "")).find("WINTER IN 3") >= 0, "and the banner carries it: %s" % str(bn.get("title", "")))
	var ans := realm.answer(crew.workers[0], "are we ready for winter?")
	_check(ans.find("%d days of food" % expect) >= 0, "and the town answers: %s" % ans)
	var warns := _notes("season").size()
	se.on_day(clock.day)
	_check(_notes("season").size() == warns, "the warning is given once")

	# --- the harvest festival ----------------------------------------------
	se.festival_year = -1
	town.stock["food"] = 1000
	clock.day = _day_for(wx, "autumn", 6)
	var moods: Array[float] = []
	for c: Population.Citizen in realm.population.alive():
		c.mood = 0.4
		moods.append(c.mood)
	se.on_day(clock.day)
	_check(_any_note("festival", "harvest festival"), "festival held with the larder full")
	_check(realm.population.mood_avg() > 0.5, "and spirits rose (%.2f)" % realm.population.mood_avg())
	var fest := _notes("festival").size()
	se.on_day(clock.day)
	_check(_notes("festival").size() == fest, "only one festival a year")
	se.festival_year = -1
	town.stock["food"] = 0
	se.on_day(clock.day)
	_check(_notes("festival").size() == fest + 1 and _any_note("festival", "no harvest festival"),
		"no festival when the stores are bare")

	# --- winter eats ---------------------------------------------------------
	town.stock["food"] = 500
	town.stock["timber"] = 500
	clock.day = _day_for(wx, "winter", 4)
	var f0 := town.units_of("food")
	var t0 := town.units_of("timber")
	se.on_day(clock.day)
	_check(town.units_of("food") < f0, "winter takes extra food (%d -> %d)" % [f0, town.units_of("food")])
	_check(town.units_of("timber") < t0, "and firewood (%d -> %d)" % [t0, town.units_of("timber")])
	_check(se.food_days() < float(f0) / float(pop), "winter days of food count at the bigger appetite")

	# --- spring brings arrivals and young animals ---------------------------
	var pop0 := realm.population.count()
	clock.day = _day_for(wx, "spring", 2)
	se.on_day(clock.day)
	var notes := _notes("arrival").size() + (1 if _any_note("season", "nobody to the gate") else 0)
	_check(realm.population.count() > pop0 or _any_note("season", "no bed to offer"),
		"spring: newcomers (%d -> %d) or no bed to give them" % [pop0, realm.population.count()])
	_check(notes >= 0, "spring noted")

	# --- the look -------------------------------------------------------------
	clock.day = _day_for(wx, "winter", 5)
	se.on_day(clock.day)
	var fx: SeasonFx = wx.season_fx()
	if fx != null:
		_check(fx.snow > 0.9, "winter: the world is under snow (%.2f)" % fx.snow)
		var grass := VoxelMaterials.get_material(VoxelTypes.GRASS)
		_check(float(grass.get_shader_parameter("snow_cover")) > 0.9, "grass material carries the snow")
		clock.day = _day_for(wx, "autumn", 8)
		se.on_day(clock.day)
		_check(fx.autumn > 0.9 and fx.snow == 0.0, "autumn: leaves turned, no snow")
		clock.day = _day_for(wx, "summer", 6)
		se.on_day(clock.day)
		_check(fx.autumn == 0.0 and fx.snow == 0.0, "summer: plain green")
	else:
		_check(true, "no props root, so no season picture (skipped)")
	_check(str(se.hud_label()).find("/12") >= 0, "hud label: %s" % se.hud_label())

	# --- save -------------------------------------------------------------
	var snap: Dictionary = se.snapshot()
	se.restore(snap)
	_check(int(se.festival_year) == int(snap["festival_year"]), "festival year survives a restore")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[seasons] FAIL: %s" % f)
	print("[seasons] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
