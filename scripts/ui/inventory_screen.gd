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
const C_SHADE := Color(0.03, 0.02, 0.02, 0.68)     ## the world, dimmed behind
const C_PANEL := UiTheme.PANEL_SOLID
const C_EDGE := UiTheme.EDGE_STRONG
const C_SLOT := Color(0.045, 0.038, 0.030, 0.85)
const C_SLOT_LIT := Color(0.20, 0.16, 0.10, 0.95)
const C_BEVEL_HI := Color(1, 0.95, 0.8, 0.08)
const C_BEVEL_LO := Color(0, 0, 0, 0.45)
const C_INK := UiTheme.INK
const C_DIM := UiTheme.DIM
const C_FAINT := UiTheme.FAINT
const C_COIN := UiTheme.ACCENT
const C_LOCK := Color(0.85, 0.62, 0.36)
## Tier rims, in the order games teach players to read: plain, green, blue,
## violet. Tier one is deliberately the quietest.
const TIER_COL := [
	Color(0.78, 0.72, 0.60), Color(0.50, 0.80, 0.52),
	Color(0.48, 0.68, 0.96), Color(0.78, 0.58, 0.96),
]
## What a locked tier is washed with: cold and pale, never black.
const LOCK_TINT := Color(0.62, 0.68, 0.84)
const HEAD_H := 78.0
const SEC_H := 28.0
const FOOT_H := 34.0

## The sections, in the order a builder would think of them. Taken from the
## VoxelTypes categories rather than restated, so a material added to the
## palette turns up here on its own instead of quietly going missing.
const SECTIONS := [
	{"title": "WALLS AND FRAME", "of": "structural"},
	{"title": "ROOFING", "of": "surface"},
	{"title": "GROUND AND FOUNDATION", "of": "ground"},
	{"title": "TRIM AND FINISH", "of": "trim"},
	{"title": "THE LARDER", "of": "larder"},
	{"title": "THE ARMOURY", "of": "arms"},
]
## Colours for the things the armoury makes. They are not voxels either.
const ARMS := {
	"pistol": Color("#3a3d42"), "musket": Color("#6d4a2c"), "rifle": Color("#4a3b2c"),
	"grenade": Color("#2b2f2b"), "mortar": Color("#4a4f55"), "launcher": Color("#5a5f66"),
	"shot": Color("#8a8a80"), "shell": Color("#565b62"), "rocket": Color("#7a4a3a"),
	"powder": Color("#1e1c1a"),
}
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
var _slot_base := 74.0
var _slots: Array[Dictionary] = []  ## {rect, mat, larder} in draw order
var _hover := -1
var _picked := -1                   ## what the detail column is describing


