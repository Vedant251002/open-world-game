extends Node
class_name Requests
## Daily requests: each morning one to three villagers ask for something
## concrete that fits the town as it really is and what they do ("Ren wants a
## barn before day 6", "Mira would like 60 food in the stores").
##
## Nothing here is scripted content. The wish is chosen from what the town
## lacks (no barn yet, a low larder, nobody sleeping under a roof), the
## condition is checked against the real state (a building of that archetype
## exists, the stores hold N, the payroll has grown), and a request that is
## met pays coins, lifts the asker's morale and rings a chime. One left past
## its day lapses and dents their mood a little. With an API key a single
## call per day phrases the asks in each villager's voice; offline the
## templates below do.

signal changed
signal issued(req: Dictionary)
signal fulfilled(req: Dictionary)
signal expired(req: Dictionary)

const MAX_ACTIVE := 4
const HISTORY := 12
const POLL_SECONDS := 1.0
const TAG := "requests"

var clock: GameClock
var town: Town
var crew: Crew
var realm: Realm
var hud: Hud
var llm: LLM

## {id, who, name, kind, arch, item, n, baseline, issued, due, reward, text, say, thanks}
var active: Array[Dictionary] = []
var history: Array[Dictionary] = []     ## {text, name, status, day}
var _next_id := 1
var _poll := 0.0
var _rng := RandomNumberGenerator.new()
var _asked_day := -1
var _spoke_ms: Dictionary = {}

## Who tends to want what. First word matching the asker's role id wins.
const AFFINITY := {
	"farmer": ["barn", "stable", "smokehouse", "well_house"],
	"shopkeeper": ["store", "tavern", "bakery"],
	"builder": ["workshop", "watchtower", "guard_post"],
	"baker": ["bakery", "store"],
	"cook": ["bakery", "tavern"],
	"guard": ["watchtower", "guard_post", "barracks"],
	"blacksmith": ["workshop", "armoury"],
	"priest": ["shrine"],
}
const GENERIC_BUILDS := ["cottage", "tavern", "shrine", "well_house", "store", "bakery", "barn", "workshop"]
const STOCK_KINDS := {
	"food": 60, "cloth": 30, "meals": 20, "tools": 15, "plank": 120, "timber": 120,
	"cobble": 120, "brick": 40, "glass": 30, "clay_tile": 40, "sandstone": 60,
}
const STOCK_ROLE := {
	"farmer": ["food", "cloth"], "shopkeeper": ["food", "plank", "cloth", "timber"],
	"builder": ["plank", "timber", "cobble", "brick"], "baker": ["food", "meals"],
}


func setup(c: GameClock, t: Town, cr: Crew, r: Realm, h: Hud, l: LLM) -> void:
	clock = c
	town = t
	crew = cr
	realm = r
	hud = h
	llm = l
	_rng.randomize()
	set_process(true)
	clock.day_passed.connect(on_day)
	if hud != null:
		hud.talk_opened.connect(_on_talk)
	if llm != null:
		llm.line_ready.connect(_on_line)


func _process(delta: float) -> void:
	if town == null:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		check()


# ------------------------------------------------------------------ the day

func on_day(day: int) -> void:
	check()
	for req: Dictionary in active.duplicate():
		if day > int(req["due"]):
			_expire(req)
	generate(day)


## Fulfils whatever is now true. Cheap; runs every second and on demand.
func check() -> void:
	for req: Dictionary in active.duplicate():
		if _met(req):
			_fulfil(req)


func _expire(req: Dictionary) -> void:
	active.erase(req)
	var w := _worker(str(req["who"]))
	if w != null:
		w.memory.nudge("morale", -0.05)
	_archive(req, "expired")
	expired.emit(req)
	changed.emit()


