extends Node
## War as a thing a kingdom does, not only a thing done to it.
##
## Warfare gives the town soldiers, guns and raids at the gate. This is the
## layer above: the army as a whole with a strength and a morale, fed and
## paid or not; walls that go up round the town over a few days with gaps
## where the streets run out; sieges, where a hostile neighbour brings an
## engine and waves of men for two days; and expeditions, where the soldiers
## march off behind a captain and come back with loot, a vassal, or fewer
## soldiers. Everything is said to a worker: "build a wall", "man the walls",
## "march on Kelder", "call the army home".

const V := VoxelChunk.VOXEL_M
const WALL_HEIGHT_V := 8
const WALL_OUT_V := 12                ## past the founding bounds
const WALL_VOXELS_PER_HOUR := 400
const GATE_HALF_V := 18
const SIEGE_EVERY_DAYS := 8
const SIEGE_HOURS := 48.0
const SIEGE_WAVE_HOURS := 3.0
const SIEGE_WAVES := 5
const ENGINE_HOURS := 2.0
const ENGINE_RANGE_M := 40.0
const PAY_EACH := 10
const FOOD_EACH := 1
const MIN_EXPEDITION := 3

var realm: Realm
var morale := 0.7
var walls: Array[Rect2i] = []           ## finished wall lines, in voxels
var wall_job: Dictionary = {}           ## {worker_id, cells: Array[Vector3i], i, mat, kind}
var siege: Dictionary = {}              ## {enemy, started, waves_left, next_wave, next_shot, engine, hits}
var expedition: Dictionary = {}         ## {target, count, captain, return_day, strength, weapons}
var _next_siege_day := -1
var _rng := RandomNumberGenerator.new()
var _unfed_days := 0
var _fallback_enemy := {"name": "the Marsh Clans", "strength": 30, "treaty": "war", "disposition": -0.8,
	"bearing": Vector2(0.0, 1.0), "distance_days": 3}


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	if realm.warfare != null:
		realm.warfare.raid_over.connect(_on_raid_over)
		realm.warfare.raid_began.connect(_on_raid_began)
	_next_siege_day = (realm.clock.day if realm.clock != null else 1) + SIEGE_EVERY_DAYS


# -------------------------------------------------------------------- army

func soldiers() -> Array:
	return realm.warfare.soldiers if realm.warfare != null else []


func strength() -> float:
	var total := 0.0
	for s: Fighter in soldiers():
		if not is_instance_valid(s) or s.is_dead():
			continue
		var w := 1.0
		match s.weapon:
			"rifle": w = 2.0
			"musket": w = 1.6
			"pistol": w = 1.3
			"grenade": w = 1.5
			"": w = 0.6
		total += w * (1.0 + s.veteran) * (0.5 + morale)
	return total * 3.0


func best_soldier() -> Fighter:
	var best: Fighter = null
	for s: Fighter in soldiers():
		if is_instance_valid(s) and (best == null or s.veteran > best.veteran):
			best = s
	return best


func morale_word() -> String:
	if morale > 0.8:
		return "eager"
	if morale > 0.5:
		return "steady"
	if morale > 0.3:
		return "grumbling"
	return "close to breaking"


func _enemies() -> Node:
	return realm.system("Neighbours")


func _enemy_named(t: String) -> Dictionary:
	var nb := _enemies()
	if nb != null and nb.has_method("list"):
		for town: Dictionary in nb.call("list"):
			if t.find(str(town["name"]).to_lower()) >= 0:
				return town
	if t.find("marsh") >= 0 or t.find("clans") >= 0:
		return _fallback_enemy
	return {}


