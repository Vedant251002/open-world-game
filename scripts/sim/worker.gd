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
## Any job of any kind is over and this worker's hands are free.
##
## Separate from job_finished because that one carries a patch, and half the
## jobs there are now do not produce one — an errand for six hens leaves nothing
## behind but six hens. The dispatcher runs multi-step orders off this, so it
## has to fire for every kind of work or a plan stalls on its second step.
signal step_done(worker: Worker)

enum State { IDLE, WALKING, GATHERING, BUILDING, REPORTING, ASKING }

const WALK_SPEED := 2.6
const HURRY_SPEED := 4.1
const ARRIVE_DIST := 1.1
## How long a worker stands about after reporting before their hands are free
## again. Long enough for the player to read the line over their head and turn
## round to look at them.
const REPORT_BEAT := 3.0

## Following the employer. The design doc has the crew living in the town, but
## the three of them are the game: if you have to walk back to the well to give
## an instruction, you stop giving instructions. So when they have nothing to do
## they come with you, each to their own side so they do not stand in a stack.
const FOLLOW_SLOT_M := 2.9
## Where each of the three stands, as a bearing off directly-behind. An arc
## rather than a rank: abreast put two of them within a few degrees of one
## another from the player's eye, so aiming at Tobias picked up Ren. Forty
## degrees apart, nobody is ambiguous.
##
## Six, not three, now that the crew can grow. The first three are the arc the
## starting crew always had; the next three are a second, wider arc behind it,
## so a hired fourth does not stand in Mira's spot.
const FOLLOW_BEARINGS: Array[float] = [0.0, -0.72, 0.72, -1.25, 1.25, 0.0]
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
## Digging a material out of the world. Only one of the three job kinds is
## ever set at a time.
var job_quarry: Quarry = null
## Making shot, powder or a gun at the armoury. Same shape as a quarry job:
## hours on the clock, then a result in the stores.
var job_craft: CraftJob = null
## Getting shot. A worker can be hurt and knocked down; they cannot be
## killed, because the three of them are the game.
var health := 100.0
var _down := 0.0
## Driving animals back and turning them out. The one job with no work in it —
## the whole of it is the walk — so it has no progress object, only a target.
var job_stock: Dictionary = {}
## An errand: a walk with something at the end of it. One job for go, wait,
## station, patrol, harvest, collect, rest and scout, because they differ only
## in what happens on arrival and how long it takes — see take_errand_job.
##   {"kind", "target": Vector3, "hours", "left", "line", "legs": [Vector3],
##    "leg": int, "extra": {...}}
var job_errand: Dictionary = {}
var job_assumptions: Array = []

## Who this person is in the town, and whether they work for you.
##
## Every person is a Worker; a role is what makes one a shepherd and another a
## builder, and `hired` is the difference between somebody who takes your orders
## and somebody who lives here. Citizens are not hired: they wander, they talk,
## and they will take a job if you offer them one.
var role: Role = null
var hired := true
## What this person does each morning without being told. Their own, if you
## have set one ("every morning, bring in the harvest"); otherwise the role's.
## Empty means nothing — most people wait to be asked.
var standing := ""
## How far an idle person drifts from home. Seven metres keeps the crew at
## your elbow; a citizen roams the whole town.
var wander_m := 7.0
var _rehome_left := 0.0
## The ground an idle person keeps to, in metres; empty means anywhere. Set
## for citizens to the town itself. Without it a citizen's home drifted a
## few metres each time it was re-drawn, and in ten minutes one had wandered
## eighty metres out to where no chunk is loaded — and fell through the
## world, mid-errand, with no floor under them and nothing to say about it.
var roam_rect := Rect2()

## Where this job is, said the way a person would say it ("on Mill Street",
## "out past the well"). A building takes it from its plot; a pen has no plot
## to take it from, which is why this is a string and not a Plot.
var job_where := "the town"
var job_started_hour := 0.0
var job_eta_hours := 0.0
var pending_question := ""
## A plan this worker has in hand and cannot start, and what it is short of.
## They are idle in every mechanical sense — they will follow you, they can be
## given something else — but they are not free, and the roster has to say so or
## the player is left wondering why nothing is happening.
var waiting_for := ""
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
## Progress watchdog. A worker who has stopped covering ground is stuck on
## something, and a stuck worker is a job that never finishes and a player
## waiting for news that will not come.
var _blocked_for := 0.0
## Where he was at the start of the window being judged, and how much of that
## window has run.
var _was_at := Vector3.ZERO
var _since_check := 0.0
## The wall he last walked into, as its outward normal, and how long that
## reading is kept before another is taken.
var _slide := Vector3.ZERO
var _slide_hold := 0.0
## How many times this one walk has had to be rescued. The second time is the
## last: after that he is put where he was going rather than back on his feet.
var _unwedges := 0
## Keeps a following worker from asking for a new route every frame while the
## employer is stood on the far side of a wall.
var _follow_repath := 0.0
## What they are doing on the site this minute, and how long until they pick
## something else and somewhere else to do it.
var _gesture := "plan"
var _gesture_left := 0.0
var _station_left := 0.0
var _repaths := 0
## Standing on a plot waiting for a plan to arrive. Idle, but not free to
## wander off after the employer.
var _holding := false
## The order this worker has been given and is still waiting on a plan for.
##
## The gap between "build me a bakery" and the first voxel is the better part
## of a minute on a free model, and for that whole minute the worker was
## reported as "idle" and behaved like it — they wandered in circles round the
## well, because _tick_idle never asked whether they were in the middle of
## anything. From the player's side that is indistinguishable from the order
## having been dropped on the floor.
var pondering := ""
## The journal id of the order currently being carried out, so that what gets
## built can be filed against what was asked for. Zero between orders.
var current_order := 0

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

	# Workers collide with the world and with nothing else. On the shared layer
	# the three of them jammed each other in doorways, and walking into one
	# pushed them off the path they were following — the animals were already
	# set up this way for the same reason.
	collision_layer = 0
	collision_mask = 1

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
		_:
			# Everybody else. Dressed from their name, so the same citizen looks
			# the same every time the town is raised, and no two of a dozen look
			# alike — the crew are told apart by their clothes, and so should
			# the person you are about to hire be.
			var h := hash(memory.worker_id)
			var rng := RandomNumberGenerator.new()
			rng.seed = h
			var cloths: Array[String] = ["#6b5b95", "#88705c", "#5c7d88", "#8a5c5c",
				"#7a8a5c", "#5c6e8a", "#8a7d5c", "#6e5c8a", "#5c8a7a", "#8a6a5c"]
			var accents: Array[String] = ["#d9c27a", "#c9a38a", "#a3c9c2", "#c99a9a",
				"#b8c98a", "#9ab0c9"]
			var hairs: Array[String] = ["#2a1e14", "#4a3220", "#7a5a3a", "#8a8a86",
				"#1e1a16", "#b08a5a"]
			var skins: Array[String] = ["#c99070", "#b08a68", "#7d5638", "#d8b090",
				"#8c6444", "#a87a58"]
			body.cloth_colour = Color(cloths[rng.randi() % cloths.size()])
			body.accent_colour = Color(accents[rng.randi() % accents.size()])
			body.hair_colour = Color(hairs[rng.randi() % hairs.size()])
			body.body_colour = Color(skins[rng.randi() % skins.size()])
			var hats: Array[String] = ["", "", "cap", "scarf", "brim", ""]
			body.accessory = hats[rng.randi() % hats.size()]
			body.long_coat = rng.randf() < 0.3


