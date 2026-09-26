extends Node
## Sickness, healers, and the king's own dinner.
##
## People fall ill for reasons the town can see — hunger, a winter with no
## roof, too many to a bed — and a plague when the events system sends one.
## An illness is a name and a rate at which it eats a Worker's health; left
## alone it kills a citizen and puts a hired worker in bed for days. Herbs
## from the foraging system cut it short, in the hands of whoever the king
## has named healer. The player eats too: a meal a day keeps their health
## climbing back after a fight, and a night at the inn is the whole of it at
## once for ten coins.

const ILLS := {
	"fever": {"drain": 12.0, "days": 5, "line": "burning up"},
	"cough": {"drain": 6.0, "days": 6, "line": "coughing fit to split"},
	"flux": {"drain": 15.0, "days": 4, "line": "grey and weak"},
}
const HERBS_PER_TREATMENT := 2
const BED_DAYS := 3
const MEAL_FOOD := 5
const MEAL_HEAL := 30.0
const INN_COINS := 10
const REGEN_PER_MIN := 1.0
const HUNGRY_AFTER_DAYS := 2

var realm: Realm
var sick: Dictionary = {}        ## worker_id -> {illness, since_day, severity}
var bedridden: Dictionary = {}   ## worker_id -> day they get up
var healer_id := ""
var fed_day := 0                 ## the last day the player ate
var _regen_t := 0.0
var _rng := RandomNumberGenerator.new()
var _jobs: Array[Dictionary] = []   ## {worker_id, patients: Array[String], done_at}


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	fed_day = realm.clock.day if realm.clock != null else 0


# ------------------------------------------------------------------- public

func infect(w: Worker, illness: String) -> void:
	if w == null or not ILLS.has(illness) or sick.has(w.memory.worker_id):
		return
	sick[w.memory.worker_id] = {"illness": illness, "since_day": realm.clock.day, "severity": 1.0}
	w.speak("I am %s." % str(ILLS[illness]["line"]))
	realm.note("health", "%s came down with %s." % [w.display_name(), illness])


## The events system's plague: n people at once.
func outbreak(kind: String, n: int) -> int:
	var pool: Array[Worker] = []
	for w: Worker in realm.crew.workers:
		if is_instance_valid(w) and not sick.has(w.memory.worker_id):
			pool.append(w)
	pool.shuffle()
	var did := 0
	for w2: Worker in pool.slice(0, n):
		infect(w2, kind if ILLS.has(kind) else "flux")
		did += 1
	if did > 0:
		realm.say("%s is going through the town. %d down with it." % [kind.capitalize(), did])
	return did


func is_sick(w: Worker) -> bool:
	return w != null and sick.has(w.memory.worker_id)


func is_bedridden(w: Worker) -> bool:
	return w != null and bedridden.has(w.memory.worker_id)


func sick_workers() -> Array[Worker]:
	var out: Array[Worker] = []
	for wid: String in sick:
		var w: Worker = realm.crew.get_worker(wid)
		if w != null and is_instance_valid(w):
			out.append(w)
	return out


func healer() -> Worker:
	if healer_id != "":
		var w: Worker = realm.crew.get_worker(healer_id)
		if w != null:
			return w
	for w2: Worker in realm.crew.hired():
		if w2.role != null and w2.role.id == "cook":
			return w2
	return null


