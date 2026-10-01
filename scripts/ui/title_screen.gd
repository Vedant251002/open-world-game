extends CanvasLayer
class_name TitleScreen
## The front door. Shown only on a normal interactive launch (no dev or test
## flags), over the world while it streams in. It holds the player still and
## the clock stopped until "Begin" is pressed, which also gives the browser the
## click it needs before it will let the game capture the pointer.

signal begun

var player: Player
var clock: GameClock
## The village being founded (or the saved one), edited in place by the customise
## card and shared with Main, which reads it when "begun" fires.
var identity: VillageIdentity
## The landscape the world behind this screen was generated with.
var built_landscape := ""
var has_save := false
var seed_value := 0

var _name_edit: LineEdit
var _preview: BannerIcon
var _swatches: Array[Button] = []
var _emblems: Array[Button] = []
var _lands: Array[Button] = []
var _land_blurb: Label
var _custom_card: PanelContainer

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


## Called by Main right after setup(): what is being founded and from what.
func configure(ident: VillageIdentity, generated_landscape: String, saved: bool, seed_v: int) -> void:
	identity = ident
	built_landscape = generated_landscape
	has_save = saved
	seed_value = seed_v
	if identity.village_name == "" and not has_save:
		identity.village_name = VillageIdentity.default_name(seed_value)
	_build_customise()


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


## The right-hand card: name, banner and landscape for a new village; just the
## banner and name for a saved one.
func _build_customise() -> void:
	var touch := Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	var k := 1.5 if touch else 1.0
	var host := MarginContainer.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_theme_constant_override("margin_right", 70)
	host.add_theme_constant_override("margin_top", 40)
	host.add_theme_constant_override("margin_bottom", 40)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(host)
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(right)
	var vc := VBoxContainer.new()
	vc.alignment = BoxContainer.ALIGNMENT_CENTER
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(vc)

	_custom_card = PanelContainer.new()
	var sb := UiTheme.panel_menu()
	sb.bg_color = Color(UiTheme.PANEL_SOLID, 0.90)
	sb.set_content_margin_all(UiTheme.px(22 * k))
	_custom_card.add_theme_stylebox_override("panel", sb)
	_custom_card.custom_minimum_size = Vector2(400 * k, 0)
	vc.add_child(_custom_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(11 * k))
	_custom_card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(14 * k))
	col.add_child(head)
	_preview = BannerIcon.make(identity.colour(), identity.emblem(), 76.0 * k)
	head.add_child(_preview)
	var hc := VBoxContainer.new()
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hc)
	hc.add_child(UiTheme.title("WELCOME BACK TO" if has_save else "FOUND YOUR VILLAGE", int(12 * k), UiTheme.GOLD))

	if has_save:
		var nm := UiTheme.label(identity.village_name if identity.village_name != "" else "Your village",
			int(28 * k), UiTheme.PARCHMENT, 800)
		nm.add_theme_font_override("font", UiTheme.display(800))
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hc.add_child(nm)
		col.add_child(UiTheme.label("Your town is where you left it. Begin to carry on.",
			int(15 * k), UiTheme.DIM, 500))
		return

	_name_edit = LineEdit.new()
	_name_edit.text = identity.village_name
	_name_edit.max_length = VillageIdentity.MAX_NAME
	_name_edit.placeholder_text = "Name your village"
	_name_edit.custom_minimum_size = Vector2(0, 40 * k)
	_name_edit.add_theme_font_override("font", UiTheme.display(700))
	_name_edit.add_theme_font_size_override("font_size", UiTheme.fs(int(22 * k)))
	_name_edit.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	var lsb := UiTheme.card(0.9, 8)
	lsb.bg_color = Color(0, 0, 0, 0.35)
	lsb.border_color = UiTheme.EDGE_STRONG
	_name_edit.add_theme_stylebox_override("normal", lsb)
	_name_edit.add_theme_stylebox_override("focus", _focus_box(lsb))
	_name_edit.text_changed.connect(func(t: String) -> void:
		identity.village_name = VillageIdentity.sanitise(t))
	_name_edit.text_submitted.connect(func(_t: String) -> void:
		_name_edit.release_focus()
		if _begin != null and not _begin.disabled:
			_begin.grab_focus())
	hc.add_child(_name_edit)
	var reroll := UiTheme.button("Another name")
	UiTheme.style_button(reroll, int(13 * k))
	reroll.pressed.connect(func() -> void:
		identity.village_name = VillageIdentity.default_name(randi())
		_name_edit.text = identity.village_name)
	col.add_child(reroll)

	col.add_child(UiTheme.title("BANNER", int(12 * k), UiTheme.GOLD))
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", int(8 * k))
	col.add_child(sw)
	for i in VillageIdentity.COLOURS.size():
		var b := _swatch_button(VillageIdentity.COLOURS[i], 34.0 * k)
		b.tooltip_text = str(VillageIdentity.COLOUR_NAMES[i])
		b.pressed.connect(_pick_colour.bind(i))
		sw.add_child(b)
		_swatches.append(b)
	var em := HBoxContainer.new()
	em.add_theme_constant_override("separation", int(8 * k))
	col.add_child(em)
	for i in VillageIdentity.EMBLEMS.size():
		var b2 := _emblem_button(str(VillageIdentity.EMBLEMS[i]), 34.0 * k)
		b2.pressed.connect(_pick_emblem.bind(i))
		em.add_child(b2)
		_emblems.append(b2)

	col.add_child(UiTheme.title("STARTING LANDSCAPE", int(12 * k), UiTheme.GOLD))
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", int(7 * k))
	col.add_child(lr)
	for id: String in VillageIdentity.LANDSCAPE_ORDER:
		var lb := Button.new()
		lb.text = str((VillageIdentity.LANDSCAPES[id] as Dictionary)["name"])
		lb.toggle_mode = true
		lb.focus_mode = Control.FOCUS_NONE
		lb.custom_minimum_size = Vector2(88 * k, 38 * k)
		UiTheme.style_button(lb, int(15 * k))
		lb.pressed.connect(_pick_landscape.bind(id))
		lr.add_child(lb)
		_lands.append(lb)
	_land_blurb = UiTheme.label("", int(14 * k), UiTheme.DIM, 500)
	_land_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_land_blurb.custom_minimum_size = Vector2(0, 40 * k)
	col.add_child(_land_blurb)
	_sync_choices()