func display_name() -> String:
	return memory.display_name


## The morning's job, if any: the one set on this person, else the role's.
func standing_task() -> String:
	# "-" is the player having said "stop": deliberately nothing, and not the
	# role's default either.
	if standing == "-":
		return ""
	if standing != "":
		return standing
	if role != null:
		return role.standing
	return ""


## Whether this worker's hands are spoken for.
##
## Includes the thinking phase, which it did not before. A worker walking to a
## plot with an order they have not seen the plan for yet is not available: not
## for a fetching errand, not for a second instruction, and not to be painted
## in the roster as though they were standing about.
func busy() -> bool:
	if _holding or pondering != "":
		return true
	return state != State.IDLE and state != State.ASKING


# ------------------------------------------------------------------ movement

## How hard a worker has to be failing before anything is done about it.
##
## Ground actually covered, over half a second, against the ground he meant to
## cover. Both halves of that matter and both were got wrong once:
##
##   - Distance to the next waypoint is not headway. A worker scraping along a
##     wall he cannot get round is going nowhere, but the gap to the waypoint
##     shrinks the whole time, so the first watchdog never fired at all.
##   - Neither is distance covered this frame. A body wedged in a corner still
##     twitches a centimetre each way every frame as the solver pushes it out
##     and the steering pushes it back, so a per-frame test says he is walking
##     — and one of them stood in the same square metre for a minute with the
##     watchdog perfectly content.
const CHECK_WINDOW := 0.5          ## how long a stretch headway is judged over
const HEADWAY_FRACTION := 0.3      ## of the distance he meant to cover
## The ladder, in seconds of no headway. Only ever a whole number of windows,
## since that is the granularity the counter moves in — SLIDE_AFTER is really
## "on the first window he loses".
const SLIDE_AFTER := 0.4           ## start feeling along the wall
const REPATH_AFTER := 2.0          ## ask for a different route
const SKIP_AFTER := 4.5            ## give up on this waypoint
const UNWEDGE_AFTER := 7.5         ## put him back on open ground
const MAX_REPATHS := 3
## The tallest thing a worker steps up without it being a wall. A doorstep, a
## kerb, one course of foundation.
const STEP_UP_M := 0.7


func _physics_process(delta: float) -> void:
	# No ground under them is not a fall, it is a chunk that is not loaded.
	# Stand still until it is. And a body that is somehow well below the
	# ground that IS loaded has slipped through a seam: put it back on top.
	var col := VoxelWorld.to_voxel(global_position)
	if world.height_at(col.x, col.z) < 0:
		velocity = Vector3.ZERO
		return
	var floor_m := world.ground_m(global_position.x, global_position.z)
	if global_position.y < floor_m - 4.0:
		global_position.y = floor_m + 0.3
		velocity = Vector3.ZERO

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
	_note_headway(planar, delta)

	if state == State.BUILDING and _path.is_empty():
		_face_the_work(delta)
		body.work(delta, _gesture)
	else:
		body.animate(delta, planar, state == State.WALKING and job_patch != null)

	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0 and bubble != null:
			bubble.visible = false

	_tick_state(delta)


## Whether the last half second actually went anywhere, and which way to lean
## if it did not.
##
## Sliding is worked out here rather than in the steering because the wall
## normal only exists once move_and_slide has already run into something.
func _note_headway(wanted: float, delta: float) -> void:
	if wanted <= 0.0:
		_blocked_for = 0.0
		_slide = Vector3.ZERO
		_since_check = 0.0
		_was_at = global_position
		return

	# Held for half a second once taken. A normal read fresh every frame flips
	# as he rocks between two faces of a corner, and a slide direction that
	# flips with it is the rocking rather than a way out of it.
	if is_on_wall():
		_slide_hold -= delta
		if _slide == Vector3.ZERO or _slide_hold <= 0.0:
			var n := get_wall_normal()
			n.y = 0.0
			if n.length() > 0.01:
				_slide = n.normalized()
				_slide_hold = 0.5

	_since_check += delta
	if _since_check < CHECK_WINDOW:
		return
	var net := Vector2(global_position.x - _was_at.x,
		global_position.z - _was_at.z).length()
	var wanted_m := wanted * _since_check * HEADWAY_FRACTION
	_was_at = global_position
	_since_check = 0.0
	if net >= wanted_m:
		_blocked_for = 0.0
		_slide = Vector3.ZERO
		return
	_blocked_for += CHECK_WINDOW


## Turns a direction the worker wants to go in into one they can actually go
## in, given whatever they last walked into.
func _steer(dir: Vector3) -> Vector3:
	if _blocked_for < SLIDE_AFTER or _slide == Vector3.ZERO:
		return dir
	# Two ways along a wall; take the one that is not backwards.
	var along := Vector3(-_slide.z, 0.0, _slide.x)
	if along.dot(dir) < 0.0:
		along = -along
	# A little push off the wall as well, or he shaves along it and catches on
	# the next corner exactly as he caught on this one.
	return (along + _slide * 0.25 + dir * 0.2).normalized()


## A doorstep is not a wall. Rather than the old hop — which fired every frame
## a worker touched anything, and was itself most of how they ended up on
## rooftops — this measures the ground just ahead and lifts him onto it only if
## it is a step rather than a storey, and only if there is room over it.
func _try_step_up(dir: Vector3) -> void:
	if not is_on_floor() or not is_on_wall():
		return
	var ahead := global_position + dir * 0.55
	var top := world.ground_m(ahead.x, ahead.z)
	var rise := top - global_position.y
	if rise <= 0.05 or rise > STEP_UP_M:
		return
	var head := VoxelWorld.to_voxel(Vector3(ahead.x, top + 1.9, ahead.z))
	if world.is_solid(head):
		return
	global_position.y = top + 0.02
	velocity.y = 0.0


