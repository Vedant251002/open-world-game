extends CanvasLayer
class_name MilestonesUi
## The village's standing, on screen: a small card at the top centre (banner,
## name, rank and a progress bar toward the next rank), the celebratory banner
## that slides in when a milestone is reached, and the milestones panel (J, or
## tap the card) that lists what is done and what is next.

const KEY_PANEL := KEY_J

var prog: Progression
var identity: VillageIdentity
var player: Player
var hud: Hud
var map: MapScreen
var inventory: InventoryScreen
var open := false

var _root: Control
var _card: PanelContainer
var _card_banner: BannerIcon
var _card_name: Label
var _card_rank: Label
var _card_bar: RankBar
var _card_count: Label
var _banner: PanelContainer
var _b_title: Label
var _b_desc: Label
var _b_reward: Label
var _b_icon: BannerIcon
var _queue: Array[Dictionary] = []
var _showing := false
var _panel_root: Control
var _panel_list: VBoxContainer
var _panel_head_name: Label
var _panel_head_rank: Label
var _panel_head_next: Label
var _panel_head_bar: RankBar
var _panel_head_banner: BannerIcon
var _touch := false
var _k := 1.0


## A thin gold-on-dark progress bar.
class RankBar extends Control:
	var value := 0.0
	var _shown := 0.0

	func _process(delta: float) -> void:
		if absf(_shown - value) > 0.002:
			_shown = move_toward(_shown, value, delta * 0.8)
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.EDGE_STRONG, 0.5), false, 1.0)
		var w := (size.x - 2.0) * clampf(_shown, 0.0, 1.0)
		if w > 0.5:
			draw_rect(Rect2(Vector2(1, 1), Vector2(w, size.y - 2.0)), UiTheme.GOLD)
			draw_rect(Rect2(Vector2(1, 1), Vector2(w, (size.y - 2.0) * 0.4)), Color(1, 1, 1, 0.18))

	func snap(v: float) -> void:
		value = v
		_shown = v
		queue_redraw()


func setup(p: Progression, ident: VillageIdentity, pl: Player, h: Hud, m: MapScreen,
		inv: InventoryScreen) -> void:
	prog = p
	identity = ident
	player = pl
	hud = h
	map = m
	inventory = inv
	layer = 11
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	_k = 1.4 if _touch else 1.0
	_build()
	prog.milestone_reached.connect(_on_milestone)
	prog.rank_changed.connect(_on_rank_changed)
	refresh()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(_root)
	add_child(_root)

	# The standing card, top centre.
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.card(0.9, 14))
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 14
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	_root.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12 * _k))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_card_banner = BannerIcon.make(identity.colour(), identity.emblem(), 46.0 * _k)
	row.add_child(_card_banner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_card_name = UiTheme.label(_display_name(), int(19 * _k), UiTheme.INK, 800)
	col.add_child(_card_name)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", int(8 * _k))
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(r2)
	_card_rank = UiTheme.title("HAMLET", int(12 * _k), UiTheme.GOLD)
	r2.add_child(_card_rank)
	_card_count = UiTheme.label("", int(12 * _k), UiTheme.DIM, 600)
	r2.add_child(_card_count)
	_card_bar = RankBar.new()
	_card_bar.custom_minimum_size = Vector2(190 * _k, 8 * _k)
	_card_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_card_bar)
	if not _touch:
		var kc := UiTheme.key_cap("J", int(12 * _k))
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kc)

	# The banner that announces a milestone.
	_banner = PanelContainer.new()
	var bsb := UiTheme.panel_active()
	bsb.border_color = Color(UiTheme.GOLD, 0.9)
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(int(UiTheme.px(UiTheme.R_LG)))
	bsb.content_margin_left = UiTheme.px(22)
	bsb.content_margin_right = UiTheme.px(26)
	_banner.add_theme_stylebox_override("panel", bsb)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 112
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_root.add_child(_banner)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", int(16 * _k))
	_banner.add_child(brow)
	_b_icon = BannerIcon.make(identity.colour(), "star", 64.0 * _k)
	brow.add_child(_b_icon)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	brow.add_child(bcol)
	bcol.add_child(UiTheme.title("MILESTONE REACHED", int(12 * _k), UiTheme.GOLD))
	_b_title = UiTheme.label("", int(28 * _k), UiTheme.PARCHMENT, 800)
	_b_title.add_theme_font_override("font", UiTheme.display(800))
	bcol.add_child(_b_title)
	_b_desc = UiTheme.label("", int(15 * _k), UiTheme.DIM, 500)
	bcol.add_child(_b_desc)
	_b_reward = UiTheme.label("", int(17 * _k), UiTheme.ACCENT, 800)
	bcol.add_child(_b_reward)

	_build_panel()


