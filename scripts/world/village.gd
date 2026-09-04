extends RefCounted
class_name Village
## The town layout: streets, plaza and plots.
##
## Finite and fixed near the origin, in a world that is otherwise endless. That
## is deliberate — the game is about one town you keep returning to, and a
## procedurally endless sprawl of plots would make the map meaningless. Beyond
## the last street it is wilderness.
##
## Everything here is a pure function of position so the chunk streamer can ask
## "is this column a road?" from a worker thread without touching any state.

const V := VoxelChunk.VOXEL_M

const ROAD_PITCH := 26.0     ## distance between parallel streets, metres
const ROAD_WIDTH := 5.0
const BLOCKS := 5            ## streets each way, so BLOCKS-1 blocks of plots
const PLOT_SETBACK := 1.5
const FLOOR_HEIGHT := 12.0   ## the town sits on a levelled shelf
const APRON := 26.0          ## how far the levelling blends into wild ground

var seed_value := 0
var plots: Array[Plot] = []
var well_pos := Vector3.ZERO
var spawn_pos := Vector3.ZERO

## Street centre lines, in voxels.
var lines_x: Array[int] = []
var lines_z: Array[int] = []
var plaza_rect_v := Rect2i()
var bounds_v := Rect2i()

var _half_road := 0
var _rng := RandomNumberGenerator.new()

const STREET_WORDS := ["Well", "Mill", "Kiln", "Ash", "Long", "Low", "Church", "Back"]


func build(world_seed: int) -> void:
	seed_value = world_seed
	_rng.seed = world_seed
	_half_road = int(ROAD_WIDTH * 0.5 / V)

	var pitch := int(ROAD_PITCH / V)
	var span := pitch * (BLOCKS - 1)
	var x0 := -span / 2
	var z0 := -span / 2

	lines_x.clear()
	lines_z.clear()
	for i in BLOCKS:
		lines_x.append(x0 + i * pitch)
		lines_z.append(z0 + i * pitch)

	bounds_v = Rect2i(
		Vector2i(lines_x[0] - _half_road - 8, lines_z[0] - _half_road - 8),
		Vector2i(span + _half_road * 2 + 16, span + _half_road * 2 + 16))

	# The middle block is the plaza, so the well sits at the town's centre.
	var mid := (BLOCKS - 1) / 2
	plaza_rect_v = Rect2i(
		Vector2i(lines_x[mid] + _half_road, lines_z[mid] + _half_road),
		Vector2i(pitch - _half_road * 2, pitch - _half_road * 2))

	var wx := plaza_rect_v.position.x + plaza_rect_v.size.x / 2
	var wz := plaza_rect_v.position.y + plaza_rect_v.size.y / 2
	var floor_v := int(FLOOR_HEIGHT / V)
	well_pos = Vector3(wx * V, (floor_v + 1) * V, wz * V)
	spawn_pos = well_pos + Vector3(0.0, 0.0, 5.0)

	_cut_plots(pitch)


# ----------------------------------------------------------------- queries
# All of these are called from generation threads, once per column, so they are
# arithmetic over a handful of line positions rather than a lookup in a mask.

func is_road(vx: int, vz: int) -> bool:
	if not _in_grid(vx, vz):
		return false
	for lx: int in lines_x:
		if absi(vx - lx) <= _half_road:
			return true
	for lz: int in lines_z:
		if absi(vz - lz) <= _half_road:
			return true
	return false


func is_road_edge(vx: int, vz: int) -> bool:
	if not is_road(vx, vz):
		return false
	return not (is_road(vx + 1, vz) and is_road(vx - 1, vz)
		and is_road(vx, vz + 1) and is_road(vx, vz - 1))


func is_plaza(vx: int, vz: int) -> bool:
	return plaza_rect_v.has_point(Vector2i(vx, vz))


func is_paved(vx: int, vz: int) -> bool:
	return is_road(vx, vz) or is_plaza(vx, vz)