func _follow_path(delta: float) -> float:
	var target := _path[_path_i]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() < ARRIVE_DIST:
		_path_i += 1
		if _path_i >= _path.size():
			_path = PackedVector3Array()
			_path_i = 0
			_repaths = 0
			_blocked_for = 0.0
			_slide = Vector3.ZERO
			_on_arrived()
			return 0.0
		target = _path[_path_i]
		to = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)

	var speed := WALK_SPEED * memory.work_rate()
	if _after_arrival == "report":
		speed = HURRY_SPEED * memory.work_rate()
	var dir := to.normalized()
	var go := _steer(dir)
	velocity.x = go.x * speed
	velocity.z = go.z * speed

	# Face where they are going. Workers who moonwalk are not people, and +Z
	# is the front of every model in the project.
	rotation.y = lerp_angle(rotation.y, atan2(go.x, go.z), delta * 7.0)

	_try_step_up(go)
	_unwedge()
	return speed


## What to do about a worker who has been getting nowhere for a while.
##
## A ladder, gentlest first, because every rung is more of a lie than the one
## before it. Leaning along the wall is free and usually enough. A fresh route
## costs a search. Skipping the waypoint admits the route was wrong. Only the
## last rung moves a body through the world, and by the time it fires the
## alternative is a worker stood against a bakery for the rest of the session
## with a job the player is still waiting to hear about.
func _unwedge() -> void:
	if _blocked_for < REPATH_AFTER:
		return
	var goal: Vector3 = _path[_path.size() - 1]

	if _blocked_for < SKIP_AFTER:
		if _repaths >= MAX_REPATHS:
			return
		_repaths += 1
		var after := _after_arrival
		var keep := state != State.WALKING
		var had := _path
		var had_i := _path_i
		# A search that comes back with nothing must not leave him with no
		# route and no errand: walk_to empties both on the way out, and a
		# worker in that state simply stops, mid-job, for good. Put the old
		# route back and let the ladder carry on to the next rung.
		if not walk_to(goal, after, keep):
			_path = had
			_path_i = had_i
			_after_arrival = after
			_blocked_for = SKIP_AFTER
		return

	if _blocked_for < UNWEDGE_AFTER:
		if _path_i < _path.size() - 1:
			_path_i += 1
			_blocked_for = REPATH_AFTER
			_slide = Vector3.ZERO
		return

	_blocked_for = 0.0
	_repaths = 0
	_slide = Vector3.ZERO
	_unwedges += 1
	if _unwedges < 2:
		# Back onto open ground. The nav grid is asked where that is rather
		# than dropping him on the waypoint: a waypoint can sit under an eave,
		# and the old version put a wedged worker straight back into the place
		# he was wedged in.
		var here := nav.nearest_walkable_world(global_position)
		global_position = Vector3(here.x, world.ground_m(here.x, here.z) + 0.3, here.z)
		velocity = Vector3.ZERO
		return

	# Twice is enough. Whatever is wrong with this route is not going to come
	# right by trying it again, and a job the player is waiting on matters more
	# than the walk to it looking honest, so he finishes the journey the only
	# way left and gets on with the work.
	var end := nav.nearest_walkable_world(goal)
	global_position = Vector3(end.x, world.ground_m(end.x, end.z) + 0.3, end.z)
	velocity = Vector3.ZERO
	_path = PackedVector3Array()
	_path_i = 0
	_unwedges = 0
	_on_arrived()


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
	var go := _steer(dir)
	velocity.x = go.x * speed
	velocity.z = go.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(go.x, go.z), delta * 7.0)
	_try_step_up(go)

	# Walking straight at the employer is right up until a house is in the way.
	# Leaning along a wall gets somebody round a corner; it does not get them
	# round a whole building, so after a couple of seconds of getting nowhere
	# the crew stops improvising and asks for a route like anybody else.
	#
	# Only from a distance, though. Within a few metres there is nothing
	# between them worth routing around, and a follower who switches to a path
	# walks all the way onto their slot instead of easing up short of it —
	# which reads as the crew shuffling about while you stand still.
	_follow_repath -= delta
	if d > FOLLOW_CHASE * 1.6 and _blocked_for > REPATH_AFTER \
			and _follow_repath <= 0.0:
		_follow_repath = 3.0
		_blocked_for = 0.0
		_slide = Vector3.ZERO
		walk_to(want, "idle", true)
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
	# Each ring of six stands a pace and a half further back than the last.
	var ring := follow_slot / FOLLOW_BEARINGS.size()
	var back := 1.0 if follow_slot % FOLLOW_BEARINGS.size() < 3 else 1.55
	return employer.global_position + out * FOLLOW_SLOT_M * (back + ring * 0.9)


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


## `keep_state` is for a worker who is walking somewhere *as part of* what they
## are already doing — crossing their own building site to work the other
## corner — rather than setting off on a new job. Their state is still
## BUILDING, so the wall keeps going up while they cross.
func walk_to(target: Vector3, then: String = "", keep_state: bool = false) -> bool:
	_after_arrival = then
	_path = nav.path(global_position, target)
	_path_i = 0
	_blocked_for = 0.0
	_slide = Vector3.ZERO
	_slide_hold = 0.0
	_since_check = 0.0
	_was_at = global_position
	_unwedges = 0
	if _path.is_empty():
		_after_arrival = ""
		return false
	if not keep_state:
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
		"stock":
			# The errand ends where it arrives. There is nothing to put up, so
			# the animals are turned out on the spot and that is the job done.
			_deliver_stock()
		"errand":
			_arrive_errand()
		"station":
			# Only crossed the site. Still building, and now facing the work.
			state = State.BUILDING
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
			# An errand with hours in it — a shift, a rest, a watch — is worked
			# on the spot rather than round a site, so it does not go through
			# _work_the_site and its wandering between stations.
			if not job_errand.is_empty():
				_tick_errand(game_hours, delta)
				return
			_work_the_site(game_hours)
			if job_quarry != null:
				job_quarry.advance(game_hours)
				if job_quarry.finished:
					_finish_quarry()
				return
			if job_craft != null:
				job_craft.advance(game_hours)
				if job_craft.finished:
					_finish_craft()
				return
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
			# Coming back to say the job is done is a beat, not a place to
			# live. Nothing used to end this state: a worker walked home,
			# reported, and then stood by the well for the rest of the
			# session — never idle, so never following, never wandering, and
			# never a candidate for the next errand. One job each and then
			# three statues, which from where the player stands is exactly
			# what being stuck looks like.
			_speak_timer += delta
			if _speak_timer >= REPORT_BEAT:
				_speak_timer = 0.0
				_clear_job()      # which puts them back to idle


