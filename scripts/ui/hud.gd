extends CanvasLayer
class_name Hud
## The whole interface: a crosshair, a line to type into, and the assumptions.
##
## Design pillar P1 says language is the only verb, so there is no build menu,
## no palette and no placement cursor — the only control that makes anything
## happen is a text field. Pillar P3 says failure must be legible, which is why
## the assumptions panel is not a popup you dismiss: it stays on screen while
## the worker is walking away, so the building you get is one you could have
## predicted before it existed.

signal instruction_given(worker: Worker, text: String)
signal answer_given(worker: Worker, text: String)
## Something said in Chat mode: talk only, never an order (Dispatcher.chat).
signal chat_given(worker: Worker, text: String)
signal harvest_wanted(tile: Vector2i)
## The player has opened the talk bar on somebody (the guided first day listens).
signal talk_opened(worker: Worker)

## The palette now lives in UiTheme, named by role. These aliases stay so the
## forty-odd call sites below do not all change at once, and so a reader can
## still see at a glance which semantic colour a line is painting.
const BG := UiTheme.PANEL
const INK := UiTheme.INK
const DIM := UiTheme.DIM
const WARN := UiTheme.WARN
const COIN := UiTheme.ACCENT
const DEBT := UiTheme.ALERT

var player: Player
var crew: Crew
var clock: GameClock
var town: Town

var _target: Worker = null
var _crop: Node3D = null
var _purse: Label
var _k := 1.0                       ## type multiplier for phones
var _status: PanelContainer
var _sky_icon: UiIcon
var _coin_icon: UiIcon
var _day_label: Label
var _time_label: Label
var _coin_word: Label
var _crew_rows: Array[Dictionary] = []
var _prompt_box: PanelContainer
var _prompt_key: PanelContainer
var _prompt_key_label: Label
var _prompt_name: Label
var _prompt_verb: Label
var _prompt_role: Label
var _prompt_state := ""
var _toast_box: PanelContainer
var _stack: VBoxContainer
var _bottom: VBoxContainer          ## subtitle, toast, prompt: stacked, never overlapping
## What the player is holding, bottom right. Empty when unarmed.
var _arms: Label
var warfare: Node = null
## The kingdom: read for the season on the clock card.
var realm: Node = null
## What the purse and the roster were last painted, so a colour is only ever
## reassigned when it has really changed.
var _in_debt := false
var _crew_tint: Array[Color] = []
var minimap: Minimap
## The weekly challenge's objective, bound by main.gd.
var challenge_card: ChallengeCard
## The Village Crier badge and the daily requests list, bound by main.gd
## (scripts/ui/crier_screen.gd, scripts/ui/requests_ui.gd).
var crier_badge: CrierScreen.Badge
var requests_card: RequestsCard
var _side: VBoxContainer           ## holds the two above, top right
var _typing_for: Worker = null
var _root: Control
## The crosshair and its target dot. The dot is the cheapest useful signal in
## the whole interface: it answers "is there someone there?" without the player
## having to read a line of text or look away from the middle of the screen.
var _crosshair: Control
var _prompt: Label
var _crewbox: VBoxContainer
var _bar: PanelContainer
var _barlabel: Label
var _entry: LineEdit
## Command or Chat, shared by the talk bar and the chat panel.
var talk_mode := ModeToggle.COMMAND
var _mode_toggle: ModeToggle
var _assume: PanelContainer
var _assume_title: Label
var _assume_body: Label
var _toast: Label
var _toast_left := 0.0
## What a worker last said, as a subtitle. The speech bubble over their head is
## where the line belongs, but it is a Label3D in a busy scene — a two-line
## answer about where the bakery is lands across a name tag and a tree, and
## the point of asking was to be able to read the answer.
var _subtitle: PanelContainer
var _subtitle_who: Label
var _subtitle_line: Label
var _subtitle_left := 0.0
var _phrases: HFlowContainer
## The conversation, kept per person, down the left of the screen.
var chat: ChatPanel
## Sized for a thumb rather than a cursor.
var _touch := false
## On the web the text field is a real HTML input laid over the canvas —
## see WebInput for why a Godot LineEdit cannot raise the keyboard there.
var _web: WebInput = null


## The villager card (see VillagerCard). Null until built.
var villager_card: VillagerCard


