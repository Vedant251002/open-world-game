extends Node
## The world talking back: things that happen to the town that it did not
## order.
##
## A merchant with iron nobody here can make, refugees at the gate, wolves
## in the pens, a plague, a bumper harvest, bandits with a letter. Each is a
## row in a table with the odds of it, the conditions it needs, what it does
## when it lands, and — for the ones that ask something of the king — the
## choices and what each costs. At most one a morning, with a decent chance
## of none, so a week can go by quietly and the one that does come is news.
## Every event reaches the other systems only through the hub, and works
## when the system it would like is not there.

const NONE_CHANCE := 0.45
const REPEAT_DAYS := 6
const DECIDE_DAYS := 2

var realm: Realm
var last_fired: Dictionary = {}      ## id -> day
var pending: Dictionary = {}         ## {id, choices: Array[String], expires, data}
var live: Dictionary = {}            ## id -> state for events that run on
var _rng := RandomNumberGenerator.new()
var _stall: Node3D = null
var _events: Array[Dictionary] = []


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	_events = [
		{"id": "merchant", "weight": 5, "min_day": 2, "fire": _merchant},
		{"id": "refugees", "weight": 4, "min_day": 3, "fire": _refugees},
		{"id": "wolves", "weight": 3, "min_day": 4, "fire": _wolves},
		{"id": "plague", "weight": 1, "min_day": 8, "fire": _plague},
		{"id": "harvest", "weight": 3, "min_day": 3, "fire": _harvest},
		{"id": "blight", "weight": 2, "min_day": 5, "fire": _blight},
		{"id": "bandits", "weight": 3, "min_day": 5, "fire": _bandits},
		{"id": "lost_child", "weight": 3, "min_day": 2, "fire": _lost_child},
		{"id": "treasure", "weight": 2, "min_day": 3, "fire": _treasure},
		{"id": "visitor", "weight": 3, "min_day": 4, "fire": _visitor},
		{"id": "players", "weight": 3, "min_day": 2, "fire": _players},
		{"id": "storm", "weight": 2, "min_day": 3, "fire": _storm},
		{"id": "omen", "weight": 4, "min_day": 1, "fire": _omen},
	]


# ------------------------------------------------------------------- public

func trigger(id: String) -> bool:
	for e: Dictionary in _events:
		if str(e["id"]) == id:
			(e["fire"] as Callable).call()
			last_fired[id] = realm.clock.day
			return true
	return false


func choose(choice: String) -> bool:
	if pending.is_empty() or choice not in (pending["choices"] as Array):
		return false
	var p := pending
	pending = {}
	_resolve(str(p["id"]), choice, p.get("data", {}))
	return true


func pending_event() -> Dictionary:
	return pending


func _ask(id: String, choices: Array[String], data: Dictionary = {}) -> void:
	pending = {"id": id, "choices": choices, "expires": realm.clock.day + DECIDE_DAYS, "data": data}


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	# A decision left too long decides itself.
	if not pending.is_empty() and day >= int(pending["expires"]):
		var p := pending
		pending = {}
		var default: String = (p["choices"] as Array).back()
		realm.note("event", "Nothing was said about the %s; it came to nothing." % str(p["id"]).replace("_", " "))
		_resolve(str(p["id"]), default, p.get("data", {}))
	_tick_live(day)
	if not pending.is_empty() or _rng.randf() < NONE_CHANCE:
		return
	var pool: Array[Dictionary] = []
	var total := 0
	for e: Dictionary in _events:
		if day < int(e["min_day"]):
			continue
		if day - int(last_fired.get(str(e["id"]), -100)) < REPEAT_DAYS:
			continue
		pool.append(e)
		total += int(e["weight"])
	if pool.is_empty():
		return
	var roll := _rng.randi_range(1, total)
	for e2: Dictionary in pool:
		roll -= int(e2["weight"])
		if roll <= 0:
			trigger(str(e2["id"]))
			return


