extends CanvasLayer
class_name InventoryScreen
## The stores, laid out as a grid of slots.
##
## The shape is borrowed from Minecraft on purpose: squares in rows, an icon of
## the thing itself, a count in the corner. It is the most legible inventory
## anyone has built and every player already knows how to read it.
##
## What it is *not* is a place to do anything. Design pillar P1 says language is
## the only verb, so there is nothing here to drag, equip or craft — you cannot
## pick a slot up. It answers one question, which is the question the player
## actually has before they open their mouth: what have we got, and if we have
## none of it, where would somebody go to get some. So every material in the
## palette has a slot whether the stores hold any or not, and an empty slot is
## as informative as a full one.
##
## Icons are drawn rather than imported. Every material is already a colour in
## VoxelTypes.PROPS and every building in the game is made of cubes, so three
## shaded faces gets an icon that is honestly the material, needs no artist, and
## can never fall out of step with what the walls actually look like.

const V := VoxelChunk.VOXEL_M

# --- palette, in the same brown-paper key as the rest of the interface ---
const C_SHADE := Color(0.03, 0.03, 0.04, 0.72)     ## the world, dimmed behind
const C_PANEL := Color(0.11, 0.10, 0.09, 0.97)
const C_EDGE := Color(1, 1, 1, 0.16)
const C_SLOT := Color(0.06, 0.055, 0.05, 0.9)
const C_SLOT_LIT := Color(0.17, 0.15, 0.12, 0.95)
const C_BEVEL_HI := Color(1, 1, 1, 0.10)
const C_BEVEL_LO := Color(0, 0, 0, 0.45)
const C_INK := Color(0.94, 0.92, 0.87)
const C_DIM := Color(0.66, 0.64, 0.60)
const C_FAINT := Color(0.42, 0.41, 0.38)
const C_COIN := Color(0.98, 0.83, 0.42)
const C_LOCK := Color(0.85, 0.62, 0.36)

## The sections, in the order a builder would think of them. Taken from the
## VoxelTypes categories rather than restated, so a material added to the
## palette turns up here on its own instead of quietly going missing.
const SECTIONS := [
	{"title": "WALLS AND FRAME", "of": "structural"},
	{"title": "ROOFING", "of": "surface"},
	{"title": "GROUND AND FOUNDATION", "of": "ground"},
	{"title": "TRIM AND FINISH", "of": "trim"},
	{"title": "THE LARDER", "of": "larder"},
]
## The two things the town makes rather than digs. They are not voxels, so they
## have no entry in the palette and need a colour of their own.
const LARDER := {
	"food": Color("#c8a24a"),
	"cloth": Color("#cbd2dc"),
}

var town: Town
var player: Player
var map: MapScreen                  ## so the two full-screen views cannot stack

var open := false

var _root: Control
var _sheet: Control                 ## the grid, drawn in one pass
var _font: Font
var _touch := false
var _slot := 74.0
var _slots: Array[Dictionary] = []  ## {rect, mat, larder} in draw order
var _hover := -1
var _picked := -1                   ## what the detail column is describing


func setup(t: Town, p: Player, m: MapScreen) -> void:
	town = t
	player = p
	map = m
	layer = 21                      ## over the map, which is 20
	_font = ThemeDB.fallback_font
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	_slot = 82.0 if _touch else 74.0
	_build()
	visible = false
	set_process(true)
	set_process_unhandled_input(true)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = C_SHADE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	_sheet = Control.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.draw.connect(_draw_sheet)
	_root.add_child(_sheet)

	get_viewport().size_changed.connect(func() -> void: _sheet.queue_redraw())


# ------------------------------------------------------------------- opening

func toggle() -> void:
	set_open(not open)


func set_open(v: bool) -> void:
	open = v
	visible = v
	if v and map != null and map.open:
		map.set_open(false)
	if player != null:
		player.set_input_enabled(not v)
	if v:
		_hover = -1
		_sheet.queue_redraw()


func _process(_delta: float) -> void:
	if not open:
		return
	# Redrawn every frame while it is up. The stores move while you are looking
	# at them — a worker finishing a wall spends from this same dictionary —
	# and an inventory that lies for a second is worse than one that flickers.
	var at := _sheet.get_local_mouse_position()
	var was := _hover
	_hover = _slot_at(at)
	if _hover != was and _hover >= 0:
		_picked = _hover
	_sheet.queue_redraw()


