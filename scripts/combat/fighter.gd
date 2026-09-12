extends CharacterBody3D
class_name Fighter
## Somebody with a weapon: one of the town's soldiers, or one of the raiders
## who come for it.
##
## The same class on both sides. What differs is who they shoot at, where they
## go when nothing is happening, and where the ammunition comes from — a
## soldier draws on the town's stores, a raider brought what he has. Bodies
## are Humanoids in different coats.
##
## Fighting is simple on purpose: find the nearest enemy in sight, get to a
## sensible distance, face it, fire when the weapon has reloaded. Raiders on
## top of that go for the buildings, because a raid that only ever shoots at
## soldiers is a duel, and the point of grenades is what they do to a wall.

signal died(who: Fighter)

enum Mode { GUARD, ENGAGE, RETREAT, MARCH, DEAD }

const WALK := 2.4
const RUN := 4.6
const SIGHT := 48.0
const STEP_UP_M := 0.7

var side := "town"                  ## "town" or "raider"
var weapon := ""                    ## Arsenal.WEAPONS key, or "" for unarmed
var health := 100.0
var max_health := 100.0
var world: VoxelWorld
var nav: NavGrid
var warfare: Node
var body: Humanoid
var post := Vector3.ZERO            ## where this one stands when idle
var ammo := 0                       ## raiders only: what they brought
var display_name := "soldier"

var _mode := Mode.GUARD
var _target: Node3D = null
var _goal := Vector3.ZERO
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _reload := 0.0
var _blocked := 0.0
var _slide := Vector3.ZERO
var _look_t := 0.0
var _gun: Node3D = null
var _dead_t := 0.0
var _flinch := 0.0
var _target_building: Dictionary = {}
var _repath := 0.0


func setup(which_side: String, w: VoxelWorld, n: NavGrid, wf: Node, at: Vector3,
		arm: String) -> void:
	side = which_side
	world = w
	nav = n
	warfare = wf
	weapon = arm
	global_position = at
	post = at
	max_health = 100.0 if side == "town" else 80.0
	health = max_health
	display_name = "soldier" if side == "town" else "raider"

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	add_child(shape)
	collision_layer = 0
	collision_mask = 1

	body = Humanoid.new()
	if side == "town":
		# The town's coat: dark blue with a white belt and a cap.
		body.cloth_colour = Color("#2e3e66")
		body.accent_colour = Color("#e6e2d6")
		body.hair_colour = Color("#3a2c20")
		body.body_colour = Color("#c99070")
		body.accessory = "cap"
	else:
		# Whatever they had: dark and worn, with a red rag at the neck.
		body.cloth_colour = Color("#3a332c")
		body.accent_colour = Color("#8f2a22")
		body.hair_colour = Color("#1a1512")
		body.body_colour = Color("#b08a68")
		body.accessory = "scarf"
	add_child(body)
	_arm(arm)
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.5
	set_physics_process(true)


## Puts a weapon in the right hand, or takes it away.
func _arm(kind: String) -> void:
	weapon = kind
	if _gun != null:
		_gun.queue_free()
		_gun = null
	if kind == "" or body == null or body.arm_r == null:
		return
	_gun = Node3D.new()
	_gun.position = Vector3(0.0, -0.36, 0.06)
	body.arm_r.add_child(_gun)
	match kind:
		"grenade":
			BoxKit.add(_gun, Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1), Color("#2b2f2b"))
		"mortar":
			BoxKit.add(_gun, Vector3(-0.06, -0.1, -0.1), Vector3(0.12, 0.12, 0.5), Color("#4a4f55"))
		"launcher":
			BoxKit.add(_gun, Vector3(-0.05, -0.06, -0.3), Vector3(0.1, 0.1, 0.8), Color("#5a5f66"))
			BoxKit.add(_gun, Vector3(-0.06, -0.07, 0.4), Vector3(0.12, 0.12, 0.1), Color("#b8302a"))
		"pistol":
			BoxKit.add(_gun, Vector3(-0.02, -0.03, -0.02), Vector3(0.04, 0.05, 0.16), Color("#3a3d42"))
		_:
			# Musket and rifle: a long stock and a barrel.
			BoxKit.add(_gun, Vector3(-0.025, -0.04, -0.28), Vector3(0.05, 0.06, 0.5), Color("#6d4a2c"))
			BoxKit.add(_gun, Vector3(-0.014, 0.0, 0.1), Vector3(0.028, 0.028, 0.5), Color("#3a3d42"))


func arm(kind: String) -> void:
	_arm(kind)


func is_dead() -> bool:
	return _mode == Mode.DEAD


# --------------------------------------------------------------------- orders

## Stand here and watch.
func hold(at: Vector3) -> void:
	post = at
	_mode = Mode.GUARD
	_goal = at
	_path = PackedVector3Array()


