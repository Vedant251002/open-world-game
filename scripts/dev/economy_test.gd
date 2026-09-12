extends Node
class_name EconomyTest
## Does the town check the stores before it starts building?
##
## The rule under test is the one the whole material economy exists to enforce:
## nobody lays a voxel of something the town has not got. A plan that cannot be
## paid for is held whole — not refused, not quietly downgraded to something
## cheaper — the worker says what is missing, somebody else walks out of town
## and digs it, and the moment the stores can cover the bill the held plan
## starts on its own.
##
## Five things have to be true for that to be real rather than cosmetic:
##
##   1. an unaffordable plan does not become a job
##   2. the worker says the shortfall in materials the player recognises
##   3. a *different* worker is sent, to a site outside the town they can walk to
##   4. the digging leaves an actual hole and actual stock
##   5. the held plan then starts, and the stores are charged for it
##
## Runs against the offline plan library, so it is deterministic and free.

var world: VoxelWorld
var gen: WorldGen
var village: Village
var crew: Crew
var dispatch: Dispatcher
var nav: NavGrid
var clock: GameClock
var town: Town

var _armed := false
var _wait := 0.0
var _fails: Array[String] = []
var _said: Array[String] = []


func begin() -> void:
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		_said.append(line)
		print("[econ]   %s (%s): %s" % [w.display_name(), kind, line]))
	set_process(true)


