extends Node3D
class_name Fish
## Something in the water, under the surface, that moves when you get close.
##
## A Node3D moved by hand, like a bird. Fish live in a pool — a centre, a
## radius and a surface height handed over by the wildlife manager — and cruise
## between points inside it, a little below the surface, never rising through
## it except the trout, which jumps. Getting near the edge sends them away
## from you fast and then they settle again, which is exactly what fish do.

var kind := "carp"
var world: VoxelWorld
var avoid: Node3D = null
var pool := Vector3.ZERO
var pool_r := 5.0
var surface_y := 0.0
var floor_y := 0.0

var _spec: Dictionary = {}
var _parts: Dictionary = {}
var _target := Vector3.ZERO
var _speed := 0.0
var _wag := 0.0
var _t := 0.0
var _jump := 0.0                  ## seconds until the next jump, trout only
var _rest := 0.0


func setup(species: String, w: VoxelWorld, at: Vector3) -> void:
	kind = species if CreatureKit.has(species) else "carp"
	_spec = CreatureKit.spec(kind)
	world = w
	global_position = at
	_parts = CreatureKit.build(kind, self)
	_jump = randf_range(15.0, 45.0)
	_pick()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var cruise := float(_spec["cruise"])
	var want := cruise

	var scared := false
	if avoid != null:
		var away := global_position - avoid.global_position
		away.y = 0.0
		var d := away.length()
		if d < 4.5 and d > 0.01:
			scared = true
			# Away, and down.
			_target = global_position + away.normalized() * 4.0
			_target.y = floor_y + (surface_y - floor_y) * 0.25
			_clamp_target()
			want = float(_spec["dart"])
			_rest = 0.0

	_rest -= delta
	if _rest > 0.0 and not scared:
		_speed = move_toward(_speed, 0.0, delta * 2.0)
	else:
		_speed = move_toward(_speed, want, delta * (8.0 if scared else 1.5))

	var to := _target - global_position
	var d2 := to.length()
	if d2 < 0.25:
		_pick()
		_rest = randf_range(0.5, 3.0)
	elif _speed > 0.01:
		var dir := to / d2
		var next := global_position + dir * minf(_speed * delta, d2)
		# Never out of the water, whatever the target says. A straight line
		# across a bay can cross the point of it.
		if world != null and world.get_voxel(VoxelWorld.to_voxel(next)) != VoxelTypes.WATER 				and not (bool(_spec.get("jumps", false)) and next.y > surface_y - 0.05):
			_pick()
			return
		global_position = next
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 3.5)
		rotation.x = lerpf(rotation.x, clampf(-dir.y * 1.2, -0.6, 0.6), delta * 3.0)

	# The tail beats faster the faster it goes, and the whole body rolls a
	# little with each beat.
	_wag += delta * (3.0 + _speed * 6.0)
	var tailfin: Node3D = _parts.get("tailfin", null)
	if tailfin != null:
		tailfin.rotation.y = sin(_wag) * (0.35 + _speed * 0.08)
	rotation.z = sin(_wag * 0.5) * 0.06

	if bool(_spec.get("jumps", false)):
		_jump -= delta
		if _jump <= 0.0:
			_jump = randf_range(20.0, 60.0)
			_leap()


## A trout breaking the surface: up through it, over, and back in a little
## further on. Done as a target above the water and a fast speed; gravity is
## not needed for something that lasts a second.
func _leap() -> void:
	_target = global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * 1.2
	_target.y = surface_y + 0.6
	_speed = 3.5
	_rest = 0.0


func _pick() -> void:
	var a := randf() * TAU
	var r := randf() * pool_r
	_target = pool + Vector3(cos(a) * r, 0.0, sin(a) * r)
	# Somewhere between the bottom and just under the surface.
	_target.y = lerpf(floor_y + 0.2, surface_y - 0.25, randf())
	_clamp_target()


## Keeps a target inside water. A pool is only roughly round, and a target on
## the bank would have the fish beach itself trying to reach it.
func _clamp_target() -> void:
	var v := VoxelWorld.to_voxel(_target)
	if world == null:
		return
	if world.get_voxel(v) != VoxelTypes.WATER:
		# Pull back toward the pool centre until it is wet.
		for _i in 6:
			_target = _target.lerp(Vector3(pool.x, _target.y, pool.z), 0.35)
			if world.get_voxel(VoxelWorld.to_voxel(_target)) == VoxelTypes.WATER:
				return
		_target = Vector3(pool.x, clampf(_target.y, floor_y + 0.2, surface_y - 0.25), pool.z)