func setup(t: Town, p: Player, m: MapScreen) -> void:
	town = t
	player = p
	map = m
	layer = 21                      ## over the map, which is 20
	_font = UiTheme.font(600)
	_touch = Platform.has_touch() or "--touchui" in OS.get_cmdline_user_args()
	_slot_base = 82.0 if _touch else 74.0
	_slot = _slot_base
	_build()
	visible = false
	set_process(true)
	set_process_unhandled_input(true)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
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
		_picked = -1                ## re-chosen on the first draw: the fullest slot
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
	# Ten across when the screen is wide enough: it saves a row, and a row is
	# what lets every slot be big enough to read.
	var cols := 10 if view.x >= 1260.0 else 8
	var rows_total := 0
	for sec0: Dictionary in SECTIONS:
		rows_total += maxi(int(ceil(float(_names_in(str(sec0["of"])).size()) / float(cols))), 1)
	var fixed_h := HEAD_H + 16.0 + FOOT_H + SEC_H * SECTIONS.size() + 44.0
	_slot = clampf((view.y - 24.0 - fixed_h) / float(rows_total) - gap, 46.0, _slot_base + 8.0)
	var grid_w := cols * _slot + (cols - 1) * gap
	var side_w := 380.0 if not _touch else 420.0
	var pad := 26.0
	var panel_w := grid_w + side_w + pad * 3.0

	# Measured before it is drawn, so the panel is exactly as tall as its
	# contents rather than a guess that leaves a gap under the last row.
	var head_h := HEAD_H
	var body_h := head_h + 16.0 + 18.0
	for sec: Dictionary in SECTIONS:
		var n := _names_in(str(sec["of"])).size()
		var rows := maxi(int(ceil(float(n) / float(cols))), 1)
		body_h += SEC_H + rows * (_slot + gap)
	body_h += FOOT_H                ## the closing line

	var origin := Vector2(
		(view.x - panel_w) * 0.5,
		maxf((view.y - body_h) * 0.5, 12.0))
	var panel := Rect2(origin, Vector2(panel_w, minf(body_h, view.y - 24.0)))
	var psb := UiTheme.panel_menu()
	psb.set_content_margin_all(0)
	_sheet.draw_style_box(psb, panel)

	_draw_header(Rect2(origin + Vector2(pad, pad), Vector2(panel_w - pad * 2, head_h)))

	var y := origin.y + pad + head_h
	var x0 := origin.x + pad
	for sec: Dictionary in SECTIONS:
		var names := _names_in(str(sec["of"]))
		var tw := UiTheme.display(700).get_string_size(str(sec["title"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text(Vector2(x0, y + 19.0), str(sec["title"]).to_upper(), 14, UiTheme.GOLD, UiTheme.display(700))
		_sheet.draw_line(Vector2(x0 + tw + 14.0, y + 14.0), Vector2(x0 + grid_w, y + 14.0),
			Color(UiTheme.GOLD, 0.22), 1.0)
		y += SEC_H
		for i in names.size():
			var cell := Rect2(
				Vector2(x0 + (i % cols) * (_slot + gap),
					y + (i / cols) * (_slot + gap)),
				Vector2(_slot, _slot))
			_slots.append({"rect": cell, "mat": names[i], "sec": str(sec["title"]),
				"larder": str(sec["of"]) == "larder" or str(sec["of"]) == "arms"})
		var rows := maxi(int(ceil(float(names.size()) / float(cols))), 1)
		y += rows * (_slot + gap)

	if _picked < 0 or _picked >= _slots.size():
		_picked = 0
		for i in _slots.size():
			if town.knows(str(_slots[i]["mat"])) and town.units_of(str(_slots[i]["mat"])) > 0:
				_picked = i
				break
	for i in _slots.size():
		if i != _hover and i != _picked:
			_draw_slot(i)
	# The lit ones last, so their glow is not clipped by the neighbours.
	if _picked >= 0 and _picked != _hover:
		_draw_slot(_picked)
	if _hover >= 0:
		_draw_slot(_hover)

	_draw_detail(Rect2(
		Vector2(x0 + grid_w + pad, origin.y + pad + head_h),
		Vector2(side_w, panel.end.y - (origin.y + pad + head_h) - pad)))

	_text(Vector2(x0, panel.end.y - 16.0),
		"I or Esc to close      a unit is about a metre and a half of wall",
		15, C_FAINT)


func _names_in(group: String) -> PackedStringArray:
	if group == "larder":
		var l := PackedStringArray()
		for k: String in LARDER:
			l.append(k)
		return l
	if group == "arms":
		return Arsenal.all_keys()
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
	_text(r.position + Vector2(0, 30), "THE STORES", 30, UiTheme.ACCENT, UiTheme.display(700))

	var purse := "%s coins" % town.coin_line()
	var w := _font.get_string_size(purse, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_text(Vector2(r.end.x - w, r.position.y + 30), purse, 30, C_COIN, UiTheme.font(800))
	var worth := "the yard is worth about %s      tier %d" % [
		Town.grouped(town.stock_worth()), town.tier]
	var w2 := _font.get_string_size(worth, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(Vector2(r.end.x - w2, r.position.y + 58), worth, 16, C_DIM)

	# Kept clear of the figures on the right, which is why this is short: the
	# two used to be written on the same baseline and ran through each other.
	_text(r.position + Vector2(0, 58), "Nothing here is yours to move.", 16, C_DIM)

	_sheet.draw_line(Vector2(r.position.x, r.end.y - 8),
		Vector2(r.end.x, r.end.y - 8), C_EDGE, 1.0)


func _tier_of(mat: String) -> int:
	var id := VoxelTypes.id_of(mat)
	return VoxelTypes.tech_tier(id) if id >= 0 else 1


func _draw_slot(i: int) -> void:
	var s: Dictionary = _slots[i]
	var r: Rect2 = s["rect"]
	var mat := str(s["mat"])
	var n := town.units_of(mat)
	var known := town.knows(mat)
	var hovered := i == _hover
	var picked := i == _picked
	var tier := clampi(_tier_of(mat), 1, 4)
	var rim: Color = TIER_COL[tier - 1]

	# A rounded recess. Stocked slots are lit from above like a shop shelf;
	# empty ones sit back; locked ones go cold so they cannot be mistaken for
	# either. Gold rim and a soft halo for the one being read.
	var ssb := StyleBoxFlat.new()
	if not known:
		ssb.bg_color = Color(0.07, 0.075, 0.095, 0.9)
	elif n > 0:
		ssb.bg_color = Color(0.17, 0.14, 0.105, 0.97)
	else:
		ssb.bg_color = Color(0.095, 0.08, 0.065, 0.9)
	if hovered or picked:
		ssb.bg_color = ssb.bg_color.lightened(0.18)
		ssb.border_color = Color(UiTheme.ACCENT, 0.95 if hovered else 0.75)
		ssb.set_border_width_all(2)
		ssb.shadow_color = Color(UiTheme.GOLD, 0.30)
		ssb.shadow_size = 9
	else:
		ssb.border_color = Color(rim, 0.55 if (known and n > 0) else 0.22)
		ssb.set_border_width_all(1)
	ssb.set_corner_radius_all(9)
	ssb.anti_aliasing = true
	_sheet.draw_style_box(ssb, r)
	# The spotlight under the block.
	if known and n > 0:
		_sheet.draw_circle(r.get_center() + Vector2(0, -2), _slot * 0.42,
			Color(1.0, 0.92, 0.75, 0.07))
		_sheet.draw_circle(r.get_center() + Vector2(0, -2), _slot * 0.30,
			Color(1.0, 0.92, 0.75, 0.06))

	var fade := 1.0
	var tint := Color.WHITE
	if not known:
		fade = 0.72
		tint = LOCK_TINT
	elif n <= 0:
		fade = 0.55
		tint = Color(0.62, 0.60, 0.58)
	# Big: the cube fills the slot, because the whole point of an icon is to be
	# recognised at a glance. Lifted a little to leave room for the count.
	var lift := _slot * (0.05 if hovered else 0.0)
	_draw_cube(r.get_center() + Vector2(0, -_slot * 0.07 - lift), _slot * 0.72, mat,
		_colour_of(mat), fade, tint)

	if not known:
		_draw_lock(r.position + Vector2(r.size.x - 13.0, 13.0), 1.0, C_LOCK)
		_badge(r.position + Vector2(5, 5), "T%d" % tier, 13, rim)
	elif tier > 1:
		_badge(r.position + Vector2(5, 5), "T%d" % tier, 12, rim, 0.8)

	# The count goes on either way. The yard opens with brick and glass in it
	# that a tier one town cannot lay a course of, and a slot that showed the
	# lock but hid the number made two hundred bricks look like none.
	var label := _short(n)
	var fs := 15 if _slot >= 60.0 else 13
	var f := UiTheme.font(800)
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pill := Rect2(Vector2(r.end.x - lw - 14.0, r.end.y - fs - 9.0), Vector2(lw + 10.0, fs + 5.0))
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.02, 0.015, 0.01, 0.78)
	psb.set_corner_radius_all(6)
	psb.anti_aliasing = true
	_sheet.draw_style_box(psb, pill)
	_text(Vector2(pill.position.x + 5.0, pill.end.y - 4.0), label, fs,
		C_INK if n > 0 else C_FAINT, f)


## 1450 stays 1450 but 12,400 becomes 12.4k, so a pill never outgrows its slot.
func _short(n: int) -> String:
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


## A small rounded tag, used for tier numbers.
func _badge(at: Vector2, s: String, size: int, col: Color, alpha: float = 1.0) -> void:
	var f := UiTheme.font(800)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := Rect2(at, Vector2(w + 9.0, size + 5.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.30, col.g * 0.30, col.b * 0.30, 0.92 * alpha)
	sb.border_color = Color(col, 0.85 * alpha)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.anti_aliasing = true
	_sheet.draw_style_box(sb, r)
	_sheet.draw_string(f, at + Vector2(4.5, size + 0.5), s, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, Color(col.lightened(0.35), alpha))


## A padlock from three primitives: shackle, body, keyhole.
func _draw_lock(c: Vector2, k: float, col: Color) -> void:
	_sheet.draw_arc(c + Vector2(0, -2.5) * k, 4.0 * k, PI, TAU, 12, col, 2.0 * k, true)
	var body := Rect2(c + Vector2(-5.5, -2.0) * k, Vector2(11.0, 8.5) * k)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(2)
	sb.anti_aliasing = true
	_sheet.draw_style_box(sb, body)
	_sheet.draw_circle(c + Vector2(0, 2.0) * k, 1.4 * k, Color(0.12, 0.09, 0.06))


## One voxel, drawn by BlockIcon: three shaded faces with the material's own
## surface painted into each of them.
##
## The pattern is what tells two greys apart. Colour alone had thirty materials
## looking like thirty copies of one item, which is the thing Minecraft's block
## textures are really doing and the reason its inventory is readable at a
## glance.
func _draw_cube(at: Vector2, w: float, mat: String, base: Color,
		fade: float, tint: Color = Color.WHITE) -> void:
	BlockIcon.draw(_sheet, at, w, mat, base, fade, tint)


## Glass is a colour with alpha in it and would come out as a ghost, so the
## icon uses the colour at full strength and lets the shape carry it.
func _colour_of(mat: String) -> Color:
	if LARDER.has(mat):
		return LARDER[mat]
	if ARMS.has(mat):
		# Gunmetal on a dark slot is a black square; lift it into the light.
		return (ARMS[mat] as Color).lerp(Color(0.8, 0.78, 0.74), 0.35)
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
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.03, 0.025, 0.02, 0.55)
	dsb.border_color = Color(UiTheme.GOLD, 0.28)
	dsb.set_border_width_all(1)
	dsb.set_corner_radius_all(12)
	dsb.anti_aliasing = true
	_sheet.draw_style_box(dsb, r)
	var x := r.position.x + 18.0
	var wrap := r.size.x - 36.0

	if _picked < 0 or _picked >= _slots.size():
		return

	var mat := str(_slots[_picked]["mat"])
	var larder: bool = bool(_slots[_picked]["larder"])
	var n := town.units_of(mat)
	var known := town.knows(mat)
	var tier := clampi(_tier_of(mat), 1, 4)
	var rim: Color = TIER_COL[tier - 1]
	var price := _price_of(mat)

	# The pedestal: a lit plinth with the block on it, big enough to read the
	# grain of the material.
	var ped := Rect2(r.position + Vector2(16, 16), Vector2(124, 124))
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.15, 0.12, 0.09, 0.95) if known else Color(0.07, 0.075, 0.095, 0.95)
	psb.border_color = Color(rim, 0.7)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(14)
	psb.shadow_color = Color(rim, 0.18)
	psb.shadow_size = 10
	psb.anti_aliasing = true
	_sheet.draw_style_box(psb, ped)
	_sheet.draw_circle(ped.get_center() + Vector2(0, -4), 56.0, Color(1.0, 0.92, 0.75, 0.07))
	_sheet.draw_circle(ped.get_center() + Vector2(0, -4), 40.0, Color(1.0, 0.92, 0.75, 0.07))
	_draw_cube(ped.get_center() + Vector2(0, -4), 92.0, mat, _colour_of(mat),
		1.0 if known else 0.7, Color.WHITE if known else LOCK_TINT)
	if not known:
		_draw_lock(ped.position + Vector2(112, 14), 1.2, C_LOCK)

	var tx := ped.end.x + 18.0
	var title := mat.replace("_", " ").capitalize()
	var tsize := 28
	var tf := UiTheme.display(700)
	while tsize > 18 and tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x > r.end.x - tx - 12.0:
		tsize -= 2
	_text(Vector2(tx, r.position.y + 50.0), title, tsize, C_INK, tf)
	_text(Vector2(tx, r.position.y + 74.0), str(_slots[_picked]["sec"]), 13, UiTheme.GOLD,
		UiTheme.display(700))
	if not larder:
		_badge(Vector2(tx, r.position.y + 90.0), "TIER %d" % tier, 13, rim)
	_badge(Vector2(tx + (78.0 if not larder else 0.0), r.position.y + 90.0),
		"IN STOCK" if (known and n > 0) else ("EMPTY" if known else "LOCKED"), 13,
		Color(0.55, 0.85, 0.55) if (known and n > 0) else (
			C_FAINT if known else C_LOCK))

	# Three figures, side by side, in cards.
	var y := r.position.y + 156.0
	var cw := (r.size.x - 36.0 - 16.0) / 3.0
	_stat(Rect2(x, y, cw, 62), "STOCK", str(n), "units" if n != 1 else "unit",
		C_INK if n > 0 else C_FAINT)
	_stat(Rect2(x + cw + 8.0, y, cw, 62), "EACH", str(price), "coins", C_COIN)
	_stat(Rect2(x + (cw + 8.0) * 2.0, y, cw, 62), "WORTH", Town.grouped(n * price),
		"coins", C_COIN if n > 0 else C_FAINT)
	y += 90.0

	if not known:
		_heading(Vector2(x, y), "WHY IT IS LOCKED")
		y = _wrapped(Vector2(x, y + 24.0), wrap,
			"It wants a tier %d town and this one is tier %d. Ask for it now "
			% [tier, town.tier]
			+ "and whoever you ask will tell you the same thing to your face.",
			16, C_DIM)
		if n > 0:
			_wrapped(Vector2(x, y + 10.0), wrap,
				"There are %d units of it in the yard all the same — it will "
				% n + "keep until the town has grown into it.", 16, C_FAINT)
		return

	_heading(Vector2(x, y), "WHAT IT IS FOR" if larder else "WHAT IT BUILDS")
	y = _wrapped(Vector2(x, y + 24.0), wrap,
		_larder_note(mat) if larder else _use_note(mat), 16, C_DIM)
	if larder:
		return
	y += 14.0

	_heading(Vector2(x, y), "WHERE IT COMES FROM")
	y += 24.0
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


func _heading(at: Vector2, s: String) -> void:
	_text(at, s, 13, UiTheme.GOLD, UiTheme.display(700))


## A figure in a small card: caption, big number, unit.
func _stat(r: Rect2, cap: String, value: String, unit: String, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.95, 0.8, 0.05)
	sb.border_color = Color(1, 0.9, 0.7, 0.10)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	_sheet.draw_style_box(sb, r)
	_text(r.position + Vector2(10, 18), cap, 11, C_FAINT, UiTheme.display(700))
	var f := UiTheme.font(800)
	var size := 24
	while size > 14 and f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > r.size.x - 20.0:
		size -= 2
	_text(r.position + Vector2(10, 43), value, size, col, f)
	_text(r.position + Vector2(10, 58), unit, 11, C_DIM)


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
	if Arsenal.is_item(mat):
		var it := Arsenal.item(mat)
		var parts: Array[String] = []
		for k: String in it["from"]:
			parts.append("%d %s" % [int(it["from"][k]), k.replace("_", " ")])
		var what := "A weapon" if str(it["kind"]) == "weapon" else (
			"Ammunition" if str(it["kind"]) == "ammo" else "The makings of ammunition")
		return "%s. The armoury makes %d at a time from %s, in about %d hours — "\
			% [what, int(it["batch"]), ", ".join(parts), int(ceil(float(it["hours"])))] \
			+ "say \"make some %s\" to anyone free." % Arsenal.label(mat)
	if mat == "food":
		return "What the fields and the animals put in. It is the one thing "\
			+ "here the town earns rather than digs, and it sells the moment "\
			+ "it is picked — which is why the purse moves at harvest."
	return "Wool off the sheep, spun and folded. Earned, like food, and sold "\
		+ "the same way."


# ----------------------------------------------------------------- text helpers

func _text(at: Vector2, s: String, size: int, colour: Color, f: Font = null) -> void:
	var ft := f if f != null else _font
	_sheet.draw_string(ft, at + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, Color(0, 0, 0, 0.6))
	_sheet.draw_string(ft, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


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
