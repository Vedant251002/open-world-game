extends CanvasLayer
class_name CrierScreen
## The Village Crier as a page: parchment, a Cinzel masthead, a headline, two
## columns of items, the gossip, the sky and the notice. Back issues are one
## key away. Opened with N, from the HUD badge, or from the pause menu.

const KEY_PAPER := KEY_N

var crier: Crier
var player: Player
var hud: Hud
var map: MapScreen
var inventory: InventoryScreen
var open := false
var shown := -1                ## index into crier.issues

var _root: Control
var _scroll: ScrollContainer
var _page: VBoxContainer
var _nav_label: Label
var _prev_btn: Button
var _next_btn: Button
var _touch := false
var _k := 1.0

const PAPER := Color("#efe3c6")
const PAPER_DARK := Color("#d9c79a")
const INK_DARK := Color("#2c1f12")
const INK_SOFT := Color("#5b4630")
const RUST := Color("#8a3b22")


func setup(c: Crier, p: Player, h: Hud, m: MapScreen, inv: InventoryScreen) -> void:
	crier = c
	player = p
	hud = h
	map = m
	inventory = inv
	layer = 12
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	_k = 1.3 if _touch else 1.0
	_build()
	visible = false
	crier.issue_printed.connect(_on_issue)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.02, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			set_open(false))
	_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_root.add_child(margin)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(centre)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 8)
	frame.custom_minimum_size = Vector2(minf(1040.0, 1600.0), 0)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(frame)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 600)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_scroll)
	var sheet := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = INK_SOFT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	sb.shadow_size = 26
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(sheet)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", int(8 * _k))
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(_page)

	# Back-issue bar under the page.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(nav)
	_prev_btn = UiTheme.button("◀  Older")
	UiTheme.style_button(_prev_btn, int(15 * _k))
	_prev_btn.pressed.connect(func() -> void: browse(-1))
	nav.add_child(_prev_btn)
	_nav_label = UiTheme.label("", int(15 * _k), UiTheme.INK, 700)
	_nav_label.custom_minimum_size = Vector2(190, 0)
	_nav_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_nav_label)
	_next_btn = UiTheme.button("Newer  ▶")
	UiTheme.style_button(_next_btn, int(15 * _k))
	_next_btn.pressed.connect(func() -> void: browse(1))
	nav.add_child(_next_btn)
	var close := UiTheme.button("Close")
	UiTheme.style_button(close, int(15 * _k), true)
	close.pressed.connect(func() -> void: set_open(false))
	nav.add_child(close)
	if not _touch:
		nav.add_child(UiTheme.key_cap("N"))


# ---------------------------------------------------------------- showing

func set_open(v: bool) -> void:
	if v == open:
		return
	open = v
	visible = v
	if v:
		Sfx.page()
		var vh := get_viewport().get_visible_rect().size.y
		_scroll.custom_minimum_size.y = clampf(vh - 96.0, 320.0, 820.0)
		show_issue(crier.issues.size() - 1)
	if player != null:
		player.set_input_enabled(not v)


func open_screen() -> void:
	if not open:
		set_open(true)


func browse(step: int) -> void:
	show_issue(shown + step)


func show_issue(idx: int) -> void:
	if crier.issues.is_empty():
		shown = -1
		_nav_label.text = "No issues yet"
		return
	shown = clampi(idx, 0, crier.issues.size() - 1)
	var issue: Dictionary = crier.issues[shown]
	crier.mark_read(issue)
	_render(issue)
	_prev_btn.disabled = shown <= 0
	_next_btn.disabled = shown >= crier.issues.size() - 1
	_nav_label.text = "No. %d   ·   %d of %d" % [int(issue["edition"]), shown + 1, crier.issues.size()]
	_scroll.scroll_vertical = 0


func _on_issue(issue: Dictionary) -> void:
	# An LLM rewrite or a fresh issue landing while the page is open.
	if open and shown >= 0 and shown < crier.issues.size() and crier.issues[shown] == issue:
		_render(issue)
	elif open and shown == crier.issues.size() - 2:
		_next_btn.disabled = false


func _lab(text: String, size: int, col: Color, weight: int = 500, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.display(weight) if display else UiTheme.font(weight))
	l.add_theme_font_size_override("font_size", UiTheme.fs(int(size * _k)))
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule(thick: int = 1, col: Color = INK_SOFT) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, thick)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _box(title: String, body: String, tint: Color, bordered := false) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(3)
	if bordered:
		sb.border_color = INK_DARK
		sb.set_border_width_all(2)
	else:
		sb.border_color = Color(INK_SOFT, 0.4)
		sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	var t := _lab(title, 12, RUST, 800, true)
	v.add_child(t)
	v.add_child(_lab(body, 15, INK_DARK, 500))
	return pc


