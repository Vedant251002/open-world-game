extends Node3D
## Pedestrian: walks a loop around a block's sidewalk ring, animated.

var ring: Array = []
var _i := 0
var _dir := 1
var _speed := 1.4
static var _idx := 0


func setup_from_graph(gen: Node3D, i: int) -> void:
	if gen.ped_rings.is_empty():
		return
	ring = gen.ped_rings[(i * 5 + 2) % gen.ped_rings.size()]
	_i = i % ring.size()
	_dir = 1 if i % 2 == 0 else -1
	_speed = 1.1 + (i % 4) * 0.25


func _ready() -> void:
	var idx := (_idx % 5) + 1
	_idx += 1
	var ch: Node3D = load("res://assets/chars/char_%d.glb" % idx).instantiate()
	ch.position = Vector3(0, 0.62, 0)
	ch.scale = Vector3.ONE * 0.55
	add_child(ch)

	var body := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	body.add_child(cs)
	add_child(body)

	var ap := _find_anim(ch)
	if ap:
		var chosen := ""
		for a in ap.get_animation_list():
			if "walk" in a.to_lower():
				chosen = a
				break
		if chosen == "":
			for a in ap.get_animation_list():
				if "run" in a.to_lower():
					chosen = a
					break
		if chosen == "":
			chosen = ap.get_animation_list()[0]
		var anim: Animation = ap.get_animation(chosen)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		ap.play(chosen)

	if not ring.is_empty():
		global_position = ring[_i]


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _physics_process(delta: float) -> void:
	if ring.is_empty():
		return
	var target: Vector3 = ring[_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.6:
		_i = wrapi(_i + _dir, 0, ring.size())
		target = ring[_i]
		to = target - global_position
		to.y = 0.0
	if to.length() > 0.001:
		var step := to.normalized() * _speed * delta
		if step.length() > to.length():
			global_position = target
		else:
			global_position += step
		var yaw := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, yaw, 10.0 * delta)