func _fulfil(req: Dictionary) -> void:
	active.erase(req)
	var reward := int(req["reward"])
	town.coins += reward
	var w := _worker(str(req["who"]))
	if w != null:
		w.memory.nudge("morale", 0.14)
		w.memory.remember(clock.day, "You came through on a request: %s" % str(req["text"]), 0.6)
		# And it warms them to you (scripts/sim/relationships.gd).
		Relationships.record(w.memory, "request_done", clock.day)
		w.speak(str(req["thanks"]))
	if realm != null:
		realm.note("request", "%s's wish was granted: %s." % [str(req["name"]), str(req["text"]).trim_suffix(".")])
	Sfx.chime()
	if hud != null:
		hud.toast("%s: \"%s\"   +%d coins" % [str(req["name"]), str(req["thanks"]), reward], 5.0)
	_archive(req, "done")
	fulfilled.emit(req)
	changed.emit()


func _archive(req: Dictionary, status: String) -> void:
	history.append({"text": str(req["text"]), "name": str(req["name"]), "status": status,
		"day": clock.day})
	if history.size() > HISTORY:
		history = history.slice(history.size() - HISTORY)


# ----------------------------------------------------------------- the state

func _count(arch: String) -> int:
	if arch == "home":
		return _count("cottage") + _count("hut") + _count("apartment")
	var n := 0
	for b: Dictionary in town.buildings:
		if str(b["archetype"]) == arch:
			n += 1
	return n


func _met(req: Dictionary) -> bool:
	match str(req["kind"]):
		"build", "home":
			return _count(str(req["arch"])) >= int(req["baseline"]) + 1
		"stock":
			return int(town.stock.get(str(req["item"]), 0)) >= int(req["n"])
		"hire":
			return crew.hired().size() >= int(req["baseline"]) + 1
	return false


## "have 12 of 60" and the like, for the HUD.
func progress_text(req: Dictionary) -> String:
	match str(req["kind"]):
		"stock":
			return "%d / %d" % [int(town.stock.get(str(req["item"]), 0)), int(req["n"])]
		"hire":
			return "%d on the payroll" % crew.hired().size()
	return ""


func _worker(id: String) -> Worker:
	return crew.get_worker(id) if crew != null else null


func for_worker(worker_id: String) -> Dictionary:
	for req: Dictionary in active:
		if str(req["who"]) == worker_id:
			return req
	return {}


# --------------------------------------------------------------- generating

func _role_key(w: Worker) -> String:
	if w.role != null and str(w.role.id) != "":
		return str(w.role.id)
	if realm != null and realm.population != null:
		var c: Variant = realm.population.for_worker(w)
		if c != null and str(c.job) != "":
			return str(c.job)
	return ""


func _affinity(key: String, table: Dictionary) -> Array:
	for k: Variant in table:
		if key.find(str(k)) >= 0:
			return (table[k] as Array).duplicate()
	return []


## Picks 1-3 askers and gives each a wish. Returns the new requests.
func generate(day: int) -> Array[Dictionary]:
	_rng.seed = hash("requests-%d-%d" % [day, town.buildings.size()])
	var made: Array[Dictionary] = []
	var room := MAX_ACTIVE - active.size()
	if room <= 0 or crew == null:
		return made
	var want := 1 if day <= 2 else 1 + _rng.randi() % 3
	want = mini(want, room)
	var pool: Array[Worker] = []
	for w: Worker in crew.workers:
		if w.memory != null and for_worker(w.memory.worker_id).is_empty():
			pool.append(w)
	# Fresh faces first: whoever asked last time goes to the back.
	pool.shuffle()
	for _i in want:
		if pool.is_empty():
			break
		var w: Worker = pool.pop_back()
		var req := _wish_for(w, day)
		if req.is_empty():
			continue
		active.append(req)
		made.append(req)
		issued.emit(req)
	if not made.is_empty():
		_ask_llm(made, day)
		changed.emit()
	return made


