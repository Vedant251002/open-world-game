extends CharacterBody3D
class_name Animal
## Anything with legs that lives on the ground — livestock, pets and the wild.
##
## Deliberately simple: wander, avoid whatever is walking at you, and produce
## something on a timer. There is no hunger, no breeding tree and no mob AI
## here, because animals are scenery that pays — the game is about the three
## workers, and an animal that needs managing would compete with them for the
## player's attention.
##
## The body comes from CreatureKit, which knows what a goat looks like; this
## file only knows how to move one. The two things that differ between a hen
## and a deer here are how far away it wants you (a deer bolts at nine metres,
## a hen at three) and whether it walks or hops.

signal produced(kind: String, at: Vector3)

const GRAVITY := 22.0

var kind := "hen"
var world: VoxelWorld
var clock: GameClock
var avoid: Node3D = null            ## the player; animals keep their distance
var home := Vector3.ZERO
var roam := 11.0
## Ground this animal will not choose to walk onto, in voxels. The streets,
## for anything wild: a deer that wanders into the plaza is a deer that has
## stopped being wild, and the town's own animals have the plaza already.
var keep_out := Rect2i()

var _spec: Dictionary = {}
var _target := Vector3.ZERO
var _rest := 0.0
var _phase := 0.0
var _since_produced := 0.0
## Game hours of being well looked after still to run. While it lasts the
## animal gives twice as often. Set by a farmhand tending the pens.
var tended_hours := 0.0
var _parts: Dictionary = {}
var _legs: Array = []
var _head: Node3D
var _torso: Node3D
var _tail: Node3D
var _head_rest_y := 0.0
var _hopping := false
var _hop_t := 0.0


func setup(species: String, w: VoxelWorld, c: GameClock, at: Vector3) -> void:
	kind = species if CreatureKit.has(species) else "hen"
	_spec = CreatureKit.spec(kind)
	world = w
	clock = c
	home = at
	global_position = at

	var dims := _dims()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = dims.x * 0.5
	cap.height = maxf(dims.y, dims.x)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)

	# Animals do not push the player about and the player does not herd them by
	# walking into them, so they collide with the world and nothing else.
	collision_layer = 0
	collision_mask = 1

	_parts = CreatureKit.build(kind, self)
	_legs = _parts.get("legs", [])
	_head = _parts.get("head", null)
	_torso = _parts.get("torso", null)
	_tail = _parts.get("tail", null)
	if _head != null:
		_head_rest_y = _head.position.y
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.4
	_rest = randf_range(0.5, 3.0)
	_since_produced = randf_range(0.0, maxf(float(_spec.get("every", 0.0)), 1.0))


## Width and height of the body, for the collision capsule, whichever plan
## built it.
func _dims() -> Vector2:
	if _spec["plan"] == "bird":
		var b: Vector3 = _spec["body"]
		return Vector2(b.x, float(_spec["stand"]) + b.y)
	return Vector2(float(_spec["W"]), float(_spec["H"]))


func is_wild() -> bool:
	return bool(_spec.get("wild", false))


# ------------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		# Terminal velocity is the whole of the difference between a hen and a
		# cow falling off a wall.
		velocity.y = maxf(velocity.y - GRAVITY * delta, -float(_spec.get("fall", 22.0)))
	else:
		velocity.y = 0.0

	var speed := _decide(delta)
	move_and_slide()
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	_tick_produce(delta)
	if speed > 0.0 and is_on_wall() and is_on_floor():
		velocity.y = 3.6


