extends Node
class_name Dispatcher
## Turns a sentence into a job.
##
## The pipeline is the whole game (voxel-module-spec.md §0):
##
##   instruction -> LLM (or the offline library) -> plan
##   plan -> pre-validator -> a typed error, or a list of one to four steps
##   step -> the part of the town that already does that work
##   patch -> the stores, which either cover the bill or do not
##   patch -> the worker, who walks off and lays it down over in-game hours
##
## A plan is a short list rather than a single building because an order often
## has parts that have to happen in order — a pen has to stand before anything
## can go in it — and because the alternative, which this had, was a growing
## pile of keyword matches in instruct() that could each hear one kind of order
## and none of them hear two. See Steps for the verbs and _advance for the loop.
##
## The stores are a gate, not a counter. Nothing is started that the town
## cannot finish; a plan it cannot pay for is held whole and somebody is sent
## out to dig for what is missing, and the build begins by itself when the
## material is in. See _begin().
##
## Every error on that path is fail-closed and typed, and every typed error
## becomes a question the worker asks out loud rather than a message box. That
## is design pillar P3: failure has to be legible, and it has to be in character.

signal spoke(worker: Worker, line: String, kind: String)
signal plan_accepted(worker: Worker, assumptions: Array)
signal refused(worker: Worker, err: Dictionary)
signal status(text: String)
## A plan that is sound but unaffordable. The HUD puts the shortfall on screen;
## the worker says it out loud. Both, because this is the one refusal the player
## can actually do something about.
signal short_of(worker: Worker, missing: Dictionary)
## The player said "save" or "start over" to somebody. The text field is the
## only control in the game (pillar P1), so these are sentences too.
signal save_requested()
signal restart_requested()

var world: VoxelWorld
var village: Village
var gen: WorldGen
var town: Town
var clock: GameClock
var nav: NavGrid
var props_root: Node3D
var llm: LLM
var map: MapScreen
var farm: Farm
var livestock: Livestock
var wildlife: Wildlife
var warfare: Warfare
var player: Node3D
## Assigned from outside, which is why it is a setter rather than a plain field:
## a multi-step order advances when a worker finishes a step, and there is no
## other moment at which every worker is known to exist.
var crew: Crew: set = _set_crew

## worker_id -> {"worker": Worker, "instruction": String, "plot": Plot}
var _open: Dictionary = {}

## worker_id -> an accepted plan being carried out, one step at a time.
##
##   {"worker", "steps", "at", "sites", "assumptions", "plot", "instruction"}
##
## `sites` is what makes this a plan rather than a list: a step that claims
## ground records it under its id, and a later step's "into" / "in" / "near"
## resolves through here. It is the entire mechanism behind "fence the top
## corner and put the hens in it", and it is forty lines, because the steps
## themselves are all things the town already knew how to do.
var _running: Dictionary = {}

## Plans that are finished and correct but cannot be paid for yet. They sit
## here, whole, until the stores can cover them — the spec is not re-planned,
## downgraded or quietly swapped for something cheaper, because the player asked
## for a thing and is owed either that thing or a reason (pillar P3).
var _held: Array[Dictionary] = []
var _retry := 0.0

## Hires waiting on a job to be written up: role key -> the people who asked
## for it. One composition can serve several — "hire Ada and Bram as guards"
## is one job, twice.
var _pending_hires: Dictionary = {}


func _set_crew(c: Crew) -> void:
	crew = c
	if crew == null:
		return
	for w: Worker in crew.workers:
		if not w.step_done.is_connected(_on_step_done):
			w.step_done.connect(_on_step_done)
		# A step that fails after the worker has taken it — no route to the
		# ground, the way blocked since the plan was made — ends the plan too.
		# Without this the run sits in _running waiting for a step_done that
		# cannot arrive, and the rest of the order is neither done nor refused.
		if not w.job_failed.is_connected(_on_step_failed):
			w.job_failed.connect(_on_step_failed)


func setup(w: VoxelWorld, v: Village, g: WorldGen, t: Town, c: GameClock,
		n: NavGrid, pr: Node3D, m: MapScreen) -> void:
	world = w
	village = v
	gen = g
	town = t
	clock = c
	nav = n
	props_root = pr
	map = m

	llm = LLM.new()
	llm.name = "LLM"
	add_child(llm)
	llm.plan_ready.connect(_on_plan_ready)
	llm.question_ready.connect(_on_question_ready)
	llm.failed.connect(_on_llm_failed)
	llm.answered.connect(_on_answered)
	llm.role_ready.connect(_on_role_ready)
	llm.status.connect(func(t2: String) -> void: status.emit(t2))
	# Everything the dispatcher says on a worker's behalf goes out through the
	# worker's own mouth. This signal was emitted and never connected in the
	# game itself — only the tests listened — so "I am in the middle of
	# something" and "there is nowhere left to put it" were never heard.
	spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		w.speak(line, kind))


## Whether the AI is answering for real or the offline library is standing in.
func ai_online() -> bool:
	return llm != null and llm.available()


func describe_ai() -> String:
	return llm.describe() if llm != null else "no AI layer"


func instruct(worker: Worker, instruction: String) -> void:
	# A question is not an order, and it does not matter how busy they are: a
	# worker halfway up a wall can still tell you what they are doing. This
	# comes before every guard below for exactly that reason.
	if Answers.is_question(instruction):
		_answer(worker, instruction)
		return

	# "Save" and "start over" are said to whoever is nearest. They are about
	# the game rather than the town, and they come first so that they work
	# whoever is asked, busy or not.
	if _try_game(worker, instruction):
		return

	# Taking somebody on, letting them go, or writing a job up. These are about
	# who works for you rather than what gets built, so they go before every
	# other guard: you can hire somebody who is standing about, and you can
	# define a job while the whole crew is busy.
	if _try_roles(worker, instruction):
		return

	# Somebody who does not work for you does not take your orders. They will
	# talk — the question path above still runs — and they will tell you how
	# to change that.
	if not worker.hired:
		spoke.emit(worker, "I do not work for you. Take me on and I might.", "talk")
		return

	if _open.has(worker.memory.worker_id):
		status.emit("%s is still thinking." % worker.display_name())
		return
	if worker.busy():
		spoke.emit(worker, "I am in the middle of something.", "refuse")
		return

	# "Wait here" and "follow me" are instructions like any other — the player
	# says them, so they go through the same text field as everything else
	# rather than becoming a key nobody would find (pillar P1).
	if _try_posting(worker, instruction):
		return

	# A new order replaces whatever this one was still holding out for.
	_forget_held(worker)

	# "Go and get some stone" does not need a model to understand it, and the
	# model costs the better part of a minute. This is the one keyword route
	# left, and it is a shortcut rather than a translation: it produces the same
	# gather step the model would have produced, and anything it is not certain
	# about it declines and lets the model have.
	#
	# The field and livestock routes that used to sit here are gone. They were
	# doing the model's job with a word list, which meant "fence the top corner
	# and put the hens in it" matched on "hens", went straight to the flock, and
	# the fence was never built or mentioned — the order was half-heard rather
	# than refused. Both are steps now, and a plan can hold them together.
	if _try_gather(worker, instruction):
		return
	if _try_war(worker, instruction):
		return

	var plot := _choose_plot(worker)
	if plot == null:
		spoke.emit(worker, "There is nowhere left to put it. Clear a plot first.",
			"refuse")
		return

	plot.reserved = true
	_open[worker.memory.worker_id] = {
		"worker": worker, "instruction": instruction, "plot": plot,
	}
	worker.speak("Right — let me think about that.", "talk")
	# Off you go. The plan will catch up on the way (§5.2): a free model takes
	# the better part of a minute, and none of that should be spent watching
	# somebody stand still — or, worse, watching them wander.
	worker.start_thinking(instruction, plot)
	llm.submit(instruction, worker.memory, plot, _ctx(worker), clock, town)


## Something the player wants to know rather than have done.
##
## The town's own records first, and the model only for what they cannot
## cover. The records are right every time and cost nothing; the model is
## right most of the time and costs a round trip, and for "how many bricks
## have we got" that is the wrong trade in both directions.
func _answer(worker: Worker, question: String) -> void:
	# About themselves first. "What do you do" has one right answer and the
	# role holds it; the records and the model are for everything else.
	var about := _answer_about_role(worker, question)
	if about != "":
		worker.speak(about, "talk")
		return
	var line := Answers.reply(question, worker, town, village, clock, player,
		farm, livestock, wildlife, warfare)
	worker.memory.remember(clock.day, "You asked me: \"%s\"" % question, 0.0, {
		"kind": "told", "question": question,
	})
	if line != "":
		worker.speak(line, "talk")
		return
	if llm != null and llm.available():
		worker.speak("Let me think.", "talk")
		llm.ask(question, worker.memory, _ctx(worker), clock, town)
		return
	worker.speak("I could not tell you, sorry.", "talk")


## What this person is for, in their own words, from the role.
func _answer_about_role(worker: Worker, question: String) -> String:
	var q := question.to_lower()
	var about_job := q.find("your job") >= 0 or q.find("what do you do") >= 0 		or q.find("what can you do") >= 0 or q.find("your role") >= 0 		or q.find("what are you for") >= 0 or q.find("who are you") >= 0 		or q.find("work for me") >= 0 or q.find("do you work") >= 0
	if not about_job:
		return ""
	var r := worker.role
	if r == null or not worker.hired:
		return "I live here. I do not work for anyone — take me on and give me a job, and I will."
	var can := r.ready_capabilities()
	var later := r.planned_capabilities()
	var line := "I am your %s. I can %s." % [r.name, _list_words(can)]
	if not later.is_empty():
		line += " The town has no means yet for me to %s." % _list_words(later)
	return line