func _strongest_enemy() -> Dictionary:
	var nb := _enemies()
	if nb != null and nb.has_method("strongest_enemy"):
		var e: Dictionary = nb.call("strongest_enemy")
		if not e.is_empty():
			return e
	return _fallback_enemy


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	# Bread and pay.
	var n := soldiers().size()
	if n > 0:
		var food := int(realm.town.stock.get("food", 0))
		if food >= n * FOOD_EACH:
			realm.town.stock["food"] = food - n * FOOD_EACH
			_unfed_days = 0
			morale = minf(morale + 0.02, 1.0)
		else:
			_unfed_days += 1
			morale = maxf(morale - 0.08, 0.0)
			if _unfed_days == 2:
				realm.say("The soldiers have not eaten in two days. They are %s." % morale_word())
				realm.note("army", "The army went unfed.")
	# The expedition comes home.
	if not expedition.is_empty() and day >= int(expedition["return_day"]):
		_expedition_returns()
	# A siege, when the enemy is stronger and it is time.
	if siege.is_empty() and expedition.is_empty() and day >= _next_siege_day:
		_next_siege_day = day + SIEGE_EVERY_DAYS
		var enemy := _strongest_enemy()
		if not enemy.is_empty() and str(enemy.get("treaty", "war")) == "war" \
				and float(enemy.get("strength", 0)) > strength() * 0.8:
			start_siege(enemy)


func on_hour(hour: float, day: int) -> void:
	_lay_wall()
	if not siege.is_empty():
		_tick_siege(hour, day)


func _on_raid_began(_count: int) -> void:
	if morale < 0.3 and not soldiers().is_empty():
		realm.say("The soldiers will not stand. They are falling back to the barracks.")
		realm.note("army", "The company routed at the sight of the raiders.")
		var at := realm.warfare.barracks_stand()
		for s: Fighter in soldiers():
			if is_instance_valid(s):
				s.march(at if at != Vector3.INF else realm.village.well_pos)


func _on_raid_over(won: bool) -> void:
	if won:
		morale = minf(morale + 0.1, 1.0)
		for s: Fighter in soldiers():
			if is_instance_valid(s):
				s.veteran = minf(s.veteran + 0.15, 1.0)
	else:
		morale = maxf(morale - 0.15, 0.0)


# -------------------------------------------------------------------- walls

## Plans a wall round the founding bounds, or one side of it, with gaps
## where the streets run out, and puts a worker on it.
func start_wall(worker: Worker, side: String, palisade: bool) -> bool:
	if not wall_job.is_empty():
		worker.speak("There is a wall going up already; let it finish.")
		return true
	var b := realm.village.bounds_v.grow(WALL_OUT_V)
	var cells: Array[Vector3i] = []
	var sides := ["north", "south", "east", "west"] if side == "" else [side]
	for s: String in sides:
		match s:
			"north":
				for x in range(b.position.x, b.end.x):
					_wall_column(cells, x, b.position.y, true)
			"south":
				for x in range(b.position.x, b.end.x):
					_wall_column(cells, x, b.end.y - 1, true)
			"east":
				for z in range(b.position.y, b.end.y):
					_wall_column(cells, b.end.x - 1, z, false)
			"west":
				for z in range(b.position.y, b.end.y):
					_wall_column(cells, b.position.x, z, false)
	if cells.is_empty():
		return false
	var mat := VoxelTypes.TIMBER if palisade else VoxelTypes.SANDSTONE
	var stand := realm.village.well_pos
	wall_job = {"worker_id": worker.memory.worker_id, "cells": cells, "i": 0, "mat": mat,
		"kind": "palisade" if palisade else "wall", "rect": b, "laid": 0}
	var hours := float(cells.size()) / float(WALL_VOXELS_PER_HOUR)
	worker.take_errand_job("station", stand, hours + 1.0,
		"A %s round the %s. About %d hours of it." % [wall_job["kind"], "town" if side == "" else side + " side", int(hours)],
		{"where": "the walls", "doing": "lay"})
	realm.note("walls", "%s started a %s %s." % [worker.display_name(), wall_job["kind"],
		"round the town" if side == "" else "on the %s side" % side])
	return true


func _wall_column(cells: Array[Vector3i], x: int, z: int, along_x: bool) -> void:
	var village := realm.village
	# A gap where a street would run out of the town.
	var lines: Array[int] = village.lines_x if along_x else village.lines_z
	var here := x if along_x else z
	for l: int in lines:
		if absi(here - l) <= GATE_HALF_V:
			return
	for y in WALL_HEIGHT_V:
		cells.append(Vector3i(x, y, z))