func _tick_live(day: int) -> void:
	if live.has("merchant") and day > int(live["merchant"]["day"]):
		live.erase("merchant")
		_strike_stall()
		if pending.get("id", "") == "merchant":
			pending = {}
		realm.say("The merchant has packed up and gone.")
	if live.has("wolves"):
		var w: Dictionary = live["wolves"]
		var alive := 0
		for a: Variant in w["pack"]:
			if is_instance_valid(a) and float((a as Node).get("_dying")) <= 0.0:
				alive += 1
		if alive == 0 or day - int(w["day"]) >= 2:
			live.erase("wolves")
			for a2: Variant in w["pack"]:
				if is_instance_valid(a2):
					(a2 as Node).queue_free()
			realm.say("The wolves are gone." if alive == 0 else "The wolves have moved on.")
			realm.note("event", "The wolves left, %d of them shot." % (int(w["count"]) - alive))
		elif realm.livestock != null and not realm.livestock.animals.is_empty() and _rng.randf() < 0.7:
			var victim: Animal = realm.livestock.animals[_rng.randi() % realm.livestock.animals.size()]
			if is_instance_valid(victim):
				realm.livestock.animals.erase(victim)
				victim.queue_free()
				realm.say("The wolves took a %s in the night." % victim.kind)
				realm.note("event", "Wolves killed a %s." % victim.kind)
	if live.has("bandits") and day >= int(live["bandits"]["due"]):
		live.erase("bandits")
		if realm.warfare != null:
			realm.say("The bandits are here for their answer.")
			realm.warfare.raid(_rng.randi_range(4, 6))
		realm.note("event", "The bandits came for what they were refused.")


# ------------------------------------------------------------------- events

func _merchant() -> void:
	var goods: String = ["glass", "tools", "brick", "cloth"][_rng.randi() % 4]
	var n := _rng.randi_range(20, 60)
	var price := int(float(Town.PRICE.get(goods, Town.DEFAULT_PRICE)) * 1.3)
	live["merchant"] = {"day": realm.clock.day, "goods": goods, "n": n, "price": price}
	_pitch_stall()
	realm.say("A travelling merchant is by the well with %d %s at %d a unit — today only." % [n, goods, price])
	realm.note("event", "A merchant came with %s." % goods)
	_ask("merchant", ["buy", "send away"], {"goods": goods, "n": n, "price": price})


func _refugees() -> void:
	var n := _rng.randi_range(2, 5)
	realm.say("%d people are at the edge of town asking for shelter." % n)
	realm.note("event", "%d refugees came asking for shelter." % n)
	_ask("refugees", ["let in", "turn away"], {"n": n})


func _wolves() -> void:
	if realm.wildlife == null or realm.props_root == null:
		return
	var n := _rng.randi_range(3, 5)
	var pack: Array = []
	var well := realm.village.well_pos
	var ang := _rng.randf() * TAU
	for i in n:
		var at := well + Vector3(cos(ang + i * 0.3), 0.0, sin(ang + i * 0.3)) * 40.0
		var col := VoxelWorld.column_of(at)
		if not realm.world.column_meshable(col.x, col.y):
			at = well + Vector3(cos(ang + i * 0.3), 0.0, sin(ang + i * 0.3)) * 22.0
		at.y = realm.world.ground_m(at.x, at.z) + 0.3
		var wolf := Animal.new()
		realm.wildlife.add_child(wolf)
		wolf.setup("dog", realm.world, realm.clock, at)
		wolf.name = "wolf_%d" % i
		wolf.roam = 30.0
		realm.wildlife.beasts.append(wolf)
		pack.append(wolf)
	live["wolves"] = {"day": realm.clock.day, "pack": pack, "count": n}
	realm.say("Wolves! A pack of %d is circling the pens." % n)
	realm.note("event", "A pack of %d wolves came down on the town." % n)
	_ask("wolves", ["hunt", "wait"], {})


func _plague() -> void:
	var hl: Node = realm.system("Health")
	var n := _rng.randi_range(2, 4)
	if hl != null and hl.has_method("outbreak"):
		hl.call("outbreak", "flux", n)
	else:
		var pool := realm.crew.workers.duplicate()
		pool.shuffle()
		for w: Worker in pool.slice(0, n):
			w.health = maxf(w.health - 40.0, 10.0)
		realm.say("A sickness is going through the town. %d down with it." % n)
	realm.note("event", "The flux came to town.")
	_ask("plague", ["quarantine", "let it run"], {})


