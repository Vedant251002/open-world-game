extends Control
class_name BannerIcon
## A village banner: a hanging pennant of cloth with a simple emblem, drawn as
## vectors so it is sharp at any size (title screen, HUD card, milestone toast).

var cloth := Color("#b8433a")
var emblem := "sun"


static func make(c: Color, e: String, px_size: float) -> BannerIcon:
	var b := BannerIcon.new()
	b.cloth = c
	b.emblem = e
	b.custom_minimum_size = Vector2(px_size * 0.78, px_size)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func set_banner(c: Color, e: String) -> void:
	cloth = c
	emblem = e
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0:
		return
	var pole := Color(0.55, 0.40, 0.22)
	var top := h * 0.06
	draw_rect(Rect2(w * 0.02, top - h * 0.03, w * 0.96, maxf(h * 0.05, 2.0)), pole)
	# The cloth: a rectangle with a swallow-tail.
	var l := w * 0.10
	var r := w * 0.90
	var b := h * 0.96
	var tail := h * 0.16
	var poly := PackedVector2Array([Vector2(l, top + h * 0.02), Vector2(r, top + h * 0.02),
		Vector2(r, b), Vector2((l + r) * 0.5, b - tail), Vector2(l, b)])
	draw_colored_polygon(poly, cloth)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(UiTheme.GOLD, 0.9), maxf(w * 0.035, 1.2), true)
	draw_emblem(self, Vector2(w * 0.5, h * 0.42), w * 0.27, emblem, UiTheme.PARCHMENT)


## Simple glyphs, centred on `c` within radius `r`.
static func draw_emblem(ci: CanvasItem, c: Vector2, r: float, kind: String, col: Color) -> void:
	var lw := maxf(r * 0.16, 1.2)
	match kind:
		"sun":
			ci.draw_circle(c, r * 0.48, col)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2.from_angle(a) * r * 0.7, c + Vector2.from_angle(a) * r * 1.0, col, lw, true)
		"wheat":
			ci.draw_line(c + Vector2(0, r), c + Vector2(0, -r * 0.9), col, lw, true)
			for i in 3:
				var y := -r * 0.6 + r * 0.5 * i
				ci.draw_line(c + Vector2(0, y + r * 0.25), c + Vector2(-r * 0.5, y - r * 0.15), col, lw, true)
				ci.draw_line(c + Vector2(0, y + r * 0.25), c + Vector2(r * 0.5, y - r * 0.15), col, lw, true)
		"tower":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.5), Vector2(r * 0.9, r * 1.5)), col)
			for i in 3:
				ci.draw_rect(Rect2(c + Vector2(-r * 0.45 + i * r * 0.36, -r * 0.85), Vector2(r * 0.18, r * 0.4)), col)
		"tree":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.7, r * 0.3),
				c + Vector2(-r * 0.7, r * 0.3)]), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.12, r * 0.3), Vector2(r * 0.24, r * 0.6)), col)
		"wave":
			for row in 2:
				var y2 := c.y - r * 0.2 + row * r * 0.6
				var pts := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					pts.append(Vector2(c.x - r + t * 2.0 * r, y2 + sin(t * TAU * 1.5) * r * 0.22))
				ci.draw_polyline(pts, col, lw, true)
		_:
			var pts2 := PackedVector2Array()
			for i in 10:
				var a2 := -PI * 0.5 + TAU * i / 10.0
				pts2.append(c + Vector2.from_angle(a2) * (r if i % 2 == 0 else r * 0.45))
			ci.draw_colored_polygon(pts2, col)
