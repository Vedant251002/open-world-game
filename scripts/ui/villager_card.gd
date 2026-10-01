extends Control
class_name VillagerCard
## Who somebody is, and where you stand with them.
##
## Opened with V (or Tab) while looking at a villager, or by clicking a crew
## card at the top left. Shows name and role, their mood, a relationship meter
## with its label (Stranger, Acquaintance, Friend, Confidant, or Wary and
## Resentful), their temperament, and what they remember about you, in their
## own words. Everything is read live from WorkerMemory through Relationships
## and Personality; the card holds no state of its own.
##
## Like the chat panel it lives beside the HUD's root and owns the pointer
## while it is up (the HUD hands the player's input back on close).

signal closed

const INK := UiTheme.INK
const DIM := UiTheme.DIM
const FAINT := UiTheme.FAINT

var open := false
var worker: Worker = null
var clock: GameClock
var _touch := false
var _panel: PanelContainer
var _col: VBoxContainer
var _t := 0.0


## Draws the standing: a track with a neutral tick, tier boundaries, and a bar
## from the middle out to where they stand.
class Meter extends Control:
	var value := 0.0           ## -1 .. 1
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var h := size.y
		var r := h * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.12)
		track.set_corner_radius_all(int(r))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var mid := size.x * 0.5
		var x := size.x * (value + 1.0) * 0.5
		var col := UiTheme.ALERT if value < -0.15 else (UiTheme.DIM if value < 0.12 else UiTheme.GOOD)
		if value >= 0.55:
			col = UiTheme.ACCENT
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(int(r))
		var a := minf(mid, x)
		var w := maxf(absf(x - mid), h * 0.6)
		if x < mid:
			a = x
		else:
			a = mid
		draw_style_box(fill, Rect2(Vector2(a, 0), Vector2(w, h)))
		for b: float in Relationships.BOUNDS:
			var bx := size.x * (b + 1.0) * 0.5
			draw_line(Vector2(bx, 2), Vector2(bx, h - 2), Color(0, 0, 0, 0.35), 1.0)
		draw_line(Vector2(mid, 0), Vector2(mid, h), Color(1, 1, 1, 0.5), 1.0)
		draw_circle(Vector2(clampf(x, r, size.x - r), r), r + 1.5, UiTheme.INK)


func setup(gc: GameClock, touch: bool) -> void:
	clock = gc
	_touch = touch
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	var w := 640.0 if _touch else 380.0
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -(w + 24.0)
	_panel.offset_right = -24.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := UiTheme.panel_menu()
	sb.set_content_margin_all(UiTheme.px(18))
	sb.bg_color = Color(UiTheme.PANEL_SOLID.r, UiTheme.PANEL_SOLID.g, UiTheme.PANEL_SOLID.b, 0.96)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", int(UiTheme.px(9)))
	_panel.add_child(_col)
	visible = false


func show_for(w: Worker) -> void:
	if w == null or not is_instance_valid(w):
		return
	worker = w
	open = true
	visible = true
	refresh()


func hide_card() -> void:
	if not open:
		return
	open = false
	visible = false
	worker = null
	closed.emit()


func _process(delta: float) -> void:
	if not open:
		return
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		if worker == null or not is_instance_valid(worker):
			hide_card()
		else:
			refresh()


# ------------------------------------------------------------------ content