func _decide(delta: float) -> float:
	# Somebody walking at it beats whatever it was doing. A dog has no shy
	# distance at all and comes to see who it is.
	var shy := float(_spec.get("shy", 0.0))
	if avoid != null and shy > 0.0:
		var away := global_position - avoid.global_position
		away.y = 0.0
		var d := away.length()
		if d < shy and d > 0.01:
			var dir := away / d
			if keep_out.size.x > 0:
				# Bolting straight away from you would carry it into the
				# streets: swing the run ninety degrees along the edge instead.
				var ahead := VoxelWorld.to_voxel(global_position + dir * 6.0)
				if keep_out.has_point(Vector2i(ahead.x, ahead.z)):
					dir = Vector3(-dir.z, 0.0, dir.x)
			var flee := float(_spec["flee"])
			velocity.x = dir.x * flee
			velocity.z = dir.z * flee
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 9.0)
			_rest = randf_range(0.3, 1.2)
			if _spec["move"] == "hop" and is_on_floor():
				velocity.y = 3.2
			return flee

	_rest -= delta
	if _rest > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		return 0.0

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	if to.length() < 0.6:
		_pick_target()
		_rest = randf_range(1.4, 5.5)
		return 0.0

	var speed := float(_spec["speed"])
	var dir := to.normalized()
	if _spec["move"] == "hop":
		# A rabbit moves in bounds: a push off the ground, a pause, another.
		if is_on_floor():
			_hop_t -= delta
			if _hop_t <= 0.0:
				velocity.y = 2.6
				velocity.x = dir.x * speed
				velocity.z = dir.z * speed
				_hop_t = randf_range(0.35, 0.7)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 5.0)
	return speed


func _pick_target() -> void:
	for _try in 6:
		var a := randf() * TAU
		var r := randf() * roam
		_target = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if keep_out.size.x > 0:
			var v := VoxelWorld.to_voxel(_target)
			if keep_out.has_point(Vector2i(v.x, v.z)):
				continue
		break
	if world != null:
		_target.y = world.ground_m(_target.x, _target.z)


func _animate(delta: float, speed: float) -> void:
	var walking := speed > 0.05
	if walking:
		_phase += delta * speed * (5.5 if _legs.size() > 2 else 7.0)
		var swing := sin(_phase) * 0.7
		for i in _legs.size():
			# Diagonal pairs move together on a quadruped, which is a walk;
			# alternate on a bird, which is a strut.
			var sign := 1.0 if (i == 0 or i == 3) else -1.0
			if _legs.size() == 2:
				sign = 1.0 if i == 0 else -1.0
			(_legs[i] as Node3D).rotation.x = swing * sign
		# The head bob is what makes a box look alive.
		if _head != null:
			_head.position.y = _head_rest_y + sin(_phase * 2.0) * 0.02
			_head.rotation.x = lerpf(_head.rotation.x, _head_rest_pitch(), delta * 6.0)
		if _torso != null:
			_torso.rotation.z = sin(_phase) * 0.02
		if _tail != null and _spec["plan"] == "quadruped":
			_tail.rotation.y = sin(_phase * 0.5) * 0.25
	else:
		for l: Node3D in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, delta * 8.0)
		if _torso != null:
			_torso.rotation.z = lerpf(_torso.rotation.z, 0.0, delta * 8.0)
		# Grazing, or pecking at the ground, while idle.
		_phase += delta * 1.3
		var peck := maxf(sin(_phase * 0.9), 0.0)
		if _head != null:
			_head.rotation.x = _head_rest_pitch() + (-peck * peck * 0.9
				if _spec["plan"] == "bird" else peck * peck * 0.55)
		if _tail != null and _spec["plan"] == "quadruped":
			_tail.rotation.y = sin(_phase * 1.7) * 0.15


## Where the head sits when it is not doing anything: level for a bird,
## most of the way back to level off a raised neck for a quadruped.
func _head_rest_pitch() -> float:
	if _spec["plan"] == "quadruped":
		return float(_spec["neck_up"]) * 0.75
	return 0.0


## Eggs, wool and milk arrive on the game clock, so a herd left alone for two
## in-game days has two days of produce waiting. Species with nothing to give
## never get here.
func _tick_produce(delta: float) -> void:
	if clock == null or clock.paused or str(_spec.get("gives", "")) == "":
		return
	var hours := delta / 60.0 * GameClock.HOURS_PER_REAL_MINUTE * clock.speed
	_since_produced += hours
	var every := float(_spec["every"])
	if tended_hours > 0.0:
		tended_hours = maxf(tended_hours - hours, 0.0)
		every *= 0.5
	if _since_produced < every:
		return
	_since_produced = 0.0
	produced.emit(str(_spec["gives"]), global_position)