func _build_panel() -> void:
	_panel_root = Control.new()
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.visible = false
	UiTheme.apply(_panel_root)
	add_child(_panel_root)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.02, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			set_open(false))
	_panel_root.add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(centre)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.panel_menu())
	pc.custom_minimum_size = Vector2(560 if not _touch else 900, 0)
	centre.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(12 * _k))
	pc.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(16 * _k))
	col.add_child(head)
	_panel_head_banner = BannerIcon.make(identity.colour(), identity.emblem(), 70.0 * _k)
	head.add_child(_panel_head_banner)
	var hc := VBoxContainer.new()
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_theme_constant_override("separation", 2)
	head.add_child(hc)
	hc.add_child(UiTheme.title("YOUR VILLAGE", int(12 * _k), UiTheme.GOLD))
	_panel_head_name = UiTheme.label("", int(30 * _k), UiTheme.PARCHMENT, 800)
	_panel_head_name.add_theme_font_override("font", UiTheme.display(800))
	hc.add_child(_panel_head_name)
	_panel_head_rank = UiTheme.label("", int(16 * _k), UiTheme.INK, 700)
	hc.add_child(_panel_head_rank)
	var close := UiTheme.button("Close")
	UiTheme.style_button(close, int(15 * _k))
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	_panel_head_bar = RankBar.new()
	_panel_head_bar.custom_minimum_size = Vector2(0, 10 * _k)
	_panel_head_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_panel_head_bar)
	_panel_head_next = UiTheme.label("", int(15 * _k), UiTheme.DIM, 500)
	_panel_head_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_panel_head_next)

	var rule := ColorRect.new()
	rule.color = UiTheme.EDGE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	col.add_child(UiTheme.title("MILESTONES", int(12 * _k), UiTheme.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380 * _k)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_panel_list = VBoxContainer.new()
	_panel_list.add_theme_constant_override("separation", int(6 * _k))
	_panel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_list)


func _display_name() -> String:
	return identity.village_name if identity.village_name != "" else "Your village"


## Re-read everything shown (identity may have changed, a milestone landed).
func refresh() -> void:
	_card_banner.set_banner(identity.colour(), identity.emblem())
	_card_name.text = _display_name()
	_card_rank.text = prog.rank_name().to_upper()
	_card_count.text = "%d / %d" % [prog.count_done(), Progression.MILESTONES.size()]
	_card_bar.snap(prog.rank_progress())
	_panel_head_banner.set_banner(identity.colour(), identity.emblem())
	_panel_head_name.text = _display_name()
	_panel_head_rank.text = "%s   ·   %d of %d milestones" % [prog.rank_name(),
		prog.count_done(), Progression.MILESTONES.size()]
	_panel_head_bar.snap(prog.rank_progress())
	_panel_head_next.text = prog.next_rank_line()
	_fill_list()


