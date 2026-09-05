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

## Following the employer. The design doc has the crew living in the town, but
## the three of them are the game: if you have to walk back to the well to give
## an instruction, you stop giving instructions. So when they have nothing to do
## they come with you, each to their own side so they do not stand in a stack.
const FOLLOW_SLOT_M := 2.9
## Where each of the three stands, as a bearing off directly-behind. An arc
## rather than a rank: abreast put two of them within a few degrees of one
## another from the player's eye, so aiming at Tobias picked up Ren. Forty
## degrees apart, nobody is ambiguous.
const FOLLOW_BEARINGS: Array[float] = [0.0, -0.72, 0.72]
const FOLLOW_CLOSE := 2.0      ## stop closing in
const FOLLOW_CHASE := 3.6      ## start closing in
const FOLLOW_RUN := 9.0        ## far enough behind to break into a run
const FOLLOW_GIVE_UP := 90.0   ## teleport rather than be lost forever

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
## Ploughing and sowing, when the job is a field rather than a building. Only
## one of these two is ever set.
var job_field: FieldWork = null
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
## Who to walk behind while idle, and where in the huddle this one stands.
var employer: Node3D = null
var follow_slot := 0
var _closing := false
## Progress watchdog. A worker who has stopped getting closer to the next
## point on his path is stuck on something, and a stuck worker is a job that
## never finishes and a player waiting for news that will not come.
var _stuck_for := 0.0
var _last_gap := INF
var _repaths := 0
## Standing on a plot waiting for a plan to arrive. Idle, but not free to
## wander off after the employer.
var _holding := false
## Where the employer was last frame, and which way he has been travelling.
## The follow slots hang off the heading rather than off his facing.
var _employer_was := Vector3.ZERO
var _employer_heading := Vector3(0.0, 0.0, 1.0)
## Speech is shown in world space rather than in the HUD, so you can tell at a
## glance which of the three said it without reading a name.
var bubble: Label3D
var _bubble_left := 0.0


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
	# Close to the width of the body. At 0.9 m this was a metre and a half
	# across, and two workers standing near each other became one target the
	# player could not choose between.
	asphere.radius = 0.62
	asphere.height = 2.4
	acs.shape = asphere
	acs.position.y = 1.0
	area.add_child(acs)
	add_child(area)

	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = false
	bubble.fixed_size = false
	bubble.font_size = 44
	bubble.outline_size = 14
	bubble.outline_modulate = Color(0.05, 0.04, 0.03, 0.85)
	bubble.pixel_size = 0.0032
	bubble.width = 900.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.position.y = 2.15
	bubble.visible = false
	add_child(bubble)

	# A name over the head, so the three of them are learnable on sight.
	var tag := Label3D.new()
	tag.text = memory.display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# At 30 px and a 0.0028 pixel size the name was eight screen pixels tall
	# from across the plaza, which is a smudge rather than a label.
	tag.font_size = 48
	tag.outline_size = 14
	tag.outline_modulate = Color(0.05, 0.04, 0.03, 0.85)
	tag.modulate = body.cloth_colour.lightened(0.55)
	tag.pixel_size = 0.0045
	tag.position.y = 1.94
	tag.visibility_range_end = 40.0
	add_child(tag)

	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.5


## Three people the player has to tell apart instantly and remember for hours.
## Colour alone does not do that at forty metres in a brown town, so each one
## also gets a different silhouette above the shoulders and a different cut
## below them.
func _style_body() -> void:
	match memory.worker_id:
		"mira":
			# Warm, quick, sleeves already rolled up before you finish asking.
			body.cloth_colour = Color("#c4632f")
			body.accent_colour = Color("#e8ae4e")
			body.hair_colour = Color("#5d2f18")
			body.body_colour = Color("#c99070")
			body.accessory = "scarf"
			body.rolled_sleeves = true
		"tobias":
			# Cool, buttoned, a long coat and a flat cap. Grey at the temples.
			body.cloth_colour = Color("#44546a")
			body.accent_colour = Color("#8c96a6")
			body.hair_colour = Color("#8a8a86")
			body.body_colour = Color("#b08a68")
			body.accessory = "cap"
			body.long_coat = true
		"ren":
			# A broad-brimmed hat with a band, and the loudest green in town.
			body.cloth_colour = Color("#3f7a4c")
			body.accent_colour = Color("#b9cf5e")
			body.hair_colour = Color("#22201c")
			body.body_colour = Color("#7d5638")
			body.accessory = "brim"


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
	elif _tags_along():
		planar = _steer_to_employer(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
	move_and_slide()

	if state == State.BUILDING and _path.is_empty():
		body.work(delta)
	else:
		body.animate(delta, planar, state == State.WALKING and job_patch != null)

	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0 and bubble != null:
			bubble.visible = false

	_tick_state(delta)


func _follow_path(delta: float) -> float:
	var target := _path[_path_i]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() < ARRIVE_DIST:
		_path_i += 1
		if _path_i >= _path.size():
			_path = PackedVector3Array()
			_path_i = 0
			_repaths = 0
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

	# Face where they are going. Workers who moonwalk are not people, and +Z
	# is the front of every model in the project.
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 7.0)

	# Step up a doorstep rather than getting stuck on it. Still gated on standing
	# on something: hopping while airborne is how you climb a wall for ever. The
	# wedged-in-mid-air case is the watchdog's job, below.
	if is_on_wall() and is_on_floor():
		velocity.y = 4.2

	_watch_progress(to.length(), delta)
	return speed


