extends Node
class_name VillageCouncil
## The village organising itself: people noticing what needs doing, talking it
## over, and handing the work to whoever can do it.
##
## Every so often the council looks at the town as it actually is — what is
## ripe in the field, whether anything is sown at all, the animals, the timber
## and stone in the yard, whether the shop is open — and picks the thing that
## most needs doing that nobody is doing. Then it plays it out the way a
## village would:
##
##   - somebody NOTICES: whoever it matters to (the baker sees the larder, the
##     shepherd's wife sees the animals, the builder sees the yard);
##   - they walk over to somebody who ORGANISES — one of your crew, whoever
##     is most sure of themselves and free — and say so, in a line with the
##     real numbers in it;
##   - the organiser goes to whoever can DO it — a crew member whose trade
##     covers the job, and who is idle — and asks;
##   - they say yes, and the job starts: the same job, run the same way, as if
##     you had given the order yourself.
##
## So a builder's wife tells her husband the yard is nearly out of timber, he
## sends the farmer for it, and you watch it happen across the square.
##
## None of it calls the model. The need is read off the town's numbers and the
## job is a step from the engine's verb catalogue — the decision is the
## engine's own, cheap and immediate, and the plan goes through exactly the
## executor your orders go through. The talk is written here, in each
## person's position, with the town's real figures in it. (Design rule: the
## village's background decisions never go to the large model.)
##
## Between the work there is plain talk: two people who are both standing
## about near each other stop, turn to each other and pass a few words — the
## weather, the town, their other half — and go on with their day.
##
## Choreography is only spent where you can see it. Out of sight, a need is
## settled without the walk: the order is simply given.

signal delegated(raiser: Worker, lead: Worker, doer: Worker, job: String)

## How often the town is looked over for work, and how often idle neighbours
## are given the chance to chat, in real seconds.
const SCAN_EVERY := 35.0
const CHAT_EVERY := 22.0
## Only between these hours does anybody organise work.
const DAY_FROM := 7.0
const DAY_TO := 18.5
## Choreography only near you; beyond this a need is settled off stage.
const STAGE_M := 45.0
## How long a scene may take before it is cut short and the order simply given.
const SCENE_TIMEOUT := 70.0
## Within this, the organiser calls across rather than walking over.
const CALL_M := 7.0

