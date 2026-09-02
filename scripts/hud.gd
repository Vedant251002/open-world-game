extends CanvasLayer
## Minimal clean HUD: crosshair, title, controls hint, FPS.

var fps_label: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# crosshair dot
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.9)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)

	# controls hint
	var hint := Label.new()
	hint.text = "WASD move  ·  SHIFT sprint  ·  SPACE jump  ·  T command workers  ·  ESC mouse"
	hint.position = Vector2(16, 694)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	# title
	var title := Label.new()
	title.text = "NEON BAY CITY"
	title.position = Vector2(16, 10)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.78))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	# fps
	fps_label = Label.new()
	fps_label.position = Vector2(1180, 14)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fps_label)


func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()
