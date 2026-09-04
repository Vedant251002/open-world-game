extends RefCounted
class_name Plot
## A buildable parcel of ground.
##
## The LLM never sees a plot. The engine hands the model a prose description of
## the plot in the prompt context ("11 by 9 metres, street to the south") and
## converts whatever comes back into voxels here. This is the boundary from
## voxel-module-spec.md §0: the model emits intent, the engine emits geometry.

const V := VoxelChunk.VOXEL_M

var id: int = -1
var origin: Vector3i          ## min corner, voxel coords (y is ground level)
var size_v: Vector2i          ## footprint in voxels
var street_dir: Vector3i      ## unit vector from the plot toward its street
var street_name: String = ""
var ground_y: int = 0         ## levelled ground height in voxels
var occupied_by: int = -1     ## building id, or -1
var reserved := false         ## claimed by a worker who has not finished yet
var terrain_note: String = "level"
var neighbours: Array[int] = []


func size_m() -> Vector2:
	return Vector2(size_v) * V


func centre_m() -> Vector3:
	return Vector3(
		(origin.x + size_v.x * 0.5) * V,
		(ground_y + 1) * V,
		(origin.z + size_v.y * 0.5) * V)


func rect_v() -> Rect2i:
	return Rect2i(Vector2i(origin.x, origin.z), size_v)


func contains_v(x: int, z: int) -> bool:
	return x >= origin.x and z >= origin.z \
		and x < origin.x + size_v.x and z < origin.z + size_v.y


## Compass word for the street direction, used in prompt context and in worker
## dialogue ("street to the south").
func street_word() -> String:
	if street_dir.z < 0:
		return "north"
	if street_dir.z > 0:
		return "south"
	if street_dir.x < 0:
		return "west"
	return "east"


func describe() -> String:
	var m := size_m()
	return "%d by %d metres, %s, street to the %s" % [
		int(round(m.x)), int(round(m.y)), terrain_note, street_word()]