func _tick_idle(delta: float) -> void:
	if _tags_along():
		return                        # steering handles it, no wandering
	if _holding or pondering != "":
		# Waiting on a plan for an order already given. Standing on the plot
		# looking at it is the whole point; drifting back to the well is how
		# this looked like three people ignoring you.
		return
	_idle_timer -= delta
	if _idle_timer > 0.0 or not _path.is_empty():
		return
	_idle_timer = randf_range(4.0, 11.0)
	# Drift around home rather than standing to attention — but drift to
	# somewhere there is actually room to stand. A random point near the well
	# lands inside whatever has just been built there about a third of the
	# time, and a worker sent to the middle of a bakery walks into the front
	# wall and stays there.
	#
	# A citizen roams further, and now and then moves house: the point of
	# people in the streets is that they are in the streets, not standing in a
	# knot round one spot for the whole session.
	if not hired:
		_rehome_left -= delta
		if _rehome_left <= 0.0:
			_rehome_left = randf_range(60.0, 140.0)
			var far := Vector3(randf_range(-wander_m, wander_m), 0.0,
				randf_range(-wander_m, wander_m)) * 1.6
			var next := _keep_in(home + far)
			var ncell := nav.nearest_walkable(nav.to_cell(next), 12)
			if nav.is_walkable(ncell):
				home = nav.to_world(ncell)
	var away := Vector3(randf_range(-wander_m, wander_m), 0.0,
		randf_range(-wander_m, wander_m))
	var tcell := nav.nearest_walkable(nav.to_cell(_keep_in(home + away)), 8)
	if not nav.is_walkable(tcell):
		return
	var target := nav.to_world(tcell)
	target.y = world.ground_m(target.x, target.z)
	walk_to(target, "idle")


## Drops everything: the job, the walk, the question. For somebody being let
## go — a dismissed worker does not finish the errand they were on, and a
## worker rehired later must not still be carrying it.
func drop_everything() -> void:
	_path = PackedVector3Array()
	_path_i = 0
	_after_arrival = ""
	pending_question = ""
	pondering = ""
	waiting_for = ""
	velocity = Vector3.ZERO
	_clear_job()


## Ends an idle stroll on the spot. A citizen has nothing else to be in the
## middle of, so this is safe to call the moment they are taken on — and it
## has to be, or the first order they get is refused for the walk they were
## on when you spoke to them.
func stop_wandering() -> void:
	if state == State.WALKING and _after_arrival == "idle":
		_path = PackedVector3Array()
		_path_i = 0
		_after_arrival = ""
		state = State.IDLE
		velocity = Vector3.ZERO


## A point pulled back inside the roam rectangle, if there is one.
func _keep_in(p: Vector3) -> Vector3:
	if roam_rect.size.x <= 0.0:
		return p
	return Vector3(clampf(p.x, roam_rect.position.x, roam_rect.end.x), p.y,
		clampf(p.z, roam_rect.position.y, roam_rect.end.y))


# --------------------------------------------------------------- errands

## A walk with something at the end of it.
##
## Every role that is not a builder is mostly made of these — a watchman is
## patrol and wait, a shopkeeper is station, a farmhand is harvest and collect.
## They share one job because they differ only in what happens on arrival and
## how long it takes; giving each its own state would have been the same
## walk-out, do, walk-back written eight times.
##
## `legs` is for a patrol: the places in order, walked round until the hours
## run out. Everything else has one target.
func take_errand_job(kind: String, target: Vector3, hours: float, line: String,
		extra: Dictionary = {}, legs: Array = []) -> bool:
	job_errand = {
		"kind": kind, "target": target, "hours": hours, "left": hours,
		"line": line, "legs": legs, "leg": 0, "extra": extra,
		"count": 0,
	}
	job_where = str(extra.get("where", "there"))
	job_started_hour = clock.day * 24.0 + clock.hour
	job_eta_hours = maxf(hours, 0.3)
	_holding = false

	if line != "":
		_say(line, "plan")
	# "Say this" has no walk in it at all.
	if kind == "speak":
		_say(str(extra.get("line", "")), "talk")
		_finish_errand()
		return true

	var stand := target
	if not legs.is_empty():
		stand = legs[0]
	stand.y = world.ground_m(stand.x, stand.z)
	if Vector2(global_position.x - stand.x, global_position.z - stand.z).length() < 2.0:
		_path = PackedVector3Array()
		_arrive_errand()
		return true
	if not walk_to(stand, "errand"):
		job_errand = {}
		job_failed.emit(self, Validator.error("unreachable_ground",
			"I cannot get there — something is in the way."))
		_clear_job()
		return false
	return true