func setup(p: Player, c: Crew, gc: GameClock, t: Town) -> void:
	player = p
	crew = c
	clock = gc
	town = t
	layer = 10
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	if WebInput.available():
		_web = WebInput.new()
		_web.setup()
	_build()
	player.looked_at.connect(_on_looked_at)
	set_process(true)
	set_process_unhandled_input(true)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(_root)
	add_child(_root)

	# Just a dot, dead centre. It warms to gold and grows a touch when it rests
	# on somebody you can talk to or a crop you can pick (_on_looked_at).
	_crosshair = UiTheme.dot_crosshair()
	_root.add_child(_crosshair)

	# Bigger on a phone, where the 1600x900 canvas is shown at under half size,
	# but not so big the column covers a third of a landscape screen: at 1.75
	# it did. 1.4 keeps the smallest line about 14 CSS px on a 390 px phone.
	_k = 1.4 if _touch else 1.0
	_build_topleft()

	# One column at the bottom centre: what was said, what happened, and what
	# [E] will do. Hidden rows take no room, so nothing ever overlaps.
	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.add_theme_constant_override("separation", int(10 * _k))
	_bottom.offset_bottom = -(150 if _touch else 112)
	_root.add_child(_bottom)

	# Built here so the order is subtitle, toast, prompt from top to bottom.
	_build_subtitle()

	# Where a thing you are looking at is named, and what [E] will do to it.
	_prompt_box = PanelContainer.new()
	_prompt_box.add_theme_stylebox_override("panel", UiTheme.card(1.0, 18))
	_prompt_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt_box.visible = false
	_bottom.add_child(_prompt_box)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", int(10 * _k))
	_prompt_box.add_child(prow)
	_prompt_key = UiTheme.key_cap("TALK" if _touch else "E", int(15 * _k))
	_prompt_key_label = _prompt_key.get_child(0) as Label
	prow.add_child(_prompt_key)
	# "[E] Talk to  Mira  — shopkeeper": the action first, then who, then what
	# they do, so the verb is the first thing read after the key.
	_prompt_verb = _label("", int(17 * _k), DIM, 600)
	prow.add_child(_prompt_verb)
	_prompt_name = _label("", int(19 * _k), INK)
	_prompt_name.add_theme_font_override("font", UiTheme.font(800))
	prow.add_child(_prompt_name)
	_prompt_role = _label("", int(15 * _k), UiTheme.GOLD, 600)
	prow.add_child(_prompt_role)

	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UiTheme.card(1.0, 18))
	_toast_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_box.visible = false
	_bottom.add_child(_toast_box)
	_bottom.move_child(_toast_box, _prompt_box.get_index())
	_toast = _label("", int(16 * _k), WARN, 600)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_box.add_child(_toast)

	_arms = _label("", int(18 * _k), INK, 700)
	_arms.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_arms.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_arms.offset_left = -640
	_arms.offset_right = -28
	_arms.offset_top = -64
	_arms.offset_bottom = -30
	_root.add_child(_arms)

	_build_bar()
	_build_assumptions()
	_place_minimap()
	get_viewport().size_changed.connect(_reflow)
	_reflow()
	# Belt and braces: anything added above that is not the text field must not
	# be able to claim the pointer.
	_ignore_mouse(_root)

	# The chat panel lives outside _root: its tabs and field are meant to be
	# clicked, and it is only ever visible while the pointer is free.
	chat = ChatPanel.new()
	chat.name = "Chat"
	chat.setup(crew, clock, _touch)
	chat.sent.connect(_on_chat_sent)
	chat.mode_changed.connect(_set_talk_mode)
	chat.closed.connect(_on_chat_closed)
	add_child(chat)

	# Villager card (features wave 2): V / Tab on whoever you look at, or click a
	# crew card. Voices also need to know who is listening.
	villager_card = VillagerCard.new()
	villager_card.name = "VillagerCard"
	villager_card.setup(clock, _touch)
	villager_card.closed.connect(_on_card_closed)
	add_child(villager_card)
	Voice.listener = player


