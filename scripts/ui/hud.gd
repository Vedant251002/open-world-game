extends CanvasLayer
class_name Hud
## The whole interface: a crosshair, a line to type into, and the assumptions.
##
## Design pillar P1 says language is the only verb, so there is no build menu,
## no palette and no placement cursor — the only control that makes anything
## happen is a text field. Pillar P3 says failure must be legible, which is why
## the assumptions panel is not a popup you dismiss: it stays on screen while
## the worker is walking away, so the building you get is one you could have
## predicted before it existed.

signal instruction_given(worker: Worker, text: String)
signal answer_given(worker: Worker, text: String)
signal harvest_wanted(tile: Vector2i)

const BG := Color(0.06, 0.055, 0.05, 0.82)
const INK := Color(0.94, 0.92, 0.87)
const DIM := Color(0.72, 0.70, 0.66)
const WARN := Color(1.0, 0.86, 0.52)

var player: Player
var crew: Crew
var clock: GameClock
var town: Town
var farm: Farm

var _target: Worker = null
var _crop: Node3D = null
var _larder: Label
var _typing_for: Worker = null
var _root: Control
var _prompt: Label
var _clockline: Label
var _crewbox: VBoxContainer
var _bar: PanelContainer
var _barlabel: Label
var _entry: LineEdit
var _assume: PanelContainer
var _assume_title: Label
var _assume_body: Label
var _toast: Label
var _toast_left := 0.0


func setup(p: Player, c: Crew, gc: GameClock, t: Town) -> void:
	player = p
	crew = c
	clock = gc
	town = t
	layer = 10
	_build()
	player.looked_at.connect(_on_looked_at)
	set_process(true)
	set_process_unhandled_input(true)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(_make_crosshair())

	_clockline = _label("", 18, INK)
	_clockline.position = Vector2(22, 18)
	_root.add_child(_clockline)

	_larder = _label("", 15, DIM)
	_larder.position = Vector2(22, 42)
	_root.add_child(_larder)

	_crewbox = VBoxContainer.new()
	_crewbox.position = Vector2(22, 70)
	_crewbox.add_theme_constant_override("separation", 3)
	_root.add_child(_crewbox)
	for _i in 3:
		_crewbox.add_child(_label("", 15, DIM))

	_prompt = _label("", 19, INK)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -420
	_prompt.offset_right = 420
	_prompt.offset_top = -132
	_prompt.offset_bottom = -104
	_root.add_child(_prompt)

	_toast = _label("", 16, WARN)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -460
	_toast.offset_right = 460
	_toast.offset_top = -166
	_toast.offset_bottom = -142
	_root.add_child(_toast)

	_build_bar()
	_build_assumptions()
	# Belt and braces: anything added above that is not the text field must not
	# be able to claim the pointer.
	_ignore_mouse(_root)


static func _ignore_mouse(node: Node) -> void:
	for child: Node in node.get_children():
		if child is LineEdit:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)


## Every part of this HUD except the text field is there to be looked at, not
## clicked, so all of it ignores the mouse.
##
## This matters more than it sounds. A captured mouse reports its position at
## the centre of the screen, which is exactly where the crosshair is: a ColorRect
## defaults to MOUSE_FILTER_STOP, so the crosshair swallowed every mouse-motion
## event before _unhandled_input could see it and mouse-look stopped working
## entirely.
func _make_crosshair() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -3
	c.offset_top = -3
	c.offset_right = 3
	c.offset_bottom = 3
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.5)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	return c


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -430
	_bar.offset_right = 430
	_bar.offset_top = -96
	_bar.offset_bottom = -22
	_bar.add_theme_stylebox_override("panel", _panel_style())
	_bar.visible = false
	_root.add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_bar.add_child(col)

	_barlabel = _label("", 15, DIM)
	col.add_child(_barlabel)

	_entry = LineEdit.new()
	_entry.placeholder_text = "tell them what to build…"
	_entry.custom_minimum_size = Vector2(0, 34)
	_entry.add_theme_font_size_override("font_size", 18)
	_entry.text_submitted.connect(_on_submit)
	col.add_child(_entry)


