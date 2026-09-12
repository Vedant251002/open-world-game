extends Node
class_name Population
## The people of the kingdom: who they are, where they sleep, what they need,
## and how they feel about it.
##
## The bodies are the crew's citizens — Workers with roles, raised by Crew —
## and this does not duplicate them. It keeps a Citizen record beside each
## one: a home, needs, a mood, an age, a family. Houses are what let more
## people arrive: a cottage has three beds, and beds with nobody in them fill
## up, one newcomer a day, until they are full. That is the whole engine of
## growth, and every other system reads from here.
##
## Needs are simple and few — fed, warm, safe — because they are meant to be
## read off a face, not managed off a chart. A person who has not eaten is
## unhappy; a town of unhappy people is a town about to become somebody's
## problem, which is the law's business and not this file's.

signal moved_in(c: Citizen)
signal died(c: Citizen)

## Beds per building. Anything not listed houses nobody.
const BEDS := {
	"hut": 2, "cottage": 3, "apartment": 8, "tower_block": 16,
	"tavern": 2, "inn": 4,
}
const FOOD_PER_DAY := 1
const MAX_AGE := 78

var realm: Realm
var people: Array[Citizen] = []
var _next_id := 1
var _seed := 0


class Citizen extends RefCounted:
	var id := 0
	var name := ""
	var worker_id := ""            ## Crew.by_id key, "" for someone with no body
	var home_id := -1              ## Town building id, -1 for homeless
	var workplace_id := -1         ## Town building id where they work
	var job := ""                  ## a RoleBook role id, or ""
	var age := 25
	var alive := true
	var spouse_id := -1
	var parent_ids: Array[int] = []
	var needs := {"fed": 1.0, "warm": 1.0, "safe": 1.0}
	var mood := 0.7
	var skills := {}
	var arrived_day := 1

	func worker(crew: Crew) -> Worker:
		if worker_id == "" or crew == null:
			return null
		return crew.get_worker(worker_id)

	func describe() -> String:
		var bits: Array[String] = []
		bits.append("%s, %d" % [name, age])
		bits.append(job.replace("_", " ") if job != "" else "no trade")
		bits.append("housed" if home_id >= 0 else "sleeping rough")
		var feel := "content"
		if mood < 0.3:
			feel = "miserable"
		elif mood < 0.5:
			feel = "unhappy"
		elif mood > 0.85:
			feel = "happy"
		if float(needs["fed"]) < 0.4:
			feel += " and hungry"
		bits.append(feel)
		return ", ".join(bits)


func setup(r: Realm) -> void:
	realm = r
	_seed = hash(str(Time.get_unix_time_from_system()))
	_sync()
	if realm.crew != null:
		realm.crew.roster_changed.connect(_sync)
	set_process(false)


# ------------------------------------------------------------------ records

## Keeps one Citizen per crew citizen, adding records for newcomers.
func _sync() -> void:
	if realm.crew == null:
		return
	var seen := {}
	for c: Citizen in people:
		seen[c.worker_id] = c
	for w: Worker in realm.crew.citizens():
		var wid: String = w.memory.worker_id
		if seen.has(wid):
			continue
		var c := Citizen.new()
		c.id = _next_id
		_next_id += 1
		c.name = w.display_name()
		c.worker_id = wid
		c.age = 18 + (hash(wid) % 40)
		c.arrived_day = realm.clock.day if realm.clock != null else 1
		people.append(c)
	_assign_homes()


func alive() -> Array[Citizen]:
	var out: Array[Citizen] = []
	for c: Citizen in people:
		if c.alive:
			out.append(c)
	return out


func count() -> int:
	return alive().size()


func by_name(n: String) -> Citizen:
	var t := n.to_lower().strip_edges()
	for c: Citizen in people:
		if c.alive and c.name.to_lower() == t:
			return c
	return null


func for_worker(w: Worker) -> Citizen:
	if w == null:
		return null
	for c: Citizen in people:
		if c.worker_id == w.memory.worker_id:
			return c
	return null


func housed() -> int:
	var n := 0
	for c: Citizen in alive():
		if c.home_id >= 0:
			n += 1
	return n


func homeless() -> int:
	return count() - housed()


func mood_avg() -> float:
	var all := alive()
	if all.is_empty():
		return 0.7
	var total := 0.0
	for c: Citizen in all:
		total += c.mood
	return total / all.size()


func mood_word() -> String:
	var m := mood_avg()
	if m < 0.3:
		return "miserable"
	if m < 0.5:
		return "unhappy"
	if m < 0.7:
		return "getting by"
	if m < 0.85:
		return "content"
	return "happy"