func _process(delta: float) -> void:
	if _armed:
		return
	_wait += delta
	if world.busy() and _wait < 20.0:
		return
	_armed = true
	set_process(false)
	print("[econ] world ready after %.1fs" % _wait)
	_run()
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _ok(cond: bool, what: String) -> void:
	print("[econ]   %s %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _run() -> void:
	_case_short()
	_case_afford()
	_case_direct()

	print("[econ] ---")
	for f: String in _fails:
		print("[econ] FAIL: %s" % f)
	print("[econ] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))


## The whole flow, in one go.
func _case_short() -> void:
	print("[econ] --- an order the stores cannot cover ---")
	var mira: Worker = crew.workers[0]
	var plot := dispatch._choose_plot(mira)
	var plan := ArchetypeLibrary.fallback("build a cottage", mira.memory, plot,
		town.tier)
	var spec: Dictionary = plan["spec"]
	var arch := str(spec.get("archetype", "?"))

	# What it would actually cost, so the test asserts against the real bill
	# rather than a number somebody typed in.
	var probe := BuildingGenerator.build(spec, 1, plot, _ctx())
	if not probe["ok"]:
		_fails.append("could not even plan a cottage: %s" % str(probe["error"]))
		return
	var bill := Resources.bill((probe["patch"] as VoxelPatch).cost)
	print("[econ]   a %s costs %s" % [arch, Resources.describe(bill)])
	_ok(bill.has("timber"), "the cottage bill includes timber")

	# Empty the timber yard. Everything else stays, so the shortfall is exactly
	# one material and the message is checkable.
	var held_stock := int(town.stock.get("timber", 0))
	town.stock["timber"] = 0
	_said.clear()
	# The founding buildings are on the register now, so "nothing registered"
	# means nothing MORE than was there when the order was given.
	var buildings_before := town.buildings.size()

	plot.reserved = true
	dispatch._open[mira.memory.worker_id] = {
		"worker": mira, "instruction": "build a cottage", "plot": plot,
	}
	dispatch._on_plan_ready(mira.memory.worker_id, plan)

	# 1 — the plan did not become a job.
	_ok(mira.job_patch == null, "Mira did not start building")
	_ok(dispatch._held.size() == 1, "the plan is held, not thrown away")
	_ok(town.buildings.size() == buildings_before, "nothing was registered in the town")

	# 2 — and she said why, in words a player would use.
	_ok(mira.waiting_for.find("timber") >= 0,
		"Mira is waiting on timber (%s)" % mira.waiting_for)
	var told := false
	for line: String in _said:
		if line.to_lower().find("timber") >= 0 and line.find("short") >= 0:
			told = true
	_ok(told, "she said out loud what she is short of")

	# The held plan is the same plan. No silent substitution — this is the
	# failure mode the whole design is trying to make impossible.
	var kept: Dictionary = dispatch._held[0]
	_ok(str((kept["spec"] as Dictionary).get("archetype", "")) == arch,
		"the held plan is still a %s" % arch)
	bill = Resources.bill((kept["patch"] as VoxelPatch).cost)

	# 3 — somebody else went.
	var digger: Worker = null
	for w: Worker in crew.workers:
		if w.job_quarry != null:
			digger = w
	if digger == null:
		_site_report("timber")
		_site_report("cobble")
		_fails.append("nobody was sent out for timber")
		town.stock["timber"] = held_stock
		return
	_ok(digger != mira, "%s went, not the one holding the plan"
		% digger.display_name())
	_ok(digger.job_quarry.material == "timber", "they went for timber")

	# Where they went. Open country is preferred and a vacant lot is allowed —
	# the world is generated from a fresh seed each run, so which one they get
	# depends on whether the seed put a wood within reach. What is never
	# allowed is the plaza, a street, or somebody's plot.
	var site: Vector3i = digger.job_quarry.site
	var at := Vector2i(site.x, site.z)
	print("[econ]   the site is %s the town" % [
		"outside" if not village.bounds_v.has_point(at) else "on open ground in"])
	_ok(not village.bounds_v.has_point(at) or village.is_diggable(site.x, site.z),
		"the site is not a street, a plaza or somebody's plot")
	_ok(nav.bounds_v().has_point(at),
		"the site is somewhere they can walk to")
	_ok(digger.job_quarry.total() > 0, "there is something there to dig")

	# 4 — the digging is real: voxels out of the world, units into the stores.
	var first: Vector3i = digger.job_quarry._order[0]
	var was := world.get_voxel(first)
	digger.job_quarry.complete_now()
	_ok(was != VoxelTypes.AIR and world.get_voxel(first) == VoxelTypes.AIR,
		"the dig left a hole where the material was")
	var got := int(town.stock.get("timber", 0))
	_ok(got > 0, "the timber reached the stores (%d units)" % got)
	_ok(got >= int(bill["timber"]), "enough of it to cover the bill (%d needed)"
		% int(bill["timber"]))

	# 5 — and the held plan starts by itself.
	var before := int(town.stock["timber"])
	crew.job_failed.connect(func(w: Worker, e: Dictionary) -> void:
		_fails.append("%s could not start: %s"
			% [w.display_name(), str(e.get("code", "?"))]))
	dispatch._process(0.0)
	_ok(mira.job_patch != null, "Mira started the cottage on her own")
	_ok(dispatch._held.is_empty(), "the held plan was let go")
	_ok(mira.waiting_for == "", "she is not waiting on anything any more")
	_ok(int(town.stock["timber"]) == before - int(bill["timber"]),
		"the stores were charged %d timber" % int(bill["timber"]))

	_reset(mira)
	_reset(digger)
	town.stock["timber"] = held_stock


## The other half of the rule: a bill the town *can* pay must not be delayed.
func _case_afford() -> void:
	print("[econ] --- an order the stores can cover ---")
	var tobias: Worker = crew.workers[1]
	var plot := dispatch._choose_plot(tobias)
	var plan := ArchetypeLibrary.fallback("build a cottage", tobias.memory, plot,
		town.tier)
	for mat: String in Resources.SOURCE:
		town.stock[mat] = 9000

	plot.reserved = true
	dispatch._open[tobias.memory.worker_id] = {
		"worker": tobias, "instruction": "build a cottage", "plot": plot,
	}
	dispatch._on_plan_ready(tobias.memory.worker_id, plan)
	_ok(tobias.job_patch != null, "Tobias started straight away")
	_ok(dispatch._held.is_empty(), "nothing was held")
	_ok(int(town.stock["timber"]) < 9000, "the stores were charged for it")
	_reset(tobias)


## "Go and dig up some iron" is an errand, not a building.
func _case_direct() -> void:
	print("[econ] --- told to go and fetch ---")
	var ren: Worker = crew.workers[2]
	dispatch.instruct(ren, "go and dig up some stone")
	_ok(ren.job_quarry != null, "Ren took the errand")
	if ren.job_quarry != null:
		_ok(ren.job_quarry.material == "cobble",
			"'stone' meant cobble (%s)" % ren.job_quarry.material)
	_ok(ren.job_patch == null, "and it did not turn into a building")
	_reset(ren)

	# The near miss: the same words with no errand in them must still build.
	_ok(not dispatch._try_gather(ren, "build a stone cottage"),
		"'build a stone cottage' is not a fetching job")
	_ok(not dispatch._try_gather(ren, "get on with it"),
		"'get on with it' names no material, so it is not one either")
	_reset(ren)


func _reset(w: Worker) -> void:
	if w.job_plot != null:
		w.job_plot.reserved = false
		w.job_plot.occupied_by = -1
	w._clear_job()
	w.waiting_for = ""


## Why the search came back empty. Prints the three things that can be wrong:
## the town is bigger than the search, the walkable world is smaller than the
## search, or the world simply is not loaded that far out.
func _site_report(mat: String) -> void:
	var centre := VoxelWorld.to_voxel(crew.workers[0].global_position)
	var src := Resources.source_of(mat)
	print("[econ]   no %s. centre %s, village %s, nav %s" % [
		mat, str(Vector2i(centre.x, centre.z)), str(village.bounds_v),
		str(nav.bounds_v())])
	for r in range(6, 46, 8):
		var loaded := 0
		var outside := 0
		var reachable := 0
		var hits := 0
		for a in 16:
			var ang := float(a) / 16.0 * TAU
			var vx := centre.x + int(cos(ang) * float(r * 4))
			var vz := centre.z + int(sin(ang) * float(r * 4))
			if not village.bounds_v.has_point(Vector2i(vx, vz)):
				outside += 1
			if nav.bounds_v().has_point(Vector2i(vx, vz)):
				reachable += 1
			var h := world.height_at(vx, vz)
			if h >= 0:
				loaded += 1
				for dy in range(0, 40):
					if world.get_voxel(Vector3i(vx, h - dy, vz)) == src:
						hits += 1
						break
		print("[econ]     r=%d (%d v): loaded %d/16, outside town %d, walkable %d, %s %d"
			% [r, r * 4, loaded, outside, reachable, mat, hits])


func _ctx() -> Dictionary:
	return {
		"world": world, "village": village, "worldgen": gen, "tier": town.tier,
		"occupied_rects": town.occupied_rects, "built_fronts": town.built_fronts,
	}
