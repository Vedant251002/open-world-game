extends PanelContainer
class_name ChallengeCard
## The weekly challenge's objective, small, in the HUD's top-left stack.
## Hidden unless a run is under way (or has just ended).

var challenge: Challenge
var _clock: GameClock
var _title: Label
var _goal: Label
var _bar: ColorRect
var _fill: ColorRect
var _stats: Label


func bind(c: Challenge, clock: GameClock) -> void:
	challenge = c
	_clock = clock
	c.changed.connect(refresh)
	clock.hour_passed.connect(func(_h: float, _d: int) -> void: refresh())
	refresh()


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.card(0.85))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(UiTheme.px(250), 0)
	add_child(col)
	_title = UiTheme.title("WEEKLY", 12, UiTheme.GOLD)
	col.add_child(_title)
	_goal = UiTheme.label("", 15, UiTheme.INK, 700)
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_goal)
	_bar = ColorRect.new()
	_bar.color = Color(1, 1, 1, 0.12)
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_bar)
	_fill = ColorRect.new()
	_fill.color = UiTheme.ACCENT
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	_bar.resized.connect(refresh)
	_stats = UiTheme.label("", 13, UiTheme.DIM, 600)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_stats)


func refresh() -> void:
	if challenge == null or _title == null:
		return
	var s := challenge.spec
	visible = challenge.active and not s.is_empty()
	if not visible:
		return
	_title.text = "WEEKLY #%d" % int(s["week"])
	_goal.text = str(s["text"])
	var target := maxi(int(s["target"]), 1)
	var frac := clampf(float(challenge.progress) / float(target), 0.0, 1.0)
	_fill.size = Vector2(_bar.size.x * frac, _bar.size.y)
	_fill.color = UiTheme.GOOD if challenge.done and challenge.success \
		else (UiTheme.ALERT if challenge.done else UiTheme.ACCENT)
	var bits: Array[String] = [Challenge.progress_phrase(s, challenge.progress)]
	var day := _clock.day if _clock != null else 1
	if challenge.done:
		bits.append("done" if challenge.success else "not finished (%s)" % challenge.reason)
	else:
		bits.append("day %d / %d" % [day, int(s["deadline"])])
	if int(s["max_orders"]) > 0:
		bits.append("orders %d / %d" % [challenge.orders, int(s["max_orders"])])
	else:
		bits.append("%d orders" % challenge.orders)
	_stats.text = "  ·  ".join(bits)
