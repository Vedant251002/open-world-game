extends RefCounted
class_name BuildingGenerator
## build(spec, seed, plot, world_context) -> VoxelPatch | GeneratorError
##
## The nine-stage pipeline from voxel-module-spec.md §5. A pure function: the
## same spec, seed and plot produce byte-identical voxels forever. Every random
## draw comes from DetRng(seed, plot_id, step_index) — never a global RNG —
## which is what makes a bug reproducible from a screenshot.
##
## The generator never returns broken geometry. When it cannot honour a spec it
## returns a typed error, which the worker turns into a spoken question. That is
## a gameplay beat, not an error dialog.

const V := VoxelChunk.VOXEL_M

## Vertical budget, in voxels.
## A storey, and the clear height inside one. Both raised by two voxels: at
## three and a quarter metres to the ceiling, a room with a bed and a hearth in
## it read as a crawlspace from the doorway.
const STORY_H := 15          ## 1 slab + 14 clear = 3.75 m
const CLEAR_H := 14
const FOUNDATION_D := 4      ## how far the footing digs in
const PATCH_MARGIN := 4      ## room for eaves, steps and site levelling

## Openings, in voxels. Spec §1 human scale: door 4 x 11, wall 12 high.
## Openings, scaled to the bigger walls they are cut into. A metre-wide door
## on a sixteen metre frontage reads as a hatch, and it is also the width the
## crew has to get through.
const DOOR_W := 6
const DOOR_H := 11
const WIN_W := 7
const WIN_H := 7
const WIN_SILL := 5
const WIN_PIER := 5          ## minimum solid wall between windows

## 2.5 m. At the old 1.5 m the partitioner would chop a small hut into two
## slivers you could not turn round in, each with its own wall down the middle
## of the only window.
## Smallest room the subdivision will cut, in voxels. Three and a half metres
## a side: below that the furniture fills it and there is nowhere to stand.
const MIN_CELL := 14
const ROOF_SLOPE := 0.55
const SHED_SLOPE := 0.28

# Stage indices, used as the DetRng step so stages cannot influence each other.
enum { STEP_SITE = 1, STEP_ENVELOPE, STEP_PARTITION, STEP_CIRCULATION, STEP_ROOF,
	STEP_OPENINGS, STEP_DETAIL, STEP_PROPS, STEP_BAKE }


## ctx: {"world": VoxelWorld, "village": Village, "worldgen": WorldGen, "tier": int}
static func build(spec: Dictionary, world_seed: int, plot: Plot, ctx: Dictionary) -> Dictionary:
	var err := Validator.check_spec(spec, plot, ctx)
	if not err.is_empty():
		return {"ok": false, "error": err}

	var g := BuildingGenerator.new()
	return g._run(spec, world_seed, plot, ctx)


# ---------------------------------------------------------------- state

var spec: Dictionary
var plot: Plot
var ctx: Dictionary
var world: VoxelWorld
var seed_value: int

var patch: VoxelPatch
var front: Vector3i           ## world unit vector, out of the front wall
var right: Vector3i
var W: int                    ## footprint along world X, voxels
var D: int                    ## footprint along world Z, voxels
var stories: int
var wall_t: int
var ground: int               ## levelled ground voxel y (top solid)
var ox: int                   ## building x offset inside the patch
var oz: int
var mat_wall: int
var mat_roof: int
var mat_trim: int
var mat_found: int
var mat_floor: int            ## what you are standing on indoors

var interior: Rect2i          ## patch-local interior rect (x, z)
var cells: Array[Rect2i] = []
var cell_module: Array = []   ## parallel to cells: module spec Dictionary or null
var cell_story: Array[int] = []
var story_cells: Dictionary = {}   ## story -> Array of cell indices
var flue_spots: Dictionary = {}    ## cell index -> Vector2i, patch-local


func _run(s: Dictionary, world_seed: int, p: Plot, c: Dictionary) -> Dictionary:
	spec = s
	plot = p
	ctx = c
	world = c["world"]
	seed_value = world_seed

	_resolve_orientation()
	_resolve_dimensions()

	var e := _stage_site()
	if not e.is_empty():
		return {"ok": false, "error": e}
	_stage_envelope()
	e = _stage_partition()
	if not e.is_empty():
		return {"ok": false, "error": e}
	_stage_circulation()
	_stage_roof()
	_stage_openings()
	_stage_detail()
	_stage_props()

	patch.archetype = spec.get("archetype", "building")
	patch.sign_text = str(spec.get("sign", "")).to_upper()
	patch.compute_cost()
	patch.compute_build_order()

	var post := Validator.check_patch(patch, self, ctx)
	if not post.is_empty():
		return {"ok": false, "error": post}
	return {"ok": true, "patch": patch}


# ------------------------------------------------------------- orientation

func _resolve_orientation() -> void:
	var want := str(spec.get("orientation", "face_street"))
	var f := plot.street_dir
	match want:
		"face_north":
			f = Vector3i(0, 0, -1)
		"face_plaza":
			f = _axis_toward((ctx["village"] as Village).well_pos)
		"face_water":
			f = _axis_toward(_nearest_water())
		"match_neighbour":
			f = _neighbour_front()
		_:
			f = plot.street_dir
	if f == Vector3i.ZERO:
		f = Vector3i(0, 0, -1)
	front = f
	right = Vector3i(-f.z, 0, f.x)


func _axis_toward(target: Vector3) -> Vector3i:
	var d := target - plot.centre_m()
	if absf(d.x) > absf(d.z):
		return Vector3i(1, 0, 0) if d.x > 0.0 else Vector3i(-1, 0, 0)
	return Vector3i(0, 0, 1) if d.z > 0.0 else Vector3i(0, 0, -1)


## A bearing toward open water, for orientation "face_water". Walks outward on
## the height field rather than assuming where the coast is, because in an
## endless world it could be in any direction.
func _nearest_water() -> Vector3:
	var g: WorldGen = ctx["worldgen"]
	var here := plot.centre_m()
	var best := here + Vector3(0, 0, 200.0)
	var best_d := INF
	for a in 8:
		var ang := a * TAU / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		for step in range(4, 40):
			var p := here + dir * float(step * 8)
			if g.is_submerged(int(p.x / V), int(p.z / V)):
				if float(step) < best_d:
					best_d = float(step)
					best = p
				break
	return best


