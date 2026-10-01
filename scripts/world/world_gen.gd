extends RefCounted
class_name WorldGen
## Endless terrain as a pure function of position.
##
## Nothing here holds per-column state, so the chunk streamer can call it from
## several worker threads at once and get identical results in any order. That
## is the whole trick behind a world with no edges: a chunk does not need to
## know about its neighbours to be generated, only about the seed.
##
## Heights come from three scales stacked — a continental drift that decides
## where land is at all, hills that shape a skyline, and a fine break-up so a
## slope is not a smooth ramp. The village shelf is blended in last.

const S := VoxelChunk.SIZE
const V := VoxelChunk.VOXEL_M

const SEA_LEVEL := 9.0             ## metres
const BEDROCK_TOP := 8.0           ## whole chunk layers below this are solid
const MAX_HEIGHT_M := 46.0

var seed_value := 0
var village: Village

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridged := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _ore := FastNoiseLite.new()

## The starting landscape, chosen on the title screen (VillageIdentity): "meadow",
## "coast", "forest" or "hills". The empty string is the classic, unbiased terrain
## that every older save and every test was made with. A preset only reshapes
## the land *outside* the village shelf, so the town itself always fits.
var landscape := ""

var _sea_v := 0
var _bedrock_v := 0
var _max_v := 0


func setup(world_seed: int, town: Village) -> void:
	seed_value = world_seed
	village = town

	_continent.seed = world_seed
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = 0.0016
	_continent.fractal_octaves = 3

	_hills.seed = world_seed ^ 0x1f3a5c
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0090
	_hills.fractal_octaves = 4
	_hills.fractal_gain = 0.48

	_detail.seed = world_seed ^ 0x5bf036
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 0.045

	_ridged.seed = world_seed ^ 0x77c1e9
	_ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridged.frequency = 0.0055
	_ridged.fractal_octaves = 4

	# Ore seams: small pockets rather than veins, at a frequency that puts a
	# worthwhile pocket within a short walk of anywhere.
	_ore.seed = world_seed ^ 0x13d7a5
	_ore.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore.frequency = 0.055

	_forest.seed = world_seed ^ 0x2ab99d
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.006

	_grove.seed = world_seed ^ 0x6c3b1d
	_grove.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_grove.frequency = 0.011

	_sea_v = int(SEA_LEVEL / V)
	_bedrock_v = int(BEDROCK_TOP / V)
	_max_v = int(MAX_HEIGHT_M / V)


func sea_voxel() -> int:
	return _sea_v


func bedrock_voxel() -> int:
	return _bedrock_v


## Surface height for a column, in voxels. The one function everything else in
## the world is derived from.
func height_at(vx: int, vz: int) -> int:
	var wx := vx * V
	var wz := vz * V

	var cont := _continent.get_noise_2d(wx, wz)             # -1..1
	# Landscape preset (see `landscape`): `away` is 0 on the village shelf and 1
	# from ~25 m beyond its edge, so the town itself is never reshaped.
	var away := 0.0
	if landscape != "":
		away = smoothstep(0.0, 25.0, _edge_distance_m(vx, vz))
		match landscape:
			"meadow":
				cont = maxf(cont, 0.12 * away)              # dry country, with ponds in the hollows
			"coast":
				cont = maxf(cont, 0.3 * away)
				var south := (vz - (village.bounds_v.position.y + village.bounds_v.size.y)) * V
				cont -= 1.6 * smoothstep(12.0, 60.0, south)  # the sea to the south
			_:
				cont = maxf(cont, 0.3 * away)               # forest, hills: dry ground all round
	var land := smoothstep(-0.22, 0.30, cont)               # 0 sea, 1 inland

	var h := SEA_LEVEL - 5.0 + land * 9.0

	var hill := _hills.get_noise_2d(wx, wz)
	if landscape == "hills":
		h += (hill * 6.5 * 1.8 + 4.0 * away) * land
	else:
		h += hill * 6.5 * land

	# Ridged noise, gated so mountains appear in bands rather than everywhere.
	var mountain := smoothstep(0.35, 0.85, _continent.get_noise_2d(wx * 0.6, wz * 0.6) * 0.5 + 0.5)
	if landscape == "hills":
		mountain = maxf(mountain, 0.55 * away)
	h += maxf(_ridged.get_noise_2d(wx, wz), 0.0) * 26.0 * mountain * land

	h += _detail.get_noise_2d(wx, wz) * 0.9 * land

	# The village shelf. Blended, not stamped, so the town sits in the land
	# rather than on a plinth dropped into it.
	var lvl := village.levelling(vx, vz)
	if lvl > 0.0:
		h = lerpf(h, Village.FLOOR_HEIGHT, lvl)
	if village.is_paved(vx, vz):
		h = Village.FLOOR_HEIGHT

	return clampi(int(round(h / V)), _bedrock_v + 1, _max_v)


## Metres beyond the edge of the village shelf (0 inside it).
func _edge_distance_m(vx: int, vz: int) -> float:
	var b := village.bounds_v
	var dx := maxf(float(b.position.x - vx), float(vx - (b.position.x + b.size.x)))
	var dz := maxf(float(b.position.y - vz), float(vz - (b.position.y + b.size.y)))
	return maxf(maxf(dx, dz), 0.0) * V


func is_submerged(vx: int, vz: int) -> bool:
	return height_at(vx, vz) <= _sea_v


