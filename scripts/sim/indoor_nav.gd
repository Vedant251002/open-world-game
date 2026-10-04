extends RefCounted
class_name IndoorNav
## Walking about inside one building.
##
## The town's NavGrid works off the top of the world at a metre a cell, which
## is exactly right for streets and exactly wrong indoors: the top of the world
## over a kitchen is its roof, and a metre cell grown by a metre of clearance
## does not fit through a door. So each building gets its own small grid, a
## voxel (quarter metre) a cell over its ground floor and the step outside its
## front door, built once from the building's own patch:
##
##   - floor you can stand on, with headroom over it, is open;
##   - walls are solid, and the cells against them too, so a body does not
##     scrape the plaster — a doorway is six voxels and keeps four;
##   - every solid piece of furniture blocks its own footprint and a voxel
##     round it, so a path goes round the table, not through it.
##
## Somebody going home walks the town to the step outside their door, steps
## onto this grid, and is routed through the house to wherever they are going
## — the bed, the fire, the counter. Cached per building; rebuilt only if a
## building is put up again.

const V := VoxelChunk.VOXEL_M
const HEAD := 7                      ## voxels of headroom wanted over a floor cell

static var _cache: Dictionary = {}   ## patch instance id -> IndoorNav

var patch: VoxelPatch
var base := 0                        ## the ground floor slab, patch-local y
var astar := AStarGrid2D.new()
var exit_cell := Vector2i(-1, -1)    ## on the step outside the front door
var inside_cell := Vector2i(-1, -1)  ## just in from it
var _rooms: Array[Vector2i] = []     ## open cells inside the walls, to potter to


static func of(p: VoxelPatch) -> IndoorNav:
	if p == null:
		return null
	var id := p.get_instance_id()
	if _cache.has(id):
		return _cache[id]
	var n := IndoorNav.new()
	n._build(p)
	_cache[id] = n
	return n


func _build(p: VoxelPatch) -> void:
	patch = p
	base = BuildingGenerator.FOUNDATION_D
	var sx := p.size.x
	var sz := p.size.z
	astar.region = Rect2i(0, 0, sx, sz)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	# A flat patch (a field, a yard) has no ground floor to walk about on;
	# leave it unusable rather than read past the end of its bytes.
	if base >= p.size.y or p.data.size() < sx * sz * p.size.y:
		return
	# Open floor first, read straight off the patch's bytes: a call per voxel
	# was most of the cost of building one of these. A cell is open with floor
	# under it and nothing written in its headroom.
	var data := p.data
	var layer := sx * sz
	var air := VoxelTypes.AIR
	var untouched := VoxelPatch.UNTOUCHED
	var top := mini(base + HEAD, p.size.y - 1)
	var open := PackedByteArray()
	open.resize(layer)
	for i in layer:
		var f := data[i + base * layer]
		if f == air or f == untouched:
			continue
		var ok := 1
		var k := i + (base + 1) * layer
		for _y in range(base + 1, top + 1):
			var v := data[k]
			if v != air and v != untouched:
				ok = 0
				break
			k += layer
		open[i] = ok
	# Furniture: each solid piece blocks its footprint.
	for pr: Dictionary in p.props:
		var t := str(pr.get("type", ""))
		if Props.solid_box(t).is_empty():
			continue
		var r := _footprint(pr)
		for z2 in range(maxi(int(floor(r.position.y)), 0), mini(int(ceil(r.end.y)), sz)):
			for x2 in range(maxi(int(floor(r.position.x)), 0), mini(int(ceil(r.end.x)), sx)):
				open[x2 + z2 * sx] = 0
	# A body's width: closed if anything within a voxel is closed. Two sweeps
	# (along x, then along z) do the 3x3 neighbourhood in a third of the work.
	var row := PackedByteArray()
	row.resize(layer)
	for z in sz:
		var o := z * sx
		for x in sx:
			var c := open[o + x]
			if c == 1 and (x == 0 or x == sx - 1 or open[o + x - 1] == 0 or open[o + x + 1] == 0):
				c = 0
			row[o + x] = c
	var fp := p.footprint
	for z3 in sz:
		for x3 in sx:
			var i3 := x3 + z3 * sx
			var ok3 := row[i3] == 1 and z3 > 0 and z3 < sz - 1 				and row[i3 - sx] == 1 and row[i3 + sx] == 1
			if not ok3:
				astar.set_point_solid(Vector2i(x3, z3), true)
			elif fp.has_point(Vector2i(p.origin.x + x3, p.origin.z + z3)):
				_rooms.append(Vector2i(x3, z3))
	if not p.doors.is_empty():
		var d := p.doors[0] - p.origin
		var fr := Vector2i(p.front.x, p.front.z)
		exit_cell = _nearest_open(Vector2i(d.x, d.z) + fr * 3)
		inside_cell = _nearest_open(Vector2i(d.x, d.z) - fr * 4)


## A prop's rectangle in patch-local voxels, a voxel bigger all round.
func _footprint(pr: Dictionary) -> Rect2:
	var e := Props.extent(str(pr["type"]))
	var yaw := float(pr.get("yaw", 0.0))
	var pos: Vector3 = pr["pos"]
	var cx := pos.x / V - patch.origin.x
	var cz := pos.z / V - patch.origin.z
	var lo := Vector2(INF, INF)
	var hi := -lo
	for ex: float in [float(e[0]), float(e[2])]:
		for ez: float in [float(e[1]), float(e[3])]:
			var wx := ex * cos(yaw) + ez * sin(yaw)
			var wz := -ex * sin(yaw) + ez * cos(yaw)
			var q := Vector2(cx + wx / V, cz + wz / V)
			lo = lo.min(q)
			hi = hi.max(q)
	return Rect2(lo, hi - lo).grow(0.6)


func _nearest_open(c: Vector2i) -> Vector2i:
	for r in range(0, 10):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(floori(world.x / V) - patch.origin.x, floori(world.z / V) - patch.origin.z)


func world_of(c: Vector2i) -> Vector3:
	return Vector3((patch.origin.x + c.x + 0.5) * V, (patch.origin.y + base + 1) * V,
		(patch.origin.z + c.y + 0.5) * V)


func usable() -> bool:
	return exit_cell.x >= 0 and inside_cell.x >= 0 and not _rooms.is_empty()


func exit_point() -> Vector3:
	return world_of(exit_cell)


func inside_point() -> Vector3:
	return world_of(inside_cell)


## Somewhere open inside the walls, for pottering about.
func random_spot() -> Vector3:
	if _rooms.is_empty():
		return inside_point()
	return world_of(_rooms[randi() % _rooms.size()])


## Waypoints from one point to another, both snapped to open floor; corners
## only, since a voxel-by-voxel path is a staircase. Empty if there is no way.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := _nearest_open(cell_of(from))
	var b := _nearest_open(cell_of(to))
	if a.x < 0 or b.x < 0:
		return out
	var cells := astar.get_id_path(a, b)
	if cells.is_empty():
		return out
	var keep: Array[Vector2i] = [cells[0]]
	for i in range(1, cells.size()):
		if i == cells.size() - 1 or not _clear(keep[keep.size() - 1], cells[i + 1]):
			keep.append(cells[i])
	for c: Vector2i in keep:
		out.append(world_of(c))
	return out


## A straight walk between two cells crosses only open floor.
func _clear(a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if n == 0:
		return true
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		var q := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if astar.is_point_solid(q):
			return false
	return true


func contains(world: Vector3) -> bool:
	var c := cell_of(world)
	return patch.footprint.has_point(Vector2i(patch.origin.x + c.x, patch.origin.z + c.y))
