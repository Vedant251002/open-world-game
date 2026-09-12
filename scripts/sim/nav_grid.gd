extends RefCounted
class_name NavGrid
## Walkable-surface pathfinding over the voxel world.
##
## Godot's navmesh baker wants source geometry it can re-parse; a voxel town
## that changes every few minutes as buildings go up would have it rebaking
## constantly. The heightmap already knows the walkable surface exactly, so an
## A* grid over it is both cheaper and more reliable — and it updates in a few
## milliseconds when a wall appears.
##
## Cells are 1 m (four voxels). Finer than that buys nothing: a worker is a bit
## over half a metre across and the streets are seven.
##
## Three things stop a route from being a lie, and all three had to be here
## before the crew stopped wedging themselves into walls:
##
##   1. The heightmap is the top of the *world*, not the top of the ground, so
##      the column through a bakery reports the ridge of its roof. Left alone
##      that makes every roof in town a lovely flat piece of pavement, and A*
##      cheerfully routes over one — which is why a worker would walk into a
##      wall and stay there. `_flood_reach` throws away everything you cannot
##      actually walk to from the town floor, so roofs, ledges and the insides
##      of sealed buildings stop being part of the graph at all.
##   2. A cell is only as walkable as its worst corner. Sampling the centre
##      alone let a cell whose far half is solid masonry read as open ground.
##   3. A route down the exact edge of a wall is a route a body with width
##      cannot take, so solid cells are grown by one cell before the search
##      sees them. The path then runs a clear metre from everything.

const CELL_V := 4                   ## voxels per nav cell
const CELL_M := CELL_V * VoxelChunk.VOXEL_M
const MAX_STEP_V := 3               ## 0.75 m — a worker can manage a doorstep
## Clear voxels a worker needs over their head. They are 2.2 m to the crown.
const HEAD_V := 9
## How much the surface may vary inside one cell before the cell is a wall
## rather than a slope.
const ROUGH_V := 3
## Cells of elbow room kept between a route and anything solid.
const CLEARANCE := 1


var world: VoxelWorld
var size: Vector2i
var origin_v := Vector2i.ZERO        ## voxel coords of nav cell (0,0)
var astar := AStarGrid2D.new()
var heights: PackedInt32Array        ## surface voxel y per nav cell

## Surface walkability, before reachability and before clearance. This is what
## the flood fill runs over and what the dilation reads.
var _open: PackedByteArray
## Cells the town floor connects to. Recomputed only on a full rebuild — a
## flood fill over sixty thousand cells is a load-time cost, not something to
## pay every time a wall goes up.
var _reach: PackedByteArray
## The surface as it stood at the last full rebuild. Anything that rises more
## than a doorstep above it afterwards is a building, and you do not walk on
## buildings.
var _base_h: PackedInt32Array
## What was last handed to AStarGrid2D for each cell, so a commit that changes
## nothing costs nothing. 2 means "never told", which no real value can be.
var _committed: PackedByteArray
var _seed_cell := Vector2i(-1, -1)
## Chunk columns already read into the grid, keyed the way the world keys them.
## The town is a hundred and sixty metres across and only the ground around the
## spawn is loaded when the crew comes on, so most of the grid is built later,
## a column at a time, as the streamer catches up.
var _seen: Dictionary = {}

## Worst time one catch_up has taken, in milliseconds, for the bench to read.
var stat_worst_catch_ms := 0.0
## Columns to read in one pass.
##
## Four, not sixteen. Reading a column is cheap; committing one is not, because
## commit tests a clearance neighbourhood for every cell and then talks to
## AStarGrid2D about it. Sixteen at once measured at thirty milliseconds in a
## single frame — two dropped frames, right after load, exactly when the player
## is looking around for the first time. Four is a few milliseconds, and the
## caller runs often enough that the grid still fills in faster than anyone can
## walk across it.
const MAX_COLUMNS_PER_PASS := 4


## The grid covers the town and a walkable margin around it. The world beyond is
## endless, but the workers never leave the village, and an unbounded A* grid
## would be an unbounded allocation.
func build(w: VoxelWorld, area_v: Rect2i) -> void:
	world = w
	origin_v = area_v.position
	size = Vector2i(area_v.size.x / CELL_V, area_v.size.y / CELL_V)

	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(CELL_M, CELL_M)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	var n := size.x * size.y
	heights = PackedInt32Array()
	heights.resize(n)
	_open = PackedByteArray()
	_open.resize(n)
	_reach = PackedByteArray()
	_reach.resize(n)
	_base_h = PackedInt32Array()
	_base_h.resize(n)
	_committed = PackedByteArray()
	_committed.resize(n)
	_committed.fill(2)
	rebuild()