## Top material for a column, given its height.
func surface_at(vx: int, vz: int, h: int) -> int:
	if village.is_paved(vx, vz):
		return VoxelTypes.GRAVEL if village.is_road_edge(vx, vz) else VoxelTypes.COBBLE
	# Sand only where the beach actually is. Deeper than a metre or so the bed
	# goes to silt, so shallows read as shallows and open water reads as deep.
	if h <= _sea_v - 5:
		return VoxelTypes.DIRT
	if h <= _sea_v + 5:
		return VoxelTypes.SAND
	# Bare rock on steep ground and at altitude, which is what makes a mountain
	# read as a mountain rather than a very tall hill.
	if h > int(30.0 / V):
		return VoxelTypes.ROCK
	if _slope(vx, vz) > 5:
		return VoxelTypes.ROCK
	return VoxelTypes.GRASS


func _slope(vx: int, vz: int) -> int:
	var h := height_at(vx, vz)
	var m := 0
	m = maxi(m, absi(height_at(vx + 2, vz) - h))
	m = maxi(m, absi(height_at(vx - 2, vz) - h))
	m = maxi(m, absi(height_at(vx, vz + 2) - h))
	m = maxi(m, absi(height_at(vx, vz - 2) - h))
	return m


func subsurface_at(vx: int, vz: int, h: int) -> int:
	if village.is_paved(vx, vz):
		return VoxelTypes.GRAVEL
	if h <= _sea_v + 3:
		return VoxelTypes.SAND
	return VoxelTypes.DIRT


# ------------------------------------------------------------------ features
# Trees, bushes, boulders and patches of flowers and tall grass are decided per
# 8 m cell from a hash of the cell, so a tree that straddles a chunk boundary is
# generated identically by both chunks.
#
# Two features never fight over a voxel. Every column of ground belongs to the
# feature it is nearest to (distance over reach, so a big tree outranks a
# flower patch), and a feature only writes the columns it owns. Neighbouring
# crowns therefore meet in a clean seam, like crown shyness in a real wood, and
# what a feature declares is exactly what the world ends up holding.

const FEATURE_CELL := 32          ## voxels; candidate features per cell
const PATCH_SLOTS := 2            ## ground cover patches tried per cell
const PATCH_WEIGHT := 3.5         ## territory of a patch, against a tree's reach

var _grove := FastNoiseLite.new()  ## which species a stretch of wood favours


## Every feature whose body could reach into this chunk column. Deterministic.
func features_near(cx: int, cz: int) -> Array:
	# Cells -3..3 so every feature in -1..1 can see everything that could take
	# a column from it (two reaches of up to 19 voxels is more than a cell).
	var by_cell := {}
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			by_cell[Vector2i(dx, dz)] = _cell_features(cx + dx, cz + dz)
	var out: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for f: Dictionary in by_cell[Vector2i(dx, dz)]:
				var nbrs: Array = []
				for ez in range(-2, 3):
					for ex in range(-2, 3):
						for g: Dictionary in by_cell[Vector2i(dx + ex, dz + ez)]:
							if g["vx"] == f["vx"] and g["vz"] == f["vz"] and g["type"] == f["type"]:
								continue
							var ddx: int = int(g["vx"]) - int(f["vx"])
							var ddz: int = int(g["vz"]) - int(f["vz"])
							var lim: int = int(f["radius"]) + int(g["radius"])
							if ddx * ddx + ddz * ddz < lim * lim:
								nbrs.append([g["vx"], g["vz"], g["w"], g["hash"]])
				f["nbrs"] = nbrs
				out.append(f)
	return out


static func _rf(hsh: int, k: int) -> float:
	return float(DetRng.mix(hsh, k) & 0xFFFFFF) / 16777216.0


static func _r3(hsh: int, x: int, y: int, z: int) -> float:
	return float(DetRng.mix(hsh ^ (x * 73856093), (y * 19349663) ^ (z * 83492791)) & 0xFFFFFF) / 16777216.0


## Nothing grows on the streets or in a plot (with `plot_margin` voxels of
## garden round it), and ground cover keeps out of the town altogether: it is
## solid, and the town's ground has to stay clear for workers, fields and
## whatever gets built next.
func _open_ground(vx: int, vz: int, plot_margin: int, whole_town: bool = false) -> bool:
	if village.is_paved(vx, vz):
		return false
	if whole_town and village.bounds_v.has_point(Vector2i(vx, vz)):
		return false
	for p in village.plots:
		if Rect2i(Vector2i(p.origin.x, p.origin.z), p.size_v).grow(plot_margin).has_point(Vector2i(vx, vz)):
			return false
	return true


func _cell_features(cell_x: int, cell_z: int) -> Array:
	var out: Array = []
	var hsh := DetRng.mix(DetRng.mix(seed_value, cell_x * 73856093), cell_z * 19349663)

	var vx := cell_x * FEATURE_CELL + int(DetRng.mix(hsh, 11) % FEATURE_CELL)
	var vz := cell_z * FEATURE_CELL + int(DetRng.mix(hsh, 12) % FEATURE_CELL)
	if _open_ground(vx, vz, 4):
		var h := height_at(vx, vz)
		if h > _sea_v + 2 and h <= int(30.0 / V):
			var big := _big_feature(vx, vz, h, hsh)
			if not big.is_empty():
				out.append(big)

	for slot in PATCH_SLOTS:
		var ph := DetRng.mix(hsh, 40 + slot)
		var px := cell_x * FEATURE_CELL + int(DetRng.mix(ph, 11) % FEATURE_CELL)
		var pz := cell_z * FEATURE_CELL + int(DetRng.mix(ph, 12) % FEATURE_CELL)
		if _rf(ph, 13) > 0.78 or not _open_ground(px, pz, 3, true):
			continue
		var ph_h := height_at(px, pz)
		if ph_h <= _sea_v + 5 or ph_h > int(30.0 / V):
			continue
		out.append({"type": "patch", "vx": px, "vz": pz, "h": ph_h, "hash": ph,
			"radius": 9, "w": PATCH_WEIGHT, "wooded": _forest.get_noise_2d(px * V, pz * V)})
	return out


