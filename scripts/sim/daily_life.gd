extends Node
class_name DailyLife
## Everybody's day: up at dawn, at work through the day, home (or at the
## tavern) in the evening, and in their own bed at night.
##
## Nobody is told to do any of this. Each person has a house — the one their
## household was founded with, or the one Population gave them a bed in — and
## most have somewhere they work. As the hours go round this decides which
## building their day has them in, walks them across town to its front door,
## takes them inside (IndoorNav), and lets them potter about in there: across
## the kitchen, over to the fire, behind the counter. At bedtime they go home,
## through the house to their own side of the bed, and lie down; at dawn they
## get up. A job always wins: somebody halfway through a wall at nine at night
## finishes the wall, then goes home.
##
## Out of sight it does not bother with the walk. Somebody the crowd system
## has stopped simulating (more than Crew.FAR from you) is simply put where the
## hour has them — in bed, or inside the building — which costs nothing and
## means the town is where it should be when you come back to it.
##
## Bounded cost: one pass over the townsfolk every TICK seconds, a handful of
## comparisons each. Beds are read off the houses' furniture once, and again
## only when a building is added or taken down; each building's indoor grid is
## built the first time somebody goes in.

const TICK := 0.5
## Bedtime and getting up, before each person's own lean either way (up to
## LATE hours later to bed, up to EARLY hours later to rise).
const BED_FROM := 21.0
const LATE := 1.5
const RISE_FROM := 5.5
const EARLY := 1.25
const WORK_FROM := 8.0
const WORK_TO := 18.0
## How likely somebody is to spend a given evening at the tavern.
const TAVERN_EVENINGS := 0.35
## Within this of the front step, they go in.
const DOOR_M := 2.5
## Where the sleeper's feet go, along the bed from its middle (+ toward the
## foot), and how far either side of the middle each half of a double bed is.
const FEET_ALONG := 0.55
const DOUBLE_SIDE := 0.38
const MATTRESS_Y := 0.72

var crew: Crew
var town: Town
var clock: GameClock
var population: Node = null          ## Population, if the realm has one

var _t := 0.0
var _bed_of: Dictionary = {}         ## worker id -> {feet, yaw, stand, rec}
var _beds_dirty := true
var _tavern: Dictionary = {}
var _bed_tries: Dictionary = {}      ## worker id -> attempts to walk to the bed
var _short_of_door: Dictionary = {}  ## worker id -> seconds idle near a door they want
var _prebuild: Array = []


func setup(c: Crew, t: Town, k: GameClock, pop: Node) -> void:
	crew = c
	town = t
	clock = k
	population = pop
	town.building_added.connect(func(_r: Dictionary) -> void: _beds_dirty = true)
	town.building_removed.connect(func(r: Dictionary) -> void:
		_beds_dirty = true
		_evict(r))


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK or crew == null or clock == null:
		return
	_t = 0.0
	if _beds_dirty:
		_read_beds()
	# Each building's indoor grid, one per tick ahead of anybody needing it,
	# so no single frame pays for more than one.
	if not _prebuild.is_empty():
		var rec: Dictionary = _prebuild.pop_back()
		IndoorNav.of(rec.get("patch", null))
	var h := clock.hour
	for w: Worker in crew.workers:
		if is_instance_valid(w):
			_live(w, h)


# ------------------------------------------------------------------ the day

func _live(w: Worker, h: float) -> void:
	var wid := w.memory.worker_id
	var bed_h := BED_FROM + _lean(wid, "bed") * LATE
	var rise_h := RISE_FROM + _lean(wid, "rise") * EARLY
	var night := h >= bed_h or h < rise_h

	if w.sleeping:
		if not night:
			wake(w)
		return
	if not w.free_for_life():
		return
	if night:
		var bed: Dictionary = _bed_of.get(wid, {})
		if not bed.is_empty():
			_to_bed(w, bed)
			return
		_bed_tries.erase(wid)
		_go_to(w, _home_rec(w) if not _home_rec(w).is_empty() else _tavern)
		return
	_bed_tries.erase(wid)
	# Somebody you posted somewhere keeps the post through the day, and
	# somebody you sent somewhere stays there a while.
	if w.hired and w.employer == null:
		return
	if clock.day * 24.0 + h < w.stay_put_until:
		return
	_go_to(w, _place_for(w, h))


