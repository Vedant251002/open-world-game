extends Node3D
class_name Farm
## Tilled ground and what grows on it.
##
## Two halves, deliberately on different sides of the Tier A / Tier B line from
## voxel-module-spec.md §1:
##
##   the soil is a world voxel — it has to survive the chunk it lives in being
##   unloaded and streamed back, and it has to be visible from the far side of
##   the valley as a patch of brown in the green;
##
##   the crop standing on it is an entity — it changes shape four times as it
##   grows, and re-meshing a 32-cube chunk for every sprout in a forty-tile
##   field would cost more than everything else in the frame together.
##
## Growth runs on the game clock, not on real time, so a field you plant in the
## morning is ready when you come back on the third day whether or not you were
## watching. Water within a few metres makes the difference between a crop that
## ripens and one that sulks — which is the only farming rule the player has to
## learn, and it is legible from the map.

signal crop_ripened(kind: String, at: Vector3)
signal harvested(kind: String, amount: int)

const V := VoxelChunk.VOXEL_M
const WATER_REACH := 16          ## voxels — 4 m, as the crow flies on the flat
const DAYS_PER_STAGE := 1.0
## One plant per metre, not one per voxel. The soil is tilled at full 0.25 m
## resolution so a field reads as a continuous brown rectangle, but a crop is a
## whole entity with a mesh and a collision area, and sixteen of them per square
## metre is a thousand nodes in a small field for no visual gain.
const SOW_STEP := 4
const DRY_PENALTY := 0.45        ## unwatered crops grow at this rate

var world: VoxelWorld
var gen: WorldGen
var clock: GameClock
var town: Town
var crops_root: Node3D

## Vector2i(voxel x, voxel z) -> {kind, stage, growth, wet, node, y}
var tiles: Dictionary = {}
var _wet_cache: Dictionary = {}      ## Vector2i(metre) -> bool


func setup(w: VoxelWorld, g: WorldGen, c: GameClock, t: Town) -> void:
	world = w
	gen = g
	clock = c
	town = t
	crops_root = Node3D.new()
	crops_root.name = "Crops"
	add_child(crops_root)
	clock.day_passed.connect(_on_day)


# ------------------------------------------------------------------ tilling

## Turns one column of ground into soil. Returns false when the ground will not
## take it — stone, water, a road, or somebody's floor.
func till(vx: int, vz: int) -> bool:
	var key := Vector2i(vx, vz)
	if tiles.has(key):
		return false
	var h := world.height_at(vx, vz)
	if h < 0:
		return false
	var top := world.get_voxel(Vector3i(vx, h, vz))
	if top != VoxelTypes.GRASS and top != VoxelTypes.DIRT:
		return false
	# Nothing standing on it. A crop under a floor is not a crop.
	if world.is_solid(Vector3i(vx, h + 1, vz)):
		return false

	var wet := _water_near(vx, h, vz)
	world.set_voxel(Vector3i(vx, h, vz),
		VoxelTypes.WET_FARMLAND if wet else VoxelTypes.FARMLAND)
	tiles[key] = {"kind": "", "stage": -1, "growth": 0.0, "wet": wet,
		"node": null, "y": h}
	return true


## Whether there is water within reach on roughly the same level — crops do not
## care about a lake forty metres below them.
##
## Sampled every metre and cached per square metre. Tilling a field is thousands
## of columns and this is the expensive part of each one; at full resolution a
## worker ploughing paid for two hundred thousand voxel lookups a second.
func _water_near(vx: int, vy: int, vz: int) -> bool:
	var key := Vector2i(vx >> 2, vz >> 2)
	if _wet_cache.has(key):
		return _wet_cache[key]
	var found := false
	for dz in range(-WATER_REACH, WATER_REACH + 1, 4):
		for dx in range(-WATER_REACH, WATER_REACH + 1, 4):
			if dx * dx + dz * dz > WATER_REACH * WATER_REACH:
				continue
			for dy in [0, -1, 1]:
				if world.get_voxel(Vector3i(vx + dx, vy + dy, vz + dz)) == VoxelTypes.WATER:
					found = true
					break
			if found:
				break
		if found:
			break
	_wet_cache[key] = found
	return found


