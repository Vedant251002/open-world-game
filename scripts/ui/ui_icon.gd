extends Control
class_name UiIcon
## Small vector icons drawn in code, so the interface needs no image assets and
## stays sharp at any UI scale. Set `kind` and `colour`; size is the control's.

var kind := "dot"
var colour := Color.WHITE


static func make(k: String, px_size: float, c: Color = Color.WHITE) -> UiIcon:
	var i := UiIcon.new()
	i.kind = k
	i.colour = c
	i.custom_minimum_size = Vector2(px_size, px_size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_kind(k: String, c: Color) -> void:
	if k == kind and c == colour:
		return
	kind = k
	colour = c
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	match kind:
		"sun":
			draw_circle(c, r * 0.42, colour)
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2.from_angle(a) * r * 0.66, c + Vector2.from_angle(a) * r * 0.95,
					colour, maxf(s * 0.09, 1.2), true)
		"moon":
			_draw_crescent(c, r * 0.9)
		"coin":
			draw_circle(c, r * 0.9, colour.darkened(0.35))
			draw_circle(c, r * 0.76, colour)
			draw_arc(c, r * 0.5, 0.0, TAU, 20, colour.darkened(0.35), maxf(s * 0.07, 1.0), true)
		"people":
			draw_circle(c + Vector2(-r * 0.32, -r * 0.3), r * 0.26, colour)
			draw_circle(c + Vector2(r * 0.34, -r * 0.2), r * 0.22, colour.darkened(0.2))
			draw_arc(c + Vector2(-r * 0.32, r * 0.62), r * 0.5, PI, TAU, 12, colour, maxf(s * 0.16, 2.0), true)
			draw_arc(c + Vector2(r * 0.34, r * 0.66), r * 0.42, PI, TAU, 12, colour.darkened(0.2), maxf(s * 0.13, 2.0), true)
		"dot":
			draw_circle(c, r * 0.9, Color(colour, 0.28))
			draw_circle(c, r * 0.6, colour)
		"close":
			var w := maxf(s * 0.1, 1.5)
			draw_line(c + Vector2(-r, -r) * 0.55, c + Vector2(r, r) * 0.55, colour, w, true)
			draw_line(c + Vector2(r, -r) * 0.55, c + Vector2(-r, r) * 0.55, colour, w, true)
		"map":
			var pts := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(-r * 0.27, -r * 0.8),
				c + Vector2(r * 0.27, -r * 0.6), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, r * 0.6),
				c + Vector2(r * 0.27, r * 0.8), c + Vector2(-r * 0.27, r * 0.6), c + Vector2(-r * 0.8, r * 0.8),
				c + Vector2(-r * 0.8, -r * 0.6)])
			draw_polyline(pts, colour, maxf(s * 0.08, 1.2), true)
		"compass":
			draw_arc(c, r * 0.85, 0.0, TAU, 32, colour, maxf(s * 0.08, 1.2), true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.6), c + Vector2(r * 0.22, 0),
				c + Vector2(-r * 0.22, 0)]), colour)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.6), c + Vector2(r * 0.22, 0),
				c + Vector2(-r * 0.22, 0)]), colour.darkened(0.4))
		_:
			draw_circle(c, r * 0.4, colour)


## The bright disc minus an offset disc, as a strip of quads between the two
## arcs (a single concave polygon fails to triangulate).
func _draw_crescent(c: Vector2, r: float) -> void:
	var n := 14
	var dx := 0.5 * r
	var rb := 0.8 * r
	var prev_a := Vector2.ZERO
	var prev_b := Vector2.ZERO
	for i in n + 1:
		var t := float(i) / n
		var pa := c + Vector2.from_angle(lerpf(deg_to_rad(-52.0), deg_to_rad(-308.0), t)) * r
		var pb := c + Vector2(dx, 0.0) + Vector2.from_angle(lerpf(deg_to_rad(-82.0), deg_to_rad(-278.0), t)) * rb
		if i > 0:
			var quad := PackedVector2Array([prev_a, pa, pb, prev_b])
			if prev_a.distance_to(prev_b) < 0.6:
				quad = PackedVector2Array([prev_a, pa, pb])
			elif pa.distance_to(pb) < 0.6:
				quad = PackedVector2Array([prev_a, pa, prev_b])
			draw_colored_polygon(quad, colour)
		prev_a = pa
		prev_b = pb
