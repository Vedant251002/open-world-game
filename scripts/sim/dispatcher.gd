extends Node
class_name Dispatcher
## Turns a sentence into a job.
##
## The pipeline is the whole game (voxel-module-spec.md §0):
##
##   instruction -> LLM (or the offline library) -> spec
##   spec -> pre-validator -> either a typed error or a plan
##   plan -> BuildingGenerator -> patch, or a second typed error
##   patch -> the worker, who walks off and lays it down over in-game hours
##
## Every error on that path is fail-closed and typed, and every typed error
## becomes a question the worker asks out loud rather than a message box. That
## is design pillar P3: failure has to be legible, and it has to be in character.

signal spoke(worker: Worker, line: String, kind: String)
signal plan_accepted(worker: Worker, assumptions: Array)
signal refused(worker: Worker, err: Dictionary)
signal status(text: String)

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
var player: Node3D

## worker_id -> {"worker": Worker, "instruction": String, "plot": Plot}
var _open: Dictionary = {}


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
	llm.status.connect(func(t2: String) -> void: status.emit(t2))


## Whether the AI is answering for real or the offline library is standing in.
func ai_online() -> bool:
	return llm != null and llm.available()


func describe_ai() -> String:
	return llm.describe() if llm != null else "no AI layer"


func instruct(worker: Worker, instruction: String) -> void:
	if worker.busy():
		spoke.emit(worker, "I am in the middle of something.", "refuse")
		return
	if _open.has(worker.memory.worker_id):
		status.emit("%s is still thinking." % worker.display_name())
		return

	# "Wait here" and "follow me" are instructions like any other — the player
	# says them, so they go through the same text field as everything else
	# rather than becoming a key nobody would find (pillar P1).
	if _try_posting(worker, instruction):
		return

	# Land work never reaches the model. The building generator emits walls and
	# roofs; a field is forty columns of soil and has no spec to argue about, so
	# routing it through the plan pipeline would only add a way to fail.
	if farm != null and _is_field_work(instruction):
		_send_to_field(worker, instruction)
		return
	if livestock != null and _is_livestock(instruction):
		_fetch_livestock(worker, instruction)
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
	# somebody stand still.
	worker.set_out_for(plot)
	llm.submit(instruction, worker.memory, plot, _ctx(), clock, town)


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


func _ctx() -> Dictionary:
	return {
		"world": world, "village": village, "worldgen": gen,
		"tier": town.tier,
		"occupied_rects": town.occupied_rects,
		"built_fronts": town.built_fronts,
	}


func _on_plan_ready(worker_id: String, plan: Dictionary) -> void:
	var job: Dictionary = _open.get(worker_id, {})
	if job.is_empty():
		return
	var worker: Worker = job["worker"]
	var plot: Plot = job["plot"]
	var spec: Dictionary = plan.get("spec", {})
	var assumptions: Array = plan.get("assumptions", [])

	# Pre-validation. A spec that cannot be built has to be refused before a
	# single voxel is written, and refused with a reason the worker can say.
	var err := Validator.check_spec(spec, plot, _ctx())
	if not err.is_empty():
		_refuse(worker, plot, err)
		return

	var res := BuildingGenerator.build(spec, hash(worker_id) & 0x7FFFFFFF, plot, _ctx())
	if not res["ok"]:
		_refuse(worker, plot, res["error"])
		return

	var patch: VoxelPatch = res["patch"]
	_open.erase(worker_id)

	# The assumptions go up before the worker leaves, never after the building
	# is finished. Seeing what they decided while they walk away is what makes
	# the result fair (design pillar P3).
	plan_accepted.emit(worker, assumptions)

	var line := str(plan.get("worker_line", ""))
	if line != "":
		worker.speak(line, "talk")

	# Nobody paths through a building site.
	nav.refresh_world_rect(patch.footprint, 3)

	worker.take_job(plot, spec, patch, assumptions, line, props_root)
	if map != null:
		map.note_building(patch, str(spec.get("archetype", "building")))


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
	var plot: Plot = job["plot"]
	plot.reserved = false
	instruct(worker, "%s (%s)" % [str(job["instruction"]), reply])



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


