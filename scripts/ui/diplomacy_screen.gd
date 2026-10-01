extends CanvasLayer
class_name DiplomacyScreen
## The neighbours, and talking to them. Key O, or the pause menu.
##
## Left: every town over the hill, with its banner, leader and temper, how it
## feels about us, the treaty between us and what it wants and sells. Right: a
## dialogue with the chosen town's envoy or leader. You say what you mean in
## your own words — "let's trade", "I'd like an alliance", "here is 200 coins",
## "pay us tribute or else" — and the leader answers in character. What is
## agreed changes the treaty, sends a caravan, soothes or provokes, and goes
## into the chronicle. The words are understood by keywords with no API key, and
## by the model (one call per exchange) with one; see realm/diplomacy.gd.

const KEY_OPEN := KEY_O

var realm: Realm
var player: Player
var diplomacy: Diplomacy
var nb: Node
var open := false

var _root: Control
var _holder: Control
var _selected := ""
var _logs: Dictionary = {}                 ## town name -> Array[String] (bbcode)
var _cards: Dictionary = {}                ## town name -> PanelContainer
var _log_label: RichTextLabel
var _entry: LineEdit
var _head: VBoxContainer
var _status: Label
var _purse: Label
var _send: Button
var _waiting := false
var _owns_pause := false
var _was_input := true


func setup(r: Realm, p: Player) -> void:
	realm = r
	player = p
	nb = r.system("Neighbours")
	diplomacy = Diplomacy.new()
	diplomacy.setup(r)
	diplomacy.replied.connect(_on_replied)
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
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


# ---------------------------------------------------------------- opening

func open_screen() -> void:
	if open or nb == null:
		return
	open = true
	visible = true
	_owns_pause = not get_tree().paused
	if _owns_pause:
		get_tree().paused = true
		if player != null:
			_was_input = player.input_enabled
			player.set_input_enabled(false)
	if _selected == "" and not nb.list().is_empty():
		_selected = str(nb.list()[0]["name"])
	_rebuild()


func close_screen() -> void:
	if not open:
		return
	open = false
	visible = false
	if _entry != null:
		_entry.release_focus()
	if _owns_pause:
		get_tree().paused = false
		if player != null:
			player.set_input_enabled(_was_input)
	_owns_pause = false


func _can_open() -> bool:
	return player != null and player.input_enabled and not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_OPEN:
		if open:
			close_screen()
			get_viewport().set_input_as_handled()
		elif _can_open():
			open_screen()
			get_viewport().set_input_as_handled()
		return
	if open and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close_screen()


# --------------------------------------------------------------- the page

func _rebuild() -> void:
	if _holder != null:
		_holder.queue_free()
	_cards.clear()
	var vp := get_viewport().get_visible_rect().size
	var narrow := vp.x < 900.0
	_holder = MarginContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := int(UiTheme.px(8 if narrow else 28))
	for side: String in ["left", "right", "top", "bottom"]:
		_holder.add_theme_constant_override("margin_" + side, m)
	_root.add_child(_holder)
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_menu()
	sb.set_content_margin_all(UiTheme.px(10 if narrow else 20))
	panel.add_theme_stylebox_override("panel", sb)
	_holder.add_child(panel)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", int(UiTheme.px(8)))
	panel.add_child(page)

	# Header
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(UiTheme.px(12)))
	page.add_child(top)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tcol)
	tcol.add_child(UiTheme.title("NEIGHBOURS", 24, UiTheme.ACCENT))
	tcol.add_child(UiTheme.label("Over the hill, in words. Say what you want; the leaders answer as they see fit.",
		13, UiTheme.DIM, 500))
	_purse = UiTheme.label("", 16, UiTheme.ACCENT, 800)
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_purse)
	var close := Button.new()
	close.text = "Close  [O]" if not narrow else "Close"
	close.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(close, 15)
	close.pressed.connect(close_screen)
	top.add_child(close)
	var rule := ColorRect.new()
	rule.color = UiTheme.EDGE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(rule)

	if nb.list().is_empty():
		page.add_child(UiTheme.label("No other settlements are known from here.", 16, UiTheme.DIM, 500))
		return

	var body: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(UiTheme.px(14)))
	page.add_child(body)

	# The towns
	if narrow:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", int(UiTheme.px(6)))
		body.add_child(tabs)
		for t: Dictionary in nb.list():
			var b := Button.new()
			b.text = str(t["name"])
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiTheme.style_button(b, 14, str(t["name"]) == _selected)
			b.pressed.connect(_select.bind(str(t["name"])))
			tabs.add_child(b)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(UiTheme.px(430), 0)
		body.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", int(UiTheme.px(8)))
		scroll.add_child(list)
		for t2: Dictionary in nb.list():
			var card := _make_card(t2)
			_cards[str(t2["name"])] = card
			list.add_child(card)

	# The talk
	var talk := VBoxContainer.new()
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	talk.add_theme_constant_override("separation", int(UiTheme.px(8)))
	body.add_child(talk)
	_head = VBoxContainer.new()
	talk.add_child(_head)

	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UiTheme.card(0.9, 10))
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	talk.add_child(log_panel)
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.fit_content = false
	_log_label.selection_enabled = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size = Vector2(0, UiTheme.px(150))
	_log_label.add_theme_font_override("normal_font", UiTheme.font(500))
	_log_label.add_theme_font_override("bold_font", UiTheme.font(800))
	_log_label.add_theme_font_size_override("normal_font_size", UiTheme.fs(16))
	_log_label.add_theme_font_size_override("bold_font_size", UiTheme.fs(16))
	_log_label.add_theme_color_override("default_color", UiTheme.INK)
	log_panel.add_child(_log_label)

	_status = UiTheme.label("", 13, UiTheme.WARN, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	talk.add_child(_status)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", int(UiTheme.px(6)))
	chips.add_theme_constant_override("v_separation", int(UiTheme.px(6)))
	talk.add_child(chips)
	for ph: Array in [["Let us trade", "I would like us to trade. Shall I send a caravan?"],
			["Propose an alliance", "I propose an alliance between our towns."],
			["Ask for peace", "I ask for peace between us."],
			["Gift of 100 coins", "Please accept 100 coins as a gift."],
			["What do you want?", "What do you want from us?"],
			["Make a threat", "Pay us tribute, or else."],
			["Declare war", "I declare war on you."]]:
		var c := Button.new()
		c.text = ph[0]
		c.focus_mode = Control.FOCUS_NONE
		UiTheme.style_button(c, 13)
		c.pressed.connect(_say.bind(str(ph[1])))
		chips.add_child(c)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiTheme.px(8)))
	talk.add_child(row)
	_entry = LineEdit.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.placeholder_text = "say it in your own words…"
	_entry.max_length = 240
	_entry.custom_minimum_size = Vector2(0, UiTheme.px(44))
	_entry.text_submitted.connect(func(t: String) -> void: _say(t))
	row.add_child(_entry)
	_send = Button.new()
	_send.text = "Say"
	_send.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(_send, 16, true)
	_send.custom_minimum_size = Vector2(UiTheme.px(80), UiTheme.px(44))
	_send.pressed.connect(func() -> void: _say(_entry.text))
	row.add_child(_send)

	_select(_selected)


