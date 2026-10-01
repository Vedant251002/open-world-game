extends PanelContainer
class_name RequestsCard
## The day's requests, small, in the HUD's top-left stack: who asks, what for,
## and by when. Hidden while there are none. A line ticks over to a gold
## check for a moment when it is fulfilled.

var requests: Requests
var clock: GameClock
var _box: VBoxContainer
var _t := 0.0
var _flash: Array[Dictionary] = []      ## {text, until_ms}
var _sig := ""


func bind(r: Requests, c: GameClock) -> void:
	requests = r
	clock = c
	r.changed.connect(refresh)
	r.fulfilled.connect(func(req: Dictionary) -> void:
		_flash.append({"text": "%s: %s" % [str(req["name"]), str(req["text"])],
			"until": Time.get_ticks_msec() + 4500})
		refresh())
	refresh()


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.card(0.82))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(UiTheme.px(250), 0)
	add_child(col)
	col.add_child(UiTheme.title("REQUESTS", 12, UiTheme.GOLD))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 5)
	col.add_child(_box)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	if not _flash.is_empty():
		var now := Time.get_ticks_msec()
		var before := _flash.size()
		_flash = _flash.filter(func(f: Dictionary) -> bool: return int(f["until"]) > now)
		if _flash.size() != before:
			refresh()
	# Progress ("12 / 60") changes without a signal.
	if requests != null and _signature() != _sig:
		refresh()


func _signature() -> String:
	var s := ""
	for r: Dictionary in requests.active:
		s += "%d:%s;" % [int(r["id"]), requests.progress_text(r)]
	return s


func refresh() -> void:
	if requests == null or _box == null:
		return
	_sig = _signature()
	for c in _box.get_children():
		c.queue_free()
	for f: Dictionary in _flash:
		var l := UiTheme.label("✔  " + str(f["text"]), 14, UiTheme.GOOD, 700)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(l)
	for r: Dictionary in requests.active:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_box.add_child(row)
		var who := UiTheme.label("%s  wants %s" % [str(r["name"]), str(r["text"])], 14, UiTheme.INK, 700)
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		who.custom_minimum_size = Vector2(UiTheme.px(250), 0)
		row.add_child(who)
		var left := int(r["due"]) - (clock.day if clock != null else 0)
		var bits: Array[String] = []
		var prog := requests.progress_text(r)
		if prog != "":
			bits.append(prog)
		if left < 1:
			bits.append("today is the last day")
		elif str(r["text"]).find("before day") < 0:
			bits.append("by day %d" % (int(r["due"]) + 1))
		bits.append("+%d coins" % int(r["reward"]))
		var sub := UiTheme.label("  ·  ".join(bits), 12, UiTheme.ALERT if left < 1 else UiTheme.DIM, 600)
		row.add_child(sub)
	visible = not requests.active.is_empty() or not _flash.is_empty()