func _slot_at(at: Vector2) -> int:
	for i in _slots.size():
		if (_slots[i]["rect"] as Rect2).has_point(at):
			return i
	return -1


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not open:
		if event.is_action_pressed("inventory") and (map == null or not map.open):
			set_open(true)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("inventory") or event.is_action_pressed("menu") \
			or event.is_action_pressed("map"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# Tapping a slot is how you read one on a phone, where there is no
		# pointer to hover with.
		var hit := _slot_at(_sheet.get_local_mouse_position())
		if hit >= 0:
			_picked = hit
			_sheet.queue_redraw()
	# Modal. Nothing behind this reaches the world while it is up, or you walk
	# off a rooftop reading a list of bricks.
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- drawing

func _draw_sheet() -> void:
	if town == null:
		return
	_slots.clear()
	var view := _sheet.size
	var gap := 6.0
	var cols := 8
	var grid_w := cols * _slot + (cols - 1) * gap
	var side_w := 380.0 if not _touch else 420.0
	var pad := 26.0
	var panel_w := grid_w + side_w + pad * 3.0

	# Measured before it is drawn, so the panel is exactly as tall as its
	# contents rather than a guess that leaves a gap under the last row.
	var head_h := 92.0
	var body_h := head_h + 16.0
	for sec: Dictionary in SECTIONS:
		var n := _names_in(str(sec["of"])).size()
		var rows := maxi(int(ceil(float(n) / float(cols))), 1)
		body_h += 30.0 + rows * (_slot + gap)
	body_h += 42.0                  ## the closing line

	var origin := Vector2(
		(view.x - panel_w) * 0.5,
		maxf((view.y - body_h) * 0.5, 12.0))
	var panel := Rect2(origin, Vector2(panel_w, minf(body_h, view.y - 24.0)))
	_sheet.draw_rect(panel, C_PANEL)
	_sheet.draw_rect(panel, C_EDGE, false, 2.0)

	_draw_header(Rect2(origin + Vector2(pad, pad), Vector2(panel_w - pad * 2, head_h)))

	var y := origin.y + pad + head_h
	var x0 := origin.x + pad
	for sec: Dictionary in SECTIONS:
		var names := _names_in(str(sec["of"]))
		_text(Vector2(x0, y + 20.0), str(sec["title"]), 15, C_FAINT)
		y += 30.0
		for i in names.size():
			var cell := Rect2(
				Vector2(x0 + (i % cols) * (_slot + gap),
					y + (i / cols) * (_slot + gap)),
				Vector2(_slot, _slot))
			_slots.append({"rect": cell, "mat": names[i],
				"larder": str(sec["of"]) == "larder"})
		var rows := maxi(int(ceil(float(names.size()) / float(cols))), 1)
		y += rows * (_slot + gap)

	for i in _slots.size():
		_draw_slot(i)

	_draw_detail(Rect2(
		Vector2(x0 + grid_w + pad, origin.y + pad + head_h),
		Vector2(side_w, panel.end.y - (origin.y + pad + head_h) - pad)))

	_text(Vector2(x0, panel.end.y - 16.0),
		"[I] or [Esc] to close      a unit is about a metre and a half of wall",
		15, C_FAINT)


func _names_in(group: String) -> PackedStringArray:
	if group == "larder":
		var l := PackedStringArray()
		for k: String in LARDER:
			l.append(k)
		return l
	var src: Array = VoxelTypes.STRUCTURAL
	match group:
		"surface": src = VoxelTypes.SURFACE
		"ground": src = VoxelTypes.GROUND
		"trim": src = VoxelTypes.TRIM
	# Cheapest first, which is roughly oldest first, so the row reads as the
	# town's own history: timber and plank on the left, carbon composite off
	# the right-hand end where it belongs.
	var out: Array = src.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia := VoxelTypes.id_of(a)
		var ib := VoxelTypes.id_of(b)
		if VoxelTypes.tech_tier(ia) != VoxelTypes.tech_tier(ib):
			return VoxelTypes.tech_tier(ia) < VoxelTypes.tech_tier(ib)
		return VoxelTypes.cost(ia) < VoxelTypes.cost(ib))
	var names := PackedStringArray()
	for n: String in out:
		names.append(n)
	return names