func _wish_for(w: Worker, day: int) -> Dictionary:
	var key := _role_key(w)
	var name := w.memory.display_name
	var options: Array[Dictionary] = []

	# Something built: an archetype the town does not have yet.
	var pref: Array = _affinity(key, AFFINITY)
	var archs: Array = pref.duplicate()
	archs.append_array(GENERIC_BUILDS)
	for a: Variant in archs:
		var arch := str(a)
		if _count(arch) == 0 and not _taken("build", arch):
			options.append({"kind": "build", "arch": arch, "weight": 5 if a in pref else 2})
	# Something in the stores: a kind that is running low.
	var kinds: Array = _affinity(key, STOCK_ROLE)
	for k: Variant in STOCK_KINDS:
		kinds.append(k)
	for k: Variant in kinds:
		var item := str(k)
		var have := int(town.stock.get(item, 0))
		if have < 600 and not _taken("stock", item):
			options.append({"kind": "stock", "item": item, "weight": 3 if k in _affinity(key, STOCK_ROLE) else 2})
	# Another pair of hands, while the payroll is small.
	if crew.hired().size() < 6 and not _taken("hire", ""):
		options.append({"kind": "hire", "weight": 2})
	# A roof, when somebody is sleeping rough.
	if realm != null and realm.population != null and realm.population.homeless() > 0 \
			and not _taken("home", "home"):
		options.append({"kind": "home", "arch": "home", "weight": 4})
	if options.is_empty():
		return {}
	var total := 0
	for o: Dictionary in options:
		total += int(o["weight"])
	var roll := _rng.randi() % total
	var pick: Dictionary = options[0]
	for o: Dictionary in options:
		roll -= int(o["weight"])
		if roll < 0:
			pick = o
			break
	return _make(w, name, pick, day)


func _taken(kind: String, what: String) -> bool:
	for r: Dictionary in active:
		if str(r["kind"]) == kind and (what == "" or str(r.get("arch", r.get("item", ""))) == what):
			return true
	return false


func _make(w: Worker, name: String, pick: Dictionary, day: int) -> Dictionary:
	var kind := str(pick["kind"])
	var req := {
		"id": _next_id, "who": w.memory.worker_id, "name": name, "kind": kind,
		"arch": str(pick.get("arch", "")), "item": str(pick.get("item", "")), "n": 0,
		"baseline": 0, "issued": day, "due": day + 3, "reward": 0,
		"text": "", "say": "", "thanks": "",
	}
	_next_id += 1
	match kind:
		"build":
			var arch := str(req["arch"])
			var what := arch.replace("_", " ")
			var art := "an" if what.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a"
			req["baseline"] = _count(arch)
			req["due"] = day + 4
			req["reward"] = 250 + 50 * (_rng.randi() % 5)
			req["text"] = "%s %s before day %d" % [art, what, int(req["due"]) + 1]
			req["say"] = str(_choose([
				"I would dearly like %s %s in town, and before day %d if it can be managed." % [art, what, int(req["due"]) + 1],
				"If you can see your way to %s %s, I would be very glad. Say by day %d?" % [art, what, int(req["due"]) + 1],
				"We want for %s %s here. Could one go up before day %d?" % [art, what, int(req["due"]) + 1],
			]))
			req["thanks"] = str(_choose([
				"There it stands! I could hug the lot of you.",
				"Well, look at that. Thank you, truly.",
				"A fine thing. You listened.",
			]))
		"stock":
			var item := str(req["item"])
			var have := int(town.stock.get(item, 0))
			var step := int(STOCK_KINDS.get(item, 40))
			var n := have + step + 10 * (_rng.randi() % 4)
			n = int(ceil(float(n) / 10.0)) * 10
			req["n"] = n
			req["due"] = day + 2
			req["reward"] = 60 + int(Town.PRICE.get(item, Town.DEFAULT_PRICE)) * step / 2
			req["text"] = "%d %s in the stores" % [n, item.replace("_", " ")]
			req["say"] = str(_choose([
				"Could the stores hold %d %s? We are cutting it fine." % [n, item.replace("_", " ")],
				"I keep counting the %s and I do not like the sum. %d would let me sleep." % [item.replace("_", " "), n],
				"Put %d %s by, would you? Just so we are not caught short." % [n, item.replace("_", " ")],
			]))
			req["thanks"] = str(_choose([
				"Stores are full. Bless you.",
				"Now that is a sight for tired eyes.",
				"There is the %s. You are better than your word." % item.replace("_", " "),
			]))
		"hire":
			req["baseline"] = crew.hired().size()
			req["due"] = day + 3
			req["reward"] = 200
			req["text"] = "another pair of hands on the payroll"
			req["say"] = str(_choose([
				"There is more work than hands. Could you take someone on?",
				"I am run off my feet. One more hired hand would do us all good.",
				"Hire somebody, would you? Anybody with a back and a willing look.",
			]))
			req["thanks"] = "A new hand! My feet thank you."
		"home":
			req["baseline"] = _count("home")
			req["due"] = day + 4
			req["reward"] = 220
			req["text"] = "a roof for those sleeping rough"
			req["say"] = str(_choose([
				"Some of us are sleeping under hedges. A cottage or even a hut would be a mercy.",
				"It is getting to be a poor sort of town that leaves its people in the cold. A house, please.",
				"Could somebody build a home? I keep stepping over our neighbours in the lane.",
			]))
			req["thanks"] = "Warm beds tonight. You have done a kindness."
	return req