## On arrival. What happens depends on the errand: some are over the moment
## they get there, some are a shift that now starts, and a patrol is only at
## the end of one leg.
func _arrive_errand() -> void:
	if job_errand.is_empty():
		state = State.IDLE
		return
	var kind := str(job_errand["kind"])
	var extra: Dictionary = job_errand["extra"]
	match kind:
		"go":
			_say("Here.", "done")
			_finish_errand()
		"wait", "station", "rest":
			if float(job_errand["hours"]) <= 0.0:
				_finish_errand()
				return
			# A shift. Stay here and be seen doing it.
			state = State.BUILDING
			var default_gesture := "hammer"
			if kind == "wait":
				default_gesture = "survey"
			elif kind == "rest":
				default_gesture = "plan"
			_gesture = str(extra.get("doing", default_gesture))
			if _gesture not in Humanoid.GESTURES:
				_gesture = default_gesture
			_gesture_left = 0.0
			if kind == "rest":
				_say("Turning in for a while.", "talk")
		"patrol":
			var legs: Array = job_errand["legs"]
			if legs.is_empty():
				_finish_errand()
				return
			# On to the next place. Hours tick down while walking, in
			# _tick_errand, which is what ends the round.
			job_errand["leg"] = (int(job_errand["leg"]) + 1) % legs.size()
			state = State.BUILDING
			var next: Vector3 = legs[int(job_errand["leg"])]
			next.y = world.ground_m(next.x, next.z)
			if not walk_to(next, "errand", true):
				_finish_errand()
		"harvest":
			var farm: Farm = extra.get("farm", null)
			var rect: Rect2i = extra.get("rect", Rect2i())
			var n := 0
			if farm != null:
				for z in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						if farm.harvest(Vector2i(x, z)) != "":
							n += 1
			job_errand["count"] = n
			memory.practise("carpentry", 0.2)
			if n == 0:
				_say("Nothing ripe out here yet.", "refuse")
			else:
				_say("Brought in %d. It is in the stores." % n, "done")
			_finish_errand()
		"collect":
			var stock: Livestock = extra.get("livestock", null)
			var got := {}
			if stock != null:
				got = stock.collect_near(global_position, float(extra.get("radius", 14.0)))
			var total := 0
			for k: String in got:
				total += int(got[k])
			job_errand["count"] = total
			if total == 0:
				_say("Nothing lying about to pick up.", "refuse")
			else:
				var parts: Array[String] = []
				for k2: String in got:
					parts.append("%d %s" % [int(got[k2]), k2])
				_say("Picked up %s." % " and ".join(parts), "done")
			_finish_errand()
		"scout":
			var report := str(extra.get("report", ""))
			if report != "":
				_say(report, "done")
			_finish_errand()
		"trade":
			var t: Town = extra.get("town", null)
			var action := str(extra.get("action", "sell"))
			var what := str(extra.get("kind", ""))
			var n := int(extra.get("count", 0))
			if t == null or what == "":
				_finish_errand()
				return
			if action == "buy":
				var got := t.buy(what, n)
				if got == 0:
					_say("The purse would not stretch to any %s." % what.replace("_", " "), "refuse")
				else:
					_say("Bought %d %s. The purse holds %d." % [got, what.replace("_", " "), t.coins], "done")
			else:
				var made := t.sell(what, n)
				if made == 0:
					_say("There was no %s to sell." % what.replace("_", " "), "refuse")
				else:
					_say("Sold %s for %d coins." % [what.replace("_", " "), made], "done")
			_finish_errand()
		"cook", "craft", "fish", "hunt":
			# A shift with something to show at the end of it. The yield is
			# applied when the hours are up, in _tick_errand.
			if float(job_errand["hours"]) <= 0.0:
				job_errand["hours"] = 4.0
				job_errand["left"] = 4.0
			state = State.BUILDING
			_gesture = str(extra.get("doing", "hammer"))
			if _gesture not in Humanoid.GESTURES:
				_gesture = "hammer"
			_gesture_left = 0.0
		"water":
			var farm: Farm = extra.get("farm", null)
			var rect: Rect2i = extra.get("rect", Rect2i())
			var n2 := farm.water(rect, 2.0) if farm != null else 0
			if n2 == 0:
				_say("There is nothing sown here to water.", "refuse")
			else:
				_say("Watered %d tiles. They will come on quicker for a couple of days." % n2, "done")
			memory.practise("carpentry", 0.1)
			_finish_errand()
		"tend":
			var stock: Livestock = extra.get("livestock", null)
			var n3 := 0
			if stock != null:
				n3 = stock.tend_near(global_position, float(extra.get("radius", 14.0)), 24.0)
			if n3 == 0:
				_say("No animals here to see to.", "refuse")
			else:
				_say("Saw to %d of them. They will give well for a day." % n3, "done")
			_finish_errand()
		"teach":
			# A lesson: stand with them for the hours, then they are better at
			# it. The pupil is nudged when the time is up.
			if float(job_errand["hours"]) <= 0.0:
				job_errand["hours"] = 3.0
				job_errand["left"] = 3.0
			state = State.BUILDING
			_gesture = "plan"
			_gesture_left = 0.0
		"decorate":
			var root: Node = extra.get("props_root", null)
			var spots: Array = extra.get("spots", [])
			var kinds: Array = ["lantern", "basket", "pot", "barrel", "crate", "hay"]
			var placed := 0
			if root != null:
				for i in spots.size():
					var at: Vector3 = spots[i]
					var prop := str(kinds[i % kinds.size()])
					Props.spawn(prop, at, randf() * TAU, root)
					placed += 1
			if placed == 0:
				_say("There was nowhere to put anything.", "refuse")
			else:
				_say("Dressed the front up a bit — %d pieces." % placed, "done")
			_finish_errand()
		_:
			_finish_errand()


## Working a shift: hours tick down, the gesture repeats, and when the time is
## up they are done. A patrol also ticks here, while walking, so a watchman's
## night ends at the hour and not at the end of a lap.
##
## Only the hours are counted here. _physics_process already walks whatever
## path is set and plays the work gesture whenever the state is BUILDING with
## nowhere to go, so a patrol moves and a shift is seen to be worked without
## this needing to touch either.
func _tick_errand(game_hours: float, _delta: float) -> void:
	job_errand["left"] = float(job_errand["left"]) - game_hours
	var kind := str(job_errand["kind"])
	if float(job_errand["left"]) <= 0.0:
		var extra: Dictionary = job_errand["extra"]
		match kind:
			"rest":
				memory.nudge("morale", 0.15)
				_say("Better for that.", "talk")
			"station":
				_say("Shift's done.", "done")
			"patrol":
				_say("Round's done. All quiet.", "done")
			"cook", "craft":
				var t: Town = extra.get("town", null)
				var batches := int(extra.get("batches", 1))
				var made := t.convert(extra.get("inputs", {}), extra.get("outputs", {}),
					batches) if t != null else 0
				memory.practise("machining" if kind == "craft" else "carpentry", 0.4)
				if made == 0:
					_say("There was nothing in the stores to %s with." % kind, "refuse")
				else:
					var out: Dictionary = extra.get("outputs", {})
					var parts: Array[String] = []
					for k: String in out:
						parts.append("%d %s" % [int(out[k]) * made, k])
					_say("Made %s." % " and ".join(parts), "done")
			"fish", "hunt":
				var t2: Town = extra.get("town", null)
				var n := int(extra.get("food", 0))
				if t2 != null and n > 0:
					t2.produce("food", n)
					_say("Back with food for %d." % n, "done")
				else:
					_say("Nothing biting today.", "refuse")
			"teach":
				var pupil: Worker = extra.get("pupil", null)
				var skill := str(extra.get("skill", "carpentry"))
				if pupil != null and is_instance_valid(pupil):
					pupil.memory.practise(skill, 2.0)
					pupil.memory.remember(clock.day, "%s taught me some %s." % [
						display_name(), skill], 0.2)
					_say("%s knows a bit more %s now." % [pupil.display_name(), skill], "done")
		_finish_errand()


func _finish_errand() -> void:
	var kind := str(job_errand.get("kind", ""))
	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	if kind != "" and kind != "speak" and kind != "go":
		memory.remember(clock.day, "%s: %s. About %d hours." % [
			kind.capitalize(), job_where, int(hours)], 0.05)
	job_errand = {}
	job_where = "the town"
	job_assumptions = []
	# Straight back to idle. Errands end where the player can see them, or
	# where the report is the whole of the result and has just been said.
	state = State.IDLE
	_path = PackedVector3Array()
	step_done.emit(self)


# ------------------------------------------------------------- on the site

