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
signal harvest_wanted(tile: Vector2i)

const BG := Color(0.06, 0.055, 0.05, 0.82)
const INK := Color(0.94, 0.92, 0.87)
const DIM := Color(0.72, 0.70, 0.66)
const WARN := Color(1.0, 0.86, 0.52)
const COIN := Color(0.98, 0.83, 0.42)
const DEBT := Color(0.94, 0.51, 0.42)

var player: Player
var crew: Crew
var clock: GameClock
var town: Town

var _target: Worker = null
var _crop: Node3D = null
var _purse: Label
var _keys: Label
## What the purse and the roster were last painted, so a colour is only ever
## reassigned when it has really changed.
var _in_debt := false
var _crew_tint: Array[Color] = []
var minimap: Minimap
var _typing_for: Worker = null
var _root: Control
var _prompt: Label
var _clockline: Label
var _crewbox: VBoxContainer
var _bar: PanelContainer
var _barlabel: Label
var _entry: LineEdit
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
## Sized for a thumb rather than a cursor.
var _touch := false
## On the web the text field is a real HTML input laid over the canvas —
## see WebInput for why a Godot LineEdit cannot raise the keyboard there.
var _web: WebInput = null


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
	add_child(_root)
	_root.add_child(_make_crosshair())

	_clockline = _label("", 32 if _touch else 18, INK)
	_clockline.position = Vector2(22, 18)
	_root.add_child(_clockline)

	# The purse, and nothing else about the economy.
	#
	# What used to be here was "timb 620   plan 430   thatc 340   cobb 620",
	# which is four numbers nobody can act on: the player cannot spend timber,
	# only ask for a building, and the worker is the one who says when the
	# stone has run out. One figure that goes up when the fields come in and
	# down when a house goes up is the whole of what the player needs.
	_purse = _label("", 38 if _touch else 24, COIN)
	_purse.position = Vector2(22, 58 if _touch else 44)
	_root.add_child(_purse)

	_crewbox = VBoxContainer.new()
	_crewbox.position = Vector2(22, 100 if _touch else 70)
	_crewbox.add_theme_constant_override("separation", 3)
	_root.add_child(_crewbox)
	# Rows are added as the crew grows; three to start.
	for _i in 3:
		_crewbox.add_child(_label("", 26 if _touch else 15, DIM))
		_crew_tint.append(Color.BLACK)

	# Two keys, said once and left there. A screen nobody can find is a screen
	# that does not exist, and neither the stores nor the map announce
	# themselves any other way on a keyboard — the phone build has buttons for
	# both, which is why this line is not drawn there.
	if not _touch:
		_keys = _label("[I] stores      [M] map", 14, Color(0.55, 0.53, 0.50))
		# Below the roster, which is three lines of fifteen-point text starting
		# at seventy and therefore finishes around a hundred and thirty.
		_keys.position = Vector2(22, 142)
		_root.add_child(_keys)

	_prompt = _label("", 34 if _touch else 19, INK)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -420
	_prompt.offset_right = 420
	_prompt.offset_top = -132
	_prompt.offset_bottom = -104
	_root.add_child(_prompt)

	_toast = _label("", 30 if _touch else 16, WARN)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -460
	_toast.offset_right = 460
	_toast.offset_top = -166
	_toast.offset_bottom = -142
	_root.add_child(_toast)

	_build_bar()
	_build_assumptions()
	_build_subtitle()
	_place_minimap()
	get_viewport().size_changed.connect(_reflow)
	_reflow()
	# Belt and braces: anything added above that is not the text field must not
	# be able to claim the pointer.
	_ignore_mouse(_root)


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
## entirely.
func _make_crosshair() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -3
	c.offset_top = -3
	c.offset_right = 3
	c.offset_bottom = 3
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.5)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	return c


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_bottom = -22
	_bar.add_theme_stylebox_override("panel", _panel_style())
	_bar.visible = false
	_root.add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_bar.add_child(col)

	_barlabel = _label("", 28 if _touch else 15, DIM)
	col.add_child(_barlabel)

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
	_entry.add_theme_font_size_override("font_size", 34 if _touch else 18)
	_entry.text_submitted.connect(_on_submit)
	col.add_child(_entry)


