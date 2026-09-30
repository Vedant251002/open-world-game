extends RefCounted
class_name BoxKit
## Shared boxes and paint for everything built out of little cubes.
##
## The workers and the animals are modelled as twenty-odd axis-aligned boxes
## each, which is the right way to draw them: it costs no artist, it matches the
## voxel world they stand in, and the parts have to move independently anyway.
##
## What was wrong was that every one of those boxes made its own BoxMesh and its
## own StandardMaterial3D. Three workers and fourteen animals is about a hundred
## and seventy unique materials and a hundred and seventy unique meshes for what
## is really a dozen sizes in a dozen colours — and a renderer can do nothing
## with that. Nothing batches, every box is a state change, and the count is
## multiplied again by the shadow pass. It was around six hundred draw calls a
## frame for seventeen small figures.
##
## Both are cached here instead, keyed by the only things that distinguish them.
## The models are unchanged; there are simply far fewer distinct resources, so
## identical parts on different bodies draw together and the shadow pass stops
## re-binding a new material for every finger-sized cube.

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

## The weave shader, loaded once. See paint() for why the figures do not use
## the world's PBR texture arrays.
const _PAINT_SHADER := preload("res://scripts/core/figure_paint.gdshader")


## A box of this size. Sizes repeat constantly — every hen has the same legs —
## so the key is the size in millimetres, which is finer than anything modelled
## here and avoids comparing floats.
static func mesh(size: Vector3) -> BoxMesh:
	var key := Vector3i(roundi(size.x * 1000.0), roundi(size.y * 1000.0),
		roundi(size.z * 1000.0))
	var m: BoxMesh = _meshes.get(key)
	if m == null:
		m = BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return m


## Matte paint in this colour, with a woven surface.
##
## These are the workers, the animals, the carts — every figure in the game,
## and they were the last thing in the world still completely flat: a single
## albedo colour with no normal map, no roughness variation and no texture of
## any kind. A flock of hens at 0.1 m each read as painted plastic next to a
## wall that had thatch grain in it.
##
## They cannot use the world's PBR texture arrays, because they are not
## surface materials — a hen's flank is wool and a worker's coat is cloth, and
## neither of those is one of the 41 world materials. What they get instead is
## a fine procedural weave derived from world position, which is enough to
## break the specular highlight up and stop a limb reading as a solid block.
## The cache is keyed on colour exactly as before, because the whole point of
## this file is that a hundred boxes share a dozen materials.
static func paint(colour: Color) -> ShaderMaterial:
	var key := colour.to_rgba32()
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _PAINT_SHADER
		var lin := colour.srgb_to_linear()
		m.set_shader_parameter("paint_albedo", Vector3(lin.r, lin.g, lin.b))
		m.set_shader_parameter("paint_rough", 0.88)
		_materials[key] = m
	return m


## One box, parented and positioned by its corner rather than its centre, which
## is how a model made of stacked cubes is easiest to write down.
static func add(parent: Node3D, origin: Vector3, size: Vector3,
		colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(size)
	mi.material_override = paint(colour)
	mi.position = origin + size * 0.5
	parent.add_child(mi)
	return mi


## The vertex-painted material every Batch shares. One resource for every
## figure in the game, so the whole cast draws with a single state.
static var _batch_material: ShaderMaterial


static func batch_material() -> ShaderMaterial:
	if _batch_material == null:
		_batch_material = ShaderMaterial.new()
		_batch_material.shader = _PAINT_SHADER
		_batch_material.set_shader_parameter("vertex_paint", true)
		_batch_material.set_shader_parameter("paint_albedo", Vector3(1.0, 1.0, 1.0))
	return _batch_material


## Boxes gathered per parent node and baked into one mesh each.
##
## A villager drawn box by box is seventy MeshInstance3Ds, and twenty of them
## on screen is fourteen hundred draw calls in the colour pass and again in the
## shadow pass. Here every box still says which limb it belongs to, but the
## boxes of one limb are welded into a single ArrayMesh carrying their colour
## (and their roughness, in alpha) per vertex, so a person is six meshes and
## one material no matter how much detail is drawn on them.
##
## Faces carry their position in metres in UV and their extent in UV2, which is
## what lets the shader bevel every edge by the same centimetre whatever the
## size of the box.
class Batch:
	var _groups: Dictionary = {}

	## Same contract as BoxKit.add: parent-relative corner and size. `rough`
	## rides along in the colour's alpha for the shader to read back.
	func box(parent: Node3D, origin: Vector3, size: Vector3, colour: Color,
			rough: float = 0.88) -> void:
		var g: Dictionary = _groups.get(parent, {})
		if g.is_empty():
			g = {"v": PackedVector3Array(), "n": PackedVector3Array(),
				"c": PackedColorArray(), "uv": PackedVector2Array(),
				"uv2": PackedVector2Array(), "i": PackedInt32Array()}
			_groups[parent] = g
		var lin := colour.srgb_to_linear()
		lin.a = rough
		var v: PackedVector3Array = g["v"]
		var n: PackedVector3Array = g["n"]
		var c: PackedColorArray = g["c"]
		var uv: PackedVector2Array = g["uv"]
		var uv2: PackedVector2Array = g["uv2"]
		var idx: PackedInt32Array = g["i"]
		var mid := origin + size * 0.5
		# Per face: the normal and two tangent axes with u x v = normal.
		var faces := [
			[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
			[Vector3.LEFT, Vector3.BACK, Vector3.UP],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
			[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
			[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
			[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		]
		for f in faces:
			var nrm: Vector3 = f[0]
			var ua: Vector3 = f[1]
			var va: Vector3 = f[2]
			var centre := mid + Vector3(nrm.x * size.x, nrm.y * size.y, nrm.z * size.z) * 0.5
			var hu := absf(ua.dot(size)) * 0.5
			var hv := absf(va.dot(size)) * 0.5
			var base := v.size()
			var fs := Vector2(hu * 2.0, hv * 2.0)
			for k in 4:
				var su := -1.0 if (k == 0 or k == 3) else 1.0
				var sv := -1.0 if (k == 0 or k == 1) else 1.0
				v.append(centre + ua * hu * su + va * hv * sv)
				n.append(nrm)
				c.append(lin)
				uv.append(Vector2((su + 1.0) * hu, (sv + 1.0) * hv))
				uv2.append(fs)
			# Godot winds front faces clockwise.
			idx.append_array(PackedInt32Array([base, base + 2, base + 1,
				base, base + 3, base + 2]))

	## Bakes every group into one MeshInstance3D under its parent.
	func flush() -> Array[MeshInstance3D]:
		var out: Array[MeshInstance3D] = []
		for parent: Node3D in _groups:
			var g: Dictionary = _groups[parent]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g["v"]
			arrays[Mesh.ARRAY_NORMAL] = g["n"]
			arrays[Mesh.ARRAY_COLOR] = g["c"]
			arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
			arrays[Mesh.ARRAY_TEX_UV2] = g["uv2"]
			arrays[Mesh.ARRAY_INDEX] = g["i"]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = BoxKit.batch_material()
			parent.add_child(mi)
			out.append(mi)
		_groups.clear()
		return out