func _render(issue: Dictionary) -> void:
	for c in _page.get_children():
		c.queue_free()
	var village := str(issue["village"])
	# Folio line.
	var folio := HBoxContainer.new()
	_page.add_child(folio)
	var f1 := _lab("Vol. I   ·   No. %d" % int(issue["edition"]), 12, INK_SOFT, 700, true)
	f1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_child(f1)
	var f2 := _lab("%s   ·   Day %d" % [str(issue.get("season", "")).capitalize(), int(issue["day"])], 12, INK_SOFT, 700, true)
	f2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_child(f2)
	var f3 := _lab("Price: one kind word", 12, INK_SOFT, 700, true)
	f3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	f3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_child(f3)
	_page.add_child(_rule(3, INK_DARK))
	# Masthead.
	var mast := _lab("The %s Crier" % village, 48, INK_DARK, 800, true)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(mast)
	var tag := _lab("— what happened, what is said, and what the town wants —", 14, INK_SOFT, 600)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(tag)
	_page.add_child(_rule(1, INK_DARK))
	_page.add_child(_rule(3, INK_DARK))
	# Headline.
	var head := _lab(str(issue["headline"]), 32, INK_DARK, 800, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(head)
	var lede := _lab(str(issue["lede"]), 17, INK_SOFT, 600)
	lede.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(lede)
	_page.add_child(_rule(1, INK_SOFT))

	# Two columns.
	var cols := BoxContainer.new()
	cols.vertical = _touch and get_viewport() != null and get_viewport().get_visible_rect().size.x < 900.0
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)
	var first := true
	for it: Dictionary in issue["items"]:
		if not first:
			left.add_child(_rule(1, Color(INK_SOFT, 0.35)))
		first = false
		left.add_child(_lab(str(it["kicker"]), 12, RUST, 800, true))
		left.add_child(_lab(str(it["text"]), 15, INK_DARK, 500))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_box("OVERHEARD AT THE WELL", str(issue["gossip"]), Color(PAPER_DARK, 0.55)))
	right.add_child(_box("THE SKY, SAYS THE CRIER", str(issue["forecast"]), Color(0.76, 0.84, 0.88, 0.35)))
	right.add_child(_box("NOTICE", str(issue["notice"]), Color(1, 1, 1, 0.12), true))
	_page.add_child(_rule(1, INK_SOFT))
	var foot := _lab("Printed fresh each morning at the sign of the well.%s" % (
		"   Set in a livelier hand today." if str(issue.get("source", "")) == "llm" else ""),
		12, INK_SOFT, 600)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(foot)


# ------------------------------------------------------------------ input

func _can_open() -> bool:
	if player == null or not player.input_enabled:
		return false
	return hud != null and hud.visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_PAPER:
				if open:
					set_open(false)
					get_viewport().set_input_as_handled()
				elif _can_open():
					set_open(true)
					get_viewport().set_input_as_handled()
				return
			if open and k.keycode == KEY_LEFT:
				browse(-1)
				get_viewport().set_input_as_handled()
			elif open and k.keycode == KEY_RIGHT:
				browse(1)
				get_viewport().set_input_as_handled()
	if open and event.is_action_pressed("menu"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if open and hud != null and not hud.visible:
		set_open(false)


# ====================================================================== badge

## The HUD's small "The Crier — day 5" tag. Pulses gold while an issue is
## unread; click or tap opens the paper.
class Badge extends PanelContainer:
	signal pressed
	var crier: Crier
	var _label: Label
	var _sub: Label
	var _t := 0.0
	var _unread := false
	var _style: StyleBoxFlat

	func bind(c: Crier) -> void:
		crier = c
		c.issue_printed.connect(func(_i: Dictionary) -> void: refresh())
		refresh()

	func _ready() -> void:
		_style = UiTheme.card(0.85)
		add_theme_stylebox_override("panel", _style)
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var icon := Paper.new()
		icon.custom_minimum_size = Vector2(UiTheme.px(26), UiTheme.px(26))
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		_label = UiTheme.title("THE CRIER", 12, UiTheme.GOLD)
		col.add_child(_label)
		_sub = UiTheme.label("", 14, UiTheme.INK, 700)
		col.add_child(_sub)
		if not (Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()):
			var kc := UiTheme.key_cap("N")
			kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(kc)
		gui_input.connect(func(e: InputEvent) -> void:
			if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
					or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
				pressed.emit()
				accept_event())
		refresh()

	func refresh() -> void:
		if crier == null or _sub == null:
			return
		var latest := crier.latest()
		_unread = crier.unread_count() > 0
		_sub.text = ("Day %d" % int(latest["day"]) + ("  ·  new issue" if _unread else "")) if not latest.is_empty() else "No issues"
		_label.text = "THE CRIER — DAY %d" % int(latest["day"]) if not latest.is_empty() else "THE CRIER"
		if not _unread and _style != null:
			_style.border_color = UiTheme.EDGE
			modulate = Color.WHITE

	func _process(delta: float) -> void:
		if not _unread or _style == null:
			return
		_t += delta
		var p := 0.5 + 0.5 * sin(_t * 4.2)
		_style.border_color = Color(UiTheme.GOLD, 0.35 + 0.65 * p)
		_style.set_border_width_all(2)
		modulate = Color(1.0, 1.0, 1.0, 0.88 + 0.12 * p)


## A tiny folded newspaper.
class Paper extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(2, 3), size - Vector2(4, 6))
		draw_rect(r, Color("#efe3c6"))
		draw_rect(r, Color("#8a6a3a"), false, 1.5)
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y * 0.22)), Color("#3a2a1a"))
		for i in 3:
			var y := r.position.y + r.size.y * (0.46 + 0.17 * i)
			draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), Color("#6b5636"), 1.2)