## Where the ground everybody shares is. The flood fill starts here, so it has
## to be somewhere nobody could argue with — the plaza around the well.
func set_ground_seed(at_m: Vector3) -> void:
	_seed_cell = to_cell(at_m)


## The walkable world, in voxels. Outside this there is ground but no route to
## it, so anything that picks a destination has to ask first.
func bounds_v() -> Rect2i:
	return Rect2i(origin_v, size * CELL_V)


## Everything, from the surface up. Costs a few hundred milliseconds on a grid
## this size, so it runs at load and after a demolition and nowhere else.
func rebuild() -> void:
	var whole := Rect2i(Vector2i.ZERO, size)
	_seen.clear()
	_base_h.fill(-1)
	_committed.fill(2)
	_surface_pass(whole)
	_flood_reach()
	_base_h = heights.duplicate()
	_commit(whole)
	_mark_seen(bounds_v())


## Recomputes walkability over a region of nav cells. Called with a small rect
## when a building goes up, so the cost is proportional to the change.
func refresh(region: Rect2i) -> void:
	_surface_pass(region)
	_commit(Rect2i(region.position - Vector2i(CLEARANCE, CLEARANCE),
		region.size + Vector2i(CLEARANCE * 2, CLEARANCE * 2)))


## Reads in whatever ground has arrived since last time.
##
## The grid covers the whole town from the moment it is built, but the world
## does not: chunks stream in around whoever is walking about, so at the moment
## the crew is raised the far half of the town is a hole in the heightmap and
## reads as unwalkable. Left alone that is a crew that can never be sent more
## than fifty metres, which looked exactly like the workers getting stuck.
##
## Called on a timer with the player's position. Costs nothing on the frames
## where nothing new has landed, which is most of them.
func catch_up(centre_m: Vector3, radius_v: int = 400) -> int:
	if world == null:
		return 0
	var t0 := Time.get_ticks_usec()
	var c := VoxelWorld.to_voxel(centre_m)
	var area := bounds_v()
	var x0 := maxi(c.x - radius_v, area.position.x) >> 5
	var x1 := mini(c.x + radius_v, area.end.x - 1) >> 5
	var z0 := maxi(c.z - radius_v, area.position.y) >> 5
	var z1 := mini(c.z + radius_v, area.end.y - 1) >> 5

	# Nearest first, and only so many at a time. Ground under the crew's feet
	# is worth more than ground at the edge of the grid, and a player walking
	# back into town after an hour away can have three hundred columns waiting.
	var waiting: Array[Vector2i] = []
	var here := Vector2i(c.x >> 5, c.z >> 5)
	for kz in range(z0, z1 + 1):
		for kx in range(x0, x1 + 1):
			var key := Vector2i(kx, kz)
			if _seen.has(key) or not world.has_column(kx, kz):
				continue
			waiting.append(key)
	if waiting.is_empty():
		return 0
	if waiting.size() > MAX_COLUMNS_PER_PASS:
		waiting.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - here).length_squared() < (b - here).length_squared())
		waiting.resize(MAX_COLUMNS_PER_PASS)

	# One column at a time, all the way through.
	#
	# These used to be merged into a single bounding rectangle and committed in
	# one go, on the reasoning that the flood fill has to see the seam between
	# two columns that arrived together. It does — but _spread is unbounded and
	# stitches them anyway on whichever column arrives second, so the merge
	# bought nothing and cost everything: two columns on opposite sides of the
	# player merge into a rectangle covering the whole town, and committing
	# that is sixty thousand cells of clearance testing inside one frame. That
	# is a visible stutter, and it fired every time the streamer delivered a
	# spread-out batch.
	# One known limit, kept deliberately.
	#
	# Reachability can run past the column that triggered it, and those cells
	# are not committed here — only the column is. The tidy fix is to commit
	# the flood's own bounding box, and it was measured: a single flood joining
	# two pockets of ground produces a rectangle the size of the town, and
	# committing it cost twenty-seven milliseconds in one frame. Widening every
	# column by a fixed margin instead cost twice the frame time for the same
	# reason at smaller scale.
	#
	# So it is left. Columns arrive next to ground that is already reachable,
	# so in practice the water only runs a few metres and the column rectangle
	# covers it. What it does not cover is ground nobody could walk to yet
	# anyway, and the next full rebuild picks that up. A stutter every time the
	# streamer delivers is a worse bug than a pocket of grass the crew declines
	# to stand on.
	var taken: Array[Rect2i] = []
	for key: Vector2i in waiting:
		_seen[key] = true
		var cells := _cells_of(Rect2i(key.x << 5, key.y << 5, 32, 32))
		_surface_pass(cells)
		taken.append(cells)
	for cells: Rect2i in taken:
		_grow_reach(cells)
	for cells: Rect2i in taken:
		_commit(Rect2i(cells.position - Vector2i(CLEARANCE, CLEARANCE),
			cells.size + Vector2i(CLEARANCE * 2, CLEARANCE * 2)))

	stat_worst_catch_ms = maxf(stat_worst_catch_ms,
		float(Time.get_ticks_usec() - t0) / 1000.0)
	return taken.size()