## The top-left stack: time and purse in one card, and a card for any crew
## member who is waiting on an answer. Everything else is in the pause menu.
func _build_topleft() -> void:
	var k := _k
	_stack = VBoxContainer.new()
	_stack.position = Vector2(24, 20)
	_stack.add_theme_constant_override("separation", int(8 * k))
	_root.add_child(_stack)

	# Time of day and money, side by side.
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", UiTheme.card())
	_stack.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12 * k))
	_status.add_child(row)
	_sky_icon = UiIcon.make("sun", 30.0 * k, Color("#ffd27a"))
	_sky_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_sky_icon)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	row.add_child(tcol)
	_day_label = UiTheme.title("DAY 1", int(13 * k), UiTheme.GOLD)
	tcol.add_child(_day_label)
	_time_label = _label("07:00", int(24 * k), INK, 800)
	tcol.add_child(_time_label)
	var sep := ColorRect.new()
	sep.color = UiTheme.EDGE
	sep.custom_minimum_size = Vector2(1, 34 * k)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	_coin_icon = UiIcon.make("coin", 24.0 * k, COIN)
	_coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_coin_icon)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 0)
	row.add_child(pcol)
	_purse = _label("0", int(24 * k), COIN, 800)
	pcol.add_child(_purse)
	_coin_word = UiTheme.title("COINS", int(12 * k), UiTheme.DIM)
	pcol.add_child(_coin_word)

	# Crew cards are added as the crew grows; three to start.
	for _i in 3:
		_add_crew_row()

	# The kingdom's own lines (people, sickness, sieges) live in the pause
	# menu now: the main screen carries only what the player acts on.

	# The weekly challenge objective (hidden unless a run is under way).
	challenge_card = ChallengeCard.new()
	_stack.add_child(challenge_card)

	# Village Crier badge and the day's requests (hidden until bound/issued).
	# Top right, clear of the roster column and the minimap.
	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -24
	side.offset_top = 20
	_side = side
	side.add_theme_constant_override("separation", int(8 * k))
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(side)
	crier_badge = CrierScreen.Badge.new()
	crier_badge.visible = false
	crier_badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(crier_badge)
	requests_card = RequestsCard.new()
	requests_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(requests_card)
	# No key hints on screen: they are listed in the pause menu.


func _add_crew_row() -> void:
	var k := _k
	var card := PanelContainer.new()
	var sb := UiTheme.card(0.86)
	sb.content_margin_top = UiTheme.px(7)
	sb.content_margin_bottom = UiTheme.px(7)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(300 * k, 0)
	card.visible = false
	_stack.add_child(card)
	# Crew sit between the status card and the realm card.
	_stack.move_child(card, 1 + _crew_rows.size())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * k))
	card.add_child(row)
	var dot := UiIcon.make("dot", 14.0 * k, DIM)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(8 * k))
	col.add_child(head)
	var nm := _label("", int(16 * k), INK, 800)
	head.add_child(nm)
	var role := _label("", int(12 * k), UiTheme.GOLD, 700)
	role.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(role)
	var st := _label("", int(13 * k), DIM, 500)
	st.clip_text = true
	col.add_child(st)
	# Clicking a crew card opens that person's villager card (only while the
	# pointer is free; see _process).
	var row_i := _crew_rows.size()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var hired_now: Array[Worker] = crew.hired()
			if row_i < hired_now.size():
				open_card(hired_now[row_i]))
	_crew_rows.append({"card": card, "dot": dot, "name": nm, "role": role, "status": st,
		"tint": Color.BLACK, "text": ""})


## Width a label needs for its text, so a one-liner is a pill and not a banner.
static func _fit(l: Label, text: String, max_w: float, size: int, weight: int = 500) -> void:
	var w := UiTheme.font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		UiTheme.fs(size)).x + 6.0
	l.custom_minimum_size = Vector2(clampf(w, 30.0, max_w), 0)


static func _ignore_mouse(node: Node) -> void:
	for child: Node in node.get_children():
		# The text field and the phrase buttons are the only things here meant
		# to be touched. They live inside the bar, which is hidden except while
		# the player is giving an order, so they cannot swallow mouse-look.
		if child is LineEdit or child is Button:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)


## Every part of this HUD except the text field is there to be looked at, not
## clicked, so all of it ignores the mouse.
##
## This matters more than it sounds. A captured mouse reports its position at
## the centre of the screen, which is exactly where the crosshair is: a ColorRect
## defaults to MOUSE_FILTER_STOP, so the crosshair swallowed every mouse-motion
## event before _unhandled_input could see it and mouse-look stopped working
## entirely. UiTheme.crosshair() sets MOUSE_FILTER_IGNORE on every blade for
## the same reason, and that comment is why it must keep doing so.
func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_bottom = -22
	var bsb := UiTheme.panel_active()
	bsb.set_corner_radius_all(int(UiTheme.px(UiTheme.R_LG)))
	_bar.add_theme_stylebox_override("panel", bsb)
	_bar.visible = false
	_root.add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_bar.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_barlabel = _label("", 28 if _touch else 16, UiTheme.ACCENT, 700)
	_barlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_barlabel)
	_mode_toggle = ModeToggle.new()
	_mode_toggle.setup(28 if _touch else 14, 70.0 if _touch else 30.0)
	_mode_toggle.changed.connect(_set_talk_mode)
	head.add_child(_mode_toggle)

	# Tappable phrases, above the field.
	#
	# On a phone the system keyboard is not something the game can insist on:
	# the touch that opens this bar is dispatched a frame later, so by the time
	# anything asks for a keyboard the browser no longer counts it as the
	# player having asked, and iOS Safari refuses. These work with no keyboard
	# at all — and on desktop they double as the answer to "what can I say?",
	# which a bare text field never tells you.
	_phrases = HFlowContainer.new()
	_phrases.add_theme_constant_override("h_separation", 6)
	_phrases.add_theme_constant_override("v_separation", 6)
	col.add_child(_phrases)

	_entry = LineEdit.new()
	_entry.placeholder_text = "tell them what to do, or ask them something…"
	_entry.custom_minimum_size = Vector2(0, 90.0 if _touch else 34.0)
	_entry.add_theme_font_size_override("font_size", 34 if _touch else 17)
	_entry.text_submitted.connect(_on_submit)
	col.add_child(_entry)


