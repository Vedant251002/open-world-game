extends RefCounted
class_name MapPixels
## The map, the way Minecraft draws one: looking straight down, one pixel per
## column, coloured by whatever is on top of it from a small fixed palette, and
## shaded by comparing each column with the one just north of it — lighter
## where the ground steps up, darker where it steps down. Water is one blue,
## darker the deeper it is, with a checker between depths.
##
## Land you have been near (its columns loaded at some point) is drawn from the
## real voxels, so roofs, roads, fields and trees all show, and it stays drawn
## after you walk away. Land you have never been near is surveyed from the
## world generator in the same palette, washed toward the parchment, so the
## map still shows the lie of the country beyond.
##
## Explored land is kept as one 32 x 32 image per column of chunks, made a few
## per frame. Zoomed out, a column's image is shrunk by whole powers of two
## (nearest, never blended), as Minecraft's zoomed maps are.

const V := VoxelChunk.VOXEL_M
const T := 32                              ## voxels per column side
## Minecraft's own map colours, by name.
const MC := {
	"grass": Color8(127, 178, 56), "sand": Color8(247, 233, 163), "fire": Color8(255, 0, 0),
	"ice": Color8(160, 160, 255), "metal": Color8(167, 167, 167), "plant": Color8(0, 124, 0),
	"snow": Color8(255, 255, 255), "clay": Color8(164, 168, 184), "dirt": Color8(151, 109, 77),
	"stone": Color8(112, 112, 112), "water": Color8(64, 64, 255), "wood": Color8(143, 119, 72),
	"quartz": Color8(255, 252, 245), "orange": Color8(216, 127, 51), "yellow": Color8(229, 229, 51),
	"gray": Color8(76, 76, 76), "light_gray": Color8(153, 153, 153), "brown": Color8(102, 76, 51),
	"red": Color8(153, 51, 51), "black": Color8(25, 25, 25), "pink": Color8(242, 127, 165),
	"cyan": Color8(76, 127, 153), "blue": Color8(51, 76, 178), "podzol": Color8(129, 86, 49),
	"terracotta": Color8(159, 82, 36),
}
## Minecraft's three shades: lower than the block to the north, level, higher.
const SHADE_LOW := 180.0 / 255.0
const SHADE_FLAT := 220.0 / 255.0
const SHADE_HIGH := 1.0
const PARCHMENT := Color8(222, 206, 162)  ## the empty map, before anything is drawn on it
const UNEXPLORED_WASH := 0.42              ## how far surveyed-only land is washed out
## Explored-column work per frame, in milliseconds (more while the map is open).
const BUDGET_OPEN_MS := 6.0
const BUDGET_CLOSED_MS := 1.5
## A column being built on is redrawn at most this often.
const REDRAW_EDITED_S := 1.5
## Coarsest zoom: a pixel per this many voxels (a column is then 2 pixels).
const MAX_STEP := 16

var world: VoxelWorld
var gen: WorldGen
var village: Village
var revision := 0                          ## bumps whenever a column image changes
var stat_column_us := 0                    ## how long the last column took to draw

var _palette := PackedColorArray()         ## voxel id -> map colour
var _tiles: Dictionary = {}                ## Vector2i -> {img: Image, mips: {s: Image}, rev: int}
var _queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _scan_t := 0.0
var _edited_at: Dictionary = {}            ## Vector2i -> msec it was last redrawn


func setup(w: VoxelWorld, g: WorldGen, v: Village) -> void:
	world = w
	gen = g
	village = v
	_palette.resize(VoxelTypes.COUNT)
	for id in VoxelTypes.COUNT:
		_palette[id] = MC[_mc_name(id)]


## Which Minecraft colour each of our materials maps to.
static func _mc_name(id: int) -> String:
	match id:
		VoxelTypes.TIMBER, VoxelTypes.PLANK: return "wood"
		VoxelTypes.BRICK, VoxelTypes.PAINTED_RED: return "red"
		VoxelTypes.SANDSTONE, VoxelTypes.SAND, VoxelTypes.BIRCH_BARK: return "sand"
		VoxelTypes.GRANITE, VoxelTypes.DIRT, VoxelTypes.FARMLAND, VoxelTypes.WET_FARMLAND: return "dirt"
		VoxelTypes.CONCRETE, VoxelTypes.PLASTIC_PANEL: return "light_gray"
		VoxelTypes.REBAR_CONCRETE, VoxelTypes.CONCRETE_SLAB, VoxelTypes.GRAVEL, VoxelTypes.COBBLE, \
				VoxelTypes.STONE, VoxelTypes.ROCK, VoxelTypes.IRON_ORE: return "stone"
		VoxelTypes.STEEL_FRAME, VoxelTypes.CORRUGATED_STEEL, VoxelTypes.SHEET_METAL, VoxelTypes.CHROME: return "metal"
		VoxelTypes.GLASS, VoxelTypes.REINFORCED_GLASS: return "ice"
		VoxelTypes.CARBON_COMPOSITE, VoxelTypes.MATTE_BLACK: return "black"
		VoxelTypes.THATCH, VoxelTypes.WHEAT_HEAD, VoxelTypes.WHEAT_STRAW: return "yellow"
		VoxelTypes.CLAY_TILE: return "terracotta"
		VoxelTypes.ASPHALT_SHINGLE, VoxelTypes.ASPHALT: return "gray"
		VoxelTypes.SOLAR_PANEL: return "blue"
		VoxelTypes.GRASS: return "grass"
		VoxelTypes.DARK_OAK: return "brown"
		VoxelTypes.PAINTED_WHITE: return "quartz"
		VoxelTypes.NEON_STRIP: return "cyan"
		VoxelTypes.WATER: return "water"
		VoxelTypes.BARK: return "podzol"
		VoxelTypes.EMBER: return "fire"
		VoxelTypes.CLAY: return "clay"
		VoxelTypes.LEAF_AUTUMN: return "orange"
		VoxelTypes.BLOSSOM: return "pink"
	return "plant"   # leaves, needles, ferns, moss, flowers, crops


