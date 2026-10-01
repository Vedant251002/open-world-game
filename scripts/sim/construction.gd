extends RefCounted
class_name Construction
## Applies a VoxelPatch to the world over in-game time.
##
## The gap between COMMIT and DISCOVER is the point of the whole loop
## (game-design-doc.md §3): if the player watches the wall go up voxel by voxel
## it is a progress bar, and the surprise is gone. So construction runs whether
## or not anyone is looking, at a rate set by the worker, and the props only
## appear when the shell is finished.

var patch: VoxelPatch
var world: VoxelWorld
var prop_parent: Node3D

var cursor := 0
var finished := false
var props_spawned := false
var spawned_nodes: Array[Node3D] = []

## The show: outline, scaffold, flag, dust, piles of material, confetti. Made
## lazily on the first hour of real work (a building put up by complete_now(),
## which is a save loading or a test, never gets one) and removes itself.
var fx: SiteFx = null
var show_fx := true
const NO_FX := ["road", "levelled ground", "tree", "grove", "demolition", "pen"]
const POPS_PER_BATCH := 6

## Voxels laid per in-game hour. A worker of speed 1.0 puts up a small hut in
## about six hours, which is the loop timing target in §3.
var voxels_per_hour := 3000.0
var _carry := 0.0


func _init(p: VoxelPatch, w: VoxelWorld, props_under: Node3D) -> void:
	patch = p
	world = w
	prop_parent = props_under


func total() -> int:
	return patch.build_order.size()


func progress() -> float:
	if total() == 0:
		return 1.0
	return float(cursor) / float(total())


## Advances construction by an elapsed span of in-game hours.
func advance(hours: float) -> void:
	if finished:
		return
	_carry += hours * voxels_per_hour
	var n := int(_carry)
	if n <= 0:
		return
	_carry -= n
	_ensure_fx()
	_lay(n, true)


## Puts the whole thing up at once. Used by the debug harness and by save
## loading, never by a worker.
func complete_now() -> void:
	_lay(total(), false)


func _lay(n: int, visual: bool = false) -> void:
	var order := patch.build_order
	var end := mini(cursor + n, order.size())
	# A dust puff for a handful of the voxels in this batch, evenly spread, so
	# the cost is the same whether a frame laid ten or ten thousand.
	var stride := maxi(1, n / POPS_PER_BATCH)
	var top_y := -1000000
	var track := visual and fx != null
	var k := 0
	while cursor < end:
		var i := order[cursor]
		cursor += 1
		var mat := patch.data[i]
		if mat == VoxelPatch.UNTOUCHED:
			continue
		var v := patch.world_of(i)
		world.set_voxel(v, mat)
		if track:
			if v.y > top_y:
				top_y = v.y
			if k % stride == 0 and mat != VoxelTypes.AIR:
				fx.pop(v, mat)
			k += 1
	if track and top_y > -1000000:
		fx.progress(progress(), float(top_y + 1) * SiteFx.VOXEL_M - fx.ground_y())
	if cursor >= order.size() and not finished:
		finished = true
		if fx != null:
			fx.celebrate(_title())
			fx = null
		_spawn_props()


## Dropped a job half way: the show goes, the walls stay as they are.
func abandon_show() -> void:
	if fx != null and is_instance_valid(fx):
		fx.queue_free()
	fx = null


## The outline goes up when the builder arrives, before the first course.
func begin_show() -> void:
	_ensure_fx()


func _ensure_fx() -> void:
	if fx != null and is_instance_valid(fx):
		return
	if not show_fx or finished or prop_parent == null or not prop_parent.is_inside_tree():
		return
	if NO_FX.has(patch.archetype) or patch.footprint.size.x < 10 or patch.footprint.size.y < 10:
		return
	fx = SiteFx.new()
	fx.name = "SiteFx"
	prop_parent.add_child(fx)
	fx.setup(patch, world)


## A worker has walked a load over and put it down by the site.
func drop_material(kind: String, at: Vector3) -> void:
	_ensure_fx()
	if fx != null:
		fx.drop_pile(kind, at)


func _title() -> String:
	if patch.sign_text != "":
		return patch.sign_text.capitalize()
	return patch.archetype.replace("_", " ").capitalize()


## The furniture, for a building put back from a save: the voxels came back
## with the world, the props did not.
func respawn_props() -> void:
	props_spawned = false
	_spawn_props()


func _spawn_props() -> void:
	if props_spawned or prop_parent == null:
		return
	props_spawned = true
	for p: Dictionary in patch.props:
		var t := str(p.get("type", ""))
		if t == "signboard_text":
			spawned_nodes.append(_spawn_sign(p))
			continue
		if not Props.exists(t):
			continue
		spawned_nodes.append(Props.spawn(t, p["pos"], float(p.get("yaw", 0.0)), prop_parent))
		# Ambient life: sparks off a forge, embers in an oven.
		var key := Props.resolve(t)
		if key == "forge_block":
			VillageAmbience.add_source(patch.get_instance_id(), "forge", Vector3(p["pos"]) + Vector3(0, 0.75, 0))
		elif key == "oven_block":
			VillageAmbience.add_source(patch.get_instance_id(), "oven", Vector3(p["pos"]) + Vector3(0, 0.5, 0))
	_register_chimneys()


## Smoke from every chimney the building has. Only the module's rectangle and
## the building's height are recorded here: the stack itself is found later, by
## Ambience, from the voxels once they are in the world (a restored save has no
## patch data to read, and its chunks are not loaded yet at this point).
func _register_chimneys() -> void:
	for m: Dictionary in patch.modules:
		var mdef := Vocabulary.def(str(m.get("type", "")))
		if not ("chimney" in mdef.get("needs", [])):
			continue
		var kind := "steam" if str(m.get("type", "")) == "oven" else "smoke"
		VillageAmbience.add_chimney(patch.get_instance_id(), kind, m["rect"],
			patch.origin.y, patch.origin.y + patch.size.y - 1)



## The shop sign is the one place text belongs in the world: it is how the
## player reads a street at a glance, and it is what makes a misread
## instruction funny rather than merely wrong.
func _spawn_sign(p: Dictionary) -> Node3D:
	var label := Label3D.new()
	label.text = str(p.get("text", ""))
	label.font_size = 72
	label.pixel_size = 0.0042
	label.outline_size = 6
	label.modulate = Color("#f4e6c8")
	label.outline_modulate = Color("#2a1c10")
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.no_depth_test = false
	label.position = p["pos"]
	label.rotation.y = float(p.get("yaw", 0.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prop_parent.add_child(label)
	return label


## Demolition: takes the building back out and refunds part of the materials,
## per game-design-doc.md §9. Wrong must be recoverable, and never free.
func demolish() -> Dictionary:
	VillageAmbience.remove_owner(patch.get_instance_id())
	if fx != null and is_instance_valid(fx):
		fx.queue_free()
	fx = null
	for i in patch.build_order:
		var mat := patch.data[i]
		if mat == VoxelPatch.UNTOUCHED or mat == VoxelTypes.AIR:
			continue
		world.set_voxel(patch.world_of(i), VoxelTypes.AIR)
	for n: Node3D in spawned_nodes:
		if is_instance_valid(n):
			n.queue_free()
	spawned_nodes.clear()

	var refund := {}
	for mat_name: String in patch.cost:
		refund[mat_name] = int(float(patch.cost[mat_name]) * 0.4)
	finished = false
	cursor = 0
	props_spawned = false
	return refund