## A subtitle strip above the prompt line: who spoke, and what they said.
func _build_subtitle() -> void:
	_subtitle = PanelContainer.new()
	_subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ssb := UiTheme.panel_active()
	ssb.set_corner_radius_all(int(UiTheme.px(UiTheme.R_LG)))
	ssb.content_margin_left = UiTheme.px(20)
	ssb.content_margin_right = UiTheme.px(20)
	_subtitle.add_theme_stylebox_override("panel", ssb)
	_subtitle.visible = false
	_bottom.add_child(_subtitle)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_subtitle.add_child(col)
	_subtitle_who = UiTheme.title("", 24 if _touch else 14, UiTheme.GOLD)
	col.add_child(_subtitle_who)
	_subtitle_line = _label("", 30 if _touch else 19, INK, 600)
	_subtitle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_line.custom_minimum_size = Vector2(900, 0)
	col.add_child(_subtitle_line)


## Shows a line a worker has just said, for about as long as it takes to read.
## Only what is said to the player — work chatter and errand reports go by in
## the bubble as they always did, and the strip is for answers and questions.
func subtitle(w: Worker, line: String, kind: String) -> void:
	if chat != null:
		chat.log_line(w, "them", line, kind)
	if kind not in ["talk", "question", "refuse", "done"]:
		return
	_subtitle_who.text = w.display_name().to_upper()
	_subtitle_line.text = line
	_fit(_subtitle_line, line, 900.0 if not _touch else 1400.0, 30 if _touch else 19, 600)
	_subtitle_line.add_theme_color_override("font_color",
		WARN if kind == "question" else (Color("#ffb4a2") if kind == "refuse" else INK))
	_subtitle_left = clampf(3.0 + line.length() * 0.05, 4.0, 16.0)
	_subtitle.visible = true


func _build_assumptions() -> void:
	_assume = PanelContainer.new()
	_assume.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_assume.offset_top = 20
	_assume.offset_bottom = 21
	var asb := UiTheme.panel_active()
	asb.set_corner_radius_all(int(UiTheme.px(UiTheme.R_LG)))
	asb.content_margin_left = UiTheme.px(18)
	asb.content_margin_right = UiTheme.px(18)
	_assume.add_theme_stylebox_override("panel", asb)
	_assume.visible = false
	_root.add_child(_assume)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_assume.add_child(col)
	var acap := UiTheme.title("ASSUMPTIONS", 22 if _touch else 12, UiTheme.DIM)
	col.add_child(acap)
	_assume_title = _label("", 26 if _touch else 16, WARN, 800)
	_assume_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assume_title.custom_minimum_size = Vector2(390, 0)
	col.add_child(_assume_title)
	_assume_body = _label("", 26 if _touch else 15, INK, 500)
	_assume_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assume_body.custom_minimum_size = Vector2(390, 0)
	col.add_child(_assume_body)


## Lays the two panels out for the screen actually in front of the player.
##
## The offsets were written for a desktop window and put the assumptions
## panel four hundred pixels in from the right edge, which on a phone held
## upright is off the left of the screen entirely.
func _reflow() -> void:
	var w := get_viewport().get_visible_rect().size.x
	# The canvas is a fixed 1600 wide however tall the screen is, so this is
	# never the device width — a phone held upright scales the whole canvas
	# down by about half. Which means a control sized for a mouse ends up at
	# twenty physical pixels under a thumb, and the only thing that tells us
	# is whether there is a touchscreen.
	var bar_w := 1520.0 if _touch else 900.0
	_bar.offset_left = maxf((w - bar_w) * 0.5, 16.0)
	_bar.offset_right = -_bar.offset_left
	_place_minimap()
	var panel_w := 760.0 if _touch else 414.0
	_assume.offset_left = -panel_w - 20.0
	_assume.offset_right = -20.0
	var body_width := absf(_assume.offset_right - _assume.offset_left) - 30.0
	_assume_title.custom_minimum_size = Vector2(body_width, 0)
	_assume_body.custom_minimum_size = Vector2(body_width, 0)