func _neighbour_front() -> Vector3i:
	var built: Dictionary = ctx.get("built_fronts", {})
	for nid: int in plot.neighbours:
		if built.has(nid):
			return built[nid]
	return plot.street_dir


# -------------------------------------------------------------- dimensions

func _resolve_dimensions() -> void:
	var fp: Array = spec.get("footprint", [8, 7])
	var frontage := int(round(float(fp[0]) / V))
	var depth := int(round(float(fp[1]) / V))

	if front.x != 0:
		W = depth
		D = frontage
	else:
		W = frontage
		D = depth

	# Never overrun the parcel, whatever the model asked for — and never come
	# in under seven metres either. The floor used to be three, which is a
	# building the size of a garden shed, and "build a hut" landed on it.
	W = clampi(W, mini(28, plot.size_v.x), plot.size_v.x)
	D = clampi(D, mini(28, plot.size_v.y), plot.size_v.y)

	stories = clampi(int(spec.get("stories", 1)), 1,
		Vocabulary.max_stories(int(ctx.get("tier", 1))))

	var mats: Dictionary = spec.get("materials", {})
	mat_wall = VoxelTypes.id_of(str(mats.get("walls", "timber")))
	mat_roof = VoxelTypes.id_of(str(mats.get("roof", "thatch")))
	mat_trim = VoxelTypes.id_of(str(mats.get("trim", "dark_oak")))
	mat_found = VoxelTypes.id_of(str(mats.get("foundation", "cobble")))
	if mat_wall < 0: mat_wall = VoxelTypes.TIMBER
	if mat_roof < 0: mat_roof = VoxelTypes.THATCH
	if mat_trim < 0: mat_trim = VoxelTypes.DARK_OAK
	if mat_found < 0: mat_found = VoxelTypes.COBBLE

	# The foundation is a plinth, not a floor. Laying it right through the
	# interior left every room with a cold blue flagstone floor no matter what
	# the building was, which read as a cellar. Indoors gets boards, or tile
	# where there is fire and flour about.
	mat_floor = VoxelTypes.id_of(str(mats.get("floor", "")))
	if mat_floor < 0:
		mat_floor = VoxelTypes.PLANK
		if mat_wall in [VoxelTypes.BRICK, VoxelTypes.SANDSTONE,
				VoxelTypes.GRANITE, VoxelTypes.CONCRETE]:
			mat_floor = VoxelTypes.CLAY_TILE

	# Masonry gets a thicker wall than timber. The model has no say in this.
	wall_t = 2 if mat_wall in [VoxelTypes.BRICK, VoxelTypes.SANDSTONE,
		VoxelTypes.GRANITE, VoxelTypes.CONCRETE, VoxelTypes.REBAR_CONCRETE] else 1

	ground = plot.ground_y

	# Sit the building against its street frontage, centred on the other axis.
	# Two metres off the pavement rather than three quarters of one: the plots
	# are thirty metres now, and a building shoved flat against the kerb wastes
	# all of that behind it.
	var setback := 8
	var bx0: int
	var bz0: int
	if front.z < 0:
		bz0 = plot.origin.z + setback
		bx0 = plot.origin.x + (plot.size_v.x - W) / 2
	elif front.z > 0:
		bz0 = plot.origin.z + plot.size_v.y - D - setback
		bx0 = plot.origin.x + (plot.size_v.x - W) / 2
	elif front.x < 0:
		bx0 = plot.origin.x + setback
		bz0 = plot.origin.z + (plot.size_v.y - D) / 2
	else:
		bx0 = plot.origin.x + plot.size_v.x - W - setback
		bz0 = plot.origin.z + (plot.size_v.y - D) / 2

	var total_h := stories * STORY_H + _roof_peak() + 6
	patch = VoxelPatch.new(
		Vector3i(bx0 - PATCH_MARGIN, ground - FOUNDATION_D, bz0 - PATCH_MARGIN),
		Vector3i(W + PATCH_MARGIN * 2, total_h + FOUNDATION_D, D + PATCH_MARGIN * 2))
	ox = PATCH_MARGIN
	oz = PATCH_MARGIN
	patch.footprint = Rect2i(bx0, bz0, W, D)
	patch.front = front
	patch.plot_id = plot.id


func _roof_peak() -> int:
	match str(spec.get("roof", "gable")):
		"flat": return 4
		"shed": return int(maxf(W, D) * SHED_SLOPE) + 3
		"dome": return int(minf(W, D) * 0.55) + 3
		"hangar_arch": return int(minf(W, D) * 0.55) + 3
		"sawtooth": return 10
		_: return int(minf(W, D) * 0.5 * ROOF_SLOPE) + 4


## Patch-local y of the ground surface.
func gy() -> int:
	return FOUNDATION_D


func story_base(s: int) -> int:
	return gy() + s * STORY_H


func wall_top() -> int:
	return story_base(stories - 1) + CLEAR_H


# -------------------------------------------------------------- stage 1: site

func _stage_site() -> Dictionary:
	var rng := DetRng.new(seed_value, plot.id, STEP_SITE)

	# Level the pad and everything within the eaves, then dig the footing.
	for z in range(-2, D + 2):
		for x in range(-2, W + 2):
			var px := ox + x
			var pz := oz + z
			# Only clear as high as the ground actually stands. On level ground
			# this writes nothing; on a slope it cuts the terrace. Clearing the
			# whole patch column instead cost a hundred thousand pointless air
			# writes per building.
			var wh := world.height_at(patch.origin.x + px, patch.origin.z + pz)
			var top_local := mini(wh - patch.origin.y, patch.size.y - 1)
			for y in range(gy() + 1, top_local + 1):
				patch.put(px, y, pz, VoxelTypes.AIR)
			for y in range(0, gy() + 1):
				patch.put(px, y, pz, mat_found)

	# A doorstep apron of foundation material out to the street, so the door
	# does not open onto grass.
	var step_len := 6 + rng.randi_range(0, 4)
	var cx := ox + W / 2
	var cz := oz + D / 2
	for i in range(0, step_len):
		for k in range(-DOOR_W, DOOR_W + 1):
			var off := front * i + right * k
			patch.put(cx + off.x + (front.x * W / 2), gy(),
				cz + off.z + (front.z * D / 2), mat_found)

	if W < 24 or D < 24:
		return Validator.error("footprint_too_small",
			"That plot is too tight for what you asked for.")
	return {}