## Voxel rectangle to the cells it touches. Rounded outward, and floored rather
## than truncated: chunk columns are not aligned to the grid origin, so both
## ends of this land on negative numbers, where integer division rounds the
## wrong way and would leave a seam of never-read cells between two columns.
func _cells_of(rect_v: Rect2i) -> Rect2i:
	var lo := Vector2i(
		floori(float(rect_v.position.x - origin_v.x) / CELL_V),
		floori(float(rect_v.position.y - origin_v.y) / CELL_V))
	var hi := Vector2i(
		ceili(float(rect_v.end.x - origin_v.x) / CELL_V),
		ceili(float(rect_v.end.y - origin_v.y) / CELL_V))
	return Rect2i(lo, hi - lo)


func _mark_seen(rect_v: Rect2i) -> void:
	for kz in range(rect_v.position.y >> 5, ((rect_v.end.y - 1) >> 5) + 1):
		for kx in range(rect_v.position.x >> 5, ((rect_v.end.x - 1) >> 5) + 1):
			if world.has_column(kx, kz):
				_seen[Vector2i(kx, kz)] = true


## Extends reachability into ground that has just appeared.
##
## Seeded from every cell around the new region that the town can already
## reach, and then left to run wherever it likes. It looks unbounded and is
## not: a cell is only ever pushed if it was unreachable a moment ago, so the
## work is the size of what has just become walkable and nothing else.
func _grow_reach(region: Rect2i) -> void:
	var r := Rect2i(region.position - Vector2i(1, 1), region.size + Vector2i(2, 2))
	var w := size.x
	var stack: Array[int] = []
	for cy in range(maxi(r.position.y, 0), mini(r.end.y, size.y)):
		for cx in range(maxi(r.position.x, 0), mini(r.end.x, size.x)):
			var i := cx + cy * w
			if _reach[i] == 1:
				stack.push_back(i)
	_spread(stack)


## Marks a rectangle of world voxels as impassable — the footprint of a
## building that is going up, so nobody paths through the site.
func refresh_world_rect(rect_v: Rect2i, pad: int = 2) -> void:
	var p0 := (rect_v.position - origin_v) / CELL_V
	var r := Rect2i(p0 - Vector2i(pad, pad),
		rect_v.size / CELL_V + Vector2i(pad * 2, pad * 2))
	refresh(r)


# ------------------------------------------------------------ the three passes