func _lay_wall() -> void:
	if wall_job.is_empty():
		return
	var cells: Array[Vector3i] = wall_job["cells"]
	var i := int(wall_job["i"])
	var laid := 0
	var mat := int(wall_job["mat"])
	var mat_name := VoxelTypes.name_of(mat)
	var w: Worker = realm.crew.get_worker(str(wall_job["worker_id"]))
	while i < cells.size() and laid < WALL_VOXELS_PER_HOUR:
		var c: Vector3i = cells[i]
		i += 1
		var col := VoxelWorld.column_of(Vector3(c.x * V, 0.0, c.z * V))
		if not realm.world.has_column(col.x, col.y):
			continue
		if c.y == 0:
			# One unit of stone or timber per column of wall.
			if int(realm.town.stock.get(mat_name, 0)) <= 0:
				if w != null:
					w.speak("Out of %s; the %s stops here." % [mat_name, wall_job["kind"]])
				realm.note("walls", "The %s stopped for want of %s." % [wall_job["kind"], mat_name])
				_finish_wall(false)
				return
			realm.town.stock[mat_name] = int(realm.town.stock[mat_name]) - 1
		var ground := realm.world.height_at(c.x, c.z)
		if ground < 0:
			continue
		var wp := Vector3i(c.x, ground + 1 + c.y, c.z)
		if realm.world.get_voxel(wp) == VoxelTypes.AIR or realm.world.get_voxel(wp) == VoxelTypes.WATER:
			realm.world.set_voxel(wp, mat)
			laid += 1
	wall_job["i"] = i
	wall_job["laid"] = int(wall_job["laid"]) + laid
	if i >= cells.size():
		if w != null:
			w.speak("The %s is up." % wall_job["kind"])
		_finish_wall(true)


func _finish_wall(done: bool) -> void:
	if done:
		walls.append(wall_job["rect"])
		realm.note("walls", "The %s was finished: %d stones laid." % [wall_job["kind"], int(wall_job["laid"])])
		realm.say("The %s is finished." % wall_job["kind"])
	var w: Worker = realm.crew.get_worker(str(wall_job["worker_id"]))
	if w != null and not w.job_errand.is_empty():
		w.drop_everything()
	wall_job = {}


func wall_progress() -> float:
	if wall_job.is_empty():
		return 1.0 if not walls.is_empty() else 0.0
	var cells: Array[Vector3i] = wall_job["cells"]
	return float(wall_job["i"]) / float(maxi(cells.size(), 1))


func man_the_walls() -> int:
	if soldiers().is_empty():
		return 0
	var b: Rect2i = walls[0] if not walls.is_empty() else realm.village.bounds_v.grow(WALL_OUT_V)
	var n := soldiers().size()
	var i := 0
	for s: Fighter in soldiers():
		if not is_instance_valid(s):
			continue
		var t := float(i) / float(maxi(n, 1))
		var spot := Vector3.ZERO
		var per := b.size.x * 2 + b.size.y * 2
		var d := int(t * per)
		if d < b.size.x:
			spot = Vector3((b.position.x + d) * V, 0.0, (b.position.y + 3) * V)
		elif d < b.size.x + b.size.y:
			spot = Vector3((b.end.x - 3) * V, 0.0, (b.position.y + d - b.size.x) * V)
		elif d < b.size.x * 2 + b.size.y:
			spot = Vector3((b.end.x - (d - b.size.x - b.size.y)) * V, 0.0, (b.end.y - 3) * V)
		else:
			spot = Vector3((b.position.x + 3) * V, 0.0, (b.end.y - (d - b.size.x * 2 - b.size.y)) * V)
		spot.y = realm.world.ground_m(spot.x, spot.z)
		s.march(spot)
		i += 1
	return i


# ------------------------------------------------------------------- sieges

func start_siege(enemy: Dictionary = {}) -> void:
	if not siege.is_empty() or realm.warfare == null:
		return
	if enemy.is_empty():
		enemy = _strongest_enemy()
	var now := realm.clock.day * 24.0 + realm.clock.hour
	siege = {"enemy": str(enemy["name"]), "started": now, "waves_left": SIEGE_WAVES,
		"next_wave": now, "next_shot": now + 1.0, "engine": null, "hits": 0, "day": realm.clock.day}
	realm.say("%s has come in strength. The town is under siege." % siege["enemy"])
	realm.note("siege", "%s laid siege to the town." % siege["enemy"])
	# The engine, out past the plots on their side.
	var b: Vector2 = enemy.get("bearing", Vector2(0, 1))
	var at := realm.village.well_pos + Vector3(b.x, 0.0, b.y) * ENGINE_RANGE_M
	for tries in 8:
		var col := VoxelWorld.column_of(at)
		if realm.world.column_meshable(col.x, col.y):
			break
		at = realm.village.well_pos + Vector3(b.x, 0.0, b.y) * (ENGINE_RANGE_M - 4.0 * (tries + 1))
	siege["engine"] = realm.warfare.add_engine(at, "trebuchet", 12)