func _select(name: String) -> void:
	_selected = name
	var town: Dictionary = nb.by_name(name)
	if town.is_empty():
		return
	if not _logs.has(name):
		var intro := "[color=#b9ad96][i]%s's envoy bows, and %s of %s will hear you. %s[/i][/color]" % [
			name, town["leader"], name,
			"Say what you want; threats and gifts both have their uses."]
		_logs[name] = [intro]
	_refresh()
	_redraw_log()
	if _entry != null and not Platform.has_touch():
		_entry.grab_focus()


## Cards, header and purse, from the towns as they stand now.
func _refresh() -> void:
	if _purse != null:
		_purse.text = "%s coins" % Town.grouped(realm.town.coins)
	for name: String in _cards:
		var card: PanelContainer = _cards[name]
		var sel := name == _selected
		var sb := UiTheme.panel_active() if sel else UiTheme.card(0.8, 10)
		card.add_theme_stylebox_override("panel", sb)
		_fill_card(card, nb.by_name(name))
	if _head != null:
		for c in _head.get_children():
			c.queue_free()
		var town: Dictionary = nb.by_name(_selected)
		if not town.is_empty():
			_head.add_child(_head_row(town))
	if _status != null:
		var town2: Dictionary = nb.by_name(_selected)
		var line := diplomacy.pending_line(town2) if not town2.is_empty() else ""
		for ms: Dictionary in nb.missions():
			if str(ms["town"]) == _selected:
				line += ("  " if line != "" else "") + "%s on the road there, back day %d." % [
					"A caravan" if str(ms["kind"]) == "trade" else "An envoy", int(ms["return_day"])]
		if not diplomacy.online():
			line += ("  " if line != "" else "") + "(Offline: leaders answer from their temper.)"
		_status.text = line


func _make_card(town: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_select(str(town["name"]))
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_select(str(town["name"])))
	return card


func _fill_card(card: PanelContainer, town: Dictionary) -> void:
	for c in card.get_children():
		c.queue_free()
	card.add_child(_town_block(town, false))


## The header over the dialogue: the same facts, one town, bigger.
func _head_row(town: Dictionary) -> Control:
	return _town_block(town, true)