func _fill_list() -> void:
	for c in _panel_list.get_children():
		c.queue_free()
	var next_id := str(prog.next_up().get("id", ""))
	# Done first would bury what is next; keep the designed order but mark them.
	for m: Dictionary in Progression.MILESTONES:
		var id := str(m["id"])
		var done := prog.is_done(id)
		var row := PanelContainer.new()
		var sb := UiTheme.card(0.55 if done else 0.9, 8)
		if id == next_id:
			sb.border_color = Color(UiTheme.GOLD, 0.8)
			sb.set_border_width_all(1)
		row.add_theme_stylebox_override("panel", sb)
		_panel_list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", int(12 * _k))
		row.add_child(h)
		var mark := Label.new()
		mark.text = "✔" if done else ("➤" if id == next_id else "○")
		mark.add_theme_font_size_override("font_size", UiTheme.fs(int(18 * _k)))
		mark.add_theme_color_override("font_color", UiTheme.GOOD if done else (UiTheme.ACCENT if id == next_id else UiTheme.FAINT))
		mark.custom_minimum_size = Vector2(26 * _k, 0)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(mark)
		var tc := VBoxContainer.new()
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tc.add_theme_constant_override("separation", 0)
		h.add_child(tc)
		tc.add_child(UiTheme.label(str(m["title"]), int(17 * _k),
			UiTheme.DIM if done else UiTheme.INK, 700))
		var d := UiTheme.label(str(m["desc"]), int(13 * _k), UiTheme.FAINT if done else UiTheme.DIM, 500)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tc.add_child(d)
		var rw := UiTheme.label("+%d" % int(m["reward"]), int(15 * _k),
			UiTheme.FAINT if done else UiTheme.ACCENT, 800)
		rw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(rw)
		var coin := UiIcon.make("coin", 16.0 * _k, UiTheme.FAINT if done else Color("#ffd27a"))
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(coin)


# ------------------------------------------------------------- banners

func _on_milestone(_id: String, title: String, reward: int) -> void:
	celebrate("MILESTONE REACHED", title, _desc_for(_id), reward)
	refresh()


func _desc_for(id: String) -> String:
	for m: Dictionary in Progression.MILESTONES:
		if str(m["id"]) == id:
			return str(m["desc"])
	return ""


func _on_rank_changed(_t: int, rank_name: String) -> void:
	refresh()
	celebrate("YOUR VILLAGE GROWS", "%s is now a %s" % [_display_name(), rank_name],
		"", 0)


## Queues a banner. Used for milestones, rank-ups and the tutorial's reward.
func celebrate(kicker: String, title: String, desc: String, reward: int) -> void:
	_queue.append({"kicker": kicker, "title": title, "desc": desc, "reward": reward})
	if hud != null:
		hud.toast("%s%s" % [title, ("   +%d coins" % reward) if reward > 0 else ""], 5.0)
	if not _showing:
		_next_banner()


func _next_banner() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var b: Dictionary = _queue.pop_front()
	_b_title.text = str(b["title"])
	_b_desc.text = str(b["desc"])
	_b_desc.visible = str(b["desc"]) != ""
	_b_reward.text = ("+%d coins" % int(b["reward"])) if int(b["reward"]) > 0 else ""
	_b_reward.visible = int(b["reward"]) > 0
	(_banner.get_child(0).get_child(1).get_child(0) as Label).text = str(b["kicker"])
	_b_icon.set_banner(identity.colour(), "star")
	_banner.visible = true
	_banner.modulate.a = 0.0
	# Under a crisis banner if one is up, not on top of it.
	var rest := maxf(112.0, CrisisBanner.bottom + 14.0)
	_banner.offset_top = rest - 32.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.35)
	tw.tween_property(_banner, "offset_top", rest, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(4.6)
	tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(func() -> void:
		_banner.visible = false
		_next_banner())


# --------------------------------------------------------------- panel

func _on_card_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		set_open(true)
		_card.accept_event()
	elif e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		set_open(true)
		_card.accept_event()


func set_open(v: bool) -> void:
	if v == open:
		return
	open = v
	_panel_root.visible = v
	if v:
		refresh()
	if player != null:
		player.set_input_enabled(not v)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_PANEL:
			if open:
				set_open(false)
				get_viewport().set_input_as_handled()
			elif _can_open():
				set_open(true)
				get_viewport().set_input_as_handled()
			return
	if open and event.is_action_pressed("menu"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if player == null or not player.input_enabled:
		return false
	return hud != null and hud.visible


func _process(_delta: float) -> void:
	# Only over the world: not through the title screen, the map or the stores.
	var show := hud != null and hud.visible
	if map != null and map.open:
		show = false
	if inventory != null and inventory.get("open") == true:
		show = false
	if hud != null and hud.chat != null and hud.chat.open:
		show = false
	_root.visible = show
	if open and not show:
		set_open(false)
