extends Control
class_name ChatPanel
## The conversation, kept: everything you said to each person and what they
## said back, in a panel down the left of the screen.
##
## The subtitle strip shows one line and then it is gone, which is fine for
## "Here." and useless for "how many people live here?" followed by three
## more questions. This is the record: a tab per person, their side and
## yours in order, with the day and hour, and a field at the bottom that
## sends to whoever's tab is open — so a whole conversation can be had from
## here without walking up to anyone. Every line goes through the same
## dispatcher as the bar by the well; this is a window on it, not a second
## mouth.

signal sent(worker: Worker, text: String)
signal closed

const BG := Color(0.06, 0.055, 0.05, 0.90)
const INK := Color(0.94, 0.92, 0.87)
const DIM := Color(0.62, 0.60, 0.56)
const YOU := Color(0.98, 0.83, 0.42)
const ASK := Color(1.0, 0.86, 0.52)
const NO := Color("#ffb4a2")
const KEEP := 200
## What is worth keeping. Work chatter ("Nailing.") is not a conversation.
const KINDS := ["talk", "question", "refuse", "done", "plan", "answer"]

var open := false
var crew: Crew
var clock: GameClock
var history: Dictionary = {}       ## worker_id -> Array[{who, text, kind, day, hour}]
var current_id := ""
var _touch := false
var _panel: PanelContainer
var _title: Label
var _tabs: HFlowContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _entry: LineEdit
var _rows_for := ""
var _rows_count := -1
var _width := 420.0


func setup(c: Crew, gc: GameClock, touch: bool) -> void:
	crew = c
	clock = gc
	_touch = touch
	_width = 720.0 if _touch else 420.0
	_build()
	visible = false


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 14
	_panel.offset_right = 14 + _width
	_panel.offset_top = 14
	_panel.offset_bottom = -14
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = _label("Chat", 30 if _touch else 18, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 34 if _touch else 20)
	close.custom_minimum_size = Vector2(90 if _touch else 36, 90 if _touch else 32)
	close.pressed.connect(hide_panel)
	head.add_child(close)

	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 4)
	col.add_child(_tabs)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)

	_entry = LineEdit.new()
	_entry.placeholder_text = "say something…"
	_entry.custom_minimum_size = Vector2(0, 90.0 if _touch else 34.0)
	_entry.add_theme_font_size_override("font_size", 34 if _touch else 17)
	_entry.text_submitted.connect(_on_submit)
	col.add_child(_entry)


# ------------------------------------------------------------------- record

## One line of the conversation. `who` is "you" or "them".
func log_line(w: Worker, who: String, text: String, kind: String = "talk") -> void:
	if w == null or text.strip_edges() == "":
		return
	if who == "them" and kind not in KINDS:
		return
	var id: String = w.memory.worker_id
	var lines: Array = history.get(id, [])
	lines.append({"who": who, "text": text, "kind": kind,
		"day": clock.day if clock != null else 0, "hour": clock.hour if clock != null else 0.0,
		"name": w.display_name()})
	if lines.size() > KEEP:
		lines = lines.slice(lines.size() - KEEP)
	history[id] = lines
	if current_id == "":
		current_id = id
	if open and id == current_id:
		_rebuild_rows()


func people() -> Array[Worker]:
	var out: Array[Worker] = []
	var seen := {}
	if crew != null:
		for w: Worker in crew.hired():
			if is_instance_valid(w):
				out.append(w)
				seen[w.memory.worker_id] = true
		for id: String in history:
			if seen.has(id):
				continue
			var w2: Worker = crew.get_worker(id)
			if w2 != null and is_instance_valid(w2):
				out.append(w2)
	return out


func current() -> Worker:
	if current_id == "" or crew == null:
		return null
	return crew.get_worker(current_id)


func select(w: Worker) -> void:
	if w == null:
		return
	current_id = w.memory.worker_id
	if open:
		_rebuild_tabs()
		_rebuild_rows()


# ------------------------------------------------------------------- showing

func toggle() -> void:
	if open:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	open = true
	visible = true
	if current() == null:
		var ps := people()
		current_id = ps[0].memory.worker_id if not ps.is_empty() else ""
	_rebuild_tabs()
	_rebuild_rows()
	_entry.text = ""
	_entry.grab_focus()


func hide_panel() -> void:
	if not open:
		return
	open = false
	visible = false
	_entry.release_focus()
	closed.emit()


func _rebuild_tabs() -> void:
	for c: Node in _tabs.get_children():
		c.queue_free()
	for w: Worker in people():
		var b := Button.new()
		b.text = w.display_name()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 28 if _touch else 14)
		b.custom_minimum_size = Vector2(0, 70.0 if _touch else 30.0)
		if w.memory.worker_id == current_id:
			b.add_theme_color_override("font_color", YOU)
			b.add_theme_color_override("font_hover_color", YOU)
		b.pressed.connect(select.bind(w))
		_tabs.add_child(b)
	var w2 := current()
	_title.text = "Chat with %s" % w2.display_name() if w2 != null else "Chat"


func _rebuild_rows() -> void:
	var lines: Array = history.get(current_id, [])
	for c: Node in _rows.get_children():
		c.queue_free()
	_rows_for = current_id
	_rows_count = lines.size()
	var wrap := _width - 60.0
	if lines.is_empty():
		var w := current()
		var empty := _label("Nothing said yet." if w == null else "Nothing said to %s yet. Type below." % w.display_name(),
			26 if _touch else 14, DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(wrap, 0)
		_rows.add_child(empty)
	for e: Dictionary in lines:
		var you := str(e["who"]) == "you"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.size_flags_horizontal = Control.SIZE_SHRINK_END if you else Control.SIZE_SHRINK_BEGIN
		var head := _label("%s · day %d %02d:%02d" % ["You" if you else str(e.get("name", "them")),
			int(e["day"]), int(e["hour"]), int(fmod(float(e["hour"]), 1.0) * 60.0)], 22 if _touch else 12, DIM)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if you else HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(head)
		var colour := YOU if you else INK
		if not you and str(e["kind"]) == "question":
			colour = ASK
		elif not you and str(e["kind"]) == "refuse":
			colour = NO
		var body := _label(str(e["text"]), 28 if _touch else 16, colour)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(wrap * 0.85, 0)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if you else HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(body)
		_rows.add_child(box)
	# To the bottom once the rows have a size.
	call_deferred("_scroll_to_end")


func _scroll_to_end() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_submit(text: String) -> void:
	var said := text.strip_edges()
	_entry.text = ""
	var w := current()
	if w == null or said == "":
		return
	sent.emit(w, said)
	_entry.grab_focus()


static func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func snapshot() -> Dictionary:
	return {"history": history, "current": current_id}


func restore(d: Dictionary) -> void:
	history = {}
	for k: Variant in d.get("history", {}):
		var lines: Array = []
		for e: Variant in d["history"][k]:
			if e is Dictionary:
				lines.append(e)
		history[str(k)] = lines
	current_id = str(d.get("current", ""))
