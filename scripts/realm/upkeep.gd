extends Node
## Buildings wear, leak, fall in, and get mended.
##
## Every building on the register has a condition from one down to nothing.
## Weather and years take it down slowly, fire takes it down at once, and
## below a quarter the roof starts visibly going — a voxel or two a day to
## air, from the top of the patch, so a ruin looks like one. Repair is a
## worker at the door for a few hours putting the original voxels back out
## of the stores. There is a small daily cost in coin for every building
## simply standing, which is what makes a sprawl of empty huts a decision.

const FOUNDING_CONDITION := 0.85
const WEAR_PER_DAY := 0.006
const LEAK_AT := 0.5
const DECAY_AT := 0.25
const DECAY_VOXELS_PER_DAY := 4
const REPAIR_PER_HOUR := 0.1
const REPAIR_VOXELS_PER_HOUR := 30
const NEEDS_REPAIR_AT := 0.8
const FLAMMABLE_ROOF := [VoxelTypes.THATCH]

var realm: Realm
var condition: Dictionary = {}      ## building id -> 0..1
## building id -> {patch index: true} for voxels that never matched the
## patch in the first place (a founding building's buried courses, a wall
## the terrain swallowed). Repair leaves those alone: they are not damage.
var _baseline: Dictionary = {}
var _jobs: Array[Dictionary] = []   ## {worker_id, ids: Array[int], i}
var _rng := RandomNumberGenerator.new()
var _upkeep_yesterday := 0


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	for rec: Dictionary in realm.town.buildings:
		condition[int(rec["id"])] = FOUNDING_CONDITION
		_take_baseline(rec)
	realm.town.building_added.connect(func(rec: Dictionary) -> void: condition[int(rec["id"])] = 1.0)
	realm.town.building_removed.connect(func(rec: Dictionary) -> void:
		condition.erase(int(rec["id"]))
		_baseline.erase(int(rec["id"])))


## What the world does not hold of this patch right now, remembered so that
## repair only ever puts back what was there and later lost.
func _take_baseline(rec: Dictionary) -> void:
	var patch: VoxelPatch = rec.get("patch")
	var bid := int(rec["id"])
	if patch == null or _baseline.has(bid):
		return
	var missing := {}
	for i in patch.data.size():
		var want := patch.data[i]
		if want == VoxelPatch.UNTOUCHED or want == VoxelTypes.AIR:
			continue
		if realm.world.get_voxel(patch.world_of(i)) != want:
			missing[i] = true
	_baseline[bid] = missing


## Voxels the building has lost since it was finished.
func missing_count(rec: Dictionary) -> int:
	var patch: VoxelPatch = rec.get("patch")
	if patch == null:
		return 0
	var base: Dictionary = _baseline.get(int(rec["id"]), {})
	var n := 0
	for i in patch.data.size():
		var want := patch.data[i]
		if want == VoxelPatch.UNTOUCHED or want == VoxelTypes.AIR or base.has(i):
			continue
		if realm.world.get_voxel(patch.world_of(i)) != want:
			n += 1
	return n


# ------------------------------------------------------------------- public

func condition_of(bid: int) -> float:
	return float(condition.get(bid, 1.0))


func is_ruined(bid: int) -> bool:
	return condition_of(bid) <= 0.0


func set_condition(bid: int, value: float) -> void:
	condition[bid] = clampf(value, 0.0, 1.0)


## The building most in need, for the court's petitions; {} when all is well.
func worst() -> Dictionary:
	var out: Dictionary = {}
	var low := LEAK_AT
	for rec: Dictionary in realm.town.buildings:
		var c := condition_of(int(rec["id"]))
		if c < low:
			low = c
			out = rec
	return out


func needing_repair() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in realm.town.buildings:
		if condition_of(int(rec["id"])) < NEEDS_REPAIR_AT:
			out.append(rec)
	return out


