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


## Matte paint in this colour. Roughness is fixed at 0.9 because everything
## drawn with this is cloth, skin, wool or wood — nothing here is shiny, and a
## second parameter would fragment the cache for no visible gain.
static func paint(colour: Color) -> StandardMaterial3D:
	var key := colour.to_rgba32()
	var m: StandardMaterial3D = _materials.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.9
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
