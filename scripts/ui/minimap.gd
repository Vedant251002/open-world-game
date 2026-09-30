extends Control
class_name Minimap
## The little round map in the corner.
##
## Every game with a town in it has one of these and they all work the same
## way, which is the point: you should not have to learn it. North is not up —
## the map turns under you, so whatever is drawn at the top of the disc is
## whatever is in front of your face. The full map on [M] is the one that holds
## still, and that is the one for reading; this one is for walking.
##
## Drawn as vectors from the town layout rather than sampled from the world.
## The streets are five numbers and the plots are a rectangle each, so a frame
## of this costs less than reading one chunk would, and it stays sharp.

const V := VoxelChunk.VOXEL_M
## Metres from the middle of the disc to its edge. Two blocks and a bit, so
## the street you are on and the ones either side are all on it.
const RANGE_M := 58.0

# Muted, because the thing on top of it is the town and the thing under it is
# the game. A minimap that shouts is a minimap you turn off.
const C_WILD := Color("#3a4a35")
const C_TOWN := Color("#4b4a38")
const C_PLOT := Color("#5f5340")
const C_ROAD := Color("#d9cba4")
const C_BUILDING := Color("#b0703e")
const C_BUILDING_EDGE := Color("#2a1c12")
const C_RING := Color("#efe0b8")
const C_SHADE := Color(0, 0, 0, 0.38)
const C_PLAYER := Color("#fff4d6")
const C_NORTH := Color("#e2604a")
## Width of the compass band around the map, in pixels at scale 1.
const BAND := 17.0

var player: Player
var village: Village
var map: MapScreen                  ## where the built footprints are kept
var crew: Crew
## The two full-screen views. Not drawn on — only asked whether they are up, so
## the minimap can stop drawing itself underneath them.
var inventory: InventoryScreen

## How often the disc is redrawn. Twenty times a second, not once a frame.
##
## Redrawing rebuilds every polygon on it and, because the disc is a clipped
## canvas item, makes the renderer copy the backbuffer behind it again. At a
## hundred and forty frames a second that was a hundred and forty rebuilds for
## a picture that moves a few pixels — and it was pure waste on every frame
## where nobody was even looking at it. Twenty is smooth to the eye and a
## seventh of the work.
const REDRAW_HZ := 20.0

var radius := 96.0
## Radius of the map itself, inside the compass band.
var _mr := 80.0

var _disc: Control                  ## draws the mask
var _ink: Control                   ## draws the map, clipped to it
var _frame: Control                 ## ring, arrow and compass, over the top
var _font: Font
var _centre := Vector2.ZERO         ## world metres under the middle of the disc
var _rot := 0.0                     ## radians the world is turned by
var _due := 0.0                     ## seconds until the next redraw


func setup(p: Player, v: Village, m: MapScreen, c: Crew, touch: bool,
		inv: InventoryScreen = null) -> void:
	player = p
	village = v
	map = m
	crew = c
	inventory = inv
	radius = 128.0 if touch else 100.0
	_mr = radius - BAND * (1.35 if touch else 1.0)
	_font = UiTheme.font(800)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size

	_disc = Control.new()
	_disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The parent's own drawing becomes the stencil and is never itself shown,
	# which is the whole trick: a square canvas that comes out round.
	_disc.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_disc.draw.connect(_draw_mask)
	add_child(_disc)

	_ink = Control.new()
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_map)
	_disc.add_child(_ink)

	_frame = Control.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	add_child(_frame)

	set_process(true)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Nothing to draw while something is on top of it, and nothing to draw
	# while it is hidden — a hidden Control still gets _process, and this used
	# to keep rebuilding the whole disc behind the map screen.
	var covered := (map != null and map.open) \
		or (inventory != null and inventory.open)
	if covered or not visible:
		return
	_due -= delta
	if _due > 0.0:
		return
	_due = 1.0 / REDRAW_HZ
	_centre = Vector2(player.global_position.x, player.global_position.z)
	# Forward is -Z, as it is for every camera in the engine. Read off the
	# basis rather than off the yaw so this keeps working if the player is ever
	# put on a horse.
	var f := -player.global_transform.basis.z
	_rot = -atan2(f.x, -f.z)
	_ink.queue_redraw()
	_frame.queue_redraw()