## Reads the world and decides, cell by cell, whether a person could stand
## there — ignoring for now whether they could ever get there.
##
## Four corners rather than one centre. One sample let a cell that is half
## bakery pass as open ground, and a worker sent down that route walks into
## masonry; four cost three more lookups and catch it.
func _surface_pass(region: Rect2i) -> void:
	var y0 := maxi(region.position.y, 0)
	var y1 := mini(region.end.y, size.y)
	var x0 := maxi(region.position.x, 0)
	var x1 := mini(region.end.x, size.x)
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			var vx := origin_v.x + cx * CELL_V
			var vz := origin_v.y + cy * CELL_V
			var lo := 1 << 30
			var hi := -1
			var ok := true
			for corner in 4:
				var sx := vx + (CELL_V - 1 if (corner & 1) != 0 else 0)
				var sz := vz + (CELL_V - 1 if (corner & 2) != 0 else 0)
				var h := world.height_at(sx, sz)
				if h < 0:
					ok = false
					break
				var top := world.get_voxel(Vector3i(sx, h, sz))
				if top == VoxelTypes.WATER or top == VoxelTypes.AIR:
					ok = false
					break
				lo = mini(lo, h)
				hi = maxi(hi, h)
			var i := cx + cy * size.x
			if not ok or hi - lo > ROUGH_V:
				# Either nothing is loaded here, or the cell straddles a wall.
				heights[i] = hi
				_open[i] = 0
				continue
			heights[i] = hi
			# The first time a cell is actually read, whatever is there is the
			# ground. Only a rise measured against ground we already knew about
			# counts as somebody having built on it.
			if _base_h[i] < 0:
				_base_h[i] = hi
			# Standing room. Three probes up the column rather than nine: an
			# overhang thinner than three voxels is a lintel, and a worker
			# ducks under one of those without anybody noticing.
			var clear := true
			for dy: int in [2, 5, HEAD_V - 1]:
				if world.is_solid(Vector3i(vx + 1, hi + dy, vz + 1)):
					clear = false
					break
			_open[i] = 1 if clear else 0


## Keeps only what the town floor connects to.
##
## This is the pass that stopped the crew climbing houses. A roof is a
## perfectly good surface with headroom over it; the only thing wrong with it
## is that you cannot get there from the street, and the only way to know that
## is to try walking.
func _flood_reach() -> void:
	_reach.fill(0)
	var start := _seed_cell
	if not in_bounds(start) or _open[start.x + start.y * size.x] == 0:
		start = _nearest_open(start if in_bounds(start) else size / 2)
	if not in_bounds(start):
		# Nothing to stand on anywhere — the world has not streamed in yet.
		# Fall back to the surface pass rather than making the town an island.
		_reach = _open.duplicate()
		return

	var w := size.x
	var stack: Array[int] = [start.x + start.y * w]
	_reach[stack[0]] = 1
	_spread(stack)


## The walk itself, shared by the full flood and by the incremental growth.
## Every neighbour within a doorstep of the cell you are on, and nothing that
## is already known to be reachable.
func _spread(stack: Array[int]) -> void:
	var w := size.x
	var h := size.y
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var cx := i % w
		var cy := i / w
		var hy := heights[i]
		for dy in range(-1, 2):
			var ny := cy + dy
			if ny < 0 or ny >= h:
				continue
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				if nx < 0 or nx >= w:
					continue
				var j := nx + ny * w
				if _reach[j] == 1 or _open[j] == 0:
					continue
				if absi(heights[j] - hy) > MAX_STEP_V:
					continue
				_reach[j] = 1
				stack.push_back(j)


## Turns the three masks into the graph A* actually searches, growing every
## obstacle by one cell so a route has room for a body.
func _commit(region: Rect2i) -> void:
	var y0 := maxi(region.position.y, 0)
	var y1 := mini(region.end.y, size.y)
	var x0 := maxi(region.position.x, 0)
	var x1 := mini(region.end.x, size.x)
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			var clear := true
			for dy in range(-CLEARANCE, CLEARANCE + 1):
				for dx in range(-CLEARANCE, CLEARANCE + 1):
					if _blocked(cx + dx, cy + dy):
						clear = false
						break
				if not clear:
					break
			# Two calls into the pathfinder per cell, and on a re-commit almost
			# nothing has moved — the same cell is committed again every time a
			# neighbouring column arrives or a wall goes up nearby. Remembering
			# what was last said means the engine only hears about the cells
			# that really changed, which on a typical refresh is a handful out
			# of several hundred.
			var i := cx + cy * size.x
			var now: int = 0 if clear else 1
			if _committed[i] == now:
				continue
			_committed[i] = now
			var c := Vector2i(cx, cy)
			astar.set_point_solid(c, not clear)
			# Walkable but with a wall within arm's reach: passable, and
			# avoided while there is open street to use instead.
			astar.set_point_weight_scale(c, 1.0 if clear else 2.4)


