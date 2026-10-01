extends Control
class_name CrisisBanner
## The banner across the top of the screen while the town is in trouble.
##
## What is wrong (in capitals), how it stands right now, and the one order the
## player is being asked to give -- in the words they could type. When it is
## over it turns green and says what it cost, for a few seconds, then goes. A
## passing notice (winter coming, the festival) uses the same card in calmer
## colours. It reads the Crisis system (scripts/realm/crisis.gd) and owns no state.
##
## Added by main.gd as a child of the HUD; it ignores the mouse entirely.

const TONES := {
	"alert": [Color(0.96, 0.46, 0.38), Color(0.30, 0.07, 0.05, 0.92)],
	"warn":  [Color(1.0, 0.84, 0.46), Color(0.26, 0.17, 0.04, 0.92)],
	"good":  [Color(0.56, 0.80, 0.50), Color(0.07, 0.20, 0.08, 0.92)],
	"info":  [Color(0.55, 0.74, 0.92), Color(0.06, 0.14, 0.24, 0.92)],
}

var crisis: Node = null
var _panel: PanelContainer
var _style: StyleBoxFlat
var _glyph: Control
var _title: Label
var _status: Label
var _action: Label
var _more: Label
var _tone := "alert"
var _shown := ""
var _t := 0.0
var _slide := 0.0
var _poll := 0.0
## Where the banner ends on screen, 0 while it is hidden, so other top-centre
## popups (the milestone banner) can sit under it instead of on it.
static var bottom := 0.0


func bind(c: Node) -> void:
	crisis = c
	if c != null and c.has_signal("changed"):
		c.changed.connect(refresh)
	refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = UiTheme.panel(1.0)
	_style.set_border_width_all(2)
	_style.content_margin_left = UiTheme.px(16)
	_style.content_margin_right = UiTheme.px(18)
	_style.content_margin_top = UiTheme.px(10)
	_style.content_margin_bottom = UiTheme.px(11)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.visible = false
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiTheme.px(14)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	_glyph = Control.new()
	_glyph.custom_minimum_size = Vector2(UiTheme.px(38), UiTheme.px(38))
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.draw.connect(_draw_glyph)
	row.add_child(_glyph)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_title = UiTheme.title("", 17, UiTheme.ALERT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_more = UiTheme.label("", 13, UiTheme.DIM, 700)
	head.add_child(_more)
	_status = UiTheme.label("", 15, UiTheme.INK, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = UiTheme.px(300)
	col.add_child(_status)
	_action = UiTheme.label("", 15, UiTheme.ACCENT, 800)
	_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_action)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	if _panel == null:
		return
	var vw := get_viewport_rect().size.x
	var w := clampf(vw - 32.0, 280.0, UiTheme.px(680))
	_panel.custom_minimum_size.x = w
	_panel.size = Vector2(w, _panel.size.y)
	_panel.position.x = (vw - w) * 0.5


func refresh() -> void:
	if _panel == null:
		return
	var b: Dictionary = {}
	if crisis != null and crisis.has_method("banner"):
		b = crisis.call("banner")
	if b.is_empty():
		_panel.visible = false
		_shown = ""
		return
	var tone := str(b.get("tone", "alert"))
	_tone = tone
	var colours: Array = TONES.get(tone, TONES["alert"])
	_style.bg_color = colours[1]
	_style.border_color = colours[0]
	_title.add_theme_color_override("font_color", colours[0])
	var title := str(b.get("title", ""))
	var status := str(b.get("status", ""))
	var action := str(b.get("action", ""))
	if _title.text != title:
		_title.text = title
	if _status.text != status:
		_status.text = status
	_action.text = action
	_action.visible = action != ""
	var more := int(b.get("more", 0))
	_more.text = "+%d more" % more if more > 0 else ""
	if _shown != title:
		_shown = title
		_slide = 0.0
	if not _panel.visible:
		_slide = 0.0
	_panel.visible = true
	_glyph.queue_redraw()
	_panel.reset_size()
	_place()


func _process(delta: float) -> void:
	_t += delta
	_poll += delta
	if _poll >= 0.4:
		_poll = 0.0
		refresh()
	if not _panel.visible:
		bottom = 0.0
		return
	# Slides down into place, then (for an alarm) pulses its edge.
	_slide = minf(_slide + delta * 3.5, 1.0)
	var ease_t := 1.0 - pow(1.0 - _slide, 3.0)
	# Below the village card that sits at the top centre of the HUD.
	var top := 98.0 if get_viewport_rect().size.x >= 900.0 else 150.0
	_panel.position.y = lerpf(-_panel.size.y - 10.0, top, ease_t)
	bottom = top + _panel.size.y
	if _tone == "alert":
		var pulse := 0.65 + 0.35 * sin(_t * 6.0)
		_style.border_color = Color(UiTheme.ALERT.r, UiTheme.ALERT.g * (0.8 + 0.2 * pulse), UiTheme.ALERT.b, 1.0)
		_glyph.queue_redraw()


func _draw_glyph() -> void:
	var s := _glyph.size
	var c := s * 0.5
	var col: Color = (TONES.get(_tone, TONES["alert"]) as Array)[0]
	if _tone == "good":
		# A check mark.
		_glyph.draw_arc(c, s.x * 0.46, 0.0, TAU, 24, Color(col, 0.35), 2.0, true)
		_glyph.draw_polyline(PackedVector2Array([c + Vector2(-s.x * 0.22, 0.0), c + Vector2(-s.x * 0.05, s.y * 0.17),
			c + Vector2(s.x * 0.24, -s.y * 0.16)]), col, 3.5, true)
		return
	if _tone == "info":
		_glyph.draw_arc(c, s.x * 0.46, 0.0, TAU, 24, col, 2.5, true)
		_glyph.draw_circle(c + Vector2(0, -s.y * 0.2), 2.4, col)
		_glyph.draw_line(c + Vector2(0, -s.y * 0.06), c + Vector2(0, s.y * 0.24), col, 3.5, true)
		return
	# A warning triangle with a flickering exclamation mark.
	var pulse := 0.75 + 0.25 * sin(_t * 9.0)
	var pts := PackedVector2Array([Vector2(c.x, 2.0), Vector2(s.x - 2.0, s.y - 4.0), Vector2(2.0, s.y - 4.0)])
	_glyph.draw_colored_polygon(pts, Color(col, 0.22 * pulse + 0.1))
	_glyph.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), col, 2.5, true)
	_glyph.draw_line(Vector2(c.x, s.y * 0.35), Vector2(c.x, s.y * 0.65), col, 3.5, true)
	_glyph.draw_circle(Vector2(c.x, s.y * 0.79), 2.2, col)