func treat(w: Worker) -> bool:
	if not is_sick(w):
		return false
	var herbs := int(realm.town.stock.get("herb", 0))
	if herbs < HERBS_PER_TREATMENT:
		return false
	realm.town.stock["herb"] = herbs - HERBS_PER_TREATMENT
	sick.erase(w.memory.worker_id)
	bedridden.erase(w.memory.worker_id)
	w.health = maxf(w.health, 60.0)
	realm.note("health", "%s was treated with herbs and is up again." % w.display_name())
	return true


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	# Who falls ill tonight.
	var pop := realm.population
	var chance := 0.01 + 0.03 * pop.hungry()
	if pop.beds() < pop.count():
		chance += 0.02
	var weather: Node = realm.system("Weather")
	var cold := weather != null and weather.has_method("temperature") and float(weather.call("temperature")) < 4.0
	for w: Worker in realm.crew.workers:
		if not is_instance_valid(w) or sick.has(w.memory.worker_id):
			continue
		var c := pop.for_worker(w)
		var roll := chance
		if cold and c != null and c.home_id < 0:
			roll += 0.08
		if c != null and float(c.needs["fed"]) < 0.4:
			roll += 0.04
		if _rng.randf() < clampf(roll, 0.0, 0.4):
			var kinds := ILLS.keys()
			infect(w, kinds[_rng.randi() % kinds.size()])
	# The sick worsen, recover, or die.
	for wid: String in sick.keys():
		var w2: Worker = realm.crew.get_worker(wid)
		if w2 == null or not is_instance_valid(w2):
			sick.erase(wid)
			continue
		var rec: Dictionary = sick[wid]
		var spec: Dictionary = ILLS[str(rec["illness"])]
		var days := day - int(rec["since_day"])
		if days >= int(spec["days"]):
			sick.erase(wid)
			bedridden.erase(wid)
			w2.speak("On my feet again.")
			realm.note("health", "%s got over the %s." % [w2.display_name(), rec["illness"]])
			continue
		w2.health -= float(spec["drain"]) * float(rec["severity"])
		if w2.health <= 0.0:
			var c2 := pop.for_worker(w2)
			if c2 != null and not w2.hired:
				sick.erase(wid)
				pop.kill(c2, "of the %s" % str(rec["illness"]))
			else:
				w2.health = 10.0
				if not bedridden.has(wid):
					bedridden[wid] = day + BED_DAYS
					w2.speak("I cannot stand. Three days in bed, they say.")
					realm.note("health", "%s took to bed with the %s." % [w2.display_name(), rec["illness"]])
	for wid2: String in bedridden.keys():
		if day >= int(bedridden[wid2]):
			bedridden.erase(wid2)
	# The player's stomach.
	if day - fed_day > HUNGRY_AFTER_DAYS and realm.warfare != null:
		realm.warfare.player_health = maxf(realm.warfare.player_health - 5.0, 10.0)


func on_hour(_hour: float, _day: int) -> void:
	var now := realm.clock.day * 24.0 + realm.clock.hour
	for job: Dictionary in _jobs.duplicate():
		if now < float(job["done_at"]):
			continue
		_jobs.erase(job)
		var h: Worker = realm.crew.get_worker(str(job["worker_id"]))
		var cured := 0
		var short := false
		for pid: String in job["patients"]:
			var p: Worker = realm.crew.get_worker(pid)
			if p == null:
				continue
			if treat(p):
				cured += 1
			elif is_sick(p):
				short = true
		if h != null and is_instance_valid(h):
			if not h.job_errand.is_empty():
				h.drop_everything()
			if cured > 0:
				h.speak("%d treated and mending." % cured + (" Out of herbs for the rest." if short else ""))
			elif short:
				h.speak("No herbs left to treat anyone with.")
			else:
				h.speak("Nobody needed me after all.")


func tick(delta: float) -> void:
	if realm.warfare == null:
		return
	_regen_t += delta
	if _regen_t < 60.0:
		return
	_regen_t = 0.0
	if realm.clock.day - fed_day <= 1 and realm.warfare.player_health < 100.0:
		realm.warfare.player_health = minf(realm.warfare.player_health + REGEN_PER_MIN, 100.0)


# ------------------------------------------------------------------ talking

## A worker in bed takes no orders at all. The dispatcher asks before it
## runs anything; this is the one line that can stop a whole plan.
func blocks(worker: Worker) -> String:
	if is_bedridden(worker):
		return "I cannot get up. Ask me in a day or two."
	return ""