func _town_block(town: Dictionary, big: bool) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(UiTheme.px(12)))
	var banner := BannerIcon.make(nb.banner_colour(town), nb.banner_emblem(town), UiTheme.px(54 if big else 46))
	banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(banner)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(UiTheme.px(3)))
	row.add_child(col)
	var line1 := HBoxContainer.new()
	line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line1)
	var nm := UiTheme.label(str(town["name"]), 22 if big else 19, UiTheme.PARCHMENT, 800)
	nm.add_theme_font_override("font", UiTheme.display(800))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_child(nm)
	line1.add_child(_treaty_chip(str(town["treaty"])))
	col.add_child(UiTheme.label("%s of %s · %s · %d days %s" % [
		town["leader"], str(town["kind"]), str(town.get("personality", "")),
		int(town["distance_days"]), nb.call("_compass", town["bearing"])], 13, UiTheme.DIM, 600))
	var meter := _Meter.new()
	meter.value = nb.attitude(town)
	meter.custom_minimum_size = Vector2(0, UiTheme.px(14))
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meter)
	col.add_child(UiTheme.label("Feels %s" % nb.mood_word(town), 13, _mood_colour(float(town["disposition"])), 700))
	var trade := UiTheme.label("Wants %s  ·  Offers %s" % [
		", ".join(town["buys"]), ", ".join(town["sells"])], 13, UiTheme.INK, 500)
	trade.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(trade)
	return row


func _treaty_chip(treaty: String) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = {"none": UiTheme.DIM, "trade": UiTheme.SKY, "peace": UiTheme.GOOD, "alliance": UiTheme.GOOD,
		"war": UiTheme.ALERT, "vassal": UiTheme.ACCENT}.get(treaty, UiTheme.DIM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.16)
	sb.border_color = Color(col, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(UiTheme.px(8)))
	sb.content_margin_left = UiTheme.px(9)
	sb.content_margin_right = UiTheme.px(9)
	sb.content_margin_top = UiTheme.px(2)
	sb.content_margin_bottom = UiTheme.px(2)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_child(UiTheme.title("NO TREATY" if treaty == "none" else treaty.to_upper(), 11, col))
	return pc


static func _mood_colour(d: float) -> Color:
	if d > 0.2:
		return UiTheme.GOOD
	if d > -0.2:
		return UiTheme.DIM
	return UiTheme.ALERT


# ----------------------------------------------------------------- talking

func _say(text: String) -> void:
	var said := text.strip_edges()
	if said == "" or _waiting or _selected == "":
		return
	if _entry != null:
		_entry.text = ""
	_log(_selected, "[color=#f5c261][b]You:[/b][/color] %s" % _esc(said))
	var town: Dictionary = nb.by_name(_selected)
	if diplomacy.online():
		_waiting = true
		_send.disabled = true
		_log(_selected, "[color=#b9ad96][i]%s considers…[/i][/color]" % town["leader"])
	diplomacy.say(_selected, said)


func _on_replied(town_name: String, line: String, outcome: Dictionary) -> void:
	if _waiting:
		_waiting = false
		if _send != null:
			_send.disabled = false
		var lg: Array = _logs.get(town_name, [])
		if not lg.is_empty() and str(lg[-1]).find("considers") >= 0:
			lg.pop_back()
	var town: Dictionary = nb.by_name(town_name)
	_log(town_name, "[b]%s:[/b] %s" % [town.get("leader", town_name), _esc(line)])
	var summary := str(outcome.get("summary", ""))
	if bool(outcome.get("ok", false)) and summary != "":
		_log(town_name, "[color=#8fcc80][i]%s[/i][/color]" % _esc(summary))
	if open:
		_refresh()
		_redraw_log()
	if realm != null and bool(outcome.get("ok", false)) and str(outcome.get("action", "")) in ["trade", "alliance", "peace", "war"]:
		realm.say(summary)


func _log(town_name: String, bb: String) -> void:
	var lg: Array = _logs.get(town_name, [])
	lg.append(bb)
	while lg.size() > 40:
		lg.pop_front()
	_logs[town_name] = lg
	if open and town_name == _selected:
		_redraw_log()


func _redraw_log() -> void:
	if _log_label == null:
		return
	_log_label.clear()
	_log_label.append_text("\n\n".join(_logs.get(_selected, [])))


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


## A small bar from hostile to devoted, with a marker where the town is.
class _Meter extends Control:
	var value := 0.5

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var h := minf(size.y, 8.0)
		var bar := Rect2(0, (size.y - h) * 0.5, size.x, h)
		draw_rect(bar, Color(0, 0, 0, 0.45))
		var segs := 24
		for i in segs:
			var f := float(i) / float(segs - 1)
			var col := Color("#c4574a").lerp(Color("#d9b25a"), clampf(f * 2.0, 0.0, 1.0)) if f < 0.5 \
				else Color("#d9b25a").lerp(Color("#7fbf6a"), clampf((f - 0.5) * 2.0, 0.0, 1.0))
			col.a = 0.85
			draw_rect(Rect2(bar.position.x + bar.size.x * float(i) / segs, bar.position.y,
				bar.size.x / segs + 1.0, h), col)
		var x := bar.size.x * clampf(value, 0.0, 1.0)
		draw_rect(Rect2(x - 2.0, 0, 4.0, size.y), Color("#f6efdc"))
		draw_rect(Rect2(x - 2.0, 0, 4.0, size.y), Color(0, 0, 0, 0.5), false, 1.0)