# -------------------------------------------------------------- shading rules

## Minecraft's height shading: compare with the column to the north.
static func land_shade(h: int, h_north: int) -> float:
	if h > h_north:
		return SHADE_HIGH
	if h < h_north:
		return SHADE_LOW
	return SHADE_FLAT


## Minecraft's water shading: by depth, with a checker between bands.
static func water_shade(depth_m: float, x: int, z: int) -> float:
	var odd := (x + z) & 1
	if depth_m < 0.6:
		return SHADE_HIGH
	if depth_m < 1.2:
		return SHADE_HIGH if odd == 0 else SHADE_FLAT
	if depth_m < 2.0:
		return SHADE_FLAT
	if depth_m < 3.2:
		return SHADE_FLAT if odd == 0 else SHADE_LOW
	return SHADE_LOW


# ---------------------------------------------------------- explored columns

## Called every frame. Finds loaded columns not yet drawn (or built on since),
## and draws as many as the budget allows, nearest first.
func tick(delta: float, focus_m: Vector2, open: bool) -> void:
	if world == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5 if open else 1.5
		_scan(focus_m)
	if _queue.is_empty():
		return
	var budget := BUDGET_OPEN_MS if open else BUDGET_CLOSED_MS
	var until := Time.get_ticks_usec() + int(budget * 1000.0)
	while not _queue.is_empty() and Time.get_ticks_usec() < until:
		var key: Vector2i = _queue.pop_back()
		_queued.erase(key)
		var t0 := Time.get_ticks_usec()
		_draw_column(key)
		stat_column_us = Time.get_ticks_usec() - t0


func _scan(focus_m: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var fresh := false
	for key: Vector2i in world._htiles.keys():
		if _queued.has(key):
			continue
		var rev := world.column_revision(key.x, key.y)
		var t: Dictionary = _tiles.get(key, {})
		if not t.is_empty():
			if int(t["rev"]) == rev:
				continue
			# Being built on: not every brick, but every second or so.
			if now - int(_edited_at.get(key, 0)) < int(REDRAW_EDITED_S * 1000.0):
				continue
		_queue.append(key)
		_queued[key] = true
		fresh = true
	if fresh:
		# Nearest last, because the queue is popped from the back.
		var f := Vector2(focus_m.x / (T * V), focus_m.y / (T * V))
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a).distance_squared_to(f) > Vector2(b).distance_squared_to(f))


func _draw_column(key: Vector2i) -> void:
	var heights: PackedInt32Array = world._htiles.get(key, PackedInt32Array())
	if heights.is_empty():
		return
	var rev := world.column_revision(key.x, key.y)
	var layers: Array = []
	for cy in world.height_chunks:
		layers.append(world.chunks.get(Vector3i(key.x, cy, key.y)))
	var north: PackedInt32Array = world._htiles.get(Vector2i(key.x, key.y - 1), PackedInt32Array())
	var sea := gen.sea_voxel() if gen != null else -1000
	var data := PackedByteArray()
	data.resize(T * T * 4)
	var bx := key.x * T
	var bz := key.y * T
	var water: Color = _palette[VoxelTypes.WATER]
	for lz in T:
		for lx in T:
			var h := heights[lx + lz * T]
			if h < 0:
				continue                    # nothing loaded here: left clear
			var hn := h
			if lz > 0:
				hn = heights[lx + (lz - 1) * T]
			elif not north.is_empty():
				hn = north[lx + (T - 1) * T]
			# Placed water sits above the top solid voxel; the sea is a plane.
			var top := h
			while _voxel(layers, lx, top + 1, lz) == VoxelTypes.WATER:
				top += 1
			var col: Color
			if top > h:
				col = water * water_shade((top - h) * V, bx + lx, bz + lz)
			elif h <= sea:
				col = water * water_shade((sea - h) * V, bx + lx, bz + lz)
			else:
				col = _palette[_voxel(layers, lx, h, lz)] * land_shade(h, hn)
			var o := (lx + lz * T) * 4
			data[o] = int(col.r * 255.0)
			data[o + 1] = int(col.g * 255.0)
			data[o + 2] = int(col.b * 255.0)
			data[o + 3] = 255
	var img := Image.create_from_data(T, T, false, Image.FORMAT_RGBA8, data)
	_tiles[key] = {"img": img, "mips": {}, "rev": rev}
	_edited_at[key] = Time.get_ticks_msec()
	revision += 1


