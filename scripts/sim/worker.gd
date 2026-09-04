extends CharacterBody3D
class_name Worker
## Mira, Tobias or Ren.
##
## State machine per build-order.md slice 3:
##   idle -> walking -> gathering -> building -> reporting
##
## The worker goes away and does the job over in-game hours. That gap is the
## design: if you stand and watch, it is a progress bar; if you wander off and
## come back, it is a surprise. So construction advances whether or not anyone
## is looking, and the worker walks back to tell you when it is done.

signal said(worker: Worker, line: String, kind: String)
signal job_finished(worker: Worker, patch: VoxelPatch)
signal job_failed(worker: Worker, err: Dictionary)

enum State { IDLE, WALKING, GATHERING, BUILDING, REPORTING, ASKING }

const WALK_SPEED := 2.6
const HURRY_SPEED := 4.1
const ARRIVE_DIST := 1.1

var memory: WorkerMemory
var body: Humanoid
var nav: NavGrid
var world: VoxelWorld
var clock: GameClock
var town: Town

var state: State = State.IDLE
var home: Vector3 = Vector3.ZERO

# --- current job ---
var job_plot: Plot = null
var job_spec: Dictionary = {}
var job_patch: VoxelPatch = null
var job_construction: Construction = null
var job_assumptions: Array = []
var job_started_hour := 0.0
var job_eta_hours := 0.0
var pending_question := ""
var last_line := ""

var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _after_arrival := ""
var _idle_target := Vector3.ZERO
var _idle_timer := 0.0
var _speak_timer := 0.0
var _gather_hours := 0.0


func setup(mem: WorkerMemory, n: NavGrid, w: VoxelWorld, c: GameClock, t: Town) -> void:
	memory = mem
	nav = n
	world = w
	clock = c
	town = t

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	add_child(shape)

	body = Humanoid.new()
	_style_body()
	add_child(body)

	# A talk target on layer 4, which is what the player's look ray reads.
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var acs := CollisionShape3D.new()
	var asphere := CapsuleShape3D.new()
	asphere.radius = 0.9
	asphere.height = 2.6
	acs.shape = asphere
	acs.position.y = 1.0
	area.add_child(acs)
	add_child(area)

	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.5


func _style_body() -> void:
	match memory.worker_id:
		"mira":
			body.cloth_colour = Color("#c46a3a")
			body.accent_colour = Color("#e0a14a")
			body.hair_colour = Color("#5d2f18")
			body.body_colour = Color("#c99070")
		"tobias":
			body.cloth_colour = Color("#4a5a6e")
			body.accent_colour = Color("#7a8494")
			body.hair_colour = Color("#8a8a86")
			body.body_colour = Color("#b08a68")
		"ren":
			body.cloth_colour = Color("#3f6b4a")
			body.accent_colour = Color("#8fae55")
			body.hair_colour = Color("#22201c")
			body.body_colour = Color("#7d5638")


func display_name() -> String:
	return memory.display_name


func busy() -> bool:
	return state != State.IDLE and state != State.ASKING


# ------------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0.0

	var planar := 0.0
	if not _path.is_empty():
		planar = _follow_path(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
	move_and_slide()

	if state == State.BUILDING and _path.is_empty():
		body.work(delta)
	else:
		body.animate(delta, planar, state == State.WALKING and job_patch != null)

	_tick_state(delta)


func _follow_path(delta: float) -> float:
	var target := _path[_path_i]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() < ARRIVE_DIST:
		_path_i += 1
		if _path_i >= _path.size():
			_path = PackedVector3Array()
			_path_i = 0
			_on_arrived()
			return 0.0
		target = _path[_path_i]
		to = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)

	var speed := WALK_SPEED * memory.work_rate()
	if _after_arrival == "report":
		speed = HURRY_SPEED * memory.work_rate()
	var dir := to.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Face where they are going. Workers who moonwalk are not people.
	var want_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, delta * 7.0)

	# Step up a doorstep rather than getting stuck on it.
	if is_on_wall() and is_on_floor():
		velocity.y = 4.2
	return speed