func _big_feature(vx: int, vz: int, h: int, hsh: int) -> Dictionary:
	var w := _forest.get_noise_2d(vx * V, vz * V)
	var g := _grove.get_noise_2d(vx * V, vz * V)
	var roll := _rf(hsh, 21)
	var p_tree := clampf(0.10 + (w + 0.2) * 0.9, 0.04, 0.78)
	if landscape == "forest":
		p_tree = clampf(0.55 + (w + 0.2) * 0.6, 0.45, 0.92)
	elif landscape == "hills":
		p_tree *= 0.55

	if roll < p_tree:
		var alt := float(h) * V
		var pine_p := clampf(0.16 + 0.75 * smoothstep(0.15, -0.55, g)
			+ clampf((alt - 16.0) / 16.0, 0.0, 0.45), 0.0, 0.9)
		var birch_p := clampf(0.08 + 0.7 * smoothstep(0.05, 0.6, g), 0.0, 0.7)
		var sp := _rf(hsh, 22)
		var species := "oak"
		if sp < pine_p:
			species = "pine"
		elif sp < pine_p + birch_p * (1.0 - pine_p):
			species = "birch"
		else:
			var o := _rf(hsh, 23)
			if o < 0.10:
				species = "autumn"
			elif o < 0.18:
				species = "blossom"
			elif o < 0.26:
				species = "apple"
		var s := 0.8 + 0.45 * _rf(hsh, 24)
		var reach := 0
		var trunk := 0
		match species:
			"pine":
				s = 0.8 + 0.4 * _rf(hsh, 24)
				trunk = int((20.0 + 12.0 * _rf(hsh, 25)) * s)
				reach = int(ceil(9.0 * s)) + 3
			"birch":
				s = 0.85 + 0.35 * _rf(hsh, 24)
				trunk = int((15.0 + 9.0 * _rf(hsh, 25)) * s)
				reach = int(ceil(8.0 * s)) + 3
			"blossom", "apple":
				s = 0.75 + 0.3 * _rf(hsh, 24)
				trunk = int((9.0 + 4.0 * _rf(hsh, 25)) * s)
				reach = int(ceil(12.0 * s)) + 3
			_:
				trunk = int((12.0 + 5.0 * _rf(hsh, 25)) * s)
				reach = int(ceil(13.0 * s)) + 3
		return {"type": "tree", "species": species, "vx": vx, "vz": vz, "h": h,
			"hash": hsh, "trunk": trunk, "scale": s, "radius": reach, "w": float(reach)}
	if roll < p_tree + (0.20 if w > -0.5 else 0.08):
		var rb := 2 + int(_rf(hsh, 27) * 2.99)
		return {"type": "bush", "vx": vx, "vz": vz, "h": h, "hash": hsh,
			"size": rb, "radius": rb * 2 + 2, "w": float(rb + 3)}
	if roll > 0.955:
		var r := 3 + int(_rf(hsh, 28) * 3.99)
		return {"type": "rock", "vx": vx, "vz": vz, "h": h, "hash": hsh,
			"size": r, "radius": r + 7, "w": float(r + 6)}
	return {}


# --------------------------------------------------------------- chunk build

## Builds every non-empty chunk of one 8x8 m column, from scratch, on whatever
## thread calls it. Returns { Vector3i(cx, cy, cz): VoxelChunk }.
func generate_column(cx: int, cz: int, height_chunks: int) -> Dictionary:
	var chunks := {}
	var base_x := cx * S
	var base_z := cz * S

	var heights := PackedInt32Array()
	heights.resize(S * S)
	var top_v := 0

	for lz in S:
		for lx in S:
			var h := height_at(base_x + lx, base_z + lz)
			heights[lx + lz * S] = h
			top_v = maxi(top_v, maxi(h, _sea_v))

	# Solid bedrock layers come first, as one memset each.
	var bedrock_layers := _bedrock_v / S
	for cy in bedrock_layers:
		var c := VoxelChunk.new(Vector3i(cx, cy, cz))
		c.fill(VoxelTypes.STONE)
		chunks[Vector3i(cx, cy, cz)] = c

	# Chunks up to the terrain surface. Anything that reaches higher — a tree,
	# the well canopy — creates its own chunk as it writes, because deriving the
	# column height from the ground alone trimmed the top off every tree tall
	# enough to cross a chunk boundary.
	var top_chunk := mini(top_v / S, height_chunks - 1)
	for cy in range(bedrock_layers, top_chunk + 1):
		chunks[Vector3i(cx, cy, cz)] = VoxelChunk.new(Vector3i(cx, cy, cz))

	# Surface stack.
	for lz in S:
		for lx in S:
			var vx := base_x + lx
			var vz := base_z + lz
			var h: int = heights[lx + lz * S]
			var surf := surface_at(vx, vz, h)
			var soil := subsurface_at(vx, vz, h)
			var col := lx + lz * S

			for y in range(_bedrock_v, h + 1):
				var mat := VoxelTypes.STONE
				if y == h:
					mat = surf
				elif y > h - 4:
					mat = soil
				elif y < h - 6:
					# Ore and clay in pockets, deterministic from position alone
					# so two players digging the same hill find the same seam.
					mat = _deep_material(vx, y, vz)
				_put(chunks, cx, cz, col, y, mat)
			if h < _sea_v:
				for y in range(h + 1, _sea_v + 1):
					_put(chunks, cx, cz, col, y, VoxelTypes.WATER)

	_carve_village(chunks, cx, cz)
	_build_well(chunks, cx, cz, height_chunks)
	_plant(chunks, cx, cz, height_chunks)

	for k: Vector3i in chunks:
		var c2: VoxelChunk = chunks[k]
		c2.solid_count = VoxelChunk.VOLUME - c2.voxels.count(VoxelTypes.AIR)
	return chunks


