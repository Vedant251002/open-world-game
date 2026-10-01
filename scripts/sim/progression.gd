extends Node
class_name Progression
## The village's standing: a rank (Hamlet, Village, Town, City) read straight
## off Town.tier, and a list of milestones that each pay a small reward the
## first time they are met.
##
## Nothing here changes how the town works. It only watches (the register, the
## crew, the farm, the kingdom's census) and says "well done" at the right
## moments. State is polled once a second and on the few signals that matter,
## so a milestone can never be missed by a signal being emitted while nobody
## listened, and a loaded save simply finds its achievements already in hand.

signal milestone_reached(id: String, title: String, reward: int)
signal rank_changed(tier: int, rank_name: String)

const RANKS := ["Hamlet", "Village", "Town", "City"]
const POLL_SECONDS := 1.0
## Founding buildings are on the register from day zero with no builder; only
## what the crew raised counts toward "your" village.
const FOUNDING_POPULATION := 15

## id, title, how it reads on the list, coin reward. Order is the order shown.
const MILESTONES: Array[Dictionary] = [
	{"id": "first_order", "title": "First Words", "desc": "Give an order that a worker accepts.", "reward": 100},
	{"id": "first_building", "title": "First Foundation", "desc": "See your first building finished.", "reward": 300},
	{"id": "build_5", "title": "A Proper Street", "desc": "Have five buildings raised by your crew.", "reward": 400},
	{"id": "build_10", "title": "Builders' Pride", "desc": "Have ten buildings raised by your crew.", "reward": 700},
	{"id": "first_hire", "title": "Another Pair of Hands", "desc": "Hire somebody from the street.", "reward": 200},
	{"id": "hired_5", "title": "A Payroll", "desc": "Have five people working for you.", "reward": 400},
	{"id": "first_harvest", "title": "First Harvest", "desc": "Bring in a crop from the field.", "reward": 250},
	{"id": "first_goal", "title": "Mission Accomplished", "desc": "See a goal you set carried through to the end.", "reward": 500},
	{"id": "week_one", "title": "A Full Week", "desc": "Reach day 8 with the village still standing.", "reward": 300},
	{"id": "pop_20", "title": "Full Houses", "desc": "A population of twenty.", "reward": 400},
	{"id": "pop_35", "title": "Bustling", "desc": "A population of thirty-five.", "reward": 800},
	{"id": "tier_2", "title": "A Village", "desc": "Rise from Hamlet to Village.", "reward": 1000},
	{"id": "tier_3", "title": "A Town", "desc": "Rise from Village to Town.", "reward": 2000},
	{"id": "tier_4", "title": "A City", "desc": "Rise from Town to City.", "reward": 4000},
]

var town: Town
var crew: Crew
var clock: GameClock
var farm: Farm
var realm: Node
var dispatch: Dispatcher

## id -> day it was reached.
var done: Dictionary = {}
var harvested_any := false
var ordered_any := false
var _last_tier := 1
var _poll := 0.0
## True while loading: milestones already earned are noted, not paid again.
var _silent := false


func setup(t: Town, c: Crew, gc: GameClock, f: Farm, r: Node, d: Dispatcher) -> void:
	town = t
	crew = c
	clock = gc
	farm = f
	realm = r
	dispatch = d
	_last_tier = town.tier
	if farm != null:
		farm.harvested.connect(func(_k: String, _n: int) -> void:
			harvested_any = true
			evaluate())
	if dispatch != null:
		dispatch.plan_accepted.connect(func(_w: Worker, _a: Array) -> void:
			ordered_any = true
			evaluate())
	town.tier_changed.connect(func(_t: int) -> void: evaluate())
	town.building_added.connect(func(_r: Dictionary) -> void: evaluate())
	if crew != null:
		crew.roster_changed.connect(evaluate)


## While a save is being put back (people are restored one signal at a time) and
## for an older save with no record: take stock without a fanfare or a payout.
## Ends at restore(), or end_silent() for a save that has no record.
func begin_silent() -> void:
	_silent = true


func end_silent() -> void:
	evaluate()
	_silent = false


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		evaluate()


# --------------------------------------------------------------- rank

