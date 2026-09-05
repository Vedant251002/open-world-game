extends Node3D
class_name Crew
## Mira, Tobias and Ren — the only three people you can talk to.
##
## The cast is fixed at three because the player has to hold all three mental
## models at once (game-design-doc.md §4). Their numbers here are the whole of
## their personality: everything the player will ever notice about them comes
## out of these traits running through WorkerMemory.
##
## Note the direction of question_threshold: it is the bar an instruction has to
## be murkier than before they will interrupt you. So Tobias, who checks before
## nearly every job, is nearly zero, and Mira, who checks nothing, is nearly one.

signal worker_spoke(worker: Worker, line: String, kind: String)
signal job_done(worker: Worker, patch: VoxelPatch)
signal job_failed(worker: Worker, err: Dictionary)

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

var workers: Array[Worker] = []
var by_id: Dictionary = {}


func spawn(world: VoxelWorld, nav: NavGrid, clock: GameClock, town: Town,
		employer: Node3D, at: Vector3) -> void:
	for i in ROSTER.size():
		var d: Dictionary = ROSTER[i]
		var mem := WorkerMemory.make(str(d["id"]), str(d["name"]),
			d["traits"], d["disposition"], d["skills"])

		var w := Worker.new()
		w.name = str(d["name"])
		add_child(w)
		w.setup(mem, nav, world, clock, town)
		w.employer = employer
		w.follow_slot = i
		w.seed_follow(employer.global_position)
		w.home = at

		var spot := at + Vector3(cos(i * TAU / 3.0) * 2.6, 0.0, sin(i * TAU / 3.0) * 2.6)
		spot.y = world.ground_m(spot.x, spot.z) + 0.3
		w.global_position = spot

		w.said.connect(func(wk: Worker, line: String, kind: String) -> void:
			worker_spoke.emit(wk, line, kind))
		w.job_finished.connect(func(wk: Worker, p: VoxelPatch) -> void:
			job_done.emit(wk, p))
		w.job_failed.connect(func(wk: Worker, e: Dictionary) -> void:
			job_failed.emit(wk, e))

		workers.append(w)
		by_id[str(d["id"])] = w


func get_worker(id: String) -> Worker:
	return by_id.get(id)


