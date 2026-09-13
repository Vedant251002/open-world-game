extends Node
## The settlements over the hill, and what they think of us.
##
## A kingdom with nobody next door is a garden. These are the neighbours:
## three or four named places a few days' walk away, each with a leader, a
## temper, something to sell and something to want. They are not simulated
## towns — they are records with a disposition that moves when we send
## gifts, envoys, insults or soldiers, and a treaty that says what that
## disposition has come to. A hostile one sends riders; a friendly one sends
## help when the riders come.
##
## Every dealing with them is a journey: a worker walks out of town in their
## direction, is gone for the days it takes, and comes back with an answer.

const KINDS := ["farming village", "mining town", "river port", "hill fort"]
const TREATIES := ["none", "trade", "peace", "alliance", "war", "vassal"]
const SYL_A := ["Har", "Wex", "Kel", "Ash", "Bran", "Tor", "Mer", "Cal", "Dun", "Fen", "Gor", "Ist"]
const SYL_B := ["row", "ley", "der", "ford", "wick", "by", "combe", "ton", "mere", "hithe", "stow", "dale"]
const LEADERS := ["Osric", "Maud", "Halvard", "Ygraine", "Tancred", "Berthe", "Aldous", "Sunniva"]
## How far out of town the road to a neighbour starts, in metres.
const EDGE_M := 32.0
const CARAVAN_UNITS := 200

var realm: Realm
var towns: Array[Dictionary] = []
var _missions: Array[Dictionary] = []   ## {worker_id, town, kind, return_day, coins, note}
var _rng := RandomNumberGenerator.new()
var _raid_from := ""                    ## who sent the riders now in the field


func setup(r: Realm) -> void:
	realm = r
	_rng.seed = hash("neighbours:%d" % (realm.village.seed_value if realm.village != null else 7))
	_generate()
	if realm.warfare != null:
		realm.warfare.raid_over.connect(_on_raid_over)
		realm.warfare.raid_began.connect(_on_raid_began)


func _generate() -> void:
	towns.clear()
	var n := 3 + (_rng.randi() % 2)
	var used := {}
	var kinds_pool := KINDS.duplicate()
	var goods := ["timber", "cobble", "plank", "brick", "food", "sandstone", "glass", "cloth", "tools", "meals"]
	for i in n:
		var name := ""
		while name == "" or used.has(name):
			name = SYL_A[_rng.randi() % SYL_A.size()] + SYL_B[_rng.randi() % SYL_B.size()]
		used[name] = true
		var angle := (TAU / n) * i + _rng.randf_range(-0.4, 0.4)
		var kind: String = kinds_pool[_rng.randi() % kinds_pool.size()]
		var sells: Array[String] = []
		var buys: Array[String] = []
		match kind:
			"farming village": sells = ["food", "cloth"]; buys = ["tools", "plank"]
			"mining town": sells = ["cobble", "sandstone", "tools"]; buys = ["food", "timber"]
			"river port": sells = ["glass", "brick", "cloth"]; buys = ["food", "meals"]
			"hill fort": sells = ["tools", "timber"]; buys = ["food", "brick"]
		towns.append({
			"name": name, "kind": kind,
			"bearing": Vector2(cos(angle), sin(angle)),
			"distance_days": 2 + (_rng.randi() % 5),
			"strength": 10 + (_rng.randi() % 51),
			"disposition": _rng.randf_range(-0.4, 0.5),
			"treaty": "none",
			"sells": sells, "buys": buys,
			"leader": LEADERS[(_rng.randi() + i) % LEADERS.size()],
			"tribute": 0,
		})
	if goods.is_empty():
		return


# ------------------------------------------------------------------- public

func list() -> Array[Dictionary]:
	return towns


func by_name(name: String) -> Dictionary:
	var t := name.to_lower().strip_edges()
	for town: Dictionary in towns:
		if str(town["name"]).to_lower() == t:
			return town
	return {}