## What can need doing. Each: the verb, the trade that can do it, who is
## likely to notice, how long after it was last handed out before it can come
## up again (game hours), and what is said. {n} is the figure that made it
## a need; {lead} and {doer} are names.
const NEEDS := {
	"harvest": {
		"step": {"do": "harvest"}, "cap": "harvest", "notice": ["greta", "anselm", "lena"],
		"cooldown": 3.0, "job": "bring in the harvest",
		"raise": ["{lead}, there are {n} rows standing ripe in the field and nobody bringing them in.",
			"{lead}, the wheat's ready — {n} rows of it. It'll spoil if it stands.",
			"The larder's bare and there's {n} rows ripe out there, {lead}."],
		"ask": ["{doer}, would you bring the harvest in? It's ready.",
			"{doer} — the field's ripe. Get it in before it turns, would you?"],
		"yes": ["Right. I'll fetch the baskets.", "On it — I'll have it in by dark.",
			"Aye, I saw it was turning."],
	},
	"sow": {
		"step": {"do": "sow", "crop": "wheat"}, "cap": "sow", "notice": ["greta", "anselm"],
		"cooldown": 10.0, "job": "plough and sow a field",
		"raise": ["{lead}, there's nothing in the ground at all. We'll have nothing to eat come autumn.",
			"Nobody's sown a thing, {lead}. Bread comes out of a field."],
		"ask": ["{doer}, can you put a field in? Wheat, while the weather holds.",
			"{doer} — plough a strip and get some wheat sown, would you?"],
		"yes": ["I'll get the plough out.", "Wheat it is. Leave it with me."],
	},
	"collect": {
		"step": {"do": "collect"}, "cap": "collect", "notice": ["lena", "greta"],
		"cooldown": 20.0, "job": "go round the animals for eggs and milk",
		"raise": ["{lead}, nobody's been round the animals today. There'll be eggs going to waste.",
			"The hens are laying and nobody's collecting, {lead}. {n} head out there."],
		"ask": ["{doer}, go round the animals, would you? Eggs, milk, whatever there is.",
			"{doer} — collect from the animals before evening."],
		"yes": ["I'll take a basket round.", "Right, eggs first."],
	},
	"tend": {
		"step": {"do": "tend"}, "cap": "tend", "notice": ["lena"],
		"cooldown": 22.0, "job": "feed and see to the animals",
		"raise": ["{lead}, the animals want feeding — {n} of them and the trough's dry.",
			"Somebody needs to see to the animals, {lead}."],
		"ask": ["{doer}, feed the animals and look them over, would you?",
			"{doer} — the animals. Feed and water, please."],
		"yes": ["I'll see to them.", "On my way to them now."],
	},
	"timber": {
		"step": {"do": "gather", "material": "timber", "units": 60}, "cap": "gather",
		"notice": ["tobias", "greta"], "cooldown": 8.0, "job": "fetch timber",
		"raise": ["{lead}, the yard's down to {n} timber. That won't put up a shed.",
			"We're nearly out of timber, {lead} — {n} left."],
		"ask": ["{doer}, go and fell some timber, would you? Sixty or so.",
			"{doer} — we need timber. Out to the woods, please."],
		"yes": ["I'll take the axe.", "Sixty it is."],
	},
	"stone": {
		"step": {"do": "gather", "material": "cobble", "units": 60}, "cap": "gather",
		"notice": ["tobias", "anselm"], "cooldown": 8.0, "job": "quarry stone",
		"raise": ["{lead}, there's only {n} stone in the yard. Nothing gets built on that.",
			"Stone's running low, {lead} — {n} left."],
		"ask": ["{doer}, can you quarry us some stone? Sixty blocks.",
			"{doer} — fetch stone, would you? We're short."],
		"yes": ["I'll get the pick.", "Right, stone."],
	},
	"shop": {
		"step": {"do": "station", "place": "store", "hours": 4}, "cap": "station",
		"notice": ["anselm", "greta"], "cooldown": 20.0, "job": "open the shop",
		"raise": ["{lead}, the shop's shut and people are asking at the door.",
			"Is nobody minding the store today, {lead}?"],
		"ask": ["{doer}, open up the shop for the afternoon, would you?",
			"{doer} — the store wants opening. Folk are waiting."],
		"yes": ["I'll open up now.", "Coming — I'll put the kettle on behind the counter."],
		"role": "shopkeeper",
	},
}

## Thresholds for the stock needs.
const TIMBER_LOW := 300
const STONE_LOW := 300

var crew: Crew
var dispatch: Node
var town: Town
var farm: Farm
var livestock: Livestock
var clock: GameClock
var player: Node3D
var hud: Node = null
var realm: Node = null

var _scan_t := 10.0
var _chat_t := 8.0
var _last: Dictionary = {}           ## need -> game hour it was last handed out
var _scene: Dictionary = {}          ## the conversation playing out now


func setup(c: Crew, d: Node, t: Town, f: Farm, l: Livestock, k: GameClock,
		p: Node3D, h: Node, r: Node) -> void:
	crew = c
	dispatch = d
	town = t
	farm = f
	livestock = l
	clock = k
	player = p
	hud = h
	realm = r


func _process(delta: float) -> void:
	if crew == null or clock == null:
		return
	if not _scene.is_empty():
		_play(delta)
		return
	_scan_t -= delta
	_chat_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY * randf_range(0.8, 1.2)
		if clock.hour >= DAY_FROM and clock.hour < DAY_TO:
			_organise()
			if not _scene.is_empty():
				return
	if _chat_t <= 0.0:
		_chat_t = CHAT_EVERY * randf_range(0.7, 1.3)
		_small_talk()


# ================================================================ organising