## Notices when a worker has stopped making headway and does something about
## it. Twice it tries a fresh route; after that it steps him onto the next
## point of the path and carries on.
##
## Stepping a character through geometry is not something to do lightly, but
## the alternative here is a worker standing in mid-air against a wall for
## the rest of the session with a job the player is waiting on, and nobody is
## watching a worker who is stuck behind a bakery.
func _watch_progress(gap: float, delta: float) -> void:
	if gap < _last_gap - 0.05:
		_last_gap = gap
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for < 3.0:
		return
	_stuck_for = 0.0
	_last_gap = INF
	var goal: Vector3 = _path[_path.size() - 1]
	if _repaths < 2:
		_repaths += 1
		var after := _after_arrival
		if walk_to(goal, after):
			return
	var step: Vector3 = _path[_path_i]
	global_position = Vector3(step.x, world.ground_m(step.x, step.z) + 0.4, step.z)
	velocity = Vector3.ZERO


## Whether the worker should be trailing the player right now. Only when idle:
## a worker who abandons a half-built wall because you walked past is not a
## worker, and being asked a question is a conversation you are standing in.
func _tags_along() -> bool:
	return employer != null and state == State.IDLE and not _holding


## Direct steering rather than a path. Following happens at three metres and
## changes target every frame, which is the one case A* is worse at than
## walking straight at the thing — and the crew follows you off the nav grid
## and into open country, where there is no graph to search at all.
func _steer_to_employer(delta: float) -> float:
	_track_employer(delta)
	var want := _follow_spot()
	var to := Vector3(want.x - global_position.x, 0.0, want.z - global_position.z)
	var d := to.length()

	if d > FOLLOW_GIVE_UP:
		# Lost. Rather than trudge home across a continent, catch up off screen.
		global_position = Vector3(want.x, world.ground_m(want.x, want.z) + 0.3, want.z)
		velocity = Vector3.ZERO
		return 0.0

	# Hysteresis, or the crew jitters in and out of range at exactly one radius.
	if _closing and d < FOLLOW_CLOSE:
		_closing = false
	elif not _closing and d > FOLLOW_CHASE:
		_closing = true

	if not _closing:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		# Turn to face the employer while waiting, so they read as attending.
		var face := employer.global_position - global_position
		if face.length() > 0.4:
			rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), delta * 5.0)
		return 0.0

	var speed := (HURRY_SPEED if d > FOLLOW_RUN else WALK_SPEED) * memory.work_rate()
	var dir := to / maxf(d, 0.001)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 7.0)
	if is_on_wall() and is_on_floor():
		velocity.y = 4.2
	return speed


## A fan behind the employer, one slot each.
##
## Behind where he has been WALKING, not behind where he is currently looking.
## Taken off his facing, the whole crew slid round to stay at his back the
## instant he turned his head — so turning to look at somebody chased them out
## of view, and there was no way to put one in the crosshair and speak to them.
##
## The heading only updates while he is actually moving, which is what makes
## standing still and turning round work: the anchor is frozen, so they hold
## their ground and you can face whichever one you want.
func _follow_spot() -> Vector3:
	var bearing: float = FOLLOW_BEARINGS[follow_slot % FOLLOW_BEARINGS.size()]
	var out := (-_employer_heading).rotated(Vector3.UP, bearing)
	return employer.global_position + out * FOLLOW_SLOT_M


## Starts the tracker where the employer actually is, so the first frame of the
## game is not a scramble away from the origin.
func seed_follow(at: Vector3) -> void:
	_employer_was = at


## Tracks which way the employer is travelling, ignoring which way he is facing.
func _track_employer(delta: float) -> void:
	var now := employer.global_position
	var moved := Vector3(now.x - _employer_was.x, 0.0, now.z - _employer_was.z)
	_employer_was = now
	# A fifth of a metre a second: enough to ignore the jitter of standing on a
	# slope, far below any real walking pace.
	if moved.length() < 0.2 * delta:
		return
	_employer_heading = _employer_heading.lerp(moved.normalized(), 0.18).normalized()


func walk_to(target: Vector3, then: String = "") -> bool:
	_after_arrival = then
	_path = nav.path(global_position, target)
	_path_i = 0
	_stuck_for = 0.0
	_last_gap = INF
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
		"hold":
			# Arrived at the site before the plan did. Wait here.
			state = State.IDLE
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
			if job_field != null:
				job_field.advance(game_hours)
				if job_field.finished:
					_finish_field()
				return
			if job_construction == null:
				state = State.IDLE
				return
			job_construction.advance(game_hours)
			if job_construction.finished:
				_finish_job()
		State.REPORTING:
			_speak_timer += delta