func _harvest() -> void:
	var pop := maxi(realm.population.count(), 4)
	var n := pop * 4 + _rng.randi_range(10, 30)
	realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + n
	if realm.farm != null and realm.farm.has_method("advance_days"):
		realm.farm.advance_days(1.0)
	realm.say("A bumper harvest: %d food into the larder." % n)
	realm.note("event", "A bumper harvest brought in %d food." % n)


func _blight() -> void:
	var lost := 0
	if realm.farm != null and not realm.farm.tiles.is_empty():
		var keys := realm.farm.tiles.keys()
		keys.shuffle()
		for k: Variant in keys.slice(0, mini(6, keys.size())):
			var tile: Dictionary = realm.farm.tiles[k]
			if tile.has("kind") and str(tile["kind"]) != "":
				tile["stage"] = -1
				tile["kind"] = ""
				realm.farm.tiles[k] = tile
				lost += 1
	var food := int(realm.town.stock.get("food", 0))
	var spoiled := mini(food / 4, 40)
	realm.town.stock["food"] = food - spoiled
	realm.say("Blight in the fields: %d tiles lost and %d food spoiled." % [lost, spoiled])
	realm.note("event", "Blight took %d tiles and %d food." % [lost, spoiled])


func _bandits() -> void:
	var demand := 100 + _rng.randi_range(0, 200)
	realm.say("A letter nailed to the gate: %d coins in two days, or the bandits come for it." % demand)
	realm.note("event", "Bandits demanded %d coins." % demand)
	_ask("bandits", ["pay", "refuse"], {"demand": demand})


func _lost_child() -> void:
	var people := realm.population.alive()
	var parent := people[_rng.randi() % people.size()].name if not people.is_empty() else "somebody"
	realm.say("%s's child has wandered into the woods and not come back." % parent)
	realm.note("event", "%s's child went missing in the woods." % parent)
	_ask("lost_child", ["search", "wait"], {"parent": parent})


func _treasure() -> void:
	realm.say("An old map turned up in the tavern: a mark in the woods, and a story about a chest.")
	realm.note("event", "A treasure map turned up.")
	_ask("treasure", ["dig", "ignore"], {})


func _visitor() -> void:
	var nb: Node = realm.system("Neighbours")
	var who := "a lord from the hills"
	var name := ""
	if nb != null and nb.has_method("list"):
		var towns: Array = nb.call("list")
		if not towns.is_empty():
			var t: Dictionary = towns[_rng.randi() % towns.size()]
			who = "%s of %s" % [t["leader"], t["name"]]
			name = str(t["name"])
	var favour: String = ["100 coins", "50 food"][_rng.randi() % 2]
	realm.say("%s is here on a visit, and asks a favour: %s." % [who.capitalize(), favour])
	realm.note("event", "%s visited and asked for %s." % [who.capitalize(), favour])
	_ask("visitor", ["grant", "refuse"], {"favour": favour, "town": name, "who": who})


func _players() -> void:
	realm.say("A troupe of players is at the well and would perform tonight, for 20 coins.")
	realm.note("event", "A troupe of players came through.")
	_ask("players", ["let them perform", "no"], {})


func _storm() -> void:
	var weather: Node = realm.system("Weather")
	if weather != null and weather.has_method("force"):
		weather.call("force", "storm")
		realm.say("The sky has gone black in the west. A storm is coming in.")
	else:
		var rec := realm.building("hut")
		if rec.is_empty() and not realm.town.buildings.is_empty():
			rec = realm.town.buildings[0]
		if not rec.is_empty():
			var patch: VoxelPatch = rec["patch"]
			var top := patch.origin + Vector3i(patch.size.x / 2, patch.size.y - 1, patch.size.z / 2)
			for y in range(top.y, patch.origin.y, -1):
				if realm.world.get_voxel(Vector3i(top.x, y, top.z)) != VoxelTypes.AIR:
					realm.world.set_voxel(Vector3i(top.x, y, top.z), VoxelTypes.AIR)
					break
		realm.say("A storm in the night tore at the roofs.")
	realm.note("event", "A storm came through.")


