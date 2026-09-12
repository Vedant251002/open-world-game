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
	_lay(n)


## Puts the whole thing up at once. Used by the debug harness and by save
## loading, never by a worker.
func complete_now() -> void:
	_lay(total())


func _lay(n: int) -> void:
	var order := patch.build_order
	var end := mini(cursor + n, order.size())
	while cursor < end:
		var i := order[cursor]
		cursor += 1
		var mat := patch.data[i]
		if mat == VoxelPatch.UNTOUCHED:
			continue
		world.set_voxel(patch.world_of(i), mat)
	if cursor >= order.size() and not finished:
		finished = true
		_spawn_props()


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
