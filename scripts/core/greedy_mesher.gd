extends RefCounted
class_name GreedyMesher
## Greedy meshing for one 32³ chunk, per voxel-module-spec.md §1.
##
## Pure and thread-safe: it takes a padded 34³ byte array (the chunk plus a
## one-voxel skin of its neighbours, so faces on the chunk seam are culled
## correctly) and returns plain arrays. It never touches the scene tree.
##
## Ambient occlusion is baked per vertex and folded into the merge key, so two
## quads only merge when their material AND their corner shading agree. That
## costs a few extra quads and buys the contact shading that makes voxel
## geometry read as solid rather than as flat coloured paper.
##
## The mask scan visits 6 x 32 x 1024 cells whatever the chunk contains, so it
## is written as flat integer index arithmetic with no Vector3i access and no
## function calls in the inner loop. In GDScript that is the difference between
## roughly 600 ms and roughly 50 ms per chunk.

const S := 32
const PAD := 34
const PAD2 := PAD * PAD
const VOXEL_M := 0.25

## Padded-array strides for x, y, z.
const STRIDE := [1, PAD2, PAD]
## Index of local voxel (0,0,0) inside the padded array.
const ORIGIN := 1 + PAD + PAD2

## Face directions: +X -X +Y -Y +Z -Z
const DIRS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Vertex AO darkening, from 0 (fully occluded corner) to 3 (open).
const AO_LEVELS := [0.40, 0.60, 0.81, 1.0]


static func padded_index(x: int, y: int, z: int) -> int:
	return (x + 1) + (z + 1) * PAD + (y + 1) * PAD2


## Opacity lookup, indexed by material id. Built once and handed to every job.
static func opacity_table() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(VoxelTypes.COUNT)
	for i in VoxelTypes.COUNT:
		t[i] = 1 if (VoxelTypes.is_solid(i) and not VoxelTypes.is_transparent(i)) else 0
	return t