func _omen() -> void:
	var good := _rng.randf() < 0.6
	var lines := ["Two ravens sat on the well all morning. The old people are pleased.",
		"A white hart was seen at the edge of the woods."] if good else [
		"The well ran cloudy for an hour. People are muttering.",
		"A cold wind blew the shrine candles out."]
	var line: String = lines[_rng.randi() % lines.size()]
	for c: Population.Citizen in realm.population.alive():
		c.mood = clampf(c.mood + (0.03 if good else -0.03), 0.0, 1.0)
	realm.say(line)
	realm.note("omen", line)


# ---------------------------------------------------------------- outcomes

func _resolve(id: String, choice: String, data: Dictionary) -> void:
	var town := realm.town
	var pop := realm.population
	var line := ""
	match id:
		"merchant":
			if choice == "buy":
				var cost := int(data["n"]) * int(data["price"])
				if town.coins < cost:
					var can := town.coins / int(data["price"])
					if can <= 0:
						line = "The purse cannot stretch to any of it."
					else:
						town.coins -= can * int(data["price"])
						town.stock[str(data["goods"])] = int(town.stock.get(str(data["goods"]), 0)) + can
						line = "Bought %d %s, all the purse would stand." % [can, data["goods"]]
				else:
					town.coins -= cost
					town.stock[str(data["goods"])] = int(town.stock.get(str(data["goods"]), 0)) + int(data["n"])
					line = "Bought %d %s for %d coins." % [data["n"], data["goods"], cost]
			else:
				line = "The merchant is sent on his way."
			live.erase("merchant")
			_strike_stall()
		"refugees":
			if choice == "let in":
				var before := pop.count()
				realm.crew.spawn_citizens(int(data["n"]), _rng.randi(), realm.village.bounds_v)
				pop._sync()
				var came := pop.count() - before
				line = "%d taken in%s." % [came, "; there are not beds for all of them" if pop.homeless() > 0 else ""]
				if pop.homeless() > 0:
					for c: Population.Citizen in pop.alive():
						c.mood = clampf(c.mood - 0.03, 0.0, 1.0)
			else:
				line = "They are turned away. Nobody liked doing it."
				for c2: Population.Citizen in pop.alive():
					c2.mood = clampf(c2.mood - 0.02, 0.0, 1.0)
		"wolves":
			if choice == "hunt":
				if realm.warfare != null and not realm.warfare.soldiers.is_empty():
					var w: Dictionary = live.get("wolves", {})
					if not w.is_empty():
						for s: Fighter in realm.warfare.soldiers:
							for a: Variant in w["pack"]:
								if is_instance_valid(a):
									s.attack(a)
									break
					line = "The soldiers are out after the pack."
				else:
					var hands := realm.crew.hired()
					if not hands.is_empty() and live.has("wolves"):
						var w2: Dictionary = live["wolves"]
						var first: Node3D = null
						for a2: Variant in w2["pack"]:
							if is_instance_valid(a2):
								first = a2
								break
						if first != null:
							(hands[0] as Worker).take_errand_job("wait", first.global_position, 3.0,
								"After the wolves with a stick and a shout.", {"where": "the woods", "doing": "survey"})
					line = "Somebody is sent to drive them off. Guns would be better."
			else:
				line = "The pens are left to take their chances."
		"plague":
			var law: Node = realm.system("Law")
			if choice == "quarantine":
				if law != null and law.has_method("try_order") and not realm.crew.hired().is_empty():
					law.call("try_order", realm.crew.hired()[0], "close the borders")
				var hl: Node = realm.system("Health")
				if hl != null:
					var sick: Dictionary = hl.get("sick")
					for wid: String in sick.keys():
						sick[wid]["severity"] = 0.5
				line = "The town is shut and the sick kept apart. It will pass sooner."
			else:
				line = "It runs its course."
		"bandits":
			if choice == "pay":
				town.coins -= int(data["demand"])
				line = "%d coins left at the gate. The bandits keep their word, this once." % int(data["demand"])
			else:
				live["bandits"] = {"due": realm.clock.day + 2}
				line = "The letter is torn up. They will come in two days; be ready."
		"lost_child":
			if choice == "search":
				var hands2 := realm.crew.hired()
				if not hands2.is_empty():
					var ang := _rng.randf() * TAU
					var at := realm.village.well_pos + Vector3(cos(ang), 0.0, sin(ang)) * 60.0
					var col := VoxelWorld.column_of(at)
					if not realm.world.column_meshable(col.x, col.y):
						at = realm.village.well_pos + Vector3(cos(ang), 0.0, sin(ang)) * 25.0
					(hands2[0] as Worker).take_errand_job("wait", at, 3.0, "Into the woods after the child.",
						{"where": "the woods", "doing": "survey"})
				if _rng.randf() < 0.8:
					line = "Found, three hours on, up a tree and furious. %s will not forget it." % data["parent"]
					for c3: Population.Citizen in pop.alive():
						c3.mood = clampf(c3.mood + 0.05, 0.0, 1.0)
				else:
					line = "Nothing found before dark. The child walked in at dawn, muddy and fine."
			else:
				line = "The child turned up the next morning. %s remembers who did not look." % data["parent"]
				var p := pop.by_name(str(data["parent"]))
				if p != null:
					p.mood = clampf(p.mood - 0.2, 0.0, 1.0)
		"treasure":
			if choice == "dig":
				var hands3 := realm.crew.hired()
				if not hands3.is_empty():
					var ang2 := _rng.randf() * TAU
					var at2 := realm.village.well_pos + Vector3(cos(ang2), 0.0, sin(ang2)) * 50.0
					var col2 := VoxelWorld.column_of(at2)
					if not realm.world.column_meshable(col2.x, col2.y):
						at2 = realm.village.well_pos + Vector3(cos(ang2), 0.0, sin(ang2)) * 25.0
					(hands3[0] as Worker).take_errand_job("wait", at2, 2.0, "Off with a spade and the map.",
						{"where": "the woods", "doing": "lay"})
				if _rng.randf() < 0.5:
					var coins := _rng.randi_range(200, 600)
					town.coins += coins
					line = "A chest under a stone: %d coins." % coins
				else:
					line = "A hole, two hours of digging, and a rusted pot. Stories."
			else:
				line = "The map goes in the fire."
		"visitor":
			var nb: Node = realm.system("Neighbours")
			if choice == "grant":
				if str(data["favour"]).begins_with("100"):
					town.coins -= 100
				else:
					town.stock["food"] = maxi(int(town.stock.get("food", 0)) - 50, 0)
				if nb != null and nb.has_method("adjust") and str(data["town"]) != "":
					nb.call("adjust", str(data["town"]), 0.3)
				for c4: Population.Citizen in pop.alive():
					c4.mood = clampf(c4.mood + 0.03, 0.0, 1.0)
				line = "%s leaves well pleased." % str(data["who"]).capitalize()
			else:
				if nb != null and nb.has_method("adjust") and str(data["town"]) != "":
					nb.call("adjust", str(data["town"]), -0.15)
				line = "%s leaves with a thin smile." % str(data["who"]).capitalize()
		"players":
			if choice == "let them perform":
				if town.coins < 20:
					line = "The purse has not got 20 coins in it."
				else:
					town.coins -= 20
					for c5: Population.Citizen in pop.alive():
						c5.mood = clampf(c5.mood + 0.15, 0.0, 1.0)
					line = "The whole town laughed till dark. Worth twenty of anybody's coins."
			else:
				line = "The players move on to the next town."
		_:
			line = "Done."
	realm.say(line)
	realm.note("event", line)


