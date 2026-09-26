extends Node
class_name LookTest
## Mouse-look has to work before the pointer is locked.
##
## The grab is asked for in _ready, which a browser refuses and which a
## desktop window that is not yet key sometimes ignores. WASD never needed
## that grab, so the game walked and the camera stayed put. This feeds the
## player the same motion events the window would, with the cursor still
## visible, and checks the heading actually changes — and that being dropped
## onto the ground once the town has meshed does not throw that heading away.
##
## Run with:  godot --path . -- --looktest

var _fails: Array[String] = []


func _ready() -> void:
	var player := Player.new()
	add_child(player)
	# The deferred grab from _ready would hide the cursor again before the
	# assertion. Looking has to stand on its own, with the pointer free.
	player._want_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame

	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fails.append("cursor was locked before any gesture; the test cannot see the startup case")

	var yaw0 := player.yaw
	var pitch0 := player.pitch
	# Straight into the player. Headless rewrites a parsed motion's relative
	# from the window's mouse position, which is not the delta we asked for.
	_feed(player, Vector2(40, -25))
	var want_yaw := yaw0 - 40.0 * Player.MOUSE_SENS
	var want_pitch := pitch0 + 25.0 * Player.MOUSE_SENS
	if absf(player.yaw - want_yaw) > 1e-5:
		_fails.append("unlocked mouse-right yaw %.5f, wanted %.5f" % [player.yaw, want_yaw])
	if absf(player.pitch - want_pitch) > 1e-5:
		_fails.append("unlocked mouse-up pitch %.5f, wanted %.5f" % [player.pitch, want_pitch])

	# And through the real input buffer, cursor still visible: the old code
	# dropped this entirely. The delta itself is the window's, so only the
	# fact of a turn, and the clamp on it, are meaningful here.
	var piped := player.yaw
	_motion(Vector2(40, -25))
	var piped_turn := absf(player.yaw - piped)
	if piped_turn < 1e-5:
		_fails.append("a visible cursor delivered no look through the input buffer")
	# Headless may flush more than the event we parsed. Unclamped, a warp is
	# tens of radians; clamped, a handful of events stays a small turn.
	if piped_turn > 2.0:
		_fails.append("unlocked input-buffer look spun %.3f rad" % piped_turn)

	var before := player.yaw
	_feed(player, Vector2(10000, 0))
	var turned := before - player.yaw
	var cap := Player._FREE_LOOK_CLAMP * Player.MOUSE_SENS
	if absf(turned - cap) > 1e-4:
		_fails.append("an unlocked spike turned %.4f rad, the clamp is %.4f" % [turned, cap])

	player.set_input_enabled(false)
	before = player.yaw
	var pitch_held := player.pitch
	_feed(player, Vector2(30, -30))
	if not is_equal_approx(player.yaw, before) or not is_equal_approx(player.pitch, pitch_held):
		_fails.append("look moved while input was disabled")

	# set_input_enabled(false) releases the cursor. Turning it back on asks
	# for the grab; park that so the facing check below is still unlocked.
	player.set_input_enabled(true)
	player._want_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	player.yaw = 1.15
	player.pitch = -0.35
	player.global_position = Vector3(8, 2, -4)
	player.reseat(3.5)
	if player.global_position.distance_to(Vector3(8, 3.5, -4)) > 0.001:
		_fails.append("reseat moved the body off its column: %s" % player.global_position)
	if absf(player.yaw - 1.15) > 1e-5 or absf(player.pitch - (-0.35)) > 1e-5:
		_fails.append("reseat discarded the look (yaw %.3f pitch %.3f)" % [player.yaw, player.pitch])
	if absf(player.rotation.y - player.yaw) > 1e-5 or absf(player._head.rotation.x - player.pitch) > 1e-5:
		_fails.append("reseat kept the numbers but did not turn the rig")

	player.pitch = 0.4
	player.teleport(Vector3(1, 2, 3), 0.2)
	if absf(player.pitch) > 1e-5 or absf(player.yaw - 0.2) > 1e-5:
		_fails.append("teleport without a pitch did not level the head")
	if player.global_position.distance_to(Vector3(1, 2, 3)) > 0.001:
		_fails.append("teleport missed its target: %s" % player.global_position)

	# One physics step publishes yaw onto the body. Mouse-right must turn
	# the facing toward world +x, which is the same axis strafe-right uses.
	player.yaw = 0.0
	player.pitch = 0.0
	player.rotation.y = 0.0
	await get_tree().physics_frame
	_feed(player, Vector2(80, 0))
	await get_tree().physics_frame
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var expected := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	if fwd.dot(expected) < 0.999:
		_fails.append("facing %s disagrees with yaw %.3f (expected %s)" % [fwd, player.yaw, expected])
	if player.yaw >= 0.0 or fwd.x <= 0.05:
		_fails.append("mouse-right should face toward world +x, yaw %.3f fwd %s" % [player.yaw, fwd])

	# A locked pointer must not hit the free-cursor clamp. Headless refuses
	# the grab, so this goes through the same function the captured branch
	# calls after it has decided not to clamp.
	before = player.yaw
	player._apply_look_pixels(Vector2(400, 0))
	var raw := before - player.yaw
	if absf(raw - 400.0 * Player.MOUSE_SENS) > 1e-4:
		_fails.append("raw look was clamped or ignored, delta %.4f" % raw)

	player.pitch = 1.4
	player._want_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_feed(player, Vector2(0, -10000))
	if absf(player.pitch - 1.45) > 1e-4:
		_fails.append("pitch escaped its limit: %.3f" % player.pitch)

	if _fails.is_empty():
		print("[look] mouse-look works before the pointer is locked")
		get_tree().quit(0)
	else:
		for f: String in _fails:
			push_error("[look] " + f)
			print("[look] FAIL ", f)
		get_tree().quit(1)


func _feed(body: Player, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	body._unhandled_input(ev)


func _motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
