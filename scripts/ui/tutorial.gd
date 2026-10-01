extends CanvasLayer
class_name Tutorial
## The guided first day. Not a wall of text: one small objective card at a
## time, in the world, that moves on by itself when the player really does the
## thing (walks up and talks, gives an order, watches it built, asks, hires,
## opens the map). Mira greets them; the first finished building pays a
## reward; everything can be skipped (K, or the Skip button on the card).
##
## It only listens. The same signals the game already emits drive it, so it
## cannot get out of step with what is actually happening, and a test can walk
## it through by emitting those signals.

signal step_changed(step_id: String)
signal finished(skipped: bool)

## id, step title, what to do. {who} is filled with the person to walk to.
const STEPS: Array[Dictionary] = [
	{"id": "talk", "title": "Meet Mira",
		"body": "Mira keeps the store off the square. Walk over to her and speak.",
		"key": true, "who": "mira"},
	{"id": "order", "title": "Ask for something",
		"body": "You cannot build anything yourself; you ask. Tobias is the builder. Go to him, press the key, and say:",
		"phrase": "build a small hut", "key": true, "who": "tobias"},
	{"id": "assume", "title": "Read the assumptions",
		"body": "Whatever you left unsaid, he filled in. The panel at the top right lists those choices. Say \"no, thatch\" any time to correct him."},
	{"id": "build", "title": "Watch it rise",
		"body": "Tobias fetches the materials and builds on the nearest plot. Follow him over, or keep exploring."},
	{"id": "ask", "title": "Ask a question",
		"body": "Anyone will answer. Talk to somebody and ask, for example:",
		"phrase": "how is the town doing?", "key": true},
	{"id": "hire", "title": "Take someone on",
		"body": "Find a villager in the street, talk to them and offer a job:",
		"phrase": "I'd like to hire you as a farmer", "key": true},
	{"id": "map", "title": "Open the map",
		"body": "Every building is numbered, with who works and lives there.",
		"mapkey": true},
	{"id": "done", "title": "That is the whole loop",
		"body": "Ask, watch, correct, grow. The village is yours."},
]

const REWARD_COINS := 500
const ASSUME_SECONDS := 14.0
const DONE_SECONDS := 8.0

var hud: Hud
var crew: Crew
var dispatch: Dispatcher
var town: Town
var map: MapScreen
var player: Player
var clock: GameClock
var ms_ui: MilestonesUi
var village_name := ""

var step := 0
var active := false
var skipped := false
var complete := false

var _touch := false
var _k := 1.0
var _hired_base := 0
var _step_t := 0.0
var _root: Control
var _card: PanelContainer
var _dots: HBoxContainer
var _kicker: Label
var _title: Label
var _body: Label
var _phrase_box: PanelContainer
var _phrase: Label
var _live: Label
var _key_row: HBoxContainer
var _key_cap_host: HBoxContainer
var _skip: Button
var _gotit: Button
var _hint := ""


func setup(h: Hud, c: Crew, d: Dispatcher, t: Town, m: MapScreen, p: Player,
		gc: GameClock, ui: MilestonesUi = null) -> void:
	hud = h
	crew = c
	dispatch = d
	town = t
	map = m
	player = p
	clock = gc
	ms_ui = ui
	layer = 12
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	_k = 1.4 if _touch else 1.0
	_build()
	_root.visible = false
	hud.talk_opened.connect(func(w: Worker) -> void: notify("talk", w))
	hud.instruction_given.connect(func(_w: Worker, text: String) -> void: notify("said", text))
	hud.answer_given.connect(func(_w: Worker, text: String) -> void: notify("said", text))
	dispatch.plan_accepted.connect(func(w: Worker, a: Array) -> void: notify("plan", [w, a]))
	crew.job_done.connect(func(w: Worker, _p: VoxelPatch) -> void: notify("job_done", w))
	crew.job_failed.connect(func(w: Worker, _e: Dictionary) -> void: notify("job_failed", w))
	crew.roster_changed.connect(func() -> void: notify("roster"))


# ------------------------------------------------------------------ flow

## Begin (or resume) the tutorial. `at` is a step index from a save.
func start(at: int = 0) -> void:
	if complete or skipped:
		return
	active = true
	step = clampi(at, 0, STEPS.size() - 1)
	# A build that was in flight when the game was saved is not coming back.
	if str(STEPS[step]["id"]) == "build":
		step -= 1
	_enter(step, at == 0)


func current_id() -> String:
	return str(STEPS[step]["id"]) if step < STEPS.size() else ""


func _enter(i: int, greet: bool = false) -> void:
	step = i
	_step_t = 0.0
	_hint = ""
	var id := current_id()
	if id == "hire":
		_hired_base = crew.hired().size()
	if greet and id == "talk":
		_mira_says("%sMorning. I am Mira; I keep the store. Come over and say hello, and I will show you how things are done here."
			% (("Welcome to %s. " % village_name) if village_name != "" else ""))
	_refresh_card()
	_root.visible = true
	step_changed.emit(id)