# ------------------------------------------------------------------ planting

func plant(vx: int, vz: int, kind: String) -> bool:
	if posmod(vx, SOW_STEP) != 0 or posmod(vz, SOW_STEP) != 0:
		return false
	var key := Vector2i(vx, vz)
	var t: Dictionary = tiles.get(key, {})
	if t.is_empty() or str(t["kind"]) != "":
		return false
	if not Props.CROPS.has(kind):
		return false
	t["kind"] = kind
	t["stage"] = 0
	t["growth"] = 0.0
	_show_stage(key, t)
	tiles[key] = t
	return true


func _show_stage(key: Vector2i, t: Dictionary) -> void:
	var node: Node3D = t.get("node")
	if node != null:
		node.queue_free()
		t["node"] = null
	var kind := str(t["kind"])
	if kind == "":
		return
	var stages: Array = Props.CROPS[kind]
	var stage: int = clampi(int(t["stage"]), 0, stages.size() - 1)
	var pos := VoxelWorld.centre_metres(Vector3i(key.x, int(t["y"]) + 1, key.y))
	pos.y -= V * 0.5
	var mi := Props.spawn(str(stages[stage]), pos, 0.0, crops_root)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Ripe crops are pickable: the look ray reads layer 4, the same layer the
	# workers answer on, and the HUD tells them apart by type.
	if stage == stages.size() - 1:
		var area := Area3D.new()
		area.collision_layer = 4
		area.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 0.9, 0.3)
		cs.shape = box
		cs.position.y = 0.45
		area.add_child(cs)
		mi.add_child(area)
		mi.set_meta("crop_tile", key)
		mi.set_meta("crop_kind", kind)
	t["node"] = mi


# ------------------------------------------------------------------- growth

func _on_day(_day: int) -> void:
	advance_days(1.0)


## Advances every crop. Split out so a test can push a season through in a frame.
func advance_days(days: float) -> void:
	for key: Vector2i in tiles:
		var t: Dictionary = tiles[key]
		if str(t["kind"]) == "":
			continue
		var stages: Array = Props.CROPS[str(t["kind"])]
		if int(t["stage"]) >= stages.size() - 1:
			continue
		# Watered by hand counts as wet until it dries out again.
		var watered := float(t.get("watered", 0.0))
		if watered > 0.0:
			t["watered"] = maxf(watered - days, 0.0)
		var rate: float = 1.0 if bool(t["wet"]) or watered > 0.0 else DRY_PENALTY
		t["growth"] = float(t["growth"]) + days * rate
		var want := int(float(t["growth"]) / DAYS_PER_STAGE)
		if want == int(t["stage"]):
			tiles[key] = t
			continue
		t["stage"] = mini(want, stages.size() - 1)
		_show_stage(key, t)
		tiles[key] = t
		if int(t["stage"]) == stages.size() - 1:
			crop_ripened.emit(str(t["kind"]),
				VoxelWorld.centre_metres(Vector3i(key.x, int(t["y"]) + 1, key.y)))


## Every tile, for a save. The soil voxel is in the world's stash; this is the
## crop standing on it and how far along it is.
func snapshot() -> Array:
	var out: Array = []
	for key: Vector2i in tiles:
		var t: Dictionary = tiles[key]
		out.append({"key": key, "kind": str(t["kind"]), "stage": int(t["stage"]),
			"growth": float(t["growth"]), "wet": bool(t["wet"]), "y": int(t["y"]),
			"watered": float(t.get("watered", 0.0))})
	return out


func restore(saved: Array) -> void:
	for t: Dictionary in tiles.values():
		var n: Node = t.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	tiles.clear()
	_wet_cache.clear()
	for e: Dictionary in saved:
		var key: Vector2i = e["key"]
		var t := {"kind": str(e["kind"]), "stage": int(e["stage"]),
			"growth": float(e["growth"]), "wet": bool(e["wet"]), "node": null,
			"y": int(e["y"]), "watered": float(e.get("watered", 0.0))}
		tiles[key] = t
		if str(t["kind"]) != "" and int(t["stage"]) >= 0:
			_show_stage(key, t)
			tiles[key] = t


