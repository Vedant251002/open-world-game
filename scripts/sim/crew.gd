extends Node3D
class_name Crew
## Everybody in the town: the three you start with, and everybody else.
##
## The cast used to be fixed at three because the player has to hold every
## mental model at once (game-design-doc.md §4). That is still the rule for the
## people who work for you, and it is still why the starting crew is three. It
## was never a reason for the streets to be empty. So the town now has
## citizens as well: people who walk about, can be spoken to, and can be hired
## into a role the player defines — at which point they join the crew and are
## held to the same standard as Mira, Tobias and Ren.
##
## Everyone is a Worker. A citizen is a Worker with `hired` false and the
## citizen role, which lets them talk and wander and nothing else. Hiring flips
## one flag and sets a role; nothing is re-created.
##
## The numbers on the three are the whole of their personality: everything the
## player will ever notice about them comes out of these traits running
## through WorkerMemory. Note the direction of question_threshold: it is the bar
## an instruction has to be murkier than before they will interrupt you. So
## Tobias, who checks before nearly every job, is nearly zero, and Mira, who
## checks nothing, is nearly one.

signal worker_spoke(worker: Worker, line: String, kind: String)
signal job_done(worker: Worker, patch: VoxelPatch)
signal job_failed(worker: Worker, err: Dictionary)
## Somebody joined the crew, or left it.
signal roster_changed()

const ROSTER := [
	{
		"id": "mira", "name": "Mira",
		# Fast, eager, over-literal. Starts before you finish talking and takes
		# every word at face value, which is how the chimney ends up indoors.
		"traits": {"speed": 0.95, "literalism": 0.95, "initiative": 0.40,
			"question_threshold": 0.88, "criticism_sensitivity": 0.90},
		"disposition": {"trust_in_player": 0.62, "morale": 0.85, "confidence": 0.55},
		"skills": {"carpentry": 2, "masonry": 1, "machining": 0, "piloting": 0},
	},
	{
		"id": "tobias", "name": "Tobias",
		# Careful, slow, precise. Asks before nearly every job and is almost
		# never wrong. Half Mira's pace, and quietly judgemental about it.
		"traits": {"speed": 0.25, "literalism": 0.60, "initiative": 0.20,
			"question_threshold": 0.12, "criticism_sensitivity": 0.18},
		"disposition": {"trust_in_player": 0.45, "morale": 0.70, "confidence": 0.72},
		"skills": {"carpentry": 3, "masonry": 3, "machining": 1, "piloting": 0},
	},
	{
		"id": "ren", "name": "Ren",
		# Creative, confident, doesn't listen. Your instruction is a starting
		# suggestion. Sometimes the best building in town, sometimes a demolition.
		"traits": {"speed": 0.60, "literalism": 0.08, "initiative": 0.95,
			"question_threshold": 0.90, "criticism_sensitivity": 0.05},
		"disposition": {"trust_in_player": 0.80, "morale": 0.80, "confidence": 0.92},
		"skills": {"carpentry": 2, "masonry": 2, "machining": 2, "piloting": 1},
	},
]

## Names for the people in the streets. Drawn in order with the seed, so the
## same town has the same neighbours every time it is raised.
const CITIZEN_NAMES := ["Ada", "Bram", "Cora", "Dov", "Elin", "Faye", "Gil",
	"Hana", "Idris", "June", "Kit", "Lior", "Mae", "Nils", "Oona", "Pim",
	"Rosa", "Sef", "Tam", "Una", "Wren", "Yara", "Zed", "Bea", "Cal", "Dot"]

## How many people are in the streets, and how far out they stop being
## simulated. Twelve is enough that you meet somebody wherever you go. Beyond
## FAR a citizen stops thinking, exactly as the animals do — they keep their
## place, so the town is as you left it when you come back.
##
## Forty-five metres, not seventy: a character body costs physics every
## frame whether or not it can be seen, and at seventy the whole dozen were
## live at once from the middle of town, which was worth 1.7 ms a frame on
## the bench. At forty-five it is the six or seven you might actually walk
## into. The bodies beyond still stand where they were.
const CITIZENS := 12
const FAR := 45.0
const CITIZEN_WANDER_M := 22.0