## Brings the little map up once there is a town to put on it.
##
## Called from Main rather than from setup(), because the crew and the
## buildings do not exist until after the world has finished streaming and a
## map with no streets on it is worse than no map.
func show_minimap(village: Village, map: MapScreen, c: Crew,
		inventory: InventoryScreen = null) -> void:
	if minimap == null:
		minimap = Minimap.new()
		minimap.name = "Minimap"
		_root.add_child(minimap)
	minimap.setup(player, village, map, c, _touch, inventory)
	_place_minimap()


## Bottom left, where every game that has one of these puts it. Kept clear of
## the instruction bar, which is centred and only there while you are typing.
func _place_minimap() -> void:
	if minimap == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	minimap.position = Vector2(26.0, h - minimap.radius * 2.0 - 26.0)


## The theme owns both of these now, so that the palette and the scale live in
## one file. The old versions here hard-coded a border alpha, a corner radius
## and a 1px shadow at a fixed size, which meant no setting could change any of
## them and the phone build could not ask for larger type.
static func _panel_style() -> StyleBoxFlat:
	return UiTheme.panel()


static func _label(text: String, size: int, colour: Color, weight: int = 500) -> Label:
	return UiTheme.label(text, size, colour, weight)


# ------------------------------------------------------------------- runtime

## The look ray reads one layer, and both a worker and a ripe crop answer on
## it. Which one it is decides what [E] means.
func _on_looked_at(node: Node) -> void:
	_target = node as Worker
	_crop = null
	if _target == null and node is Node3D and (node as Node3D).has_meta("crop_tile"):
		_crop = node as Node3D
	# The dot grows a little on something you can act on: the player learns
	# there is someone to talk to without reading a line of text.
	var on := _target != null or _crop != null
	if _crosshair != null:
		_crosshair.scale = Vector2.ONE * (1.5 if on else 1.0)
	# Rim glow on what is being looked at, and a warm crosshair to match.
	TargetHighlight.set_target(node if (_target != null or _crop != null) else null)
	if _crosshair != null:
		_crosshair.modulate = Color(1.0, 0.86, 0.5) if (_target != null or _crop != null) \
			else Color.WHITE


