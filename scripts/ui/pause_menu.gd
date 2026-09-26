extends CanvasLayer
class_name PauseMenu
## Esc: stop the world, hand the pointer back, and offer the way out.
##
## Esc used to do nothing outside the talk bar, the map and the inventory, so
## the only way out of a captured mouse was to leave the game — and the grab
## came straight back every time the window was focused again, which is what
## a cursor bouncing between the game and the desktop looked like. Now Esc,
## or switching away from the window, pauses: the pointer is free, the clock
## stops, and Quit saves on the way out.
##
## Also the one place that owns the window: fullscreen on boot, F11 to
## switch, and Cmd+Q honoured even while the pointer is captured.

const C_SHADE := Color(0.03, 0.03, 0.04, 0.72)
const C_PANEL := Color(0.11, 0.10, 0.09, 0.97)
const C_EDGE := Color(1, 1, 1, 0.16)
const C_INK := Color(0.94, 0.92, 0.87)
## Switching into a macOS fullscreen space drops and returns focus once on
## the way in. That is not the player leaving.
const FOCUS_GRACE_MS := 2500

var player: Player
var open := false

var _root: Control
var _screen_button: Button
var _ready_ms := 0


## `on_focus_loss` false for tests and benches, which must not freeze because
## somebody clicked on another window while they ran.
func setup(p: Player, on_focus_loss: bool = true) -> void:
	player = p
	layer = 30                      ## over the map and the inventory
	# Everything else stops while this is up; this has to keep listening.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_ms = Time.get_ticks_msec()
	_build()
	visible = false
	var win := get_window()
	if win != null and on_focus_loss and not Platform.is_web():
		win.focus_exited.connect(_on_focus_lost)


## Fullscreen unless told otherwise. Not on the web, where the browser only
## allows it from inside a click, and not headless, where there is no window.
static func start_fullscreen(args: PackedStringArray) -> void:
	if Platform.is_web() or DisplayServer.get_name() == "headless":
		return
	if "--windowed" in args:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


static func toggle_fullscreen() -> void:
	if Platform.is_web():
		return
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
		else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = C_SHADE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(260, 0)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", C_INK)
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)

	col.add_child(_button("Resume", set_open.bind(false)))
	if not Platform.is_web():
		_screen_button = _button("", func() -> void:
			toggle_fullscreen()
			_label_screen_button())
		col.add_child(_screen_button)
		col.add_child(_button("Save and quit", quit_game))


func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(pressed)
	return b


func _label_screen_button() -> void:
	if _screen_button == null:
		return
	var full := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED
	_screen_button.text = "Windowed   [F11]" if full else "Fullscreen   [F11]"


func set_open(v: bool) -> void:
	if v == open:
		return
	open = v
	visible = v
	get_tree().paused = v
	if player != null:
		player.set_input_enabled(not v)
	if v:
		_label_screen_button()


## Saves through the same close notification the window sends, so a quit from
## here and a quit from the title bar are one path.
func quit_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


func _on_focus_lost() -> void:
	if open or player == null or not player.input_enabled:
		return                      # already paused, or in the map / talk bar
	if Time.get_ticks_msec() - _ready_ms < FOCUS_GRACE_MS:
		return
	set_open(true)


## _input rather than _unhandled_input: Cmd+Q and F11 must work whatever
## else has the keyboard, the talk bar included.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_Q and k.meta_pressed and OS.get_name() == "macOS":
		get_viewport().set_input_as_handled()
		quit_game()
	elif k.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		toggle_fullscreen()
		_label_screen_button()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu"):
		return
	# Esc closes the talk bar, the map and the inventory first; those take the
	# pointer with them, so a disabled player means one of them is up.
	if open:
		set_open(false)
		get_viewport().set_input_as_handled()
	elif player != null and player.input_enabled:
		set_open(true)
		get_viewport().set_input_as_handled()
