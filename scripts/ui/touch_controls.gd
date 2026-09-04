extends CanvasLayer
class_name TouchControls
## The thumb HUD.
##
## DELEGATE is a keyboard game — WASD, mouse-look, E to talk — and none of that
## survives contact with a phone. iPhone Safari has no pointer lock at all, so
## on touch the player never captures the mouse and looking around has to come
## from a drag instead.
##
## Two analogue inputs are handed to the Player directly, because they are
## continuous and the action system has nowhere to put them: a left-thumb stick
## for movement and a right-thumb drag for the camera. Everything discrete —
## talk, jump, map, menu — is synthesised as an InputEventAction on the existing
## bindings, so every other script in the game keeps asking `is_action_pressed`
## and never learns that a finger was involved.
##
## The stick is dynamic: it appears wherever the left thumb lands rather than at
## a fixed spot, because on a phone held in two hands the thumb is never twice
## in the same place. Pushing it to the rim sprints, which saves a button.

const STICK_RADIUS := 96.0        ## travel to full tilt, in canvas units
const STICK_DEADZONE := 0.14
const SPRINT_AT := Player.TOUCH_SPRINT_AT   ## stick tilt that counts as a run
const LOOK_SENS := 0.0052         ## radians per canvas unit of drag

var player: Player
var map: MapScreen

## Up from boot on a handheld. Elsewhere it stays out of the way until a real
## finger lands, which covers both the touchscreen laptop that should keep its
## mouse and the mobile browser that reports no touchscreen until first use.
var active := false

var _pad: Control
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_point := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _button_touch: Dictionary = {}    ## touch index -> action name
var _held: Dictionary = {}            ## action name -> frames held
var _wants_release: Dictionary = {}   ## action name -> true
var _unit := 1.0


func _ready() -> void:
	layer = 5
	_pad = Control.new()
	_pad.name = "Pad"
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	active = Platform.is_handheld()
	_pad.visible = active


# ------------------------------------------------------------------- geometry

func _size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Buttons scale with the short edge so they stay thumb-sized on a phone and do
## not become absurd on a tablet.
func _refresh_unit() -> void:
	var s := _size()
	_unit = clampf(minf(s.x, s.y) / 720.0, 0.62, 1.5)


## name -> {centre, radius, action, label, lit_when_target}
func _buttons() -> Dictionary:
	var s := _size()
	var u := _unit
	var out := {
		"map": {
			"centre": Vector2(s.x - 56.0 * u, 56.0 * u), "radius": 28.0 * u,
			"action": &"map", "label": "MAP",
		},
	}
	if _map_open():
		return out
	out["menu"] = {
		"centre": Vector2(56.0 * u, 56.0 * u), "radius": 28.0 * u,
		"action": &"menu", "label": "ESC",
	}
	out["talk"] = {
		"centre": Vector2(s.x - 100.0 * u, s.y - 108.0 * u), "radius": 54.0 * u,
		"action": &"talk", "label": "TALK",
	}
	out["jump"] = {
		"centre": Vector2(s.x - 212.0 * u, s.y - 74.0 * u), "radius": 38.0 * u,
		"action": &"move_jump", "label": "JUMP",
	}
	return out


func _map_open() -> bool:
	return map != null and map.open


func _button_at(pos: Vector2, buttons: Dictionary) -> String:
	for key: String in buttons:
		var b: Dictionary = buttons[key]
		if pos.distance_to(b["centre"]) <= float(b["radius"]) * 1.12:
			return key
	return ""


## The left thumb owns the lower-left corner of the screen; the right thumb gets
## everything else that is not a button.
func _in_stick_zone(pos: Vector2) -> bool:
	var s := _size()
	return pos.x < s.x * 0.45 and pos.y > s.y * 0.18


# ---------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not active:
			active = true
			_pad.visible = true
	if not active:
		return

	_refresh_unit()

	var used := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		used = _press(t.index, t.position) if t.pressed else _release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		used = _drag(d.index, d.position)
	if used:
		get_viewport().set_input_as_handled()