func _process(delta: float) -> void:
	# Crier/requests column steps down while a held-plan panel is up top right.
	if _side != null:
		_side.offset_top = (_assume.size.y + 32.0) if _assume != null and _assume.visible else 20.0
	# Crew cards are clickable (they open the villager card) only while the
	# pointer is free, for the same reason as the chat word above.
	if player != null:
		var free := not player.input_enabled
		for r: Dictionary in _crew_rows:
			(r["card"] as Control).mouse_filter = Control.MOUSE_FILTER_STOP \
				if free else Control.MOUSE_FILTER_IGNORE
	if clock != null:
		var h := int(clock.hour)
		var tt := "%02d:%02d" % [h, int((clock.hour - h) * 60.0)]
		if _time_label.text != tt:
			_time_label.text = tt
		var dt := "DAY %d" % clock.day
		# --- seasons: "DAY 14  ·  AUTUMN 3/12" (Seasons system, scripts/realm/seasons.gd)
		if realm != null:
			var seasons: Node = realm.system("Seasons") if realm.has_method("system") else null
			if seasons != null and seasons.has_method("hud_label"):
				dt = "DAY %d  ·  %s" % [clock.day, str(seasons.call("hud_label"))]
		if _day_label.text != dt:
			_day_label.text = dt
		# Sun by day, moon from dusk to dawn; a warm tint near the horizon.
		var night := clock.hour < 5.5 or clock.hour >= 19.5
		var low := (clock.hour >= 5.5 and clock.hour < 8.0) or (clock.hour >= 17.5 and clock.hour < 19.5)
		_sky_icon.set_kind("moon" if night else "sun",
			Color("#b9c8ff") if night else (Color("#ff9d5c") if low else Color("#ffd27a")))
	if warfare != null and warfare.has_method("player_status"):
		_arms.text = str(warfare.player_status())
		var hp := float(warfare.get("player_health"))
		if hp < 100.0:
			_arms.text = ("health %d     " % int(hp)) + _arms.text
	if town != null:
		var pt := town.coin_line()
		pt = pt.replace(" coins", "")
		if _purse.text != pt:
			_purse.text = pt
		# Only when it actually changes. Setting a theme override marks the
		# control dirty and queues a re-layout.
		var owed := town.coins < 0
		if owed != _in_debt:
			_in_debt = owed
			_purse.add_theme_color_override("font_color", DEBT if owed else COIN)
			_coin_icon.set_kind("coin", DEBT if owed else COIN)

	# The roster on the main screen is only whoever is waiting on you.
	var hired: Array[Worker] = crew.hired() if crew != null else []
	while _crew_rows.size() < hired.size():
		_add_crew_row()
	for i in _crew_rows.size():
		var row: Dictionary = _crew_rows[i]
		var card: Control = row["card"]
		# Only somebody waiting on an answer earns a place on the main screen;
		# the full roster is in the pause menu.
		var want := i < hired.size() and hired[i].pending_question != ""
		if card.visible != want:
			card.visible = want
		if not want:
			continue
		var w: Worker = hired[i]
		var job := w.role.name if w.role != null and w.role.id != "builder" else "Builder"
		var nm: Label = row["name"]
		if nm.text != w.display_name():
			nm.text = w.display_name()
		var rl: Label = row["role"]
		if rl.text != job.to_upper():
			rl.text = job.to_upper()
		var st: Label = row["status"]
		var stt := w.status_text()
		if st.text != stt:
			st.text = stt
		# Status colour: amber when waiting on you, green when at work, grey idle.
		var tint := WARN if w.pending_question != "" else (UiTheme.GOOD if w.busy() else UiTheme.FAINT)
		if row["tint"] != tint:
			row["tint"] = tint
			(row["dot"] as UiIcon).set_kind("dot", tint)

	if _web != null and _typing_for != null:
		var said := _web.take()
		if said != "":
			_set_talk_mode(_web.mode())
			_on_submit(said)
		elif _web.take_closed():
			_close_bar()

	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.text = ""
			_toast_box.visible = false
	if _subtitle_left > 0.0:
		_subtitle_left -= delta
		if _subtitle_left <= 0.0:
			_subtitle.visible = false

	var pname := ""
	var pverb := ""
	var prole := ""
	var pcol := INK
	_bottom.offset_bottom = (_bar.offset_top - 14.0) if _bar.visible else -(150 if _touch else 112)
	if _typing_for != null:
		pass
	elif _target != null:
		pname = _target.display_name()
		pverb = "Talk to"
		if _target.role != null:
			prole = "— " + _target.role.name.to_lower()
		if _target.pending_question != "":
			prole = "— is waiting on an answer"
			pcol = WARN
	elif _crop != null and is_instance_valid(_crop):
		pname = str(_crop.get_meta("crop_kind", "crop"))
		pverb = "Harvest"
	var pstate := pname + "|" + pverb + "|" + prole
	if pstate != _prompt_state:
		_prompt_state = pstate
		_prompt_box.visible = pname != ""
		_prompt_name.text = pname
		_prompt_name.add_theme_color_override("font_color", pcol)
		_prompt_verb.text = pverb
		_prompt_role.text = prole
		_prompt_role.visible = prole != ""
		_prompt_role.add_theme_color_override("font_color", pcol if pcol != INK else UiTheme.GOLD)


## Tab opens the card too, but the inventory also answers to Tab, so this runs
## before it (_input) and only when somebody is under the crosshair.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_TAB and _typing_for == null \
			and villager_card != null and (_target != null or villager_card.open):
		toggle_card()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_V and _typing_for == null \
			and (chat == null or not chat.open) and villager_card != null:
		toggle_card()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu") and villager_card != null and villager_card.open:
		villager_card.hide_card()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("talk") and _typing_for == null and _target != null:
		_open_bar(_target)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("talk") and _typing_for == null 			and _crop != null and is_instance_valid(_crop):
		harvest_wanted.emit(_crop.get_meta("crop_tile") as Vector2i)
		_crop = null
		TargetHighlight.clear()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu") and _typing_for != null:
		_close_bar()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and _typing_for == null:
		toggle_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu") and chat != null and chat.open:
		chat.hide_panel()
		get_viewport().set_input_as_handled()


## The villager card: whoever is under the crosshair, or close it.
func toggle_card() -> void:
	if villager_card == null:
		return
	if villager_card.open:
		villager_card.hide_card()
	elif _target != null:
		open_card(_target)


func open_card(w: Worker) -> void:
	if villager_card == null or w == null or not is_instance_valid(w):
		return
	if _typing_for != null:
		_close_bar()
	if chat != null and chat.open:
		chat.hide_panel()
	villager_card.show_for(w)
	if minimap != null:
		minimap.visible = false
	player.set_input_enabled(false)


