extends CanvasLayer
class_name PhotoMode
## P: stop the village, put the interface away, and take a picture of it.
##
## Time freezes (the tree is paused, so is the clock), the HUD is hidden and a
## free camera takes over from the player's eyes: WASD to fly, Q/E down and up,
## Shift for quick, hold the right mouse button to look (or drag on a phone:
## the left of the screen flies, the right looks), wheel to zoom. The panel
## sets the time of day, a colour filter, a frame and (where the renderer can
## do it) depth of field, and writes the caption of a postcard. Capture saves
## a PNG — into user://photos on a desktop, as a download in a browser.
##
## The filter and the frame are drawn on canvas layers under the panel, which
## is hidden for the instant of the capture, so what is saved is the picture
## and nothing of the tool.

signal opened
signal closed

const PHOTO_ACTION := &"photo"
const FILTERS := ["None", "Warm", "Cool", "Vintage", "B&W"]
const FRAMES := ["None", "Classic", "Polaroid", "Postcard"]
const FLY_SPEED := 9.0
const FLY_FAST := 3.2
const RANGE_M := 70.0           ## how far from where you stood the camera may roam
const MAX_UP_M := 70.0
const LOOK_SENS := 0.0030
const TOUCH_LOOK := 0.0045

var player: Player
var hud: Hud
var clock: GameClock
var sky: SkyEnv
var realm: Realm
var town: Town
var crew: Crew
var world: VoxelWorld
var dispatch: Dispatcher
var touch: TouchControls
var pause_menu: PauseMenu

var active := false
var filter_index := 0
var frame_index := 0
var caption := ""
var last_path := ""

var _cam: Camera3D
var _attrs: CameraAttributesPractical
var _anchor := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _fov := 74.0
var _looking := false
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _look_touch := -1
var _saved := {}

var _grade_layer: CanvasLayer
var _grade: ColorRect
var _frame: PhotoFrame
var _ui: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _time_slider: HSlider
var _time_label: Label
var _filter_buttons: Array[Button] = []
var _frame_buttons: Array[Button] = []
var _caption_edit: LineEdit
var _status: Label
var _dof_box: VBoxContainer
var _focus_slider: HSlider
var _blur_slider: HSlider
var _ai_day := -1
var _variant := 0
var _busy := false
var _hint: Control


## A `photo` action so one name covers the P key and the touch button.
static func ensure_action() -> void:
	if not InputMap.has_action(PHOTO_ACTION):
		InputMap.add_action(PHOTO_ACTION)
		var ev := InputEventKey.new()
		ev.keycode = KEY_P
		InputMap.action_add_event(PHOTO_ACTION, ev)


func setup() -> void:
	ensure_action()
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	if dispatch != null and dispatch.llm != null:
		dispatch.llm.line_ready.connect(_on_ai_line)


# ------------------------------------------------------------------- opening

func can_open() -> bool:
	return not active and player != null and player.input_enabled \
		and (pause_menu == null or not pause_menu.open)


func toggle() -> void:
	if active:
		close()
	elif can_open():
		open()


## From the pause menu: put the menu away first, then go in.
func open_from_pause() -> void:
	if pause_menu != null and pause_menu.open:
		pause_menu.set_open(false)
	if can_open():
		open()


func open() -> void:
	if active:
		return
	active = true
	_saved = {
		"hour": clock.hour if clock != null else 12.0,
		"clock_paused": clock.paused if clock != null else false,
		"cam": player.camera,
		"hud": hud.visible if hud != null else true,
		"touch": touch.visible if touch != null else true,
		"mouse": Input.mouse_mode,
	}
	var from := player.camera.global_transform
	_anchor = player.global_position
	_yaw = player.yaw
	_pitch = player.pitch
	_fov = player.camera.fov

	_cam = Camera3D.new()
	_cam.name = "PhotoCamera"
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	_cam.near = 0.05
	_cam.far = player.camera.far
	_cam.fov = _fov
	get_parent().add_child(_cam)
	_cam.global_transform = from
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = false
	_attrs.dof_blur_near_enabled = false
	_cam.attributes = _attrs
	_cam.current = true

	player.set_input_enabled(false)
	if clock != null:
		clock.paused = true
	get_tree().paused = true
	if hud != null:
		hud.visible = false
	if touch != null:
		touch.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_time_slider.set_value_no_signal(_saved["hour"])
	_update_time_label()
	_set_filter(filter_index)
	_set_frame(frame_index)
	_dof_box.visible = _dof_supported()
	_apply_dof()
	_refresh_caption(true)
	_status.text = ""
	visible = true
	_ui.visible = true
	_hint.visible = true
	_reflow()
	opened.emit()


