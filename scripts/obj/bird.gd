extends Node3D
class_name Bird
## A crow on a ridge, a gull over the water, a duck on it.
##
## No physics body. A bird is a point that flies — collision is what a body is
## for and nothing in the town should ever collide with a sparrow, so this is a
## Node3D moved by hand, which makes a flock of them cost about what a flock
## of them should.
##
## Two behaviours. A flier has a perch and a sky: it sits until something
## bothers it or it gets bored, flies a few slow loops at height, and comes
## down on a perch again. A floater — the mallard — lives on the water: it
## paddles between points on the surface, dabbles, and if you walk at it takes
## off in a short low hop to somewhere else on the pond.

enum Mode { PERCHED, FLYING, LANDING, FLOATING }

var kind := "crow"
var world: VoxelWorld
var avoid: Node3D = null
## Places to sit, in world metres. Ridges, treetops, fence posts. Filled by
## the wildlife manager; an empty list means "the ground".
var perches: Array[Vector3] = []
## The water the duck lives on: a centre and a radius it will not paddle past.
var pond := Vector3.ZERO
var pond_r := 6.0
var surface_y := 0.0

var _spec: Dictionary = {}
var _parts: Dictionary = {}
var _mode := Mode.PERCHED
var _t := 0.0                     ## seconds in this mode
var _stay := 10.0                 ## how long the current perch lasts
var _target := Vector3.ZERO
var _speed := 0.0
var _flap := 0.0
var _bank := 0.0
var _wander_centre := Vector3.ZERO
var _wander_r := 12.0
var _wander_h := 10.0
var _wander_ang := 0.0
var _wander_dir := 1.0
var _loops := 0.0
var _dabble := 0.0


func setup(species: String, w: VoxelWorld, at: Vector3) -> void:
	kind = species if CreatureKit.has(species) else "crow"
	_spec = CreatureKit.spec(kind)
	world = w
	global_position = at
	_parts = CreatureKit.build(kind, self)
	_fold(true)
	if str(_spec["move"]) == "float":
		_mode = Mode.FLOATING
		pond = at
		surface_y = at.y
		_pick_paddle()
	else:
		_mode = Mode.PERCHED
		_stay = _perch_time()
		rotation.y = randf() * TAU
	set_process(true)


func _perch_time() -> float:
	var r: Vector2 = _spec["perch_time"]
	return randf_range(r.x, r.y)


func _process(delta: float) -> void:
	_t += delta
	match _mode:
		Mode.PERCHED:
			_perched(delta)
		Mode.FLYING:
			_flying(delta)
		Mode.LANDING:
			_landing(delta)
		Mode.FLOATING:
			_floating(delta)


# ------------------------------------------------------------------ perched

func _perched(delta: float) -> void:
	# Sitting still, with the odd look round. A bird that never moves its head
	# is a decoy.
	var head: Node3D = _parts.get("head", null)
	if head != null:
		head.rotation.y = lerpf(head.rotation.y, sin(_t * 0.7) * 0.6 * signf(sin(_t * 0.23)),
			delta * 3.0)
	var bothered := avoid != null and avoid.global_position.distance_to(global_position) < 5.0
	if _t > _stay or bothered:
		_take_off()


func _take_off() -> void:
	_mode = Mode.FLYING
	_t = 0.0
	_fold(false)
	var alt: Vector2 = _spec["altitude"]
	_wander_centre = global_position + Vector3(randf_range(-10, 10), 0.0, randf_range(-10, 10))
	_wander_centre.y = maxf(world.ground_m(_wander_centre.x, _wander_centre.z), global_position.y) \
		+ randf_range(alt.x, alt.y)
	_wander_r = randf_range(8.0, 18.0)
	_wander_dir = 1.0 if randf() < 0.5 else -1.0
	_wander_ang = atan2(global_position.x - _wander_centre.x, global_position.z - _wander_centre.z)
	_loops = randf_range(1.2, 3.5)
	_speed = float(_spec["cruise"]) * 0.5


# ------------------------------------------------------------------- flying

## Round and round a point in the sky, gaining height on the way up and
## losing it on the way down, which is what a bird with nowhere to be does.
func _flying(delta: float) -> void:
	var cruise := float(_spec["cruise"])
	_speed = move_toward(_speed, cruise, delta * 4.0)
	_wander_ang += _wander_dir * (_speed / _wander_r) * delta
	_loops -= (_speed / _wander_r) * delta / TAU
	var want := _wander_centre + Vector3(sin(_wander_ang) * _wander_r, 0.0,
		cos(_wander_ang) * _wander_r)
	# Never through the ground, whatever the loop wants.
	want.y = maxf(want.y, world.ground_m(want.x, want.z) + 2.5)
	_steer_to(want, delta, cruise)
	_flap_wings(delta, true)
	if _loops <= 0.0:
		_pick_landing()