# ---------------------------------------------------------- stage 2: envelope

func _stage_envelope() -> void:
	for s in stories:
		var base := story_base(s)
		# Floor slab: the plinth carries the walls, boards carry the people.
		for z in D:
			for x in W:
				var under_wall := x < wall_t or z < wall_t 					or x >= W - wall_t or z >= D - wall_t
				patch.put(ox + x, base, oz + z,
					mat_found if (s == 0 and under_wall) else mat_floor)
		# Perimeter wall.
		for y in range(base + 1, base + CLEAR_H + 1):
			for z in D:
				for x in W:
					if x < wall_t or z < wall_t or x >= W - wall_t or z >= D - wall_t:
						patch.put(ox + x, y, oz + z, mat_wall)
					else:
						patch.put(ox + x, y, oz + z, VoxelTypes.AIR)
	# Ceiling over the top story is the roof's job.


# --------------------------------------------------------- stage 3: partition

## Binary space partition of each story, then modules assigned to cells by score
## against their stated wall, adjacency, size and needs.
func _stage_partition() -> Dictionary:
	var rng := DetRng.new(seed_value, plot.id, STEP_PARTITION)
	interior = Rect2i(ox + wall_t, oz + wall_t, W - wall_t * 2, D - wall_t * 2)

	var by_story := {}
	for s in stories:
		by_story[s] = []
	for m: Variant in spec.get("modules", []):
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		by_story[_story_of(md)].append(md)

	cells.clear()
	cell_module.clear()
	cell_story.clear()
	story_cells.clear()

	for s in stories:
		var mods: Array = by_story[s]
		var want := maxi(mods.size(), 1)
		var rects := _bsp(interior, want, rng)
		var first := cells.size()
		var idxs: Array[int] = []
		for r: Rect2i in rects:
			cells.append(r)
			cell_module.append(null)
			cell_story.append(s)
			idxs.append(cells.size() - 1)
		story_cells[s] = idxs

		var err := _assign(mods, idxs)
		if not err.is_empty():
			return err
		patch.interior_cells.append_array(rects)
		if first == 0:
			pass
	return {}


func _story_of(m: Dictionary) -> int:
	var v: Variant = m.get("story", "ground")
	if v is int:
		return clampi(int(v), 0, stories - 1)
	match str(v):
		"top": return stories - 1
		_: return 0


func _bsp(rect: Rect2i, n: int, rng: DetRng) -> Array[Rect2i]:
	var out: Array[Rect2i] = [rect]
	var guard := 0
	while out.size() < n and guard < 64:
		guard += 1
		# Split the largest splittable rect along its longer axis.
		var best := -1
		var best_area := 0
		for i in out.size():
			var r: Rect2i = out[i]
			if r.size.x < MIN_CELL * 2 + 1 and r.size.y < MIN_CELL * 2 + 1:
				continue
			var a := r.size.x * r.size.y
			if a > best_area:
				best_area = a
				best = i
		if best < 0:
			break
		var r0: Rect2i = out[best]
		var horizontal := r0.size.x >= r0.size.y
		if horizontal and r0.size.x < MIN_CELL * 2 + 1:
			horizontal = false
		elif not horizontal and r0.size.y < MIN_CELL * 2 + 1:
			horizontal = true
		var span := r0.size.x if horizontal else r0.size.y
		var lo := MIN_CELL
		var hi := span - MIN_CELL - 1
		if hi <= lo:
			out.remove_at(best)
			out.append(r0)
			break
		var cut := rng.randi_range(lo, hi)
		var a1: Rect2i
		var b1: Rect2i
		if horizontal:
			a1 = Rect2i(r0.position, Vector2i(cut, r0.size.y))
			b1 = Rect2i(r0.position + Vector2i(cut + 1, 0),
				Vector2i(r0.size.x - cut - 1, r0.size.y))
		else:
			a1 = Rect2i(r0.position, Vector2i(r0.size.x, cut))
			b1 = Rect2i(r0.position + Vector2i(0, cut + 1),
				Vector2i(r0.size.x, r0.size.y - cut - 1))
		out.remove_at(best)
		out.append(a1)
		out.append(b1)
	return out


func _assign(mods: Array, idxs: Array[int]) -> Dictionary:
	var order: Array = []
	for m: Dictionary in mods:
		var pr := str(m.get("priority", "preferred"))
		var rank := 0 if pr == "required" else (1 if pr == "preferred" else 2)
		order.append([rank, m])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	for entry: Array in order:
		var m: Dictionary = entry[1]
		var best := -1
		var best_score := -INF
		for i: int in idxs:
			if cell_module[i] != null:
				continue
			var sc := _score(m, i)
			if sc > best_score:
				best_score = sc
				best = i
		if best < 0:
			if str(m.get("priority", "preferred")) == "required":
				return Validator.error("no_room_for_required_module",
					"There is no room in there for the %s." % str(m.get("type", "module")))
			patch.dropped_modules.append(str(m.get("type", "module")))
			continue
		cell_module[best] = m
	return {}


func _score(m: Dictionary, ci: int) -> float:
	var r: Rect2i = cells[ci]
	var mtype := str(m.get("type", ""))
	var d := Vocabulary.def(mtype)
	var score := 1.0

	var want_wall := str(m.get("wall", "any"))
	var touches := _touches(r)
	if want_wall == "centre":
		score += 9.0 if touches.is_empty() else -3.0
	elif want_wall != "any":
		score += 10.0 if _world_side(want_wall) in touches else -4.0
	if d.get("wants_wall", false) and touches.is_empty():
		score -= 6.0

	# Size class: how close the cell is to the area the module asks for.
	var area_m := r.size.x * r.size.y * V * V
	var want_area := Vocabulary.size_area(str(m.get("size", "medium")))
	score += 5.0 / (1.0 + absf(area_m - want_area) / maxf(want_area, 1.0))

	var min_m: Array = d.get("min_m", [1.0, 1.0])
	if r.size.x * V < float(min_m[0]) or r.size.y * V < float(min_m[1]):
		if r.size.y * V < float(min_m[0]) or r.size.x * V < float(min_m[1]):
			score -= 8.0

	var adj := str(m.get("adjacent_to", ""))
	if adj != "":
		for j in cells.size():
			if cell_module[j] != null and str(cell_module[j].get("type", "")) == adj:
				if _adjacent(cells[j], r):
					score += 6.0
				break

	for need: String in Vocabulary.needs_of(m):
		if need == "road_access" and _world_side("front") in touches:
			score += 4.0
		elif need == "chimney" and not touches.is_empty():
			score += 2.0

	return score