## A subtitle strip above the prompt line: who spoke, and what they said.
func _build_subtitle() -> void:
	_subtitle = PanelContainer.new()
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.offset_left = -470
	_subtitle.offset_right = 470
	_subtitle.offset_bottom = -176
	_subtitle.offset_top = -240
	_subtitle.add_theme_stylebox_override("panel", _panel_style())
	_subtitle.visible = false
	_root.add_child(_subtitle)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_subtitle.add_child(col)
	_subtitle_who = _label("", 24 if _touch else 14, DIM)
	col.add_child(_subtitle_who)
	_subtitle_line = _label("", 30 if _touch else 18, INK)
	_subtitle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_line.custom_minimum_size = Vector2(900, 0)
	col.add_child(_subtitle_line)


## Shows a line a worker has just said, for about as long as it takes to read.
## Only what is said to the player — work chatter and errand reports go by in
## the bubble as they always did, and the strip is for answers and questions.
func subtitle(w: Worker, line: String, kind: String) -> void:
	if kind not in ["talk", "question", "refuse", "done"]:
		return
	_subtitle_who.text = w.display_name()
	_subtitle_line.text = line
	_subtitle_line.add_theme_color_override("font_color",
		WARN if kind == "question" else (Color("#ffb4a2") if kind == "refuse" else INK))
	_subtitle_left = clampf(3.0 + line.length() * 0.05, 4.0, 16.0)
	_subtitle.visible = true
	# Sized to the text, so a one-liner is not a banner.
	_subtitle.offset_top = _subtitle.offset_bottom - _subtitle.get_combined_minimum_size().y


func _build_assumptions() -> void:
	_assume = PanelContainer.new()
	_assume.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_assume.offset_top = 18
	_assume.offset_bottom = 260
	_assume.add_theme_stylebox_override("panel", _panel_style())
	_assume.visible = false
	_root.add_child(_assume)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_assume.add_child(col)
	_assume_title = _label("", 26 if _touch else 15, WARN)
	_assume_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assume_title.custom_minimum_size = Vector2(390, 0)
	col.add_child(_assume_title)
	_assume_body = _label("", 26 if _touch else 15, INK)
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


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb


static func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------- runtime

## The look ray reads one layer, and both a worker and a ripe crop answer on
## it. Which one it is decides what [E] means.
func _on_looked_at(node: Node) -> void:
	_target = node as Worker
	_crop = null
	if _target == null and node is Node3D and (node as Node3D).has_meta("crop_tile"):
		_crop = node as Node3D