func _tick_siege(_hour: float, _day: int) -> void:
	var now := realm.clock.day * 24.0 + realm.clock.hour
	var wf := realm.warfare
	var engine: Fighter = siege["engine"]
	var engine_alive := engine != null and is_instance_valid(engine) and not engine.is_dead()
	if int(siege["waves_left"]) > 0 and now >= float(siege["next_wave"]):
		siege["waves_left"] = int(siege["waves_left"]) - 1
		siege["next_wave"] = now + SIEGE_WAVE_HOURS
		wf.raid(_rng.randi_range(3, 6))
	if engine_alive and now >= float(siege["next_shot"]):
		siege["next_shot"] = now + ENGINE_HOURS
		if not realm.town.buildings.is_empty():
			var rec: Dictionary = realm.town.buildings[_rng.randi() % realm.town.buildings.size()]
			var aim := realm.door_of(rec)
			var patch: VoxelPatch = rec.get("patch")
			if patch != null:
				aim = Vector3((patch.footprint.position.x + patch.footprint.size.x * 0.5) * V, 0.0,
					(patch.footprint.position.y + patch.footprint.size.y * 0.5) * V)
				aim.y = realm.world.ground_m(aim.x, aim.z) + 1.0
			var from := engine.global_position + Vector3(0, 2.0, 0)
			if wf.fire(engine, "trebuchet", from, aim):
				siege["hits"] = int(siege["hits"]) + 1
				realm.say("A stone from the engine hits the %s!" % str(rec["archetype"]).replace("_", " "))
				var weather: Node = realm.system("Weather")
				if weather != null and weather.has_method("ignite") and _rng.randf() < 0.5:
					weather.call("ignite", rec, "the siege")
	var over := now - float(siege["started"]) >= SIEGE_HOURS
	var beaten := int(siege["waves_left"]) == 0 and wf.raiders.is_empty()
	if beaten or over or int(siege["hits"]) >= 3:
		_end_siege(beaten or (over and int(siege["hits"]) < 3))


func _end_siege(won: bool) -> void:
	var enemy: String = siege["enemy"]
	var engine: Fighter = siege["engine"]
	if engine != null and is_instance_valid(engine) and not engine.is_dead():
		engine.take_hit(9999.0, engine.global_position, null)
	siege = {}
	var nb := _enemies()
	if won:
		var loot := 150 + _rng.randi_range(0, 250)
		realm.town.coins += loot
		realm.town.stock["tools"] = int(realm.town.stock.get("tools", 0)) + 5
		morale = minf(morale + 0.2, 1.0)
		for s: Fighter in soldiers():
			if is_instance_valid(s):
				s.veteran = minf(s.veteran + 0.25, 1.0)
		if nb != null and nb.has_method("by_name"):
			var t: Dictionary = nb.call("by_name", enemy)
			if not t.is_empty():
				t["strength"] = maxi(int(int(t["strength"]) * 0.66), 5)
				nb.call("adjust", enemy, 0.2)
		else:
			_fallback_enemy["strength"] = maxi(int(_fallback_enemy["strength"] * 0.66), 5)
		realm.say("The siege is broken. %s fell back, and left %d coins and their tools behind." % [enemy, loot])
		realm.note("siege", "The siege by %s was broken; %d coins taken." % [enemy, loot])
	else:
		var tribute := 200 + int(strength())
		realm.town.coins -= tribute
		morale = maxf(morale - 0.2, 0.0)
		realm.say("The town bought %s off with %d coins. They will be back." % [enemy, tribute])
		realm.note("siege", "%s's siege ended in tribute of %d coins." % [enemy, tribute])


# -------------------------------------------------------------- expeditions