func _in_grid(vx: int, vz: int) -> bool:
	return vx >= lines_x[0] - _half_road and vx <= lines_x[BLOCKS - 1] + _half_road \
		and vz >= lines_z[0] - _half_road and vz <= lines_z[BLOCKS - 1] + _half_road


## 0 outside the town, 1 on the levelled shelf, blending across the apron. The
## height sampler uses this to flatten the ground under the streets without
## putting a cliff around the whole village.
func levelling(vx: int, vz: int) -> float:
	var apron := APRON / V
	var dx := maxf(float(bounds_v.position.x - vx),
		float(vx - (bounds_v.position.x + bounds_v.size.x)))
	var dz := maxf(float(bounds_v.position.y - vz),
		float(vz - (bounds_v.position.y + bounds_v.size.y)))
	var d := maxf(maxf(dx, dz), 0.0)
	if d <= 0.0:
		return 1.0
	if d >= apron:
		return 0.0
	var t := 1.0 - d / apron
	return t * t * (3.0 - 2.0 * t)


func floor_voxel() -> int:
	return int(FLOOR_HEIGHT / V)


# ------------------------------------------------------------------- plots

func _cut_plots(_pitch: int) -> void:
	plots.clear()
	var setback := int(PLOT_SETBACK / V)
	var next_id := 0

	for bi in range(BLOCKS - 1):
		for bj in range(BLOCKS - 1):
			var x0: int = lines_x[bi] + _half_road + setback
			var x1: int = lines_x[bi + 1] - _half_road - setback
			var z0: int = lines_z[bj] + _half_road + setback
			var z1: int = lines_z[bj + 1] - _half_road - setback
			if plaza_rect_v.has_point(Vector2i((x0 + x1) / 2, (z0 + z1) / 2)):
				continue

			var p := Plot.new()
			p.id = next_id
			p.origin = Vector3i(x0, 0, z0)
			p.size_v = Vector2i(x1 - x0, z1 - z0)
			p.street_dir = _frontage_dir(bi, bj)
			p.street_name = STREET_WORDS[(bi * 3 + bj * 5) % STREET_WORDS.size()] + " Row"
			p.ground_y = floor_voxel()
			p.terrain_note = "level"
			plots.append(p)
			next_id += 1

	for a in plots:
		for b in plots:
			if a.id != b.id and a.centre_m().distance_to(b.centre_m()) < 40.0:
				a.neighbours.append(b.id)


## Blocks look outward from the plaza, so the town faces its own centre.
func _frontage_dir(bi: int, bj: int) -> Vector3i:
	var mid := (BLOCKS - 2) * 0.5
	var di := float(bi) - mid
	var dj := float(bj) - mid
	if absf(di) > absf(dj):
		return Vector3i(-1, 0, 0) if di > 0.0 else Vector3i(1, 0, 0)
	if absf(dj) > 0.01:
		return Vector3i(0, 0, -1) if dj > 0.0 else Vector3i(0, 0, 1)
	return Vector3i(0, 0, -1)


func plot_at(world_m: Vector3) -> Plot:
	var v := VoxelWorld.to_voxel(world_m)
	for p in plots:
		if p.contains_v(v.x, v.z):
			return p
	return null


func plot_by_id(id: int) -> Plot:
	for p in plots:
		if p.id == id:
			return p
	return null


func nearest_free_plot(from_m: Vector3) -> Plot:
	var best: Plot = null
	var best_d := INF
	for p in plots:
		if p.occupied_by >= 0 or p.reserved:
			continue
		var d := p.centre_m().distance_to(from_m)
		if d < best_d:
			best_d = d
			best = p
	return best


## Rectangle the nav grid needs to cover: the streets plus a margin to walk on.
func nav_bounds_v(margin: int = 40) -> Rect2i:
	return Rect2i(bounds_v.position - Vector2i(margin, margin),
		bounds_v.size + Vector2i(margin * 2, margin * 2))