func _advance() -> void:
	if not active:
		return
	if step >= STEPS.size() - 1:
		_finish(false)
		return
	_flash()
	_enter(step + 1)


func skip() -> void:
	if not active:
		return
	skipped = true
	_finish(true)


func _finish(was_skipped: bool) -> void:
	active = false
	complete = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		_root.visible = false
		_root.modulate.a = 1.0)
	finished.emit(was_skipped)


## Every event the game emits that the tutorial cares about comes through here.
func notify(kind: String, data: Variant = null) -> void:
	if not active:
		return
	var id := current_id()
	match kind:
		"talk":
			if id == "talk":
				var w := data as Worker
				if w != null and w.memory.worker_id == "mira":
					_mira_says("Good to meet you. I only sell. Anything that needs building is Tobias's trade; he waits at the workshop.")
				_advance()
			elif id == "order" and data is Worker and (data as Worker).memory.worker_id == "mira":
				_mira_says("That is Tobias's trade, not mine. Look for the builder at the workshop.")
		"plan":
			if id == "order":
				_advance()
		"job_done":
			if id == "build" or id == "order" or id == "assume":
				_celebrate_first_build(data as Worker)
				_enter(_index_of("ask"))
		"job_failed":
			if id == "build" or id == "assume":
				_hint = "That did not work out. Ask again, perhaps simpler."
				_enter(_index_of("order"))
		"said":
			if id == "ask" and _looks_like_question(str(data)):
				_advance()
		"roster":
			if id == "hire" and crew.hired().size() > _hired_base:
				_advance()
			elif id == "hire":
				_hired_base = mini(_hired_base, crew.hired().size())
		"map":
			if id == "map":
				_advance()
		"gotit":
			if id == "assume":
				_advance()


func _index_of(id: String) -> int:
	for i in STEPS.size():
		if str(STEPS[i]["id"]) == id:
			return i
	return 0


static func _looks_like_question(t: String) -> bool:
	var s := t.strip_edges().to_lower()
	if s.is_empty():
		return false
	if s.ends_with("?"):
		return true
	for w in ["how", "what", "where", "who", "why", "when", "which", "is ", "are ", "do ", "does ", "can "]:
		if s.begins_with(w):
			return true
	return false


func _celebrate_first_build(w: Worker) -> void:
	town.coins += REWARD_COINS
	if ms_ui != null:
		ms_ui.celebrate("YOUR FIRST BUILDING", "It stands!",
			"%s finished what you asked for." % (w.display_name() if w != null else "Your crew"),
			REWARD_COINS)
	elif hud != null:
		hud.toast("Your first building stands!   +%d coins" % REWARD_COINS, 6.0)
	var mira := crew.get_worker("mira")
	if mira != null and hud != null:
		hud.subtitle(mira, "Look at that. A thing that was not there this morning, and all from a sentence.", "talk")


func _mira_says(line: String) -> void:
	var mira := crew.get_worker("mira")
	if mira != null and hud != null:
		hud.subtitle(mira, line, "talk")


# ------------------------------------------------------------------ save

func snapshot() -> Dictionary:
	return {"step": step, "complete": complete, "skipped": skipped}


## An older save has no record: it is not a new player.
func restore(d: Dictionary) -> void:
	if d.is_empty() or bool(d.get("complete", false)):
		complete = true
		skipped = bool(d.get("skipped", false))
		active = false
		return
	start(int(d.get("step", 0)))


# -------------------------------------------------------------------- ui

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(_root)
	add_child(_root)

	_card = PanelContainer.new()
	var sb := UiTheme.panel_active()
	sb.border_color = Color(UiTheme.GOLD, 0.75)
	sb.set_corner_radius_all(int(UiTheme.px(UiTheme.R_LG)))
	sb.content_margin_left = UiTheme.px(18)
	sb.content_margin_right = UiTheme.px(18)
	_card.add_theme_stylebox_override("panel", sb)
	_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.offset_right = -20
	_card.offset_left = -20 - (400 if not _touch else 640)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(7 * _k))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_kicker = UiTheme.title("FIRST DAY", int(12 * _k), UiTheme.GOLD)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_kicker)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", int(5 * _k))
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_dots)

	_title = UiTheme.label("", int(24 * _k), UiTheme.PARCHMENT, 800)
	_title.add_theme_font_override("font", UiTheme.display(800))
	col.add_child(_title)
	_body = UiTheme.label("", int(15 * _k), UiTheme.INK, 500)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)

	_phrase_box = PanelContainer.new()
	var psb := UiTheme.card(0.9, 8)
	psb.bg_color = Color(1, 0.92, 0.75, 0.10)
	psb.border_color = Color(UiTheme.GOLD, 0.55)
	psb.set_border_width_all(1)
	_phrase_box.add_theme_stylebox_override("panel", psb)
	_phrase_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_phrase_box)
	_phrase = UiTheme.label("", int(17 * _k), UiTheme.ACCENT, 700)
	_phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phrase_box.add_child(_phrase)

	_live = UiTheme.label("", int(14 * _k), UiTheme.SKY, 600)
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_live)

	_key_row = HBoxContainer.new()
	_key_row.add_theme_constant_override("separation", int(10 * _k))
	_key_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_key_row)
	_key_cap_host = HBoxContainer.new()
	_key_cap_host.add_theme_constant_override("separation", int(6 * _k))
	_key_cap_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_cap_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_row.add_child(_key_cap_host)

	_gotit = UiTheme.button("Got it")
	UiTheme.style_button(_gotit, int(14 * _k), true)
	_gotit.focus_mode = Control.FOCUS_NONE
	_gotit.mouse_filter = Control.MOUSE_FILTER_STOP
	_gotit.pressed.connect(func() -> void: notify("gotit"))
	_key_row.add_child(_gotit)
	_skip = UiTheme.button("Skip tutorial")
	UiTheme.style_button(_skip, int(13 * _k))
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip.pressed.connect(skip)
	_key_row.add_child(_skip)
	if not _touch:
		_key_row.add_child(UiTheme.key_cap("K", int(12 * _k)))
		_key_row.move_child(_key_row.get_child(_key_row.get_child_count() - 1), _skip.get_index() + 1)