func _focus_box(base: StyleBoxFlat) -> StyleBoxFlat:
	var f := base.duplicate() as StyleBoxFlat
	f.border_color = UiTheme.ACCENT
	return f


func _swatch_button(c: Color, size: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	for n: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = c.lightened(0.12) if n == "hover" else c
		sbx.set_corner_radius_all(int(size * 0.5))
		sbx.border_color = Color(UiTheme.EDGE_STRONG)
		sbx.set_border_width_all(2)
		sbx.anti_aliasing = true
		b.add_theme_stylebox_override(n, sbx)
	return b


func _emblem_button(kind: String, size: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	for n: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = Color(1, 0.92, 0.75, 0.22 if n == "hover" else 0.10)
		sbx.set_corner_radius_all(8)
		sbx.border_color = UiTheme.EDGE
		sbx.set_border_width_all(1)
		b.add_theme_stylebox_override(n, sbx)
	var ic := _EmblemGlyph.new()
	ic.kind = kind
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	return b


## An emblem drawn on a button face.
class _EmblemGlyph extends Control:
	var kind := "sun"

	func _draw() -> void:
		BannerIcon.draw_emblem(self, size * 0.5, minf(size.x, size.y) * 0.3, kind, UiTheme.PARCHMENT)


func _pick_colour(i: int) -> void:
	identity.colour_idx = i
	_sync_choices()


func _pick_emblem(i: int) -> void:
	identity.emblem_idx = i
	_sync_choices()


func _pick_landscape(id: String) -> void:
	identity.landscape = id
	_sync_choices()


## Marks the current choices and refreshes the live banner preview.
func _sync_choices() -> void:
	_preview.set_banner(identity.colour(), identity.emblem())
	for i in _swatches.size():
		var on := i == identity.colour_idx
		for n: String in ["normal", "hover", "pressed", "focus"]:
			var sbx := _swatches[i].get_theme_stylebox(n) as StyleBoxFlat
			sbx.border_color = UiTheme.ACCENT if on else UiTheme.EDGE_STRONG
			sbx.set_border_width_all(4 if on else 2)
	for i in _emblems.size():
		var on2 := i == identity.emblem_idx
		for n: String in ["normal", "hover", "pressed", "focus"]:
			var sbx2 := _emblems[i].get_theme_stylebox(n) as StyleBoxFlat
			sbx2.border_color = UiTheme.ACCENT if on2 else UiTheme.EDGE
			sbx2.set_border_width_all(2 if on2 else 1)
			sbx2.bg_color = Color(UiTheme.GOLD, 0.30) if on2 else Color(1, 0.92, 0.75, 0.10)
	for i in _lands.size():
		_lands[i].set_pressed_no_signal(VillageIdentity.LANDSCAPE_ORDER[i] == identity.landscape)
	if _land_blurb != null:
		_land_blurb.text = str((VillageIdentity.LANDSCAPES[identity.landscape] as Dictionary)["blurb"])
		if identity.landscape != built_landscape:
			_land_blurb.text += "  (The land is raised afresh when you begin.)"


func _process(delta: float) -> void:
	if _ready_to_play or _fading:
		return
	_dots = fmod(_dots + delta * 2.5, 4.0)
	_begin.text = "Raising the village" + ".".repeat(int(_dots))


## Called once the world has streamed in.
func ready_to_play() -> void:
	_ready_to_play = true
	_begin.disabled = false
	_begin.text = "Continue" if has_save else "Begin"
	_begin.grab_focus()
	# Reloaded to raise a different landscape: the player already pressed Begin.
	if VillageIdentity.auto_begin:
		VillageIdentity.auto_begin = false
		_on_begin()


func _unhandled_input(event: InputEvent) -> void:
	if _ready_to_play and not _fading and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			get_viewport().set_input_as_handled()
			_on_begin()


func _on_begin() -> void:
	if _fading or not _ready_to_play:
		return
	# A new village on a landscape the world was not generated with: remember the
	# choice and raise the world again. (A save, or the landscape already on
	# screen, begins straight away.)
	if identity != null and not has_save:
		identity.village_name = VillageIdentity.sanitise(identity.village_name)
		VillageIdentity.pending = identity
		if identity.landscape != built_landscape:
			_fading = true
			VillageIdentity.auto_begin = true
			_begin.text = "Raising the land..."
			_begin.disabled = true
			get_tree().reload_current_scene()
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