## Returns:
##   {
##     "surfaces":  { material_id: Mesh.ARRAY_MAX-sized Array },
##     "collision": PackedVector3Array (triangle soup),
##     "quads":     int
##   }
static func mesh(padded: PackedByteArray, opaque: PackedByteArray) -> Dictionary:
	var acc := {}                 # material id -> {v, n, c, i}, all Arrays
	var collision: Array = []
	var quad_total := 0

	var mask := PackedInt32Array()
	mask.resize(S * S)

	for d in 6:
		var q: Vector3i = DIRS[d]
		var axis := 0
		if q.y != 0:
			axis = 1
		elif q.z != 0:
			axis = 2
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3

		var sa: int = STRIDE[axis]
		var su: int = STRIDE[u]
		var sv: int = STRIDE[v]
		var positive := q[axis] > 0
		var sq := sa if positive else -sa

		var du := Vector3i.ZERO
		var dv := Vector3i.ZERO
		du[u] = 1
		dv[v] = 1

		for slice in S:
			var slice_base := ORIGIN + slice * sa
			var any := false

			for j in S:
				var idx := slice_base + j * sv
				var mrow := j * S
				for i in S:
					var here := padded[idx]
					if here == 0:
						mask[mrow + i] = 0
						idx += su
						continue
					var nidx := idx + sq
					var there := padded[nidx]
					if opaque[there] == 1 or there == here:
						mask[mrow + i] = 0
						idx += su
						continue

					# Eight neighbours of the empty cell in front of this face,
					# in the face plane. Classic voxel vertex AO.
					var o_mu := opaque[padded[nidx - su]]
					var o_pu := opaque[padded[nidx + su]]
					var o_mv := opaque[padded[nidx - sv]]
					var o_pv := opaque[padded[nidx + sv]]
					var o_mm := opaque[padded[nidx - su - sv]]
					var o_pm := opaque[padded[nidx + su - sv]]
					var o_pp := opaque[padded[nidx + su + sv]]
					var o_mp := opaque[padded[nidx - su + sv]]

					var a00 := 0 if (o_mu == 1 and o_mv == 1) else 3 - (o_mu + o_mv + o_mm)
					var a10 := 0 if (o_pu == 1 and o_mv == 1) else 3 - (o_pu + o_mv + o_pm)
					var a11 := 0 if (o_pu == 1 and o_pv == 1) else 3 - (o_pu + o_pv + o_pp)
					var a01 := 0 if (o_mu == 1 and o_pv == 1) else 3 - (o_mu + o_pv + o_mp)

					mask[mrow + i] = here | (a00 << 8) | (a10 << 10) | (a11 << 12) | (a01 << 14)
					any = true
					idx += su

			if not any:
				continue

			for j2 in S:
				var i2 := 0
				while i2 < S:
					var key := mask[j2 * S + i2]
					if key == 0:
						i2 += 1
						continue

					var w := 1
					while i2 + w < S and mask[j2 * S + i2 + w] == key:
						w += 1

					var h := 1
					var grow := true
					while j2 + h < S and grow:
						for k in w:
							if mask[(j2 + h) * S + i2 + k] != key:
								grow = false
								break
						if grow:
							h += 1

					for jj in h:
						var mrow2 := (j2 + jj) * S + i2
						for ii in w:
							mask[mrow2 + ii] = 0

					_emit(acc, collision, key, axis, slice, i2, j2, w, h,
						q, du, dv, positive)
					quad_total += 1
					i2 += w

	var out := {}
	for mat: int in acc:
		var s: Dictionary = acc[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(s["v"])
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(s["n"])
		arr[Mesh.ARRAY_COLOR] = PackedColorArray(s["c"])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array(s["i"])
		out[mat] = arr

	return {
		"surfaces": out,
		"collision": PackedVector3Array(collision),
		"quads": quad_total,
	}


static func _emit(acc: Dictionary, collision: Array, key: int,
		axis: int, slice: int, i0: int, j0: int, w: int, h: int,
		q: Vector3i, du: Vector3i, dv: Vector3i, positive: bool) -> void:
	var mat := key & 0xFF
	var a00: float = AO_LEVELS[(key >> 8) & 3]
	var a10: float = AO_LEVELS[(key >> 10) & 3]
	var a11: float = AO_LEVELS[(key >> 12) & 3]
	var a01: float = AO_LEVELS[(key >> 14) & 3]

	# Positive faces sit one voxel further along the axis than the voxel they
	# belong to; negative faces sit on the voxel's own low boundary.
	var base := du * i0 + dv * j0
	base[axis] = slice + (1 if positive else 0)

	var uw := du * w
	var vh := dv * h

	var p0 := Vector3(base) * VOXEL_M
	var p1 := Vector3(base + uw) * VOXEL_M
	var p2 := Vector3(base + uw + vh) * VOXEL_M
	var p3 := Vector3(base + vh) * VOXEL_M
	var nrm := Vector3(q)

	if not acc.has(mat):
		acc[mat] = {"v": [], "n": [], "c": [], "i": []}
	var s: Dictionary = acc[mat]
	var verts: Array = s["v"]
	var norms: Array = s["n"]
	var cols: Array = s["c"]
	var idx: Array = s["i"]

	var vi := verts.size()
	verts.push_back(p0); verts.push_back(p1); verts.push_back(p2); verts.push_back(p3)
	norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm)
	cols.push_back(Color(a00, a00, a00, 1.0))
	cols.push_back(Color(a10, a10, a10, 1.0))
	cols.push_back(Color(a11, a11, a11, 1.0))
	cols.push_back(Color(a01, a01, a01, 1.0))

	# (du, dv, q) is right-handed for every axis, so p0->p1->p2 is CCW seen from
	# the +axis side. Godot treats clockwise as front-facing, hence the flip.
	# Split along the darker diagonal, otherwise the AO gradient creases wrongly.
	var tris: Array
	if (a00 + a11) > (a10 + a01):
		tris = [[1, 2, 3], [1, 3, 0]]
	else:
		tris = [[0, 1, 2], [0, 2, 3]]

	for t: Array in tris:
		var b: int = t[0]
		var c: int = t[2] if positive else t[1]
		var e: int = t[1] if positive else t[2]
		idx.push_back(vi + b); idx.push_back(vi + c); idx.push_back(vi + e)
		collision.push_back(verts[vi + b])
		collision.push_back(verts[vi + c])
		collision.push_back(verts[vi + e])