## What is in the rock at a given point: mostly stone, with pockets of clay
## nearer the surface and iron deeper down.
##
## A pure function of position, like everything else in the generator, so a seam
## is in the same place every time the column streams back in — a worker sent to
## mine it finds what was there before.
func _deep_material(vx: int, vy: int, vz: int) -> int:
	var n := _ore.get_noise_3d(float(vx), float(vy) * 1.7, float(vz))
	if vy < _bedrock_v + 26 and n > 0.52:
		return VoxelTypes.IRON_ORE
	if n < -0.58:
		return VoxelTypes.CLAY
	return VoxelTypes.STONE


static func _put(chunks: Dictionary, cx: int, cz: int, col: int, y: int, mat: int) -> void:
	var key := Vector3i(cx, y >> 5, cz)
	var c: VoxelChunk = chunks.get(key)
	if c == null:
		c = VoxelChunk.new(key)
		chunks[key] = c
	c.voxels[col + (y & 31) * S * S] = mat


## Streets get headroom cleared above them so a hill does not bury the town.
func _carve_village(chunks: Dictionary, cx: int, cz: int) -> void:
	var base_x := cx * S
	var base_z := cz * S
	if not village.bounds_v.intersects(Rect2i(base_x, base_z, S, S)):
		return
	var floor_v := village.floor_voxel()
	for lz in S:
		for lx in S:
			if not village.is_paved(base_x + lx, base_z + lz):
				continue
			var col := lx + lz * S
			for y in range(floor_v + 1, floor_v + 10):
				_put(chunks, cx, cz, col, y, VoxelTypes.AIR)


## The town well, written by whichever columns it overlaps. It is worldgen
## rather than a placed prop because it has to survive a column unloading and
## come back identical — and because it is the landmark every tier 1
## instruction is measured from.
func _build_well(chunks: Dictionary, cx: int, cz: int, height_chunks: int) -> void:
	var wx := int(village.well_pos.x / V)
	var wz := int(village.well_pos.z / V)
	var top_y := height_chunks * S - 1
	var base_x := cx * S
	var base_z := cz * S

	# Cheap rejection: the well is 14 voxels across, so only nearby columns care.
	if absi(base_x + S / 2 - wx) > S + 20 or absi(base_z + S / 2 - wz) > S + 20:
		return

	var y := village.floor_voxel()

	# Granite apron, then the rim, then the shaft.
	for dz in range(-15, 16):
		for dx in range(-15, 16):
			var d := Vector2(dx, dz).length()
			if d > 15.0:
				continue
			_write(chunks, cx, cz, base_x, base_z, wx + dx, y, wz + dz,
				VoxelTypes.COBBLE if d > 9.0 else VoxelTypes.GRANITE, top_y)

	for dz in range(-7, 8):
		for dx in range(-7, 8):
			var d2 := Vector2(dx, dz).length()
			if d2 <= 7.0 and d2 > 4.6:
				for dy in range(1, 5):
					_write(chunks, cx, cz, base_x, base_z, wx + dx, y + dy, wz + dz,
						VoxelTypes.GRANITE, top_y)
			elif d2 <= 4.6:
				for dy in range(-20, 5):
					_write(chunks, cx, cz, base_x, base_z, wx + dx, y + dy, wz + dz,
						VoxelTypes.WATER if dy < -13 else VoxelTypes.AIR, top_y)

	# Timber frame and a tiled canopy, so the well reads from fifty metres.
	for dz in [-6, 6]:
		for dy in range(5, 17):
			_write(chunks, cx, cz, base_x, base_z, wx - 6, y + dy, wz + dz,
				VoxelTypes.TIMBER, top_y)
			_write(chunks, cx, cz, base_x, base_z, wx + 6, y + dy, wz + dz,
				VoxelTypes.TIMBER, top_y)
	for dz in range(-9, 10):
		for dx in range(-9, 10):
			var rise := 4 - int(absf(dx) / 2.5)
			if rise < 0:
				continue
			_write(chunks, cx, cz, base_x, base_z, wx + dx, y + 16 + rise, wz + dz,
				VoxelTypes.CLAY_TILE, top_y)