func close() -> void:
	if not active:
		return
	active = false
	_looking = false
	_stick_touch = -1
	_look_touch = -1
	if _cam != null:
		_cam.queue_free()
		_cam = null
	(_saved["cam"] as Camera3D).current = true
	# Hand the sky back to the clock: setting the hour by hand stops it being
	# driven (see SkyEnv._process), so say it is in step again.
	if clock != null:
		clock.hour = float(_saved["hour"])
		clock.paused = bool(_saved["clock_paused"])
	if sky != null:
		sky._clock_synced = true
		sky._last_pushed_hour = float(_saved["hour"])
		sky.hour = float(_saved["hour"])
	get_tree().paused = false
	if hud != null:
		hud.visible = bool(_saved["hud"])
	if touch != null:
		touch.visible = bool(_saved["touch"])
	_grade.visible = false
	_frame.visible = false
	visible = false
	player.set_input_enabled(true)
	closed.emit()


# ----------------------------------------------------------------- building

func _build() -> void:
	# Grade and frame live on layers of their own, below the panel, so the
	# capture can leave the panel out and keep them.
	_grade_layer = CanvasLayer.new()
	_grade_layer.layer = 24
	_grade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_grade_layer)
	_grade = ColorRect.new()
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/ui/photo_filter.gdshader")
	_grade.material = mat
	_grade.visible = false
	_grade_layer.add_child(_grade)
	_frame = PhotoFrame.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	_grade_layer.add_child(_frame)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(_ui)
	add_child(_ui)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel(1.0))
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = UiTheme.px(16)
	_panel.offset_right = -UiTheme.px(16)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(UiTheme.px(310), 0)
	col.add_theme_constant_override("separation", int(UiTheme.px(8)))
	_scroll.add_child(col)

	var title := UiTheme.title("PHOTO MODE", 20, UiTheme.ACCENT)
	col.add_child(title)
	col.add_child(UiTheme.label("The village holds still.", 13, UiTheme.DIM, 500))

	# Time of day.
	col.add_child(_section("TIME OF DAY"))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", int(UiTheme.px(10)))
	col.add_child(trow)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 24.0
	_time_slider.step = 0.25
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.custom_minimum_size = Vector2(0, UiTheme.px(26))
	_time_slider.value_changed.connect(_on_time)
	trow.add_child(_time_slider)
	_time_label = UiTheme.label("12:00", 15, UiTheme.INK, 700)
	_time_label.custom_minimum_size = Vector2(UiTheme.px(48), 0)
	trow.add_child(_time_label)

	# Filters.
	col.add_child(_section("FILTER"))
	var frow := HFlowContainer.new()
	frow.add_theme_constant_override("h_separation", int(UiTheme.px(6)))
	frow.add_theme_constant_override("v_separation", int(UiTheme.px(6)))
	col.add_child(frow)
	for i in FILTERS.size():
		var b := _chip_button(FILTERS[i], _set_filter.bind(i))
		frow.add_child(b)
		_filter_buttons.append(b)

	# Frames.
	col.add_child(_section("FRAME"))
	var grow := HFlowContainer.new()
	grow.add_theme_constant_override("h_separation", int(UiTheme.px(6)))
	grow.add_theme_constant_override("v_separation", int(UiTheme.px(6)))
	col.add_child(grow)
	for i in FRAMES.size():
		var b2 := _chip_button(FRAMES[i], _set_frame.bind(i))
		grow.add_child(b2)
		_frame_buttons.append(b2)

	# Depth of field, where the renderer has one.
	_dof_box = VBoxContainer.new()
	_dof_box.add_theme_constant_override("separation", int(UiTheme.px(4)))
	col.add_child(_dof_box)
	_dof_box.add_child(_section("FOCUS"))
	_focus_slider = _slider(_dof_box, 4.0, 200.0, 40.0, "Focus distance")
	_blur_slider = _slider(_dof_box, 0.0, 0.2, 0.0, "Blur")
	_focus_slider.value_changed.connect(func(_v: float) -> void: _apply_dof())
	_blur_slider.value_changed.connect(func(_v: float) -> void: _apply_dof())

	# Postcard caption.
	col.add_child(_section("POSTCARD CAPTION"))
	_caption_edit = LineEdit.new()
	_caption_edit.placeholder_text = "Write a few words..."
	_caption_edit.max_length = 200
	_caption_edit.custom_minimum_size = Vector2(0, UiTheme.px(38))
	_caption_edit.text_changed.connect(func(t: String) -> void:
		caption = t
		_frame.caption = t
		_frame.queue_redraw())
	col.add_child(_caption_edit)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", int(UiTheme.px(6)))
	col.add_child(crow)
	var regen := _small_button("New caption", func() -> void: _refresh_caption(false, true))
	crow.add_child(regen)
	crow.add_child(_small_button("Copy", func() -> void:
		DisplayServer.clipboard_set("%s — %s" % [_frame.village, caption])
		_status.text = "Caption copied."))

	col.add_child(_rule())
	var cap := _button("Take photo   [Enter]", capture, true)
	col.add_child(cap)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", int(UiTheme.px(6)))
	col.add_child(row2)
	row2.add_child(_small_button("Hide panel  [H]", _toggle_panel))
	row2.add_child(_small_button("Close  [Esc]", close))
	_status = UiTheme.label("", 13, UiTheme.GOOD, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(UiTheme.px(300), 0)
	col.add_child(_status)

	# Key hints, lower left.
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", UiTheme.card(0.75, 14))
	hp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hp.offset_left = UiTheme.px(16)
	hp.offset_bottom = -UiTheme.px(16)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(hp)
	_hint = hp
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(UiTheme.px(14)))
	hp.add_child(hb)
	hb.add_child(UiTheme.chip("WASD", "fly"))
	hb.add_child(UiTheme.chip("Q E", "down / up"))
	hb.add_child(UiTheme.chip("RMB", "look"))
	hb.add_child(UiTheme.chip("Wheel", "zoom"))
	hb.add_child(UiTheme.chip("Shift", "fast"))

	get_viewport().size_changed.connect(_reflow)