## Go there, fighting anything met on the way.
func march(to: Vector3) -> void:
	_goal = to
	_mode = Mode.MARCH
	_path = PackedVector3Array()


func attack(t: Node3D) -> void:
	_target = t
	_mode = Mode.ENGAGE


# --------------------------------------------------------------------- damage

func take_hit(dmg: float, from: Vector3, who: Node3D) -> void:
	if _mode == Mode.DEAD:
		return
	health -= dmg
	_flinch = 0.35
	if health <= 0.0:
		_die()
		return
	# Being shot by somebody is a reason to shoot them back.
	if who != null and is_instance_valid(who) and who != self and who is Node3D:
		if _enemy(who):
			_target = who
			if _mode != Mode.RETREAT:
				_mode = Mode.ENGAGE
	if side == "town" and health < max_health * 0.22:
		_mode = Mode.RETREAT


func _die() -> void:
	_mode = Mode.DEAD
	velocity = Vector3.ZERO
	collision_mask = 0
	_dead_t = 0.0
	died.emit(self)


# ------------------------------------------------------------------- thinking

func _physics_process(delta: float) -> void:
	if _mode == Mode.DEAD:
		_lie_down(delta)
		return
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0.0
	_reload = maxf(_reload - delta, 0.0)
	_flinch = maxf(_flinch - delta, 0.0)
	if health < max_health and side == "town" and _mode != Mode.ENGAGE:
		health = minf(health + 2.0 * delta, max_health)

	_look_for_trouble(delta)
	var planar := 0.0
	match _mode:
		Mode.GUARD:
			planar = _guard(delta)
		Mode.ENGAGE:
			planar = _engage(delta)
		Mode.RETREAT:
			planar = _go(post, delta, RUN)
			if global_position.distance_to(post) < 2.0 and health > max_health * 0.5:
				_mode = Mode.GUARD
		Mode.MARCH:
			planar = _go(_goal, delta, WALK)
			if global_position.distance_to(_goal) < 2.0:
				post = _goal
				_mode = Mode.GUARD

	var was := global_position
	move_and_slide()
	_headway(was, planar, delta)
	if body != null:
		body.animate(delta, planar, false)


## Whoever is nearest and hostile and in sight becomes the target. Checked a
## few times a second, not every frame.
func _look_for_trouble(delta: float) -> void:
	_look_t -= delta
	if _look_t > 0.0:
		return
	_look_t = 0.3
	if _mode == Mode.RETREAT:
		return
	if _target != null and (not is_instance_valid(_target) or _dead_of(_target)):
		_target = null
		if _mode == Mode.ENGAGE:
			_mode = Mode.GUARD
	if _target == null and warfare != null and warfare.has_method("nearest_enemy"):
		var t: Node3D = warfare.nearest_enemy(self, SIGHT)
		if t != null:
			_target = t
			_mode = Mode.ENGAGE
	# A raider with nobody to shoot goes for the nearest building instead.
	if side == "raider" and _target == null and _mode != Mode.ENGAGE \
			and warfare != null and warfare.has_method("nearest_building"):
		_target_building = warfare.nearest_building(global_position)
		if not _target_building.is_empty():
			_goal = _target_building["at"]
			_mode = Mode.MARCH


func _dead_of(n: Node3D) -> bool:
	if n.has_method("is_dead"):
		return n.is_dead()
	return false


func _enemy(n: Node3D) -> bool:
	if n is Fighter:
		return (n as Fighter).side != side
	# Workers, the player and the animals are the town's.
	return side == "raider"


func _guard(delta: float) -> float:
	var d := global_position.distance_to(post)
	if d > 2.5:
		return _go(post, delta, WALK)
	velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
	# Looking about.
	rotation.y = lerp_angle(rotation.y, rotation.y + sin(_look_t * 3.0) * 0.02, 1.0)
	# A raider with a building to break goes and breaks it.
	if side == "raider" and not _target_building.is_empty() and weapon != "":
		_shoot_at_point(_target_building["at"] + Vector3(0, 1.5, 0))
	return 0.0


## Close to a good range, face the target, fire when loaded.
func _engage(delta: float) -> float:
	if _target == null or not is_instance_valid(_target):
		_mode = Mode.GUARD
		return 0.0
	var spec := Arsenal.weapon(weapon)
	var reach := float(spec.get("range", 20.0)) if not spec.is_empty() else 3.0
	var want := clampf(reach * 0.4, 4.0, 18.0)
	var to := _target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var planar := 0.0
	# No use firing at somebody behind a hill. The first version of this had
	# both sides stood either side of the town's terrace, emptying their
	# guns into the lip of it — a hundred and thirty-eight shots, no hits.
	var clear := _can_see(_target)
	if d > want + 1.5 or not clear:
		planar = _go(_target.global_position, delta, RUN if side == "raider" else WALK)
	elif d < want * 0.5 and weapon != "grenade":
		# Too close: back off while still facing them.
		var back := global_position - to.normalized() * 3.0
		planar = _go(back, delta, WALK)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
	if d > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), delta * 8.0)
	if weapon != "" and d <= reach and clear:
		_shoot_at(_target)
	elif weapon == "" and d < 1.4 and _reload <= 0.0:
		# Fists. Better than nothing, and what a raider who has run dry does.
		_reload = 1.2
		if _target.has_method("take_hit"):
			_target.take_hit(8.0, global_position, self)
	return planar