func _now() -> float:
	return float(clock.day) * 24.0 + clock.hour


## The most pressing thing nobody is doing, and the people to see it done.
func _organise() -> void:
	var busy_verbs: Dictionary = dispatch.call("running_verbs")
	var best := ""
	var best_n := 0
	var best_urgency := 0.0
	var best_doer: Worker = null
	for need: String in NEEDS:
		var def: Dictionary = NEEDS[need]
		if _now() - float(_last.get(need, -999.0)) < float(def["cooldown"]):
			continue
		if busy_verbs.has(str((def["step"] as Dictionary)["do"])):
			continue
		var m := _measure(need)
		var urgency := float(m[0])
		if urgency <= 0.0 or urgency <= best_urgency:
			continue
		var doer := _doer_for(def)
		if doer == null:
			continue
		best = need
		best_n = int(m[1])
		best_urgency = urgency
		best_doer = doer
	if best == "":
		return
	var def2: Dictionary = NEEDS[best]
	var lead := _lead_for(best_doer)
	var raiser := _raiser_for(def2, lead, best_doer)
	_last[best] = _now()
	_begin(best, best_n, raiser, lead, best_doer)


## How much a need matters right now, 0 for not at all, and the figure behind
## it. Read straight off the town.
func _measure(need: String) -> Array:
	match need:
		"harvest":
			var ripe := farm.ripe_count() if farm != null else 0
			return [3.0 + ripe * 0.2 if ripe >= 3 else 0.0, ripe]
		"sow":
			if farm == null or farm.season_rate <= 0.05:
				return [0.0, 0]
			return [2.0 if farm.planted_count() == 0 else 0.0, 0]
		"collect":
			var n := livestock.total() if livestock != null else 0
			return [1.6 if n >= 2 else 0.0, n]
		"tend":
			var n2 := livestock.total() if livestock != null else 0
			return [1.2 if n2 >= 2 and clock.hour < 12.0 else 0.0, n2]
		"timber":
			var tb := int(town.stock.get("timber", 0))
			return [2.4 if tb < TIMBER_LOW else 0.0, tb]
		"stone":
			var st := int(town.stock.get("cobble", 0))
			return [2.2 if st < STONE_LOW else 0.0, st]
		"shop":
			var has_store := false
			for rec: Dictionary in town.buildings:
				if str(rec["archetype"]) == "store":
					has_store = true
			return [1.0 if has_store and clock.hour >= 9.0 and clock.hour < 16.0 else 0.0, 0]
	return [0.0, 0]


## A crew member whose trade covers it and who has nothing on.
func _doer_for(def: Dictionary) -> Worker:
	var cap := str(def["cap"])
	var want_role := str(def.get("role", ""))
	var pick: Worker = null
	var best := -1.0
	for w: Worker in crew.hired():
		if w.role == null or not w.role.can(cap):
			continue
		if want_role != "" and w.role.id != want_role:
			continue
		if not w.free_for_life() or bool(dispatch.call("has_job", w)):
			continue
		# The one whose trade it most is: a specialist before the builder who
		# can do everything.
		var score := 2.0 if w.role.id != "builder" else 1.0
		score += randf() * 0.2
		if score > best:
			best = score
			pick = w
	return pick


## Somebody to organise it: of your crew, sure of themselves, free, and not
## the one who will be doing it. Nobody of the sort, and the doer is asked
## directly by whoever noticed.
func _lead_for(doer: Worker) -> Worker:
	var pick: Worker = null
	var best := -1.0
	for w: Worker in crew.hired():
		if w == doer or w.sleeping or w.engaged:
			continue
		if not w.free_for_life():
			continue
		var t: Dictionary = w.memory.traits
		var d: Dictionary = w.memory.disposition
		var score := float(d.get("confidence", 0.5)) + 0.4 * float(t.get("initiative", 0.5))
		if w.role != null and w.role.can("delegate"):
			score += 1.0
		if score > best:
			best = score
			pick = w
	return pick


