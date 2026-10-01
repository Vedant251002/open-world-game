extends CanvasLayer
class_name VisitScreen
## Sharing your village, and visiting somebody else's.
##
## "Share my village" makes a village code (VillageExport) you can copy to the
## clipboard or save as a file; send it to anybody by any means. "Visit a
## village" takes a pasted code, shows what is in it (or why it was refused) and
## walks you into a read-only copy of it (VillageVisit). While visiting, a small
## banner names the village and offers the way home.

signal visit_requested(data: Dictionary)
signal leave_requested

const CFG := "user://share.cfg"

var player: Player
var identity: VillageIdentity
## Returns VillageExport.build_data(...) for the live village; set by Main.
var export_provider: Callable
var owner_name := ""
var open := false

var _root: Control
var _holder: Control
var _code_box: TextEdit
var _paste_box: TextEdit
var _status: Label
var _preview: Label
var _visit_button: Button
var _checked: Dictionary = {}
var _owns_pause := false
var _was_input := true
var _banner_layer: CanvasLayer


func setup(p: Player, id: VillageIdentity) -> void:
	player = p
	identity = id
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		owner_name = VillageExport.clean_text(cf.get_value("share", "name", ""), 24)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.02, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	visible = false


func open_screen() -> void:
	if open:
		return
	open = true
	visible = true
	_owns_pause = not get_tree().paused
	if _owns_pause:
		get_tree().paused = true
		if player != null:
			_was_input = player.input_enabled
			player.set_input_enabled(false)
	_rebuild()


func close_screen() -> void:
	if not open:
		return
	open = false
	visible = false
	if _owns_pause:
		get_tree().paused = false
		if player != null:
			player.set_input_enabled(_was_input)
	_owns_pause = false


func _input(event: InputEvent) -> void:
	if open and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close_screen()


func _rebuild() -> void:
	if _holder != null:
		_holder.queue_free()
	_checked = {}
	var vp := get_viewport().get_visible_rect().size
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_holder)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_menu())
	_holder.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(UiTheme.px(700), vp.y - UiTheme.px(90)))
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(minf(UiTheme.px(600), vp.x - UiTheme.px(70)), 0)
	col.add_theme_constant_override("separation", int(UiTheme.px(8)))
	scroll.add_child(col)

	var t := UiTheme.title("VILLAGES", 26, UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := UiTheme.label("A village is a short piece of text. Send yours to anybody; walk round theirs.",
		13, UiTheme.DIM, 500)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	col.add_child(_rule())

	# ---------------------------------------------------------------- share
	col.add_child(UiTheme.title("SHARE MY VILLAGE", 13, UiTheme.GOLD))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", int(UiTheme.px(8)))
	col.add_child(name_row)
	name_row.add_child(UiTheme.label("Sign it as", 14, UiTheme.DIM, 600))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "your name (optional)"
	name_edit.max_length = 24
	name_edit.text = owner_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(s: String) -> void:
		owner_name = VillageExport.clean_text(s, 24)
		var cf := ConfigFile.new()
		cf.set_value("share", "name", owner_name)
		cf.save(CFG))
	name_row.add_child(name_edit)
	col.add_child(_button("Make my village code", _make_code, true))
	_code_box = TextEdit.new()
	_code_box.editable = false
	_code_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code_box.custom_minimum_size = Vector2(0, UiTheme.px(84))
	_code_box.placeholder_text = "Your code appears here."
	_code_box.add_theme_font_size_override("font_size", UiTheme.fs(12))
	col.add_child(_code_box)
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", int(UiTheme.px(8)))
	col.add_child(share_row)
	var cp := _button("Copy to clipboard", _copy_code)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_row.add_child(cp)
	var dl := _button("Download as file" if Platform.is_web() else "Save as file", _save_code)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_row.add_child(dl)
	_status = UiTheme.label("", 13, UiTheme.GOOD, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(_rule())

	# ---------------------------------------------------------------- visit
	col.add_child(UiTheme.title("VISIT A VILLAGE", 13, UiTheme.GOLD))
	col.add_child(UiTheme.label("Paste a village code. You will look and talk, and nothing can be ordered; your own village is kept as it is.",
		13, UiTheme.DIM, 500))
	_paste_box = TextEdit.new()
	_paste_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_paste_box.custom_minimum_size = Vector2(0, UiTheme.px(84))
	_paste_box.placeholder_text = "Paste a code here (it begins DV1.)"
	_paste_box.add_theme_font_size_override("font_size", UiTheme.fs(12))
	_paste_box.text_changed.connect(_on_paste_changed)
	col.add_child(_paste_box)
	var paste_row := HBoxContainer.new()
	paste_row.add_theme_constant_override("separation", int(UiTheme.px(8)))
	col.add_child(paste_row)
	var pb := _button("Paste from clipboard", func() -> void:
		_paste_box.text = DisplayServer.clipboard_get()
		_on_paste_changed())
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste_row.add_child(pb)
	_visit_button = _button("Visit this village", _go_visit, true)
	_visit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_visit_button.disabled = true
	paste_row.add_child(_visit_button)
	_preview = UiTheme.label("", 14, UiTheme.DIM, 600)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_preview)
	col.add_child(_rule())
	col.add_child(_button("Close", close_screen))


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
	b.focus_mode = Control.FOCUS_ALL
	UiTheme.style_button(b, 15, primary)
	b.pressed.connect(pressed)
	return b


