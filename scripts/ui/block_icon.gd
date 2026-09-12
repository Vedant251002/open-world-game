extends RefCounted
class_name BlockIcon
## Draws one material as an isometric cube with its own surface on it.
##
## The first version of the inventory drew every material as the same cube in a
## different colour, and it read as thirty copies of one item. Colour alone is
## not enough: half the palette is grey stone of one kind or another, and at
## thirty pixels a side "grey" and "slightly different grey" are the same
## picture. Minecraft solves this with a texture per block, and the texture is
## doing most of the work — you know cobblestone by its lumps and planks by
## their boards long before you notice their colour.
##
## There are no textures here and there should not be: the world is drawn with
## a procedural grain shader, so a hand-painted icon would be a second source of
## truth about what a material looks like. Instead each face is treated as a
## unit square and a small pattern is drawn into it — boards, courses, ribs,
## speckle. It costs a dozen lines per icon, matches the material it names, and
## a new material inherits a sensible default rather than vanishing.
##
## The mapping from a face to its unit square is the only fiddly part. All three
## faces of an isometric cube are parallelograms, so a point (a, b) in [0,1]
## squared lands at origin + u*a + v*b, and every pattern below is written in
## that space and never has to know which face it is on or how big the icon is.

## Which surface each material gets. Anything not named here falls through to
## "plain", which is a clean shaded cube — the same thing every material used
## to get, now reserved for the ones with nothing to say.
const SURFACE := {
	"timber": "grain", "dark_oak": "grain",
	"plank": "boards",
	"brick": "courses",
	"sandstone": "strata",
	"granite": "speckle", "cobble": "cobbles",
	"concrete": "aggregate", "concrete_slab": "aggregate",
	"rebar_concrete": "rebar",
	"steel_frame": "ribs", "corrugated_steel": "ribs", "sheet_metal": "ribs",
	"glass": "pane", "reinforced_glass": "mesh",
	"plastic_panel": "panel",
	"carbon_composite": "weave",
	"thatch": "straw",
	"clay_tile": "tiles", "asphalt_shingle": "tiles",
	"solar_panel": "cells",
	"dirt": "specks", "sand": "specks", "asphalt": "specks",
	"gravel": "pebbles",
	"grass": "blades",
	"painted_white": "plain", "painted_red": "plain", "matte_black": "plain",
	"chrome": "gloss",
	"neon_strip": "neon",
	"food": "grains",
	"cloth": "weave",
}

## Speckle positions, fixed rather than random. A pattern that reshuffles every
## time the panel redraws is a pattern that crawls, and the inventory redraws
## many times a second.
const SCATTER: Array[Vector2] = [
	Vector2(0.18, 0.24), Vector2(0.62, 0.16), Vector2(0.83, 0.47),
	Vector2(0.34, 0.58), Vector2(0.11, 0.72), Vector2(0.71, 0.79),
	Vector2(0.47, 0.35), Vector2(0.26, 0.90), Vector2(0.90, 0.68),
	Vector2(0.55, 0.63), Vector2(0.39, 0.11), Vector2(0.77, 0.31),
]


## One cube, centred on `at`, `w` wide. `fade` dims the whole thing for a
## material the stores have none of, or none the town can work.
static func draw(on: CanvasItem, at: Vector2, w: float, mat: String,
		base: Color, fade: float) -> void:
	var hw := w * 0.5
	var qh := w * 0.25            ## the 2:1 squash that makes it isometric
	var bh := w * 0.62            ## how tall the body stands

	var t := at + Vector2(0.0, -bh * 0.5 - qh)
	var rt := at + Vector2(hw, -bh * 0.5)
	var mid := at + Vector2(0.0, -bh * 0.5 + qh)
	var lt := at + Vector2(-hw, -bh * 0.5)
	var rb := at + Vector2(hw, bh * 0.5 - qh)
	var bot := at + Vector2(0.0, bh * 0.5)
	var lb := at + Vector2(-hw, bh * 0.5 - qh)

	var a := base.a
	var top := base.lightened(0.20)
	var left := base.darkened(0.14)
	var right := base.darkened(0.34)
	top.a = a * fade
	left.a = a * fade
	right.a = a * fade

	var surface := str(SURFACE.get(mat, "plain"))
	var line := maxf(w * 0.028, 0.9)

	# Top face: origin at the left corner, across to the back and to the front.
	on.draw_colored_polygon(PackedVector2Array([t, rt, mid, lt]), top)
	_paint(on, lt, t - lt, mid - lt, surface, top, fade, line, true)

	on.draw_colored_polygon(PackedVector2Array([lt, mid, bot, lb]), left)
	_paint(on, lt, mid - lt, lb - lt, surface, left, fade, line, false)

	on.draw_colored_polygon(PackedVector2Array([mid, rt, rb, bot]), right)
	_paint(on, mid, rt - mid, bot - mid, surface, right, fade, line, false)

	# The silhouette last, over the pattern, so nothing runs off an edge.
	var ink := Color(0.04, 0.03, 0.03, 0.6 * fade)
	on.draw_polyline(PackedVector2Array([t, rt, rb, bot, lb, lt, t]), ink, line * 1.2)
	on.draw_polyline(PackedVector2Array([lt, mid, rt]), ink, line)
	on.draw_line(mid, bot, ink, line)