## Whoever the need matters to and is about; otherwise the organiser noticed
## it themselves.
func _raiser_for(def: Dictionary, lead: Worker, doer: Worker) -> Worker:
	for wid: String in def["notice"]:
		var w := crew.get_worker(wid)
		if w == null or w == lead or w == doer:
			continue
		if w.free_for_life():
			return w
	return lead


# =================================================================== scenes

func _begin(need: String, n: int, raiser: Worker, lead: Worker, doer: Worker) -> void:
	var on_stage := _near(doer) and (lead == null or _near(lead)) \
		and (raiser == null or _near(raiser))
	if not on_stage:
		_hand_over(need, n, raiser, lead, doer, false)
		return
	_scene = {
		"kind": "work", "need": need, "n": n, "raiser": raiser, "lead": lead,
		"doer": doer, "phase": "meet", "t": 0.0, "wait": 0.0, "age": 0.0,
	}
	for w: Worker in _cast():
		w.engaged = true
		w.stop_wandering()
	# Who walks: the one who noticed goes to the organiser, or, with no
	# organiser, straight to the one who will do it.
	var a: Worker = raiser
	var b: Worker = lead if lead != null else doer
	if a == null or a == b:
		_scene["phase"] = "fetch"
		return
	_walk_up(a, b)


func _cast() -> Array[Worker]:
	var out: Array[Worker] = []
	for k: String in ["raiser", "lead", "doer"]:
		var w: Worker = _scene.get(k, null)
		if w != null and is_instance_valid(w) and not out.has(w):
			out.append(w)
	return out


func _play(delta: float) -> void:
	_scene["age"] = float(_scene["age"]) + delta
	_scene["wait"] = float(_scene["wait"]) - delta
	if float(_scene["wait"]) > 0.0:
		return
	if str(_scene["kind"]) == "chat":
		_play_chat()
		return
	for w: Worker in _cast():
		if not is_instance_valid(w) or w.sleeping:
			_end_scene()
			return
	var need := str(_scene["need"])
	var def: Dictionary = NEEDS[need]
	var raiser: Worker = _scene["raiser"]
	var lead: Worker = _scene["lead"]
	var doer: Worker = _scene["doer"]
	if float(_scene["age"]) > SCENE_TIMEOUT:
		_hand_over(need, int(_scene["n"]), raiser, lead, doer, true)
		_end_scene()
		return
	var b: Worker = lead if lead != null else doer
	match str(_scene["phase"]):
		"meet":
			if _close(raiser, b, 2.4):
				raiser.face(b.global_position)
				b.face(raiser.global_position)
				raiser.say_aloud(_fill(_pick(def["raise"]), need, b, doer))
				_scene["phase"] = "reply"
				_scene["wait"] = 3.2
		"reply":
			if lead != null and lead != doer:
				lead.say_aloud(_lead_reply(doer))
				_scene["wait"] = 2.6
			_scene["phase"] = "fetch"
		"fetch":
			var asker: Worker = lead if lead != null else raiser
			if asker == null or asker == doer:
				_scene["phase"] = "yes"
				return
			if _close(asker, doer, CALL_M):
				asker.face(doer.global_position)
				doer.face(asker.global_position)
				asker.say_aloud(_fill(_pick(def["ask"]), need, b, doer))
				_scene["phase"] = "yes"
				_scene["wait"] = 2.8
			elif asker.state == Worker.State.IDLE:
				_walk_up(asker, doer)
				_scene["wait"] = 1.0
		"yes":
			doer.say_aloud(_pick(def["yes"]))
			_scene["wait"] = 2.0
			_scene["phase"] = "go"
		"go":
			_hand_over(need, int(_scene["n"]), raiser, lead, doer, true)
			_end_scene()


func _end_scene() -> void:
	for w: Worker in _cast():
		if is_instance_valid(w):
			w.engaged = false
	_scene = {}