func _section(text: String) -> Label:
	return UiTheme.title(text, 12, UiTheme.DIM)


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = UiTheme.EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _button(text: String, pressed: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UiTheme.px(42))
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(b, 16, primary)
	b.pressed.connect(pressed)
	return b


func _small_button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UiTheme.px(34))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(b, 13)
	b.pressed.connect(pressed)
	return b


func _chip_button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UiTheme.px(58), UiTheme.px(34))
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(b, 13)
	b.pressed.connect(pressed)
	return b


func _slider(into: Control, lo: float, hi: float, v: float, label: String) -> HSlider:
	into.add_child(UiTheme.label(label, 13, UiTheme.DIM, 500))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value = v
	s.custom_minimum_size = Vector2(0, UiTheme.px(24))
	into.add_child(s)
	return s


func _reflow() -> void:
	if _scroll == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	_scroll.custom_minimum_size = Vector2(0, minf(UiTheme.px(640), h - UiTheme.px(80)))
	_scroll.size = Vector2.ZERO


# ----------------------------------------------------------------- controls

func _on_time(v: float) -> void:
	_apply_hour(v)
	_update_time_label()


func _apply_hour(v: float) -> void:
	if clock != null:
		clock.hour = v
	if sky != null:
		sky.hour = v


func _update_time_label() -> void:
	var h := int(_time_slider.value)
	var m := int((_time_slider.value - h) * 60.0)
	_time_label.text = "%02d:%02d" % [h, m]


func _set_filter(i: int) -> void:
	filter_index = clampi(i, 0, FILTERS.size() - 1)
	_grade.visible = active and filter_index > 0
	(_grade.material as ShaderMaterial).set_shader_parameter("mode", filter_index)
	_mark(_filter_buttons, filter_index)


func _set_frame(i: int) -> void:
	frame_index = clampi(i, 0, FRAMES.size() - 1)
	_frame.style = frame_index
	_frame.visible = active and frame_index > 0
	_frame.queue_redraw()
	_mark(_frame_buttons, frame_index)


