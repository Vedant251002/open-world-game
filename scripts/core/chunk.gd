extends RefCounted
class_name VoxelChunk
## One 32x32x32 block of Tier A world voxels (voxel-module-spec.md §1).
##
## In memory the chunk is a dense PackedByteArray, because the greedy mesher
## reads it several hundred thousand times per remesh and anything cleverer is
## slower. On disk it is palette + RLE, which is what the spec asks for and
## costs a few hundred bytes for a typical chunk.

const SIZE := 32
const SIZE2 := SIZE * SIZE
const VOLUME := SIZE * SIZE * SIZE
const VOXEL_M := 0.25          ## metres per voxel
const SPAN_M := SIZE * VOXEL_M ## 8 m per chunk axis

var cpos: Vector3i                ## chunk coordinate
var voxels: PackedByteArray       ## VOLUME bytes, material ids
var solid_count := 0
var dirty := true
## True once anything outside worldgen has written to this chunk. The streamer
## keeps modified chunks when a column unloads and regenerates the rest.
var modified := false


func _init(chunk_pos: Vector3i = Vector3i.ZERO) -> void:
	cpos = chunk_pos
	voxels = PackedByteArray()
	voxels.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return x + z * SIZE + y * SIZE2


func get_voxel(x: int, y: int, z: int) -> int:
	return voxels[x + z * SIZE + y * SIZE2]


func set_voxel(x: int, y: int, z: int, id: int) -> void:
	var i := x + z * SIZE + y * SIZE2
	var prev := voxels[i]
	if prev == id:
		return
	if prev == VoxelTypes.AIR and id != VoxelTypes.AIR:
		solid_count += 1
	elif prev != VoxelTypes.AIR and id == VoxelTypes.AIR:
		solid_count -= 1
	voxels[i] = id
	dirty = true


func is_empty() -> bool:
	return solid_count == 0


func fill(id: int) -> void:
	voxels.fill(id)
	solid_count = VOLUME if id != VoxelTypes.AIR else 0
	dirty = true


func recount() -> void:
	var n := 0
	for i in VOLUME:
		if voxels[i] != VoxelTypes.AIR:
			n += 1
	solid_count = n


# ---------------------------------------------------------------- persistence

## Palette + run-length encoding. Format:
##   u16 palette_len, palette_len x u8 material ids,
##   u16 run_count, run_count x (u16 length, u8 palette_index)
func serialize() -> PackedByteArray:
	var palette: PackedByteArray = PackedByteArray()
	var lookup := {}
	for i in VOLUME:
		var v := voxels[i]
		if not lookup.has(v):
			lookup[v] = palette.size()
			palette.append(v)

	var runs := PackedByteArray()
	var run_count := 0
	var i2 := 0
	while i2 < VOLUME:
		var v2 := voxels[i2]
		var run_len := 1
		while i2 + run_len < VOLUME and voxels[i2 + run_len] == v2 and run_len < 65535:
			run_len += 1
		runs.append(run_len & 0xFF)
		runs.append((run_len >> 8) & 0xFF)
		runs.append(lookup[v2])
		run_count += 1
		i2 += run_len

	var out := PackedByteArray()
	out.append(palette.size() & 0xFF)
	out.append((palette.size() >> 8) & 0xFF)
	out.append_array(palette)
	out.append(run_count & 0xFF)
	out.append((run_count >> 8) & 0xFF)
	out.append_array(runs)
	return out


func deserialize(data: PackedByteArray) -> bool:
	if data.size() < 4:
		return false
	var p := 0
	var pal_len := data[0] | (data[1] << 8)
	p = 2
	if data.size() < p + pal_len + 2:
		return false
	var palette := data.slice(p, p + pal_len)
	p += pal_len
	var run_count := data[p] | (data[p + 1] << 8)
	p += 2
	if data.size() < p + run_count * 3:
		return false

	var out := 0
	var solids := 0
	for _r in run_count:
		var run_len := data[p] | (data[p + 1] << 8)
		var mat := palette[data[p + 2]]
		p += 3
		for _k in run_len:
			if out >= VOLUME:
				break
			voxels[out] = mat
			if mat != VoxelTypes.AIR:
				solids += 1
			out += 1
	solid_count = solids
	dirty = true
	return out == VOLUME