## The order given, the log told, and the people remember it.
func _hand_over(need: String, n: int, raiser: Worker, lead: Worker, doer: Worker,
		_seen: bool) -> void:
	if doer == null or not is_instance_valid(doer) or not doer.hired:
		return
	var def: Dictionary = NEEDS[need]
	var job := str(def["job"])
	var by: Worker = lead if lead != null else raiser
	var by_name := by.display_name() if by != null and by != doer else ""
	doer.engaged = false
	var steps: Array = [(def["step"] as Dictionary).duplicate(true)]
	dispatch.call("delegate_plan", doer, job, steps)
	var day := clock.day
	if by_name != "":
		doer.memory.remember(day, "%s asked me to %s." % [by_name, job], 0.05,
			{"kind": "delegated", "by": by.memory.worker_id})
		by.memory.remember(day, "I asked %s to %s." % [doer.display_name(), job], 0.05,
			{"kind": "delegated", "to": doer.memory.worker_id})
	var line := "%s asked %s to %s." % [by_name, doer.display_name(), job] if by_name != "" \
		else "%s went to %s." % [doer.display_name(), job]
	if raiser != null and raiser != by and raiser != doer:
		line += " (%s had noticed.)" % raiser.display_name()
	if hud != null and hud.has_method("toast"):
		hud.call("toast", line, 4.5)
	if realm != null and realm.has_method("note"):
		realm.call("note", "village", line)
	delegated.emit(raiser, lead, doer, job)
	print("[council] %s  (need %s, figure %d)" % [line, need, n])


func _walk_up(a: Worker, b: Worker) -> void:
	var to := b.global_position - a.global_position
	to.y = 0.0
	if to.length() < 2.0:
		return
	var spot := b.global_position - to.normalized() * 1.5
	# Both under the same roof: across the room, not out of the door.
	if a.indoors != null and a.indoors == b.indoors:
		if not a.indoor_walking():
			a.indoor_walk_to(spot)
		return
	a.engaged = false              # let the walk run; the scene still holds them
	a.go_near(spot)
	a.engaged = true


func _close(a: Worker, b: Worker, m: float) -> bool:
	if a == null or b == null:
		return true
	var d := Vector2(a.global_position.x - b.global_position.x,
		a.global_position.z - b.global_position.z).length()
	return d < m


func _near(w: Worker) -> bool:
	if w == null or player == null:
		return true
	return w.visible and w.is_physics_processing() \
		and w.global_position.distance_to(player.global_position) < STAGE_M


# ================================================================== the talk

func _lead_reply(doer: Worker) -> String:
	var n := doer.display_name()
	return _pick(["Then it's a job for %s. Leave it with me." % n,
		"You're right. I'll get %s on it." % n,
		"Good that you said. %s can see to that." % n,
		"Mm. I'll have a word with %s." % n])


func _fill(tpl: String, need: String, lead: Worker, doer: Worker) -> String:
	var n := 0
	match need:
		"harvest":
			n = farm.ripe_count() if farm != null else 0
		"collect", "tend":
			n = livestock.total() if livestock != null else 0
		"timber":
			n = int(town.stock.get("timber", 0))
		"stone":
			n = int(town.stock.get("cobble", 0))
	return tpl.format({"n": n, "lead": lead.display_name() if lead != null else "",
		"doer": doer.display_name() if doer != null else ""})


func _pick(pool: Array) -> String:
	return str(pool[randi() % pool.size()])


# =============================================================== small talk

## Two people standing about near each other, both free, near you: they stop
## and pass a few words, then go on with their day.
func _small_talk() -> void:
	if player == null:
		return
	var free: Array[Worker] = []
	for w: Worker in crew.workers:
		if w.free_for_life() and _near(w) \
				and w.global_position.distance_to(player.global_position) < 30.0:
			free.append(w)
	if free.size() < 2:
		return
	var a: Worker = null
	var b: Worker = null
	var best := INF
	for i in free.size():
		for j in range(i + 1, free.size()):
			# Through a wall is not talking distance: the same building, or
			# both out in the open.
			if free[i].indoors != free[j].indoors:
				continue
			var d := free[i].global_position.distance_to(free[j].global_position)
			# A couple find each other from further off, and first.
			var couple := free[i].partner_id == free[j].memory.worker_id
			var reach := 12.0 if couple else 7.0
			var score := d - (6.0 if couple else 0.0)
			if d < reach and score < best:
				best = score
				a = free[i]
				b = free[j]
	if a == null:
		return
	var lines := _chat_lines(a, b)
	if lines.is_empty():
		return
	_scene = {"kind": "chat", "a": a, "b": b, "lines": lines, "i": 0, "wait": 0.0,
		"age": 0.0, "raiser": a, "lead": b}
	a.engaged = true
	b.engaged = true
	a.stop_wandering()
	b.stop_wandering()
	if a.global_position.distance_to(b.global_position) > 2.6:
		_walk_up(a, b)