## How long they keep doing one thing, and how long before they move to work a
## different part of it — both in game hours, and both ranges rather than
## fixed numbers so three workers do not switch in lockstep like machinery.
##
## Game hours rather than seconds, because a building takes eight or nine of
## them and the player can wind the clock forward through the wait. On a real
## timer, a fast-forwarded build would finish with the worker having never once
## moved off the spot they started on — which is the exact thing this is here
## to fix.
const GESTURE_HOURS := Vector2(0.22, 0.50)
const STATION_HOURS := Vector2(0.80, 1.70)


## Working the site rather than standing on one paving stone for a day.
##
## Two clocks. One picks what they are doing — reading the drawings, nailing,
## laying a course, standing back to look at it. The other walks them round to
## a different part of their own building, because nobody builds a house from a
## single spot, and a worker rooted to the ground for an in-game day is a prop
## with an animation on it rather than somebody at work.
func _work_the_site(hours: float) -> void:
	_gesture_left -= hours
	if _gesture_left <= 0.0:
		_gesture_left = randf_range(GESTURE_HOURS.x, GESTURE_HOURS.y)
		_gesture = _pick_gesture()

	# Only buildings have a site to walk round. A shaft and a field are one
	# place by definition, and sending somebody on a lap of a hole in the
	# ground would look like they had lost it.
	if job_patch == null or not _path.is_empty():
		return
	_station_left -= hours
	if _station_left > 0.0:
		return
	_station_left = randf_range(STATION_HOURS.x, STATION_HOURS.y)
	_move_station()


## What the job looks like depends on how far along it is. Setting out at the
## start, the trades in the middle, checking and making good at the end —
## somebody rendering a wall that does not exist yet is worse than no animation
## at all.
func _pick_gesture() -> String:
	if job_quarry != null:
		return _one_of(["hammer", "hammer", "lift", "lay"])
	if job_craft != null:
		return _one_of(["hammer", "measure", "lift"])
	if job_field != null:
		return _one_of(["lay", "lay", "lift", "survey"])
	var done := progress()
	if done < 0.25:
		return _one_of(["plan", "measure", "plan", "lay", "survey"])
	if done < 0.75:
		return _one_of(["hammer", "lay", "saw", "lift", "hammer", "plan"])
	return _one_of(["hammer", "survey", "plan", "lay", "measure"])


## A typed array, deliberately: indexing an untyped literal loses the element
## type and GDScript then infers Variant for whatever it is assigned to.
func _one_of(pool: Array[String]) -> String:
	return pool[randi() % pool.size()]


## Somewhere else round the building to work from. Points outside the
## footprint, a step or two back from the wall, so they are standing on the
## street rather than inside the room they have not finished yet.
func _move_station() -> void:
	var fp := job_patch.footprint
	var v := VoxelChunk.VOXEL_M
	var centre := Vector3((fp.position.x + fp.size.x * 0.5) * v, 0.0,
		(fp.position.y + fp.size.y * 0.5) * v)
	var out_m := maxf(fp.size.x, fp.size.y) * v * 0.5
	for _attempt in 8:
		var ang := randf() * TAU
		var at := centre + Vector3(cos(ang), 0.0, sin(ang)) 			* (out_m + randf_range(1.8, 3.4))
		# Round the site, not into it: on a corner of a big footprint that
		# radius still lands inside the walls.
		at = nav.nearest_walkable_world(at, 8)
		at.y = world.ground_m(at.x, at.z)
		if at.distance_to(global_position) < 2.0:
			continue
		if walk_to(at, "station", true):
			return


## Turn to the work. A worker who walked to the far corner and then hammered
## with his back to the wall is worse than one who never moved at all.
func _face_the_work(delta: float) -> void:
	var at := _work_centre()
	var to := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	if to.length() < 0.6:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), delta * 4.0)


func _work_centre() -> Vector3:
	var v := VoxelChunk.VOXEL_M
	if job_patch != null:
		var fp := job_patch.footprint
		return Vector3((fp.position.x + fp.size.x * 0.5) * v, global_position.y,
			(fp.position.y + fp.size.y * 0.5) * v)
	if job_quarry != null:
		return Vector3(job_quarry.site) * v
	if job_craft != null:
		return global_position + Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * 1.5
	if job_field != null and job_field.rect.size.x > 0:
		var fr := job_field.rect
		return Vector3((fr.position.x + fr.size.x * 0.5) * v, global_position.y,
			(fr.position.y + fr.size.y * 0.5) * v)
	return global_position


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
## Sets off for the plot before anyone knows what is going in it, and says so.
func start_thinking(instruction: String, plot: Plot) -> void:
	pondering = instruction
	job_where = plot.street_name
	current_order = memory.remember(clock.day,
		"You told me: \"%s\"." % instruction, 0.0, {
			"kind": "order", "instruction": instruction,
			"street": plot.street_name, "plot": plot.id,
		})
	set_out_for(plot)


## The plan landed, or it did not. Either way the waiting is over and whatever
## happens next has a status of its own.
func stop_thinking() -> void:
	pondering = ""


func set_out_for(plot: Plot) -> void:
	if state != State.IDLE:
		return
	_holding = true
	var stand := _stand_for(plot)
	if not walk_to(stand, "hold"):
		_holding = false


## How far off the plot edge they stand. It has to clear the margin the nav
## grid blocks off around a building site (NavGrid.refresh_world_rect, three
## cells), or the stand point is inside the block and the worker reports that
## they cannot reach a plot they are looking straight at.
const STAND_CLEAR_M := 4.5


## Where a worker stands to work on a plot: off the front of it, on the street
## side, so they are not inside their own building site.
func _stand_for(plot: Plot) -> Vector3:
	var dir := plot.street_dir
	# The plot's extent along the street direction, not always its x.
	var half := (plot.size_m().x if absi(dir.x) > 0 else plot.size_m().y) * 0.5
	var stand := plot.centre_m() + Vector3(dir) * (half + STAND_CLEAR_M)
	stand.y = world.ground_m(stand.x, stand.z)
	return stand


## Returns false if they cannot get there, so the caller can put the material
## back rather than charging the town for a house nobody can reach.
func take_job(plot: Plot, spec: Dictionary, patch: VoxelPatch,
		assumptions: Array, line: String, props_root: Node3D) -> bool:
	job_plot = plot
	job_spec = spec
	job_patch = patch
	job_assumptions = assumptions
	job_where = plot.street_name
	job_started_hour = clock.day * 24.0 + clock.hour
	memory.remember(clock.day, "Started on a %s on %s." % [
		patch.archetype.replace("_", " "), plot.street_name], 0.05, {
			"kind": "plan", "order": current_order,
			"archetype": patch.archetype, "street": plot.street_name,
			"plot": plot.id,
		})

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
		return false
	if line != "":
		_say(line, "plan")
	return true