func _choose(options: Array) -> Variant:
	return options[_rng.randi() % options.size()]


# ----------------------------------------------------------------- talking

func _on_talk(w: Worker) -> void:
	if w == null or w.memory == null:
		return
	var req := for_worker(w.memory.worker_id)
	if req.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_spoke_ms.get(w.memory.worker_id, -100000)) < 15000:
		return
	_spoke_ms[w.memory.worker_id] = now
	var t := get_tree().create_timer(0.8)
	t.timeout.connect(func() -> void:
		if is_instance_valid(w) and not for_worker(w.memory.worker_id).is_empty():
			w.speak(str(req["say"])))


# ----------------------------------------------------------------- the LLM

func _ask_llm(made: Array[Dictionary], day: int) -> void:
	if llm == null or not llm.available() or _asked_day == day:
		return
	_asked_day = day
	var lines: Array[String] = []
	for r: Dictionary in made:
		lines.append("%d | %s | wants: %s" % [int(r["id"]), str(r["name"]), str(r["text"])])
	var system := ("You voice villagers in a small, warm, slightly literary village. For each request "
		+ "line, write what that villager would say aloud to the player, in one short sentence in their "
		+ "own voice, keeping every number and the deadline. Reply with one line per request in the "
		+ "form: id | sentence. Nothing else.")
	llm.talk(TAG, system, [{"role": "user", "content": "\n".join(lines)}], TAG, "")


func _on_line(worker_id: String, text: String, tag: String) -> void:
	if tag != TAG or worker_id != TAG:
		return
	apply_phrasing(text)


## Parses "id | sentence" lines onto the active requests. Public for the test.
func apply_phrasing(text: String) -> int:
	var n := 0
	for raw: String in text.split("\n"):
		var parts := raw.split("|", true, 1)
		if parts.size() < 2 or not parts[0].strip_edges().is_valid_int():
			continue
		var id := int(parts[0].strip_edges())
		var line := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if line == "" or line.length() > 220:
			continue
		for r: Dictionary in active:
			if int(r["id"]) == id:
				r["say"] = line
				n += 1
	if n > 0:
		changed.emit()
	return n


# ------------------------------------------------------------------- saving

func snapshot() -> Dictionary:
	return {"active": active, "history": history, "next": _next_id, "asked": _asked_day}


func restore(d: Dictionary) -> void:
	active.clear()
	history.clear()
	for r: Variant in d.get("active", []):
		if r is Dictionary:
			var req: Dictionary = r
			for k: String in ["id", "n", "baseline", "issued", "due", "reward"]:
				req[k] = int(req.get(k, 0))
			active.append(req)
	for h: Variant in d.get("history", []):
		if h is Dictionary:
			history.append(h)
	_next_id = int(d.get("next", active.size() + 1))
	_asked_day = int(d.get("asked", -1))
	changed.emit()