func march_on(worker: Worker, enemy: Dictionary, count: int) -> bool:
	if not expedition.is_empty():
		worker.speak("The army is away already, at %s." % expedition["target"])
		return true
	if not siege.is_empty():
		worker.speak("We are under siege. Nobody marches anywhere.")
		return true
	var live: Array[Fighter] = []
	for s: Fighter in soldiers():
		if is_instance_valid(s) and not s.is_dead():
			live.append(s)
	count = mini(count if count > 0 else live.size(), live.size())
	if count < MIN_EXPEDITION:
		worker.speak("We have %d soldiers; it takes three to call it an army." % live.size())
		return true
	if worker.busy():
		worker.speak("When I am done here.")
		return true
	var going := live.slice(0, count)
	var weapons: Array = []
	var vet := 0.0
	for s2: Fighter in going:
		weapons.append(s2.weapon)
		vet += s2.veteran
		realm.warfare.soldiers.erase(s2)
		s2.queue_free()
	var days := int(enemy.get("distance_days", 3)) * 2
	var edge := realm.village.well_pos
	var nb := _enemies()
	if nb != null and nb.has_method("edge_point") and enemy.has("bearing") and enemy.has("kind"):
		edge = nb.call("edge_point", enemy)
	else:
		var b: Vector2 = enemy.get("bearing", Vector2(0, 1))
		edge = realm.village.well_pos + Vector3(b.x, 0.0, b.y) * 30.0
	expedition = {"target": str(enemy["name"]), "count": count, "captain": worker.memory.worker_id,
		"return_day": realm.clock.day + days, "strength": (count * 3.0) * (1.0 + vet / count) * (0.5 + morale),
		"weapons": weapons}
	worker.take_errand_job("wait", edge, float(days) * 24.0,
		"Marching on %s with %d. %d days there and back." % [enemy["name"], count, days],
		{"where": str(enemy["name"]), "doing": "survey"})
	realm.note("army", "%s led %d soldiers against %s." % [worker.display_name(), count, enemy["name"]])
	return true


func call_home(worker: Worker) -> bool:
	if expedition.is_empty():
		worker.speak("The army is here.")
		return true
	expedition["return_day"] = realm.clock.day + 1
	expedition["recalled"] = true
	worker.speak("Word is sent. They turn for home tomorrow.")
	return true


func _expedition_returns() -> void:
	var e := expedition
	expedition = {}
	var captain: Worker = realm.crew.get_worker(str(e["captain"]))
	if captain != null and not captain.job_errand.is_empty():
		captain.drop_everything()
		captain.walk_to(realm.village.well_pos, "idle")
	var nb := _enemies()
	var enemy: Dictionary = {}
	if nb != null and nb.has_method("by_name"):
		enemy = nb.call("by_name", str(e["target"]))
	if enemy.is_empty():
		enemy = _fallback_enemy
	var at := realm.warfare.barracks_stand()
	if at == Vector3.INF:
		at = realm.village.well_pos
	var line := ""
	if bool(e.get("recalled", false)):
		for i in int(e["count"]):
			realm.warfare.add_soldier(at, str(e["weapons"][i]), 0.1)
		line = "The army is back from the road, none the worse."
	else:
		var ours := float(e["strength"]) * _rng.randf_range(0.8, 1.3)
		var theirs := float(enemy.get("strength", 30)) * _rng.randf_range(0.8, 1.2)
		if ours > theirs:
			var decisive := ours > theirs * 1.5
			var lost := 0 if decisive else _rng.randi_range(0, maxi(int(e["count"]) / 4, 0))
			for i in int(e["count"]) - lost:
				realm.warfare.add_soldier(at, str(e["weapons"][i]), 0.3)
			var loot := _rng.randi_range(100, 400)
			realm.town.coins += loot
			realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + 40
			enemy["strength"] = maxi(int(float(enemy["strength"]) * 0.6), 5)
			morale = minf(morale + 0.2, 1.0)
			if decisive and nb != null and nb.has_method("set_treaty"):
				nb.call("set_treaty", str(enemy["name"]), "vassal")
				line = "Victory at %s! %s bends the knee; %d coins and their granary taken%s." % [
					enemy["name"], enemy["name"], loot, ", %d of ours lost" % lost if lost > 0 else ""]
			else:
				line = "Victory at %s: %d coins and grain brought home%s." % [enemy["name"], loot,
					", %d of ours lost" % lost if lost > 0 else ""]
		else:
			var lost := _rng.randi_range(int(e["count"]) / 2, int(e["count"]))
			for i in int(e["count"]) - lost:
				realm.warfare.add_soldier(at, str(e["weapons"][i]), 0.2)
			morale = maxf(morale - 0.25, 0.0)
			if nb != null and nb.has_method("adjust"):
				nb.call("adjust", str(enemy["name"]), -0.3)
			line = "Beaten at %s. %d of %d came home." % [enemy["name"], int(e["count"]) - lost, int(e["count"])]
	if captain != null:
		captain.speak(line)
	else:
		realm.say(line)
	realm.note("army", line)


