extends RefCounted
class_name Props
## Tier B object voxels, per voxel-module-spec.md §1.
##
## These are entities with their own transform at 0.05 m — twenty times finer
## than the world grid — and they are never written into chunk data. That
## separation is what lets a barrel be knocked over later without inheriting
## every hard problem in voxel physics.
##
## Each prop is a short list of boxes in 0.05 m units, meshed once per type and
## reused by every instance.

const U := 0.05                     ## object voxel size, metres

## [x, y, z, w, h, d, material] in object voxels. Origin is the base centre, so
## a prop can be dropped straight onto a floor position.
const DEFS := {
	"table": [
		[-14, 14, -9, 28, 2, 18, VoxelTypes.PLANK],
		[-12, 0, -7, 3, 14, 3, VoxelTypes.DARK_OAK],
		[9, 0, -7, 3, 14, 3, VoxelTypes.DARK_OAK],
		[-12, 0, 4, 3, 14, 3, VoxelTypes.DARK_OAK],
		[9, 0, 4, 3, 14, 3, VoxelTypes.DARK_OAK],
	],
	"stool": [
		[-5, 8, -5, 10, 2, 10, VoxelTypes.PLANK],
		[-4, 0, -4, 2, 8, 2, VoxelTypes.DARK_OAK],
		[2, 0, -4, 2, 8, 2, VoxelTypes.DARK_OAK],
		[-4, 0, 2, 2, 8, 2, VoxelTypes.DARK_OAK],
		[2, 0, 2, 2, 8, 2, VoxelTypes.DARK_OAK],
	],
	"bench": [
		[-16, 8, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-15, 0, -4, 3, 8, 8, VoxelTypes.DARK_OAK],
		[12, 0, -4, 3, 8, 8, VoxelTypes.DARK_OAK],
		[-16, 10, 3, 32, 10, 2, VoxelTypes.PLANK],
	],
	"bed": [
		[-13, 4, -22, 26, 3, 44, VoxelTypes.PLANK],
		[-13, 7, -22, 26, 4, 34, VoxelTypes.THATCH],
		[-13, 7, 12, 26, 6, 8, VoxelTypes.PAINTED_WHITE],
		[-13, 0, -22, 3, 4, 3, VoxelTypes.DARK_OAK],
		[10, 0, -22, 3, 4, 3, VoxelTypes.DARK_OAK],
		[-13, 0, 19, 3, 4, 3, VoxelTypes.DARK_OAK],
		[10, 0, 19, 3, 4, 3, VoxelTypes.DARK_OAK],
		[-13, 7, -23, 26, 12, 2, VoxelTypes.DARK_OAK],
	],
	"chest": [
		[-9, 0, -6, 18, 10, 12, VoxelTypes.PLANK],
		[-9, 10, -6, 18, 4, 12, VoxelTypes.DARK_OAK],
		[-2, 5, -7, 4, 5, 1, VoxelTypes.CHROME],
	],
	"crate": [
		[-7, 0, -7, 14, 14, 14, VoxelTypes.PLANK],
		[-8, 0, -8, 16, 2, 16, VoxelTypes.DARK_OAK],
		[-8, 12, -8, 16, 2, 16, VoxelTypes.DARK_OAK],
	],
	"barrel": [
		[-6, 0, -6, 12, 18, 12, VoxelTypes.DARK_OAK],
		[-7, 3, -7, 14, 2, 14, VoxelTypes.CHROME],
		[-7, 13, -7, 14, 2, 14, VoxelTypes.CHROME],
	],
	"shelf": [
		[-16, 0, -5, 2, 40, 10, VoxelTypes.DARK_OAK],
		[14, 0, -5, 2, 40, 10, VoxelTypes.DARK_OAK],
		[-16, 10, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-16, 22, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-16, 34, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-12, 12, -3, 6, 8, 6, VoxelTypes.CLAY_TILE],
		[2, 24, -3, 6, 8, 6, VoxelTypes.SANDSTONE],
	],
	"counter_block": [
		[-22, 0, -8, 44, 18, 16, VoxelTypes.PLANK],
		[-23, 18, -9, 46, 3, 18, VoxelTypes.GRANITE],
	],
	"oven_block": [
		[-16, 0, -14, 32, 26, 28, VoxelTypes.BRICK],
		[-7, 4, -15, 14, 12, 2, VoxelTypes.MATTE_BLACK],
		[-10, 26, -10, 20, 8, 20, VoxelTypes.BRICK],
	],
	"kiln_block": [
		[-12, 0, -12, 24, 22, 24, VoxelTypes.SANDSTONE],
		[-5, 3, -13, 10, 10, 2, VoxelTypes.MATTE_BLACK],
	],
	"forge_block": [
		[-14, 0, -10, 28, 14, 20, VoxelTypes.COBBLE],
		[-9, 14, -6, 18, 3, 12, VoxelTypes.MATTE_BLACK],
		[-4, 17, -3, 8, 4, 6, VoxelTypes.PAINTED_RED],
	],
	"anvil": [
		[-5, 0, -4, 10, 8, 8, VoxelTypes.DARK_OAK],
		[-4, 8, -3, 8, 4, 6, VoxelTypes.STEEL_FRAME],
		[-8, 12, -3, 16, 5, 6, VoxelTypes.STEEL_FRAME],
	],
	"millstone": [
		[-16, 0, -16, 32, 6, 32, VoxelTypes.GRANITE],
		[-14, 6, -14, 28, 5, 28, VoxelTypes.GRANITE],
		[-2, 11, -2, 4, 16, 4, VoxelTypes.DARK_OAK],
	],
	"desk": [
		[-18, 12, -10, 36, 3, 20, VoxelTypes.PLANK],
		[-18, 0, -10, 5, 12, 20, VoxelTypes.DARK_OAK],
		[13, 0, -10, 5, 12, 20, VoxelTypes.DARK_OAK],
		[-8, 15, -5, 10, 2, 8, VoxelTypes.PAINTED_WHITE],
	],
	"rack": [
		[-14, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[11, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[-14, 14, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-14, 30, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-10, 16, -4, 8, 12, 8, VoxelTypes.MATTE_BLACK],
	],
	"tool_rack": [
		[-16, 20, -2, 32, 3, 4, VoxelTypes.DARK_OAK],
		[-12, 8, -1, 3, 12, 2, VoxelTypes.STEEL_FRAME],
		[-4, 6, -1, 3, 14, 2, VoxelTypes.STEEL_FRAME],
		[6, 9, -1, 3, 11, 2, VoxelTypes.STEEL_FRAME],
	],
	"hay": [
		[-11, 0, -11, 22, 12, 22, VoxelTypes.THATCH],
		[-8, 12, -8, 16, 6, 16, VoxelTypes.THATCH],
	],
	"trough": [
		[-16, 0, -6, 32, 3, 12, VoxelTypes.DARK_OAK],
		[-16, 3, -6, 2, 7, 12, VoxelTypes.DARK_OAK],
		[14, 3, -6, 2, 7, 12, VoxelTypes.DARK_OAK],
		[-16, 3, -6, 32, 7, 2, VoxelTypes.DARK_OAK],
		[-16, 3, 4, 32, 7, 2, VoxelTypes.DARK_OAK],
	],
	"firewood": [
		[-10, 0, -5, 20, 4, 4, VoxelTypes.BARK],
		[-10, 0, 1, 20, 4, 4, VoxelTypes.BARK],
		[-10, 4, -2, 20, 4, 4, VoxelTypes.BARK],
	],
	"bucket": [
		[-4, 0, -4, 8, 9, 8, VoxelTypes.DARK_OAK],
		[-5, 8, -5, 10, 2, 10, VoxelTypes.CHROME],
	],
	"signboard": [
		[-1, 0, -1, 2, 30, 2, VoxelTypes.DARK_OAK],
		[-12, 22, -1, 24, 12, 2, VoxelTypes.PLANK],
	],
	"pallet": [
		[-12, 0, -10, 24, 3, 20, VoxelTypes.PLANK],
		[-12, 3, -10, 24, 2, 4, VoxelTypes.DARK_OAK],
		[-12, 3, 6, 24, 2, 4, VoxelTypes.DARK_OAK],
	],
	"flour_sack": [
		[-6, 0, -5, 12, 12, 10, VoxelTypes.PAINTED_WHITE],
		[-4, 12, -3, 8, 3, 6, VoxelTypes.PAINTED_WHITE],
	],
	"peel": [
		[-1, 0, -1, 2, 26, 2, VoxelTypes.DARK_OAK],
		[-5, 26, -1, 10, 8, 2, VoxelTypes.PLANK],
	],
	"scale": [
		[-6, 0, -6, 12, 3, 12, VoxelTypes.CHROME],
		[-1, 3, -1, 2, 10, 2, VoxelTypes.CHROME],
		[-7, 13, -3, 14, 2, 6, VoxelTypes.CHROME],
	],
	"stair": [
		[-8, 0, -12, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 4, -8, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 8, -4, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 12, 0, 16, 4, 4, VoxelTypes.PLANK],
	],
	"generator_block": [
		[-14, 0, -10, 28, 20, 20, VoxelTypes.STEEL_FRAME],
		[-10, 20, -6, 20, 5, 12, VoxelTypes.MATTE_BLACK],
		[8, 20, -2, 4, 14, 4, VoxelTypes.CORRUGATED_STEEL],
	],
	"mat": [
		[-10, 0, -6, 20, 1, 12, VoxelTypes.THATCH],
	],
}

## Types that share a shape with another.
const ALIAS := {
	"signboard_text": "signboard",
	"stool_pair": "stool",
}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func exists(type_name: String) -> bool:
	return DEFS.has(type_name) or ALIAS.has(type_name)


static func resolve(type_name: String) -> String:
	return ALIAS.get(type_name, type_name)


## Object-voxel props use their own materials rather than the world shader: the
## world shader is world-space triplanar with a grain sized for 0.25 m voxels,
## which reads as mud at a twentieth of that scale.
static func material_for(mat_id: int) -> StandardMaterial3D:
	if _mat_cache.has(mat_id):
		return _mat_cache[mat_id]
	var props: Array = VoxelTypes.PROPS[mat_id]
	var m := StandardMaterial3D.new()
	m.albedo_color = props[0]
	m.roughness = float(props[1])
	m.metallic = float(props[2])
	if float(props[3]) > 0.0:
		m.emission_enabled = true
		m.emission = props[0]
		m.emission_energy_multiplier = float(props[3])
	_mat_cache[mat_id] = m
	return m


static func mesh_for(type_name: String) -> ArrayMesh:
	var key := resolve(type_name)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var boxes: Array = DEFS.get(key, DEFS["crate"])

	# One surface per material, built with SurfaceTool so normals and tangents
	# come out right without hand-rolling another mesher.
	var by_mat := {}
	for b: Array in boxes:
		var mat: int = b[6]
		if not by_mat.has(mat):
			by_mat[mat] = []
		by_mat[mat].append(b)

	var mesh := ArrayMesh.new()
	var i := 0
	for mat: int in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b: Array in by_mat[mat]:
			_add_box(st, Vector3(b[0], b[1], b[2]) * U, Vector3(b[3], b[4], b[5]) * U)
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(i, material_for(mat))
		i += 1

	_mesh_cache[key] = mesh
	return mesh


static func _add_box(st: SurfaceTool, o: Vector3, s: Vector3) -> void:
	var p := [
		o,
		o + Vector3(s.x, 0, 0),
		o + Vector3(s.x, s.y, 0),
		o + Vector3(0, s.y, 0),
		o + Vector3(0, 0, s.z),
		o + Vector3(s.x, 0, s.z),
		o + s,
		o + Vector3(0, s.y, s.z),
	]
	# Faces wound clockwise from outside, which is Godot's front-face order.
	var faces := [
		[0, 3, 2, 1],   # -Z
		[5, 6, 7, 4],   # +Z
		[4, 7, 3, 0],   # -X
		[1, 2, 6, 5],   # +X
		[3, 7, 6, 2],   # +Y
		[4, 0, 1, 5],   # -Y
	]
	for f: Array in faces:
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[1]]); st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[2]]); st.add_vertex(p[f[3]])


## Spawns one prop as a scene node. Props are entities: they carry their own
## transform and never touch chunk data.
static func spawn(type_name: String, pos: Vector3, yaw: float, parent: Node) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(type_name)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi
