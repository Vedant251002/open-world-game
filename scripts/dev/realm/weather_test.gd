extends Node
## Seasons turn, rain waters, fire burns and gets put out.
## Run with:  godot --path . -- --realmtest=weather

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
	print("[weather] %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var w: Worker = crew.workers[0]
	var wx: Node = realm.system("Weather")
	_check(wx != null, "weather system loaded")
	if wx == null:
		_finish()
		return

	# Questions before anything happens.
	var a := realm.answer(w, "what is the weather like?")
	_check(a != "", "weather answered: %s" % a)
	a = realm.answer(w, "what season is it?")
	_check(a.find("It is") >= 0, "season answered: %s" % a)
	a = realm.answer(w, "how cold is it?")
	_check(a != "", "temperature answered: %s" % a)
	a = realm.answer(w, "will it rain?")
	_check(a != "", "forecast answered: %s" % a)
	a = realm.answer(w, "is anything on fire?")
	_check(a.find("Nothing") >= 0, "no fire yet: %s" % a)

	# Rain waters the fields. Till a couple of tiles so there is a field.
	var wp := VoxelWorld.to_voxel(realm.village.well_pos + Vector3(30, 0, 30))
	var tilled := 0
	for dx in 4:
		for dz in 4:
			if farm.till(wp.x + dx * Farm.SOW_STEP, wp.z + dz * Farm.SOW_STEP):
				tilled += 1
	_check(tilled > 0, "tilled %d tiles" % tilled)
	wx.force("rain")
	_check(wx.is_raining(), "forced rain")
	clock.advance(1.0)
	a = realm.answer(w, "is it raining?")
	_check(a.findn("rain") >= 0, "says it is raining: %s" % a)
	var wet := 0
	for key: Vector2i in farm.tiles:
		var tile: Dictionary = farm.tiles[key]
		if float(tile.get("watered", 0.0)) > 0.0:
			wet += 1
	_check(wet > 0 or farm.tiles.is_empty(), "rain watered %d of %d tiles" % [wet, farm.tiles.size()])
	_check(realm.hud_lines().any(func(l: String) -> bool: return l.find("rain") >= 0),
		"hud shows rain: %s" % str(realm.hud_lines()))

	# Fire.
	wx.force("clear")
	var rec := realm.building("bakery")
	_check(not rec.is_empty(), "there is a bakery to burn")
	var patch: VoxelPatch = rec.get("patch")
	wx.ignite(rec, "the test")
	_check(wx.burning().size() == 1, "bakery is burning")
	clock.advance(1.0)
	var embers := 0
	for x in patch.size.x:
		for y in patch.size.y:
			for z in patch.size.z:
				var v := world.get_voxel(patch.origin + Vector3i(x, y, z))
				if v == VoxelTypes.EMBER:
					embers += 1
	_check(embers > 0, "%d voxels turned to ember" % embers)
	a = realm.answer(w, "is anything on fire?")
	_check(a.find("bakery") >= 0, "says the bakery burns: %s" % a)
	_check(realm.handle(w, "put out the fire"), "bucket line order taken")
	_check(not w.job_errand.is_empty(), "worker is on the fire errand")
	var hours := 0
	while not wx.burning().is_empty() and hours < 12:
		clock.advance(1.0)
		hours += 1
	_check(wx.burning().is_empty(), "fire out after %d hours" % hours)
	_check(realm.handle(w, "ring the bell"), "ring the bell with no fire is still taken")

	# Snapshot round trip keeps the calendar.
	var season_before: String = wx.season()
	var snap := realm.snapshot()
	wx.restore(snap["Weather"])
	_check(wx.season() == season_before, "restore keeps the season")

	# Not ours.
	_check(not realm.handle(w, "build a big bakery"), "build orders are left alone")
	_check(realm.answer(w, "what is your favourite colour?") == "", "unknown question falls through")
	_finish()


func _finish() -> void:
	for f: String in _fails:
		print("[weather] FAIL: %s" % f)
	print("[weather] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