## A fence, rather than a building. Deliberately almost the same function, and
## almost the same function is the whole argument for making an enclosure a
## VoxelPatch: it is Construction, the same pacing, the same walk out, the same
## report on the way back. The only thing a pen does not have is a plot.
func take_enclosure_job(patch: VoxelPatch, where: String, assumptions: Array,
		line: String, props_root: Node3D) -> bool:
	job_plot = null
	job_spec = {}
	job_patch = patch
	job_assumptions = assumptions
	job_where = where
	job_started_hour = clock.day * 24.0 + clock.hour

	job_construction = Construction.new(patch, world, props_root)
	# Faster than a house per voxel, because a fence is a tenth of the voxels
	# and a day and a half to put up eighty posts would read as a punishment.
	# Knocking down is quicker still, and a road is laid a stone at a time.
	var rate := 900.0
	match patch.archetype:
		"demolition": rate = 6000.0
		"road", "levelled ground": rate = 2500.0
		"tree", "grove": rate = 1500.0
	job_construction.voxels_per_hour = rate * memory.work_rate()
	job_eta_hours = float(patch.build_order.size()) / maxf(job_construction.voxels_per_hour, 1.0)

	_holding = false
	# A demolition stands at the building's own door, a pace out: its centre is
	# inside the walls, and a walk to a cell the grid cannot reach fails
	# quietly, which read as a worker ignoring you. Everything else stands in
	# the middle of what it is making — open ground when they get there, and
	# for a pen the inside of the fence, which is where the animals go next
	# and where a gate the nav grid has just learned about is no obstacle.
	var stand := Vector3.ZERO
	if patch.archetype == "demolition" and not patch.doors.is_empty():
		var d := patch.doors[0]
		stand = Vector3(float(d.x) * VoxelChunk.VOXEL_M, 0.0, float(d.z) * VoxelChunk.VOXEL_M) 			+ Vector3(patch.front) * 1.5
	else:
		var c := patch.footprint.get_center()
		stand = Vector3(float(c.x) * VoxelChunk.VOXEL_M, 0.0, float(c.y) * VoxelChunk.VOXEL_M)
	stand.y = world.ground_m(stand.x, stand.z)
	if Vector2(global_position.x - stand.x, global_position.z - stand.z).length() < 2.5:
		_path = PackedVector3Array()
		state = State.GATHERING
		_gather_hours = 0.0
		_say("%s. I will fetch what I need." % _acknowledge(), "work")
	elif not walk_to(stand, "build"):
		job_failed.emit(self, Validator.error("unreachable_ground",
			"I cannot get out to that ground — something is in the way."))
		_clear_job()
		return false
	if line != "":
		_say(line, "plan")
	return true


## An errand for livestock. There is no work object because there is no work:
## the job is the walk, and the animals are there when they arrive, which is
## the fiction — they were driven back, they did not appear.
func take_stock_job(stock: Livestock, species: String, count: int,
		centre: Vector3, spread: float, where: String, line: String) -> bool:
	job_stock = {
		"livestock": stock, "species": species, "count": count,
		"centre": centre, "spread": spread,
	}
	job_where = where
	job_started_hour = clock.day * 24.0 + clock.hour
	job_eta_hours = 0.5

	_holding = false
	var stand := centre
	stand.y = world.ground_m(stand.x, stand.z)
	# Said before the errand, not after it. When the target is where they are
	# already standing — the pen they have just this moment finished — delivery
	# is immediate, and announcing the trip afterwards had them saying "I will
	# go and fetch two hens" to two hens already standing in front of them.
	if line != "":
		_say(line, "plan")
	if Vector2(global_position.x - stand.x, global_position.z - stand.z).length() < 2.5:
		_path = PackedVector3Array()
		_deliver_stock()
		return true
	if not walk_to(stand, "stock"):
		job_stock = {}
		job_failed.emit(self, Validator.error("unreachable_ground",
			"I cannot get them out to there — something is in the way."))
		_clear_job()
		return false
	return true


## Turning the animals out, on arrival. A pen that takes fewer than asked for is
## not an error — the ground decides how many will stand up, and the worker says
## the real number rather than the one they were given.
func _deliver_stock() -> void:
	var job := job_stock
	job_stock = {}
	if job.is_empty():
		state = State.IDLE
		return
	var stock: Livestock = job["livestock"]
	var species := str(job["species"])
	var made := stock.stock_area(species, job["centre"], int(job["count"]),
		float(job["spread"]))
	memory.remember(clock.day, "Brought %d %s back." % [made, species], 0.1, {
		"kind": "done", "order": current_order, "species": species,
		"count": made, "street": job_where,
	})

	if made == 0:
		_say("There was nowhere to put them. Somewhere more open?", "refuse")
	else:
		_say("%d %s, turned out %s." % [made, Steps.plural(species, made), job_where], "done")
	# Idle rather than reporting, and straight away rather than after the report
	# beat. REPORTING is the pause for news carried home from somewhere the
	# player could not see; there is none of that here, because the errand ends
	# in front of them and they have just been told out loud.
	state = State.IDLE
	step_done.emit(self)


func _finish_job() -> void:
	var patch := job_patch
	memory.practise(_skill_for(patch), 1.0)
	nav.refresh_world_rect(patch.footprint, 3)

	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	memory.remember(clock.day,
		"Built the %s on %s. Took about %d hours." % [
			patch.archetype.replace("_", " "), job_where, int(hours)], 0.2, {
			"kind": "done", "order": current_order,
			"archetype": patch.archetype, "street": job_where,
			"plot": job_plot.id if job_plot != null else -1,
			"hours": int(hours),
		})

	job_finished.emit(self, patch)

	# Walk back and say so. Coming back to report is the beat that closes the
	# loop; a notification would not be the same thing at all.
	#
	# step_done goes out after the report walk is set up, not instead of it: if
	# there is another step, taking it re-routes them from wherever this line
	# left them, and if there is not, they carry on home with the news.
	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	var line := _completion_line(patch, hours)
	if line != "":
		_say(line, "done")
	step_done.emit(self)


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


## Sends a worker out to dig. The site is outside the town, so fetching is
## a real errand with a walk at each end rather than a number going up.
func take_quarry_job(q: Quarry, line: String) -> bool:
	job_quarry = q
	job_started_hour = clock.day * 24.0 + clock.hour
	q.voxels_per_hour = 34.0 * memory.work_rate()
	job_eta_hours = float(q.total()) / maxf(q.voxels_per_hour, 1.0)

	var stand := Vector3(q.site) * VoxelChunk.VOXEL_M
	stand.y = world.ground_m(stand.x, stand.z)
	if not walk_to(stand, "build"):
		job_quarry = null
		return false
	if line != "":
		_say(line, "plan")
	return true