## Watering a field by hand: every tile in the rectangle grows at the wet rate
## for `days`. Returns how many tiles were watered — none, if there is no
## field there, which the worker says rather than pretending.
func water(rect: Rect2i, days: float) -> int:
	var n := 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var key := Vector2i(x, z)
			if not tiles.has(key):
				continue
			var t: Dictionary = tiles[key]
			t["watered"] = maxf(float(t.get("watered", 0.0)), days)
			tiles[key] = t
			n += 1
	return n


# ------------------------------------------------------------------ harvest

func ripe_at(key: Vector2i) -> bool:
	var t: Dictionary = tiles.get(key, {})
	if t.is_empty() or str(t["kind"]) == "":
		return false
	var stages: Array = Props.CROPS[str(t["kind"])]
	return int(t["stage"]) >= stages.size() - 1


## Picks one tile. The soil stays tilled, so a field is worth planting once and
## harvesting for as long as you keep coming back.
func harvest(key: Vector2i) -> String:
	if not ripe_at(key):
		return ""
	var t: Dictionary = tiles[key]
	var kind := str(t["kind"])
	t["kind"] = ""
	t["stage"] = -1
	t["growth"] = 0.0
	_show_stage(key, t)
	tiles[key] = t
	if town != null:
		town.produce("food", 3)
	harvested.emit(kind, 3)
	return kind


func tile_count() -> int:
	return tiles.size()


func planted_count() -> int:
	var n := 0
	for key: Vector2i in tiles:
		if str((tiles[key] as Dictionary)["kind"]) != "":
			n += 1
	return n


func ripe_count() -> int:
	var n := 0
	for key: Vector2i in tiles:
		if ripe_at(key):
			n += 1
	return n


## Somewhere to put a field. Returns the rect chosen, empty if there was no room.
##
## Watered ground wins over near ground. A dry field takes seven in-game days to
## ripen against three, and a worker who ploughed the first flat rectangle they
## trod on regardless of the stream twenty metres away would look like a fool —
## so the search keeps looking for water before it settles for close.
func find_field(near: Vector3, want: Vector2i) -> Dictionary:
	var c := VoxelWorld.to_voxel(near)
	# Half-width steps, so the field lands as close to the asked-for spot as the
	# ground allows rather than a whole field-width away.
	var sx := maxi(want.x / 2, 4)
	var sz := maxi(want.y / 2, 4)
	var dry := Rect2i()
	# Nine rings of half-field steps is about forty metres. Searching further
	# found watered ground on the coast and sent the worker on a quarter-hour
	# walk to reach it — off the navigation grid, out of sight of the town, and
	# not a field anybody would have chosen. If nothing inside forty metres will
	# do, the right answer is to ask where, not to wander.
	for radius in range(0, 9):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var r := Rect2i(c.x + dx * sx, c.z + dz * sz, want.x, want.y)
				if not _field_clear(r):
					continue
				var mid := r.get_center()
				var h := world.height_at(mid.x, mid.y)
				if h >= 0 and _water_near(mid.x, h, mid.y):
					return {"rect": r, "wet": true}
				if dry.size.x == 0:
					dry = r
	return {"rect": dry, "wet": false} if dry.size.x > 0 else {}


func _field_clear(r: Rect2i) -> bool:
	var base := -1
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if tiles.has(Vector2i(x, z)):
				return false
			var h := world.height_at(x, z)
			if h < 0:
				return false
			var top := world.get_voxel(Vector3i(x, h, z))
			if top != VoxelTypes.GRASS and top != VoxelTypes.DIRT:
				return false
			if world.is_solid(Vector3i(x, h + 1, z)):
				return false
			# Flat enough to plough. A field down a hillside is a landslide.
			if base < 0:
				base = h
			elif absi(h - base) > 2:
				return false
	return true