func verbs() -> Dictionary:
	return {
		"eat": {
			"says": "a meal for your employer from the larder",
			"instant": true,
		},
		"lodge": {
			"says": "put your employer up at the inn till morning",
			"instant": true,
		},
		"name_healer": {
			"says": "make a named person the town's healer",
			"required": ["who"],
			"instant": true,
		},
		"treat": {
			"says": "go round the sick with herbs — everyone, or one named person",
			"optional": ["who"],
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"eat":
			var food := int(realm.town.stock.get("food", 0))
			if food < MEAL_FOOD:
				return "The larder has %d food; not enough for a meal." % food
			realm.town.stock["food"] = food - MEAL_FOOD
			fed_day = realm.clock.day
			if realm.warfare != null:
				realm.warfare.player_health = minf(realm.warfare.player_health + MEAL_HEAL, 100.0)
			worker.speak("Bread and something hot. You look better for it.")
			return "done"
		"lodge":
			var inn := realm.building("inn")
			if inn.is_empty():
				inn = realm.building("tavern")
			if inn.is_empty():
				return "There is no inn or tavern to put you up."
			if realm.town.coins < INN_COINS:
				return "A bed is %d coins and the purse is short." % INN_COINS
			realm.town.coins -= INN_COINS
			if realm.player != null and realm.player.has_method("teleport"):
				var door := realm.door_of(inn)
				realm.player.teleport(door + Vector3(0, 0.4, 0), realm.player.yaw)
			var skipped := realm.clock.skip_to(GameClock.DAY_START)
			if realm.warfare != null:
				realm.warfare.player_health = 100.0
			fed_day = realm.clock.day
			worker.speak("Morning. You slept %d hours at the %s." % [int(skipped), str(inn["archetype"])])
			realm.note("health", "The king slept at the %s." % str(inn["archetype"]))
			return "done"
		"name_healer":
			var who := str(step.get("who", "")).strip_edges().to_lower()
			for w: Worker in realm.crew.workers:
				if w.display_name().to_lower() == who:
					healer_id = w.memory.worker_id
					worker.speak("%s is the healer now." % w.display_name())
					realm.note("health", "%s was named healer." % w.display_name())
					return "done"
			return "There is nobody here called %s." % who.capitalize()
		"treat":
			var patients: Array[String] = []
			var who2 := str(step.get("who", "")).strip_edges().to_lower()
			for s2: Worker in sick_workers():
				if who2 == "" or s2.display_name().to_lower() == who2:
					patients.append(s2.memory.worker_id)
			if patients.is_empty():
				worker.speak("Nobody is sick." if who2 == "" else "%s is not sick." % who2.capitalize())
				return "done"
			if int(realm.town.stock.get("herb", 0)) < HERBS_PER_TREATMENT:
				return "No herbs to treat anyone with. Send someone to gather some."
			var h := healer()
			if h == null or h.busy():
				h = worker
			if h.busy():
				return "When I am done here."
			var legs: Array = []
			for pid: String in patients:
				var p: Worker = realm.crew.get_worker(pid)
				if p != null:
					legs.append(p.global_position)
			var hours := 0.5 * patients.size()
			h.take_errand_job("wait", legs[0] if not legs.is_empty() else h.global_position, hours,
				"Going round the sick with the herbs.", {"where": "the sick", "doing": "plan"})
			_jobs.append({"worker_id": h.memory.worker_id, "patients": patients,
				"done_at": realm.clock.day * 24.0 + realm.clock.hour + hours})
			return "started" if h == worker else "done"
	return "failed"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["who is sick", "who is ill", "anyone sick", "anyone ill", "is anyone unwell",
			"how are the sick", "any sickness", "anybody sick"]):
		var ws := sick_workers()
		if ws.is_empty():
			return "Nobody is sick."
		var bits: Array[String] = []
		for w: Worker in ws:
			var rec: Dictionary = sick[w.memory.worker_id]
			bits.append("%s with %s%s" % [w.display_name(), rec["illness"], " (in bed)" if bedridden.has(w.memory.worker_id) else ""])
		return "%d sick: %s. We have %d herbs." % [ws.size(), ", ".join(bits), int(realm.town.stock.get("herb", 0))]
	if Realm.has_phrase(t, ["how am i", "my health", "how is my health", "am i hurt", "how do i look"]):
		var hp := int(realm.warfare.player_health) if realm.warfare != null else 100
		var hungry := realm.clock.day - fed_day > HUNGRY_AFTER_DAYS
		return "You are at %d of 100%s." % [hp, ", and you have not eaten in days" if hungry else ""]
	if Realm.has_phrase(t, ["how is "]) and not Realm.has_phrase(t, ["how is the", "how is everyone", "how is morale"]):
		for w2: Worker in realm.crew.workers:
			if is_instance_valid(w2) and Realm.has_word(t, [w2.display_name().to_lower()]):
				if sick.has(w2.memory.worker_id):
					return "%s is down with %s — health %d." % [w2.display_name(), sick[w2.memory.worker_id]["illness"], int(w2.health)]
				return "%s is well enough; health %d." % [w2.display_name(), int(w2.health)]
	if Realm.has_phrase(t, ["who is the healer", "do we have a healer", "any healer"]):
		var h := healer()
		return "%s is the healer." % h.display_name() if h != null else "No healer. Name one, or hire a cook."
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if not sick.is_empty():
		out.append("%d sick" % sick.size())
	if realm.clock.day - fed_day > HUNGRY_AFTER_DAYS:
		out.append("you are hungry")
	return out


func snapshot() -> Dictionary:
	return {"sick": sick, "bedridden": bedridden, "healer_id": healer_id, "fed_day": fed_day}


func restore(d: Dictionary) -> void:
	sick = {}
	for k: Variant in d.get("sick", {}):
		sick[str(k)] = d["sick"][k]
	bedridden = {}
	for k2: Variant in d.get("bedridden", {}):
		bedridden[str(k2)] = int(d["bedridden"][k2])
	healer_id = str(d.get("healer_id", ""))
	fed_day = int(d.get("fed_day", fed_day))