func refresh() -> void:
	if worker == null or not is_instance_valid(worker):
		return
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var mem := worker.memory
	var big := 30 if _touch else 17
	var small := 22 if _touch else 13
	var body := 26 if _touch else 15

	# Header: name, job, close.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(UiTheme.px(10)))
	_col.add_child(head)
	var nm := UiTheme.title(mem.display_name, int(big * 1.45), UiTheme.INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(close, 34 if _touch else 20)
	close.custom_minimum_size = Vector2(90 if _touch else 36, 90 if _touch else 32)
	close.pressed.connect(hide_card)
	head.add_child(close)

	var role := "Resident"
	if worker.role != null and worker.hired:
		role = worker.role.name.capitalize()
	elif worker.role != null and worker.role.id != "citizen":
		role = worker.role.name.capitalize()
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", int(UiTheme.px(8)))
	_col.add_child(sub)
	sub.add_child(UiTheme.label(role.to_upper(), small, UiTheme.GOLD, 800))
	var st := UiTheme.label(worker.status_text(), small, DIM, 500)
	st.clip_text = true
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_child(st)

	_rule()

	# Mood.
	var morale := float(mem.disposition.get("morale", 0.7))
	var mood := HBoxContainer.new()
	mood.add_theme_constant_override("separation", int(UiTheme.px(8)))
	_col.add_child(mood)
	mood.add_child(UiTheme.label("MOOD", small, FAINT, 800))
	var mc := UiTheme.GOOD if morale >= 0.6 else (UiTheme.WARN if morale >= 0.4 else UiTheme.ALERT)
	var dot := UiIcon.make("dot", UiTheme.px(13), mc)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mood.add_child(dot)
	mood.add_child(UiTheme.label(Relationships.mood_word(mem), body, INK, 700))

	# Relationship.
	var tier := Relationships.tier(mem)
	var lab := HBoxContainer.new()
	lab.add_theme_constant_override("separation", int(UiTheme.px(8)))
	_col.add_child(lab)
	lab.add_child(UiTheme.label("TOWARD YOU", small, FAINT, 800))
	var tc := UiTheme.ALERT if tier <= Relationships.Tier.WARY else \
		(UiTheme.ACCENT if tier >= Relationships.Tier.FRIEND else INK)
	var tl := UiTheme.label(Relationships.label(mem), int(body * 1.25), tc, 800)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.add_child(tl)
	var meter := Meter.new()
	meter.value = Relationships.standing(mem)
	meter.custom_minimum_size = Vector2(0, UiTheme.px(14))
	_col.add_child(meter)
	var blurb := UiTheme.label(Relationships.blurb(mem), small, DIM, 500)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(blurb)

	_rule()

	# Temperament.
	_col.add_child(UiTheme.label("TEMPERAMENT", small, FAINT, 800))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", int(UiTheme.px(6)))
	chips.add_theme_constant_override("v_separation", int(UiTheme.px(6)))
	_col.add_child(chips)
	for c: String in Personality.chips(mem):
		chips.add_child(_chip(c, small))
	var desc := UiTheme.label(Personality.describe(mem), small, DIM, 500)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(desc)

	_rule()

	# Memories.
	_col.add_child(UiTheme.label("WHAT THEY REMEMBER ABOUT YOU", small, FAINT, 800))
	var mems := Relationships.memories(mem, 4)
	if mems.is_empty():
		var none := UiTheme.label("Nothing yet worth remembering.", body, DIM, 500)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(none)
	for m: Dictionary in mems:
		var v := float(m["valence"])
		var colr := UiTheme.GOOD if v > 0.15 else (UiTheme.ALERT if v < -0.15 else INK)
		var row := UiTheme.label("•  %s" % str(m["text"]), body, colr, 600)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2((600.0 if _touch else 340.0), 0)
		_col.add_child(row)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	_col.add_child(foot)
	foot.add_child(UiTheme.chip("V", "close", small))


func _rule() -> void:
	var r := ColorRect.new()
	r.color = UiTheme.EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(r)


func _chip(text: String, size: int) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.80, 0.50, 0.12)
	sb.border_color = UiTheme.EDGE_STRONG
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(UiTheme.px(11)))
	sb.content_margin_left = UiTheme.px(10)
	sb.content_margin_right = UiTheme.px(10)
	sb.content_margin_top = UiTheme.px(3)
	sb.content_margin_bottom = UiTheme.px(3)
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(UiTheme.label(text, size, UiTheme.INK, 700))
	return pc