## Whether the muzzle can see the target's chest: the voxels between them,
## sampled every quarter metre, with the last metre forgiven because the
## target's own body is solid to nothing here.
func _can_see(t: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 1.25, 0.0)
	var to := t.global_position + Vector3(0.0, 0.9, 0.0)
	var d := from.distance_to(to)
	if d < 1.5:
		return true
	var dir := (to - from) / d
	var steps := int((d - 0.8) / 0.25)
	for i in range(2, steps + 1):
		if world.is_solid(VoxelWorld.to_voxel(from + dir * (i * 0.25))):
			return false
	return true


func _shoot_at(t: Node3D) -> void:
	if _reload > 0.0 or warfare == null:
		return
	var aim := t.global_position + Vector3(0.0, 0.9, 0.0)
	# Lead a moving target a little, badly. Nobody here is a marksman.
	if t is CharacterBody3D:
		var v := (t as CharacterBody3D).velocity
		aim += Vector3(v.x, 0.0, v.z) * 0.25
	_shoot_at_point(aim, t)


func _shoot_at_point(aim: Vector3, t: Node3D = null) -> void:
	if _reload > 0.0 or warfare == null or not warfare.has_method("fire"):
		return
	var spec := Arsenal.weapon(weapon)
	if spec.is_empty():
		return
	if not warfare.can_fire(self):
		return
	var muzzle := global_position + Vector3(0.0, 1.25, 0.0) \
		+ Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * 0.5
	if warfare.fire(self, weapon, muzzle, aim, t):
		_reload = float(spec.get("reload", 2.0))
		if body != null:
			body.reset_cycle()


# ------------------------------------------------------------------- walking

## Toward a point: on the nav grid when both ends are on it, straight at it
## when they are not, sliding along whatever is in the way either way.
func _go(to: Vector3, delta: float, speed: float) -> float:
	_repath -= delta
	if _path.is_empty() or _repath <= 0.0 or _blocked > 1.5:
		_repath = 2.0
		_blocked = 0.0
		if nav != null and nav.walkable_at(global_position) and nav.walkable_at(to):
			_path = nav.path(global_position, to)
		else:
			_path = PackedVector3Array([to])
		_path_i = 0
	if _path.is_empty():
		_path = PackedVector3Array([to])
		_path_i = 0
	var wp := _path[_path_i]
	var d := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
	if d.length() < 1.0 and _path_i < _path.size() - 1:
		_path_i += 1
		wp = _path[_path_i]
		d = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
	if d.length() < 0.3:
		velocity.x = 0.0
		velocity.z = 0.0
		return 0.0
	var dir := d.normalized()
	if _blocked > 0.3 and _slide != Vector3.ZERO:
		var along := Vector3(-_slide.z, 0.0, _slide.x)
		if along.dot(dir) < 0.0:
			along = -along
		dir = (along + _slide * 0.25 + dir * 0.2).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if _mode != Mode.ENGAGE:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 7.0)
	_step_up(dir)
	return speed


func _step_up(dir: Vector3) -> void:
	if not is_on_floor() or not is_on_wall():
		return
	var ahead := global_position + dir * 0.55
	var top := world.ground_m(ahead.x, ahead.z)
	var rise := top - global_position.y
	if rise <= 0.05 or rise > STEP_UP_M:
		return
	if world.is_solid(VoxelWorld.to_voxel(Vector3(ahead.x, top + 1.9, ahead.z))):
		return
	global_position.y = top + 0.02


func _headway(was: Vector3, wanted: float, delta: float) -> void:
	if wanted <= 0.0:
		_blocked = 0.0
		_slide = Vector3.ZERO
		return
	var moved := Vector2(global_position.x - was.x, global_position.z - was.z).length()
	if moved > 0.35 * delta:
		_blocked = maxf(_blocked - delta * 2.0, 0.0)
		return
	_blocked += delta
	if is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length() > 0.01:
			_slide = n.normalized()


## Down, and then gone.
func _lie_down(delta: float) -> void:
	_dead_t += delta
	var k := clampf(_dead_t / 0.45, 0.0, 1.0)
	rotation.x = lerpf(rotation.x, -PI * 0.5, k)
	position.y = lerpf(position.y, position.y, 0.0)
	if _dead_t > 7.0:
		queue_free()