# ------------------------------------------------------------- the surfaces
# Everything below works in the unit square of one face. `o` is its corner,
# `u` runs one way across it and `v` the other, both as screen vectors.

static func _paint(on: CanvasItem, o: Vector2, u: Vector2, v: Vector2,
		surface: String, face: Color, fade: float, line: float,
		is_top: bool) -> void:
	# Grooves are the face in shadow, highlights the face catching the light.
	# Taking both from the face colour rather than from a fixed grey is what
	# keeps a pattern legible on dark slate and on pale sandstone alike.
	var cut := face.darkened(0.34)
	var lit := face.lightened(0.30)
	cut.a = face.a
	lit.a = face.a

	match surface:
		"boards":
			for i in 3:
				var y := (i + 1) / 4.0
				_seg(on, o, u, v, 0.0, y, 1.0, y, cut, line)
			# A short cross-join, so boards read as boards and not as stripes.
			_seg(on, o, u, v, 0.44, 0.0, 0.44, 0.25, cut, line * 0.8)
			_seg(on, o, u, v, 0.68, 0.5, 0.68, 0.75, cut, line * 0.8)
		"grain":
			for i in 3:
				var x := (i + 1) / 4.0
				_seg(on, o, u, v, x, 0.06, x, 0.94, cut, line * 0.9)
			_seg(on, o, u, v, 0.30, 0.30, 0.30, 0.70, lit, line * 0.7)
		"courses":
			for i in 2:
				var y := (i + 1) / 3.0
				_seg(on, o, u, v, 0.0, y, 1.0, y, cut, line)
			# Staggered perpends, which is what makes brick look like brick.
			_seg(on, o, u, v, 0.5, 0.0, 0.5, 1.0 / 3.0, cut, line)
			_seg(on, o, u, v, 0.25, 1.0 / 3.0, 0.25, 2.0 / 3.0, cut, line)
			_seg(on, o, u, v, 0.75, 1.0 / 3.0, 0.75, 2.0 / 3.0, cut, line)
			_seg(on, o, u, v, 0.5, 2.0 / 3.0, 0.5, 1.0, cut, line)
		"strata":
			_seg(on, o, u, v, 0.0, 0.34, 1.0, 0.30, cut, line)
			_seg(on, o, u, v, 0.0, 0.68, 1.0, 0.72, cut, line)
			_seg(on, o, u, v, 0.0, 0.50, 1.0, 0.49, lit, line * 0.6)
		"cobbles":
			# Four lumps with mortar between them, drawn as a broken grid so
			# nothing lines up the way brick does.
			_seg(on, o, u, v, 0.0, 0.46, 0.46, 0.52, cut, line)
			_seg(on, o, u, v, 0.46, 0.52, 1.0, 0.42, cut, line)
			_seg(on, o, u, v, 0.40, 0.0, 0.46, 0.52, cut, line)
			_seg(on, o, u, v, 0.62, 0.48, 0.68, 1.0, cut, line)
			_dot(on, o, u, v, 0.22, 0.24, line * 0.8, lit)
			_dot(on, o, u, v, 0.74, 0.22, line * 0.7, lit)
		"speckle":
			# Granite: coarse mineral flecks, light and dark together. Distinct
			# from "specks", which is loose material rather than cut stone.
			for i in 7:
				_dot(on, o, u, v, SCATTER[i].x, SCATTER[i].y,
					line * (0.75 if i % 3 == 0 else 0.5),
					lit if i % 2 == 0 else cut)
		"aggregate":
			for i in 5:
				_dot(on, o, u, v, SCATTER[i].x, SCATTER[i].y, line * 0.55, cut)
			_dot(on, o, u, v, SCATTER[7].x, SCATTER[7].y, line * 0.5, lit)
		"rebar":
			for i in 5:
				_dot(on, o, u, v, SCATTER[i].x, SCATTER[i].y, line * 0.5, cut)
			_seg(on, o, u, v, 0.12, 0.5, 0.88, 0.5, lit, line * 0.7)
			_seg(on, o, u, v, 0.5, 0.12, 0.5, 0.88, lit, line * 0.7)
		"ribs":
			for i in 5:
				var x := (i + 1) / 6.0
				_seg(on, o, u, v, x, 0.05, x, 0.95, cut if i % 2 == 0 else lit,
					line * 0.75)
		"pane":
			# A frame and one glint. Glass is mostly what you can see through
			# it, so the icon says "empty in the middle" as loudly as it can.
			_quad(on, o, u, v, 0.14, 0.14, 0.86, 0.86, cut, line * 0.8)
			_seg(on, o, u, v, 0.24, 0.72, 0.66, 0.24, lit, line * 1.1)
			_seg(on, o, u, v, 0.46, 0.78, 0.74, 0.46, lit, line * 0.7)
		"mesh":
			_quad(on, o, u, v, 0.12, 0.12, 0.88, 0.88, cut, line * 0.8)
			for i in 2:
				var g := (i + 1) / 3.0
				_seg(on, o, u, v, g, 0.12, g, 0.88, cut, line * 0.55)
				_seg(on, o, u, v, 0.12, g, 0.88, g, cut, line * 0.55)
			_seg(on, o, u, v, 0.26, 0.70, 0.62, 0.30, lit, line * 0.8)
		"panel":
			_quad(on, o, u, v, 0.16, 0.16, 0.84, 0.84, cut, line * 0.8)
		"weave":
			for i in 3:
				var g := (i + 1) / 4.0
				_seg(on, o, u, v, g, 0.08, g, 0.92, cut, line * 0.6)
				_seg(on, o, u, v, 0.08, g, 0.92, g, lit, line * 0.5)
		"straw":
			# Loose diagonal stalks of uneven length — a thatched roof read from
			# below, which is the only way anybody sees one.
			for i in 5:
				var x := i / 5.0 + 0.08
				_seg(on, o, u, v, x, 0.9, x + 0.16, 0.12, cut, line * 0.7)
			_seg(on, o, u, v, 0.30, 0.86, 0.50, 0.20, lit, line * 0.6)
			_seg(on, o, u, v, 0.62, 0.92, 0.80, 0.34, lit, line * 0.5)
		"tiles":
			# Overlapping courses: a line for each row and a lip hanging off it.
			for i in 3:
				var y := (i + 1) / 4.0
				_seg(on, o, u, v, 0.0, y, 1.0, y, cut, line)
			for i in 2:
				var x := (i + 1) / 3.0
				_seg(on, o, u, v, x, 0.25, x, 0.5, cut, line * 0.7)
			_seg(on, o, u, v, 0.5, 0.5, 0.5, 0.75, cut, line * 0.7)
			_seg(on, o, u, v, 0.16, 0.5, 0.16, 0.75, cut, line * 0.7)
		"cells":
			_quad(on, o, u, v, 0.12, 0.12, 0.88, 0.88, lit, line * 0.6)
			_seg(on, o, u, v, 0.5, 0.12, 0.5, 0.88, lit, line * 0.6)
			_seg(on, o, u, v, 0.12, 0.5, 0.88, 0.5, lit, line * 0.6)
		"specks":
			for i in 8:
				_dot(on, o, u, v, SCATTER[i].x, SCATTER[i].y, line * 0.42,
					cut if i % 2 == 0 else lit)
		"pebbles":
			for i in 6:
				_dot(on, o, u, v, SCATTER[i].x, SCATTER[i].y, line * 0.85, cut)
				_dot(on, o, u, v, SCATTER[i].x - 0.03, SCATTER[i].y - 0.03,
					line * 0.4, lit)
		"blades":
			# Grass only grows on the side you can see the sky from.
			if not is_top:
				_seg(on, o, u, v, 0.0, 0.12, 1.0, 0.12, cut, line * 0.8)
				return
			for i in 6:
				var x := i / 6.0 + 0.09
				_seg(on, o, u, v, x, 0.72, x + 0.05, 0.28, lit, line * 0.6)
		"gloss":
			_seg(on, o, u, v, 0.10, 0.66, 0.66, 0.10, lit, line * 2.2)
			_seg(on, o, u, v, 0.42, 0.88, 0.88, 0.42, lit, line * 1.1)
		"neon":
			_seg(on, o, u, v, 0.08, 0.5, 0.92, 0.5, lit, line * 2.4)
		"grains":
			for i in 7:
				_seg(on, o, u, v, SCATTER[i].x, SCATTER[i].y,
					SCATTER[i].x + 0.07, SCATTER[i].y - 0.09, cut, line * 0.55)
		_:
			# "plain": one soft highlight so the face is not a flat fill.
			if is_top:
				_seg(on, o, u, v, 0.22, 0.30, 0.62, 0.22, lit, line * 0.7)