## Which world sides of the interior rect this cell touches.
func _touches(r: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if r.position.x <= interior.position.x:
		out.append(Vector3i(-1, 0, 0))
	if r.position.x + r.size.x >= interior.position.x + interior.size.x:
		out.append(Vector3i(1, 0, 0))
	if r.position.y <= interior.position.y:
		out.append(Vector3i(0, 0, -1))
	if r.position.y + r.size.y >= interior.position.y + interior.size.y:
		out.append(Vector3i(0, 0, 1))
	return out


func _world_side(name: String) -> Vector3i:
	match name:
		"front": return front
		"back": return -front
		"right": return right
		"left": return -right
	return Vector3i.ZERO


static func _adjacent(a: Rect2i, b: Rect2i) -> bool:
	var ax1 := a.position.x + a.size.x
	var bx1 := b.position.x + b.size.x
	var az1 := a.position.y + a.size.y
	var bz1 := b.position.y + b.size.y
	var x_overlap := mini(ax1, bx1) - maxi(a.position.x, b.position.x)
	var z_overlap := mini(az1, bz1) - maxi(a.position.y, b.position.y)
	if x_overlap > MIN_CELL and (az1 + 1 == b.position.y or bz1 + 1 == a.position.y):
		return true
	if z_overlap > MIN_CELL and (ax1 + 1 == b.position.x or bx1 + 1 == a.position.x):
		return true
	return false


# ------------------------------------------------------- stage 4: circulation

func _stage_circulation() -> void:
	var rng := DetRng.new(seed_value, plot.id, STEP_CIRCULATION)

	for s in stories:
		var idxs: Array = story_cells.get(s, [])
		_walls_between(idxs, s)
		var entry := _entrance_cell(idxs)
		_carve_doors(idxs, entry, s, rng)
		if s == 0:
			_carve_front_door(entry, rng)
			patch.entrance_cell = Rect2i(
				cells[entry].position + Vector2i(patch.origin.x, patch.origin.z),
				cells[entry].size)

	# Stairs, if the spec asked for them or the building simply has more floors.
	if stories > 1:
		_carve_stairs()


func _walls_between(idxs: Array, s: int) -> void:
	var base := story_base(s)
	for i: int in idxs:
		var r: Rect2i = cells[i]
		# Draw only the low edges, so a shared boundary is written once.
		if r.position.x > interior.position.x:
			for z in range(r.position.y, r.position.y + r.size.y):
				for y in range(base + 1, base + CLEAR_H + 1):
					patch.put(r.position.x - 1, y, z, mat_wall)
		if r.position.y > interior.position.y:
			for x in range(r.position.x, r.position.x + r.size.x):
				for y in range(base + 1, base + CLEAR_H + 1):
					patch.put(x, y, r.position.y - 1, mat_wall)


func _entrance_cell(idxs: Array) -> int:
	var best := -1
	var best_score := -1.0
	for i: int in idxs:
		var sc := 0.0
		if cell_module[i] != null and str(cell_module[i].get("type", "")) == "entrance":
			sc += 20.0
		if _world_side("front") in _touches(cells[i]):
			sc += 10.0
		sc += float(cells[i].size.x * cells[i].size.y) * 0.01
		if sc > best_score:
			best_score = sc
			best = i
	return best if best >= 0 else (idxs[0] if not idxs.is_empty() else 0)


## Spanning tree over the cell adjacency graph, one doorway per tree edge. Every
## room is therefore reachable from the entrance by construction, which is what
## the post-validator checks.
func _carve_doors(idxs: Array, entry: int, s: int, rng: DetRng) -> void:
	var base := story_base(s)
	var seen := {entry: true}
	var frontier: Array[int] = [entry]
	var guard := 0
	while not frontier.is_empty() and guard < 256:
		guard += 1
		var cur: int = frontier.pop_front()
		for j: int in idxs:
			if seen.has(j) or j == cur:
				continue
			if not _adjacent(cells[cur], cells[j]):
				continue
			_carve_doorway(cells[cur], cells[j], base, rng)
			seen[j] = true
			frontier.append(j)

	# Anything the tree could not reach loses its partition walls entirely,
	# rather than becoming a sealed room nobody can enter.
	for j: int in idxs:
		if not seen.has(j):
			_open_cell(cells[j], base)


func _carve_doorway(a: Rect2i, b: Rect2i, base: int, _rng: DetRng) -> void:
	var ax1 := a.position.x + a.size.x
	var bx1 := b.position.x + b.size.x
	var az1 := a.position.y + a.size.y
	var bz1 := b.position.y + b.size.y

	if az1 + 1 == b.position.y or bz1 + 1 == a.position.y:
		var wz := az1 if az1 + 1 == b.position.y else bz1
		var lo := maxi(a.position.x, b.position.x)
		var hi := mini(ax1, bx1) - 1
		var c := (lo + hi) / 2
		for x in range(c - DOOR_W / 2, c - DOOR_W / 2 + DOOR_W):
			for y in range(base + 1, base + 1 + DOOR_H):
				patch.put(x, y, wz, VoxelTypes.AIR)
		patch.doors.append(patch.local_to_world(c, base + 1, wz))
	else:
		var wx := ax1 if ax1 + 1 == b.position.x else bx1
		var lo2 := maxi(a.position.y, b.position.y)
		var hi2 := mini(az1, bz1) - 1
		var c2 := (lo2 + hi2) / 2
		for z in range(c2 - DOOR_W / 2, c2 - DOOR_W / 2 + DOOR_W):
			for y in range(base + 1, base + 1 + DOOR_H):
				patch.put(wx, y, z, VoxelTypes.AIR)
		patch.doors.append(patch.local_to_world(wx, base + 1, c2))


func _open_cell(r: Rect2i, base: int) -> void:
	for y in range(base + 1, base + CLEAR_H + 1):
		for z in range(r.position.y - 1, r.position.y + r.size.y + 1):
			for x in range(r.position.x - 1, r.position.x + r.size.x + 1):
				if x <= interior.position.x - 1 or z <= interior.position.y - 1:
					continue
				if x >= interior.position.x + interior.size.x \
						or z >= interior.position.y + interior.size.y:
					continue
				patch.put(x, y, z, VoxelTypes.AIR)


func _carve_front_door(entry: int, _rng: DetRng) -> void:
	var r: Rect2i = cells[entry]
	var base := story_base(0)
	var f := front
	var cx := r.position.x + r.size.x / 2
	var cz := r.position.y + r.size.y / 2

	if f.z != 0:
		var wz := oz + (D - 1 if f.z > 0 else 0)
		for t in wall_t:
			var z := wz - f.z * t
			for x in range(cx - DOOR_W / 2, cx - DOOR_W / 2 + DOOR_W):
				for y in range(base + 1, base + 1 + DOOR_H):
					patch.put(x, y, z, VoxelTypes.AIR)
		patch.doors.push_front(patch.local_to_world(cx, base + 1, wz))
	else:
		var wx := ox + (W - 1 if f.x > 0 else 0)
		for t in wall_t:
			var x2 := wx - f.x * t
			for z in range(cz - DOOR_W / 2, cz - DOOR_W / 2 + DOOR_W):
				for y in range(base + 1, base + 1 + DOOR_H):
					patch.put(x2, y, z, VoxelTypes.AIR)
		patch.doors.push_front(patch.local_to_world(wx, base + 1, cz))


func _carve_stairs() -> void:
	# A straight flight in the back-left corner of every floor but the top.
	var sx := interior.position.x + 1
	var sz := interior.position.y + 1
	for s in range(0, stories - 1):
		var base := story_base(s)
		var top := story_base(s + 1)
		var steps := top - base
		for i in range(0, steps + 1):
			for w in range(0, 6):
				for dz in range(0, 3):
					patch.put(sx + w, base + i, sz + i / 2 + dz, mat_trim)
					patch.put(sx + w, base + i + 1, sz + i / 2 + dz, VoxelTypes.AIR)
		# Hole through the slab above.
		for w in range(0, 6):
			for dz in range(0, steps / 2 + 3):
				patch.put(sx + w, top, sz + dz, VoxelTypes.AIR)


# --------------------------------------------------------------- stage 5: roof

func _stage_roof() -> void:
	var kind := str(spec.get("roof", "gable"))
	var top := wall_top()
	var over := 2                       ## eaves overhang, voxels

	if kind == "flat":
		for z in range(-over, D + over):
			for x in range(-over, W + over):
				patch.put(ox + x, top + 1, oz + z, mat_roof)
		# Parapet.
		for z in range(-over, D + over):
			for x in range(-over, W + over):
				var edge := x < 0 or z < 0 or x >= W or z >= D
				if edge:
					for y in range(top + 2, top + 5):
						patch.put(ox + x, y, oz + z, mat_wall)
		_cut_penetrations(top + 5)
		return

	for z in range(-over, D + over):
		for x in range(-over, W + over):
			var rh := _roof_height(kind, x, z)
			if rh < 0:
				continue
			var rmin := rh
			for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(0, 1), Vector2i(0, -1)]:
				rmin = mini(rmin, maxi(_roof_height(kind, x + n.x, z + n.y), 0))
			var y0 := top + 1
			# Gable / hip ends: close the wall under the slope.
			var on_wall := (x < wall_t or z < wall_t or x >= W - wall_t or z >= D - wall_t) \
				and x >= 0 and z >= 0 and x < W and z < D
			if on_wall:
				for y in range(y0, top + rh + 1):
					patch.put(ox + x, y, oz + z, mat_wall)
			elif x >= 0 and z >= 0 and x < W and z < D:
				for y in range(y0, top + rh + 1):
					patch.put(ox + x, y, oz + z, VoxelTypes.AIR)
			for y in range(top + rmin + 1, top + rh + 3):
				patch.put(ox + x, y, oz + z, mat_roof)

	_cut_penetrations(top + _roof_peak() + 3)