var workers: Array[Worker] = []          ## everyone: crew and citizens
var by_id: Dictionary = {}
var roles: RoleBook = null

var _world: VoxelWorld
var _nav: NavGrid
var _clock: GameClock
var _town: Town
var _employer: Node3D
var _player: Node3D
var _cull_t := 0.0


func spawn(world: VoxelWorld, nav: NavGrid, clock: GameClock, town: Town,
		employer: Node3D, at: Vector3) -> void:
	_world = world
	_nav = nav
	_clock = clock
	_town = town
	_employer = employer
	_player = employer
	if roles == null:
		roles = RoleBook.new()

	for i in ROSTER.size():
		var d: Dictionary = ROSTER[i]
		var mem := WorkerMemory.make(str(d["id"]), str(d["name"]),
			d["traits"], d["disposition"], d["skills"])
		var w := _raise(mem, at)
		w.role = roles.get_role("builder")
		w.hired = true
		w.employer = employer
		w.follow_slot = i
		w.seed_follow(employer.global_position)

		var spot := at + Vector3(cos(i * TAU / 3.0) * 2.6, 0.0, sin(i * TAU / 3.0) * 2.6)
		spot.y = world.ground_m(spot.x, spot.z) + 0.3
		w.global_position = spot


## People in the streets. Scattered over the town's walkable ground rather than
## round the well, so the first thing you see on arriving is not a crowd.
func spawn_citizens(count: int, seed: int, bounds: Rect2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var names := CITIZEN_NAMES.duplicate()
	# Coats dealt from a shuffled deck rather than drawn at random, so no two
	# of the first dozen match. Random draws collided about two times in
	# three, and two strangers in the same coat read as the same stranger.
	var coats: Array[String] = ["#6b5b95", "#88705c", "#5c7d88", "#8a5c5c",
		"#7a8a5c", "#5c6e8a", "#8a7d5c", "#6e5c8a", "#5c8a7a", "#8a6a5c",
		"#9a6b4a", "#4a6b9a", "#7b4a6b", "#6b9a4a"]
	for i in coats.size():
		var j := rng.randi_range(i, coats.size() - 1)
		var tmp := coats[i]
		coats[i] = coats[j]
		coats[j] = tmp
	for i in count:
		if names.is_empty():
			break
		var name: String = names.pop_at(rng.randi() % names.size())
		var id := "cit_" + name.to_lower()
		var mem := WorkerMemory.make(id, name,
			{"speed": rng.randf_range(0.3, 0.9), "literalism": rng.randf_range(0.2, 0.9),
				"initiative": rng.randf_range(0.1, 0.9),
				"question_threshold": rng.randf_range(0.2, 0.9),
				"criticism_sensitivity": rng.randf_range(0.1, 0.9)},
			{"trust_in_player": 0.5, "morale": rng.randf_range(0.5, 0.9),
				"confidence": rng.randf_range(0.3, 0.8)},
			{"carpentry": rng.randi_range(0, 1), "masonry": rng.randi_range(0, 1),
				"machining": 0, "piloting": 0})

		# Somewhere on the streets: a random spot in the inner two-thirds of
		# the town, snapped to the nearest walkable cell, checked. The grid
		# hands back the point it was given when it finds nothing near, so
		# the check has to be asked outright — a citizen stood inside a wall
		# can neither wander nor take an order, and looks merely idle.
		var v := VoxelChunk.VOXEL_M
		var inner := Rect2i(bounds.position + bounds.size / 6, bounds.size * 2 / 3)
		var at := Vector3.ZERO
		var found := false
		for _try in 24:
			var vx := rng.randi_range(inner.position.x, inner.end.x - 1)
			var vz := rng.randi_range(inner.position.y, inner.end.y - 1)
			var cell := _nav.nearest_walkable(Vector2i(vx, vz), 10)
			if _nav.is_walkable(cell):
				at = _nav.to_world(cell)
				found = true
				break
		if not found:
			at = _nav.nearest_walkable_world(_employer.global_position, 16)
		at.y = _world.ground_m(at.x, at.z)

		var w := _raise(mem, at)
		w.role = roles.get_role("citizen")
		w.hired = false
		w.employer = null
		w.wander_m = CITIZEN_WANDER_M
		w.global_position = at + Vector3(0, 0.3, 0)
		w.body.cloth_colour = Color(coats[i % coats.size()])
		# Kept to the town, in metres, with a street's width of slack.
		w.roam_rect = Rect2(Vector2(bounds.position) * v - Vector2(6, 6),
			Vector2(bounds.size) * v + Vector2(12, 12))


func _raise(mem: WorkerMemory, home: Vector3) -> Worker:
	var w := Worker.new()
	w.name = mem.display_name
	add_child(w)
	w.setup(mem, _nav, _world, _clock, _town)
	w.home = home
	w.said.connect(func(wk: Worker, line: String, kind: String) -> void:
		worker_spoke.emit(wk, line, kind))
	w.job_finished.connect(func(wk: Worker, p: VoxelPatch) -> void:
		job_done.emit(wk, p))
	w.job_failed.connect(func(wk: Worker, e: Dictionary) -> void:
		job_failed.emit(wk, e))
	workers.append(w)
	by_id[mem.worker_id] = w
	return w


func get_worker(id: String) -> Worker:
	return by_id.get(id)


## The people who work for you, in the order they were taken on.
func hired() -> Array[Worker]:
	var out: Array[Worker] = []
	for w: Worker in workers:
		if w.hired:
			out.append(w)
	return out


func citizens() -> Array[Worker]:
	var out: Array[Worker] = []
	for w: Worker in workers:
		if not w.hired:
			out.append(w)
	return out


## Taking somebody on. They fall in behind you like the rest of the crew, in
## the next free slot, and from here on they are held to the role they were
## given: the planner will only use its capabilities, and they will say so
## when asked for anything else.
func hire(w: Worker, role: Role) -> void:
	w.stop_wandering()
	w.role = role
	w.hired = true
	w.employer = _employer
	w.wander_m = 7.0
	w.follow_slot = hired().size() - 1
	w.seed_follow(_employer.global_position)
	w.home = _employer.global_position
	w.set_physics_process(true)
	w.visible = true
	roster_changed.emit()


## Letting somebody go. They keep their name and their memory of you, and go
## back to being a citizen — which means the next time you talk to them, they
## remember what happened.
func dismiss(w: Worker) -> void:
	if w.memory.worker_id in ["mira", "tobias", "ren"]:
		return                      # the three are the game; they do not leave
	w.drop_everything()
	w.role = roles.get_role("citizen")
	w.hired = false
	w.employer = null
	w.wander_m = CITIZEN_WANDER_M
	w.home = w.global_position
	roster_changed.emit()


## Far citizens stop thinking. Same rule as the animals, for the same reason:
## a dozen character bodies on the far side of the valley are a dozen bodies
## nobody can see, and the frame budget is not free. The crew are never
## culled — they are following you, or they are on a job you are waiting on.
func _process(delta: float) -> void:
	_cull_t += delta
	if _cull_t < 0.5 or _player == null:
		return
	_cull_t = 0.0
	var here := _player.global_position
	for w: Worker in workers:
		# Only the unhired. A stroll counts as busy() and is exactly what a
		# citizen is doing most of the time, so that is not a reason to keep
		# simulating them — nothing waits on a citizen's walk.
		if w.hired:
			continue
		var near := w.global_position.distance_to(here) < FAR
		if w.is_physics_processing() != near:
			w.set_physics_process(near)
			w.visible = near