func _plant(chunks: Dictionary, cx: int, cz: int, height_chunks: int) -> void:
	var base_x := cx * S
	var base_z := cz * S
	var top_y := height_chunks * S - 1

	for f: Dictionary in features_near(cx, cz):
		# A feature the size of a tree is rarely near this column at all, and
		# building its voxel list only to throw them away is the whole cost.
		var reach: int = f["radius"]
		if absi(int(f["vx"]) - (base_x + S / 2)) > reach + S / 2 \
				or absi(int(f["vz"]) - (base_z + S / 2)) > reach + S / 2:
			continue
		f["clip_x"] = base_x
		f["clip_z"] = base_z
		for e: Array in feature_voxels(f):
			var v: Vector3i = e[0]
			_write(chunks, cx, cz, base_x, base_z, v.x, v.y, v.z, e[1], top_y)


## Every voxel a feature consists of, as [Vector3i, material].
##
## The single source of truth for a feature's shape. _plant writes whichever of
## these fall inside the column it is generating, and the acceptance test checks
## that all of them made it into the assembled world — which is only meaningful
## because both ask the same function.
func feature_voxels(f: Dictionary) -> Array:
	var vox := {}
	match str(f["type"]):
		"tree":
			match str(f["species"]):
				"birch": _birch(f, vox)
				"pine": _pine(f, vox)
				_: _broadleaf(f, vox)
		"bush": _bush(f, vox)
		"rock": _rock(f, vox)
		"patch": _patch(f, vox)
	var out: Array = []
	for v: Vector3i in vox:
		out.append([v, vox[v]])
	return out


## Does this feature own the column? See the note above FEATURE_CELL.
static func _owns(f: Dictionary, x: int, z: int) -> bool:
	# While a chunk column is being generated only its own share is wanted, so
	# everything outside it is refused here, before any voxel is worked out.
	if f.has("clip_x"):
		var lx := x - int(f["clip_x"])
		var lz := z - int(f["clip_z"])
		if lx < 0 or lz < 0 or lx >= S or lz >= S:
			return false
	var w: float = f["w"]
	var dx: float = float(x - int(f["vx"]))
	var dz: float = float(z - int(f["vz"]))
	var mine := (dx * dx + dz * dz) / (w * w)
	var hsh: int = f["hash"]
	for n: Array in f["nbrs"]:
		var nw: float = n[2]
		var ex: float = float(x - int(n[0]))
		var ez: float = float(z - int(n[1]))
		var theirs := (ex * ex + ez * ez) / (nw * nw)
		if theirs < mine or (theirs == mine and int(n[3]) < hsh):
			return false
	return true


static func _vput(vox: Dictionary, f: Dictionary, x: int, y: int, z: int, mat: int) -> void:
	if _owns(f, x, z):
		vox[Vector3i(x, y, z)] = mat


## Leaf material for a canopy voxel. Colour comes in one-metre clumps with a
## voxel-scale scatter on top, and the sunlit upper side runs lighter, so a
## crown reads as lit foliage in layers rather than one green mass.
static func _leaf_mat(species: String, hsh: int, x: int, y: int, z: int, rel: float, tone: float) -> int:
	var n := _r3(hsh ^ 0x9e37, x, y, z)
	var k := _r3(hsh, x >> 2, y >> 2, z >> 2) * 0.6 + n * 0.4 + tone
	match species:
		"birch":
			return VoxelTypes.LEAF_BIRCH if k + rel * 0.2 > 0.40 else VoxelTypes.LEAF_LIGHT
		"autumn":
			if k < 0.22:
				return VoxelTypes.LEAF
			return VoxelTypes.LEAF_BIRCH if k < 0.36 else VoxelTypes.LEAF_AUTUMN
		"blossom":
			return VoxelTypes.BLOSSOM if k + rel * 0.1 > 0.30 else VoxelTypes.LEAF_LIGHT
		"apple":
			if n > 0.93 and rel < 0.85:
				return VoxelTypes.FLOWER_RED
			return VoxelTypes.LEAF_LIGHT if k + rel * 0.25 > 0.5 else VoxelTypes.LEAF
		"bush":
			if n > 0.94:
				return VoxelTypes.FLOWER_RED if tone > 0.0 else VoxelTypes.FLOWER_WHITE
			return VoxelTypes.LEAF_LIGHT if k + rel * 0.2 > 0.56 else VoxelTypes.LEAF
	return VoxelTypes.LEAF_LIGHT if k + rel * 0.25 > 0.62 else VoxelTypes.LEAF


## An ellipsoid of leaves, ragged at the rim and with holes through it, so
## light gets into the crown and the silhouette is not a ball.
func _lobe(vox: Dictionary, f: Dictionary, cx: float, cy: float, cz: float,
		rx: float, ry: float, species: String, tone: float, hole: float = 0.07) -> void:
	var hsh: int = f["hash"]
	for z in range(int(floor(cz - rx)) - 1, int(ceil(cz + rx)) + 2):
		for x in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 2):
			if not _owns(f, x, z):
				continue
			for y in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 2):
				var ax := (float(x) - cx) / rx
				var ay := (float(y) - cy) / ry
				var az := (float(z) - cz) / rx
				var d := sqrt(ax * ax + ay * ay + az * az)
				if d > 1.0:
					continue
				var n := _r3(hsh, x, y, z)
				if d > 0.72 and n < (d - 0.72) * 2.1:
					continue
				if _r3(hsh ^ 0x5bd1, x, y, z) < hole:
					continue
				vox[Vector3i(x, y, z)] = _leaf_mat(species, hsh, x, y, z,
					(float(y) - (cy - ry)) / (2.0 * ry), tone)