static func _list_words(ids: Array) -> String:
	var words: Array[String] = []
	for id: Variant in ids:
		words.append(str(id).replace("_", " "))
	if words.size() <= 1:
		return "".join(words)
	var last: String = words.pop_back()
	return ", ".join(words) + " and " + last


func _on_answered(worker_id: String, text: String) -> void:
	var worker := crew.get_worker(worker_id) if crew != null else null
	if worker == null:
		return
	worker.speak(text, "talk")


# ------------------------------------------------------------------ fighting

const CRAFT_WORDS := ["make", "craft", "forge", "produce", "manufacture", "prepare",
	"load", "cast", "mould", "build", "assemble"]
const RECRUIT_WORDS := ["recruit", "enlist", "train", "raise", "hire", "muster", "conscript"]
const SOLDIER_WORDS := ["soldier", "soldiers", "men", "army", "militia", "guards",
	"troops", "company", "fighters"]
const ARM_WORDS := ["arm", "equip", "issue", "hand out", "give the men", "give them", "give everyone"]
const ATTACK_WORDS := ["attack", "charge", "fight", "engage", "kill", "drive off", "go after"]
const DEFEND_WORDS := ["defend", "guard", "protect", "hold", "watch"]
const RAID_WORDS := ["test the defences", "test the defenses", "sound the alarm",
	"drill", "call a raid", "simulate a raid"]
const TAKE_WORDS := ["give me", "hand me", "i want", "i will take", "i'll take",
	"pass me", "let me have"]


## Orders about the army, the armoury and the enemy. Keyword routes, like the
## errands: none of these needs a model to understand and all of them need to
## happen the moment they are said.
func _try_war(worker: Worker, instruction: String) -> bool:
	if warfare == null:
		return false
	var text := instruction.to_lower().strip_edges()
	var item := Arsenal.find_in(text)

	# "test the defences" — a raid, now.
	if _has_phrase(text, RAID_WORDS):
		warfare.raid(3 + warfare.soldiers.size() / 2)
		worker.speak("Here they come. To your posts!", "refuse")
		return true

	# "give me a rifle" — the player takes one.
	if _has_phrase(text, TAKE_WORDS) and item != "" and Arsenal.is_weapon(item):
		var r := warfare.arm_player(item)
		worker.speak(str(r["line"]), "talk" if r["ok"] else "refuse")
		return true

	# "recruit five soldiers"
	if _has_word(text, RECRUIT_WORDS) and _has_word(text, SOLDIER_WORDS):
		var n := _count_in(text, 3)
		var r2 := warfare.recruit(n)
		worker.speak(str(r2["line"]), "done" if r2["ok"] else "refuse")
		return true

	# "arm the men with rifles"
	if _has_phrase(text, ARM_WORDS) and item != "" and Arsenal.is_weapon(item):
		var r3 := warfare.arm_soldiers(item)
		worker.speak(str(r3["line"]), "done" if r3["ok"] else "refuse")
		return true

	# "attack the raiders"
	if _has_word(text, ATTACK_WORDS) and (_has_word(text, ["raiders", "raider", "them",
			"enemy", "bandits", "attackers", "invaders"]) or warfare.raiders.size() > 0):
		var r4 := warfare.attack()
		worker.speak(str(r4["line"]), "done" if r4["ok"] else "refuse")
		return true

	# "defend the well" / "guard the armoury" / "hold here"
	if _has_word(text, DEFEND_WORDS) and _has_word(text, ["well", "plaza", "square",
			"here", "armoury", "armory", "barracks", "town", "gate", "bakery", "store",
			"tavern", "me"]):
		var at := _defend_point(text, worker)
		var r5 := warfare.defend(at)
		worker.speak(str(r5["line"]), "done" if r5["ok"] else "refuse")
		return true

	# "make 40 shot" / "forge some rifles" / "load grenades"
	if item != "" and _has_word(text, CRAFT_WORDS) and not _has_word(text, ["armoury", "armory", "barracks"]):
		return _craft(worker, item, _count_in(text, int(Arsenal.item(item)["batch"])))

	return false


func _craft(worker: Worker, item: String, count: int) -> bool:
	var stand := warfare.armoury_stand()
	if stand == Vector3.INF:
		worker.speak("We have no armoury. Say \"build an armoury\" and I will put one up first.", "refuse")
		return true
	var batches := Arsenal.batches_for(item, count)
	var short := warfare.short_for(item, batches)
	if not short.is_empty():
		worker.speak("For %d %s I am short %s." % [
			batches * int(Arsenal.item(item)["batch"]), Arsenal.label(item),
			Resources.describe(short)], "refuse")
		return true
	if worker.busy():
		worker.speak("I am in the middle of something.", "refuse")
		return true
	var job := warfare.start_craft(item, count)
	var line := "%d %s — about %d hours at the armoury." % [
		job.made(), Arsenal.label(item), int(ceil(job.total_hours))]
	if not worker.take_craft_job(job, stand, line):
		# Give the materials back; the job never started.
		town.refund(Arsenal.bill(item, batches))
		worker.speak("I cannot get to the armoury from here.", "refuse")
	return true


func _defend_point(text: String, worker: Worker) -> Vector3:
	if _has_word(text, ["here", "me"]) and player != null:
		return player.global_position
	for key: String in ["armoury", "barracks", "bakery", "store", "tavern"]:
		if text.find(key) >= 0:
			for rec: Dictionary in town.buildings:
				if str(rec["archetype"]) == key:
					return warfare.stand_at(rec)
	return village.well_pos


func _has_phrase(text: String, phrases: Array) -> bool:
	for p: String in phrases:
		if text.find(p) >= 0:
			return true
	return false


## The first number in the sentence, or the default. "a dozen" is twelve.
func _count_in(text: String, fallback: int) -> int:
	if text.find("dozen") >= 0:
		return 12
	var words := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
		"seven": 7, "eight": 8, "nine": 9, "ten": 10, "twenty": 20, "thirty": 30,
		"fifty": 50, "hundred": 100}
	for w: String in text.split(" ", false):
		if w.is_valid_int():
			return clampi(int(w), 1, 500)
		if words.has(w):
			return int(words[w])
	return fallback