func word_for(c: float) -> String:
	if c <= 0.0:
		return "a ruin"
	if c < DECAY_AT:
		return "falling in"
	if c < LEAK_AT:
		return "leaking"
	if c < NEEDS_REPAIR_AT:
		return "worn"
	return "sound"


# ------------------------------------------------------------------- the day

func on_day(_day: int) -> void:
	var weather: Node = realm.system("Weather")
	var wet := weather != null and weather.has_method("is_raining") and bool(weather.call("is_raining"))
	var burning: Array = []
	if weather != null and weather.has_method("burning"):
		burning = weather.call("burning")
	_upkeep_yesterday = 0
	for rec: Dictionary in realm.town.buildings:
		var bid := int(rec["id"])
		var patch: VoxelPatch = rec["patch"]
		# A building finished yesterday is what it will be; note it now.
		if not _baseline.has(bid) and int(rec.get("day", 0)) < _day:
			_take_baseline(rec)
		var wear := WEAR_PER_DAY
		if wet:
			wear *= 2.0
		if patch != null and _roof_is(patch, FLAMMABLE_ROOF):
			wear *= 1.5
		if burning.has(rec):
			condition[bid] = minf(condition_of(bid), 0.4) - 0.05
		condition[bid] = clampf(condition_of(bid) - wear, 0.0, 1.0)
		# Upkeep in coin, by size.
		var cost := 1
		if patch != null:
			cost = clampi(patch.footprint.size.x * patch.footprint.size.y / 900, 1, 3)
		realm.town.coins -= cost
		_upkeep_yesterday += cost
		# A leaking roof is felt by whoever sleeps under it.
		if condition_of(bid) < LEAK_AT:
			for c: Population.Citizen in realm.population.alive():
				if c.home_id == bid:
					c.needs["warm"] = maxf(float(c.needs["warm"]) - 0.1, 0.0)
		if condition_of(bid) < DECAY_AT and patch != null:
			var gone := _decay(patch)
			if gone > 0:
				realm.note("upkeep", "The %s lost %d more of its roof." % [str(rec["archetype"]).replace("_", " "), gone])
		if condition_of(bid) <= 0.0 and not bool(rec.get("ruin_noted", false)):
			rec["ruin_noted"] = true
			realm.say("The %s is a ruin." % str(rec["archetype"]).replace("_", " "))
			realm.note("upkeep", "The %s fell into ruin." % str(rec["archetype"]).replace("_", " "))


