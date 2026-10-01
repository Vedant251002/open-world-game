class_name SoundPanel
## The volume controls inside the pause menu: a "Sound" row that unfolds into
## a mute switch and one slider per bus. Changes are heard at once and written
## to user://settings.cfg half a second after the last touch.

static var _knob: Texture2D = null


static func build() -> Control:
	AudioBuses.ensure()
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
	save_timer.timeout.connect(AudioBuses.save)
	box.add_child(save_timer)

	var label_head := func() -> void:
		head.text = "Sound  %s" % ("(muted)" if AudioBuses.muted else ("hide" if body.visible else "show"))
	label_head.call()
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		label_head.call())

	var mute := CheckButton.new()
	mute.text = "Mute all"
	mute.button_pressed = AudioBuses.muted
	mute.focus_mode = Control.FOCUS_ALL
	mute.add_theme_font_override("font", UiTheme.font(600))
	mute.add_theme_font_size_override("font_size", UiTheme.fs(15))
	mute.add_theme_color_override("font_color", UiTheme.INK)
	mute.toggled.connect(func(on: bool) -> void:
		AudioBuses.set_muted(on)
		label_head.call()
		save_timer.start())
	body.add_child(mute)

	for bus: String in AudioBuses.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(UiTheme.px(10)))
		body.add_child(row)
		var name_l := UiTheme.label(str(AudioBuses.LABELS[bus]), 14, UiTheme.DIM, 600)
		name_l.custom_minimum_size = Vector2(UiTheme.px(84), 0)
		row.add_child(name_l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = AudioBuses.volume(bus)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(UiTheme.px(150), UiTheme.px(28))
		s.focus_mode = Control.FOCUS_ALL
		_style_slider(s)
		row.add_child(s)
		var pct := UiTheme.label("%d%%" % int(round(s.value * 100.0)), 13, UiTheme.FAINT, 600)
		pct.custom_minimum_size = Vector2(UiTheme.px(40), 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)
		s.value_changed.connect(func(v: float) -> void:
			AudioBuses.set_volume(bus, v)
			pct.text = "%d%%" % int(round(v * 100.0))
			save_timer.start())
		# Letting go of the effects slider plays a sample, so you can judge it.
		if bus == AudioBuses.SFX or bus == AudioBuses.UI:
			s.drag_ended.connect(func(_c: bool) -> void: Sfx.click())
	return box


static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.ACCENT
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var k := _knob_texture()
	s.add_theme_icon_override("grabber", k)
	s.add_theme_icon_override("grabber_highlight", k)
	s.add_theme_icon_override("grabber_disabled", k)


## A small round knob, drawn once.
static func _knob_texture() -> Texture2D:
	if _knob != null:
		return _knob
	var d := 22
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var a := clampf(c - r + 0.5, 0.0, 1.0)
			var rim := clampf(c - 3.0 - r + 0.5, 0.0, 1.0)
			var col := Color(0.28, 0.2, 0.08).lerp(UiTheme.INK, rim)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_knob = ImageTexture.create_from_image(img)
	return _knob