## The nearest free plot to the worker. The design has the player pointing at a
## plot eventually; until then, nearest-free is the choice a person would make.
func _choose_plot(worker: Worker) -> Plot:
	var best: Plot = null
	var best_d := INF
	for p: Plot in village.plots:
		if p.occupied_by >= 0 or p.reserved:
			continue
		var d := p.centre_m().distance_squared_to(worker.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _ctx(worker: Worker = null) -> Dictionary:
	var c := {
		"world": world, "village": village, "worldgen": gen,
		"tier": town.tier,
		"occupied_rects": town.occupied_rects,
		"built_fronts": town.built_fronts,
	}
	# The role travels with the order. It is what narrows the prompt to the
	# verbs this person may use and what the validator holds the plan to, so
	# a plan is never checked against a different job than it was made for.
	if worker != null and worker.role != null:
		c["role"] = worker.role
	return c


func _on_plan_ready(worker_id: String, plan: Dictionary) -> void:
	var job: Dictionary = _open.get(worker_id, {})
	if job.is_empty():
		return
	var worker: Worker = job["worker"]
	var plot: Plot = job["plot"]
	var assumptions: Array = plan.get("assumptions", [])
	var steps := Steps.normalise(plan)

	# Pre-validation, and all of it before anything starts. A plan that cannot
	# be carried out has to be refused before a single voxel is written, and
	# refused with a reason the worker can say — and for a plan with parts that
	# means checking the parts nobody has reached yet. Half an order carried out
	# and then refused would be the worst of both: it looks understood right up
	# until it stops.
	var err := Validator.check_plan(steps, plot, _ctx(worker))
	if not err.is_empty():
		_refuse(worker, plot, err)
		return

	_open.erase(worker_id)
	worker.stop_thinking()

	# Said once, up front, for the whole plan. The assumptions go up while the
	# worker walks away, which is what makes the result fair (pillar P3) — and
	# a second panel three steps later would just be the same list again.
	#
	# A plan with parts leads with its shape. An order that quietly became two
	# jobs is the player's business before it starts, not after they notice the
	# worker has walked off twice.
	if steps.size() > 1:
		var shape: Array[String] = []
		for s: Variant in steps:
			shape.append(Steps.describe(s as Dictionary))
		var counts: Array[String] = ["", "", "two", "three", "four"]
		var many: String = counts[mini(steps.size(), 4)]
		assumptions = ["I took that as %s jobs: %s." % [many,
			", then ".join(shape)]] + assumptions
	plan_accepted.emit(worker, assumptions)
	if str(plan.get("worker_line", "")) != "":
		worker.speak(str(plan["worker_line"]), "plan")

	var run := {
		"worker": worker, "steps": steps, "at": 0, "sites": {},
		"assumptions": assumptions, "plot": plot,
		"instruction": str(job.get("instruction", "")),
	}
	_running[worker_id] = run
	_advance(run)


# ------------------------------------------------------------------ the plan

## Carry out the next step, or finish.
##
## Every step ends in one of four places and the caller does not have to know
## which: the worker walked off with it, it was over the moment it started, the
## stores could not cover it, or it cannot be done at all. Only the last one
## ends the plan — an unaffordable step is held exactly as an unaffordable
## building always was, and the rest of the order is still coming.
func _advance(run: Dictionary) -> void:
	if run.get("abandoned", false):
		return
	var worker: Worker = run["worker"]
	if worker == null or not is_instance_valid(worker):
		return

	var at := int(run["at"])
	if at >= (run["steps"] as Array).size():
		_finish_run(run)
		return

	var step: Dictionary = (run["steps"] as Array)[at]
	match _run_step(run, step):
		"started":
			return                      # the worker has it; step_done will wake us
		"done":
			run["at"] = at + 1
			_advance(run)
		"held":
			return                      # _process retries it
		_:
			_abandon(run)


## One step, dispatched to whichever part of the town already does that work.
##
## The whole of the new machinery is this match. Every arm below calls something
## that existed before the plan had steps in it — a generator, a field, a
## quarry, a flock — because a verb is meant to be a name for work the town can
## already do, not a new way of doing work.
func _run_step(run: Dictionary, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"build":   return _step_build(run, step)
		"enclose": return _step_enclose(run, step)
		"stock":   return _step_stock(run, step)
		"sow":     return _step_sow(run, step)
		"gather":  return _step_gather(run, step)
		"go", "wait", "station", "patrol", "harvest", "collect", "rest", "speak", "scout":
			return _step_errand(run, step)
		"trade":      return _step_trade(run, step)
		"cook", "craft", "fish", "hunt":
			return _step_shift_with_yield(run, step)
		"water", "tend":
			return _step_land_care(run, step)
		"teach":      return _step_teach(run, step)
		"decorate":   return _step_decorate(run, step)
		"plant_tree", "pave", "level", "demolish":
			return _step_works(run, step)
		"delegate":   return _step_delegate(run, step)
		"recruit":    return _step_recruit(run, step)
		"report":     return _step_report(run, step)
		"follow":
			var w: Worker = run["worker"]
			if player != null:
				w.employer = player
			w.speak("Right behind you.", "talk")
			return "done"
	return "failed"


# ---------------------------------------------------------------- errands

## Every verb that is a walk with something at the end of it. The worker has
## one job for all of them; this only works out where, for how long, and what
## to say.
func _step_errand(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var verb := str(step["do"])
	var hours := float(step.get("hours", 0))
	var extra := {}
	var target := worker.global_position
	var where := "here"
	var line := ""

	match verb:
		"go":
			var place := _resolve_place(str(step["place"]), worker)
			if place.is_empty():
				return _refuse_step(run, "I do not know where %s is." % _place_name(str(step["place"])))
			target = place["pos"]
			where = str(place["where"])
			line = "Off to %s." % where
			_remember_site(run, step, {"centre": target, "spread": 3.0, "where": where})
		"wait":
			if step.has("place"):
				var place2 := _resolve_place(str(step["place"]), worker)
				if place2.is_empty():
					return _refuse_step(run, "I do not know where %s is." % _place_name(str(step["place"])))
				target = place2["pos"]
				where = str(place2["where"])
			# "Wait here" with no hours is the posting command, not a shift.
			if hours <= 0.0 and not step.has("place"):
				worker.employer = null
				worker.home = worker.global_position
				worker.speak("I will wait here, then.", "talk")
				return "done"
			var at_words := "here" if where == "here" else "at " + where
			var for_words := (" for %d hours" % int(hours)) if hours > 0 else ""
			line = "I will wait %s%s." % [at_words, for_words]
		"station":
			var place3 := _resolve_place(str(step["place"]), worker)
			if place3.is_empty():
				return _refuse_step(run, "There is no %s in this town to work at." % _place_name(str(step["place"])))
			target = place3["pos"]
			where = str(place3["where"])
			if hours <= 0.0:
				hours = 6.0
			extra["doing"] = str(step.get("doing", "hammer"))
			line = "I will take a %d hour shift at %s." % [int(hours), where]
			_remember_site(run, step, {"centre": target, "spread": 3.0, "where": where})
		"patrol":
			var legs: Array = []
			var names: Array[String] = []
			for pl: Variant in step.get("places", []):
				var place4 := _resolve_place(str(pl), worker)
				if place4.is_empty():
					return _refuse_step(run, "I do not know where %s is." % _place_name(str(pl)))
				legs.append(place4["pos"])
				names.append(str(place4["where"]))
			if hours <= 0.0:
				hours = 8.0
			where = " and ".join(names)
			line = "I will walk the round — %s — for %d hours." % [where, int(hours)]
			if not worker.take_errand_job("patrol", legs[0], hours, line,
					{"where": where}, legs):
				return "failed"
			return "started"
		"harvest":
			if farm == null or farm.tile_count() == 0:
				return _refuse_step(run, "There is no field to bring anything in from.")
			var rect := _field_rect(run, step)
			var c := rect.get_center()
			target = Vector3(c.x * VoxelChunk.VOXEL_M, 0.0, c.y * VoxelChunk.VOXEL_M)
			where = "the field"
			extra = {"farm": farm, "rect": rect}
			line = "I will see what is ripe."
		"collect":
			if livestock == null or livestock.total() == 0:
				return _refuse_step(run, "We have no animals to go round.")
			var site := _site_for(run, step, "in")
			target = site["centre"]
			where = str(site.get("where", "the pens"))
			extra = {"livestock": livestock,
				"radius": maxf(float(site["spread"]) + 6.0, 14.0)}
			line = "I will go round the animals."
		"rest":
			target = worker.home
			where = "home"
			if hours <= 0.0:
				hours = 4.0
			line = "I could do with a rest. Back in a few hours."
		"speak":
			extra["line"] = str(step["line"])
			if not worker.take_errand_job("speak", worker.global_position, 0.0, "", extra):
				return "failed"
			return "started"
		"scout":
			var dir := str(step["direction"])
			var dist := float(step.get("distance", 60))
			var d := Vector3.ZERO
			match dir:
				"north": d = Vector3(0, 0, -1)
				"south": d = Vector3(0, 0, 1)
				"east": d = Vector3(1, 0, 0)
				"west": d = Vector3(-1, 0, 0)
			var far := worker.global_position + d * dist
			target = nav.nearest_walkable_world(far, 20)
			if target == Vector3.ZERO:
				return _refuse_step(run, "There is no way out to the %s from here." % dir)
			where = "%d metres %s" % [int(dist), dir]
			extra["report"] = _describe_ground(target, dir)
			line = "I will have a look %s." % dir

	extra["where"] = where
	if not worker.take_errand_job(verb, target, hours, line, extra):
		return "failed"
	return "started"


# ---------------------------------------------------------- trades and works

func _step_trade(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var action := str(step.get("action", "sell"))
	var kind := str(step.get("kind", ""))
	var count := int(step.get("count", 0))
	if count <= 0:
		count = 20 if action == "sell" else 10
	# The market is the store if there is one, and the square if there is not.
	var place := _resolve_place("store", worker)
	if place.is_empty():
		place = _resolve_place("square", worker)
	var line := "I will %s %d %s at %s." % [action, count, kind.replace("_", " "), str(place["where"])]
	if not worker.take_errand_job("trade", place["pos"], 0.0, line, {
			"town": town, "action": action, "kind": kind, "count": count,
			"where": str(place["where"])}):
		return "failed"
	return "started"


## Cooking, crafting, fishing and hunting: a shift somewhere with something
## in the stores at the end of it.
func _step_shift_with_yield(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var verb := str(step["do"])
	var hours := float(step.get("hours", 0))
	if hours <= 0.0:
		hours = 4.0
	var extra := {"town": town}
	var target := Vector3.ZERO
	var where := ""
	var line := ""
	match verb:
		"cook":
			var at := _building_with(["oven", "hearth"], str(step.get("place", "")), worker)
			if at.is_empty():
				return _refuse_step(run, "There is no oven in this town to cook at.")
			target = at["pos"]
			where = str(at["where"])
			extra["inputs"] = {"food": 3}
			extra["outputs"] = {"meals": 2}
			extra["batches"] = int(hours / 2.0)
			extra["doing"] = "lay"
			line = "I will get the oven going at %s — %d hours." % [where, int(hours)]
		"craft":
			var at2 := _building_with(["workbench", "forge"], str(step.get("place", "")), worker)
			if at2.is_empty():
				return _refuse_step(run, "There is no bench in this town to work at.")
			target = at2["pos"]
			where = str(at2["where"])
			extra["inputs"] = {"timber": 4, "plank": 2}
			extra["outputs"] = {"tools": 2}
			extra["batches"] = int(hours / 2.0)
			extra["doing"] = "hammer"
			line = "I will make what I can at %s — %d hours." % [where, int(hours)]
		"fish":
			target = _nearest_ground_of([VoxelTypes.WATER], worker.global_position, true)
			if target == Vector3.ZERO:
				return _refuse_step(run, "There is no water within reach to fish.")
			where = "the water's edge"
			extra["food"] = int(hours * 2.0)
			extra["doing"] = "survey"
			line = "I will try the water for %d hours." % int(hours)
		"hunt":
			target = _nearest_ground_of([VoxelTypes.LEAF, VoxelTypes.BARK], worker.global_position, false)
			if target == Vector3.ZERO:
				return _refuse_step(run, "There are no woods within reach to hunt.")
			where = "the woods"
			extra["food"] = int(hours * 3.0)
			extra["doing"] = "survey"
			line = "I will see what the woods have — %d hours." % int(hours)
	extra["where"] = where
	if not worker.take_errand_job(verb, target, hours, line, extra):
		return "failed"
	return "started"


func _step_land_care(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var verb := str(step["do"])
	if verb == "water":
		if farm == null or farm.tile_count() == 0:
			return _refuse_step(run, "There is no field to water.")
		var rect := _field_rect(run, step)
		var c := rect.get_center()
		var target := Vector3(c.x * VoxelChunk.VOXEL_M, 0.0, c.y * VoxelChunk.VOXEL_M)
		if not worker.take_errand_job("water", target, 0.0, "I will water the field.",
				{"farm": farm, "rect": rect, "where": "the field"}):
			return "failed"
		return "started"
	if livestock == null or livestock.total() == 0:
		return _refuse_step(run, "We have no animals to see to.")
	var site := _site_for(run, step, "in")
	if not worker.take_errand_job("tend", site["centre"], 0.0, "I will see to the animals.",
			{"livestock": livestock, "radius": maxf(float(site["spread"]) + 6.0, 14.0),
				"where": str(site.get("where", "the pens"))}):
		return "failed"
	return "started"


func _step_teach(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var pupil := _worker_named(str(step.get("who", "")))
	if pupil == null or not pupil.hired:
		return _refuse_step(run, "There is nobody working for you called %s." % str(step.get("who", "")).capitalize())
	if pupil == worker:
		return _refuse_step(run, "I cannot teach myself.")
	var skill := str(step.get("skill", "carpentry"))
	var hours := float(step.get("hours", 0))
	if hours <= 0.0:
		hours = 3.0
	var line := "I will take %s through some %s — %d hours." % [pupil.display_name(), skill, int(hours)]
	if not worker.take_errand_job("teach", pupil.global_position, hours, line, {
			"pupil": pupil, "skill": skill, "where": "with " + pupil.display_name()}):
		return "failed"
	return "started"


func _step_decorate(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var rec := _building_rec(str(step.get("place", "")), worker)
	if rec.is_empty():
		return _refuse_step(run, "There is no %s to dress up." % _place_name(str(step.get("place", ""))))
	var n := clampi(int(step.get("count", 4)), 1, 8)
	var spots := _front_spots(rec, n)
	var place := _resolve_place(str(step.get("place", "")), worker)
	if not worker.take_errand_job("decorate", place["pos"], 0.0,
			"I will smarten up the front of %s." % str(place["where"]), {
			"props_root": props_root, "spots": spots, "where": str(place["where"])}):
		return "failed"
	return "started"


## Trees, roads, levelling and demolition: all patches, all handled by the
## same construction the buildings use.
func _step_works(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var verb := str(step["do"])
	var res := {}
	var where := ""
	var after := Callable()
	var seed := hash(worker.memory.worker_id + str(clock.day) + str(clock.hour)) & 0x7FFFFFFF
	match verb:
		"plant_tree":
			# "place" is either an earlier step's id or the name of somewhere;
			# with neither, the trees go in near the worker.
			var site := _site_for(run, step, "place")
			if step.has("place") and not (run["sites"] as Dictionary).has(str(step["place"])):
				var place := _resolve_place(str(step["place"]), worker)
				if place.is_empty():
					return _refuse_step(run, "I do not know where %s is." % _place_name(str(step["place"])))
				site = {"centre": place["pos"], "where": str(place["where"])}
			var count := clampi(int(step.get("count", 1)), 1, 12)
			res = TerrainWorks.trees(world, site["centre"], count, seed, _avoid_rects())
			where = "by " + str(site.get("where", "the town"))
		"pave":
			var a := _resolve_place(str(step["from"]), worker)
			var b := _resolve_place(str(step["to"]), worker)
			if a.is_empty() or b.is_empty():
				return _refuse_step(run, "I do not know both of those places.")
			var mat_name := str(step.get("material", "cobble"))
			var mat := VoxelTypes.id_of(mat_name)
			if mat < 0:
				return _refuse_step(run, "I cannot lay a road in %s." % mat_name)
			var width := clampi(int(step.get("width", 3)), 1, 6)
			res = TerrainWorks.road(world, a["pos"], b["pos"], mat,
				int(width / VoxelChunk.VOXEL_M), town.occupied_rects)
			where = "from %s to %s" % [str(a["where"]), str(b["where"])]
		"level":
			var centre := worker.global_position
			where = "here"
			if step.has("place"):
				var place2 := _resolve_place(str(step["place"]), worker)
				if place2.is_empty():
					return _refuse_step(run, "I do not know where %s is." % _place_name(str(step["place"])))
				centre = place2["pos"]
				where = "at " + str(place2["where"])
			var size_m := 8
			if step.has("size"):
				size_m = clampi(int((step["size"] as Array)[0]), 3, 24)
			var sv := int(size_m / VoxelChunk.VOXEL_M)
			var cv := VoxelWorld.to_voxel(centre)
			var rect := Rect2i(cv.x - sv / 2, cv.z - sv / 2, sv, sv)
			res = TerrainWorks.flatten(world, rect, -1, _avoid_rects())
			if res["ok"]:
				var r2 := rect
				_remember_site(run, step, {"centre": centre, "spread": size_m * 0.4,
					"where": "the levelled ground", "rect": r2})
		"demolish":
			var rec := _building_rec(str(step["place"]), worker)
			if rec.is_empty():
				return _refuse_step(run, "There is no %s to take down." % _place_name(str(step["place"])))
			res = TerrainWorks.demolition(rec)
			where = "the " + str(rec["archetype"]).replace("_", " ")
			var plot := _plot_of(int(rec.get("plot_id", -1)))
			var salvage := TerrainWorks.salvage(rec)
			# The register and the refund wait for the last voxel to go.
			after = func() -> void:
				_clear_props_in((rec["patch"] as VoxelPatch))
				if plot != null:
					town.unregister(rec, plot)
					plot.reserved = false
				town.refund(salvage)
				worker.speak("%s is down. Salvaged %s." % [where.capitalize(),
					Resources.describe(salvage) if not salvage.is_empty() else "nothing worth keeping"],
					"done")

	if not res.get("ok", false):
		return _refuse_step(run, str((res.get("error", {}) as Dictionary).get("question",
			"I could not do that there.")))
	var patch: VoxelPatch = res["patch"]
	var ready := {
		"kind": verb, "run": run, "worker": worker, "plot": null,
		"patch": patch, "assumptions": run["assumptions"], "where": where, "line": "",
	}
	if after.is_valid():
		run["after"] = after
	if not _begin(ready):
		_held.append(ready)
		return "held"
	return "started"


# ----------------------------------------------------------- running things

## A foreman: hands an order to another hired person. The order goes through
## instruct() like anything the player says, so it is planned, validated and
## refused exactly as if the player had said it — a foreman cannot get a
## shepherd to build a tavern any more than you can.
func _step_delegate(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var who := str(step.get("who", ""))
	var target := _worker_named(who)
	if target == null or not target.hired:
		return _refuse_step(run, "There is nobody working for you called %s." % who.capitalize())
	if target == worker:
		return _refuse_step(run, "I cannot give myself orders.")
	var order := str(step.get("order", "")).strip_edges()
	if order == "":
		return _refuse_step(run, "Tell %s what?" % target.display_name())
	worker.speak("%s — %s." % [target.display_name(), order], "talk")
	instruct(target, order)
	return "done"


## A recruiter: takes somebody from the street on as a job, on your behalf.
func _step_recruit(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var role_name := str(step.get("role", "")).strip_edges()
	if role_name == "":
		return _refuse_step(run, "Take somebody on as what?")
	var target: Worker = null
	if step.has("who") and str(step["who"]).strip_edges() != "":
		target = _worker_named(str(step["who"]))
		if target == null:
			return _refuse_step(run, "There is nobody here called %s." % str(step["who"]).capitalize())
	else:
		var free := crew.citizens()
		if free.is_empty():
			return _refuse_step(run, "There is nobody left in the town to take on.")
		# The nearest, so the person hired is one you can see.
		var best_d := INF
		for c: Worker in free:
			var d := c.global_position.distance_squared_to(worker.global_position)
			if d < best_d:
				best_d = d
				target = c
	worker.speak("I will have a word with %s." % target.display_name(), "talk")
	_hire_as(target, role_name, "", worker)
	return "done"


## An accountant: the state of the town, said out loud with the real numbers.
func _step_report(run: Dictionary, _step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var lines: Array[String] = []
	lines.append("The purse holds %d coins." % town.coins)
	lines.append(town.stock_line())
	lines.append("%d buildings, tier %d, %d of us working." % [town.buildings.size(),
		town.tier, crew.hired().size()])
	if livestock != null and livestock.total() > 0:
		lines.append("%d animals." % livestock.total())
	if farm != null and farm.tile_count() > 0:
		lines.append("%d tiles under crop, %d ripe." % [farm.planted_count(), farm.ripe_count()])
	return _step_errand(run, {"do": "speak", "line": " ".join(lines)})


# ------------------------------------------------------------------ lookups

## A building record by what it is or where it is, nearest first.
func _building_rec(name: String, worker: Worker) -> Dictionary:
	var p := name.strip_edges().to_lower().trim_prefix("the ").trim_prefix("a ")
	var best: Dictionary = {}
	var best_d := INF
	for rec: Dictionary in town.buildings:
		var arch := str(rec["archetype"]).replace("_", " ")
		var street := str(rec.get("street", "")).to_lower()
		if not (p == arch or p == arch + "s" or p.find(arch) >= 0 \
				or (street != "" and p.find(street) >= 0)):
			continue
		var patch: VoxelPatch = rec["patch"]
		var c := patch.footprint.get_center()
		var d := Vector2(c.x * VoxelChunk.VOXEL_M, c.y * VoxelChunk.VOXEL_M) \
			.distance_squared_to(Vector2(worker.global_position.x, worker.global_position.z))
		if d < best_d:
			best_d = d
			best = rec
	return best


## The nearest building with one of these modules in it, or the named one if
## a name was given. Returns {pos, where} like _resolve_place.
func _building_with(modules: Array, named: String, worker: Worker) -> Dictionary:
	if named.strip_edges() != "":
		return _resolve_place(named, worker)
	var best: Dictionary = {}
	var best_d := INF
	for rec: Dictionary in town.buildings:
		var patch: VoxelPatch = rec["patch"]
		var has := false
		for m: Dictionary in patch.modules:
			if str(m.get("type", "")) in modules:
				has = true
				break
		if not has:
			continue
		var c := patch.footprint.get_center()
		var d := Vector2(c.x * VoxelChunk.VOXEL_M, c.y * VoxelChunk.VOXEL_M) \
			.distance_squared_to(Vector2(worker.global_position.x, worker.global_position.z))
		if d < best_d:
			best_d = d
			best = rec
	if best.is_empty():
		return {}
	return _resolve_place(str(best["archetype"]).replace("_", " "), worker)


## Ground of a given kind nearest a point: water for fishing, trees for
## hunting. Rings out to the edge of the nav grid; the spot returned is the
## walkable cell beside it, not the water itself.
func _nearest_ground_of(tops: Array, from: Vector3, beside: bool) -> Vector3:
	var c := VoxelWorld.to_voxel(from)
	for radius in range(4, 200, 4):
		for dz in range(-radius, radius + 1, 4):
			for dx in range(-radius, radius + 1, 4):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var x := c.x + dx
				var z := c.z + dz
				var h := world.height_at(x, z)
				if h < 0:
					continue
				var top := world.get_voxel(Vector3i(x, h, z))
				if top not in tops:
					continue
				var at := Vector3(x * VoxelChunk.VOXEL_M, 0.0, z * VoxelChunk.VOXEL_M)
				var stand := nav.nearest_walkable_world(at, 12) if beside else at
				if stand != Vector3.ZERO:
					return stand
	return Vector3.ZERO


## Places along the front of a building, a pace out from the wall, for
## whatever is being put there.
func _front_spots(rec: Dictionary, n: int) -> Array:
	var patch: VoxelPatch = rec["patch"]
	var v := VoxelChunk.VOXEL_M
	var fp := patch.footprint
	var front := Vector3(patch.front)
	var out: Array = []
	var along := Vector3(-front.z, 0.0, front.x)
	var centre := Vector3((fp.position.x + fp.size.x * 0.5) * v, 0.0,
		(fp.position.y + fp.size.y * 0.5) * v)
	var half := (fp.size.x if absi(patch.front.z) > 0 else fp.size.y) * v * 0.5
	var edge := centre + front * (half + 0.9)
	var span := half * 0.8
	for i in n:
		var t := -span + (2.0 * span) * (float(i) + 0.5) / float(n)
		var at := edge + along * t
		# Not in the doorway.
		if not patch.doors.is_empty():
			var door := Vector3(patch.doors[0]) * v
			if Vector2(at.x - door.x, at.z - door.z).length() < 1.2:
				continue
		at.y = world.ground_m(at.x, at.z)
		out.append(at)
	return out


func _plot_of(plot_id: int) -> Plot:
	for p: Plot in village.plots:
		if p.id == plot_id:
			return p
	return null


## Free the furniture standing inside a building's box. The props were never
## kept against the building they went in, so this is the only way to find
## them: anything under props_root whose feet are inside the footprint.
func _clear_props_in(patch: VoxelPatch) -> void:
	if props_root == null:
		return
	var v := VoxelChunk.VOXEL_M
	var fp := patch.footprint
	var y0 := patch.origin.y * v - 0.5
	var y1 := (patch.origin.y + patch.size.y) * v + 0.5
	for n: Node in props_root.get_children():
		if not (n is Node3D):
			continue
		var at := (n as Node3D).global_position
		var vx := floori(at.x / v)
		var vz := floori(at.z / v)
		if fp.has_point(Vector2i(vx, vz)) and at.y >= y0 and at.y <= y1:
			n.queue_free()


## A refusal from inside a step: the worker says it, and the plan ends.
func _refuse_step(run: Dictionary, line: String) -> String:
	var worker: Worker = run["worker"]
	worker.speak(line, "refuse")
	refused.emit(worker, Validator.error("no_such_place", line))
	return "failed"


## The field a harvest is about: the one a step in this plan sowed, if it
## names it, otherwise every field in the town at once.
func _field_rect(run: Dictionary, step: Dictionary) -> Rect2i:
	var site := _site_for(run, step, "in")
	if site.has("rect"):
		return site["rect"]
	return _all_fields()


func _all_fields() -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for k: Vector2i in farm.tiles:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
	if lo.x > hi.x:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## A place, by the words a player uses for it.
##
## Buildings by what they are ("the bakery") or where they are ("the one on
## Mill Street"); the well, the field and home by name; "you" and "here" are
## wherever the player is standing. Returns {} for a place the town has not
## got, which the worker says out loud rather than walking to the origin.
func _resolve_place(name: String, worker: Worker) -> Dictionary:
	var p := name.strip_edges().to_lower().trim_prefix("the ").trim_prefix("a ")
	var v := VoxelChunk.VOXEL_M
	match p:
		"you", "here", "me", "player":
			var at := player.global_position if player != null else worker.global_position
			return {"pos": at, "where": "where you are"}
		"home":
			return {"pos": worker.home, "where": "home"}
		"well":
			return {"pos": village.well_pos, "where": "the well"}
		"field", "fields", "farm":
			if farm == null or farm.tile_count() == 0:
				return {}
			var r := _all_fields()
			var c := r.get_center()
			return {"pos": Vector3(c.x * v, 0.0, c.y * v), "where": "the field"}
		"gate", "edge", "town edge":
			# The end of the last street: as far out as the town goes.
			var far := village.well_pos + Vector3(0, 0, 40)
			return {"pos": nav.nearest_walkable_world(far, 20), "where": "the edge of town"}
		"square", "plaza", "middle", "centre", "center":
			return {"pos": village.well_pos, "where": "the square"}

	# A building. By archetype first — "bakery", "the tavern" — and by street
	# if nothing matched, so "the one on Mill Street" finds something.
	var best: Dictionary = {}
	var best_d := INF
	for rec: Dictionary in town.buildings:
		var arch := str(rec["archetype"]).replace("_", " ")
		var street := str(rec.get("street", "")).to_lower()
		var hit := p == arch or p == arch + "s" or p.find(arch) >= 0 \
			or (street != "" and p.find(street) >= 0)
		if not hit:
			continue
		var patch: VoxelPatch = rec["patch"]
		var door := Vector3i(patch.footprint.get_center().x, 0, patch.footprint.get_center().y)
		if not patch.doors.is_empty():
			door = patch.doors[0]
		# Stand a pace outside the door, not in it.
		var front := Vector3(patch.front)
		var pos := Vector3(door.x * v, 0.0, door.z * v) + front * 1.2
		var d := pos.distance_squared_to(worker.global_position)
		if d < best_d:
			best_d = d
			best = {"pos": pos, "where": "the " + arch}
	return best


## "the bakery" from "bakery" or "the_bakery", for saying out loud.
static func _place_name(raw: String) -> String:
	var p := raw.strip_edges().to_lower().replace("_", " ")
	return p if p.begins_with("the ") else "the " + p


## What a scout reports from where they end up: the lie of the land in a few
## words, from the same terrain the generator reads.
func _describe_ground(at: Vector3, dir: String) -> String:
	var v := VoxelChunk.VOXEL_M
	var cx := int(at.x / v)
	var cz := int(at.z / v)
	var water := 0
	var lo := 1 << 30
	var hi := -(1 << 30)
	var trees := 0
	var n := 0
	for dz in range(-12, 13, 3):
		for dx in range(-12, 13, 3):
			var h := world.height_at(cx + dx, cz + dz)
			if h < 0:
				continue
			n += 1
			lo = mini(lo, h)
			hi = maxi(hi, h)
			var top := world.get_voxel(Vector3i(cx + dx, h, cz + dz))
			if top == VoxelTypes.WATER:
				water += 1
			elif top == VoxelTypes.LEAF or top == VoxelTypes.BARK:
				trees += 1
	if n == 0:
		return "Nothing out %s but the edge of the world." % dir
	var parts: Array[String] = []
	if water > n / 4:
		parts.append("there is water")
	if trees > n / 4:
		parts.append("it is wooded")
	if hi - lo <= 3:
		parts.append("the ground is flat")
	elif hi - lo > 12:
		parts.append("it climbs steeply")
	else:
		parts.append("it rises a little")
	return "Out %s: %s." % [dir, ", ".join(parts)]


## Where a referenced step left its ground, or the player's feet if the step
## named nothing. "here" is not a failure to be specific: most orders are given
## while standing in the place they are about, and that is the whole reason the
## crew follows you around.
func _site_for(run: Dictionary, step: Dictionary, field: String) -> Dictionary:
	var id := str(step.get(field, ""))
	var sites: Dictionary = run["sites"]
	if id != "" and id != "here" and sites.has(id):
		return sites[id]
	var worker: Worker = run["worker"]
	var near := worker.global_position if player == null else player.global_position
	return {"centre": near, "spread": 9.0, "where": "where you were standing"}


func _finish_run(run: Dictionary) -> void:
	var worker: Worker = run["worker"]
	_running.erase(worker.memory.worker_id)
	# A plot reserved for a plan that turned out to be all fences and hens is a
	# plot nobody can build on for the rest of the game.
	var plot: Plot = run["plot"]
	if plot != null and plot.occupied_by < 0:
		plot.reserved = false


func _abandon(run: Dictionary) -> void:
	run["abandoned"] = true
	_finish_run(run)


## A worker's hands are free. If they were in the middle of a plan, the next
## step of it starts.
##
## Deferred, because a step can finish inside the call that started it — an
## errand for hens given while standing on the spot has no walk in it — and
## advancing the plan from inside its own dispatch would run two steps into
## each other.
func _on_step_done(worker: Worker) -> void:
	var run: Dictionary = _running.get(worker.memory.worker_id, {})
	if run.is_empty():
		return                          # a one-off errand, not part of a plan
	# Some steps have a piece of bookkeeping that belongs to the moment the
	# work is finished, not the moment it was started — a demolished building
	# leaves the register when the last voxel is gone, not when the worker
	# sets off with a hammer.
	if run.has("after"):
		var after: Callable = run["after"]
		run.erase("after")
		after.call()
	run["at"] = int(run["at"]) + 1
	_advance.call_deferred(run)


## The worker could not do the step they had taken. They have already said so
## out loud, so this only has to stop the rest of the plan waiting on them.
func _on_step_failed(worker: Worker, _err: Dictionary) -> void:
	var run: Dictionary = _running.get(worker.memory.worker_id, {})
	if not run.is_empty():
		_abandon(run)


# ------------------------------------------------------------------ the steps

func _step_build(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var plot: Plot = run["plot"]
	var spec: Dictionary = step.get("spec", {})
	var res := BuildingGenerator.build(spec,
		hash(worker.memory.worker_id) & 0x7FFFFFFF, plot, _ctx())
	if not res["ok"]:
		_refuse(worker, plot, res["error"])
		return "failed"

	var patch: VoxelPatch = res["patch"]
	var ready := {
		"kind": "build", "run": run, "worker": worker, "plot": plot,
		"spec": spec, "patch": patch, "assumptions": run["assumptions"],
		"line": "",
	}
	if not _begin(ready):
		_held.append(ready)
		return "held"
	_remember_site(run, step, {
		"centre": plot.centre_m(), "spread": 4.0, "where": plot.street_name,
	})
	return "started"


func _step_enclose(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var anchor := _site_for(run, step, "near")
	var size: Array = step["size"]
	var want := Vector2i(
		int(round(float(size[0]) / VoxelChunk.VOXEL_M)),
		int(round(float(size[1]) / VoxelChunk.VOXEL_M)))

	# A pen goes on open ground, never on a plot. That is partly so it does not
	# eat somewhere a building could stand, and partly because it is where a pen
	# belongs: behind the town, not on the high street.
	var site := EnclosureGenerator.find_site(world, anchor["centre"], want,
		_avoid_rects())
	var res := EnclosureGenerator.build(step, world, site, _ctx())
	if not res["ok"]:
		worker.ask_player(str((res["error"] as Dictionary).get("question",
			"I could not put a fence there.")))
		refused.emit(worker, res["error"])
		return "failed"

	var patch: VoxelPatch = res["patch"]
	var inside := EnclosureGenerator.inside_of(site, world)
	var ready := {
		"kind": "enclose", "run": run, "worker": worker, "plot": null,
		"patch": patch, "assumptions": run["assumptions"],
		"where": "out past the town", "line": "",
	}
	if not _begin(ready):
		_held.append(ready)
		return "held"
	_remember_site(run, step, {
		"centre": inside["centre"], "spread": inside["spread"],
		"where": "in the pen", "rect": site,
	})
	return "started"


func _step_stock(run: Dictionary, step: Dictionary) -> String:
	if livestock == null:
		return "failed"
	var worker: Worker = run["worker"]
	var species := str(step["species"])
	var target := _site_for(run, step, "into")
	var count := int(step.get("count", 0))
	if count <= 0:
		count = 6 if species == "hen" else 4

	# The pen decides how many will fit, not the order. Six hens in a three by
	# three is not six hens, it is a crate.
	#
	# Spread is the radius they may drift over, so the room is its circle at
	# roughly two square metres an animal. Squaring the radius and calling that
	# the area put six hens in an eight by six pen at two of them, which looked
	# like the order being ignored rather than the pen being full.
	var spread := maxf(float(target["spread"]), 0.6)
	var room := int(PI * spread * spread * 0.5)
	count = clampi(count, 1, maxi(room, 1))

	var line := "I will go and fetch %d %s." % [count, Steps.plural(species, count)]
	if not worker.take_stock_job(livestock, species, count, target["centre"],
			float(target["spread"]), str(target["where"]), line):
		return "failed"
	return "started"


func _step_sow(run: Dictionary, step: Dictionary) -> String:
	if farm == null:
		return "failed"
	var worker: Worker = run["worker"]
	var crop := str(step.get("crop", "wheat"))
	var anchor := _site_for(run, step, "in")

	var side := 20                        ## voxels — 5 m square, the usual field
	if step.has("size"):
		var size: Array = step["size"]
		side = int(round(float(size[0]) / VoxelChunk.VOXEL_M))
	var found := farm.find_field(anchor["centre"], Vector2i(side, side))
	if found.is_empty():
		worker.ask_player("There is no flat open ground near here for a field. "
			+ "Where would you like it?")
		return "failed"

	var rect: Rect2i = found["rect"]
	_remember_site(run, step, {
		"centre": Vector3(rect.get_center().x * VoxelChunk.VOXEL_M,
			world.ground_m(rect.get_center().x * VoxelChunk.VOXEL_M,
				rect.get_center().y * VoxelChunk.VOXEL_M),
			rect.get_center().y * VoxelChunk.VOXEL_M),
		"spread": float(mini(rect.size.x, rect.size.y)) * VoxelChunk.VOXEL_M * 0.4,
		"where": "on the new field", "rect": rect,
	})
	worker.take_field_job(FieldWork.new(farm, rect, crop), run["assumptions"],
		"Right — %s it is." % crop)
	return "started"


func _step_gather(run: Dictionary, step: Dictionary) -> String:
	var worker: Worker = run["worker"]
	var mat := str(step["material"])
	var units := int(step.get("units", 0))
	if units <= 0:
		units = 240
	if not _dig(worker, mat, units):
		return "failed"
	return "started"


func _remember_site(run: Dictionary, step: Dictionary, site: Dictionary) -> void:
	var id := str(step.get("id", ""))
	if id == "":
		return
	(run["sites"] as Dictionary)[id] = site


## Ground a pen must not be put on: every building already standing, and every
## plot, taken or not, because a plot is where a building is going to stand.
func _avoid_rects() -> Array:
	var out: Array = []
	for r: Rect2i in town.occupied_rects:
		out.append(r)
	if village != null:
		for p: Plot in village.plots:
			out.append(p.rect_v())
	return out


# ---------------------------------------------------------------- the stores

## Everything between a finished plan and a worker walking off with it.
##
## The check that matters is the first one. A plan is not a job until the stores
## can pay for it, because the alternative — starting a wall the town cannot
## finish — is the worst failure this game can have: it looks like progress for
## an hour and then stops halfway up, with nothing to tell the player why.
##
## So the bill is settled before the first voxel, out loud, and a plan that
## cannot be paid for is held rather than refused. Held, because the answer is
## not "no": the answer is "not until somebody fetches the stone", and fetching
## the stone is a job like any other.
##
## Returns false when the plan is being held; the caller keeps it.
func _begin(job: Dictionary) -> bool:
	var worker: Worker = job["worker"]
	var patch: VoxelPatch = job["patch"]
	var bill := Resources.bill(patch.cost)

	if not town.can_afford(bill):
		var missing := Resources.shortfall(bill, town.stock)
		var wanted := Resources.describe(missing)
		# Said once, not once a second: the shortfall only changes when somebody
		# comes back with something.
		var already := worker.waiting_for == wanted
		worker.waiting_for = wanted
		if not already:
			worker.speak("We have not got the material — I am short %s. "
				% wanted + "I will hold here until it comes in.", "refuse")
			short_of.emit(worker, missing)
		# Sent every time, though. The first errand can come up short — a seam
		# runs out, the only free hand was already busy — and a town that asked
		# once and then waited forever would just be a hang with dialogue.
		_send_for(missing, worker, not already)
		return false

	# Paid for at the start of the work, not at the end of it. A half-built
	# house has already consumed its timber.
	town.spend(bill)
	worker.waiting_for = ""

	# Nobody paths through a building site. A pen is a building site too — the
	# posts are solid, and a worker who pathed through where the fence is going
	# would walk out through it once it was there.
	nav.refresh_world_rect(patch.footprint, 3)

	# A fence and a house are the same job to everything above this line. They
	# part company only here, and only because one of them has a plot.
	var took := false
	if str(job.get("kind", "build")) != "build":
		# Anything with no plot: a fence, a road, a grove, a cut, a demolition.
		took = worker.take_enclosure_job(patch, str(job.get("where", "the town")),
			job["assumptions"], str(job["line"]), props_root)
	else:
		took = worker.take_job(job["plot"], job["spec"], patch, job["assumptions"],
			str(job["line"]), props_root)
	if not took:
		# The route was there when the plan was made and is not there now. The
		# worker has already said so; the town gets its material back, because
		# a bill for a house that was never started is just a leak.
		town.refund(bill)
		if job.get("plot", null) != null:
			(job["plot"] as Plot).reserved = false
		return true
	if map != null:
		map.note_building(patch, patch.archetype if patch.archetype != ""
			else str((job.get("spec", {}) as Dictionary).get("archetype", "building")))
	return true


## Send somebody out for what is missing.
##
## One errand at a time, and never the worker who is waiting on the delivery:
## the point of having three of them is that one can stand at the plot with the
## plan while another walks to the hillside, which is the shape of delegation
## the whole game is about.
func _send_for(missing: Dictionary, asker: Worker, announce: bool) -> void:
	for mat: String in missing:
		if not Resources.gatherable(mat):
			continue
		if _already_fetching(mat):
			continue
		var hand := _free_hand(asker)
		if hand == null:
			if announce:
				status.emit("Nobody free to fetch %s yet." % mat.replace("_", " "))
			return
		_dig(hand, mat, int(missing[mat]), announce)


func _already_fetching(mat: String) -> bool:
	if crew == null:
		return false
	for w: Worker in crew.workers:
		if w.job_quarry != null and w.job_quarry.material == mat:
			return true
	return false


## An idle worker who is not the one holding the plan.
func _free_hand(exclude: Worker) -> Worker:
	if crew == null:
		return null
	for w: Worker in crew.workers:
		if w == exclude or w.busy() or w.waiting_for != "":
			continue
		if _open.has(w.memory.worker_id):
			continue
		return w
	return null


## The errand itself. The site is a real place in the world with real voxels of
## the right kind in it, so the hole they leave is where the material came from.
##
## `announce` is false when a held plan is quietly having another go, because
## the retry runs on a timer and a worker who said "I cannot find any iron"
## every second and a half would be worse than one who said nothing.
func _dig(worker: Worker, mat: String, units: int, announce: bool = true) -> bool:
	var near := worker.global_position
	var site := Quarry.find_site(world, village, mat, near, nav.bounds_v())
	if site == Vector3i.ZERO:
		if announce:
			worker.speak("I cannot find any %s within reach of the town."
				% mat.replace("_", " "), "refuse")
		return false

	# A margin, so the next order does not send them straight back out.
	var q := Quarry.new(world, town, mat, int(units * 1.5) + 8, site)
	if q.total() == 0:
		if announce:
			worker.speak("There is no %s left in that seam."
				% mat.replace("_", " "), "refuse")
		return false

	var where := Resources.place_of(Resources.source_of(mat))
	var line := "I will go to %s for the %s." % [where, mat.replace("_", " ")]
	if not worker.take_quarry_job(q, line):
		if announce:
			worker.speak("I cannot get out to %s from here." % where, "refuse")
		return false
	status.emit("%s is off to %s for %s." % [worker.display_name(), where,
		mat.replace("_", " ")])
	return true


## Held plans wake up on their own the moment the stores can cover them. Nobody
## has to be told twice, and the player does not have to remember to re-ask.
func _process(delta: float) -> void:
	if _held.is_empty():
		return
	# Once and a half a second is often enough to feel immediate and rare
	# enough that a town waiting on a two-day errand is not re-costing a
	# building sixty times a second.
	_retry -= delta
	if _retry > 0.0:
		return
	_retry = 1.5
	for i in range(_held.size() - 1, -1, -1):
		var job: Dictionary = _held[i]
		var worker: Worker = job["worker"]
		if worker == null or not is_instance_valid(worker):
			_held.remove_at(i)
			continue
		if worker.busy():
			continue
		var run: Dictionary = job.get("run", {})
		if run.get("abandoned", false):
			_held.remove_at(i)
			continue
		if _begin(job):
			_held.remove_at(i)


## Drop a held plan — the player asked this worker for something else.
##
## The rest of the plan goes with it. A worker holding "fence it, then stock it"
## who is told to go and dig instead has been given a different order, and
## coming back to the hens an hour later would be a ghost of an instruction the
## player has forgotten giving.
func _forget_held(worker: Worker) -> void:
	for i in range(_held.size() - 1, -1, -1):
		var job: Dictionary = _held[i]
		if job["worker"] == worker:
			if job.get("plot", null) != null:
				(job["plot"] as Plot).reserved = false
			_held.remove_at(i)
	var run: Dictionary = _running.get(worker.memory.worker_id, {})
	if not run.is_empty():
		_abandon(run)
	worker.waiting_for = ""


func _on_question_ready(worker_id: String, question: String, line: String) -> void:
	var job: Dictionary = _open.get(worker_id, {})
	if job.is_empty():
		return
	var worker: Worker = job["worker"]
	if line != "":
		worker.speak(line, "talk")
	worker.ask_player(question)
	# The plot stays reserved: the question is about that plot, and the answer
	# is coming.


## The call did not land. This is news, not a refusal: LLM always follows a
## failure with an offline plan, so the job carries on with the standard design
## and the player is told why it is not the clever one.
##
## Closing the job here — which is what this used to do — meant the plan that
## arrived a millisecond later had nowhere to go, and every API hiccup became a
## worker who shrugged and did nothing.
func _on_llm_failed(_worker_id: String, reason: String) -> void:
	status.emit(reason)


func _refuse(worker: Worker, plot: Plot, err: Dictionary) -> void:
	_open.erase(worker.memory.worker_id)
	worker.stop_thinking()
	plot.reserved = false
	# A typed error is a question, not a stack trace. This is the moment the
	# design is built around: the worker turns "MODULE_WONT_FIT" into a sentence.
	worker.ask_player(str(err.get("question", "I am not sure how to do that.")))
	refused.emit(worker, err)



## Answering an open question re-runs the instruction with the answer appended,
## which is exactly how a person would take it.
func answer(worker: Worker, reply: String) -> void:
	var job: Dictionary = _open.get(worker.memory.worker_id, {})
	worker.resolve_question()
	if job.is_empty():
		return
	_open.erase(worker.memory.worker_id)
	# Before instruct(), not after: a worker still marked as thinking counts as
	# busy now, and would be told they were in the middle of something by the
	# very call meant to restart them.
	worker.stop_thinking()
	var plot: Plot = job["plot"]
	plot.reserved = false
	instruct(worker, "%s (%s)" % [str(job["instruction"]), reply])



# ------------------------------------------------------------------- roles

## Taking people on and writing jobs up.
##
## Kept as sentence patterns rather than sent to the model, for the same
## reason "wait here" is: they are about the crew, not the world, there is
## nothing to plan, and a forty-second pause before "you're hired" would be
## absurd. The job itself — what a "night watchman" is made of — is the part
## that goes to the model, once, the first time the town hears the name.
const HIRE_RE := "^(?:hire|take on|employ|recruit|sign up)\\s+(?<who>you|me|him|her|them|[a-z]+)\\s+as\\s+(?:a |an |the |my )?(?<role>[a-z][a-z \\-]*?)(?:\\s*[:,;\\-–—]\\s*(?<desc>.+))?[.!]?$"
const HIRED_RE := "^(?:you're|you are|youre|your) hired as\\s+(?:a |an |the |my )?(?<role>[a-z][a-z \\-]*?)(?:\\s*[:,;\\-–—]\\s*(?<desc>.+))?[.!]?$"
const BE_MY_RE := "^(?:be my|work for me as|join me as|you can be my|i want you as)\\s+(?:a |an |the )?(?<role>[a-z][a-z \\-]*?)(?:\\s*[:,;\\-–—]\\s*(?<desc>.+))?[.!]?$"
const DEFINE_RE := "^(?:define|create|make|add|write up|new)\\s+(?:a |an )?(?:new )?(?:role|job)\\s+(?:called |named |for )?(?<role>[a-z][a-z \\-]*?)\\s*(?:[:,;\\-–—]|\\bwho\\b|\\bthat\\b|\\bto\\b)?\\s*(?<desc>.*)$"
const FIRE_RE := "^(?:you're fired|you are fired|youre fired|dismiss(?:ed)?|let you go|i'm letting you go|you can go home for good|you're let go)"

var _re_hire := RegEx.new()
var _re_hired := RegEx.new()
var _re_be_my := RegEx.new()
var _re_define := RegEx.new()
var _re_fire := RegEx.new()


func _compile_role_patterns() -> void:
	_re_hire.compile(HIRE_RE)
	_re_hired.compile(HIRED_RE)
	_re_be_my.compile(BE_MY_RE)
	_re_define.compile(DEFINE_RE)
	_re_fire.compile(FIRE_RE)


const SAVE_WORDS := ["save", "save the game", "save the town", "write it down",
	"save game", "save everything"]
const RESTART_WORDS := ["start over", "start again", "new game", "new town",
	"wipe the save", "reset the game", "reset everything"]


func _try_game(worker: Worker, instruction: String) -> bool:
	var t := instruction.strip_edges().to_lower().rstrip(".!")
	if t in SAVE_WORDS:
		spoke.emit(worker, "Written down.", "talk")
		save_requested.emit()
		return true
	if t in RESTART_WORDS:
		spoke.emit(worker, "Starting again, then.", "talk")
		restart_requested.emit()
		return true
	return false


## Returns true if the instruction was about hiring or roles, whatever it
## then did about it.
func _try_roles(worker: Worker, instruction: String) -> bool:
	if _re_hire.get_pattern() == "":
		_compile_role_patterns()
	var t := instruction.strip_edges().to_lower()

	if _re_fire.search(t) != null:
		if not worker.hired:
			spoke.emit(worker, "I never worked for you.", "talk")
		elif worker.memory.worker_id in ["mira", "tobias", "ren"]:
			spoke.emit(worker, "I am not going anywhere.", "talk")
		else:
			# Whatever plan they were in the middle of goes with them.
			_forget_held(worker)
			_open.erase(worker.memory.worker_id)
			crew.dismiss(worker)
			worker.memory.remember(clock.day, "Let go.", -0.3)
			spoke.emit(worker, "Right. I will be about, if you change your mind.", "talk")
		return true

	var m := _re_hire.search(t)
	var target := worker
	if m == null:
		m = _re_hired.search(t)
	if m == null:
		m = _re_be_my.search(t)
	if m != null:
		var who := m.get_string("who") if m.names.has("who") else "you"
		if who not in ["", "you", "me", "him", "her", "them"]:
			target = _worker_named(who)
			if target == null:
				spoke.emit(worker, "There is nobody here called %s." % who.capitalize(), "talk")
				return true
		_hire_as(target, m.get_string("role"), m.get_string("desc"), worker)
		return true

	m = _re_define.search(t)
	if m != null and m.get_string("role").strip_edges() != "":
		_define_role(worker, m.get_string("role"), m.get_string("desc"), null)
		return true
	return false


func _worker_named(name: String) -> Worker:
	if crew == null:
		return null
	for w: Worker in crew.workers:
		if w.display_name().to_lower() == name.to_lower():
			return w
	return null


## Taking somebody on as a job. If the town knows the job, it is immediate;
## if not, the job is written up first and the hire waits on it.
func _hire_as(target: Worker, role_name: String, desc: String, asked: Worker) -> void:
	var id := RoleBook.canonical(Role.id_of(role_name))
	if id == "":
		spoke.emit(asked, "As a what?", "question")
		return
	if id == "citizen":
		spoke.emit(asked, "That is not a job, that is just living here.", "talk")
		return
	if target.hired and target.role != null and target.role.id == id:
		spoke.emit(target, "I already am.", "talk")
		return
	if crew.roles.has(id):
		_finish_hire(target, crew.roles.get_role(id))
		return
	_define_role(asked, role_name, desc, target)


## Writing a job up. `then_hire` is who to take on once it exists, or null to
## only define it.
func _define_role(asked: Worker, role_name: String, desc: String, then_hire: Worker) -> void:
	var id := RoleBook.canonical(Role.id_of(role_name))
	if id == "":
		spoke.emit(asked, "What is the job called?", "question")
		return
	if crew.roles.has(id) and then_hire == null:
		spoke.emit(asked, "We have %s already: %s." % [
			Validator.an(crew.roles.get_role(id).name), crew.roles.get_role(id).summary()], "talk")
		return
	if not _pending_hires.has(id):
		_pending_hires[id] = []
	if then_hire != null:
		(_pending_hires[id] as Array).append(then_hire)
	spoke.emit(asked, "%s — let me think what that comes to." % role_name.capitalize(), "talk")
	llm.compose_role(id, role_name, desc.strip_edges(), _ctx(asked))


## The job has been written up, by the model or by the keyword composer. It
## is checked like everything else that comes back from a model: a role that
## names something the town has never heard of is refused out loud, not
## quietly trimmed.
func _on_role_ready(key: String, raw: Dictionary, source: String) -> void:
	var waiting: Array = _pending_hires.get(key, [])
	_pending_hires.erase(key)
	var mouth: Worker = waiting[0] if not waiting.is_empty() else _any_hired()

	var err := Validator.check_role(raw)
	if not err.is_empty():
		if mouth != null:
			mouth.speak(str(err["question"]), "refuse")
		refused.emit(mouth, err)
		return

	var role := Role.make(key, str(raw.get("name", key)).strip_edges().to_lower(),
		raw.get("capabilities", []), "")
	role.character = str(raw.get("character", "")).strip_edges()
	role.standing = str(raw.get("standing", "")).strip_edges()
	role.created_day = clock.day
	role.source = source
	# Everybody can walk, stand and talk, whatever the composer left out.
	for base: String in ["go", "wait", "speak"]:
		if base not in role.capabilities:
			role.capabilities.append(base)
	crew.roles.add(role)
	status.emit("New job: %s" % role.summary())

	var line := str(raw.get("line", "")).strip_edges()
	for w: Variant in waiting:
		_finish_hire(w as Worker, role, line)
	if waiting.is_empty() and mouth != null:
		mouth.speak("%s: %s." % [role.name.capitalize(),
			", ".join(role.ready_capabilities())], "talk")


func _finish_hire(target: Worker, role: Role, line: String = "") -> void:
	crew.hire(target, role)
	target.memory.remember(clock.day, "Taken on as %s." % Validator.an(role.name), 0.3)
	target.memory.nudge("trust_in_player", 0.1)
	if line == "":
		line = "Right. I am your %s, then." % role.name
	target.speak(line, "talk")
	plan_accepted.emit(target, ["Taken on as %s." % Validator.an(role.name),
		"Can do: %s." % ", ".join(role.ready_capabilities()),
		("Cannot do yet: %s." % ", ".join(role.planned_capabilities()))
			if not role.planned_capabilities().is_empty() else "Nothing waiting on the town."])


func _any_hired() -> Worker:
	if crew == null:
		return null
	for w: Worker in crew.hired():
		return w
	return null


const STAY_WORDS := ["wait", "stay", "stop", "hold"]
const COME_WORDS := ["follow", "come", "with"]


## Posting a worker: stand there, or come along. Returns true if that is what
## the instruction was.
func _try_posting(worker: Worker, instruction: String) -> bool:
	var text := instruction.to_lower()
	if _has_word(text, STAY_WORDS) and text.length() < 40:
		worker.employer = null
		worker.home = worker.global_position
		worker.speak("I will wait here, then.", "talk")
		return true
	if _has_word(text, COME_WORDS) and text.length() < 40:
		if player != null:
			worker.employer = player
		worker.speak("Right behind you.", "talk")
		return true
	return false


# ------------------------------------------------------------------ fetching

const DIG_WORDS := ["dig", "fetch", "mine", "quarry", "gather", "collect",
	"get", "bring", "chop", "fell", "cut"]

## What a player calls a material, mapped to what the stores call it. The left
## side is the vocabulary of somebody standing in a field; the right side is a
## key in Town.stock.
const MATERIAL_WORDS := {
	"stone": "cobble", "stones": "cobble", "rock": "cobble", "rocks": "cobble",
	"cobble": "cobble", "granite": "granite", "gravel": "gravel",
	"concrete": "concrete", "asphalt": "asphalt",
	"wood": "timber", "timber": "timber", "logs": "timber", "log": "timber",
	"tree": "timber", "trees": "timber", "lumber": "timber",
	"plank": "plank", "planks": "plank", "oak": "dark_oak",
	"thatch": "thatch", "straw": "thatch", "reed": "thatch",
	"sand": "sand", "sandstone": "sandstone", "glass": "glass",
	"clay": "brick", "brick": "brick", "bricks": "brick", "tile": "clay_tile",
	"dirt": "dirt", "soil": "dirt", "earth": "dirt",
	"iron": "steel_frame", "ore": "steel_frame", "steel": "steel_frame",
	"metal": "sheet_metal", "chrome": "chrome",
}


## "go and dig up some iron" — a verb about the ground and a material. Both are
## required: "build a stone wall" has the material and no errand, and "get on
## with it" has the errand and no material.
func _try_gather(worker: Worker, instruction: String) -> bool:
	var text := instruction.to_lower()
	if not _has_word(text, DIG_WORDS):
		return false
	var mat := ""
	for word: String in MATERIAL_WORDS:
		if _has_word(text, [word]):
			mat = str(MATERIAL_WORDS[word])
			break
	if mat == "":
		return false

	var units := 240
	for token: String in text.replace(",", " ").split(" ", false):
		if token.is_valid_int():
			units = clampi(int(token), 10, 4000)
			break
	_dig(worker, mat, units)
	return true


static func _has_word(text: String, words: Array) -> bool:
	var t := " %s " % text.to_lower().replace(",", " ").replace(".", " ")
	for w: String in words:
		if t.find(" %s " % w) >= 0:
			return true
	return false