func hungry() -> int:
	var n := 0
	for c: Citizen in alive():
		if float(c.needs["fed"]) < 0.4:
			n += 1
	return n


# -------------------------------------------------------------------- homes

## Beds in the town, and who is in them.
func beds() -> int:
	var n := 0
	for rec: Dictionary in realm.town.buildings:
		n += int(BEDS.get(str(rec["archetype"]), 0))
	return n


func _beds_in(rec: Dictionary) -> int:
	return int(BEDS.get(str(rec["archetype"]), 0))


func _occupants(building_id: int) -> int:
	var n := 0
	for c: Citizen in alive():
		if c.home_id == building_id:
			n += 1
	return n


## Everybody without a home takes the first free bed. Families stay together
## when they can.
func _assign_homes() -> void:
	for c: Citizen in alive():
		if c.home_id >= 0:
			continue
		# Beside a spouse first.
		if c.spouse_id >= 0:
			var sp := _by_id(c.spouse_id)
			if sp != null and sp.home_id >= 0:
				var home := _building_by_id(sp.home_id)
				if not home.is_empty() and _occupants(sp.home_id) < _beds_in(home):
					c.home_id = sp.home_id
					continue
		for rec: Dictionary in realm.town.buildings:
			var bid := int(rec["id"])
			if _beds_in(rec) > _occupants(bid):
				c.home_id = bid
				break


func _building_by_id(bid: int) -> Dictionary:
	for rec: Dictionary in realm.town.buildings:
		if int(rec["id"]) == bid:
			return rec
	return {}


func _by_id(cid: int) -> Citizen:
	for c: Citizen in people:
		if c.id == cid:
			return c
	return null


func home_of(c: Citizen) -> String:
	if c.home_id < 0:
		return "nowhere"
	var rec := _building_by_id(c.home_id)
	if rec.is_empty():
		return "nowhere"
	return "the %s on %s" % [str(rec["archetype"]).replace("_", " "), str(rec["street"])]


# -------------------------------------------------------------------- days

## Once a day: everybody eats, needs settle, moods move, someone new may
## arrive, and the old may not wake up.
func on_day(day: int) -> void:
	_sync()
	var all := alive()
	var food := realm.town.units_of("food")
	var short := 0
	for c: Citizen in all:
		# Fed: from the larder, first come first served.
		if food >= FOOD_PER_DAY:
			food -= FOOD_PER_DAY
			c.needs["fed"] = minf(float(c.needs["fed"]) + 0.5, 1.0)
		else:
			c.needs["fed"] = maxf(float(c.needs["fed"]) - 0.35, 0.0)
			short += 1
		# Warm: a roof, or not.
		c.needs["warm"] = minf(float(c.needs["warm"]) + 0.3, 1.0) if c.home_id >= 0 \
			else maxf(float(c.needs["warm"]) - 0.25, 0.0)
		# Safe: raiders about are frightening; soldiers about are reassuring.
		var safe := 0.8
		if realm.warfare != null:
			if not realm.warfare.raiders.is_empty():
				safe = 0.2
			elif not realm.warfare.soldiers.is_empty():
				safe = 1.0
		c.needs["safe"] = lerpf(float(c.needs["safe"]), safe, 0.5)
		# Mood follows the needs, slowly.
		var want := (float(c.needs["fed"]) * 0.5 + float(c.needs["warm"]) * 0.3
			+ float(c.needs["safe"]) * 0.2)
		c.mood = lerpf(c.mood, want, 0.35)
		# Age, and the end of it.
		c.age += 1 if day % 30 == 0 else 0
		if c.age >= MAX_AGE and randf() < 0.15:
			_die(c, "of old age")
	realm.town.stock["food"] = food
	if short > 0:
		realm.note("hunger", "%d %s went hungry." % [short, "person" if short == 1 else "people"])
		if short >= 3:
			realm.say("%d people went hungry today. The larder is empty." % short)

	# Newcomers, while there are beds for them.
	var free := beds() - housed()
	if free > 0 and homeless() == 0 and mood_avg() > 0.45:
		_arrive(1)
	_assign_homes()


func _arrive(n: int) -> void:
	if realm.crew == null or not realm.crew.has_method("spawn_citizens"):
		return
	var before := realm.crew.citizens().size()
	_seed += 1
	realm.crew.spawn_citizens(n, _seed, realm.village.bounds_v)
	_sync()
	var after := realm.crew.citizens().size()
	if after > before:
		var newest: Citizen = people[people.size() - 1]
		newest.arrived_day = realm.clock.day
		realm.note("arrival", "%s arrived in town and took a bed in %s." % [
			newest.name, home_of(newest)])
		realm.say("%s has come to live here." % newest.name)
		moved_in.emit(newest)