func _refresh_card() -> void:
	var s: Dictionary = STEPS[step]
	var id := str(s["id"])
	_kicker.text = "FIRST DAY  ·  STEP %d OF %d" % [mini(step + 1, STEPS.size() - 1), STEPS.size() - 1] \
		if id != "done" else "FIRST DAY  ·  COMPLETE"
	_title.text = str(s["title"])
	var body := str(s["body"])
	if _hint != "":
		body = _hint + "  " + body
	_body.text = body
	_phrase_box.visible = s.has("phrase")
	if s.has("phrase"):
		_phrase.text = "“%s”" % str(s["phrase"])
	_gotit.visible = id == "assume"
	_skip.visible = id != "done"
	# Step dots.
	for c in _dots.get_children():
		c.queue_free()
	for i in STEPS.size() - 1:
		var d := UiIcon.make("dot", 9.0 * _k,
			UiTheme.GOLD if i == step else (UiTheme.GOOD if i < step else UiTheme.FAINT))
		_dots.add_child(d)
	# The key to press.
	for c in _key_cap_host.get_children():
		c.queue_free()
	if s.get("key", false) and not _touch_hide_keys():
		_key_cap_host.add_child(UiTheme.chip("E", "to talk", int(13 * _k)))
	elif s.get("key", false):
		_key_cap_host.add_child(UiTheme.chip("TALK", "button", int(13 * _k)))
	elif s.get("mapkey", false):
		_key_cap_host.add_child(UiTheme.chip("MAP" if _touch else "M", "to open the map", int(13 * _k)))
	_update_live()


func _touch_hide_keys() -> bool:
	return _touch


func _flash() -> void:
	if _card == null:
		return
	_card.modulate = Color(1.5, 1.4, 1.0)
	var tw := create_tween()
	tw.tween_property(_card, "modulate", Color.WHITE, 0.5)


## "Mira is 23 m away, ahead of you": the thing a new player actually needs.
func _update_live() -> void:
	var s: Dictionary = STEPS[step]
	var id := str(s["id"])
	var line := ""
	if s.has("who"):
		var w := crew.get_worker(str(s["who"]))
		if w != null and player != null:
			line = "%s is %s." % [w.display_name(), _where(w.global_position)]
	elif id == "build":
		var t := crew.get_worker("tobias")
		if t != null:
			line = "%s: %s." % [t.display_name(), t.status_text()]
	elif id == "hire":
		line = "Those with a bed but no job are the ones to ask."
	_live.text = line
	_live.visible = line != ""


func _where(at: Vector3) -> String:
	var off := at - player.global_position
	off.y = 0.0
	var d := off.length()
	if d < 3.5:
		return "right here"
	var fwd := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var right := Vector3(cos(player.yaw), 0.0, -sin(player.yaw))
	var f := off.normalized().dot(fwd)
	var r := off.normalized().dot(right)
	var dir := "ahead"
	if f < -0.5:
		dir = "behind you"
	elif r > 0.5:
		dir = "to your right"
	elif r < -0.5:
		dir = "to your left"
	return "%d m away, %s" % [int(round(d)), dir]


func _process(delta: float) -> void:
	if not active:
		return
	_step_t += delta
	# Visible only over the world.
	var show := hud != null and hud.visible
	if map != null and map.open:
		if current_id() == "map":
			notify("map")
		show = false
	if hud != null and hud.chat != null and hud.chat.open:
		show = false
	_root.visible = show and active
	_update_live_throttled()
	if current_id() == "assume" and _step_t > ASSUME_SECONDS:
		notify("gotit")
	elif current_id() == "done" and _step_t > DONE_SECONDS:
		_finish(false)


var _live_t := 0.0


func _update_live_throttled() -> void:
	_live_t -= get_process_delta_time()
	if _live_t <= 0.0:
		_live_t = 0.4
		_update_live()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_K and current_id() != "done":
			skip()
			get_viewport().set_input_as_handled()