func hostile() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for town: Dictionary in towns:
		if str(town["treaty"]) == "war" or float(town["disposition"]) < -0.5:
			out.append(town)
	return out


func strongest_enemy() -> Dictionary:
	var best: Dictionary = {}
	for town: Dictionary in hostile():
		if best.is_empty() or int(town["strength"]) > int(best["strength"]):
			best = town
	return best


func set_treaty(name: String, state: String) -> void:
	var town := by_name(name)
	if town.is_empty() or state not in TREATIES:
		return
	town["treaty"] = state
	realm.note("neighbours", "%s and we are now at %s." % [town["name"], state if state != "none" else "no terms"])


func adjust(name: String, delta: float) -> void:
	var town := by_name(name)
	if not town.is_empty():
		town["disposition"] = clampf(float(town["disposition"]) + delta, -1.0, 1.0)


func mood_word(town: Dictionary) -> String:
	var d := float(town["disposition"])
	if str(town["treaty"]) == "war":
		return "at war with us"
	if str(town["treaty"]) == "vassal":
		return "ours, and paying for it"
	if d > 0.6:
		return "warm to us"
	if d > 0.2:
		return "friendly enough"
	if d > -0.2:
		return "indifferent"
	if d > -0.6:
		return "cool towards us"
	return "hostile"


## Where the road to a neighbour leaves the town: a standable point out past
## the plots in its direction.
func edge_point(town: Dictionary) -> Vector3:
	var b: Vector2 = town["bearing"]
	var well := realm.village.well_pos
	for dist: float in [EDGE_M, EDGE_M * 0.75, EDGE_M * 0.5, 12.0]:
		var at: Vector3 = well + Vector3(b.x, 0.0, b.y) * dist
		var col := VoxelWorld.column_of(at)
		if realm.world.column_meshable(col.x, col.y):
			at.y = realm.world.ground_m(at.x, at.z)
			var v := VoxelWorld.to_voxel(at)
			if realm.world.get_voxel(Vector3i(v.x, v.y - 1, v.z)) != VoxelTypes.WATER:
				return at
	return well


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	for m: Dictionary in _missions.duplicate():
		if day >= int(m["return_day"]):
			_missions.erase(m)
			_return(m)
	for town: Dictionary in towns:
		# Tempers cool toward indifference; vassals pay.
		town["disposition"] = lerpf(float(town["disposition"]), 0.0, 0.02)
		if str(town["treaty"]) == "vassal" and day % 5 == 0:
			var due := 40 + int(town["strength"])
			realm.town.coins += due
			realm.note("tribute", "%s paid %d coins in tribute." % [town["name"], due])
		# Enemies send riders on their own account, when the field is clear.
		if str(town["treaty"]) == "war" and realm.warfare != null and not realm.warfare._raid_active \
				and _raid_from == "" and _rng.randf() < 0.3:
			var n := clampi(int(town["strength"]) / 8, 2, 9)
			_raid_from = str(town["name"])
			realm.say("Riders from %s!" % town["name"])
			realm.note("raid", "%s sent %d riders against us." % [town["name"], n])
			realm.warfare.raid(n)


func _on_raid_began(_count: int) -> void:
	# Allies turn out when the fighting starts.
	if realm.warfare == null:
		return
	for town: Dictionary in towns:
		if str(town["treaty"]) == "alliance" and _rng.randf() < 0.7:
			var n := 3 + (_rng.randi() % 4)
			var got := realm.warfare.recruit(n)
			realm.say("%s sent %d fighters to stand with us." % [town["name"], int(got.get("count", n))])
			realm.note("allies", "%s sent help against the raid." % town["name"])
			break