## A patch restored from a save can carry a size its data does not fill, so
## every read here is bounded by the bytes actually there, not by the box.
static func _peek(patch: VoxelPatch, x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= patch.size.x or y >= patch.size.y or z >= patch.size.z:
		return VoxelPatch.UNTOUCHED
	var i := x + z * patch.size.x + y * patch.size.x * patch.size.z
	if i >= patch.data.size():
		return VoxelPatch.UNTOUCHED
	return patch.data[i]


func _roof_is(patch: VoxelPatch, mats: Array) -> bool:
	var y := patch.size.y - 1
	var hits := 0
	var tries := 0
	while y >= 0 and tries < 3:
		for x in range(0, patch.size.x, 3):
			for z in range(0, patch.size.z, 3):
				var m := _peek(patch, x, y, z)
				if m != VoxelPatch.UNTOUCHED and m != VoxelTypes.AIR:
					hits += 1
					if m in mats:
						return true
		if hits > 0:
			return false
		y -= 1
		tries += 1
	return false


## Takes a few voxels off the top of the building; from the highest solid
## layer, at random, so it goes the way roofs go.
func _decay(patch: VoxelPatch) -> int:
	var gone := 0
	var tries := 0
	while gone < DECAY_VOXELS_PER_DAY and tries < 40:
		tries += 1
		var x := _rng.randi_range(0, patch.size.x - 1)
		var z := _rng.randi_range(0, patch.size.z - 1)
		for y in range(patch.size.y - 1, -1, -1):
			var wp := patch.local_to_world(x, y, z)
			var here := realm.world.get_voxel(wp)
			if here != VoxelTypes.AIR:
				if _peek(patch, x, y, z) != VoxelPatch.UNTOUCHED:
					realm.world.set_voxel(wp, VoxelTypes.AIR)
					gone += 1
				break
	return gone


# ------------------------------------------------------------------- repair

func on_hour(_hour: float, _day: int) -> void:
	for job: Dictionary in _jobs.duplicate():
		var w: Worker = realm.crew.get_worker(str(job["worker_id"]))
		if w == null or not is_instance_valid(w):
			_jobs.erase(job)
			continue
		var ids: Array = job["ids"]
		var i := int(job["i"])
		if i >= ids.size():
			_jobs.erase(job)
			if not w.job_errand.is_empty():
				w.drop_everything()
			w.speak("All mended.")
			continue
		var rec := realm.population._building_by_id(int(ids[i]))
		if rec.is_empty():
			job["i"] = i + 1
			continue
		if w.job_errand.is_empty() or w.global_position.distance_to(realm.door_of(rec)) > 6.0:
			# Not there yet, or between buildings: send them on.
			if w.job_errand.is_empty():
				w.take_errand_job("station", realm.door_of(rec), 12.0, "", {"where": "the " + str(rec["archetype"]).replace("_", " "), "doing": "hammer"})
			continue
		var short := _restore_voxels(rec)
		if short != "":
			w.speak("Out of %s; the %s will have to wait." % [short, str(rec["archetype"]).replace("_", " ")])
			realm.note("upkeep", "Repairs to the %s stopped for want of %s." % [str(rec["archetype"]).replace("_", " "), short])
			_jobs.erase(job)
			w.drop_everything()
			continue
		var bid := int(rec["id"])
		condition[bid] = minf(condition_of(bid) + REPAIR_PER_HOUR, 1.0)
		rec.erase("ruin_noted")
		if condition_of(bid) >= 1.0:
			w.speak("The %s is sound again." % str(rec["archetype"]).replace("_", " "))
			realm.note("upkeep", "The %s was repaired." % str(rec["archetype"]).replace("_", " "))
			job["i"] = i + 1
			w.drop_everything()


## Puts back up to thirty of the building's own voxels that are missing,
## charging the stores for each. Returns the material it ran out of, or "".
func _restore_voxels(rec: Dictionary) -> String:
	var patch: VoxelPatch = rec["patch"]
	if patch == null:
		return ""
	var put := 0
	var base: Dictionary = _baseline.get(int(rec["id"]), {})
	for i in patch.data.size():
		if put >= REPAIR_VOXELS_PER_HOUR:
			return ""
		var want := patch.data[i]
		if want == VoxelPatch.UNTOUCHED or want == VoxelTypes.AIR or want == VoxelTypes.EMBER or base.has(i):
			continue
		var wp := patch.world_of(i)
		if realm.world.get_voxel(wp) == want:
			continue
		var mat := VoxelTypes.name_of(want)
		if int(realm.town.stock.get(mat, 0)) <= 0:
			return mat
		realm.town.stock[mat] = int(realm.town.stock[mat]) - 1
		realm.world.set_voxel(wp, want)
		put += 1
	return ""


func repair(worker: Worker, recs: Array[Dictionary]) -> bool:
	if recs.is_empty():
		return false
	var ids: Array = []
	for rec: Dictionary in recs:
		ids.append(int(rec["id"]))
	for job: Dictionary in _jobs:
		if job["worker_id"] == worker.memory.worker_id:
			job["ids"] = ids
			job["i"] = 0
			return true
	_jobs.append({"worker_id": worker.memory.worker_id, "ids": ids, "i": 0})
	var first := recs[0]
	worker.take_errand_job("station", realm.door_of(first), 12.0,
		"Off to mend the %s." % str(first["archetype"]).replace("_", " ") if recs.size() == 1
		else "Going round the town with a hammer; %d to mend." % recs.size(),
		{"where": "the " + str(first["archetype"]).replace("_", " "), "doing": "hammer"})
	return true


# ------------------------------------------------------------------ talking

func verbs() -> Dictionary:
	return {
		"repair": {
			"says": "mend a building by name, or everything that needs it (place: all)",
			"required": ["place"],
			"anyone": false,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	if str(step.get("do", "")) != "repair":
		return "failed"
	var place := str(step.get("place", "")).strip_edges().to_lower()
	if place in ["all", "everything", "the town", "town", "the buildings"]:
		var todo := needing_repair()
		if todo.is_empty():
			worker.speak("Nothing needs mending.")
			return "done"
		# Spread the work over whoever is free.
		var hands: Array[Worker] = [worker]
		for w: Worker in realm.crew.hired():
			if w != worker and not w.busy():
				hands.append(w)
		var per := int(ceil(float(todo.size()) / float(hands.size())))
		for i in hands.size():
			var slice: Array[Dictionary] = []
			for rec: Dictionary in todo.slice(i * per, (i + 1) * per):
				slice.append(rec)
			if not slice.is_empty():
				repair(hands[i], slice)
		worker.speak("%d buildings to mend between %d of us." % [todo.size(), hands.size()])
		return "started"
	var rec := realm.building_named(place)
	if rec.is_empty():
		return "Mend what? Name a building."
	if condition_of(int(rec["id"])) >= 1.0:
		worker.speak("The %s is sound; nothing to do." % str(rec["archetype"]).replace("_", " "))
		return "done"
	if worker.busy():
		return "When I am done here."
	repair(worker, [rec])
	return "started"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["need repair", "needs repair", "need mending", "falling down", "falling apart",
			"in bad repair", "what needs fixing", "anything to mend", "which buildings"]):
		var todo := needing_repair()
		if todo.is_empty():
			return "Every building is sound."
		var bits: Array[String] = []
		for rec: Dictionary in todo:
			bits.append("the %s (%s)" % [str(rec["archetype"]).replace("_", " "), word_for(condition_of(int(rec["id"])))])
		return "Needing work: %s." % ", ".join(bits)
	if Realm.has_phrase(t, ["upkeep cost", "cost of upkeep", "how much does upkeep", "maintenance"]):
		return "Upkeep took %d coins yesterday, for %d buildings." % [_upkeep_yesterday, realm.town.buildings.size()]
	if Realm.has_phrase(t, ["what state", "condition of", "how sound", "what shape", "state of the"]):
		var rec2 := _building_in(t)
		if not rec2.is_empty():
			var c := condition_of(int(rec2["id"]))
			return "The %s is %s — about %d percent." % [str(rec2["archetype"]).replace("_", " "), word_for(c), int(c * 100.0)]
	return ""


func hud_lines() -> Array[String]:
	var n := 0
	for rec: Dictionary in realm.town.buildings:
		if condition_of(int(rec["id"])) < LEAK_AT:
			n += 1
	return ["%d building%s need repair" % [n, "" if n == 1 else "s"]] if n > 0 else []


func _building_in(t: String) -> Dictionary:
	var best := ""
	var best_len := 0
	for word: String in ArchetypeLibrary.KEYWORDS:
		if word.length() > best_len and Realm.has_word(t, [word]):
			best = str(ArchetypeLibrary.KEYWORDS[word])
			best_len = word.length()
	if best == "":
		return {}
	# The worst one of that kind, which is the one they mean.
	var out: Dictionary = {}
	var low := 2.0
	for rec: Dictionary in realm.buildings_of(best):
		if condition_of(int(rec["id"])) < low:
			low = condition_of(int(rec["id"]))
			out = rec
	return out


func snapshot() -> Dictionary:
	return {"condition": condition}


func restore(d: Dictionary) -> void:
	for k: Variant in d.get("condition", {}):
		condition[int(k)] = float(d["condition"][k])