## Puts the flue against whichever exterior wall the room touches, inset far
## enough that the 5x5 stack stays inside the room, and never across its middle.
func _flue_spot(r: Rect2i) -> Vector2i:
	var inset := 3
	var cx := r.position.x + r.size.x / 2
	var cz := r.position.y + r.size.y / 2
	var touches := _touches(r)
	if not touches.is_empty():
		var side: Vector3i = touches[0]
		if side.x < 0:
			cx = r.position.x + inset
		elif side.x > 0:
			cx = r.position.x + r.size.x - 1 - inset
		elif side.z < 0:
			cz = r.position.y + inset
		else:
			cz = r.position.y + r.size.y - 1 - inset
	cx = clampi(cx, r.position.x + inset, r.position.x + maxi(r.size.x - 1 - inset, inset))
	cz = clampi(cz, r.position.y + inset, r.position.y + maxi(r.size.y - 1 - inset, inset))
	return Vector2i(cx, cz)


func _roof_height(kind: String, x: int, z: int) -> int:
	var fx := float(x) + 0.5
	var fz := float(z) + 0.5
	var hw := W * 0.5
	var hd := D * 0.5
	match kind:
		"shed":
			# Falls toward the street, so rain runs off the front.
			var t := (fz / maxf(D, 1)) if front.z < 0 else (1.0 - fz / maxf(D, 1))
			if front.x != 0:
				t = (fx / maxf(W, 1)) if front.x < 0 else (1.0 - fx / maxf(W, 1))
			return int(t * maxf(W, D) * SHED_SLOPE)
		"hip":
			var d := minf(minf(fx, W - fx), minf(fz, D - fz))
			return int(maxf(d, 0.0) * ROOF_SLOPE)
		"dome":
			var r := minf(hw, hd)
			var dd := Vector2(fx - hw, fz - hd).length()
			if dd >= r:
				return 0
			return int(sqrt(maxf(r * r - dd * dd, 0.0)) * 0.9)
		"hangar_arch":
			# Barrel vault springing from the long walls.
			var along_x := W >= D
			var u := (fz - hd) / maxf(hd, 1.0) if along_x else (fx - hw) / maxf(hw, 1.0)
			u = clampf(u, -1.0, 1.0)
			return int(sqrt(maxf(1.0 - u * u, 0.0)) * minf(hw, hd) * 1.1)
		"sawtooth":
			var period := 10.0
			var u2 := fposmod(fx if W >= D else fz, period) / period
			return int(u2 * 7.0) + 1
		_:  # gable
			if W >= D:
				return int((hd - absf(fz - hd)) * ROOF_SLOPE)
			return int((hw - absf(fx - hw)) * ROOF_SLOPE)