func _mark(buttons: Array[Button], chosen: int) -> void:
	for i in buttons.size():
		UiTheme.style_button(buttons[i], 13, i == chosen)


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_hint.visible = _panel.visible


static func _dof_supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


func _apply_dof() -> void:
	if _attrs == null:
		return
	var on := _dof_supported() and _blur_slider.value > 0.001
	_attrs.dof_blur_far_enabled = on
	_attrs.dof_blur_near_enabled = on
	_attrs.dof_blur_amount = _blur_slider.value
	_attrs.dof_blur_far_distance = _focus_slider.value
	_attrs.dof_blur_far_transition = maxf(_focus_slider.value * 0.6, 6.0)
	_attrs.dof_blur_near_distance = maxf(_focus_slider.value * 0.5, 1.0)
	_attrs.dof_blur_near_transition = maxf(_focus_slider.value * 0.4, 1.0)


# ------------------------------------------------------------------ caption

func _stats() -> Dictionary:
	return Postcard.stats_for(realm, town, crew, clock)


## Fills the caption box: offline from the template at once; with a key, one
## model call per in-game day (the offline line shows meanwhile). `again` is
## the regenerate button, which cycles the template and never calls out.
func _refresh_caption(first: bool, again: bool = false) -> void:
	var st := _stats()
	_frame.village = str(st["name"])
	_frame.day = int(st["day"])
	if again:
		_variant += 1
	var line := Postcard.offline(st, (int(st["day"]) + int(st["buildings"]) + _variant))
	if first and caption != "" and _ai_day == int(st["day"]):
		line = caption                      # keep this day's, edits included
	else:
		_set_caption(line)
	if first and not again and dispatch != null and dispatch.llm != null \
			and dispatch.llm.available() and _ai_day != int(st["day"]):
		_ai_day = int(st["day"])
		dispatch.llm.talk("photo", Postcard.ai_system(),
			[{"role": "user", "content": Postcard.ai_user(st)}], "postcard", line)
	elif first:
		_ai_day = int(st["day"]) if caption != "" else _ai_day


func _set_caption(t: String) -> void:
	caption = t
	_caption_edit.text = t
	_frame.caption = t
	_frame.queue_redraw()


func _on_ai_line(worker_id: String, text: String, tag: String) -> void:
	if worker_id != "photo" or tag != "postcard" or not active:
		return
	var t := Postcard.clean(text)
	if t != "":
		_set_caption(t)


# ------------------------------------------------------------------ capture

## The picture, as an Image, with the panel left out. Null when there is no
## renderer (headless).
func render_image() -> Image:
	var was_ui := _ui.visible
	var was_hint := _hint.visible
	_ui.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_ui.visible = was_ui
	_hint.visible = was_hint
	return img


func capture() -> void:
	if _busy:
		return
	_busy = true
	var img := await render_image()
	_busy = false
	if img == null or img.is_empty():
		_status.text = "No picture to take here."
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var fname := "delegate_day%d_%s.png" % [clock.day if clock != null else 1, stamp]
	if Platform.is_web() and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), fname, "image/png")
		last_path = fname
		_status.text = "Your photo is downloading: %s" % fname
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://photos"))
	var path := "user://photos/%s" % fname
	if img.save_png(path) != OK:
		_status.text = "Could not save the photo."
		return
	last_path = ProjectSettings.globalize_path(path)
	_status.text = "Saved to %s" % last_path
	print("[photo] saved %s (%dx%d)" % [last_path, img.get_width(), img.get_height()])


# -------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PHOTO_ACTION):
		if active or can_open():
			get_viewport().set_input_as_handled()
			toggle()


func _input(event: InputEvent) -> void:
	if not active:
		return
	var typing := _caption_edit.has_focus()
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if typing:
				_caption_edit.release_focus()
			else:
				close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			if typing:
				_caption_edit.release_focus()
			else:
				capture()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_H and not typing:
			_toggle_panel()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed and not _over_panel(mb.position)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and not _over_panel(mb.position):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-3.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(3.0)
			elif mb.button_index == MOUSE_BUTTON_LEFT and typing:
				_caption_edit.release_focus()
	elif event is InputEventMouseMotion and _looking:
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * LOOK_SENS
		_pitch = clampf(_pitch - rel.y * LOOK_SENS, -1.5, 1.5)
	elif event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_drag(event as InputEventScreenDrag)


