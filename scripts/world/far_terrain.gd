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

const INNER := 52.0        ## starts well inside the voxel radius, hidden under it
const SINK := 0.7          ## sits this far below true height, so voxels win
const OUTER := 900.0       ## visible horizon
const STEP_NEAR := 4.0     ## sample spacing close in
const RINGS := 46          ## concentric rings, spacing grows outward

var gen: WorldGen
var mesh_instance: MeshInstance3D
var _built_at := Vector2(1e9, 1e9)
var _rebuild_dist := 64.0


func setup(world_gen: WorldGen) -> void:
	gen = world_gen
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_instance.material_override = _make_material()
	add_child(mesh_instance)


## Vertex-coloured, unshaded-ish land. It never needs to match the voxel
## lighting exactly — it only has to read as the same landscape at distance.
func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# The palette is sRGB; without this Godot reads the vertex colours as linear
	# and the distant land comes out pale and washed compared to the voxels.
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func refresh(around: Vector3, force: bool = false) -> void:
	var here := Vector2(around.x, around.z)
	if not force and here.distance_to(_built_at) < _rebuild_dist:
		return
	_built_at = here
	_build(here)


## A polar grid centred on the player: dense where it meets the voxels, coarse
## at the horizon. A regular square grid would spend most of its triangles in
## the corners, where nobody is looking.
func _build(centre: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 96
	var radii: PackedFloat32Array = PackedFloat32Array()
	var r := INNER
	var step := STEP_NEAR
	for i in RINGS:
		radii.append(r)
		r += step
		step *= 1.115                      # geometric growth out to the horizon
		if r > OUTER:
			break

	var sea := gen.sea_voxel() * VoxelChunk.VOXEL_M

	for ri in range(radii.size() - 1):
		var r0: float = radii[ri]
		var r1: float = radii[ri + 1]
		for si in segments:
			var a0 := float(si) / segments * TAU
			var a1 := float(si + 1) / segments * TAU
			var p00 := _sample(centre, r0, a0, sea)
			var p01 := _sample(centre, r0, a1, sea)
			var p10 := _sample(centre, r1, a0, sea)
			var p11 := _sample(centre, r1, a1, sea)
			_tri(st, p00, p10, p11)
			_tri(st, p00, p11, p01)

	st.generate_normals()
	mesh_instance.mesh = st.commit()
	# Keep it centred on the player so the horizon never runs out.
	mesh_instance.position = Vector3.ZERO


func _sample(centre: Vector2, radius: float, angle: float, sea: float) -> Array:
	var wx := centre.x + cos(angle) * radius
	var wz := centre.y + sin(angle) * radius
	var h := gen.height_at(int(wx / VoxelChunk.VOXEL_M),
		int(wz / VoxelChunk.VOXEL_M)) * VoxelChunk.VOXEL_M

	var colour: Color
	if h <= sea:
		h = sea
		colour = VoxelTypes.albedo(VoxelTypes.WATER)
		colour.a = 1.0
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
	return [Vector3(wx, h - SINK, wz), colour]


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	st.set_color(a[1]); st.add_vertex(a[0])
	st.set_color(b[1]); st.add_vertex(b[0])
	st.set_color(c[1]); st.add_vertex(c[0])
