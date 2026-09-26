extends Node
## The shrine, the feast days, and how the town feels about itself.
##
## Morale is a number in Population; this is where it gets spent and
## bought. A feast costs real food and coin, and tomorrow the citizens walk
## to the plaza and stand about being glad of it, which is the one day a
## town looks like a place people chose. A shrine makes the ordinary days a
## little steadier and takes a coin a week in offerings; pilgrims come to it
## and buy things. The seasonal feast days are suggested, never taken —
## spending the larder is the king's decision, every time.

const FEAST_DAYS := [12, 24, 36, 48]      ## of the year
const FEAST_FOOD_EACH := 2
const FEAST_COINS_BASE := 20
const FEAST_COINS_EACH := 5
const OFFERING_EACH := 3                  ## coins per citizen per week
const PILGRIMS_EVERY := 8
const GATHER_MAX := 12

var realm: Realm
var feast_day := -1          ## the day everyone gathers
var feast_reason := ""
var feasts_held := 0
var _gathered := false
var _rng := RandomNumberGenerator.new()


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()


# ------------------------------------------------------------------- public

func has_shrine() -> bool:
	return not realm.building("shrine").is_empty()


## Book a feast for tomorrow, paying today. Returns "" when it is on, or the
## reason it cannot be.
func feast(reason: String) -> String:
	if feast_day >= realm.clock.day:
		return "A feast is already set for day %d." % feast_day
	var n := maxi(realm.population.count(), 1)
	var food := n * FEAST_FOOD_EACH
	var coins := FEAST_COINS_BASE + n * FEAST_COINS_EACH
	var have_food := int(realm.town.stock.get("food", 0))
	if have_food < food:
		return "A feast for %d needs %d food; the larder holds %d." % [n, food, have_food]
	if realm.town.coins < coins:
		return "A feast for %d costs %d coins; the purse holds %d." % [n, coins, realm.town.coins]
	realm.town.stock["food"] = have_food - food
	realm.town.coins -= coins
	feast_day = realm.clock.day + 1
	feast_reason = reason
	_gathered = false
	realm.note("feast", "A feast was called for %s: %d food and %d coins laid out." % [reason, food, coins])
	return ""


func next_feast_day() -> int:
	var doy := realm.clock.day % 48
	for d: int in FEAST_DAYS:
		if d > doy:
			return realm.clock.day + (d - doy)
	return realm.clock.day + (48 - doy) + FEAST_DAYS[0]


# ------------------------------------------------------------------- the day

func on_day(day: int) -> void:
	var pop := realm.population
	if day == feast_day:
		feasts_held += 1
		for c: Population.Citizen in pop.alive():
			c.mood = clampf(c.mood + 0.2, 0.0, 1.0)
		_gather()
		realm.say("Feast day, for %s. The town is in the plaza." % feast_reason)
		realm.note("feast", "The town feasted for %s." % feast_reason)
	elif day == feast_day + 1:
		_disperse()
	if has_shrine():
		for c2: Population.Citizen in pop.alive():
			c2.mood = clampf(c2.mood + 0.005, 0.0, 1.0)
			c2.needs["safe"] = minf(float(c2.needs["safe"]) + 0.05, 1.0)
		if day % 7 == 0:
			var offered := pop.count() * OFFERING_EACH
			realm.town.coins += offered
			realm.note("faith", "The shrine took %d coins in offerings." % offered)
		if day % PILGRIMS_EVERY == 0:
			var n := 1 + (_rng.randi() % 3)
			var spent := n * (15 + (_rng.randi() % 20))
			realm.town.coins += spent
			realm.say("%d pilgrim%s came to the shrine and spent %d coins in town." % [n, "" if n == 1 else "s", spent])
			realm.note("faith", "%d pilgrims visited the shrine." % n)
	# The calendar's feasts are suggested the day before.
	var doy := day % 48
	for d: int in FEAST_DAYS:
		if d - doy == 1 and feast_day != day + 1:
			realm.say("%s feast tomorrow, if we can afford it. Say the word." % _season_feast(d))


func _season_feast(d: int) -> String:
	match d:
		12: return "Spring"
		24: return "Midsummer"
		36: return "Harvest"
	return "Midwinter"


## The nearest dozen citizens stroll to the plaza and stay the day.
func _gather() -> void:
	if realm.crew == null:
		return
	var well := realm.village.well_pos
	var walkers: Array[Worker] = []
	for c: Population.Citizen in realm.population.alive():
		var w := c.worker(realm.crew)
		if w != null and not w.busy():
			walkers.append(w)
	walkers.sort_custom(func(a: Worker, b: Worker) -> bool:
		return a.global_position.distance_to(well) < b.global_position.distance_to(well))
	for i in mini(GATHER_MAX, walkers.size()):
		var ang := TAU * float(i) / float(GATHER_MAX)
		var spot := well + Vector3(cos(ang), 0.0, sin(ang)) * (4.0 + float(i % 3))
		walkers[i].take_errand_job("wait", spot, 10.0, "", {"where": "the feast", "doing": "survey"})
	_gathered = true


func _disperse() -> void:
	if not _gathered:
		return
	_gathered = false
	for c: Population.Citizen in realm.population.alive():
		var w := c.worker(realm.crew)
		if w != null and not w.job_errand.is_empty() and str(w.job_errand.get("extra", {}).get("where", "")) == "the feast":
			w.drop_everything()


# ------------------------------------------------------------------ talking

func verbs() -> Dictionary:
	return {
		"feast": {
			"says": "call a feast for tomorrow, and say what for",
			"optional": ["reason"],
			"types": {"reason": ["the harvest", "the victory", "the season", "the king's pleasure"]},
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	if str(step.get("do", "")) != "feast":
		return "failed"
	var reason := str(step.get("reason", "the king's pleasure"))
	var why := feast(reason)
	if why != "":
		return why
	worker.speak("A feast tomorrow, for %s. The larder is open." % reason)
	return "done"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["next feast", "when is the feast", "when do we feast", "feast day", "is there a feast"]):
		if feast_day >= realm.clock.day:
			return "A feast for %s on day %d." % [feast_reason, feast_day]
		return "Nothing set. The calendar's next feast day is day %d; say the word for one sooner." % next_feast_day()
	if Realm.has_phrase(t, ["how is morale", "morale", "spirits", "how are spirits"]):
		var out := "People are %s." % realm.population.mood_word()
		if has_shrine():
			out += " The shrine steadies them."
		if feasts_held > 0:
			out += " %d feast%s held so far." % [feasts_held, "" if feasts_held == 1 else "s"]
		return out
	if Realm.has_phrase(t, ["is there a shrine", "do we have a shrine", "a church", "a chapel", "the shrine"]):
		return "There is a shrine; pilgrims come every %d days." % PILGRIMS_EVERY if has_shrine() else "No shrine yet. One would steady the town and bring pilgrims."
	return ""


func hud_lines() -> Array[String]:
	if feast_day == realm.clock.day:
		return ["feast today"]
	return []


func snapshot() -> Dictionary:
	return {"feast_day": feast_day, "feast_reason": feast_reason, "feasts_held": feasts_held}


func restore(d: Dictionary) -> void:
	feast_day = int(d.get("feast_day", -1))
	feast_reason = str(d.get("feast_reason", ""))
	feasts_held = int(d.get("feasts_held", 0))