func _tick_idle(delta: float) -> void:
	if _tags_along():
		return                        # steering handles it, no wandering
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
## Sets off for the plot before anyone knows what is going in it.
##
## The model takes the better part of a minute to answer on a free
## endpoint. Spent standing still that is a player watching a man think;
## spent walking it is a man on his way to work, and by the time the plan
## lands he is usually there. This is what §5.2 means by hiding the latency
## behind in-game time.
func set_out_for(plot: Plot) -> void:
	if state != State.IDLE:
		return
	_holding = true
	var stand := _stand_for(plot)
	if not walk_to(stand, "hold"):
		_holding = false


## Where a worker stands to work on a plot: off the front of it, on the
## street side, so they are not inside their own building site.
func _stand_for(plot: Plot) -> Vector3:
	var stand := plot.centre_m() + Vector3(plot.street_dir) * (plot.size_m().x * 0.5 + 2.0)
	stand.y = world.ground_m(stand.x, stand.z)
	return stand


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

	_holding = false
	var stand := _stand_for(plot)
	if Vector2(global_position.x - stand.x, global_position.z - stand.z).length() < 2.5:
		# Already here — they walked over while the model was thinking.
		_path = PackedVector3Array()
		state = State.GATHERING
		_gather_hours = 0.0
		_say("%s. I will fetch what I need." % _acknowledge(), "work")
	elif not walk_to(stand, "build"):
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


## A field, rather than a building. Same rhythm — walk out, work for hours,
## walk back and report — because that rhythm is what the player learns to
## read, and a job that behaved differently would just be confusing.
func take_field_job(work: FieldWork, assumptions: Array, line: String) -> void:
	job_field = work
	job_assumptions = assumptions
	job_started_hour = clock.day * 24.0 + clock.hour
	job_field.tiles_per_hour = 26.0 * memory.work_rate()
	job_eta_hours = float(work.total()) / maxf(job_field.tiles_per_hour, 1.0)

	var c := work.rect.get_center()
	var stand := Vector3(float(c.x) * 0.25, 0.0, float(c.y) * 0.25)
	stand.y = world.ground_m(stand.x, stand.z)
	if not walk_to(stand, "build"):
		job_failed.emit(self, Validator.error("unreachable_plot",
			"I cannot get out to that ground — something is in the way."))
		_clear_job()
		return
	if line != "":
		_say(line, "plan")


func _finish_field() -> void:
	var work := job_field
	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	memory.practise("carpentry", 0.4)
	memory.remember(clock.day, "Ploughed a field: %s." % work.summary(), 0.15)

	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	_say("Field is in — %s." % work.summary(), "done")
	job_field = null
	job_assumptions = []


func _clear_job() -> void:
	_holding = false
	job_plot = null
	job_spec = {}
	job_patch = null
	job_construction = null
	job_field = null
	job_assumptions = []
	state = State.IDLE


func _skill_for(patch: VoxelPatch) -> String:
	var walls := str(patch.cost.keys()[0] if not patch.cost.is_empty() else "timber")
	if walls in ["brick", "sandstone", "granite", "cobble", "concrete"]:
		return "masonry"
	return "carpentry"


func progress() -> float:
	if job_field != null:
		return job_field.progress()
	if job_construction == null:
		return 0.0
	return job_construction.progress()


## Where this worker is and what is holding them up. Diagnostic only.
func debug_state() -> String:
	return "%s at %s, path %d/%d, after=%s, on_floor=%s, vel=%.1f" % [
		status_text(), str(global_position.round()), _path_i, _path.size(),
		_after_arrival if _after_arrival != "" else "-",
		"yes" if is_on_floor() else "NO",
		Vector2(velocity.x, velocity.z).length()]


func status_text() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.WALKING:
			return "on the way" if (job_patch != null or job_field != null) 				else "walking"
		State.GATHERING:
			return "fetching materials"
		State.BUILDING:
			if job_field != null:
				return "ploughing — %d%%" % int(progress() * 100.0)
			return "building — %d%%" % int(progress() * 100.0)
		State.REPORTING:
			return "back with news"
		State.ASKING:
			return "waiting on you"
	return ""


# ------------------------------------------------------------------ dialogue

func _say(line: String, kind: String) -> void:
	last_line = line
	if bubble != null:
		bubble.text = line
		bubble.modulate = _bubble_tint(kind)
		bubble.visible = true
		# Long lines stay up longer, at roughly reading speed.
		_bubble_left = clampf(2.4 + line.length() * 0.045, 3.0, 11.0)
	said.emit(self, line, kind)


static func _bubble_tint(kind: String) -> Color:
	match kind:
		"refuse": return Color("#ffb4a2")
		"question": return Color("#ffe08a")
		"done": return Color("#b9f0b0")
		"work": return Color("#dbe6f0")
		_: return Color("#f4efe6")


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