## Chimneys and vents must reach open sky — the post-validator enforces it, so
## the generator has to actually cut the hole.
func _cut_penetrations(sky_y: int) -> void:
	for i in cells.size():
		var m = cell_module[i]
		if m == null:
			continue
		var needs := Vocabulary.needs_of(m)
		if not ("chimney" in needs or "ventilation" in needs):
			continue
		var r: Rect2i = cells[i]
		var flue := _flue_spot(r)
		flue_spots[i] = flue
		var cx := flue.x
		var cz := flue.y
		var stack_mat := mat_wall if "chimney" in needs else VoxelTypes.CORRUGATED_STEEL
		var base := story_base(cell_story[i]) + 1
		for y in range(base, sky_y + 5):
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var edge := absi(dx) == 2 or absi(dz) == 2
					if y < wall_top():
						if edge:
							patch.put(cx + dx, y, cz + dz, stack_mat)
					else:
						patch.put(cx + dx, y, cz + dz, stack_mat if edge else VoxelTypes.AIR)
			patch.put(cx, y, cz, VoxelTypes.AIR)
			patch.put(cx + 1, y, cz, VoxelTypes.AIR)
			patch.put(cx, y, cz + 1, VoxelTypes.AIR)
			patch.put(cx + 1, y, cz + 1, VoxelTypes.AIR)


# ----------------------------------------------------------- stage 6: openings

func _stage_openings() -> void:
	var rng := DetRng.new(seed_value, plot.id, STEP_OPENINGS)
	# Glazing is an engine decision, not a model one: the tier gate on the glass
	# material governs what the model may *name*, not what a window is made of.
	# Tier 1 gets a heavy trim mullion through the opening so it reads as a
	# rustic shuttered window rather than a plate-glass shopfront.
	var glass := VoxelTypes.GLASS
	var rustic := int(ctx.get("tier", 1)) < 2
	for s in stories:
		var base := story_base(s)
		var sill := base + 1 + WIN_SILL
		for side: Vector3i in [front, -front, right, -right]:
			_windows_on(side, base, sill, s, glass, rustic, rng)


func _windows_on(side: Vector3i, base: int, sill: int, s: int,
		glass: int, rustic: bool, rng: DetRng) -> void:
	var along_x := side.z != 0
	var span := W if along_x else D
	var fixed := 0
	if side.z < 0:
		fixed = 0
	elif side.z > 0:
		fixed = D - 1
	elif side.x < 0:
		fixed = 0
	else:
		fixed = W - 1

	var pos := WIN_PIER + rng.randi_range(0, 2)
	while pos + WIN_W < span - WIN_PIER:
		var mid := pos + WIN_W / 2
		if not _window_allowed(along_x, mid, side, s, base):
			pos += WIN_W + WIN_PIER
			continue
		for k in WIN_W:
			for y in range(sill, sill + WIN_H):
				for t in wall_t:
					var lx: int
					var lz: int
					if along_x:
						lx = pos + k
						lz = fixed + (t if side.z < 0 else -t)
					else:
						lx = fixed + (t if side.x < 0 else -t)
						lz = pos + k
					patch.put(ox + lx, y, oz + lz, glass)
		# A mullion cross at tier 1. Without it a pane of glass in a timber wall
		# reads as a hole, because the mesher culls the seam between two faces
		# of the same material and a plain shutter would vanish entirely.
		if rustic:
			for y in range(sill, sill + WIN_H):
				for t in wall_t:
					var mx: int
					var mz: int
					if along_x:
						mx = pos + WIN_W / 2
						mz = fixed + (t if side.z < 0 else -t)
					else:
						mx = fixed + (t if side.x < 0 else -t)
						mz = pos + WIN_W / 2
					patch.put(ox + mx, y, oz + mz, mat_trim)
			for k in WIN_W:
				for t in wall_t:
					var mx2: int
					var mz2: int
					if along_x:
						mx2 = pos + k
						mz2 = fixed + (t if side.z < 0 else -t)
					else:
						mx2 = fixed + (t if side.x < 0 else -t)
						mz2 = pos + k
					patch.put(ox + mx2, sill + WIN_H / 2, oz + mz2, mat_trim)

		# Lintel and sill in trim, which is what makes an opening read as a
		# window rather than as a hole.
		for k in range(-1, WIN_W + 1):
			for t in wall_t:
				var lx2: int
				var lz2: int
				if along_x:
					lx2 = pos + k
					lz2 = fixed + (t if side.z < 0 else -t)
				else:
					lx2 = fixed + (t if side.x < 0 else -t)
					lz2 = pos + k
				patch.put(ox + lx2, sill - 1, oz + lz2, mat_trim)
				patch.put(ox + lx2, sill + WIN_H, oz + lz2, mat_trim)
		pos += WIN_W + WIN_PIER + rng.randi_range(0, 2)


func _window_allowed(along_x: bool, mid: int, side: Vector3i, s: int, base: int) -> bool:
	# Never within a door width of the front door.
	if not patch.doors.is_empty() and s == 0 and side == front:
		var d := patch.doors[0] - patch.origin
		var dm := d.x if along_x else d.z
		if absi(dm - (ox if along_x else oz) - mid) < DOOR_W + 3:
			return false
	# Storage, armouries and docks get a blank wall.
	var probe_x := (ox + mid) if along_x else (ox + (1 if side.x < 0 else W - 2))
	var probe_z := (oz + (1 if side.z < 0 else D - 2)) if along_x else (oz + mid)
	for i in cells.size():
		if cell_story[i] != s or cell_module[i] == null:
			continue
		var r: Rect2i = cells[i]
		if r.has_point(Vector2i(probe_x, probe_z)):
			var d2 := Vocabulary.def(str(cell_module[i].get("type", "")))
			return not bool(d2.get("blocks_window", false))
	return true


# ------------------------------------------------------------- stage 7: detail