# ------------------------------------------------------------------ talking

func verbs() -> Dictionary:
	return {
		"wall": {
			"says": "raise a wall or palisade round the town, or along one side of it",
			"optional": ["side", "walling"],
			"types": {"side": ["north", "south", "east", "west", "all"],
				"walling": ["stone", "timber"]},
		},
		"man_walls": {
			"says": "send the soldiers up onto the walls",
			"instant": true,
		},
		"pay_army": {
			"says": "pay the soldiers their wages from the purse",
			"instant": true,
		},
		"feed_army": {
			"says": "a hot meal for the soldiers from the larder",
			"instant": true,
		},
		"alarm": {
			"says": "sound the alarm: everyone indoors, soldiers to the well",
			"instant": true,
		},
		"stand_down": {
			"says": "the all clear after an alarm",
			"instant": true,
		},
		"recall_army": {
			"says": "call the army home from wherever it has marched",
			"instant": true,
		},
		"march": {
			"says": "lead the army against a neighbouring town, by name",
			"required": ["town"],
			"optional": ["count"],
			"types": {"count": "int"},
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"wall":
			var side := str(step.get("side", "all"))
			if side == "all":
				side = ""
			if not start_wall(worker, side, str(step.get("walling", "stone")) == "timber"):
				return "There is nothing to wall."
			return "started"
		"man_walls":
			var n := man_the_walls()
			worker.speak("%d on the walls." % n if n > 0 else "There are no soldiers to man them.")
			return "done"
		"pay_army":
			var n2 := soldiers().size()
			if n2 == 0:
				return "There is nobody to pay."
			if realm.town.coins < n2 * PAY_EACH:
				return "Pay for %d is %d coins; the purse is short." % [n2, n2 * PAY_EACH]
			realm.town.coins -= n2 * PAY_EACH
			morale = minf(morale + 0.15, 1.0)
			worker.speak("%d coins paid out. They are %s." % [n2 * PAY_EACH, morale_word()])
			realm.note("army", "The soldiers were paid %d coins." % (n2 * PAY_EACH))
			return "done"
		"feed_army":
			var n3 := soldiers().size()
			var food := int(realm.town.stock.get("food", 0))
			if food < n3 * 2:
				return "The larder has %d food; not enough for a proper meal for %d." % [food, n3]
			realm.town.stock["food"] = food - n3 * 2
			morale = minf(morale + 0.1, 1.0)
			_unfed_days = 0
			worker.speak("A hot meal all round. They are %s." % morale_word())
			return "done"
		"alarm":
			var inside := 0
			for w: Worker in realm.crew.hired():
				if w != worker and not w.busy():
					var rec := realm.warfare.nearest_building(w.global_position) if realm.warfare != null else {}
					if not rec.is_empty():
						w.take_errand_job("wait", realm.door_of(rec), 4.0, "", {"where": "indoors", "doing": "survey"})
						inside += 1
			if realm.warfare != null:
				realm.warfare.defend(realm.village.well_pos)
			worker.speak("Alarm raised: %d indoors, the soldiers at the well." % inside)
			realm.note("army", "The alarm was sounded.")
			return "done"
		"stand_down":
			for w2: Worker in realm.crew.hired():
				if not w2.job_errand.is_empty() and str(w2.job_errand.get("extra", {}).get("where", "")) == "indoors":
					w2.drop_everything()
			worker.speak("Stood down.")
			return "done"
		"recall_army":
			call_home(worker)
			return "done"
		"march":
			var enemy := _enemy_named(str(step.get("town", "")).to_lower())
			if enemy.is_empty():
				return "March on whom? Name a town."
			if not expedition.is_empty():
				return "The army is away already, at %s." % expedition["target"]
			if not siege.is_empty():
				return "We are under siege. Nobody marches anywhere."
			if worker.busy():
				return "When I am done here."
			var before := expedition.size()
			march_on(worker, enemy, int(step.get("count", 0)))
			return "started" if expedition.size() > before else "done"
	return "failed"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["how strong is our army", "how strong is the army", "is the army ready", "army ready",
			"how is the army", "how are the soldiers", "state of the army", "army's morale", "morale of the army"]):
		var n := soldiers().size()
		if n == 0 and expedition.is_empty():
			return "There is no army. A barracks and some recruits, and there will be."
		var line := "%d soldiers, strength about %d, %s" % [n, int(strength()), morale_word()]
		if not walls.is_empty():
			line += "; the town is walled"
		if not expedition.is_empty():
			line += "; %d away at %s" % [int(expedition["count"]), expedition["target"]]
		return line + "."
	if Realm.has_phrase(t, ["best soldier", "who is our best", "finest soldier"]):
		var b := best_soldier()
		if b == null:
			return "There are no soldiers."
		return "%s, with %s — %s." % [b.display_name, b.weapon if b.weapon != "" else "bare hands",
			"a veteran" if b.veteran > 0.4 else "green still"]
	if Realm.has_phrase(t, ["where is the army", "when will the army", "army back", "where are the soldiers"]):
		if expedition.is_empty():
			return "The army is here in town."
		return "%d soldiers are away at %s, due back on day %d." % [int(expedition["count"]), expedition["target"],
			int(expedition["return_day"])]
	if Realm.has_phrase(t, ["under siege", "is there a siege", "the siege"]):
		if siege.is_empty():
			return "No siege. The walls are %s." % ("up" if not walls.is_empty() else "not built")
		return "%s is at the gates: %d waves still to come, %d stones landed." % [siege["enemy"],
			int(siege["waves_left"]), int(siege["hits"])]
	if Realm.has_phrase(t, ["do we have walls", "is the town walled", "how are the walls", "the wall"]):
		if not wall_job.is_empty():
			return "The %s is %d percent up." % [wall_job["kind"], int(wall_progress() * 100.0)]
		return "The town is walled." if not walls.is_empty() else "No walls yet. Say the word."
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if not siege.is_empty():
		out.append("siege · day %d" % (realm.clock.day - int(siege["day"]) + 1))
	if not expedition.is_empty():
		out.append("army away · back day %d" % int(expedition["return_day"]))
	if not wall_job.is_empty():
		out.append("%s %d%%" % [wall_job["kind"], int(wall_progress() * 100.0)])
	return out


func snapshot() -> Dictionary:
	var ex := expedition.duplicate()
	return {"morale": morale, "walls": walls.duplicate(), "expedition": ex, "next_siege_day": _next_siege_day,
		"wall_job": {} if wall_job.is_empty() else {"worker_id": wall_job["worker_id"], "cells": wall_job["cells"],
			"i": wall_job["i"], "mat": wall_job["mat"], "kind": wall_job["kind"], "rect": wall_job["rect"], "laid": wall_job["laid"]}}


func restore(d: Dictionary) -> void:
	morale = float(d.get("morale", morale))
	var saved: Array = (d.get("walls", []) as Array).duplicate()
	walls.clear()
	for r: Variant in saved:
		walls.append(r)
	expedition = d.get("expedition", {})
	_next_siege_day = int(d.get("next_siege_day", _next_siege_day))
	var wj: Dictionary = d.get("wall_job", {})
	if not wj.is_empty():
		var cells: Array[Vector3i] = []
		for c: Variant in wj.get("cells", []):
			cells.append(c)
		wall_job = {"worker_id": str(wj["worker_id"]), "cells": cells, "i": int(wj["i"]), "mat": int(wj["mat"]),
			"kind": str(wj["kind"]), "rect": wj["rect"], "laid": int(wj["laid"])}