func tier() -> int:
	return clampi(town.tier, 1, RANKS.size()) if town != null else 1


func rank_name(t: int = -1) -> String:
	return str(RANKS[(tier() if t < 0 else clampi(t, 1, RANKS.size())) - 1])


## What the next rank still wants, as building names; empty at the top.
func missing_for_next() -> Array[String]:
	if town == null or tier() >= RANKS.size():
		return []
	return town.needs_met_for(tier() + 1)


## 0..1 progress toward the next rank: the share of its required buildings the
## town already has. Full at the top.
func rank_progress() -> float:
	if town == null or tier() >= RANKS.size():
		return 1.0
	var need: Array = Town.TIER_NEEDS.get(tier() + 1, [])
	if need.is_empty():
		return 1.0
	return float(need.size() - missing_for_next().size()) / float(need.size())


func next_rank_line() -> String:
	if tier() >= RANKS.size():
		return "The greatest rank there is."
	var miss := missing_for_next()
	if miss.is_empty():
		return "Ready to become a %s." % rank_name(tier() + 1)
	return "To become a %s: %s." % [rank_name(tier() + 1), ", ".join(miss)]


# ---------------------------------------------------------- milestones

func is_done(id: String) -> bool:
	return done.has(id)


func count_done() -> int:
	return done.size()


func built_by_crew() -> int:
	var n := 0
	if town != null:
		for b: Dictionary in town.buildings:
			if str(b.get("builder", "")) != "":
				n += 1
	return n


func population() -> int:
	if realm != null and realm.get("population") != null:
		return int((realm.get("population") as Object).call("count"))
	return crew.workers.size() if crew != null else 0


func hired_count() -> int:
	return crew.hired().size() if crew != null else 0


func _goal_done() -> bool:
	if crew == null:
		return false
	for w: Worker in crew.workers:
		if w.goal != null and w.goal.done:
			return true
	return false


func _met(id: String) -> bool:
	match id:
		"first_order":
			return ordered_any
		"first_building":
			return built_by_crew() >= 1
		"build_5":
			return built_by_crew() >= 5
		"build_10":
			return built_by_crew() >= 10
		"first_hire":
			return hired_count() >= 4
		"hired_5":
			return hired_count() >= 5
		"first_harvest":
			return harvested_any
		"first_goal":
			return _goal_done()
		"week_one":
			return clock != null and clock.day >= 8
		"pop_20":
			return population() >= 20
		"pop_35":
			return population() >= 35
		"tier_2":
			return tier() >= 2
		"tier_3":
			return tier() >= 3
		"tier_4":
			return tier() >= 4
	return false


## Checks every milestone not yet reached and pays out the ones now met.
func evaluate() -> void:
	if town == null:
		return
	if tier() != _last_tier:
		_last_tier = tier()
		rank_changed.emit(_last_tier, rank_name())
	for m: Dictionary in MILESTONES:
		var id := str(m["id"])
		if done.has(id) or not _met(id):
			continue
		done[id] = clock.day if clock != null else 1
		if _silent:
			continue
		var reward := int(m["reward"])
		town.coins += reward
		milestone_reached.emit(id, str(m["title"]), reward)


## Marks a milestone as reached from outside (the tutorial's own reward is not
## one of these, but a test can force one).
func grant(id: String) -> bool:
	if done.has(id):
		return false
	for m: Dictionary in MILESTONES:
		if str(m["id"]) == id:
			done[id] = clock.day if clock != null else 1
			town.coins += int(m["reward"])
			milestone_reached.emit(id, str(m["title"]), int(m["reward"]))
			return true
	return false


## The first milestone not yet reached, for "next up".
func next_up() -> Dictionary:
	for m: Dictionary in MILESTONES:
		if not done.has(str(m["id"])):
			return m
	return {}


# ------------------------------------------------------------- saving

func snapshot() -> Dictionary:
	return {"done": done.duplicate(), "harvested": harvested_any, "ordered": ordered_any}


func restore(d: Dictionary) -> void:
	done = (d.get("done", {}) as Dictionary).duplicate()
	harvested_any = bool(d.get("harvested", false))
	ordered_any = bool(d.get("ordered", false))
	_last_tier = tier()
	_silent = false
