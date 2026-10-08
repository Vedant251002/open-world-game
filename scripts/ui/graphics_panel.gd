class_name GraphicsPanel
## The graphics controls inside the pause menu, built like the Sound row: a
## "Graphics" header that unfolds into a quality preset, render scale, view
## distance, vsync and a frame cap. Every change is applied at once and written
## to user://settings.cfg half a second after the last touch.


static func build() -> Control:
	GraphicsSettings.load_settings()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(UiTheme.px(8)))

	var head := Button.new()
	head.custom_minimum_size = Vector2(0, UiTheme.px(46))
	head.focus_mode = Control.FOCUS_ALL
	UiTheme.style_button(head, 17)
	box.add_child(head)

	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", int(UiTheme.px(8)))
	box.add_child(body)

	var save_timer := Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.5
	save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	save_timer.timeout.connect(GraphicsSettings.save)
	box.add_child(save_timer)

	var label_head := func() -> void:
		head.text = "Graphics  %s  %s" % [
			GraphicsSettings.PRESET_NAMES[GraphicsSettings.preset],
			"hide" if body.visible else "show"]
	label_head.call()
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		label_head.call())

	var preset := _option(body, "Quality", GraphicsSettings.PRESET_NAMES,
		GraphicsSettings.preset)
	var scale_row := _slider(body, "Render scale", 0.5, 1.0, 0.05,
		GraphicsSettings.render_scale)
	var scale: HSlider = scale_row[0]
	var scale_pct: Label = scale_row[1]
	var view := _option(body, "View distance", GraphicsSettings.VIEW_NAMES,
		GraphicsSettings.view)
	var fps_names: Array[String] = []
	for f: int in GraphicsSettings.FPS_CAPS:
		fps_names.append("Unlimited" if f == 0 else "%d fps" % f)
	var fps := _option(body, "Frame limit", fps_names,
		maxi(GraphicsSettings.FPS_CAPS.find(GraphicsSettings.max_fps), 0))
	var vs := CheckButton.new()
	vs.text = "VSync"
	vs.button_pressed = GraphicsSettings.vsync
	vs.focus_mode = Control.FOCUS_ALL
	vs.add_theme_font_override("font", UiTheme.font(600))
	vs.add_theme_font_size_override("font_size", UiTheme.fs(15))
	vs.add_theme_color_override("font_color", UiTheme.INK)
	body.add_child(vs)

	# Picking a preset moves the render scale and view distance with it, so the
	# controls are refreshed from the settings rather than left showing the old
	# values.
	var sync := func() -> void:
		scale.set_value_no_signal(GraphicsSettings.render_scale)
		scale_pct.text = "%d%%" % int(round(GraphicsSettings.render_scale * 100.0))
		view.select(GraphicsSettings.view)
		label_head.call()

	preset.item_selected.connect(func(i: int) -> void:
		GraphicsSettings.choose_preset(i)
		sync.call()
		save_timer.start())
	scale.value_changed.connect(func(v: float) -> void:
		GraphicsSettings.render_scale = v
		scale_pct.text = "%d%%" % int(round(v * 100.0))
		GraphicsSettings.apply()
		save_timer.start())
	view.item_selected.connect(func(i: int) -> void:
		GraphicsSettings.view = i
		GraphicsSettings.apply()
		save_timer.start())
	fps.item_selected.connect(func(i: int) -> void:
		GraphicsSettings.max_fps = GraphicsSettings.FPS_CAPS[i]
		GraphicsSettings.apply()
		save_timer.start())
	vs.toggled.connect(func(on: bool) -> void:
		GraphicsSettings.vsync = on
		GraphicsSettings.apply()
		save_timer.start())
	return box


static func _row(body: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiTheme.px(10)))
	body.add_child(row)
	var name_l := UiTheme.label(title, 14, UiTheme.DIM, 600)
	name_l.custom_minimum_size = Vector2(UiTheme.px(110), 0)
	row.add_child(name_l)
	return row


static func _option(body: VBoxContainer, title: String, items: Array[String],
		selected: int) -> OptionButton:
	var row := _row(body, title)
	var o := OptionButton.new()
	for it: String in items:
		o.add_item(it)
	o.select(clampi(selected, 0, items.size() - 1))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(UiTheme.px(150), UiTheme.px(32))
	o.focus_mode = Control.FOCUS_ALL
	o.add_theme_font_override("font", UiTheme.font(600))
	o.add_theme_font_size_override("font_size", UiTheme.fs(14))
	row.add_child(o)
	return o


## Returns [slider, percentage label].
static func _slider(body: VBoxContainer, title: String, lo: float, hi: float,
		step: float, value: float) -> Array:
	var row := _row(body, title)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(UiTheme.px(150), UiTheme.px(28))
	s.focus_mode = Control.FOCUS_ALL
	SoundPanel._style_slider(s)
	row.add_child(s)
	var pct := UiTheme.label("%d%%" % int(round(value * 100.0)), 13, UiTheme.FAINT, 600)
	pct.custom_minimum_size = Vector2(UiTheme.px(40), 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	return [s, pct]
