extends RefCounted
class_name VoxelPatch
## The generator's output: a dense box of voxel writes plus everything the game
## needs to know about what was built.
##
## A patch is never applied all at once. The worker walks to the plot and lays
## it down over in-game hours in build_order, which is what makes DISCOVER a
## real beat instead of a progress bar.

const UNTOUCHED := 255

var origin: Vector3i                  ## min corner in world voxel coords
var size: Vector3i
var data: PackedByteArray             ## size.x*size.y*size.z, UNTOUCHED = no change

var props: Array[Dictionary] = []     ## {type, pos (world m), yaw, module}
var modules: Array[Dictionary] = []   ## {type, rect (Rect2i, world voxels), story, priority}
var doors: Array[Vector3i] = []       ## world voxel coords of doorway floor cells
var interior_cells: Array[Rect2i] = []
var entrance_cell: Rect2i = Rect2i()
var footprint: Rect2i = Rect2i()      ## ground the building claims, world voxels
var front: Vector3i = Vector3i(0, 0, -1)
var plot_id: int = -1
var sign_text: String = ""
var archetype: String = ""
var cost: Dictionary = {}             ## material name -> voxel count
var dropped_modules: Array[String] = []
var build_order: PackedInt32Array = PackedInt32Array()
var touched := 0


func _init(box_origin: Vector3i, box_size: Vector3i) -> void:
	origin = box_origin
	size = box_size
	data = PackedByteArray()
	data.resize(size.x * size.y * size.z)
	data.fill(UNTOUCHED)


func index(x: int, y: int, z: int) -> int:
	return x + z * size.x + y * size.x * size.z


func inside(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func put(x: int, y: int, z: int, mat: int) -> void:
	if not inside(x, y, z):
		return
	var i := index(x, y, z)
	if data[i] == UNTOUCHED:
		touched += 1
	data[i] = mat


func peek(x: int, y: int, z: int) -> int:
	if not inside(x, y, z):
		return UNTOUCHED
	return data[index(x, y, z)]


## Blocks passage: any written, non-air voxel. Glass is transparent but it is
## still a wall — it keeps the weather out and you cannot walk through it — so
## enclosure, reachability and prop clearance all use this, not opacity.
func solid_at(x: int, y: int, z: int) -> bool:
	var v := peek(x, y, z)
	return v != UNTOUCHED and v != VoxelTypes.AIR


## Blocks sight as well as passage. Used only where transparency matters.
func opaque_at(x: int, y: int, z: int) -> bool:
	var v := peek(x, y, z)
	if v == UNTOUCHED or v == VoxelTypes.AIR:
		return false
	return not VoxelTypes.is_transparent(v)


func fill_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, mat: int) -> void:
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				put(x, y, z, mat)


func world_of(i: int) -> Vector3i:
	var y := i / (size.x * size.z)
	var rem := i % (size.x * size.z)
	return origin + Vector3i(rem % size.x, y, rem / size.x)


func local_to_world(x: int, y: int, z: int) -> Vector3i:
	return origin + Vector3i(x, y, z)


## Orders the writes so construction reads as a building going up: foundations
## and floors first, then each course of wall, then the roof. Within a layer,
## sorted by distance from the entrance so it grows outward from the door.
func compute_build_order() -> void:
	var anchor := Vector2(size.x * 0.5, size.z * 0.5)
	if not doors.is_empty():
		var d := doors[0] - origin
		anchor = Vector2(d.x, d.z)

	# Sort key and array index are packed into one 64-bit integer so the sort
	# runs in engine code. A custom comparator over this many entries costs
	# most of a second in GDScript.
	var keys := PackedInt64Array()
	var layer := size.x * size.z
	for i in data.size():
		if data[i] == UNTOUCHED:
			continue
		var y := i / layer
		var rem := i % layer
		var d2 := int(Vector2(rem % size.x, rem / size.x).distance_squared_to(anchor))
		keys.append(((y * 65536 + mini(d2, 65535)) << 22) | i)
	keys.sort()

	build_order = PackedInt32Array()
	build_order.resize(keys.size())
	for k in keys.size():
		build_order[k] = int(keys[k] & 0x3FFFFF)


func compute_cost() -> void:
	cost.clear()
	var counts := {}
	for i in data.size():
		var m := data[i]
		if m == UNTOUCHED or m == VoxelTypes.AIR:
			continue
		counts[m] = counts.get(m, 0) + 1
	for m: int in counts:
		for name: String in VoxelTypes.NAMES:
			if VoxelTypes.NAMES[name] == m:
				cost[name] = counts[m]
				break


## Total resource units, used by the economy and by demolition refunds.
func total_cost_units() -> int:
	var n := 0
	for mat_name: String in cost:
		n += int(cost[mat_name]) * VoxelTypes.cost(VoxelTypes.id_of(mat_name))
	return n
