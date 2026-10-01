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
var inventory: InventoryScreen
var hud: Hud

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
var _last_target: Node = null
var _last_armed := false


func _ready() -> void:
	layer = 5
	_pad = Control.new()
	_pad.name = "Pad"
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	# Rotating the phone moves every button, and redraws are event-driven.
	_pad.resized.connect(_pad.queue_redraw)
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
	out["bag"] = {
		"centre": Vector2(s.x - 56.0 * u, 122.0 * u), "radius": 28.0 * u,
		"action": &"inventory", "label": "BAG",
	}
	# One full-screen view at a time. While either is up, the only button that
	# still does anything is the one that closes it again — everything else
	# would be a tap through a panel at the world underneath.
	if _map_open():
		return {"map": out["map"]}
	if _inventory_open():
		return {"bag": out["bag"]}
	# Down the right edge under MAP and BAG. The top-left corner is the HUD's
	# clock and crew cards, and buttons there sat underneath them.
	out["chat"] = {
		"centre": Vector2(s.x - 56.0 * u, 188.0 * u), "radius": 28.0 * u,
		"action": &"chat", "label": "CHAT",
	}
	out["menu"] = {
		"centre": Vector2(s.x - 56.0 * u, 254.0 * u), "radius": 28.0 * u,
		"action": &"menu", "label": "ESC",
	}
	# Photo mode (PhotoMode listens for the `photo` action).
	out["photo"] = {
		"centre": Vector2(s.x - 56.0 * u, 320.0 * u), "radius": 28.0 * u,
		"action": &"photo", "label": "SNAP",
	}
	out["talk"] = {
		"centre": Vector2(s.x - 100.0 * u, s.y - 108.0 * u), "radius": 54.0 * u,
		"action": &"talk", "label": "TALK",
	}
	out["jump"] = {
		"centre": Vector2(s.x - 212.0 * u, s.y - 74.0 * u), "radius": 38.0 * u,
		"action": &"move_jump", "label": "JUMP",
	}
	# The villager card (Tab / V on a keyboard), only while somebody is under
	# the crosshair or the card is already up to be closed again.
	if _has_target() or _card_open():
		out["info"] = {
			"centre": Vector2(s.x - 196.0 * u, s.y - 176.0 * u), "radius": 28.0 * u,
			"action": &"", "label": "INFO",
		}
	# The gun is a mouse button on a desktop. Nobody is holding one until they
	# have been handed one at the armoury, so until then there is nothing to
	# fire and no reason to crowd the right thumb.
	if _armed():
		out["fire"] = {
			"centre": Vector2(s.x - 100.0 * u, s.y - 248.0 * u), "radius": 46.0 * u,
			"action": &"fire", "label": "FIRE",
		}
		out["swap"] = {
			"centre": Vector2(s.x - 186.0 * u, s.y - 284.0 * u), "radius": 26.0 * u,
			"action": &"swap_weapon", "label": "SWAP",
		}
	return out


func _has_target() -> bool:
	return player != null and player.looked_at_worker() != null


func _card_open() -> bool:
	return hud != null and hud.villager_card != null and hud.villager_card.open


func _armed() -> bool:
	if player == null or player.warfare == null:
		return false
	return str(player.warfare.call("player_weapon")) != ""


func _map_open() -> bool:
	return map != null and map.open


func _inventory_open() -> bool:
	return inventory != null and inventory.open


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
		if hit == "info":
			# Not an action of its own: the keyboard reaches it through two
			# raw keys, so the button goes straight to the HUD instead.
			if hud != null:
				hud.toggle_card()
		else:
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
		if _button_touch[index] != &"":
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
		# The talk button lights up when the player is looking at somebody, so
		# the HUD has to repaint when that changes. Nothing else about it moves
		# on its own, and a phone should not be redrawing a static overlay
		# sixty times a second.
		var target := player.looked_at_worker()
		var armed := _armed()
		if target != _last_target or armed != _last_armed:
			_last_target = target
			_last_armed = armed
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
	var font := UiTheme.font(800)
	var has_target := _has_target()

	if _stick_touch != -1:
		var r := STICK_RADIUS * _unit
		var tilt := _stick_vector()
		var knob := _stick_origin + tilt * r
		_pad.draw_circle(_stick_origin, r, Color(0.07, 0.06, 0.05, 0.28))
		_ring(_stick_origin, r, Color(UiTheme.GOLD, 0.35), 2.0 * _unit)
		_pad.draw_circle(knob, 26.0 * _unit, Color(UiTheme.PARCHMENT, 0.30))
		_ring(knob, 26.0 * _unit, Color(UiTheme.PARCHMENT, 0.75), 2.0 * _unit)
		if tilt.length() >= SPRINT_AT:
			_ring(_stick_origin, r + 6.0 * _unit, Color(UiTheme.ACCENT, 0.7),
				2.5 * _unit)

	var held := _button_touch.values()
	var buttons := _buttons()
	for key: String in buttons:
		var b: Dictionary = buttons[key]
		var radius := float(b["radius"])
		var down: bool = b["action"] in held
		var lit: bool = down or (key == "talk" and has_target) or (key == "info" and _card_open())
		var fill := Color(0.075, 0.062, 0.05, 0.50)
		if down:
			fill = Color(UiTheme.GOLD, 0.45)
		elif key == "talk" and has_target:
			fill = Color(UiTheme.ACCENT, 0.32)
		_pad.draw_circle(b["centre"] + Vector2(0, 2.0 * _unit), radius, Color(0, 0, 0, 0.22))
		_pad.draw_circle(b["centre"], radius, fill)
		_ring(b["centre"], radius, Color(UiTheme.GOLD, 0.95 if lit else 0.55),
			2.0 * _unit)
		var fs := int(round(15.0 * _unit))
		_pad.draw_string(font, b["centre"] + Vector2(-radius, fs * 0.36),
			str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs,
			Color(UiTheme.PARCHMENT, 1.0 if lit else 0.75))


func _ring(centre: Vector2, radius: float, colour: Color, width: float) -> void:
	_pad.draw_arc(centre, radius, 0.0, TAU, 48, colour, width, true)
