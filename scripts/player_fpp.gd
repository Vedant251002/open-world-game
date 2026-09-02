extends CharacterBody3D
## First-person player controller (the king).
## WASD + mouse look, sprint, jump. Input actions are registered from code.

const EYE_HEIGHT := 1.62
const WALK_SPEED := 4.6
const SPRINT_SPEED := 8.4
const ACCEL := 34.0
const FRICTION := 14.0
const JUMP_VELOCITY := 4.9
const GRAVITY := 15.0

var camera: Camera3D
var autopilot := false   # true during automated capture runs
var frozen := false      # true = hover in place (aerial shots)
var ui_block := false    # true while typing in the command console

var _yaw := 0.0
var _pitch := 0.0
var _bob_t := 0.0


func _ready() -> void:
	_register_action("move_forward", KEY_W)
	_register_action("move_back", KEY_S)
	_register_action("move_left", KEY_A)
	_register_action("move_right", KEY_D)
	_register_action("jump", KEY_SPACE)
	_register_action("sprint", KEY_SHIFT)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.75
	shape.shape = capsule
	add_child(shape)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 1200.0
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(camera)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_state(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	global_position = pos
	_yaw = deg_to_rad(yaw_deg)
	_pitch = deg_to_rad(pitch_deg)
	rotation.y = _yaw
	camera.rotation.x = _pitch
	velocity = Vector3.ZERO


func _register_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if autopilot:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch -= event.relative.y * 0.0022
		_pitch = clamp(_pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation.y = _yaw
		camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if is_on_floor() and not autopilot and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if not autopilot and not ui_block:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var wish := Vector3.ZERO
	if input_dir.length() > 0.1:
		wish = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target := wish * target_speed
	var accel := ACCEL if wish.length() > 0.1 else FRICTION
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	move_and_slide()

	# subtle head bob
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob_t += delta * hspeed * 1.6
		camera.position.y = EYE_HEIGHT + sin(_bob_t * 2.0) * 0.035
	else:
		camera.position.y = EYE_HEIGHT