func walk_to(target: Vector3, then: String = "") -> bool:
	_after_arrival = then
	_path = nav.path(global_position, target)
	_path_i = 0
	if _path.is_empty():
		_after_arrival = ""
		return false
	state = State.WALKING
	return true


func _on_arrived() -> void:
	match _after_arrival:
		"build":
			state = State.GATHERING
			_gather_hours = 0.0
			_say("%s. I will fetch what I need." % _acknowledge(), "work")
		"report":
			state = State.REPORTING
			_speak_timer = 0.0
		"idle":
			state = State.IDLE
		_:
			state = State.IDLE
	_after_arrival = ""


# --------------------------------------------------------------------- state

func _tick_state(delta: float) -> void:
	var game_hours := delta / 60.0 * GameClock.HOURS_PER_REAL_MINUTE * clock.speed
	if clock.paused:
		game_hours = 0.0

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.GATHERING:
			_gather_hours += game_hours
			# Gathering is a beat, not a minigame: it exists so the player sees
			# the worker doing something before the walls appear.
			if _gather_hours >= 0.8 / maxf(memory.work_rate(), 0.2):
				state = State.BUILDING
				_say("Right. Starting now.", "work")
		State.BUILDING:
			if job_construction == null:
				state = State.IDLE
				return
			job_construction.advance(game_hours)
			if job_construction.finished:
				_finish_job()
		State.REPORTING:
			_speak_timer += delta