func _steer_to(want: Vector3, delta: float, speed: float) -> void:
	var to := want - global_position
	var d := to.length()
	if d < 0.05:
		return
	var dir := to / d
	global_position += dir * minf(speed * delta, d)
	# Face the way it is going, and bank into the turn.
	var yaw := atan2(dir.x, dir.z)
	var turn := wrapf(yaw - rotation.y, -PI, PI)
	rotation.y = lerp_angle(rotation.y, yaw, delta * 4.0)
	_bank = lerpf(_bank, clampf(-turn * 1.6, -0.7, 0.7), delta * 3.0)
	rotation.z = _bank
	rotation.x = lerpf(rotation.x, clampf(-dir.y * 0.8, -0.5, 0.5), delta * 3.0)


func _flap_wings(delta: float, airborne: bool) -> void:
	var wings: Array = _parts.get("wings", [])
	if wings.is_empty():
		return
	# A gull glides; a sparrow beats. Wingspan decides the rate, and a bird
	# climbing beats harder than one coasting down.
	var span := float(_spec["wingspan"])
	var rate := 14.0 / maxf(span, 0.2)
	var climbing := rotation.x < -0.05
	var amp := 0.9 if climbing else (0.35 if span > 1.0 else 0.7)
	_flap += delta * rate * (1.0 if airborne else 0.0)
	var a := sin(_flap) * amp
	for i in wings.size():
		var w: Node3D = wings[i]
		var side := -1.0 if i == 0 else 1.0
		w.rotation.z = side * a


## Wings along the body, or out.
func _fold(folded: bool) -> void:
	# Two sets of wings, one shown at a time: the panels along the flank on
	# the ground, the flight wings in the air.
	for w: Node3D in _parts.get("wings", []):
		w.visible = not folded
		w.rotation = Vector3.ZERO
	for m: Node3D in _parts.get("folded", []):
		m.visible = folded
	rotation.x = 0.0
	rotation.z = 0.0
	_bank = 0.0


func _pick_landing() -> void:
	_mode = Mode.LANDING
	_t = 0.0
	if perches.is_empty():
		var g := global_position + Vector3(randf_range(-6, 6), 0.0, randf_range(-6, 6))
		g.y = world.ground_m(g.x, g.z)
		_target = g
		return
	# The nearest few perches, one at random, so a flock does not all land on
	# the same ridge.
	var near: Array = perches.duplicate()
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(global_position) < b.distance_squared_to(global_position))
	_target = near[randi() % mini(near.size(), 4)]


func _landing(delta: float) -> void:
	var cruise := float(_spec["cruise"])
	var d := global_position.distance_to(_target)
	# Come in above the perch, then drop onto it.
	var approach := _target + Vector3(0.0, clampf(d * 0.35, 0.0, 4.0), 0.0)
	_steer_to(approach, delta, maxf(cruise * clampf(d / 8.0, 0.3, 1.0), 1.2))
	_flap_wings(delta, true)
	if d < 0.35:
		global_position = _target
		_mode = Mode.PERCHED
		_t = 0.0
		_stay = _perch_time()
		_fold(true)
		rotation.y = randf() * TAU


# ------------------------------------------------------------------ floating

## The mallard: paddling about the pond, head down now and then.
func _floating(delta: float) -> void:
	global_position.y = surface_y + sin(_t * 1.7) * 0.015
	var bothered := avoid != null and avoid.global_position.distance_to(global_position) < 4.0
	if bothered:
		# A short low flight to the far side of the pond, not a real take-off.
		var away := (global_position - avoid.global_position)
		away.y = 0.0
		var spot := pond + away.normalized() * pond_r * 0.8
		spot.y = surface_y
		_target = spot
		_speed = 5.0
		_flap_wings(delta, true)
	else:
		_speed = float(_spec["cruise"])
		_fold(true)
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.3:
		_pick_paddle()
		return
	var dir := to.normalized()
	global_position += dir * _speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 3.0)
	# Dabbling: the head goes under for a moment every so often.
	var head: Node3D = _parts.get("head", null)
	_dabble -= delta
	if head != null:
		var under := _dabble < 0.0 and _dabble > -1.2
		head.rotation.x = lerpf(head.rotation.x, 1.3 if under else 0.0, delta * 5.0)
		if _dabble < -1.2:
			_dabble = randf_range(4.0, 12.0)


func _pick_paddle() -> void:
	var a := randf() * TAU
	var r := randf() * pond_r
	_target = pond + Vector3(cos(a) * r, 0.0, sin(a) * r)
	_target.y = surface_y