static func _voxel(layers: Array, lx: int, y: int, lz: int) -> int:
	if y < 0:
		return VoxelTypes.AIR
	var cy := y >> 5
	if cy >= layers.size() or layers[cy] == null:
		return VoxelTypes.AIR
	var c: VoxelChunk = layers[cy]
	return c.voxels[lx + lz * T + (y & 31) * T * T]


## A column's picture at one pixel per `step` voxels (a power of two).
func _mip(t: Dictionary, step: int) -> Image:
	if step <= 1:
		return t["img"]
	var mips: Dictionary = t["mips"]
	if not mips.has(step):
		var m: Image = (t["img"] as Image).duplicate()
		var n := maxi(T / step, 1)
		m.resize(n, n, Image.INTERPOLATE_NEAREST)
		mips[step] = m
	return mips[step]


func explored(key: Vector2i) -> bool:
	return _tiles.has(key)


func explored_count() -> int:
	return _tiles.size()


# -------------------------------------------------------------------- grids

## The pixel grid for a view: whole powers of two of voxels per pixel, and an
## origin snapped to that, so the pixels do not swim as the map is dragged.
## Returns {origin: Vector2i voxels, step: int, n: int pixels per side}.
static func grid_for(centre_m: Vector2, span_m: float, max_px: int) -> Dictionary:
	var want := span_m / V / float(max_px)
	var step := 1
	while step < want and step < MAX_STEP:
		step *= 2
	var n := max_px
	var half := n * step / 2
	# Whole columns, so a column's picture always lands on whole pixels.
	var ox := int(floor((centre_m.x / V - half) / T)) * T
	var oz := int(floor((centre_m.y / V - half) / T)) * T
	return {"origin": Vector2i(ox, oz), "step": step, "n": n}


## The explored land on a grid, transparent where nothing has been seen.
func compose_explored(g: Dictionary) -> Image:
	var n: int = g["n"]
	var step: int = g["step"]
	var o: Vector2i = g["origin"]
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var k0 := Vector2i(int(floor(float(o.x) / T)), int(floor(float(o.y) / T)))
	var k1 := Vector2i(int(floor(float(o.x + n * step - 1) / T)), int(floor(float(o.y + n * step - 1) / T)))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var t: Dictionary = _tiles.get(Vector2i(kx, kz), {})
			if t.is_empty():
				continue
			var m := _mip(t, step)
			var at := Vector2i((kx * T - o.x) / step, (kz * T - o.y) / step)
			img.blit_rect(m, Rect2i(Vector2i.ZERO, m.get_size()), at)
	return img


## Unexplored country, surveyed from the generator. Pure, so it runs on a
## worker thread. One extra row is sampled to the north for the shading.
static func survey(g: Dictionary, wgen: WorldGen, vil: Village) -> Image:
	var n: int = g["n"]
	var step: int = g["step"]
	var o: Vector2i = g["origin"]
	var sea := wgen.sea_voxel()
	var high := int(30.0 / V)
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var prev := PackedInt32Array()
	prev.resize(n)
	for i in n:
		prev[i] = wgen.height_at(o.x + i * step, o.y - step)
	var row := PackedInt32Array()
	row.resize(n)
	var water: Color = MC["water"]
	for j in n:
		var vz := o.y + j * step
		for i in n:
			row[i] = wgen.height_at(o.x + i * step, vz)
		for i in n:
			var vx := o.x + i * step
			var h := row[i]
			var col: Color
			if h <= sea:
				col = water * water_shade((sea - h) * V, i, j)
			else:
				var name := "grass"
				if vil != null and vil.is_paved(vx, vz):
					name = "stone"
				elif h <= sea + 5:
					name = "sand"
				elif h > high:
					name = "snow" if h > high + int(6.0 / V) else "stone"
				else:
					var hw := row[maxi(i - 1, 0)]
					if absf(h - prev[i]) / step + absf(h - hw) / step > 2.5:
						name = "stone"
				col = (MC[name] as Color) * land_shade(h, prev[i])
			col = col.lerp(PARCHMENT, UNEXPLORED_WASH)
			var p := (i + j * n) * 4
			data[p] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[p + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[p + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			data[p + 3] = 255
		var swap := prev
		prev = row
		row = swap
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