## Blocked before clearance: off the grid, nothing to stand on, nothing that
## connects to town, or something built on it since the last rebuild.
func _blocked(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= size.x or cy >= size.y:
		return true
	var i := cx + cy * size.x
	if _open[i] == 0 or _reach[i] == 0:
		return true
	return absi(heights[i] - _base_h[i]) > MAX_STEP_V


func _nearest_open(cell: Vector2i) -> Vector2i:
	for r in range(0, maxi(size.x, size.y)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dy) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if in_bounds(c) and _open[c.x + c.y * size.x] == 1:
					return c
	return Vector2i(-1, -1)


# ------------------------------------------------------------------- queries

func to_cell(world_m: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_m.x - origin_v.x * VoxelChunk.VOXEL_M) / CELL_M),
		floori((world_m.z - origin_v.y * VoxelChunk.VOXEL_M) / CELL_M))


func to_world(cell: Vector2i) -> Vector3:
	var h := heights[clampi(cell.x, 0, size.x - 1) + clampi(cell.y, 0, size.y - 1) * size.x]
	return Vector3(
		origin_v.x * VoxelChunk.VOXEL_M + (cell.x + 0.5) * CELL_M,
		float(h + 1) * VoxelChunk.VOXEL_M,
		origin_v.y * VoxelChunk.VOXEL_M + (cell.y + 0.5) * CELL_M)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not astar.is_point_solid(cell)


func walkable_at(world_m: Vector3) -> bool:
	return is_walkable(to_cell(world_m))


## Nearest walkable cell to a target, searched outward. A worker asked to build
## on a plot stands next to it, not inside the wall.
func nearest_walkable(cell: Vector2i, max_radius: int = 16) -> Vector2i:
	if is_walkable(cell):
		return cell
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if is_walkable(c):
					return c
	return cell


## Somewhere near here that a person could actually stand — where a worker who
## has got themselves wedged is put back on their feet.
func nearest_walkable_world(world_m: Vector3, max_radius: int = 16) -> Vector3:
	var c := nearest_walkable(to_cell(world_m), max_radius)
	if not is_walkable(c):
		return world_m
	return to_world(c)


# -------------------------------------------------------------------- routing

## World-space waypoints from one position to another. Empty if unreachable.
func path(from_m: Vector3, to_m: Vector3) -> PackedVector3Array:
	var a := nearest_walkable(to_cell(from_m))
	var b := nearest_walkable(to_cell(to_m))
	var out := PackedVector3Array()
	if not is_walkable(a) or not is_walkable(b):
		return out
	var cells := astar.get_id_path(a, b)
	if cells.is_empty():
		return out
	for c: Vector2i in _straighten(cells):
		out.append(to_world(c))
	# Finish at the real target rather than at the centre of its cell — but
	# only when the real target is somewhere a person can stand. Asked to work
	# a corner of their own site, a worker is given a point that lands inside
	# the building; walking the last metre to it means walking into the wall,
	# and then it is the watchdog's problem instead of nobody's.
	if out.size() > 0 and walkable_at(to_m):
		out[out.size() - 1] = Vector3(to_m.x, out[out.size() - 1].y, to_m.z)
	return out


## Pulls the staircase out of a grid path.
##
## A* on a square grid hands back a waypoint every metre, and a worker steering
## at each of them in turn walks a zigzag that scuffs along every wall it
## passes. Dropping every waypoint you can already see past turns the same
## route into three or four long straight runs down the middle of the street,
## which is both what it should look like and far harder to catch on.
const LOOK_AHEAD := 24


func _straighten(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() < 3:
		return cells
	var out: Array[Vector2i] = [cells[0]]
	var anchor := 0
	var i := 1
	while i < cells.size() - 1:
		var visible := i + 1 - anchor <= LOOK_AHEAD \
			and _clear_line(cells[anchor], cells[i + 1])
		if not visible:
			out.append(cells[i])
			anchor = i
		i += 1
	out.append(cells[cells.size() - 1])
	return out


## Whether a straight walk from one cell to another crosses only open ground of
## roughly one height. Sampled every half cell, which cannot step over an
## obstacle a whole cell wide.
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y)) * 2
	if steps <= 0:
		return true
	var last := heights[a.x + a.y * size.x]
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var c := Vector2i(roundi(a.x + d.x * t), roundi(a.y + d.y * t))
		if not is_walkable(c):
			return false
		var h := heights[c.x + c.y * size.x]
		if absi(h - last) > MAX_STEP_V:
			return false
		last = h
	return true


## Steps too big for the path to be honest about — used to sanity-check a route
## across freshly terraced ground.
func step_ok(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return false
	return absi(heights[a.x + a.y * size.x] - heights[b.x + b.y * size.x]) <= MAX_STEP_V