# ------------------------------------------------------------------- share

func _make_code() -> void:
	if not export_provider.is_valid():
		return
	var d: Dictionary = export_provider.call()
	var code := VillageExport.encode(d)
	_code_box.text = code
	_status.add_theme_color_override("font_color", UiTheme.GOOD)
	_status.text = "%d buildings, %d people, %d characters. Copy it and send it on." % [
		(d["buildings"] as Array).size(), (d["crew"] as Array).size(), code.length()]


func _copy_code() -> void:
	if _code_box.text == "":
		_make_code()
	_clip(_code_box.text)
	_status.add_theme_color_override("font_color", UiTheme.GOOD)
	_status.text = "Copied to the clipboard."


func _clip(text: String) -> String:
	if Platform.is_web() and Engine.has_singleton("JavaScriptBridge"):
		var js := "(function(t){ if (navigator.clipboard) { navigator.clipboard.writeText(t); return 'copied'; } return 'none'; })(%s)" % JSON.stringify(text)
		var r: Variant = JavaScriptBridge.eval(js, true)
		if str(r) == "copied":
			return "copied"
	DisplayServer.clipboard_set(text)
	return "copied"


func _save_code() -> void:
	if _code_box.text == "":
		_make_code()
	var fname := "village-%s.txt" % str(identity.village_name).to_lower().replace(" ", "-")
	if Platform.is_web() and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.download_buffer(_code_box.text.to_utf8_buffer(), fname, "text/plain")
		_status.text = "Downloading %s." % fname
		return
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write %s." % path
		return
	f.store_string(_code_box.text)
	f.close()
	_status.text = "Saved to %s." % path


# ------------------------------------------------------------------- visit

func _on_paste_changed() -> void:
	var text := _paste_box.text
	_visit_button.disabled = true
	_checked = {}
	if text.strip_edges() == "":
		_preview.text = ""
		return
	var res := VillageExport.decode(text)
	if not bool(res.get("ok", false)):
		_preview.add_theme_color_override("font_color", UiTheme.ALERT)
		_preview.text = str(res.get("error", "That code is not usable."))
		return
	var d: Dictionary = res["data"]
	_checked = d
	_visit_button.disabled = false
	_preview.add_theme_color_override("font_color", UiTheme.GOOD)
	var by := " by %s" % str(d["owner"]) if str(d["owner"]) != "" else ""
	_preview.text = "%s%s: %d buildings, %d people%s." % [str(d["name"]), by,
		(d["buildings"] as Array).size(), (d["crew"] as Array).size(),
		", shared %s" % str(d["date"]) if str(d["date"]) != "" else ""]


func _go_visit() -> void:
	if _checked.is_empty():
		return
	var d := _checked
	close_screen()
	visit_requested.emit(d)


# ---------------------------------------------------------------- the banner

## While visiting: whose village this is, that it is read-only, and the way home.
func show_visit_banner(d: Dictionary) -> void:
	if _banner_layer != null:
		_banner_layer.queue_free()
	_banner_layer = CanvasLayer.new()
	_banner_layer.layer = 24
	add_child(_banner_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	_banner_layer.add_child(root)
	var anchor := CenterContainer.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top = UiTheme.px(84)      # under the village card
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(anchor)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.panel_active())
	anchor.add_child(pc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiTheme.px(12)))
	pc.add_child(row)
	row.add_child(BannerIcon.make(VillageIdentity.COLOURS[int(d["colour"])],
		str(VillageIdentity.EMBLEMS[int(d["emblem"])]), UiTheme.px(44)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	col.add_child(UiTheme.title("VISITING  " + str(d["name"]).to_upper(), 15, UiTheme.ACCENT))
	var owner_s := "%s's village" % str(d["owner"]) if str(d["owner"]) != "" else "A shared village"
	var when := "  ·  shared %s" % str(d["date"]) if str(d["date"]) != "" else ""
	col.add_child(UiTheme.label("%s%s  ·  look and talk; nothing can be ordered" % [owner_s, when],
		12, UiTheme.DIM, 600))
	var leave := Button.new()
	leave.text = "Leave"
	leave.focus_mode = Control.FOCUS_NONE
	leave.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.style_button(leave, 14, true)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	row.add_child(leave)