func _stage_detail() -> void:
	var rng := DetRng.new(seed_value, plot.id, STEP_DETAIL)

	# Corner posts, full height. On timber buildings this reads as exposed frame.
	for s in stories:
		var base := story_base(s)
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(W - 1, 0),
				Vector2i(0, D - 1), Vector2i(W - 1, D - 1)]:
			for y in range(base + 1, base + CLEAR_H + 1):
				for t in wall_t:
					patch.put(ox + corner.x + (t if corner.x == 0 else -t), y,
						oz + corner.y + (t if corner.y == 0 else -t), mat_trim)
		# Eaves course.
		var top := base + CLEAR_H
		for z in D:
			for x in W:
				if x < wall_t or z < wall_t or x >= W - wall_t or z >= D - wall_t:
					patch.put(ox + x, top, oz + z, mat_trim)

	# Kerb along the street frontage.
	for k in range(-2, (W if front.z != 0 else D) + 2):
		var off := front * (2 + rng.randi_range(0, 1))
		if front.z != 0:
			patch.put(ox + k, gy(), oz + (D + off.z if front.z > 0 else off.z), VoxelTypes.GRAVEL)
		else:
			patch.put(ox + (W + off.x if front.x > 0 else off.x), gy(), oz + k, VoxelTypes.GRAVEL)

	_hang_sign()


## The sign is a voxel board over the door in the trim material, with the text
## itself rendered as a Tier B prop so it stays readable at any distance.
func _hang_sign() -> void:
	if patch.doors.is_empty():
		return
	var d := patch.doors[0] - patch.origin
	var y := mini(story_base(0) + 2 + DOOR_H, wall_top() - 2)
	for k in range(-4, 5):
		for dy in range(0, 2):
			if front.z != 0:
				patch.put(d.x + k, y + dy, d.z, mat_trim)
			else:
				patch.put(d.x, y + dy, d.z + k, mat_trim)
	if patch.sign_text != "":
		var wpos := patch.local_to_world(d.x, y, d.z)
		patch.props.append({
			"type": "signboard_text",
			"pos": VoxelWorld.centre_metres(wpos) + Vector3(front) * 0.35,
			"yaw": _yaw_of(front),
			"text": patch.sign_text,
		})


static func _yaw_of(dir: Vector3i) -> float:
	if dir.z < 0:
		return 0.0
	if dir.z > 0:
		return PI
	return PI * 0.5 if dir.x > 0 else -PI * 0.5


# -------------------------------------------------------------- stage 8: props

func _stage_props() -> void:
	var rng := DetRng.new(seed_value, plot.id, STEP_PROPS)
	for i in cells.size():
		var m = cell_module[i]
		if m == null:
			continue
		var mtype := str(m.get("type", ""))
		var d := Vocabulary.def(mtype)
		var r: Rect2i = cells[i]
		var base := story_base(cell_story[i])
		patch.modules.append({
			"type": mtype,
			"rect": Rect2i(r.position + Vector2i(patch.origin.x, patch.origin.z), r.size),
			"story": cell_story[i],
			"priority": str(m.get("priority", "preferred")),
			"flue": flue_spots.get(i, Vector2i(-1, -1)),
		})

		_furnish(r, base, mtype, d.get("props", []), rng)

	# Rooms the partitioner never assigned a module to are still rooms. Left
	# bare they read as an unfinished house, and being unlit they read as a
	# cupboard.
	for i in cells.size():
		if cell_module[i] != null:
			continue
		var base2 := story_base(cell_story[i])
		_furnish(cells[i], base2, "spare_room",
			[["lantern", 1], ["chest", 1], ["stool", 2], ["basket", 1]], rng)


## Places one room's worth of furniture, guaranteeing a light.
##
## Every room gets something that glows. Without it the interior is lit only by
## whatever the windows let in, and away from the window wall that is nothing at
## all — the first interior screenshots were near-black at midday.
func _furnish(r: Rect2i, base: int, mtype: String, wanted: Array,
		rng: DetRng) -> void:
	var lights: Array[String] = []
	var rest: Array[String] = []
	for entry: Variant in wanted:
		var e: Array = entry
		var ptype := str(e[0])
		for _k in int(e[1]):
			if Props.LIGHTS.has(Props.resolve(ptype)):
				lights.append(ptype)
			else:
				rest.append(ptype)
	if lights.is_empty():
		lights.append("lantern")

	# Big things first, so a table claims its floor before four stools fill the
	# room with places it can no longer stand — but the light goes down before
	# any of them. A room that runs out of floor still has to be a room you can
	# see, and sorting by size alone put the lantern last and dropped it.
	rest.sort_custom(func(a: String, b: String) -> bool:
		return Props.radius(a) > Props.radius(b))
	var list: Array[String] = lights
	list.append_array(rest)

	var spots := _prop_spots(r, base, rng)
	var taken: Array[Vector3] = []      ## x, z, radius
	for ptype: String in list:
		var rad := Props.radius(ptype)
		var at := -1
		for i in spots.size():
			var c := Vector2(spots[i])
			var clear := true
			for t: Vector3 in taken:
				if Vector2(t.x, t.y).distance_to(c) < (rad + t.z) / V:
					clear = false
					break
			if clear:
				at = i
				break
		if at < 0:
			continue
		var p: Vector2i = spots[at]
		spots.remove_at(at)
		taken.append(Vector3(p.x, p.y, rad))
		var backed := Props.wall_backed(ptype)
		var wall: Array = _wall_for(r, p, Props.depth(ptype)) if backed \
			else _nearest_wall(r, p)
		var pos := VoxelWorld.centre_metres(
			patch.local_to_world(p.x, base + 1, p.y)) - Vector3(0, 0.125, 0)
		if backed:
			# Set the distance from the wall rather than nudging toward it. A bed
			# is 2.25 m long; dropped on a grid square half a metre from the wall
			# it hangs two thirds of a metre through the plaster, and nudging it
			# closer only makes that worse. Placing its back at a fixed clearance
			# from the wall puts the whole thing inside the room by construction.
			#
			# The clearance is a fifth of a metre because a partition wall is
			# drawn on the cell edge; against an outside wall the cell edge is
			# already the inner face, and this still reads as flush.
			var want := Props.back_extent(ptype) + 0.20
			pos -= Vector3(wall[0]) * (float(wall[1]) * V - want)
			pos.y += Props.mount_y(ptype)
			# And then check, rather than trust the margin. A partition wall is
			# drawn on the cell edge and an outside wall is not, so no single
			# clearance is right for both — pushing everything back by a fixed
			# amount put lanterns inside partitions, and the post-validator
			# threw out the whole building for it.
			pos = _backed_off(pos, Vector3(wall[0]))
			if pos == Vector3.INF:
				continue
		patch.props.append({
			"type": ptype,
			"pos": pos,
			"yaw": _facing_yaw(wall[0]),
			"module": mtype,
		})