func _tick_idle(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer > 0.0 or not _path.is_empty():
		return
	_idle_timer = randf_range(4.0, 11.0)
	# Drift around home rather than standing to attention.
	var away := Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
	var target := home + away
	target.y = world.ground_m(target.x, target.z)
	walk_to(target, "idle")


# ---------------------------------------------------------------------- jobs

## Accepts a validated plan and goes to build it. Everything about *what* to
## build was settled upstream; from here it is legwork.
func take_job(plot: Plot, spec: Dictionary, patch: VoxelPatch,
		assumptions: Array, line: String, props_root: Node3D) -> void:
	job_plot = plot
	job_spec = spec
	job_patch = patch
	job_assumptions = assumptions
	job_started_hour = clock.day * 24.0 + clock.hour

	job_construction = Construction.new(patch, world, props_root)
	job_construction.voxels_per_hour = 2200.0 * memory.work_rate()
	job_eta_hours = float(patch.build_order.size()) / maxf(job_construction.voxels_per_hour, 1.0)

	var stand := plot.centre_m() + Vector3(plot.street_dir) * (plot.size_m().x * 0.5 + 2.0)
	stand.y = world.ground_m(stand.x, stand.z)
	if not walk_to(stand, "build"):
		# No route: that is a question, not a crash.
		job_failed.emit(self, Validator.error("unreachable_plot",
			"I cannot get to that plot — something is in the way."))
		_clear_job()
		return
	if line != "":
		_say(line, "plan")


func _finish_job() -> void:
	var patch := job_patch
	memory.practise(_skill_for(patch), 1.0)
	nav.refresh_world_rect(patch.footprint, 3)

	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	memory.remember(clock.day,
		"Built the %s on %s. Took about %d hours." % [
			patch.archetype.replace("_", " "), job_plot.street_name, int(hours)], 0.2)

	job_finished.emit(self, patch)

	# Walk back and say so. Coming back to report is the beat that closes the
	# loop; a notification would not be the same thing at all.
	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	_say(_completion_line(patch, hours), "done")


func _clear_job() -> void:
	job_plot = null
	job_spec = {}
	job_patch = null
	job_construction = null
	job_assumptions = []
	state = State.IDLE


func _skill_for(patch: VoxelPatch) -> String:
	var walls := str(patch.cost.keys()[0] if not patch.cost.is_empty() else "timber")
	if walls in ["brick", "sandstone", "granite", "cobble", "concrete"]:
		return "masonry"
	return "carpentry"


func progress() -> float:
	if job_construction == null:
		return 0.0
	return job_construction.progress()


func status_text() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.WALKING:
			return "on the way" if job_patch != null else "walking"
		State.GATHERING:
			return "fetching materials"
		State.BUILDING:
			return "building — %d%%" % int(progress() * 100.0)
		State.REPORTING:
			return "back with news"
		State.ASKING:
			return "waiting on you"
	return ""


# ------------------------------------------------------------------ dialogue

func _say(line: String, kind: String) -> void:
	last_line = line
	said.emit(self, line, kind)


func speak(line: String, kind: String = "talk") -> void:
	_say(line, kind)


func _acknowledge() -> String:
	match memory.worker_id:
		"mira": return "Already going"
		"tobias": return "Very well"
		"ren": return "Sure"
	return "Right"


func _completion_line(patch: VoxelPatch, hours: float) -> String:
	var what := patch.archetype.replace("_", " ")
	match memory.worker_id:
		"mira":
			if hours < job_eta_hours * 0.9:
				return "%s is done, and early. Come and look." % what.capitalize()
			return "%s is up. I did exactly what you said." % what.capitalize()
		"tobias":
			return "The %s is finished. It took the time it needed to take." % what
		"ren":
			return "%s is done. I changed a couple of things — you will like it." % what.capitalize()
	return "The %s is finished." % what


## A clarifying question, which is a gameplay beat rather than an error.
func ask_player(question: String) -> void:
	pending_question = question
	state = State.ASKING
	memory.ask(clock.day, question)
	_say(question, "question")


func resolve_question() -> void:
	pending_question = ""
	if state == State.ASKING:
		state = State.IDLE


# ------------------------------------------------------------------ reaction

## Player reactions write to memory. This is what makes the workers people
## rather than units, and it is where progression actually lives.
func react_praise() -> void:
	memory.nudge("morale", 0.18)
	memory.nudge("confidence", 0.10)
	memory.nudge("trust_in_player", 0.06)
	var ev := memory.remember(clock.day, "Player praised the last job.", 0.8)
	if job_patch != null:
		memory.learn("player likes %s buildings" % job_patch.archetype.replace("_", " "),
			0.35, ev)
	_say(_praise_reply(), "talk")


func react_criticise(about: String = "") -> void:
	var sting: float = memory.traits["criticism_sensitivity"]
	memory.nudge("morale", -0.22 * sting)
	memory.nudge("confidence", -0.14 * sting)
	var ev := memory.remember(clock.day,
		"Player criticised the last job%s." % ("" if about == "" else " — " + about), -0.6)
	if about != "":
		memory.learn("player dislikes %s" % about, 0.55, ev)
	_say(_criticism_reply(), "talk")


func react_correction(preference: String) -> void:
	var ev := memory.remember(clock.day, "Player changed %s afterwards." % preference, -0.25)
	memory.learn(preference, 0.6, ev)
	memory.nudge("trust_in_player", 0.03)
	_say(_correction_reply(preference), "talk")


func react_demolish() -> void:
	var sting: float = memory.traits["criticism_sensitivity"]
	memory.nudge("morale", -0.30 * sting)
	memory.nudge("confidence", -0.20 * sting)
	memory.remember(clock.day, "Player pulled down what I built.", -0.9)
	_say(_demolish_reply(), "talk")


func _praise_reply() -> String:
	match memory.worker_id:
		"mira": return "Oh — thank you. I will do the next one the same way."
		"tobias": return "It was a straightforward job, but I am glad it suits."
		"ren": return "Of course it is good. I made it."
	return "Thank you."


func _criticism_reply() -> String:
	match memory.worker_id:
		"mira": return "...oh. I did what you asked. I thought that was what you wanted."
		"tobias": return "I did mention this at the time."
		"ren": return "You will come round to it."
	return "Noted."


func _correction_reply(pref: String) -> String:
	match memory.worker_id:
		"mira": return "I will remember. %s." % pref.capitalize()
		"tobias": return "Good. Now I know for next time: %s." % pref
		"ren": return "If you say so. %s." % pref.capitalize()
	return pref.capitalize() + "."


func _demolish_reply() -> String:
	match memory.worker_id:
		"mira": return "You pulled it down. ...Right. What should I have done?"
		"tobias": return "A shame. Two days of work, that."
		"ren": return "Your town. I still think it was the best thing on that street."
	return "Understood."