func _build_assumptions() -> void:
	_assume = PanelContainer.new()
	_assume.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_assume.offset_left = -434
	_assume.offset_right = -20
	_assume.offset_top = 18
	_assume.offset_bottom = 200
	_assume.add_theme_stylebox_override("panel", _panel_style())
	_assume.visible = false
	_root.add_child(_assume)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_assume.add_child(col)
	_assume_title = _label("", 15, WARN)
	_assume_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assume_title.custom_minimum_size = Vector2(390, 0)
	col.add_child(_assume_title)
	_assume_body = _label("", 15, INK)
	_assume_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assume_body.custom_minimum_size = Vector2(390, 0)
	col.add_child(_assume_body)


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb


static func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------- runtime

## The look ray reads one layer, and both a worker and a ripe crop answer on
## it. Which one it is decides what [E] means.
func _on_looked_at(node: Node) -> void:
	_target = node as Worker
	_crop = null
	if _target == null and node is Node3D and (node as Node3D).has_meta("crop_tile"):
		_crop = node as Node3D


func _process(delta: float) -> void:
	if clock != null and town != null:
		_clockline.text = "%s   ·   %s" % [clock.clock_text(), town.stock_line()]
		var extra := ""
		if farm != null and farm.tile_count() > 0:
			extra = "   ·   %d tiles sown, %d ripe" % [
				farm.planted_count(), farm.ripe_count()]
		_larder.text = town.larder_line() + extra

	for i in _crewbox.get_child_count():
		var l := _crewbox.get_child(i) as Label
		if crew == null or i >= crew.workers.size():
			l.text = ""
			continue
		var w: Worker = crew.workers[i]
		l.text = "%s — %s" % [w.display_name(), w.status_text()]
		l.add_theme_color_override("font_color",
			WARN if w.pending_question != "" else (INK if w.busy() else DIM))

	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.text = ""

	if _typing_for != null:
		_prompt.text = ""
	elif _target != null:
		if _target.pending_question != "":
			_prompt.text = "%s is waiting on an answer   [E]" % _target.display_name()
		else:
			_prompt.text = "%s   [E] speak" % _target.display_name()
	elif _crop != null and is_instance_valid(_crop):
		_prompt.text = "ripe %s   [E] pick" % str(_crop.get_meta("crop_kind", "crop"))
	else:
		_prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talk") and _typing_for == null and _target != null:
		_open_bar(_target)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("talk") and _typing_for == null 			and _crop != null and is_instance_valid(_crop):
		harvest_wanted.emit(_crop.get_meta("crop_tile") as Vector2i)
		_crop = null
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu") and _typing_for != null:
		_close_bar()
		get_viewport().set_input_as_handled()


## Typing and mouse-look cannot both own the input. Releasing the pointer while
## the bar is open is also the only cue the player gets that the game is now
## waiting for words rather than for movement.
func _open_bar(w: Worker) -> void:
	_typing_for = w
	_bar.visible = true
	if w.pending_question != "":
		_barlabel.text = "%s asked:  %s" % [w.display_name(), w.pending_question]
		_entry.placeholder_text = "answer them…"
	else:
		_barlabel.text = "Telling %s what to do" % w.display_name()
		_entry.placeholder_text = "tell them what to build…"
	_entry.text = ""
	_entry.grab_focus()
	player.set_input_enabled(false)


func _close_bar() -> void:
	_typing_for = null
	_bar.visible = false
	_entry.release_focus()
	player.set_input_enabled(true)


func _on_submit(text: String) -> void:
	var w := _typing_for
	var said := text.strip_edges()
	var answering := w != null and w.pending_question != ""
	_close_bar()
	if w == null or said == "":
		return
	if answering:
		answer_given.emit(w, said)
	else:
		instruction_given.emit(w, said)


## What the worker decided that you never said. Stays up until the next plan
## replaces it: the player has to be able to read it while the worker is still
## walking to the plot, so the building they get is one they could have seen
## coming.
func show_assumptions(w: Worker, assumptions: Array) -> void:
	if assumptions.is_empty():
		_assume_title.text = "%s assumed nothing." % w.display_name()
		_assume_body.text = "You left them no room to guess."
	else:
		_assume_title.text = "%s filled in the gaps:" % w.display_name()
		var lines: Array[String] = []
		for a: Variant in assumptions:
			lines.append("•  " + str(a))
		_assume_body.text = "\n".join(lines)
	_assume.visible = true


func toast(text: String, seconds: float = 4.0) -> void:
	_toast.text = text
	_toast_left = seconds