func _die(c: Citizen, how: String) -> void:
	c.alive = false
	realm.note("death", "%s died %s, aged %d." % [c.name, how, c.age])
	realm.say("%s has died, %s." % [c.name, how])
	died.emit(c)
	var w := c.worker(realm.crew)
	if w != null and realm.crew.has_method("dismiss"):
		realm.crew.dismiss(w)
		w.queue_free()


## For other systems: somebody has been killed, or fallen ill and not
## recovered, or otherwise ended. Keeps the bookkeeping in one place.
func kill(c: Citizen, how: String) -> void:
	if c != null and c.alive:
		_die(c, how)


# ------------------------------------------------------------------ talking

func try_order(_worker: Worker, _text: String) -> bool:
	return false


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["how many people", "how many live", "population", "how many citizens",
			"how many of us", "how big is the town", "who lives here", "who is in town"]):
		var n := count()
		if n == 0:
			return "Nobody lives here but us. Build houses and people will come."
		var names: Array[String] = []
		for c: Citizen in alive():
			names.append(c.name)
		var out := "%d %s live here" % [n, "person" if n == 1 else "people"]
		if n <= 8:
			out += ": " + ", ".join(names)
		out += ". %d %s, %d beds in all." % [housed(), "housed" if housed() != 1 else "housed",
			beds()]
		if homeless() > 0:
			out += " %d sleeping rough." % homeless()
		return out + " They are %s." % mood_word()
	if Realm.has_phrase(t, ["how is everyone", "how are people", "how are the people", "mood",
			"are people happy", "is everyone happy", "how does everyone feel", "morale"]):
		var out2 := "People are %s." % mood_word()
		var h := hungry()
		if h > 0:
			out2 += " %d of them hungry." % h
		if homeless() > 0:
			out2 += " %d with nowhere to sleep." % homeless()
		return out2
	if Realm.has_phrase(t, ["anyone hungry", "is anyone hungry", "who is hungry", "hungry"]):
		var h2 := hungry()
		return "Nobody is hungry." if h2 == 0 else "%d %s hungry. The larder holds %d food." % [
			h2, "person is" if h2 == 1 else "people are", realm.town.units_of("food")]
	if Realm.has_phrase(t, ["where does", "where do", "who is", "tell me about"]):
		for c: Citizen in alive():
			if t.find(c.name.to_lower()) >= 0:
				return "%s — lives in %s." % [c.describe().capitalize(), home_of(c)]
	if Realm.has_phrase(t, ["how many beds", "any room", "room for more", "free beds"]):
		return "%d beds, %d taken." % [beds(), housed()]
	return ""


func hud_lines() -> Array[String]:
	var n := count()
	if n == 0:
		return []
	var line := "%d people · %s" % [n, mood_word()]
	if hungry() > 0:
		line += " · %d hungry" % hungry()
	return [line]


func snapshot() -> Dictionary:
	var out: Array = []
	for c: Citizen in people:
		out.append({"id": c.id, "name": c.name, "worker_id": c.worker_id,
			"home_id": c.home_id, "workplace_id": c.workplace_id, "job": c.job,
			"age": c.age, "alive": c.alive, "spouse_id": c.spouse_id,
			"parent_ids": c.parent_ids, "needs": c.needs, "mood": c.mood,
			"skills": c.skills, "arrived_day": c.arrived_day})
	return {"people": out, "next_id": _next_id}


func restore(d: Dictionary) -> void:
	people.clear()
	for rec: Variant in d.get("people", []):
		if not (rec is Dictionary):
			continue
		var c := Citizen.new()
		c.id = int(rec.get("id", 0))
		c.name = str(rec.get("name", ""))
		c.worker_id = str(rec.get("worker_id", ""))
		c.home_id = int(rec.get("home_id", -1))
		c.workplace_id = int(rec.get("workplace_id", -1))
		c.job = str(rec.get("job", ""))
		c.age = int(rec.get("age", 25))
		c.alive = bool(rec.get("alive", true))
		c.spouse_id = int(rec.get("spouse_id", -1))
		c.needs = rec.get("needs", c.needs)
		c.mood = float(rec.get("mood", 0.7))
		c.skills = rec.get("skills", {})
		c.arrived_day = int(rec.get("arrived_day", 1))
		people.append(c)
	_next_id = int(d.get("next_id", people.size() + 1))
