extends CanvasLayer
class_name TitleScreen
## The front door. Shown only on a normal interactive launch (no dev or test
## flags), over the world while it streams in. It holds the player still and
## the clock stopped until "Begin" is pressed, which also gives the browser the
## click it needs before it will let the game capture the pointer.

signal begun

var player: Player
var clock: GameClock

var _root: Control
var _begin: Button
var _status: Label
var _ready_to_play := false
var _dots := 0.0
var _fading := false


func setup(p: Player, gc: GameClock = null) -> void:
	player = p
	clock = gc
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	player.set_input_enabled(false)
	if clock != null:
		clock.paused = true


func attach_clock(gc: GameClock) -> void:
	clock = gc
	if clock != null and not _fading and visible:
		clock.paused = true


func _build() -> void:
	var touch := Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	var k := 1.5 if touch else 1.0

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
	add_child(_root)

	# Dark on the left where the type sits, clear on the right so the village
	# behind still shows; a floor vignette to seat it.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.04, 0.03, 0.02, 0.92))
	grad.set_color(1, Color(0.04, 0.03, 0.02, 0.10))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 0.85)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 512
	gt.height = 8
	var side := TextureRect.new()
	side.texture = gt
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.stretch_mode = TextureRect.STRETCH_SCALE
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(side)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(110 * (1.0 if not touch else 0.6)))
	margin.add_theme_constant_override("margin_right", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(14 * k))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var cap := UiTheme.title("A VILLAGE OF WORDS", int(15 * k), UiTheme.GOLD)
	col.add_child(cap)
	var name_l := Label.new()
	name_l.text = "DELEGATE"
	name_l.add_theme_font_override("font", UiTheme.display(800))
	name_l.add_theme_font_size_override("font_size", int(104 * k))
	name_l.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	name_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	name_l.add_theme_constant_override("shadow_offset_y", 4)
	name_l.add_theme_constant_override("shadow_outline_size", 6)
	col.add_child(name_l)

	var rule := ColorRect.new()
	rule.color = Color(UiTheme.GOLD, 0.6)
	rule.custom_minimum_size = Vector2(120 * k, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var tag := UiTheme.label("You cannot touch anything.\nYou can only talk to three people.",
		int(22 * k), UiTheme.INK, 500)
	col.add_child(tag)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18 * k)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_begin = Button.new()
	_begin.text = "Raising the village"
	_begin.disabled = true
	_begin.focus_mode = Control.FOCUS_ALL
	_begin.custom_minimum_size = Vector2(300 * k, 58 * k)
	_begin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(_begin, int(20 * k), true)
	_begin.pressed.connect(_on_begin)
	col.add_child(_begin)

	_status = UiTheme.label("", int(14 * k), UiTheme.DIM, 500)
	col.add_child(_status)

	if not touch:
		var hints := HBoxContainer.new()
		hints.add_theme_constant_override("separation", 18)
		hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hints.add_child(UiTheme.chip("WASD", "move"))
		hints.add_child(UiTheme.chip("E", "speak"))
		hints.add_child(UiTheme.chip("M", "map"))
		hints.add_child(UiTheme.chip("Esc", "pause"))
		col.add_child(hints)


func _process(delta: float) -> void:
	if _ready_to_play or _fading:
		return
	_dots = fmod(_dots + delta * 2.5, 4.0)
	_begin.text = "Raising the village" + ".".repeat(int(_dots))


## Called once the world has streamed in.
func ready_to_play() -> void:
	_ready_to_play = true
	_begin.disabled = false
	_begin.text = "Begin"
	_begin.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _ready_to_play and not _fading and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			get_viewport().set_input_as_handled()
			_on_begin()


func _on_begin() -> void:
	if _fading or not _ready_to_play:
		return
	_fading = true
	if clock != null:
		clock.paused = false
	player.set_input_enabled(true)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.45)
	tw.finished.connect(func() -> void:
		begun.emit()
		queue_free())