func _over_panel(p: Vector2) -> bool:
	return _panel.visible and _panel.get_global_rect().has_point(p)


func _zoom(d: float) -> void:
	_fov = clampf(_fov + d, 22.0, 100.0)


func _touch(t: InputEventScreenTouch) -> void:
	var s := get_viewport().get_visible_rect().size
	if t.pressed:
		if _over_panel(t.position):
			return
		if t.position.x < s.x * 0.4 and _stick_touch == -1:
			_stick_touch = t.index
			_stick_origin = t.position
			_stick = Vector2.ZERO
		elif _look_touch == -1:
			_look_touch = t.index
	else:
		if t.index == _stick_touch:
			_stick_touch = -1
			_stick = Vector2.ZERO
		if t.index == _look_touch:
			_look_touch = -1


func _drag(d: InputEventScreenDrag) -> void:
	if d.index == _stick_touch:
		_stick = ((d.position - _stick_origin) / 90.0).limit_length(1.0)
	elif d.index == _look_touch:
		_yaw -= d.relative.x * TOUCH_LOOK
		_pitch = clampf(_pitch - d.relative.y * TOUCH_LOOK, -1.5, 1.5)


func _process(delta: float) -> void:
	if not active or _cam == null:
		return
	var typing := _caption_edit.has_focus()
	var wish := Vector3.ZERO
	if not typing:
		if Input.is_key_pressed(KEY_W):
			wish.z -= 1.0
		if Input.is_key_pressed(KEY_S):
			wish.z += 1.0
		if Input.is_key_pressed(KEY_A):
			wish.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			wish.x += 1.0
		if Input.is_key_pressed(KEY_E):
			wish.y += 1.0
		if Input.is_key_pressed(KEY_Q):
			wish.y -= 1.0
	wish.x += _stick.x
	wish.z += _stick.y
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var flat := Basis(Vector3.UP, _yaw)
	var speed := FLY_SPEED * (FLY_FAST if (Input.is_key_pressed(KEY_SHIFT) and not typing) else 1.0)
	var move := flat * Vector3(wish.x, 0, 0) + basis * Vector3(0, 0, wish.z) + Vector3(0, wish.y, 0)
	var pos := _cam.global_position + move * speed * delta
	# Keep within sight of where the player stood (the world only streams
	# around them), and above the ground.
	var off := Vector2(pos.x - _anchor.x, pos.z - _anchor.z)
	if off.length() > RANGE_M:
		off = off.normalized() * RANGE_M
		pos.x = _anchor.x + off.x
		pos.z = _anchor.z + off.y
	var ground := world.ground_m(pos.x, pos.z) if world != null else _anchor.y
	pos.y = clampf(pos.y, ground + 0.5, maxf(_anchor.y, ground) + MAX_UP_M)
	_cam.global_position = pos
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.fov = _fov