func _on_card_closed() -> void:
	if minimap != null and _typing_for == null:
		minimap.visible = true
	if _typing_for == null and (chat == null or not chat.open):
		player.set_input_enabled(true)


## The chat panel owns the pointer while it is up, like the bar does.
func toggle_chat() -> void:
	if chat == null:
		return
	if chat.open:
		chat.hide_panel()
		return
	if _typing_for != null:
		_close_bar()
	chat.show_panel()
	if minimap != null:
		minimap.visible = false
	player.set_input_enabled(false)


func _on_chat_closed() -> void:
	if minimap != null:
		minimap.visible = true
	if _typing_for == null:
		player.set_input_enabled(true)


## A line typed in the panel goes exactly where a line from the bar goes.
func _on_chat_sent(w: Worker, said: String) -> void:
	chat.log_line(w, "you", said)
	_route(w, said)


## Where a line goes: an answer to their question, a chat line, or an order.
## A pending question is only answered in Command mode — in Chat the same
## words are talk, and must not be taken as the answer to a work question.
func _route(w: Worker, said: String) -> void:
	if talk_mode == ModeToggle.CHAT:
		chat_given.emit(w, said)
	elif w.pending_question != "":
		answer_given.emit(w, said)
	else:
		instruction_given.emit(w, said)


## Switches Command / Chat everywhere it is shown, and re-labels the open bar.
func _set_talk_mode(m: String) -> void:
	talk_mode = ModeToggle.CHAT if m == ModeToggle.CHAT else ModeToggle.COMMAND
	if _mode_toggle != null:
		_mode_toggle.set_mode(talk_mode)
	if chat != null:
		chat.set_mode(talk_mode)
	if _typing_for != null:
		_label_bar(_typing_for)
		if _web == null:
			_fill_phrases(_typing_for)


## Opens the instruction bar from outside, for the screenshot rig.
func open_for(w: Worker) -> void:
	_open_bar(w)


## Typing and mouse-look cannot both own the input. Releasing the pointer while
## the bar is open is also the only cue the player gets that the game is now
## waiting for words rather than for movement.
func _open_bar(w: Worker) -> void:
	_typing_for = w
	Voice.focus_id = w.memory.worker_id      # voiced even from across the square
	talk_opened.emit(w)
	if chat != null:
		chat.select(w)
	_bar.visible = true
	# You are talking, not navigating — and on a phone the instruction bar is
	# nearly the width of the screen and lands straight on top of the map.
	if minimap != null:
		minimap.visible = false
	# Somebody waiting on an answer about their work is answered as a command.
	if w.pending_question != "" and talk_mode == ModeToggle.CHAT:
		_set_talk_mode(ModeToggle.COMMAND)
	_label_bar(w)
	_entry.text = ""
	player.set_input_enabled(false)
	if _web != null:
		# The browser gets the whole panel: label, phrases and field together,
		# as real elements. Two fields on screen would be worse than none.
		_bar.visible = false
		_web.show_bar(_barlabel.text, _entry.placeholder_text, _phrases_for(w),
			talk_mode, _hint_for(w, ModeToggle.COMMAND), _hint_for(w, ModeToggle.CHAT))
		return
	_entry.grab_focus()
	_show_keyboard()
	_fill_phrases(w)


func _label_bar(w: Worker) -> void:
	if talk_mode == ModeToggle.CHAT:
		_barlabel.text = "Chatting with %s" % w.display_name()
	elif w.pending_question != "":
		_barlabel.text = "%s asked:  %s" % [w.display_name(), w.pending_question]
	elif not w.hired:
		_barlabel.text = "Talking to %s, who lives here" % w.display_name()
	else:
		var job := "" if w.role == null or w.role.id == "builder" else " the " + w.role.name
		_barlabel.text = "Telling %s%s what to do" % [w.display_name(), job]
	_entry.placeholder_text = _hint_for(w, talk_mode)


func _hint_for(w: Worker, m: String) -> String:
	if m == ModeToggle.CHAT:
		return "say anything — they will answer, nothing gets done…"
	if w.pending_question != "":
		return "answer them…"
	if not w.hired:
		return "hire them as something…"
	return "tell them what to do…"


func _close_bar() -> void:
	_typing_for = null
	Voice.focus_id = ""
	_bar.visible = false
	if minimap != null:
		minimap.visible = true
	if _web != null:
		_web.hide_bar()
	_entry.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	_bar.offset_bottom = -22
	player.set_input_enabled(true)