func _draw_header(r: Rect2) -> void:
	_text(r.position + Vector2(0, 30), "THE STORES", 30, C_INK)

	var purse := "%s coins" % town.coin_line()
	var w := _font.get_string_size(purse, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_text(Vector2(r.end.x - w, r.position.y + 30), purse, 30, C_COIN)
	var worth := "the yard is worth about %s      tier %d" % [
		Town.grouped(town.stock_worth()), town.tier]
	var w2 := _font.get_string_size(worth, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(Vector2(r.end.x - w2, r.position.y + 58), worth, 16, C_DIM)

	# Kept clear of the figures on the right, which is why this is short: the
	# two used to be written on the same baseline and ran through each other.
	_text(r.position + Vector2(0, 58), "Nothing here is yours to move.", 16, C_DIM)

	_sheet.draw_line(Vector2(r.position.x, r.end.y - 8),
		Vector2(r.end.x, r.end.y - 8), C_EDGE, 1.0)


func _draw_slot(i: int) -> void:
	var s: Dictionary = _slots[i]
	var r: Rect2 = s["rect"]
	var mat := str(s["mat"])
	var n := town.units_of(mat)
	var known := town.knows(mat)
	var lit := i == _hover or i == _picked

	_sheet.draw_rect(r, C_SLOT_LIT if lit else C_SLOT)
	# Two lines instead of a border: a slot with a lit top-left edge and a dark
	# bottom-right one reads as a recess, which is what makes a grid of these
	# look like somewhere things are kept rather than like a spreadsheet.
	_sheet.draw_line(r.position, Vector2(r.end.x, r.position.y), C_BEVEL_LO, 2.0)
	_sheet.draw_line(r.position, Vector2(r.position.x, r.end.y), C_BEVEL_LO, 2.0)
	_sheet.draw_line(Vector2(r.position.x, r.end.y), r.end, C_BEVEL_HI, 1.0)
	_sheet.draw_line(Vector2(r.end.x, r.position.y), r.end, C_BEVEL_HI, 1.0)
	if lit:
		_sheet.draw_rect(r, C_EDGE, false, 1.0)

	var fade := 1.0
	if not known:
		fade = 0.16
	elif n <= 0:
		fade = 0.34
	# Just over half the slot. At 0.44 the surface patterns were technically
	# there and practically invisible, which defeats the point of having them.
	_draw_cube(r.get_center() + Vector2(0, -4.0), _slot * 0.54, mat,
		_colour_of(mat), fade)

	if not known:
		var tier_id := VoxelTypes.id_of(mat)
		_text(r.position + Vector2(6, 20), "T%d" % VoxelTypes.tech_tier(tier_id),
			15, C_LOCK)
	# The count goes on either way. The yard opens with brick and glass in it
	# that a tier one town cannot lay a course of, and a slot that showed the
	# lock but hid the number made two hundred bricks look like none.
	var label := str(n)
	var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text(Vector2(r.end.x - lw - 6, r.end.y - 7), label, 18,
		C_INK if n > 0 else C_FAINT)


## One voxel, drawn by BlockIcon: three shaded faces with the material's own
## surface painted into each of them.
##
## The pattern is what tells two greys apart. Colour alone had thirty materials
## looking like thirty copies of one item, which is the thing Minecraft's block
## textures are really doing and the reason its inventory is readable at a
## glance.
func _draw_cube(at: Vector2, w: float, mat: String, base: Color,
		fade: float) -> void:
	BlockIcon.draw(_sheet, at, w, mat, base, fade)


## Glass is a colour with alpha in it and would come out as a ghost, so the
## icon uses the colour at full strength and lets the shape carry it.
func _colour_of(mat: String) -> Color:
	if LARDER.has(mat):
		return LARDER[mat]
	var id := VoxelTypes.id_of(mat)
	if id < 0:
		return Color("#8a8078")
	var c := VoxelTypes.albedo(id)
	c.a = 1.0
	return c


# -------------------------------------------------------------- the right-hand column

## What the highlighted slot actually is, in the terms the player will have to
## use out loud. Not a stat block: the useful facts are how much there is, what
## it is for, and — when there is none — who would have to go where.
func _draw_detail(r: Rect2) -> void:
	_sheet.draw_rect(r, Color(0, 0, 0, 0.22))
	_sheet.draw_rect(r, C_EDGE, false, 1.0)
	var x := r.position.x + 16.0
	var y := r.position.y + 34.0
	var wrap := r.size.x - 32.0

	if _picked < 0 or _picked >= _slots.size():
		_text(Vector2(x, y), "Point at something.", 19, C_DIM)
		y = _wrapped(Vector2(x, y + 30.0), wrap,
			"Every material the town could build with has a slot here, "
			+ "whether the stores hold any of it or not — an empty one tells "
			+ "you what to send somebody out for.", 16, C_FAINT)
		return

	var mat := str(_slots[_picked]["mat"])
	var larder: bool = bool(_slots[_picked]["larder"])
	var n := town.units_of(mat)

	_draw_cube(Vector2(r.end.x - 52.0, r.position.y + 52.0), 58.0, mat,
		_colour_of(mat), 1.0 if town.knows(mat) else 0.3)
	_text(Vector2(x, y), mat.replace("_", " ").capitalize(), 24, C_INK)
	y += 34.0

	if not town.knows(mat):
		var id := VoxelTypes.id_of(mat)
		_text(Vector2(x, y), "Nobody here can work it yet.", 17, C_LOCK)
		y = _wrapped(Vector2(x, y + 26.0), wrap,
			"It wants a tier %d town and this one is tier %d. Ask for it now "
			% [VoxelTypes.tech_tier(id), town.tier]
			+ "and whoever you ask will tell you the same thing to your face.",
			16, C_DIM)
		if n > 0:
			_wrapped(Vector2(x, y + 12.0), wrap,
				"There are %d units of it in the yard all the same — it will "
				% n + "keep until the town has grown into it.", 16, C_FAINT)
		return

	_text(Vector2(x, y), "%d units in the stores" % n, 19,
		C_INK if n > 0 else C_FAINT)
	y += 26.0
	_text(Vector2(x, y), "worth about %d coins" % (n * _price_of(mat)), 16, C_DIM)
	y += 34.0

	if larder:
		y = _wrapped(Vector2(x, y), wrap, _larder_note(mat), 16, C_DIM)
		return

	y = _wrapped(Vector2(x, y), wrap, _use_note(mat), 16, C_DIM)
	y += 12.0

	var src := Resources.source_of(mat)
	if src < 0:
		_wrapped(Vector2(x, y), wrap,
			"There is nowhere to dig this. What the town has is all it will "
			+ "ever have.", 16, C_FAINT)
		return
	_wrapped(Vector2(x, y), wrap,
		"Comes out of %s. Say \"fetch some %s\" to anyone with their hands "
		% [Resources.place_of(src), mat.replace("_", " ")]
		+ "free and they will go — a voxel of it is worth %d units."
		% Resources.yield_of(src), 16, C_DIM)


func _price_of(mat: String) -> int:
	return int(Town.PRICE.get(mat, Town.DEFAULT_PRICE))


func _use_note(mat: String) -> String:
	if mat in VoxelTypes.STRUCTURAL:
		return "A walling material. Ask for a building in it and the walls, "\
			+ "and whatever holds them up, come out of this pile."
	if mat in VoxelTypes.SURFACE:
		return "Roofing. It is what goes over the rafters, and it is most of "\
			+ "what a building looks like from across the street."
	if mat in VoxelTypes.GROUND:
		return "Footings and paving — the plinth a building stands on, and "\
			+ "the ground around it."
	return "Trim: door frames, sills, lintels and the mouldings that stop a "\
		+ "wall reading as a box."


func _larder_note(mat: String) -> String:
	if mat == "food":
		return "What the fields and the animals put in. It is the one thing "\
			+ "here the town earns rather than digs, and it sells the moment "\
			+ "it is picked — which is why the purse moves at harvest."
	return "Wool off the sheep, spun and folded. Earned, like food, and sold "\
		+ "the same way."


# ----------------------------------------------------------------- text helpers

func _text(at: Vector2, s: String, size: int, colour: Color) -> void:
	_sheet.draw_string(_font, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, Color(0, 0, 0, 0.7))
	_sheet.draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


## Word wrap by hand, because draw_string has no idea how wide the column is.
## Returns the y the next thing should start at.
func _wrapped(at: Vector2, width: float, s: String, size: int, colour: Color) -> float:
	var line := ""
	var y := at.y
	var step := size + 6.0
	for word: String in s.split(" ", false):
		var attempt := word if line == "" else line + " " + word
		if _font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			_text(Vector2(at.x, y), line, size, colour)
			y += step
			line = word
		else:
			line = attempt
	if line != "":
		_text(Vector2(at.x, y), line, size, colour)
		y += step
	return y
