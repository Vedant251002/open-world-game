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
## Cells are 1 m (four voxels). Finer than that buys nothing: a worker is seven
## voxels wide and the streets are five metres.

const CELL_V := 4                   ## voxels per nav cell
const CELL_M := CELL_V * VoxelChunk.VOXEL_M
const MAX_STEP_V := 3               ## 0.75 m — a worker can manage a doorstep

var world: VoxelWorld
var size: Vector2i
var origin_v := Vector2i.ZERO        ## voxel coords of nav cell (0,0)
var astar := AStarGrid2D.new()
var heights: PackedInt32Array        ## surface voxel y per nav cell


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

	heights = PackedInt32Array()
	heights.resize(size.x * size.y)
	refresh(Rect2i(Vector2i.ZERO, size))


## Recomputes walkability over a region of nav cells. Called with a small rect
## when a building goes up, so the cost is proportional to the change.
func refresh(region: Rect2i) -> void:
	for cy in range(maxi(region.position.y, 0), mini(region.end.y, size.y)):
		for cx in range(maxi(region.position.x, 0), mini(region.end.x, size.x)):
			var vx := origin_v.x + cx * CELL_V + CELL_V / 2
			var vz := origin_v.y + cy * CELL_V + CELL_V / 2
			var h := world.height_at(vx, vz)
			heights[cx + cy * size.x] = h

			var solid := false
			if h < 0:
				solid = true
			else:
				var top := world.get_voxel(Vector3i(vx, h, vz))
				if top == VoxelTypes.WATER or top == VoxelTypes.AIR:
					solid = true
				else:
					# Needs standing room: a worker is 28 voxels tall.
					for dy in range(1, 8):
						if world.is_solid(Vector3i(vx, h + dy, vz)):
							solid = true
							break
			astar.set_point_solid(Vector2i(cx, cy), solid)


## Marks a rectangle of world voxels as impassable — the footprint of a
## building that is going up, so nobody paths through the site.
func refresh_world_rect(rect_v: Rect2i, pad: int = 2) -> void:
	var p0 := (rect_v.position - origin_v) / CELL_V
	var r := Rect2i(p0 - Vector2i(pad, pad),
		rect_v.size / CELL_V + Vector2i(pad * 2, pad * 2))
	refresh(r)


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


## Nearest walkable cell to a target, searched outward. A worker asked to build
## on a plot stands next to it, not inside the wall.
func nearest_walkable(cell: Vector2i, max_radius: int = 12) -> Vector2i:
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


## World-space waypoints from one position to another. Empty if unreachable.
func path(from_m: Vector3, to_m: Vector3) -> PackedVector3Array:
	var a := nearest_walkable(to_cell(from_m))
	var b := nearest_walkable(to_cell(to_m))
	var out := PackedVector3Array()
	if not is_walkable(a) or not is_walkable(b):
		return out
	var cells := astar.get_id_path(a, b)
	for c: Vector2i in cells:
		out.append(to_world(c))
	# Finish at the real target rather than the centre of its cell.
	if out.size() > 0:
		out[out.size() - 1] = Vector3(to_m.x, out[out.size() - 1].y, to_m.z)
	return out


## Steps too big for the path to be honest about — used to sanity-check a route
## across freshly terraced ground.
func step_ok(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return false
	return absi(heights[a.x + a.y * size.x] - heights[b.x + b.y * size.x]) <= MAX_STEP_V
