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
	var land := smoothstep(-0.22, 0.30, cont)               # 0 sea, 1 inland

	var h := SEA_LEVEL - 5.0 + land * 9.0

	var hill := _hills.get_noise_2d(wx, wz)
	h += hill * 6.5 * land

	# Ridged noise, gated so mountains appear in bands rather than everywhere.
	var mountain := smoothstep(0.35, 0.85, _continent.get_noise_2d(wx * 0.6, wz * 0.6) * 0.5 + 0.5)
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
# Trees and rocks are decided per 8 m cell from a hash of the cell, so a tree
# that straddles a chunk boundary is generated identically by both chunks.

const FEATURE_CELL := 32          ## voxels; one candidate feature per cell


## Every feature whose canopy could reach into this chunk column. Deterministic.
func features_near(cx: int, cz: int) -> Array:
	var out: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var f := _feature_in_cell(cx + dx, cz + dz)
			if not f.is_empty():
				out.append(f)
	return out


func _feature_in_cell(cell_x: int, cell_z: int) -> Dictionary:
	var hsh := DetRng.mix(DetRng.mix(seed_value, cell_x * 73856093), cell_z * 19349663)
	if (hsh % 1000) < 380:
		return {}                                  # most cells stay empty

	var vx := cell_x * FEATURE_CELL + int((hsh >> 10) % FEATURE_CELL)
	var vz := cell_z * FEATURE_CELL + int((hsh >> 22) % FEATURE_CELL)

	# Nothing grows on the streets, in a plot, on rock or in the sea.
	if village.is_paved(vx, vz):
		return {}
	for p in village.plots:
		if p.contains_v(vx, vz):
			return {}
	var h := height_at(vx, vz)
	if h <= _sea_v + 2 or h > int(30.0 / V):
		return {}

	var wooded := _forest.get_noise_2d(vx * V, vz * V)
	var is_tree := wooded > -0.15 and (hsh % 100) < 78
	if is_tree:
		return {
			"type": "tree", "vx": vx, "vz": vz, "h": h, "hash": hsh,
			"trunk": 13 + int((hsh >> 4) % 10),
			"radius": 6 + int((hsh >> 8) % 4),
		}
	if (hsh % 100) < 92:
		return {}
	return {"type": "rock", "vx": vx, "vz": vz, "h": h, "hash": hsh,
		"radius": 3 + int((hsh >> 6) % 4)}


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
	return _tree_voxels(f) if f["type"] == "tree" else _rock_voxels(f)


func _tree_voxels(f: Dictionary) -> Array:
	var out: Array = []
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var h: int = f["h"]
	var trunk: int = f["trunk"]
	var r: int = f["radius"]
	var hsh: int = f["hash"]

	for i in trunk:
		for dz in 2:
			for dx in 2:
				out.append([Vector3i(ox + dx, h + 1 + i, oz + dz), VoxelTypes.BARK])

	var cy := h + trunk - 2
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var d := Vector3(dx - 0.5, dy * 1.3, dz - 0.5).length()
				if d > float(r):
					continue
				# Deterministic nibble at the canopy edge, so it is not a sphere.
				if d > float(r) - 1.4 						and (DetRng.mix(hsh, dx * 31 + dy * 17 + dz * 7) % 100) < 46:
					continue
				out.append([Vector3i(ox + dx, cy + dy, oz + dz), VoxelTypes.LEAF])
	return out


func _rock_voxels(f: Dictionary) -> Array:
	var out: Array = []
	var ox: int = f["vx"]
	var oz: int = f["vz"]
	var h: int = f["h"]
	var r: int = f["radius"]
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for dy in range(0, r + 1):
				if Vector3(dx, dy * 1.7, dz).length() > float(r):
					continue
				out.append([Vector3i(ox + dx, h + dy - 1, oz + dz), VoxelTypes.ROCK])
	return out


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