static func _at(o: Vector2, u: Vector2, v: Vector2, a: float, b: float) -> Vector2:
	return o + u * a + v * b


static func _seg(on: CanvasItem, o: Vector2, u: Vector2, v: Vector2,
		a0: float, b0: float, a1: float, b1: float,
		colour: Color, width: float) -> void:
	on.draw_line(_at(o, u, v, a0, b0), _at(o, u, v, a1, b1), colour, width)


static func _dot(on: CanvasItem, o: Vector2, u: Vector2, v: Vector2,
		a: float, b: float, r: float, colour: Color) -> void:
	on.draw_circle(_at(o, u, v, a, b), maxf(r, 0.6), colour)


## An open rectangle in face space. Four segments rather than draw_rect, because
## a face is a parallelogram and an axis-aligned rectangle would sit on it at
## the wrong angle.
static func _quad(on: CanvasItem, o: Vector2, u: Vector2, v: Vector2,
		a0: float, b0: float, a1: float, b1: float,
		colour: Color, width: float) -> void:
	_seg(on, o, u, v, a0, b0, a1, b0, colour, width)
	_seg(on, o, u, v, a1, b0, a1, b1, colour, width)
	_seg(on, o, u, v, a1, b1, a0, b1, colour, width)
	_seg(on, o, u, v, a0, b1, a0, b0, colour, width)
