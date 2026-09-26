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