## Which building the hour has somebody in. Empty: out and about.
func _place_for(w: Worker, h: float) -> Dictionary:
	if h >= WORK_FROM and h < WORK_TO:
		var work := _work_rec(w)
		if not work.is_empty():
			return work
		# No trade building: a hired hand waits at home, a citizen wanders.
		return _home_rec(w) if w.hired else {}
	if h >= WORK_TO and not _tavern.is_empty() \
			and _lean(w.memory.worker_id, "tavern%d" % clock.day) < TAVERN_EVENINGS:
		return _tavern
	var home := _home_rec(w)
	# Somebody with no house is about the town until it is dark.
	return home


## Walks somebody to a building and in, or out of the one they are in.
func _go_to(w: Worker, rec: Dictionary) -> void:
	if rec.is_empty():
		if w.indoors != null and _unseen(w):
			w.leave_building()
		elif w.indoors != null and not w.indoor_walking():
			w.indoor_walk_to(w.indoors.exit_point(), "exit")
		w.routine_anchor = Vector3.INF
		return
	var nav := IndoorNav.of(rec.get("patch", null))
	if nav == null or not nav.usable():
		w.routine_anchor = Crew.inside_door(rec)
		return
	if w.indoors == nav:
		w.routine_anchor = Vector3.INF
		return
	# Out of sight nobody walks: they are simply there.
	if _unseen(w):
		w.leave_building()
		w.appear_inside(nav, nav.random_spot())
		return
	if w.indoors != null:
		# In the wrong building: out through its door first.
		if not w.indoor_walking() and not w.indoor_walk_to(w.indoors.exit_point(), "exit"):
			w.leave_building()
		return
	var door := nav.exit_point()
	var wid := w.memory.worker_id
	var d := Vector2(w.global_position.x - door.x, w.global_position.z - door.z).length()
	# Standing about short of the door for long (the street grid stops a
	# metre off every wall, and some steps are hemmed in by a bench and a
	# barrel): they go in rather than loiter outside their own house.
	var stuck := float(_short_of_door.get(wid, 0.0))
	if w.state == Worker.State.IDLE and d < 12.0:
		stuck += TICK
	_short_of_door[wid] = stuck
	if d < DOOR_M or stuck > 12.0:
		_short_of_door.erase(wid)
		w.enter_building(nav)
		w.indoor_walk_to(nav.random_spot())
		return
	w.routine_anchor = door
	if w.state == Worker.State.IDLE:
		w.go_near(door)


func _unseen(w: Worker) -> bool:
	return not w.is_physics_processing() or not w.visible


func _home_rec(w: Worker) -> Dictionary:
	if w.home_building_id >= 0:
		var r := _rec(w.home_building_id)
		if not r.is_empty():
			return r
	if population == null:
		return {}
	var c: Variant = population.call("for_worker", w)
	if c == null or int(c.home_id) < 0:
		return {}
	return _rec(int(c.home_id))


func _work_rec(w: Worker) -> Dictionary:
	var arch := str(VillagePlan.WORKPLACE.get(w.memory.worker_id, ""))
	if arch == "":
		return {}
	for rec: Dictionary in town.buildings:
		if str(rec["archetype"]) == arch:
			return rec
	return {}


func _rec(bid: int) -> Dictionary:
	for rec: Dictionary in town.buildings:
		if int(rec["id"]) == bid:
			return rec
	return {}


# ------------------------------------------------------------------- bed

func _to_bed(w: Worker, bed: Dictionary) -> void:
	var wid := w.memory.worker_id
	var rec: Dictionary = bed["rec"]
	var nav := IndoorNav.of(rec.get("patch", null))
	if _unseen(w) or nav == null or not nav.usable():
		_lie(w, bed)
		return
	if w.indoors != nav:
		_go_to(w, rec)
		return
	if w.indoor_walking():
		return
	var stand: Vector3 = bed["stand"]
	var d := Vector2(w.global_position.x - stand.x, w.global_position.z - stand.z).length()
	var tries := int(_bed_tries.get(wid, 0))
	if d < 1.3 or tries >= 3:
		_lie(w, bed)
		return
	_bed_tries[wid] = tries + 1
	if not w.indoor_walk_to(stand):
		_lie(w, bed)