func _on_raid_over(won: bool) -> void:
	if _raid_from == "":
		return
	var town := by_name(_raid_from)
	_raid_from = ""
	if town.is_empty():
		return
	if won:
		town["strength"] = maxi(int(town["strength"]) - 8, 5)
		town["disposition"] = clampf(float(town["disposition"]) + 0.15, -1.0, 1.0)
		realm.note("raid", "%s's riders were beaten off. They will think twice." % town["name"])
	else:
		town["disposition"] = clampf(float(town["disposition"]) - 0.1, -1.0, 1.0)


# ---------------------------------------------------------------- missions

func _send(worker: Worker, town: Dictionary, kind: String, coins: int = 0) -> bool:
	if worker.busy():
		worker.speak("I am in the middle of something; send me when I am done.")
		return true
	if coins > 0:
		if realm.town.coins < coins:
			worker.speak("We have not got %d coins to send." % coins)
			return true
		realm.town.coins -= coins
	var days := int(town["distance_days"]) * 2
	var edge := edge_point(town)
	var verb: String = {"envoy": "to talk", "peace": "to sue for peace", "alliance": "to ask for an alliance",
		"war": "with a declaration of war", "gift": "with a gift of %d coins" % coins,
		"demand": "to demand tribute", "trade": "with a caravan"}.get(kind, "")
	var line := "Off to %s %s. %d days there and back." % [town["name"], verb, days]
	worker.take_errand_job("wait", edge, float(days) * 24.0, line,
		{"where": str(town["name"]), "doing": "survey"})
	_missions.append({"worker_id": worker.memory.worker_id, "town": str(town["name"]),
		"kind": kind, "return_day": realm.clock.day + days, "coins": coins})
	realm.note("neighbours", "%s left for %s %s." % [worker.display_name(), town["name"], verb])
	return true


func _return(m: Dictionary) -> void:
	var town := by_name(str(m["town"]))
	var w: Worker = realm.crew.get_worker(str(m["worker_id"]))
	if town.is_empty():
		return
	if w != null and not w.job_errand.is_empty():
		w.drop_everything()
	if w != null:
		# A stroll back to the well, interruptible like any idle wander.
		w.walk_to(realm.village.well_pos, "idle")
	var d := float(town["disposition"])
	var line := ""
	match str(m["kind"]):
		"envoy":
			town["disposition"] = clampf(d + 0.1, -1.0, 1.0)
			line = "%s of %s received me. They are %s." % [town["leader"], town["name"], mood_word(town)]
		"gift":
			town["disposition"] = clampf(d + 0.15 + float(m["coins"]) / 1000.0, -1.0, 1.0)
			line = "%s took the gift well. %s is %s now." % [town["leader"], town["name"], mood_word(town)]
		"peace":
			if d > -0.3 or str(town["treaty"]) != "war":
				town["treaty"] = "peace"
				town["disposition"] = clampf(d + 0.2, -1.0, 1.0)
				line = "Peace with %s. %s put their seal to it." % [town["name"], town["leader"]]
			else:
				line = "%s would not hear of peace. Not yet." % town["leader"]
		"alliance":
			if d > 0.4:
				town["treaty"] = "alliance"
				line = "%s will stand with us. An alliance with %s." % [town["leader"], town["name"]]
			else:
				line = "%s wants to see more of us before an alliance. Gifts and trade, they said." % town["leader"]
		"war":
			town["treaty"] = "war"
			town["disposition"] = clampf(d - 0.5, -1.0, 1.0)
			line = "War with %s. %s said they would be ready." % [town["name"], town["leader"]]
		"demand":
			if int(town["strength"]) < 25 or d > 0.5:
				var paid := 60 + int(town["strength"]) * 2
				realm.town.coins += paid
				town["disposition"] = clampf(d - 0.2, -1.0, 1.0)
				line = "%s paid %d coins rather than argue." % [town["name"], paid]
			else:
				town["disposition"] = clampf(d - 0.3, -1.0, 1.0)
				line = "%s laughed at the demand. %s is not friendlier for it." % [town["leader"], town["name"]]
		"trade":
			line = _settle_caravan(town)
	if w != null:
		w.speak(line)
	else:
		realm.say(line)
	realm.note("neighbours", line)


