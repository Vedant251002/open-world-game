extends Node3D
class_name FarTerrain
## The land beyond the streamed chunks.
##
## Voxel chunks stop about eighty metres out; without something past that the
## world ends in a cliff into the sky, which is exactly what a world with no
## edges must not look like. This is one coarse mesh sampled from the same
## height function, so the hills on the horizon are the real hills you will walk
## over half an hour later.
##
## It is deliberately not voxels. At four metres a sample it costs a few
## thousand triangles for a kilometre of landscape, and the fog hides the join.
##
## Built on a worker thread and swapped in whole. Building it on the main thread
## cost a visible hitch every time the player walked far enough to trigger a
## rebuild, and the previous mesh disappeared for a frame while the new one was
## assembled.

const INNER := 52.0        ## starts well inside the voxel radius, hidden under it
const SINK := 0.7          ## sits this far below true height, so voxels win
const OUTER := 900.0       ## visible horizon
const STEP_NEAR := 4.0     ## sample spacing close in
const RINGS := 46          ## concentric rings, spacing grows outward
const SEGMENTS := 96
const REBUILD_DIST := 56.0

var gen: WorldGen
var mesh_instance: MeshInstance3D

var _built_at := Vector2(1e9, 1e9)
var _pending := false
var _mutex := Mutex.new()
var _result: Array = []


func setup(world_gen: WorldGen) -> void:
	gen = world_gen
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_instance.material_override = _make_material()
	add_child(mesh_instance)
	set_process(true)


## Vertex-coloured land. It never has to match the voxel lighting exactly — it
## only has to read as the same landscape at distance.
func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# The palette is sRGB; without this Godot reads the vertex colours as linear
	# and the distant land comes out pale beside the voxels.
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func refresh(around: Vector3, force: bool = false) -> void:
	if _pending:
		return
	var here := Vector2(around.x, around.z)
	if not force and here.distance_to(_built_at) < REBUILD_DIST:
		return
	_pending = true
	WorkerThreadPool.add_task(_build_job.bind(here), false, "far_terrain")


## Builds and installs synchronously. Used once at boot so the horizon is never
## missing on the first frame.
func build_now(around: Vector3) -> void:
	_build_job(Vector2(around.x, around.z))
	_collect()


func _process(_delta: float) -> void:
	_collect()


func _collect() -> void:
	_mutex.lock()
	var got: Dictionary = {}
	if not _result.is_empty():
		got = _result.pop_back()
		_result.clear()
	_mutex.unlock()
	if got.is_empty():
		return

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = got["v"]
	arr[Mesh.ARRAY_NORMAL] = got["n"]
	arr[Mesh.ARRAY_COLOR] = got["c"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh_instance.mesh = mesh
	_built_at = got["at"]
	_pending = false


## A polar grid centred on the player: dense where it meets the voxels, coarse
## at the horizon. A regular square grid would spend most of its triangles in
## the corners, where nobody is looking.
##
## Runs on a worker thread — WorldGen is a pure function of position, so it can
## survey a kilometre of land while the game carries on.
func _build_job(centre: Vector2) -> void:
	var radii := PackedFloat32Array()
	var r := INNER
	var step := STEP_NEAR
	for _i in RINGS:
		radii.append(r)
		r += step
		step *= 1.115
		if r > OUTER:
			break

	var sea := float(gen.sea_voxel()) * VoxelChunk.VOXEL_M
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	for ri in range(radii.size() - 1):
		var r0: float = radii[ri]
		var r1: float = radii[ri + 1]
		var spacing := maxf(r1 - r0, 1.0)
		for si in SEGMENTS:
			var a0 := float(si) / SEGMENTS * TAU
			var a1 := float(si + 1) / SEGMENTS * TAU
			var p00 := _sample(centre, r0, a0, sea, spacing)
			var p01 := _sample(centre, r0, a1, sea, spacing)
			var p10 := _sample(centre, r1, a0, sea, spacing)
			var p11 := _sample(centre, r1, a1, sea, spacing)
			_tri(verts, norms, cols, p00, p10, p11)
			_tri(verts, norms, cols, p00, p11, p01)

	_mutex.lock()
	_result.append({"v": verts, "n": norms, "c": cols, "at": centre})
	_mutex.unlock()


## Returns [position, normal, colour]. The normal comes from the height field
## rather than from the triangles, so distant hills shade smoothly instead of
## faceting at the sample spacing.
func _sample(centre: Vector2, radius: float, angle: float, sea: float,
		spacing: float) -> Array:
	var wx := centre.x + cos(angle) * radius
	var wz := centre.y + sin(angle) * radius
	var h := _height(wx, wz)

	var e := maxf(spacing, 2.0)
	var nrm := Vector3(_height(wx - e, wz) - _height(wx + e, wz), 2.0 * e,
		_height(wx, wz - e) - _height(wx, wz + e)).normalized()

	var colour: Color
	if h <= sea:
		h = sea
		colour = VoxelTypes.albedo(VoxelTypes.WATER)
		colour.a = 1.0
		nrm = Vector3.UP
	elif h < sea + 1.6:
		colour = VoxelTypes.albedo(VoxelTypes.SAND)
	elif h > 30.0:
		colour = VoxelTypes.albedo(VoxelTypes.ROCK)
	else:
		# Grass drying toward rock with altitude, so distant hills are not one
		# flat green — but starting from the same grass the voxels use.
		var t := clampf((h - sea) / 24.0, 0.0, 1.0)
		colour = VoxelTypes.albedo(VoxelTypes.GRASS).lerp(
			VoxelTypes.albedo(VoxelTypes.ROCK), t * 0.55)
	return [Vector3(wx, h - SINK, wz), nrm, colour]


func _height(wx: float, wz: float) -> float:
	return float(gen.height_at(int(wx / VoxelChunk.VOXEL_M),
		int(wz / VoxelChunk.VOXEL_M))) * VoxelChunk.VOXEL_M


static func _tri(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, a: Array, b: Array, c: Array) -> void:
	verts.push_back(a[0]); norms.push_back(a[1]); cols.push_back(a[2])
	verts.push_back(b[0]); norms.push_back(b[1]); cols.push_back(b[2])
	verts.push_back(c[0]); norms.push_back(c[1]); cols.push_back(c[2])