func _lie(w: Worker, bed: Dictionary) -> void:
	_bed_tries.erase(w.memory.worker_id)
	w.routine_anchor = Vector3.INF
	var nav := IndoorNav.of((bed["rec"] as Dictionary).get("patch", null))
	if nav != null and nav.usable():
		w.indoors = nav
	w.lie_down(bed["feet"], float(bed["yaw"]))


## Out of bed and on their feet beside it. Also how anyone else wakes
## somebody — an order, walking into their house — so they stand somewhere
## sensible rather than where their feet were on the mattress.
func wake(w: Worker) -> void:
	var bed: Dictionary = _bed_of.get(w.memory.worker_id, {})
	w.wake(bed.get("stand", Vector3.INF))
	w.routine_anchor = Vector3.INF


## Anybody asleep in, or inside, a building that has gone is put outside.
func _evict(rec: Dictionary) -> void:
	var nav := IndoorNav.of(rec.get("patch", null))
	for w: Worker in crew.workers:
		if is_instance_valid(w) and w.indoors == nav:
			if w.sleeping:
				w.wake()
			w.leave_building()


## Every bed in town, and whose it is. Household members take their own
## house's bed, a side each; everybody else with a Population home takes the
## next free bed in it.
func _read_beds() -> void:
	_beds_dirty = false
	_prebuild = town.buildings.duplicate()
	var beds := {}
	_bed_of.clear()
	_tavern = {}
	for rec: Dictionary in town.buildings:
		var patch: VoxelPatch = rec.get("patch", null)
		if patch == null:
			continue
		if str(rec["archetype"]) == "tavern" and _tavern.is_empty():
			_tavern = rec
		var slots: Array = []
		for p: Dictionary in patch.props:
			var t := str(p.get("type", ""))
			if t != "bed" and t != "bed_double":
				continue
			var sides: Array[float] = [0.0]
			if t == "bed_double":
				sides = [-DOUBLE_SIDE, DOUBLE_SIDE]
			for sd: float in sides:
				var slot := _slot(p["pos"], float(p.get("yaw", 0.0)), sd, t == "bed_double")
				slot["rec"] = rec
				slots.append(slot)
		beds[int(rec["id"])] = slots
	var taken := {}
	# Households first, so a couple is never split by somebody else's claim.
	for rec2: Dictionary in town.buildings:
		var owner := str(rec2.get("household", ""))
		if owner == "":
			continue
		var bid := int(rec2["id"])
		var k := 0
		for wid: String in [owner, Crew.partner_of(owner)]:
			var slots2: Array = beds.get(bid, [])
			if k < slots2.size():
				_bed_of[wid] = slots2[k]
				k += 1
		taken[bid] = k
	if population == null:
		return
	for w: Worker in crew.workers:
		var wid2 := w.memory.worker_id
		if _bed_of.has(wid2):
			continue
		var c: Variant = population.call("for_worker", w)
		if c == null or int(c.home_id) < 0:
			continue
		var bid2 := int(c.home_id)
		var slots3: Array = beds.get(bid2, [])
		var k2 := int(taken.get(bid2, 0))
		if k2 < slots3.size():
			_bed_of[wid2] = slots3[k2]
			taken[bid2] = k2 + 1


## One sleeping place on a bed: where the feet go, which way the body lies,
## and where to stand to get in and out.
func _slot(bed_pos: Vector3, yaw: float, side: float, double: bool) -> Dictionary:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))        # toward the foot
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))    # the bed's own +X
	var feet := bed_pos + fwd * FEET_ALONG + across * side
	feet.y = bed_pos.y + MATTRESS_Y
	var out := 1.05 if double else 0.9
	var stand := bed_pos + fwd * 0.2 + across * (out * (signf(side) if side != 0.0 else 1.0))
	stand.y = bed_pos.y
	return {"feet": feet, "yaw": yaw, "stand": stand}


## A steady 0..1 per person and purpose, so somebody is always the one who
## stays up late, and the same evening comes out the same for them.
static func _lean(wid: String, what: String) -> float:
	return float(hash(wid + ":" + what) & 0xffff) / 65535.0