func _on_submit(text: String) -> void:
	var w := _typing_for
	var said := text.strip_edges()
	_close_bar()
	if w == null or said == "":
		return
	if chat != null:
		chat.log_line(w, "you", said)
	_route(w, said)


## Everything a worker understands, in the words that reach them.
##
## Deliberately phrased as instructions rather than as buttons: tapping one
## sends exactly the sentence shown, so a player learns what kind of thing
## can be said and then starts typing their own variations on it.
## Chat mode: things to say, not things to have done.
const CHAT_PHRASES := ["how are you?", "what do you do?", "how is the town doing?",
	"what do you think of me?", "tell me about yourself"]

const PHRASES := [
	"build a hut", "build a bakery", "build a workshop",
	"build a tavern", "build a store", "plant a wheat field",
	"bring some hens", "wait here",
	# Questions, so the field is visibly a conversation and not a command line.
	"what are you doing?", "where is the store?", "what do we have?",
	"what did I ask you?",
]
## When a worker has asked something, these are the useful replies.
const REPLIES := [
	"yes, go ahead", "use whatever we have", "make it smaller",
	"a workshop", "a store", "never mind",
]
## For somebody who does not work for you yet. The jobs are examples; the
## point is that the sentence shape is "hire you as a ...", and a player
## types the rest.
const HIRE_PHRASES := [
	"hire you as a farmer", "hire you as a shepherd", "hire you as a guard",
	"hire you as a shopkeeper", "hire you as a scout",
	"what do you do?", "who are you?",
]
## Things a hired person other than a builder is usually asked.
const ROLE_PHRASES := [
	"go to the well", "wait here",
	"work a shift at the bakery", "patrol the well and the edge of town",
	"bring in the harvest", "collect the eggs", "scout north",
	"what can you do?", "what are you doing?",
]


func _phrases_for(w: Worker) -> Array:
	if talk_mode == ModeToggle.CHAT:
		return CHAT_PHRASES
	if w.pending_question != "":
		return REPLIES
	if not w.hired:
		return HIRE_PHRASES
	if w.role != null and w.role.id != "builder":
		return ROLE_PHRASES
	return PHRASES


func _fill_phrases(w: Worker) -> void:
	for c: Node in _phrases.get_children():
		c.queue_free()
	var list: Array = _phrases_for(w)
	for text: String in list:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		UiTheme.style_button(b, 34 if _touch else 15)
		# Forty-four physical pixels is the smallest thing a thumb hits
		# reliably. On the half-scale canvas of a phone that is ninety here.
		b.custom_minimum_size = Vector2(0, 90.0 if _touch else 44.0)
		b.pressed.connect(_on_submit.bind(text))
		_phrases.add_child(b)
	# The bar is as tall as whatever it is holding. Two rows of phrases on a
	# narrow screen is twice the height of one row on a wide one.
	await get_tree().process_frame
	_bar.offset_top = _bar.offset_bottom - _bar.get_combined_minimum_size().y


## Asks the platform for a keyboard, for the platforms that will give one.
##
## grab_focus() alone is enough on a desktop and enough on Android; iOS
## Safari wants the request to arrive inside the touch that caused it, and
## by the time a synthesised action has been through the input queue it no
## longer is. Asking explicitly costs nothing and helps where it can; the
## phrase buttons are what make the bar usable where it cannot.
func _show_keyboard() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	DisplayServer.virtual_keyboard_show(_entry.text, Rect2i(), 
		DisplayServer.KEYBOARD_TYPE_DEFAULT, -1, _entry.text.length())
	# Lift the bar clear of the keyboard if one did appear.
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb > 0:
		_bar.offset_bottom = -22 - kb
		_bar.offset_top = -160 - kb


## What the worker decided that you never said. Stays up until the next plan
## replaces it: the player has to be able to read it while the worker is still
## walking to the plot, so the building they get is one they could have seen
## coming.
func show_assumptions(w: Worker, assumptions: Array) -> void:
	if assumptions.is_empty():
		_assume_title.text = "%s assumed nothing." % w.display_name()
		_assume_body.text = "You left them no room to guess."
	else:
		_assume_title.text = "%s filled in the gaps:" % w.display_name()
		var lines: Array[String] = []
		for a: Variant in assumptions:
			lines.append("•  " + str(a))
		_assume_body.text = "\n".join(lines)
	_assume.visible = true


func toast(text: String, seconds: float = 4.0) -> void:
	_toast.text = text
	_fit(_toast, text, 860.0 if not _touch else 1400.0, int(16 * _k), 600)
	_toast_box.visible = text != ""
	_toast_left = seconds