## The frame drawn over the picture. A frame is part of the photograph, so it
## lives under the panel and is captured with the rest.
class PhotoFrame extends Control:
	var style := 0
	var village := "My Village"
	var day := 1
	var caption := ""

	const CREAM := Color("#efe3c6")
	const INKC := Color("#3a2a1a")
	const GOLDC := Color("#e8b85c")

	func _draw() -> void:
		var s := size
		if s.x < 8 or s.y < 8 or style == 0:
			return
		var u := s.y / 900.0
		match style:
			1:
				_classic(s, u)
			2:
				_polaroid(s, u)
			3:
				_postcard(s, u)

	func _text(at: Vector2, t: String, sz: float, col: Color, w: int = 600,
			align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, display := false) -> void:
		var f: Font = UiTheme.display(w) if display else UiTheme.font(w)
		draw_string(f, at, t, align, width, int(sz), col)

	func _classic(s: Vector2, u: float) -> void:
		var m := 18.0 * u
		draw_rect(Rect2(Vector2(m, m), s - Vector2(m, m) * 2.0), GOLDC, false, maxf(2.0 * u, 1.5))
		draw_rect(Rect2(Vector2(m, m) * 1.7, s - Vector2(m, m) * 3.4),
			Color(GOLDC, 0.45), false, maxf(1.0 * u, 1.0))
		var plate := Vector2(maxf(s.x * 0.28, 320.0 * u), 62.0 * u)
		var r := Rect2(Vector2((s.x - plate.x) * 0.5, s.y - m * 2.0 - plate.y), plate)
		draw_rect(r, Color(0.07, 0.06, 0.05, 0.82))
		draw_rect(r, GOLDC, false, maxf(1.5 * u, 1.0))
		_text(r.position + Vector2(0, 28.0 * u), village.to_upper(), 24.0 * u, GOLDC, 700,
			HORIZONTAL_ALIGNMENT_CENTER, plate.x, true)
		_text(r.position + Vector2(0, 50.0 * u), "Day %d" % day, 16.0 * u, CREAM, 600,
			HORIZONTAL_ALIGNMENT_CENTER, plate.x)

	func _polaroid(s: Vector2, u: float) -> void:
		var side := 30.0 * u
		var top := 30.0 * u
		var bottom := 150.0 * u
		draw_rect(Rect2(0, 0, s.x, top), CREAM)
		draw_rect(Rect2(0, s.y - bottom, s.x, bottom), CREAM)
		draw_rect(Rect2(0, 0, side, s.y), CREAM)
		draw_rect(Rect2(s.x - side, 0, side, s.y), CREAM)
		draw_rect(Rect2(side, top, s.x - side * 2.0, s.y - top - bottom), Color(0, 0, 0, 0.25), false, 2.0)
		var w := s.x - side * 3.0
		_text(Vector2(side * 1.5, s.y - bottom + 40.0 * u), village.to_upper() + "  ·  DAY %d" % day,
			20.0 * u, Color(INKC, 0.7), 700, HORIZONTAL_ALIGNMENT_LEFT, w, true)
		var f := UiTheme.font(600)
		draw_multiline_string(f, Vector2(side * 1.5, s.y - bottom + 76.0 * u), caption,
			HORIZONTAL_ALIGNMENT_LEFT, w, int(22.0 * u), 2, INKC)

	func _postcard(s: Vector2, u: float) -> void:
		var m := 26.0 * u
		draw_rect(Rect2(0, 0, s.x, m), CREAM)
		draw_rect(Rect2(0, s.y - m, s.x, m), CREAM)
		draw_rect(Rect2(0, 0, m, s.y), CREAM)
		draw_rect(Rect2(s.x - m, 0, m, s.y), CREAM)
		draw_rect(Rect2(m, m, s.x - m * 2.0, s.y - m * 2.0), Color(INKC, 0.5), false, 1.5)
		# Stamp, top right.
		var st := Vector2(96.0, 118.0) * u
		var sr := Rect2(Vector2(s.x - m * 1.6 - st.x, m * 1.6), st)
		draw_rect(sr, CREAM)
		draw_rect(sr.grow(-6.0 * u), Color("#7a3b2e"), false, 2.0 * u)
		_text(sr.position + Vector2(0, 52.0 * u), "DAY", 15.0 * u, Color("#7a3b2e"), 700,
			HORIZONTAL_ALIGNMENT_CENTER, st.x, true)
		_text(sr.position + Vector2(0, 92.0 * u), str(day), 38.0 * u, Color("#7a3b2e"), 800,
			HORIZONTAL_ALIGNMENT_CENTER, st.x, true)
		# Message band, lower left.
		var bw := minf(s.x * 0.58, 760.0 * u)
		var band := Rect2(Vector2(m * 1.6, s.y - m * 1.6 - 150.0 * u), Vector2(bw, 150.0 * u))
		draw_rect(band, Color(0.96, 0.91, 0.78, 0.92))
		draw_rect(band, Color(INKC, 0.6), false, 1.5)
		_text(band.position + Vector2(16.0 * u, 38.0 * u), "Greetings from", 17.0 * u,
			Color(INKC, 0.8), 600, HORIZONTAL_ALIGNMENT_LEFT, bw)
		_text(band.position + Vector2(16.0 * u, 76.0 * u), village, 36.0 * u, Color("#7a3b2e"), 700,
			HORIZONTAL_ALIGNMENT_LEFT, bw - 32.0 * u, true)
		draw_multiline_string(UiTheme.font(500), band.position + Vector2(16.0 * u, 106.0 * u),
			caption, HORIZONTAL_ALIGNMENT_LEFT, bw - 32.0 * u, int(17.0 * u), 2, INKC)
