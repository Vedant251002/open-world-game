extends Node3D
## Autonomous construction worker (GOAP-lite):
## idle -> pick plot -> walk there -> scaffold -> build over time -> done.
## Visible autonomy: status text above head the whole time.

const SPEED := 3.2
const BUILD_TIME := 9.0

enum State { IDLE, WALKING, BUILDING, DONE }

var state: State = State.IDLE
var target: Vector3 = Vector3.ZERO
var order: Dictionary = {}
var building_path := ""
var sign_text := ""
var gen_ref: Node3D = null
var _t := 0.0
var _scaffold: MeshInstance3D = null
var _progress_label: Label3D = null
var _status_label: Label3D = null
var _building: Node3D = null
static var _worker_idx := 0


func assign(ord: Dictionary, pos: Vector3, bldg_path: String, sign_name: String) -> void:
	order = ord
	target = pos
	building_path = bldg_path
	sign_text = sign_name
	state = State.WALKING
	_set_status("On it, my liege!")


func _ready() -> void:
	var idx := (_worker_idx % 5) + 1
	_worker_idx += 1
	var ch: Node3D = load("res://assets/chars/char_%d.glb" % idx).instantiate()
	ch.position = Vector3(0, 0.62, 0)
	ch.scale = Vector3.ONE * 0.55
	add_child(ch)
	_play(ch, "walk")

	_status_label = Label3D.new()
	_status_label.font_size = 34
	_status_label.pixel_size = 0.011
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.modulate = Color("#ffe14d")
	_status_label.outline_size = 6
	_status_label.position = Vector3(0, 2.35, 0)
	_status_label.no_depth_test = true
	add_child(_status_label)

	var body := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	body.add_child(cs)
	add_child(body)


func _play(ch: Node, key: String) -> void:
	var ap := _find_anim(ch)
	if ap == null:
		return
	for a in ap.get_animation_list():
		if key in a.to_lower():
			var anim: Animation = ap.get_animation(a)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(a)
			return
	ap.play(ap.get_animation_list()[0])


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _set_status(s: String) -> void:
	if _status_label:
		_status_label.text = s


func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			pass
		State.WALKING:
			var to := target - global_position
			to.y = 0.0
			if to.length() < 1.2:
				_arrive()
				return
			global_position += to.normalized() * SPEED * delta
			rotation.y = atan2(to.x, to.z)
			_set_status("Heading to the site (%dm)" % int(to.length()))
		State.BUILDING:
			_t += delta
			var pct := clampf(_t / BUILD_TIME, 0.0, 1.0)
			if _progress_label:
				_progress_label.text = "%s — %d%%" % [sign_text, int(pct * 100)]
			if _scaffold:
				_scaffold.material_override.set("albedo_color", Color("#ffe14d").darkened(0.55 - 0.25 * pct))
			if _building:
				var s := 0.05 + 0.95 * pct
				_building.scale = Vector3.ONE * 12.0 * s
			if pct >= 1.0:
				_finish()


func _arrive() -> void:
	state = State.BUILDING
	_t = 0.0
	_set_status("Building!")
	_play(get_child(0), "idle")

	# scaffold box over the site
	_scaffold = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(13, 17, 13)
	_scaffold.mesh = bm
	_scaffold.position = target + Vector3(0, 8.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#7a6a2a")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.35
	_scaffold.material_override = m
	add_child(_scaffold)

	_progress_label = Label3D.new()
	_progress_label.font_size = 34
	_progress_label.pixel_size = 0.012
	_progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_progress_label.modulate = Color("#39ff88")
	_progress_label.outline_size = 6
	_progress_label.position = Vector3(0, 17.5, 0)
	_progress_label.no_depth_test = true
	add_child(_progress_label)

	# the actual building grows from the ground
	_building = load(building_path).instantiate()
	_building.position = Vector3.ZERO
	_building.scale = Vector3.ONE * 0.05
	get_parent().add_child(_building)
	_building.global_position = target


func _finish() -> void:
	state = State.DONE
	_set_status("Done! %s is ready." % sign_text.capitalize())
	if _scaffold:
		_scaffold.queue_free()
	if _progress_label:
		_progress_label.queue_free()
	# neon sign with the ordered name
	if gen_ref and gen_ref.has_method("_neon"):
		gen_ref._neon(gen_ref, sign_text.to_upper(), _building.global_position + Vector3(0, 0, 7.0) + Vector3(0, 12.0, 0), 0.0, "#ff2d95")