## We sell what they pay dear for and buy what they sell cheap, a cart-load
## either way, at a spread that rewards knowing who wants what.
func _settle_caravan(town: Dictionary) -> String:
	var t := realm.town
	var made := 0
	var sold := ""
	for k: String in town["buys"]:
		var have := int(t.stock.get(k, 0))
		var n := mini(have - 50, CARAVAN_UNITS)
		if n > 0:
			var each := int(ceil(float(Town.PRICE.get(k, Town.DEFAULT_PRICE)) * 1.6))
			t.stock[k] = have - n
			t.coins += n * each
			made += n * each
			sold = "%d %s" % [n, k]
			break
	var bought := ""
	for k: String in town["sells"]:
		var each := maxi(int(float(Town.PRICE.get(k, Town.DEFAULT_PRICE)) * 0.8), 1)
		var n := mini(CARAVAN_UNITS / 2, t.coins / each)
		if n > 0:
			t.coins -= n * each
			t.stock[k] = int(t.stock.get(k, 0)) + n
			bought = "%d %s" % [n, k]
			break
	town["disposition"] = clampf(float(town["disposition"]) + 0.1, -1.0, 1.0)
	if str(town["treaty"]) == "none":
		town["treaty"] = "trade"
	var parts: Array[String] = []
	if sold != "":
		parts.append("sold %s for %d coins" % [sold, made])
	if bought != "":
		parts.append("bought %s" % bought)
	if parts.is_empty():
		return "The caravan came back from %s with nothing done; we had nothing they wanted." % town["name"]
	return "Back from %s: %s." % [town["name"], " and ".join(parts)]


# ------------------------------------------------------------------ talking

func _town_in(t: String) -> Dictionary:
	for town: Dictionary in towns:
		if t.find(str(town["name"]).to_lower()) >= 0:
			return town
	return {}