# -------------------------------------------------------------------- drawing

func _draw_mask() -> void:
	_disc.draw_circle(Vector2(radius, radius), _mr, Color.WHITE)


func _scale() -> float:
	return _mr / RANGE_M


## World metres to a point on the disc, turned so the player's nose is up.
func _at(world_xz: Vector2) -> Vector2:
	var r := (world_xz - _centre) * _scale()
	return Vector2(radius, radius) + r.rotated(_rot)


func _rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		_at(r.position),
		_at(Vector2(r.end.x, r.position.y)),
		_at(r.end),
		_at(Vector2(r.position.x, r.end.y)),
	])


## Anything this far outside the disc cannot land on it, whatever the rotation.
func _near(world_xz: Vector2, slack: float) -> bool:
	return world_xz.distance_squared_to(_centre) < (RANGE_M + slack) * (RANGE_M + slack)


func _draw_map() -> void:
	_ink.draw_circle(Vector2(radius, radius), _mr, C_WILD)
	if village == null:
		return

	# The levelled shelf the town stands on, so the edge of town reads as an
	# edge rather than as the map running out.
	var b := village.bounds_v
	_ink.draw_colored_polygon(_rect_points(Rect2(
		b.position.x * V, b.position.y * V, b.size.x * V, b.size.y * V)), C_TOWN)

	for p: Plot in village.plots:
		var c := p.centre_m()
		if not _near(Vector2(c.x, c.z), 30.0):
			continue
		var pr := p.rect_v()
		_ink.draw_colored_polygon(_rect_points(Rect2(
			pr.position.x * V, pr.position.y * V,
			pr.size.x * V, pr.size.y * V)), C_PLOT)

	_draw_streets()

	if map != null:
		for rec: Dictionary in map.buildings:
			var r: Rect2 = rec["rect_m"]
			if not _near(r.get_center(), 24.0):
				continue
			var quad := _rect_points(r)
			_ink.draw_colored_polygon(quad, C_BUILDING)
			quad.append(quad[0])
			_ink.draw_polyline(quad, C_BUILDING_EDGE, 1.4, true)

	if crew != null:
		for w: Worker in crew.workers:
			if not is_instance_valid(w):
				continue
			var at := Vector2(w.global_position.x, w.global_position.z)
			if not _near(at, 0.0):
				continue
			var dot := _at(at)
			if w.hired:
				_ink.draw_circle(dot, 5.6, Color(0.05, 0.04, 0.03, 0.85))
				_ink.draw_circle(dot, 4.4, C_RING)
				_ink.draw_circle(dot, 3.0, w.body.cloth_colour.lightened(0.3))
			else:
				_ink.draw_circle(dot, 3.2, Color(0.05, 0.04, 0.03, 0.6))
				_ink.draw_circle(dot, 2.2, w.body.cloth_colour.lightened(0.35))

	# A vignette, so the edge of the disc is a horizon rather than a cut.
	_ink.draw_arc(Vector2(radius, radius), _mr - 6.0, 0.0, TAU, 64,
		C_SHADE, 12.0, true)


## The street grid. Five lines each way, drawn as the roads they are rather
## than as hairlines: the width is what makes a junction look like a junction.
func _draw_streets() -> void:
	var w := Village.ROAD_WIDTH * _scale()
	var lo_x := village.lines_x[0] * V
	var hi_x := village.lines_x[village.lines_x.size() - 1] * V
	var lo_z := village.lines_z[0] * V
	var hi_z := village.lines_z[village.lines_z.size() - 1] * V
	for lx: int in village.lines_x:
		var x := lx * V
		if absf(x - _centre.x) > RANGE_M + Village.ROAD_PITCH:
			continue
		_ink.draw_line(_at(Vector2(x, lo_z)), _at(Vector2(x, hi_z)), C_ROAD, w)
	for lz: int in village.lines_z:
		var z := lz * V
		if absf(z - _centre.y) > RANGE_M + Village.ROAD_PITCH:
			continue
		_ink.draw_line(_at(Vector2(lo_x, z)), _at(Vector2(hi_x, z)), C_ROAD, w)

	var pz := village.plaza_rect_v
	_ink.draw_colored_polygon(_rect_points(Rect2(
		pz.position.x * V, pz.position.y * V,
		pz.size.x * V, pz.size.y * V)), C_ROAD)