func _process(delta: float) -> void:
	if clock != null:
		_clockline.text = clock.clock_text()
	if town != null:
		_purse.text = "%s coins" % town.coin_line()
		# Only when it actually changes. Setting a theme override marks the
		# control dirty and queues a re-layout, so doing it unconditionally is
		# a font shaping pass every frame for a colour that changes about once
		# a session.
		var owed := town.coins < 0
		if owed != _in_debt:
			_in_debt = owed
			_purse.add_theme_color_override("font_color", DEBT if owed else COIN)

	# The roster is the people who work for you, with their job. Citizens are
	# not listed: a dozen names of people you have not spoken to is a phone
	# book, and the point of the roster is to hold the crew in your head.
	var hired: Array[Worker] = crew.hired() if crew != null else []
	while _crewbox.get_child_count() < hired.size():
		_crewbox.add_child(_label("", 26 if _touch else 15, DIM))
		_crew_tint.append(Color.BLACK)
	for i in _crewbox.get_child_count():
		var l := _crewbox.get_child(i) as Label
		if i >= hired.size():
			l.text = ""
			continue
		var w: Worker = hired[i]
		var job := w.role.name if w.role != null and w.role.id != "builder" else ""
		l.text = "%s%s — %s" % [w.display_name(),
			(" the " + job) if job != "" else "", w.status_text()]
		var tint := WARN if w.pending_question != "" else (INK if w.busy() else DIM)
		if _crew_tint[i] != tint:
			_crew_tint[i] = tint
			l.add_theme_color_override("font_color", tint)

	if _web != null and _typing_for != null:
		var said := _web.take()
		if said != "":
			_on_submit(said)
		elif _web.take_closed():
			_close_bar()

	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.text = ""
	if _subtitle_left > 0.0:
		_subtitle_left -= delta
		if _subtitle_left <= 0.0:
			_subtitle.visible = false

	if _typing_for != null:
		_prompt.text = ""
	elif _target != null:
		if _target.pending_question != "":
			_prompt.text = "%s is waiting on an answer   [E]" % _target.display_name()
		else:
			_prompt.text = "%s   [E] speak" % _target.display_name()
	elif _crop != null and is_instance_valid(_crop):
		_prompt.text = "ripe %s   [E] pick" % str(_crop.get_meta("crop_kind", "crop"))
	else:
		_prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talk") and _typing_for == null and _target != null:
		_open_bar(_target)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("talk") and _typing_for == null 			and _crop != null and is_instance_valid(_crop):
		harvest_wanted.emit(_crop.get_meta("crop_tile") as Vector2i)
		_crop = null
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu") and _typing_for != null:
		_close_bar()
		get_viewport().set_input_as_handled()


## Opens the instruction bar from outside, for the screenshot rig.
func open_for(w: Worker) -> void:
	_open_bar(w)


## Typing and mouse-look cannot both own the input. Releasing the pointer while
## the bar is open is also the only cue the player gets that the game is now
## waiting for words rather than for movement.
func _open_bar(w: Worker) -> void:
	_typing_for = w
	_bar.visible = true
	# You are talking, not navigating — and on a phone the instruction bar is
	# nearly the width of the screen and lands straight on top of the map.
	if minimap != null:
		minimap.visible = false
	if w.pending_question != "":
		_barlabel.text = "%s asked:  %s" % [w.display_name(), w.pending_question]
		_entry.placeholder_text = "answer them…"
	elif not w.hired:
		_barlabel.text = "Talking to %s, who lives here" % w.display_name()
		_entry.placeholder_text = "hire them as something, or ask them something…"
	else:
		var job := "" if w.role == null or w.role.id == "builder" else " the " + w.role.name
		_barlabel.text = "Telling %s%s what to do" % [w.display_name(), job]
		_entry.placeholder_text = "tell them what to do, or ask them something…"
	_entry.text = ""
	player.set_input_enabled(false)
	if _web != null:
		# The browser gets the whole panel: label, phrases and field together,
		# as real elements. Two fields on screen would be worse than none.
		_bar.visible = false
		var hint := "answer them…" if w.pending_question != "" else "tell them what to do, or ask them something…"
		_web.show_bar(_barlabel.text, hint, _phrases_for(w))
		return
	_entry.grab_focus()
	_show_keyboard()
	_fill_phrases(w)


func _close_bar() -> void:
	_typing_for = null
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
	var answering := w != null and w.pending_question != ""
	_close_bar()
	if w == null or said == "":
		return
	if answering:
		answer_given.emit(w, said)
	else:
		instruction_given.emit(w, said)


## Everything a worker understands, in the words that reach them.
##
## Deliberately phrased as instructions rather than as buttons: tapping one
## sends exactly the sentence shown, so a player learns what kind of thing
## can be said and then starts typing their own variations on it.
const PHRASES := [
	"build a hut", "build a bakery", "build a workshop",
	"build a tavern", "build a store", "plant a wheat field",
	"bring some hens", "wait here", "follow me",
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
	"go to the well", "follow me", "wait here",
	"work a shift at the bakery", "patrol the well and the edge of town",
	"bring in the harvest", "collect the eggs", "scout north",
	"what can you do?", "what are you doing?",
]


func _phrases_for(w: Worker) -> Array:
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
		b.add_theme_font_size_override("font_size", 34 if _touch else 18)
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
	_toast_left = seconds
