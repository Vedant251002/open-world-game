extends Node3D
class_name FpHands
## The player's own forearms, in the bottom corners of the view.
##
## Built from the same little boxes as every villager (BoxKit.Batch, one mesh
## per arm) so the player reads as one of the cast rather than a floating
## camera. Everything here is a rotation or an offset on two nodes: walking
## bobs them, turning drags them a moment behind the view, standing still lets
## them breathe, and a few gestures (wave, reach, recoil) answer what the
## player just did.
##
## The rig is modelled at full size and then scaled by SCALE, which puts the
## hands about a quarter of a metre from the eye. That is inside the player's
## capsule (0.32 m), so walking face-first into a wall or a cupboard can never
## push a hand through it; perspective makes them look exactly as big as before.

const SCALE := 0.45
## Where each shoulder-end of the sleeve sits, in unscaled camera space.
const REST_R := Vector3(0.40, -0.40, -0.14)
const REST_L := Vector3(-0.40, -0.40, -0.14)
## Turned in toward the middle and tipped up a little: a relaxed carry.
const ROT_R := Vector3(0.16, 0.10, 0.12)
const ROT_L := Vector3(0.16, -0.10, -0.12)

var player: Player
var skin := Color("#a8754f")
var sleeve := Color("#56627a")

var _arm_r: Node3D
var _arm_l: Node3D
var _bob := 0.0
var _t := 0.0
var _sway := Vector2.ZERO          ## lags the view when it turns
var _last_look := Vector2.ZERO
var _lower := 0.0                  ## 1 = dropped out of sight (a menu has the pointer)
var _run := 0.0
var _air := 0.0
var _jolt := 0.0
## The current gesture and how far through it we are (0..1).
var _gesture := ""
var _g := 1.0


func setup(p: Player) -> void:
	player = p
	name = "FpHands"
	scale = Vector3.ONE * SCALE
	var batch := BoxKit.Batch.new()
	_arm_r = _arm(batch, 1.0)
	_arm_l = _arm(batch, -1.0)
	for mi: MeshInstance3D in batch.flush():
		# No shadow: from the camera's own position it would only ever fall as
		# a dark smear on the ground in front of the player.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
	_last_look = Vector2(player.yaw, player.pitch)
	set_process(true)


## One forearm reaching forward along -Z from its pivot: sleeve, turned-back
## cuff, a leather wrist band, the forearm, the hand and a thumb on the inside.
func _arm(batch: BoxKit.Batch, side: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var cuff := sleeve.darkened(0.22)
	var band := Color("#5a3d27")
	var w := 0.116
	batch.box(n, Vector3(-w * 0.5, -w * 0.5, -0.30), Vector3(w, w, 0.34), sleeve)
	batch.box(n, Vector3(-0.064, -0.064, -0.33), Vector3(0.128, 0.128, 0.05), cuff)
	batch.box(n, Vector3(-0.05, -0.05, -0.44), Vector3(0.10, 0.10, 0.12), skin, 0.6)
	batch.box(n, Vector3(-0.054, -0.054, -0.415), Vector3(0.108, 0.108, 0.035), band, 0.7)
	# The hand: a little flatter and wider than the wrist, knuckles a shade lighter.
	batch.box(n, Vector3(-0.056, -0.045, -0.535), Vector3(0.112, 0.085, 0.10), skin.lightened(0.03), 0.6)
	batch.box(n, Vector3(-0.056, -0.045, -0.55), Vector3(0.112, 0.07, 0.02), skin.darkened(0.06), 0.6)
	batch.box(n, Vector3(-side * 0.075 - 0.0125, -0.035, -0.50), Vector3(0.025, 0.045, 0.06), skin, 0.6)
	return n


func wave() -> void:
	_start("wave")


func reach() -> void:
	_start("reach")


## Recoil or a blast nearby (Player.kick).
func jolt(amount: float) -> void:
	_jolt = maxf(_jolt, clampf(amount, 0.0, 1.0))


func _start(g: String) -> void:
	_gesture = g
	_g = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	var vel := player.velocity
	var planar := Vector2(vel.x, vel.z).length()
	var grounded := player.is_on_floor()
	# Walk bob, a figure of eight that stops when you do.
	if grounded and planar > 0.4:
		_bob += delta * planar * 1.55
	var amp := clampf(planar / Player.SPRINT_SPEED, 0.0, 1.0) if grounded else 0.0
	_run = lerpf(_run, 1.0 if planar > Player.WALK_SPEED + 0.6 and grounded else 0.0, delta * 6.0)
	_air = lerpf(_air, 0.0 if grounded or player.in_water else clampf(-vel.y * 0.08, -0.6, 1.0), delta * 6.0)
	var want_low := 0.0 if player.input_enabled else 1.0
	_lower = move_toward(_lower, want_low, delta * 3.5)
	visible = _lower < 0.999

	# Sway: the hands trail the view by a fraction of how fast it is turning.
	var look := Vector2(player.yaw, player.pitch)
	var d := look - _last_look
	d.x = wrapf(d.x, -PI, PI)
	_last_look = look
	var target := Vector2(clampf(d.x * 2.6, -0.06, 0.06), clampf(-d.y * 2.6, -0.06, 0.06))
	_sway = _sway.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	_jolt = move_toward(_jolt, 0.0, delta * 3.0)
	if _g < 1.0:
		_g = minf(_g + delta / (0.9 if _gesture == "wave" else 0.55), 1.0)

	var breathe := sin(_t * 1.7) * 0.006
	var bx := sin(_bob) * 0.022 * amp
	var by := -absf(cos(_bob)) * 0.026 * amp
	var common := Vector3(bx - _sway.x, by + breathe + _sway.y + _air * 0.05 - _run * 0.04
		- _lower * 0.55, _jolt * 0.10)
	_pose(_arm_r, REST_R, ROT_R, common, 1.0)
	_pose(_arm_l, REST_L, ROT_L, Vector3(-bx * 0.8 - _sway.x, by * 0.9 + breathe + _sway.y
		+ _air * 0.05 - _run * 0.04 - _lower * 0.55, _jolt * 0.06), -1.0)


func _pose(arm: Node3D, rest: Vector3, rot: Vector3, off: Vector3, side: float) -> void:
	var pos := rest + off
	var r := rot
	# Running pumps the arms against each other.
	r.x += sin(_bob * (side) + (0.0 if side > 0.0 else PI)) * 0.10 * _run
	r.x += _jolt * 0.35
	if _g < 1.0:
		var e := sin(_g * PI)            # out and back
		match _gesture:
			"wave":
				if side > 0.0:
					pos += Vector3(-0.06, 0.24, -0.04) * e
					r.x += 0.85 * e
					r.z += sin(_g * TAU * 2.0) * 0.25 * e
			"reach":
				pos += Vector3(-0.05 * side, -0.04, -0.14) * e
				r.x -= 0.25 * e
	arm.position = pos
	arm.rotation = r
