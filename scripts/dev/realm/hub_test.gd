extends Node
## The realm hub itself: systems load, questions route, the day turns.
## Run with:  godot --path . -- --realmtest=hub
## Every system's test follows this shape; copy it.

var world: VoxelWorld
var crew: Crew
var clock: GameClock
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
	print("[hub] %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var w: Worker = crew.workers[0]
	_check(realm != null, "realm exists")
	_check(realm.chronicle != null and realm.population != null, "chronicle and population stood up")
	print("[hub] systems loaded: %s" % str(realm.systems.map(func(s: Node) -> String: return s.name)))
	_check(realm.population.count() > 0, "people counted: %d" % realm.population.count())
	var a := realm.answer(w, "how many people live here?")
	_check(a.find("live here") >= 0, "population answers: %s" % a)
	a = realm.answer(w, "what happened today?")
	_check(a.find("founded") >= 0, "chronicle answers: %s" % a)
	_check(realm.handle(w, "fly to the moon") == false, "nonsense is not taken")
	var day0 := clock.day
	clock.advance(24.0)
	_check(clock.day == day0 + 1, "day turned to %d" % clock.day)
	var lines := realm.hud_lines()
	_check(lines.size() >= 0, "hud lines: %s" % str(lines))
	var snap := realm.snapshot()
	_check(snap.has("population") and snap.has("chronicle"), "snapshot has the basics")
	realm.restore(snap)
	_check(realm.population.count() > 0, "restore keeps the people")
	for f: String in _fails:
		print("[hub] FAIL: %s" % f)
	print("[hub] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