## A column of wood from the ground under it up to `top`, so a trunk on a slope
## meets the hill rather than hovering over it.
func _trunk_column(vox: Dictionary, f: Dictionary, x: int, z: int, top: int, mat: int) -> void:
	if not _owns(f, x, z):
		return
	for y in range(mini(height_at(x, z), int(f["h"])), top + 1):
		vox[Vector3i(x, y, z)] = mat


## Oak family: a thick trunk with a flared foot and roots, limbs that carry
## separate lobes of leaves, and a lobe on top, so the crown is lumpy and broad.
func _broadleaf(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var h: int = f["h"]
	var hsh: int = f["hash"]
	var sp: String = f["species"]
	var s: float = f["scale"]
	var t: int = f["trunk"]
	var tw := 3 if (s > 1.12 and sp == "oak") else 2
	var cx := float(ox) + float(tw - 1) * 0.5
	var cz := float(oz) + float(tw - 1) * 0.5
	var tone := (_rf(hsh, 30) - 0.5) * 0.22
	var big := 1.0 if sp == "oak" or sp == "autumn" else 0.8

	# Canopy first; the wood is written over it.
	var top_r := (6.0 + 2.0 * _rf(hsh, 31)) * s * big
	var tcx := cx + (_rf(hsh, 32) - 0.5) * 3.0
	var tcz := cz + (_rf(hsh, 33) - 0.5) * 3.0
	_lobe(vox, f, tcx, float(h + t + 2), tcz, top_r, top_r * 0.8, sp, tone)

	var nb := 3 + int(_rf(hsh, 34) * 1.99)
	var a0 := _rf(hsh, 35) * TAU
	var limbs: Array = []
	for k in nb:
		var a := a0 + float(k) * TAU / float(nb) + (_rf(hsh, 36 + k) - 0.5) * 0.7
		var length := (5.0 + 2.0 * _rf(hsh, 40 + k)) * s * big
		var y0 := float(t) * (0.55 + 0.2 * _rf(hsh, 44 + k))
		limbs.append([a, length, y0])
		var lx := cx + cos(a) * length
		var lz := cz + sin(a) * length
		var ly := float(h) + y0 + length * 0.6
		var lr := (3.6 + 1.6 * _rf(hsh, 48 + k)) * s * big
		_lobe(vox, f, lx, ly, lz, lr, lr * 0.8, sp, tone)

	# Trunk, flared at the foot.
	for dz in tw:
		for dx in tw:
			_trunk_column(vox, f, ox + dx, oz + dz, h + t + 2, VoxelTypes.BARK)
	for dz in range(-1, tw + 1):
		for dx in range(-1, tw + 1):
			var inside := dx >= 0 and dx < tw and dz >= 0 and dz < tw
			var corner := (dx < 0 or dx >= tw) and (dz < 0 or dz >= tw)
			if inside or corner:
				continue
			_trunk_column(vox, f, ox + dx, oz + dz,
				h + 1 + int(_rf(hsh, 52 + dx * 5 + dz) * 2.0), VoxelTypes.BARK)
	# Roots creeping out along the ground.
	for k in 4:
		var rdx: int = [1, 0, -1, 0][k]
		var rdz: int = [0, 1, 0, -1][k]
		var rl := 1 + int(_rf(hsh, 60 + k) * 3.0)
		var bx := ox + (tw if rdx > 0 else (-1 if rdx < 0 else int(_rf(hsh, 64 + k) * tw)))
		var bz := oz + (tw if rdz > 0 else (-1 if rdz < 0 else int(_rf(hsh, 68 + k) * tw)))
		for j in range(1, rl + 1):
			var rx := bx + rdx * j
			var rz := bz + rdz * j
			if _owns(f, rx, rz):
				vox[Vector3i(rx, height_at(rx, rz) + (1 if j == 1 else 0), rz)] = VoxelTypes.BARK

	# Limbs: thick at the trunk, one voxel at the tip.
	for lm: Array in limbs:
		var a: float = lm[0]
		var length: float = lm[1]
		var y0: float = lm[2]
		for j in range(0, int(length) + 1):
			var bx2 := int(round(cx + cos(a) * float(j)))
			var bz2 := int(round(cz + sin(a) * float(j)))
			var by := h + int(y0) + int(float(j) * 0.6)
			_vput(vox, f, bx2, by, bz2, VoxelTypes.BARK)
			if j < int(length * 0.4):
				_vput(vox, f, bx2, by + 1, bz2, VoxelTypes.BARK)


## Birch: pale slim trunk with a slight lean, small ovoid crown in light
## yellow-green with a couple of side tufts.
func _birch(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var h: int = f["h"]
	var hsh: int = f["hash"]
	var s: float = f["scale"]
	var t: int = f["trunk"]
	var tone := (_rf(hsh, 30) - 0.5) * 0.2
	var ph := _rf(hsh, 31) * TAU
	var lean := (_rf(hsh, 32) - 0.5) * 0.12
	var wob := 0.9 + _rf(hsh, 33)

	var top_x := ox
	var top_z := oz
	var px := ox
	var pz := oz
	for i in range(0, t + 1):
		var x := ox + int(round(sin(float(i) * 0.21 + ph) * wob + lean * float(i) * 3.0))
		var z := oz + int(round(cos(float(i) * 0.17 + ph) * wob * 0.7))
		# Join diagonal steps so the trunk stays one piece.
		if x != px and z != pz:
			_trunk_column(vox, f, x, pz, h + 1 + i, VoxelTypes.BIRCH_BARK)
		_trunk_column(vox, f, x, z, h + 1 + i, VoxelTypes.BIRCH_BARK)
		px = x
		pz = z
		top_x = x
		top_z = z
	# A swollen foot.
	for k in 4:
		if _rf(hsh, 36 + k) < 0.7:
			_trunk_column(vox, f, ox + [1, 0, -1, 0][k], oz + [0, 1, 0, -1][k],
				h + 1 + int(_rf(hsh, 40 + k) * 2.0), VoxelTypes.BIRCH_BARK)

	var cx := float(top_x)
	var cz := float(top_z)
	_lobe(vox, f, cx, float(h + t - 1), cz, 4.2 * s, 6.5 * s, "birch", tone, 0.12)
	var nl := 2 + int(_rf(hsh, 44) * 1.99)
	for k in nl:
		var a := _rf(hsh, 45 + k) * TAU
		var d := (2.4 + 1.2 * _rf(hsh, 49 + k)) * s
		var ly := float(h + t) - (3.0 + 4.0 * _rf(hsh, 53 + k)) * s
		var lr := (2.6 + 0.8 * _rf(hsh, 57 + k)) * s
		_lobe(vox, f, cx + cos(a) * d, ly, cz + sin(a) * d, lr, lr * 1.3, "birch", tone, 0.12)
		# A thin limb running out to the tuft.
		for j in range(1, 4):
			_vput(vox, f, int(round(cx + cos(a) * d * float(j) / 3.0)), int(ly) - 1 + j / 2,
				int(round(cz + sin(a) * d * float(j) / 3.0)), VoxelTypes.BIRCH_BARK)


## Spruce / pine: dark trunk, layered tiers that shrink to a spike, each tier a
## drooping skirt with an uneven star-like rim and gaps between the boughs.
func _pine(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var h: int = f["h"]
	var hsh: int = f["hash"]
	var s: float = f["scale"]
	var t: int = f["trunk"]
	var rmax := (6.5 + 2.5 * _rf(hsh, 26)) * s
	var cx := float(ox) + 0.5
	var cz := float(oz) + 0.5
	var y0 := 4 + int(_rf(hsh, 31) * 2.99)
	var ph := _rf(hsh, 32) * TAU
	var tier_gap := 3 if t > 22 else 2

	var yk := y0
	var idx := 0
	while yk <= t:
		var fr := float(yk - y0) / float(maxi(t - y0, 1))
		var rk := rmax * pow(1.0 - fr, 0.85) + 0.9
		for z in range(int(floor(cz - rk)) - 2, int(ceil(cz + rk)) + 3):
			for x in range(int(floor(cx - rk)) - 2, int(ceil(cx + rk)) + 3):
				if not _owns(f, x, z):
					continue
				var dx := float(x) - cx
				var dz := float(z) - cz
				var d := sqrt(dx * dx + dz * dz)
				var star := 1.0 + 0.2 * sin(atan2(dz, dx) * 3.0 + float(idx) * 1.7 + ph)
				var r := rk * star
				if d > r + 0.5:
					continue
				var n := _r3(hsh, x, h + yk, z)
				if d > r - 1.2 and n < 0.32:
					continue
				if _r3(hsh ^ 0x5bd1, x, yk, z) < 0.05:
					continue
				var m := VoxelTypes.PINE_NEEDLES
				vox[Vector3i(x, h + yk, z)] = m
				if d >= r * 0.45 and d <= r * 0.9:
					vox[Vector3i(x, h + yk - 1, z)] = m
				if d <= r * 0.55:
					vox[Vector3i(x, h + yk + 1, z)] = m
		yk += tier_gap
		idx += 1

	for dz in 2:
		for dx in 2:
			_trunk_column(vox, f, ox + dx, oz + dz, h + t, VoxelTypes.BARK)
	# The foot flares and the leader tapers into a spike of needles.
	for fp: Array in [[2, 0], [-1, 1], [0, 2], [1, -1]]:
		_trunk_column(vox, f, ox + int(fp[0]), oz + int(fp[1]), h + 1, VoxelTypes.BARK)
	for dz in 2:
		for dx in 2:
			_vput(vox, f, ox + dx, h + t + 1, oz + dz, VoxelTypes.PINE_NEEDLES)
	for y in range(h + t + 2, h + t + 5):
		_vput(vox, f, ox, y, oz, VoxelTypes.PINE_NEEDLES)


## A low rounded shrub that follows the ground under it, studded with berries.
func _bush(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var hsh: int = f["hash"]
	var rb: int = f["size"]
	var tone := (_rf(hsh, 30) - 0.5) * 0.3
	var lobes: Array = [[0.0, 0.0, float(rb)]]
	var extra := 1 + int(_rf(hsh, 31) * 2.0)
	for k in extra:
		var a := _rf(hsh, 32 + k) * TAU
		lobes.append([cos(a) * float(rb) * 0.9, sin(a) * float(rb) * 0.9, float(rb) * 0.75])
	for z in range(oz - rb * 2, oz + rb * 2 + 1):
		for x in range(ox - rb * 2, ox + rb * 2 + 1):
			if not _owns(f, x, z):
				continue
			var top := 0.0
			for lb: Array in lobes:
				var dx := float(x - ox) - float(lb[0])
				var dz := float(z - oz) - float(lb[1])
				var r: float = lb[2]
				var q := (dx * dx + dz * dz) / (r * r)
				if q < 1.0:
					top = maxf(top, r * 0.8 * sqrt(1.0 - q))
			if top < 0.5:
				continue
			var g := height_at(x, z)
			for y in range(g + 1, g + 2 + int(round(top))):
				if _r3(hsh ^ 0x5bd1, x, y, z) < 0.06:
					continue
				vox[Vector3i(x, y, z)] = _leaf_mat("bush", hsh, x, y, z,
					float(y - g) / (top + 1.0), tone)


## A boulder, draped over the ground: irregular outline, mossy on top and a
## couple of small stones leaning against it.
func _rock(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var hsh: int = f["hash"]
	var r: int = f["size"]
	var bodies: Array = [[0.0, 0.0, float(r), 0.7]]
	var sat := int(_rf(hsh, 31) * 2.99)
	for k in sat:
		var a := _rf(hsh, 32 + k) * TAU
		var d := float(r) + 1.5 + _rf(hsh, 36 + k) * 2.0
		bodies.append([cos(a) * d, sin(a) * d, 1.5 + _rf(hsh, 40 + k) * 1.6, 0.8])
	var span := r + 7
	for z in range(oz - span, oz + span + 1):
		for x in range(ox - span, ox + span + 1):
			if not _owns(f, x, z):
				continue
			var top := 0.0
			for b: Array in bodies:
				var dx := float(x - ox) - float(b[0])
				var dz := float(z - oz) - float(b[1])
				var rr: float = float(b[2]) * (0.78 + 0.5 * _r3(hsh, (x - ox) >> 1, 0, (z - oz) >> 1))
				var q := (dx * dx + dz * dz) / (rr * rr)
				if q < 1.0:
					top = maxf(top, rr * float(b[3]) * 1.6 * sqrt(1.0 - q))
			if top < 0.6:
				continue
			var g := height_at(x, z)
			var hh := int(round(top))
			for y in range(g, g + hh + 1):
				var m := VoxelTypes.ROCK
				var from_top := g + hh - y
				if from_top == 0 and _r3(hsh, x, y, z) < 0.7:
					m = VoxelTypes.MOSS
				elif from_top == 1 and _r3(hsh ^ 0x77, x, y, z) < 0.25:
					m = VoxelTypes.MOSS
				vox[Vector3i(x, y, z)] = m


## A drift of flowers, tall grass or ferns lying one to two voxels over the
## ground. Sparse on purpose: these are solid, and the player walks round them.
func _patch(f: Dictionary, vox: Dictionary) -> void:
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var hsh: int = f["hash"]
	var wooded: float = f["wooded"]
	var style := _rf(hsh, 3)
	var pal := [VoxelTypes.FLOWER_RED, VoxelTypes.FLOWER_YELLOW,
		VoxelTypes.FLOWER_WHITE, VoxelTypes.FLOWER_PURPLE]
	var c1: int = pal[int(_rf(hsh, 4) * 3.99)]
	var c2: int = pal[int(_rf(hsh, 5) * 3.99)]
	var radius := 5.0 + 4.0 * _rf(hsh, 6)
	var fill := 0.26 + 0.2 * _rf(hsh, 7)
	var sea5 := _sea_v + 5
	var cap := int(30.0 / V)

	for z in range(oz - 9, oz + 10):
		for x in range(ox - 9, ox + 10):
			var dx := float(x - ox)
			var dz := float(z - oz)
			var d := sqrt(dx * dx + dz * dz)
			if d > radius:
				continue
			var p := fill * (1.0 - d / radius * 0.8)
			if _r3(hsh, x, 0, z) > p:
				continue
			if not _owns(f, x, z):
				continue
			var g := height_at(x, z)
			if g <= sea5 or g > cap or _slope(x, z) > 5:
				continue
			if not _open_ground(x, z, 2, true):
				continue
			var n := _r3(hsh ^ 0x31, x, 1, z)
			var mat := VoxelTypes.TALL_GRASS
			var tall := 1
			if style < 0.30:
				mat = c1 if n < 0.55 else (c2 if n < 0.88 else VoxelTypes.TALL_GRASS)
			elif style < 0.62:
				tall = 2 if n < 0.5 else 1
				if n > 0.93:
					mat = c1
					tall = 1
			elif style < 0.80:
				mat = VoxelTypes.FERN if wooded > -0.2 else VoxelTypes.TALL_GRASS
				tall = 2 if n < 0.45 else 1
			else:
				mat = c1 if n < 0.85 else VoxelTypes.TALL_GRASS
			for y in range(g + 1, g + 1 + tall):
				vox[Vector3i(x, y, z)] = mat


## Writes a voxel only if it falls inside this chunk column. Features are
## generated by every column they overlap, and each keeps only its own share.
##
## Creates the chunk if it does not exist yet: a tree standing on the surface
## reaches five or six metres above it, which is often the next chunk up, and
## dropping those writes is what left every tall tree with a flat top.
static func _write(chunks: Dictionary, cx: int, cz: int, base_x: int, base_z: int,
		vx: int, vy: int, vz: int, mat: int, top_y: int) -> void:
	if vy < 0 or vy > top_y:
		return
	var lx := vx - base_x
	var lz := vz - base_z
	if lx < 0 or lz < 0 or lx >= S or lz >= S:
		return
	var key := Vector3i(cx, vy >> 5, cz)
	var c: VoxelChunk = chunks.get(key)
	if c == null:
		c = VoxelChunk.new(key)
		chunks[key] = c
	c.voxels[lx + lz * S + (vy & 31) * S * S] = mat