## Goes to the armoury and makes the batch. `stand` is the spot in front of
## its door; the manager worked it out because it knows which building that is.
func take_craft_job(job: CraftJob, stand: Vector3, line: String) -> bool:
	job_craft = job
	job_started_hour = clock.day * 24.0 + clock.hour
	job_eta_hours = job.total_hours
	job_where = "the armoury"
	if not walk_to(stand, "build"):
		job_craft = null
		return false
	if line != "":
		_say(line, "plan")
	return true


func _finish_craft() -> void:
	var job := job_craft
	job_craft = null
	memory.remember(clock.day, "Made %s at the armoury." % job.summary(), 0.1, {
		"kind": "done", "order": current_order, "errand": job.summary(),
	})
	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	_say("%s, in the stores." % job.summary().capitalize(), "done")
	step_done.emit(self)


## Shot, or a blast. Knocks them down at nothing; never kills. They lie where
## they fell for a while, then get up with the job still theirs.
func take_hit(dmg: float, _from: Vector3, _who: Node3D) -> void:
	if _down > 0.0:
		return
	health -= dmg
	if health > 0.0:
		if randf() < 0.5:
			_say(_one_of(["Argh!", "They are shooting at us!", "Get down!"]), "refuse")
		return
	health = 0.0
	_down = 25.0
	_say("I am hit —", "refuse")
	set_physics_process(false)
	rotation.x = -PI * 0.5
	get_tree().create_timer(_down).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_down = 0.0
		health = 100.0
		rotation.x = 0.0
		set_physics_process(true)
		_say("On my feet. Where was I.", "talk"))


func _finish_quarry() -> void:
	var q := job_quarry
	job_quarry = null
	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	memory.practise("masonry", 0.3)
	memory.remember(clock.day, "Went out for %s. Took about %d hours."
		% [q.summary(), int(hours)], 0.1, {
		"kind": "done", "order": current_order, "errand": q.summary(),
		"hours": int(hours),
	})

	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	_say("Back with %s." % q.summary(), "done")
	step_done.emit(self)


func _finish_field() -> void:
	var work := job_field
	var hours := (clock.day * 24.0 + clock.hour) - job_started_hour
	memory.practise("carpentry", 0.4)
	memory.remember(clock.day, "Ploughed a field: %s." % work.summary(), 0.15, {
		"kind": "done", "order": current_order, "field": work.summary(),
	})

	var back := home
	back.y = world.ground_m(back.x, back.z)
	if not walk_to(back, "report"):
		state = State.REPORTING
	_say("Field is in — %s." % work.summary(), "done")
	job_field = null
	job_assumptions = []
	step_done.emit(self)


func _clear_job() -> void:
	_holding = false
	job_quarry = null
	job_craft = null
	job_plot = null
	job_spec = {}
	job_patch = null
	job_construction = null
	job_field = null
	job_stock = {}
	job_errand = {}
	job_where = "the town"
	job_assumptions = []
	state = State.IDLE


func _skill_for(patch: VoxelPatch) -> String:
	var walls := str(patch.cost.keys()[0] if not patch.cost.is_empty() else "timber")
	if walls in ["brick", "sandstone", "granite", "cobble", "concrete"]:
		return "masonry"
	return "carpentry"


func progress() -> float:
	if not job_errand.is_empty():
		var h := float(job_errand["hours"])
		if h <= 0.0:
			return 0.0
		return clampf(1.0 - float(job_errand["left"]) / h, 0.0, 1.0)
	if job_quarry != null:
		return job_quarry.progress()
	if job_craft != null:
		return job_craft.progress()
	if job_field != null:
		return job_field.progress()
	if job_construction == null:
		return 0.0
	return job_construction.progress()


## Where this worker is and what is holding them up. Diagnostic only.
func debug_state() -> String:
	return "%s at %s, path %d/%d, after=%s, on_floor=%s, vel=%.1f, blocked=%.1fs" % [
		status_text(), str(global_position.round()), _path_i, _path.size(),
		_after_arrival if _after_arrival != "" else "-",
		"yes" if is_on_floor() else "NO",
		Vector2(velocity.x, velocity.z).length(), _blocked_for]


func status_text() -> String:
	# Said before the state machine gets a look in, because during the wait the
	# state is IDLE or WALKING and neither of those words is true: they have
	# your order, they are on it, and the plan is what has not arrived yet.
	if pondering != "":
		if state == State.WALKING:
			return "heading to %s" % job_where
		return "sizing up the plot on %s" % job_where

	match state:
		State.IDLE:
			if waiting_for != "":
				return "waiting on %s" % waiting_for
			return "idle"
		State.WALKING:
			if job_quarry != null:
				return "off to fetch %s" % job_quarry.material.replace("_", " ")
			if job_craft != null:
				return "off to the armoury" 
			if not job_stock.is_empty():
				return "off for the %s" % str(job_stock["species"])
			if not job_errand.is_empty():
				return "off to %s" % job_where
			return "on the way" if (job_patch != null or job_field != null) 				else "walking"
		State.GATHERING:
			return "fetching materials"
		State.BUILDING:
			if not job_errand.is_empty():
				match str(job_errand["kind"]):
					"patrol": return "on the round"
					"rest": return "resting"
					"wait": return "waiting at %s" % job_where
					_: return "working %s — %d%%" % [job_where, int(progress() * 100.0)]
			if job_quarry != null:
				return "digging — %d%%" % int(progress() * 100.0)
			if job_craft != null:
				return "making %s — %d%%" % [job_craft.summary(), int(progress() * 100.0)]
			if job_field != null:
				return "ploughing — %d%%" % int(progress() * 100.0)
			# A pen has a patch but no plot, which is the only place that
			# distinction ever surfaces to the player.
			if job_patch != null and job_plot == null:
				return "fencing — %d%%" % int(progress() * 100.0)
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
	# Works that are not buildings do not go "up". The demolition says
	# nothing here at all: the dispatcher says what came down and what was
	# salvaged, the moment the register is updated.
	match patch.archetype:
		"demolition": return ""
		"road": return "The road is laid."
		"tree": return "The tree is in."
		"grove": return "The trees are in."
		"levelled ground": return "That ground is level now."
		"pen": return "The pen is up."
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
	# Whatever they walked out to a plot for is not coming until the player
	# answers, so they are no longer standing by for it. Without this a worker
	# whose plan was refused held the plot for the rest of the session: still
	# idle, but never free to fall in behind the player again, which from the
	# outside is a man who has wandered off and will not come back.
	_holding = false
	memory.ask(clock.day, question)
	memory.remember(clock.day, "Asked you: \"%s\"" % question, 0.0, {
		"kind": "asked", "order": current_order, "question": question,
	})
	_say(question, "question")


func resolve_question() -> void:
	pending_question = ""
	_holding = false
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