# ------------------------------------------------------------------ the land

const FIELD_WORDS := ["field", "farm", "plant", "sow", "crop", "wheat",
	"carrot", "garden", "plough", "plow", "allotment"]
const STOCK_WORDS := ["hen", "hens", "chicken", "chickens", "sheep", "cow",
	"cows", "cattle", "livestock", "coop", "poultry"]


static func _has_word(text: String, words: Array) -> bool:
	var t := " %s " % text.to_lower().replace(",", " ").replace(".", " ")
	for w: String in words:
		if t.find(" %s " % w) >= 0:
			return true
	return false


static func _is_field_work(instruction: String) -> bool:
	return _has_word(instruction, FIELD_WORDS)


static func _is_livestock(instruction: String) -> bool:
	return _has_word(instruction, STOCK_WORDS)


## Size and crop are the two things a one-line instruction usually leaves out,
## so both are guessed and both are said out loud. That is the whole of pillar
## P3 applied to a field instead of a building.
func _send_to_field(worker: Worker, instruction: String) -> void:
	var text := instruction.to_lower()
	var crop := "carrot" if text.find("carrot") >= 0 else "wheat"
	var side := 20                       ## voxels — 5 m square
	var size_word := "the usual size"
	if _has_word(text, ["big", "large", "great", "huge"]):
		side = 36
		size_word = "big, since you asked"
	elif _has_word(text, ["small", "little", "tiny"]):
		side = 12
		size_word = "small, since you asked"

	var near := worker.global_position if player == null else player.global_position
	var found := farm.find_field(near, Vector2i(side, side))
	if found.is_empty():
		worker.ask_player("There is no flat open ground near here for a field. " 			+ "Where would you like it?")
		return
	var rect: Rect2i = found["rect"]

	var where := "on the nearest flat ground I could find"
	if bool(found["wet"]):
		where = "within reach of water, so it will ripen in about three days"
	else:
		where = "on the nearest flat ground I could find — there is no water " 			+ "near it, so it will be slow"
	var assumptions: Array = [
		"You did not say what to sow, so I put in %s." % crop
			if text.find(crop) < 0 else "Sowing %s, as you said." % crop,
		"You did not say how big, so I made it %s — %.0f by %.0f metres."
			% [size_word, side * 0.25, side * 0.25],
		"I put it %s, %.0f m from you." % [where,
			Vector3(rect.get_center().x * 0.25, near.y,
				rect.get_center().y * 0.25).distance_to(near)],
	]
	plan_accepted.emit(worker, assumptions)

	var work := FieldWork.new(farm, rect, crop)
	worker.take_field_job(work, assumptions,
		"Right — %s it is." % crop)


## Livestock arrives with the worker rather than appearing from nowhere: they
## walk out, and the animals are there when they get back.
func _fetch_livestock(worker: Worker, instruction: String) -> void:
	var text := instruction.to_lower()
	var species := "hen"
	if _has_word(text, ["sheep"]):
		species = "sheep"
	elif _has_word(text, ["cow", "cows", "cattle"]):
		species = "cow"

	var count := 6 if species == "hen" else 4
	if _has_word(text, ["a", "one"]) and _has_word(text, ["few"]):
		count = 3
	var near := worker.global_position if player == null else player.global_position
	var made := livestock.stock_area(species, near, count, 9.0)
	if made == 0:
		worker.ask_player("There is nowhere here to put them. Somewhere more open?")
		return

	plan_accepted.emit(worker, [
		"You did not say how many, so I brought %d." % made,
		"I turned them out where you were standing; they will not stray far.",
	])
	worker.speak("%d %s, turned out here." % [made,
		species + ("s" if made != 1 else "")], "done")