## The furniture: a glass compass band with degree ticks and N/E/S/W that turn
## with the map, a gold rim, off-map markers for your crew, and the arrow that
## is always you.
func _draw_frame() -> void:
	var c := Vector2(radius, radius)
	# Drop shadow, then the band: dark glass between the map and the rim.
	_frame.draw_circle(c + Vector2(0, 3), radius, Color(0, 0, 0, 0.30))
	var band_mid := (radius + _mr) * 0.5
	_frame.draw_arc(c, band_mid, 0.0, TAU, 96, Color(0.07, 0.058, 0.045, 0.88),
		radius - _mr + 1.0, true)
	# Gold rim outside, thin gold line at the map's edge.
	_frame.draw_arc(c, radius - 1.0, 0.0, TAU, 96, Color(UiTheme.GOLD, 0.85), 1.6, true)
	_frame.draw_arc(c, radius - 3.0, 0.0, TAU, 96, Color(0, 0, 0, 0.5), 1.0, true)
	_frame.draw_arc(c, _mr, 0.0, TAU, 96, Color(UiTheme.GOLD, 0.55), 1.4, true)

	# Ticks every 15 degrees, longer every 45. They rotate with the world.
	for i in 24:
		var a := TAU * i / 24.0 + _rot
		var d := Vector2.from_angle(a - PI * 0.5)
		var major := i % 3 == 0
		var t0 := radius - 4.0
		var t1 := radius - (9.0 if major else 6.5)
		if i % 6 != 0:
			_frame.draw_line(c + d * t0, c + d * t1, Color(UiTheme.PARCHMENT, 0.55 if major else 0.3), 1.1, true)

	# Cardinal letters, upright, at the compass points wherever they have got to.
	var lp := band_mid
	var letters := ["N", "E", "S", "W"]
	for i in 4:
		var d2 := Vector2.from_angle(TAU * i / 4.0 - PI * 0.5 + _rot)
		var at := c + d2 * lp
		var col := C_NORTH if i == 0 else C_RING
		var fs := 13 if i == 0 else 11
		var sz := _font.get_string_size(letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_frame.draw_string(_font, at + Vector2(-sz.x * 0.5, fs * 0.36), letters[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# Crew who have wandered off the disc: a small marker on the rim, pointing
	# the way. So you can always find your people.
	if crew != null:
		for w: Worker in crew.workers:
			if not is_instance_valid(w) or not w.hired:
				continue
			var off := (Vector2(w.global_position.x, w.global_position.z) - _centre) * _scale()
			if off.length() < _mr - 6.0:
				continue
			var dirv := off.rotated(_rot).normalized()
			var mp := c + dirv * (_mr - 5.0)
			var perp := Vector2(-dirv.y, dirv.x)
			_frame.draw_colored_polygon(PackedVector2Array([
				mp + dirv * 5.0, mp - dirv * 3.0 + perp * 4.5, mp - dirv * 3.0 - perp * 4.5]),
				w.body.cloth_colour.lightened(0.3))

	# You: a gold arrow with a soft view wedge, always pointing up the screen.
	_frame.draw_colored_polygon(PackedVector2Array([
		c, c + Vector2(-_mr * 0.30, -_mr * 0.48), c + Vector2(_mr * 0.30, -_mr * 0.48)]),
		Color(1, 0.95, 0.8, 0.09))
	var arrow := PackedVector2Array([
		c + Vector2(0.0, -10.0), c + Vector2(7.0, 8.0),
		c + Vector2(0.0, 4.0), c + Vector2(-7.0, 8.0),
	])
	var ring := PackedVector2Array(arrow)
	ring.append(arrow[0])
	_frame.draw_colored_polygon(arrow, Color(0, 0, 0, 0.7))
	_frame.draw_polyline(ring, Color(0, 0, 0, 0.7), 3.0, true)
	var inner := PackedVector2Array()
	for pt: Vector2 in arrow:
		inner.append(c + (pt - c) * 0.8)
	_frame.draw_colored_polygon(inner, C_PLAYER)
