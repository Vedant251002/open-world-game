extends RefCounted
class_name Quarry
## Digging a material out of the world, over in-game time.
##
## The same shape as Construction and FieldWork, because it is the same beat:
## the worker goes away, the world changes while nobody is watching it happen,
## and they come back with news. Here what changes is a hole in a hillside and
## a number in the stores.
##
## The hole is real. A worker sent for stone leaves a cut in the ground that is
## still there next week, which is the only honest way to show that the town's
## materials came from somewhere.

const V := VoxelChunk.VOXEL_M

var world: VoxelWorld
var town: Town
var material := ""        ## the stock key being filled
var source := -1          ## the world voxel being dug
var wanted := 0           ## units still needed when the job was given
var site := Vector3i.ZERO ## where the digging happens

var got := 0
var finished := false
var exhausted := false    ## ran out of seam before filling the order

## Voxels cut per in-game hour, before the worker's own pace.
var voxels_per_hour := 34.0

var _order: Array[Vector3i] = []
var _cursor := 0
var _carry := 0.0


func _init(w: VoxelWorld, t: Town, mat: String, amount: int, at: Vector3i) -> void:
	world = w
	town = t
	material = mat
	wanted = amount
	site = at
	source = Resources.source_of(mat)
	_plan_cut()


## The order the voxels come out in: nearest the surface first, so the hole
## reads as something dug rather than as a cavern that was always there.
func _plan_cut() -> void:
	var per := Resources.yield_of(source)
	var need := int(ceil(float(wanted) / float(maxi(per, 1))))
	var found: Array = []
	# A shaft rather than a quarry: narrow, and as deep as it needs to be.
	for r in range(0, 7):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for dy in range(0, 34):
					var v := Vector3i(site.x + dx, site.y - dy, site.z + dz)
					if v.y < 2:
						break
					if world.get_voxel(v) == source:
						found.append([dy + r * 2, v])
		if found.size() >= need:
			break
	found.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for e: Array in found:
		_order.append(e[1])
		if _order.size() >= need:
			break


func total() -> int:
	return _order.size()


func progress() -> float:
	if _order.is_empty():
		return 1.0
	return float(_cursor) / float(_order.size())


func advance(hours: float) -> void:
	if finished:
		return
	_carry += hours * voxels_per_hour
	var n := int(_carry)
	if n <= 0:
		return
	_carry -= n
	_cut(n)


func complete_now() -> void:
	_cut(_order.size())


func _cut(n: int) -> void:
	var per := Resources.yield_of(source)
	var end := mini(_cursor + n, _order.size())
	while _cursor < end:
		var v: Vector3i = _order[_cursor]
		_cursor += 1
		# Somebody may have built over it since the cut was planned.
		if world.get_voxel(v) != source:
			continue
		world.set_voxel(v, VoxelTypes.AIR)
		got += per
		town.stock[material] = int(town.stock.get(material, 0)) + per
	if _cursor >= _order.size():
		finished = true
		exhausted = got < wanted


func summary() -> String:
	if exhausted:
		return "%d %s — the seam ran out" % [got, material.replace("_", " ")]
	return "%d %s" % [got, material.replace("_", " ")]


## Somewhere to dig for this material.
##
## Preference in order, because all three read differently to a player: open
## country outside the town, then the vacant ground between the blocks. A
## quarry in the plaza or through somebody's floor is never allowed, and a site
## nobody can walk to is no site at all — an unreachable seam would just be an
## excuse dressed up as geology.
static func find_site(w: VoxelWorld, village: Village, mat: String,
		near: Vector3, reach: Rect2i = Rect2i()) -> Vector3i:
	var src := Resources.source_of(mat)
	if src < 0:
		return Vector3i.ZERO
	var centre := VoxelWorld.to_voxel(near)
	var out := _search(w, village, src, centre, reach, true)
	if out != Vector3i.ZERO:
		return out
	return _search(w, village, src, centre, reach, false)


## Rings outward from the worker, nearest first, so the errand is as short as
## the ground allows.
static func _search(w: VoxelWorld, village: Village, src: int, centre: Vector3i,
		reach: Rect2i, outside_town: bool) -> Vector3i:
	for rv in range(20, 300, 10):
		var n := clampi(rv / 5, 12, 48)
		for a in n:
			var ang := float(a) / float(n) * TAU
			var hit := _probe(w, village, src,
				centre.x + int(cos(ang) * float(rv)),
				centre.z + int(sin(ang) * float(rv)), reach, outside_town)
			if hit != Vector3i.ZERO:
				return hit
	return Vector3i.ZERO


## Is there any of this within a few metres of here?
##
## Wood needs the wider look. Stone, sand and clay are layers — hit the column
## anywhere and you have found them — but a trunk is two voxels across, and
## sampling one column at a time would walk a worker through a forest reporting
## that there were no trees in it.
static func _probe(w: VoxelWorld, village: Village, src: int, vx: int, vz: int,
		reach: Rect2i, outside_town: bool) -> Vector3i:
	var wood := src == VoxelTypes.BARK or src == VoxelTypes.LEAF
	var span := 6 if wood else 0
	var step := 3 if wood else 1
	var depth := 20 if wood else 44
	for dz in range(-span, span + 1, step):
		for dx in range(-span, span + 1, step):
			var cx := vx + dx
			var cz := vz + dz
			var at := Vector2i(cx, cz)
			if reach.size.x > 0 and not reach.has_point(at):
				continue
			if outside_town:
				if village.bounds_v.has_point(at):
					continue
			elif not village.is_diggable(cx, cz):
				continue
			var h := w.height_at(cx, cz)
			if h < 0:
				continue
			# Trees stand above the ground; everything else is under it.
			var top := h + 14 if wood else h
			for dy in range(0, depth):
				var v := Vector3i(cx, top - dy, cz)
				if v.y < 2:
					break
				if w.get_voxel(v) == src:
					return Vector3i(cx, maxi(v.y, h), cz)
	return Vector3i.ZERO
