extends CharacterBody3D
class_name Player
## The employer. Walks, looks, and talks. That is the whole verb set.
##
## Design pillar P1: language is the only verb. There is deliberately no build
## key, no placement cursor and no inventory — if you want something to exist,
## somebody else has to make it.

signal looked_at(worker: Node)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.4
const ACCEL := 12.0
const AIR_ACCEL := 2.5
const JUMP_SPEED := 6.4
const MOUSE_SENS := 0.0022
const EYE_HEIGHT := 1.62
const REACH := 9.0
## How far the touch stick has to be pushed before walking becomes running.
## Owned here rather than in the HUD because it is a movement rule; the HUD
## reads it back so the sprint ring lights up at exactly the right moment.
const TOUCH_SPRINT_AT := 0.92

var camera: Camera3D
var yaw := 0.0
var pitch := 0.0
var input_enabled := true

var _bob := 0.0
var _touch_move := Vector2.ZERO   ## left stick, -1..1 per axis
var _touch_look := Vector2.ZERO   ## drag accumulated since the last physics tick
var _head: Node3D
var _target: Node = null
var _ray: RayCast3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	shape.shape = cap
	shape.position.y = 0.89
	add_child(shape)

	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)

	camera = Camera3D.new()
	camera.fov = 74.0
	camera.near = 0.05
	camera.far = 2400.0
	camera.current = true
	_head.add_child(camera)

	# A whisper of far-field defocus, starting well past anything the player
	# needs to read. Enough to sell depth, not enough to soften the town.
	var att := CameraAttributesPractical.new()
	att.dof_blur_far_enabled = true
	att.dof_blur_far_distance = 160.0
	att.dof_blur_far_transition = 120.0
	att.dof_blur_amount = 0.015
	camera.attributes = att

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = 0xFFFFFFFF
	camera.add_child(_ray)

	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.4
	_apply_mouse_mode()


func teleport(to: Vector3, facing_yaw: float = 0.0) -> void:
	global_position = to
	yaw = facing_yaw
	pitch = 0.0
	velocity = Vector3.ZERO
	rotation.y = yaw
	_head.rotation.x = 0.0


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		_touch_move = Vector2.ZERO
		_touch_look = Vector2.ZERO
	_apply_mouse_mode()


## Pointer lock is the desktop half of mouse-look and does not exist on a phone
## at all — iPhone Safari has no Pointer Lock API — so on a handheld we leave
## the cursor alone and let the drag handler do the work. A desktop with a
## touchscreen is still a desktop and keeps the capture.
func _apply_mouse_mode() -> void:
	if Platform.is_handheld():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Radians of yaw/pitch a thumb drag is asking for. Accumulated rather than
## applied straight away so several drag events inside one frame add up instead
## of fighting each other.
func add_touch_look(delta_rad: Vector2) -> void:
	if input_enabled:
		_touch_look += delta_rad


func set_touch_move(v: Vector2) -> void:
	_touch_move = v if input_enabled else Vector2.ZERO


## Drops the effects the gl_compatibility renderer cannot draw anyway. The
## far-field defocus is the expensive lie here: it is a Forward+ post pass, so
## on a phone it buys nothing and the attributes resource is dead weight.
func set_low_spec(on: bool) -> void:
	if camera == null or not on:
		return
	camera.attributes = null
	camera.far = 900.0   ## the far terrain ends here anyway


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENS
		pitch = clampf(pitch - mm.relative.y * MOUSE_SENS, -1.45, 1.45)


func _physics_process(delta: float) -> void:
	if _touch_look != Vector2.ZERO:
		yaw -= _touch_look.x
		pitch = clampf(pitch - _touch_look.y, -1.45, 1.45)
		_touch_look = Vector2.ZERO

	rotation.y = yaw
	_head.rotation.x = pitch

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 22.0) * delta

	var wish := Vector3.ZERO
	if input_enabled:
		var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if _touch_move != Vector2.ZERO:
			dir = _touch_move
		wish = (transform.basis * Vector3(dir.x, 0.0, dir.y))
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
		if Input.is_action_just_pressed("move_jump") and is_on_floor():
			velocity.y = JUMP_SPEED

	var stick_run := _touch_move.length() >= TOUCH_SPRINT_AT
	var running := Input.is_action_pressed("move_sprint") or stick_run
	var speed := SPRINT_SPEED if (input_enabled and running) else WALK_SPEED
	var target := wish * speed
	var rate := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target.x, rate * delta * 10.0)
	velocity.z = move_toward(velocity.z, target.z, rate * delta * 10.0)

	move_and_slide()

	# Head bob, scaled by actual ground speed so it stops when you do.
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 0.4:
		_bob += delta * planar * 1.5
		_head.position.y = EYE_HEIGHT + sin(_bob * 2.0) * 0.035
		_head.rotation.z = sin(_bob) * 0.006
	else:
		_bob = 0.0
		_head.position.y = lerpf(_head.position.y, EYE_HEIGHT, delta * 8.0)
		_head.rotation.z = lerpf(_head.rotation.z, 0.0, delta * 8.0)

	_scan_target()


## Finds the worker the player is looking at, so pressing talk opens the right
## conversation. Workers carry an Area3D on layer 4.
func _scan_target() -> void:
	var found: Node = null
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 4)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.has("collider"):
		var c: Node = hit["collider"]
		found = c.get_parent() if c.get_parent() != null else c
	if found != _target:
		_target = found
		looked_at.emit(found)


func looked_at_worker() -> Node:
	return _target


func eye_position() -> Vector3:
	return camera.global_position