## Candidate prop positions: hugging the walls first, then the middle, spaced so
## furniture does not pile up. Deterministic order, shuffled by the step RNG.
##
## Runs after every other stage, so it can reject any spot the geometry has
## already claimed — a stair flight, a chimney stack, a partition wall. Without
## that check the post-validator rejects the whole building for prop clipping,
## which is a nonsense reason to refuse a job.
func _prop_spots(r: Rect2i, base: int, rng: DetRng) -> Array[Vector2i]:
	var out: Array = []
	var step := 3
	# Two voxels of clearance from the wall line, not one: at one voxel a bench
	# half a metre deep stands with its back inside the wall.
	var x0 := r.position.x + 2
	var z0 := r.position.y + 2
	var x1 := r.position.x + r.size.x - 3
	var z1 := r.position.y + r.size.y - 3
	if x1 < x0 or z1 < z0:
		x0 = r.position.x + 1
		z0 = r.position.y + 1
		x1 = r.position.x + r.size.x - 2
		z1 = r.position.y + r.size.y - 2
	for z in range(z0, z1 + 1, step):
		for x in range(x0, x1 + 1, step):
			if not _spot_clear(x, z, base):
				continue
			var edge := x <= x0 + 1 or z <= z0 + 1 or x >= x1 - 1 or z >= z1 - 1
			out.append([0 if edge else 1, Vector2i(x, z)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var flat: Array[Vector2i] = []
	for e: Array in out:
		flat.append(e[1])
	if flat.size() > 3:
		var tail := flat.slice(2)
		rng.shuffle(tail)
		flat = flat.slice(0, 2)
		flat.append_array(tail)
	if flat.is_empty():
		# Nothing passed the full test. A hearth room is mostly chimney and a
		# cupboard is mostly wall, and both were coming out completely bare —
		# an unlit empty box with a flue in it. So sweep again asking only
		# that the square itself is free and has headroom.
		for z in range(r.position.y + 1, r.position.y + r.size.y - 1):
			for x in range(r.position.x + 1, r.position.x + r.size.x - 1):
				if _square_free(x, z, base):
					flat.append(Vector2i(x, z))
		rng.shuffle(flat)
	return flat


## The relaxed test: this one square, and room to stand a thing on it.
func _square_free(x: int, z: int, base: int) -> bool:
	for y in range(base + 1, base + 5):
		if patch.solid_at(x, y, z):
			return false
	return patch.peek(x, base, z) != VoxelPatch.UNTOUCHED


## A prop needs its own cell and standing room above it.
func _spot_clear(x: int, z: int, base: int) -> bool:
	for y in range(base + 1, base + 5):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if patch.solid_at(x + dx, y, z + dz):
					return false
	return patch.peek(x, base, z) != VoxelPatch.UNTOUCHED


## Which wall a spot belongs to, and how far it is from it in voxels.
##
## Returns [outward unit vector toward that wall, distance in voxels].
static func _nearest_wall(r: Rect2i, p: Vector2i) -> Array:
	var west := p.x - r.position.x
	var east := r.position.x + r.size.x - 1 - p.x
	var north := p.y - r.position.y
	var south := r.position.y + r.size.y - 1 - p.y
	var best := mini(mini(west, east), mini(north, south))
	if best == west:
		return [Vector3i(-1, 0, 0), west]
	if best == east:
		return [Vector3i(1, 0, 0), east]
	if best == north:
		return [Vector3i(0, 0, -1), north]
	return [Vector3i(0, 0, 1), south]


## Steps a prop away from its wall until its origin is out of the masonry.
##
## Returns Vector3.INF when there is nowhere clear within half a metre, in
## which case the prop is simply not placed. One missing barrel is a far
## better outcome than a refused building: the validator rejects the entire
## plan if a single prop sits inside a wall, and the worker then has to ask
## the player a question about it, which is a nonsense conversation to have.
func _backed_off(pos: Vector3, toward_wall: Vector3) -> Vector3:
	for step in 5:
		var l := VoxelWorld.to_voxel(pos) - patch.origin
		if not patch.solid_at(l.x, l.y, l.z):
			return pos
		pos -= toward_wall * V
	return Vector3.INF


## The wall a wall-backed prop should stand against.
##
## Nearest first, but only if the room is deep enough that way to take the
## whole prop. A bed against the near wall of a three-metre room sticks out
## of the far one; against the long wall it fits with room to walk past.
func _wall_for(r: Rect2i, p: Vector2i, prop_depth: float) -> Array:
	var options: Array = [
		[Vector3i(-1, 0, 0), p.x - r.position.x, r.size.x],
		[Vector3i(1, 0, 0), r.position.x + r.size.x - 1 - p.x, r.size.x],
		[Vector3i(0, 0, -1), p.y - r.position.y, r.size.y],
		[Vector3i(0, 0, 1), r.position.y + r.size.y - 1 - p.y, r.size.y],
	]
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for o: Array in options:
		if float(o[2]) * V >= prop_depth + 0.4:
			return [o[0], o[1]]
	return [options[0][0], options[0][1]]


## Facing, snapped to the four walls, always.
##
## The old version pointed each prop at the centre of the room, which put
## every bed and bench at whatever angle its grid position happened to make.
## A voxel building is axis-aligned and a bed at eleven degrees to the wall
## reads as a bug, not as character.
static func _facing_yaw(toward_wall: Vector3i) -> float:
	# Face away from the wall: local +Z is the front of every prop.
	return atan2(float(-toward_wall.x), float(-toward_wall.z))


# --------------------------------------------------------------- introspection

## Used by the validator and by the town register.
func footprint_rect_world() -> Rect2i:
	return Rect2i(patch.origin.x + ox, patch.origin.z + oz, W, D)


func required_modules() -> Array[String]:
	var out: Array[String] = []
	for m: Variant in spec.get("modules", []):
		if m is Dictionary and str((m as Dictionary).get("priority", "preferred")) == "required":
			out.append(str((m as Dictionary).get("type", "")))
	return out