## Returns whether the HUD took the touch. Anything it declines is left alone
## so the rest of the game still sees it — with the map open that is how
## panning keeps working while the map button stays live on top of it.
func _press(index: int, pos: Vector2) -> bool:
	var buttons := _buttons()
	var hit := _button_at(pos, buttons)
	if hit != "":
		var b: Dictionary = buttons[hit]
		_button_touch[index] = b["action"]
		_begin(b["action"])
		_pad.queue_redraw()
		return true
	if _map_open():
		return false
	if _stick_touch == -1 and _in_stick_zone(pos):
		_stick_touch = index
		_stick_origin = pos
		_stick_point = pos
		_pad.queue_redraw()
		return true
	if _look_touch == -1:
		_look_touch = index
		_look_last = pos
		return true
	return false


func _drag(index: int, pos: Vector2) -> bool:
	if index == _stick_touch:
		_stick_point = pos
		_pad.queue_redraw()
		return true
	if index == _look_touch and player != null:
		player.add_touch_look((pos - _look_last) * LOOK_SENS)
		_look_last = pos
		return true
	return false


func _release(index: int) -> bool:
	var used := false
	if _button_touch.has(index):
		_wants_release[_button_touch[index]] = true
		_button_touch.erase(index)
		_pad.queue_redraw()
		used = true
	if index == _stick_touch:
		_stick_touch = -1
		_pad.queue_redraw()
		used = true
	if index == _look_touch:
		_look_touch = -1
		used = true
	return used


# -------------------------------------------------------------------- actions

## Synthesised actions are deferred and always held for at least one whole
## frame. Firing one inline would re-enter input dispatch from inside it, and a
## tap quick enough to press and release within a single frame would otherwise
## never be seen by `is_action_just_pressed`.
func _begin(action: StringName) -> void:
	if _held.has(action):
		return
	_held[action] = 0
	_wants_release.erase(action)
	_fire.call_deferred(action, true)


func _fire(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(_delta: float) -> void:
	if not active:
		return
	for action: StringName in _held.keys():
		_held[action] = int(_held[action]) + 1
		if _wants_release.has(action) and int(_held[action]) >= 2:
			_fire(action, false)
			_held.erase(action)
			_wants_release.erase(action)

	if player != null:
		player.set_touch_move(_stick_vector())
	_pad.queue_redraw()


func _stick_vector() -> Vector2:
	if _stick_touch == -1:
		return Vector2.ZERO
	var v := (_stick_point - _stick_origin) / (STICK_RADIUS * _unit)
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v


# -------------------------------------------------------------------- drawing

func _draw_pad() -> void:
	if not active:
		return
	_refresh_unit()
	var font := ThemeDB.fallback_font
	var has_target := player != null and player.looked_at_worker() != null

	if _stick_touch != -1:
		var r := STICK_RADIUS * _unit
		var tilt := _stick_vector()
		var knob := _stick_origin + tilt * r
		_ring(_stick_origin, r, Color(1, 1, 1, 0.18), 3.0 * _unit)
		_pad.draw_circle(knob, 26.0 * _unit, Color(1, 1, 1, 0.22))
		_ring(knob, 26.0 * _unit, Color(1, 1, 1, 0.5), 2.0 * _unit)
		if tilt.length() >= SPRINT_AT:
			_ring(_stick_origin, r + 6.0 * _unit, Color(1, 0.86, 0.5, 0.55),
				2.0 * _unit)

	var held := _button_touch.values()
	for key: String in _buttons():
		var b: Dictionary = _buttons()[key]
		var radius := float(b["radius"])
		var down: bool = b["action"] in held
		var lit: bool = down or (key == "talk" and has_target)
		var fill := Color(0, 0, 0, 0.28)
		if down:
			fill = Color(1, 1, 1, 0.22)
		elif key == "talk" and has_target:
			fill = Color(1, 0.86, 0.5, 0.22)
		_pad.draw_circle(b["centre"], radius, fill)
		_ring(b["centre"], radius, Color(1, 1, 1, 0.85 if lit else 0.38),
			2.0 * _unit)
		var fs := int(round(15.0 * _unit))
		_pad.draw_string(font, b["centre"] + Vector2(-radius, fs * 0.36),
			str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs,
			Color(1, 1, 1, 0.92 if lit else 0.55))


func _ring(centre: Vector2, radius: float, colour: Color, width: float) -> void:
	_pad.draw_arc(centre, radius, 0.0, TAU, 48, colour, width, true)