func _play_chat() -> void:
	var a: Worker = _scene["a"]
	var b: Worker = _scene["b"]
	if not is_instance_valid(a) or not is_instance_valid(b) or a.sleeping or b.sleeping \
			or float(_scene["age"]) > 40.0:
		_end_scene()
		return
	if not _close(a, b, 2.8):
		if a.state == Worker.State.IDLE and not a.indoor_walking():
			_walk_up(a, b)
		_scene["wait"] = 0.8
		return
	var i := int(_scene["i"])
	var lines: Array = _scene["lines"]
	if i >= lines.size():
		_end_scene()
		return
	var speaker: Worker = a if i % 2 == 0 else b
	var other: Worker = b if i % 2 == 0 else a
	speaker.face(other.global_position)
	other.face(speaker.global_position)
	speaker.say_aloud(str(lines[i]))
	_scene["i"] = i + 1
	_scene["wait"] = clampf(2.2 + str(lines[i]).length() * 0.045, 2.6, 5.0)


## What two people say to each other, from what is true right now.
func _chat_lines(a: Worker, b: Worker) -> Array:
	var an := a.display_name()
	var bn := b.display_name()
	var h := clock.hour
	var food := int(town.stock.get("food", 0))
	var ripe := farm.ripe_count() if farm != null else 0
	var animals := livestock.total() if livestock != null else 0
	var built := town.buildings.size()
	var pool: Array = []
	# A couple.
	if a.partner_id == b.memory.worker_id:
		if h >= 17.0:
			pool.append(["There you are. Long day?", "Long enough. Is there anything to eat?",
				"There will be, if somebody brought the bread."])
			pool.append(["%s. I was hoping I'd see you before supper." % bn,
				"I'm done for the day. Walk home with me?"])
		else:
			pool.append(["%s! What are you doing out here?" % bn,
				"Same as you — working. Don't be late tonight.", "I won't."])
			pool.append(["Did you eat anything this morning?",
				"A crust. Don't fuss.", "I'll fuss if I like."])
	# The town as it is.
	if ripe >= 3:
		pool.append(["Have you seen the field? %d rows ripe." % ripe,
			"Somebody ought to bring it in before the birds do."])
	if food < 10:
		pool.append(["The larder's near empty, %s." % bn,
			"I know. We'll be eating air if the harvest doesn't come in."])
	else:
		pool.append(["%d in the larder now. Better than it was." % food,
			"Better. Not good. But better."])
	if animals > 0:
		pool.append(["%d animals about the place now." % animals,
			"And every one of them louder than the last."])
	pool.append(["%d buildings standing, %s. When I came there was mud." % [built, bn],
		"There's still mud. It just has houses on it now."])
	# The hour.
	if h < 10.0:
		pool.append(["Morning, %s." % bn, "Morning. Sleep well?", "Like a log. You?",
			"The cockerel had other ideas."])
	elif h > 16.0:
		pool.append(["Nearly done for the day?", "Nearly. Are you going to the tavern?",
			"If my feet hold out."])
	else:
		pool.append(["Busy, %s?" % bn, "Always. You?", "Never, if anybody asks."])
	pool.append(["%s." % bn, "%s." % an, "Fine weather for it.", "For what?",
		"For anything."])
	return pool[randi() % pool.size()]
