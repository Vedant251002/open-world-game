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
const C_WILD := Color("#2f3a2a")
const C_TOWN := Color("#3b3a2e")
const C_PLOT := Color("#4b4335")
const C_ROAD := Color("#cdbf9c")
const C_BUILDING := Color("#8d5c37")
const C_RING := Color("#efe4c8")
const C_SHADE := Color(0, 0, 0, 0.45)
const C_PLAYER := Color("#ffffff")
const C_NORTH := Color("#d4553f")

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
	radius = 118.0 if touch else 92.0
	_font = ThemeDB.fallback_font

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
	_disc.draw_circle(Vector2(radius, radius), radius, Color.WHITE)


func _scale() -> float:
	return radius / RANGE_M


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
	_ink.draw_circle(Vector2(radius, radius), radius, C_WILD)
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
			_ink.draw_colored_polygon(_rect_points(r), C_BUILDING)

	if crew != null:
		for w: Worker in crew.workers:
			if not is_instance_valid(w):
				continue
			var at := Vector2(w.global_position.x, w.global_position.z)
			if not _near(at, 0.0):
				continue
			var dot := _at(at)
			_ink.draw_circle(dot, 5.0, Color(0, 0, 0, 0.55))
			_ink.draw_circle(dot, 3.6, w.body.cloth_colour.lightened(0.35))

	# A vignette, so the edge of the disc is a horizon rather than a cut.
	_ink.draw_arc(Vector2(radius, radius), radius - 5.0, 0.0, TAU, 48,
		C_SHADE, 10.0, true)


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


## The furniture: the ring, the arrow that is always you, and the one mark that
## remembers where north went.
func _draw_frame() -> void:
	var c := Vector2(radius, radius)
	_frame.draw_arc(c, radius - 1.0, 0.0, TAU, 72, Color(0, 0, 0, 0.7), 5.0, true)
	_frame.draw_arc(c, radius - 1.0, 0.0, TAU, 72, C_RING, 2.0, true)

	# North, wherever it has got to. Without it a map that turns is a map you
	# cannot use to describe anything to anybody.
	var north := c + Vector2(0.0, -1.0).rotated(_rot) * (radius - 9.0)
	_frame.draw_circle(north, 4.5, C_NORTH)
	if _font != null:
		_frame.draw_string(_font, north + Vector2(-4.0, -8.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_RING)

	# You, always at the middle and always pointing up the screen.
	var arrow := PackedVector2Array([
		c + Vector2(0.0, -9.0), c + Vector2(6.5, 7.0),
		c + Vector2(0.0, 3.5), c + Vector2(-6.5, 7.0),
	])
	_frame.draw_colored_polygon(arrow, Color(0, 0, 0, 0.65))
	var inner := PackedVector2Array()
	for p: Vector2 in arrow:
		inner.append(c + (p - c) * 0.78)
	_frame.draw_colored_polygon(inner, C_PLAYER)
