extends Node3D
class_name CarriedItem
## What somebody is carrying, held out in front of them in both arms.
##
## The carry pose has always been there (arms forward, 1.35 rad) but the hands
## were empty, which read as a man pushing an invisible door. This is the load:
## a bundle of planks, a hod of bricks, a sack, a basket. It hangs off the torso
## so it rides the walk bob and the counter-twist for free, and it is built
## from the same vertex-painted boxes as the people so it costs nothing.

const KINDS := ["planks", "timber", "stone", "bricks", "sack", "basket", "crate"]

static var _cache: Dictionary = {}     ## kind -> ArrayMesh, shared by everyone


## Which load goes with a material name from VoxelPatch.cost.
static func kind_for_material(mat_name: String) -> String:
	match mat_name:
		"plank", "thatch", "wood":
			return "planks"
		"timber", "log", "bark":
			return "timber"
		"brick", "tile", "clay":
			return "bricks"
		"granite", "sandstone", "cobble", "stone", "concrete", "rock", "slate":
			return "stone"
	return "planks"


## The main material of a building: the one it has most of.
static func kind_for_patch(patch: VoxelPatch) -> String:
	var best := ""
	var most := -1
	for mat_name: String in patch.cost:
		var n := int(patch.cost[mat_name])
		if n > most:
			most = n
			best = mat_name
	return kind_for_material(best)


## Swaps the load on a humanoid. "" puts it down. Safe to call every frame.
static func set_on(body: Humanoid, kind: String) -> void:
	if body == null or body.torso == null:
		return
	var cur: Node3D = body.get_meta("carried_node") if body.has_meta("carried_node") else null
	var cur_kind := str(body.get_meta("carried_kind", ""))
	if cur_kind == kind:
		return
	if cur != null and is_instance_valid(cur):
		cur.queue_free()
	body.set_meta("carried_node", null)
	body.set_meta("carried_kind", kind)
	if kind == "":
		return
	var item := CarriedItem.new()
	item.name = "Carried"
	# In front of the chest, between the forearms. The arms come up to 1.35 rad
	# from the shoulder at y 0.42, so the hands end about 0.27 m out.
	item.position = Vector3(0.0, 0.17, 0.30)
	item.build(kind)
	body.torso.add_child(item)
	body.set_meta("carried_node", item)


func build(kind: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	mi.material_override = BoxKit.batch_material()
	add_child(mi)


static func _mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var holder := Node3D.new()
	var b := BoxKit.Batch.new()
	match kind:
		"planks":
			# A stack of boards, tied with cord.
			for i in 4:
				b.box(holder, Vector3(-0.17, -0.09 + i * 0.045, -0.20), Vector3(0.34, 0.04, 0.44),
					Color("#b88b57").lerp(Color("#8e6a40"), float(i % 2) * 0.5), 0.9)
			b.box(holder, Vector3(-0.175, -0.095, -0.06), Vector3(0.35, 0.19, 0.02), Color("#e0d2a8"))
		"timber":
			for i in 3:
				b.box(holder, Vector3(-0.15 + i * 0.1, -0.08 + (i % 2) * 0.07, -0.22),
					Vector3(0.09, 0.09, 0.48), Color("#6e4d30"), 0.95)
		"stone":
			b.box(holder, Vector3(-0.15, -0.09, -0.12), Vector3(0.28, 0.17, 0.26), Color("#7b7873"), 0.95)
			b.box(holder, Vector3(-0.02, 0.06, -0.08), Vector3(0.18, 0.13, 0.20), Color("#8d8a84"), 0.95)
		"bricks":
			for i in 3:
				b.box(holder, Vector3(-0.16, -0.09 + i * 0.07, -0.13), Vector3(0.32, 0.065, 0.24),
					Color("#98462f").lerp(Color("#b1593c"), float(i % 2) * 0.6), 0.9)
		"sack":
			b.box(holder, Vector3(-0.15, -0.10, -0.15), Vector3(0.30, 0.26, 0.30), Color("#c8b88e"), 0.95)
			b.box(holder, Vector3(-0.08, 0.15, -0.08), Vector3(0.16, 0.06, 0.16), Color("#b3a276"), 0.95)
			b.box(holder, Vector3(-0.09, 0.145, -0.09), Vector3(0.18, 0.02, 0.18), Color("#7a6240"), 0.95)
		"basket":
			b.box(holder, Vector3(-0.19, -0.10, -0.17), Vector3(0.38, 0.17, 0.34), Color("#a07a47"), 0.95)
			b.box(holder, Vector3(-0.17, 0.07, -0.15), Vector3(0.34, 0.03, 0.30), Color("#7d5a32"), 0.95)
			# What is in it: something green and something gold.
			b.box(holder, Vector3(-0.14, 0.09, -0.11), Vector3(0.14, 0.09, 0.14), Color("#7aa63c"), 0.9)
			b.box(holder, Vector3(0.01, 0.09, -0.04), Vector3(0.13, 0.08, 0.12), Color("#d7a93a"), 0.9)
		_:
			b.box(holder, Vector3(-0.18, -0.10, -0.17), Vector3(0.36, 0.26, 0.34), Color("#8c6a43"), 0.9)
			b.box(holder, Vector3(-0.185, 0.0, -0.175), Vector3(0.37, 0.03, 0.35), Color("#5e4429"), 0.9)
	var out := b.flush()
	var m: ArrayMesh = null
	if not out.is_empty():
		m = out[0].mesh as ArrayMesh
	holder.free()
	_cache[kind] = m
	return m