func try_order(worker: Worker, text: String) -> bool:
	var t := text.to_lower()
	var town := _town_in(t)
	if Realm.has_phrase(t, ["build", "put up", "construct", "erect", "lay a road", "road"]):
		return false
	if town.is_empty():
		if Realm.has_phrase(t, ["send an envoy", "send envoy", "make peace", "declare war",
				"demand tribute", "ask for an alliance"]):
			worker.speak("To whom? Our neighbours are %s." % _names())
			return true
		return false
	if Realm.has_phrase(t, ["declare war", "go to war", "war on", "war with"]):
		return _send(worker, town, "war")
	if Realm.has_phrase(t, ["make peace", "sue for peace", "peace with", "offer peace", "end the war"]):
		return _send(worker, town, "peace")
	if Realm.has_word(t, ["alliance", "ally", "allies", "allied"]):
		return _send(worker, town, "alliance")
	if Realm.has_word(t, ["gift", "present", "tribute"]) and Realm.has_word(t, ["send", "give", "offer"]):
		return _send(worker, town, "gift", Realm.count_in(t, 100))
	if Realm.has_word(t, ["demand", "exact"]) or Realm.has_phrase(t, ["tribute from"]):
		return _send(worker, town, "demand")
	if Realm.has_word(t, ["trade", "caravan", "sell", "buy"]):
		return _send(worker, town, "trade")
	if Realm.has_word(t, ["envoy", "emissary", "messenger", "embassy", "talk", "visit", "greet"]):
		return _send(worker, town, "envoy")
	return false


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	var town := _town_in(t)
	if Realm.has_phrase(t, ["who are our neighbours", "who are the neighbours", "what towns",
			"other towns", "who lives nearby", "who is nearby", "our neighbours", "neighbouring"]):
		var bits: Array[String] = []
		for tw: Dictionary in towns:
			bits.append("%s, a %s %s %d days off, %s" % [tw["name"], tw["kind"],
				_compass(tw["bearing"]), int(tw["distance_days"]), mood_word(tw)])
		return "; ".join(bits).capitalize() + "."
	if Realm.has_phrase(t, ["think of us", "feel about us", "how are relations", "relations with"]):
		if not town.is_empty():
			return "%s is %s." % [town["name"], mood_word(town)]
		var bits2: Array[String] = []
		for tw: Dictionary in towns:
			bits2.append("%s %s" % [tw["name"], mood_word(tw)])
		return ", ".join(bits2).capitalize() + "."
	if Realm.has_phrase(t, ["at war", "any wars", "enemies", "who hates us"]):
		var foes: Array[String] = []
		for tw: Dictionary in hostile():
			foes.append(str(tw["name"]))
		return "We are at peace with everyone." if foes.is_empty() else "%s: %s." % [
			"At war with" if foes.size() == 1 else "Trouble with", " and ".join(foes)]
	if Realm.has_phrase(t, ["envoy", "when will", "back from"]) and not _missions.is_empty():
		var m: Dictionary = _missions[0]
		var w: Worker = realm.crew.get_worker(str(m["worker_id"]))
		return "%s is away at %s, back on day %d." % [w.display_name() if w != null else "The envoy",
			m["town"], int(m["return_day"])]
	if town.is_empty():
		return ""
	if Realm.has_phrase(t, ["where is", "how far", "which way"]):
		return "%s lies %s, %d days' walk." % [town["name"], _compass(town["bearing"]), int(town["distance_days"])]
	if Realm.has_phrase(t, ["sell", "buy", "want", "trade"]):
		return "%s sells %s and pays well for %s." % [town["name"],
			" and ".join(town["sells"]), " and ".join(town["buys"])]
	if Realm.has_phrase(t, ["tell me about", "what is", "who rules", "who leads", "how strong"]):
		return "%s is a %s %s of here, %d days' walk, under %s. Strength about %d; %s. Sells %s, wants %s." % [
			town["name"], town["kind"], _compass(town["bearing"]), int(town["distance_days"]),
			town["leader"], int(town["strength"]), mood_word(town),
			" and ".join(town["sells"]), " and ".join(town["buys"])]
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in _missions:
		out.append("%s to %s · back day %d" % [str(m["kind"]), m["town"], int(m["return_day"])])
		break
	for tw: Dictionary in towns:
		if str(tw["treaty"]) == "war":
			out.append("war with %s" % tw["name"])
			break
	return out


func _names() -> String:
	var names: Array[String] = []
	for tw: Dictionary in towns:
		names.append(str(tw["name"]))
	return " and ".join(names)


static func _compass(b: Vector2) -> String:
	var a := fmod(atan2(b.x, -b.y) + TAU, TAU)
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return dirs[int(round(a / (TAU / 8))) % 8]


func snapshot() -> Dictionary:
	var out: Array = []
	for tw: Dictionary in towns:
		var d := tw.duplicate()
		d["bearing"] = [tw["bearing"].x, tw["bearing"].y]
		out.append(d)
	return {"towns": out, "missions": _missions.duplicate(true), "raid_from": _raid_from}


func restore(d: Dictionary) -> void:
	if not d.has("towns"):
		return
	towns.clear()
	for tw: Variant in d["towns"]:
		if tw is Dictionary:
			var rec: Dictionary = (tw as Dictionary).duplicate()
			var b: Array = rec.get("bearing", [1.0, 0.0])
			rec["bearing"] = Vector2(float(b[0]), float(b[1]))
			var sells: Array[String] = []
			for s: Variant in rec.get("sells", []):
				sells.append(str(s))
			var buys: Array[String] = []
			for s2: Variant in rec.get("buys", []):
				buys.append(str(s2))
			rec["sells"] = sells
			rec["buys"] = buys
			towns.append(rec)
	_missions.clear()
	for m: Variant in d.get("missions", []):
		if m is Dictionary:
			_missions.append(m)
	_raid_from = str(d.get("raid_from", ""))