# ------------------------------------------------------------------ talking

## The choices of whatever is waiting are put in front of the router with
## the town (see situation()); this is how one of them is taken.
func verbs() -> Dictionary:
	return {
		"decide": {
			"says": "settle the matter that is waiting on your employer, with one of the choices it offers",
			"required": ["choice"],
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	if str(step.get("do", "")) != "decide":
		return "failed"
	if pending.is_empty():
		return "Nothing is waiting on you."
	var choice := str(step.get("choice", "")).strip_edges().to_lower()
	var choices: Array = pending["choices"]
	if choice not in choices:
		# Near enough: the first choice the words fit.
		for c: String in choices:
			if choice.find(c) >= 0 or c.find(choice) >= 0:
				choice = c
				break
	if not choose(choice):
		return "It is one of: %s." % " or ".join(choices)
	return "done"


## What the router should know is waiting. One line, or "".
func situation() -> String:
	return _pending_line()


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["anything happening", "is anything going on", "what is going on", "what's going on",
			"any trouble", "what are my options", "what can i do about", "what do they want", "what does the merchant",
			"what does he have", "what is he selling", "who is at the gate"]):
		if pending.is_empty():
			var bits: Array[String] = []
			for id: String in live:
				bits.append(id.replace("_", " "))
			return "Nothing waiting on you." if bits.is_empty() else "Still going on: %s." % ", ".join(bits)
		return _pending_line()
	return ""


func _pending_line() -> String:
	if not pending.is_empty():
		var id2 := str(pending["id"])
		var data: Dictionary = pending.get("data", {})
		var what := ""
		match id2:
			"merchant": what = "The merchant has %d %s at %d each" % [data["n"], data["goods"], data["price"]]
			"refugees": what = "%d refugees are asking for shelter" % int(data["n"])
			"wolves": what = "Wolves are at the pens"
			"plague": what = "The flux is in the town"
			"bandits": what = "Bandits want %d coins" % int(data["demand"])
			"lost_child": what = "%s's child is lost in the woods" % data["parent"]
			"treasure": what = "There is a treasure map"
			"visitor": what = "%s asks for %s" % [str(data["who"]).capitalize(), data["favour"]]
			"players": what = "A troupe would perform for 20 coins"
			_: what = "Something is waiting"
		return "%s. You can say: %s." % [what, " or ".join(pending["choices"])]
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if not pending.is_empty():
		out.append("%s · decide" % str(pending["id"]).replace("_", " "))
	elif live.has("wolves"):
		out.append("wolves!")
	elif live.has("merchant"):
		out.append("merchant in town")
	return out


# -------------------------------------------------------------------- stall

func _pitch_stall() -> void:
	if _stall != null or realm.props_root == null:
		return
	_stall = Node3D.new()
	var at := realm.village.well_pos + Vector3(-6.0, 0.0, -6.0)
	at.y = realm.world.ground_m(at.x, at.z)
	_stall.position = at
	realm.props_root.add_child(_stall)
	var wood := Color("#6b4e32")
	BoxKit.add(_stall, Vector3(-1.0, 0.7, -0.5), Vector3(2.0, 0.08, 1.0), wood)
	BoxKit.add(_stall, Vector3(-0.95, 0.0, -0.4), Vector3(0.1, 0.7, 0.1), wood)
	BoxKit.add(_stall, Vector3(0.85, 0.0, -0.4), Vector3(0.1, 0.7, 0.1), wood)
	BoxKit.add(_stall, Vector3(-0.95, 0.0, 0.3), Vector3(0.1, 0.7, 0.1), wood)
	BoxKit.add(_stall, Vector3(0.85, 0.0, 0.3), Vector3(0.1, 0.7, 0.1), wood)
	BoxKit.add(_stall, Vector3(-0.6, 0.78, -0.3), Vector3(0.5, 0.35, 0.5), Color("#7d7d85"))
	BoxKit.add(_stall, Vector3(0.1, 0.78, -0.2), Vector3(0.6, 0.25, 0.4), Color("#4a6f9a"))
	for child in _stall.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visibility_range_end = 80.0
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _strike_stall() -> void:
	if _stall != null:
		_stall.queue_free()
		_stall = null


func snapshot() -> Dictionary:
	var lv := {}
	for id: String in live:
		if id != "wolves":
			lv[id] = live[id]
	return {"last_fired": last_fired, "pending": pending, "live": lv}


func restore(d: Dictionary) -> void:
	last_fired = {}
	for k: Variant in d.get("last_fired", {}):
		last_fired[str(k)] = int(d["last_fired"][k])
	pending = d.get("pending", {})
	live = {}
	for k2: Variant in d.get("live", {}):
		live[str(k2)] = d["live"][k2]
	if live.has("merchant"):
		_pitch_stall()
