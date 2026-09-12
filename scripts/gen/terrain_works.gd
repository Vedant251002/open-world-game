extends RefCounted
class_name TerrainWorks
## Patches that are not buildings: a tree, a road, a levelled piece of ground,
## a demolition.
##
## Every one of these is a VoxelPatch, which is the whole trick. The stores
## bill it, the worker walks out and lays it down over hours, the nav grid
## learns about it, and Construction applies it voxel by voxel — including
## air, which is what a demolition and a cut are made of. None of it needed a
## new way of changing the world; it needed four small shapes.

const V := VoxelChunk.VOXEL_M


## Trees: `count` of them scattered round `at`, each a trunk of bark and a
## rough ball of leaves sized by the seed, so an orchard is not twelve copies.
## One patch for the lot, because one patch is one job.
static func trees(world: VoxelWorld, at: Vector3, count: int, seed: int,
		avoid: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var centre := VoxelWorld.to_voxel(at)
	var spread := 0 if count <= 1 else 12 + count * 5     # voxels
	var spots: Array[Vector3i] = []
	for _try in count * 8:
		if spots.size() >= count:
			break
		var x := centre.x + rng.randi_range(-spread, spread)
		var z := centre.z + rng.randi_range(-spread, spread)
		var h := world.height_at(x, z)
		if h < 0 or world.get_voxel(Vector3i(x, h, z)) == VoxelTypes.WATER:
			continue
		if world.is_solid(Vector3i(x, h + 1, z)):
			continue
		var blocked := false
		for r: Rect2i in avoid:
			if r.grow(4).has_point(Vector2i(x, z)):
				blocked = true
				break
		for other in spots:
			if absi(other.x - x) < 8 and absi(other.z - z) < 8:
				blocked = true
				break
		if not blocked:
			spots.append(Vector3i(x, h, z))
	if spots.is_empty():
		return {"ok": false, "error": Validator.error("no_open_ground",
			"There is no open ground there to plant in.")}

	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for sp in spots:
		lo = Vector3i(mini(lo.x, sp.x - 12), mini(lo.y, sp.y + 1), mini(lo.z, sp.z - 12))
		hi = Vector3i(maxi(hi.x, sp.x + 12), maxi(hi.y, sp.y + 46), maxi(hi.z, sp.z + 12))
	var patch := VoxelPatch.new(lo, hi - lo + Vector3i.ONE)
	patch.archetype = "tree" if spots.size() == 1 else "grove"
	patch.footprint = Rect2i(lo.x, lo.z, hi.x - lo.x + 1, hi.z - lo.z + 1)
	for sp2 in spots:
		_stamp_tree(patch, sp2 - lo, rng)
	patch.doors = [Vector3i(spots[0].x, spots[0].y + 1, spots[0].z + 12)]
	patch.compute_cost()
	patch.compute_build_order()
	return {"ok": true, "patch": patch, "planted": spots.size()}


static func _stamp_tree(patch: VoxelPatch, base: Vector3i, rng: RandomNumberGenerator) -> void:
	var trunk := rng.randi_range(14, 22)          # 3.5 to 5.5 m
	var crown := rng.randi_range(7, 10)           # radius in voxels
	var cx := base.x
	var cz := base.z
	var y0 := base.y + 1
	for y in trunk:
		patch.put(cx, y0 + y, cz, VoxelTypes.BARK)
		# A thicker foot, so a five-metre tree is not a pole.
		if y < 4:
			patch.put(cx + 1, y0 + y, cz, VoxelTypes.BARK)
			patch.put(cx, y0 + y, cz + 1, VoxelTypes.BARK)
			patch.put(cx + 1, y0 + y, cz + 1, VoxelTypes.BARK)
	var top := y0 + trunk + crown - 2
	for dy in range(-crown, crown + 1):
		for dz in range(-crown, crown + 1):
			for dx in range(-crown, crown + 1):
				var r2 := float(dx * dx + dy * dy * 1.6 + dz * dz)
				if r2 > float(crown * crown) * rng.randf_range(0.72, 1.0):
					continue
				if patch.peek(cx + dx, top + dy, cz + dz) == VoxelTypes.BARK:
					continue
				patch.put(cx + dx, top + dy, cz + dz, VoxelTypes.LEAF)


## A road: the surface voxel along a straight line from `a` to `b`, `width_v`
## voxels wide, set to `mat`. Follows the ground; it does not cut or fill.
static func road(world: VoxelWorld, a: Vector3, b: Vector3, mat: int,
		width_v: int, avoid: Array) -> Dictionary:
	var va := VoxelWorld.to_voxel(a)
	var vb := VoxelWorld.to_voxel(b)
	var p0 := Vector2(va.x, va.z)
	var p1 := Vector2(vb.x, vb.z)
	var length := p0.distance_to(p1)
	if length < 4.0:
		return {"ok": false, "error": Validator.error("road_too_short",
			"Those two places are next to each other.")}
	if length > 600.0:
		return {"ok": false, "error": Validator.error("road_too_long",
			"That is further than I can lay a road in a week.")}

	var half := maxi(width_v / 2, 1)
	var lo := Vector2i(mini(va.x, vb.x) - half, mini(va.z, vb.z) - half)
	var hi := Vector2i(maxi(va.x, vb.x) + half, maxi(va.z, vb.z) + half)
	var ymin := 1 << 30
	var ymax := -(1 << 30)
	var cells: Array[Vector3i] = []
	var dir := (p1 - p0).normalized()
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			# Distance from the centre line, clamped to the segment.
			var q := Vector2(x, z)
			var t := clampf((q - p0).dot(dir), 0.0, length)
			var d := (q - (p0 + dir * t)).length()
			if d > float(half) + 0.5:
				continue
			var h := world.height_at(x, z)
			if h < 0:
				continue
			if world.get_voxel(Vector3i(x, h, z)) == VoxelTypes.WATER:
				continue
			var inside_building := false
			for r: Rect2i in avoid:
				if r.has_point(Vector2i(x, z)):
					inside_building = true
					break
			if inside_building:
				continue
			cells.append(Vector3i(x, h, z))
			ymin = mini(ymin, h)
			ymax = maxi(ymax, h)
	if cells.is_empty():
		return {"ok": false, "error": Validator.error("no_open_ground",
			"There is no ground to lay it on between those two.")}

	var origin := Vector3i(lo.x, ymin, lo.y)
	var patch := VoxelPatch.new(origin, Vector3i(hi.x - lo.x + 1, ymax - ymin + 1, hi.y - lo.y + 1))
	patch.archetype = "road"
	patch.footprint = Rect2i(lo, hi - lo + Vector2i.ONE)
	for cell in cells:
		patch.put(cell.x - origin.x, cell.y - origin.y, cell.z - origin.z, mat)
	patch.doors = [Vector3i(va.x, va.y, va.z)]
	patch.compute_cost()
	patch.compute_build_order()
	return {"ok": true, "patch": patch}


## Level a rectangle of ground to one height: cut what stands above it to air,
## fill what lies below with earth, and grass the top. `target` is a voxel
## height; -1 picks the middle of what is there.
static func flatten(world: VoxelWorld, rect: Rect2i, target: int, avoid: Array) -> Dictionary:
	for r: Rect2i in avoid:
		if r.intersects(rect):
			return {"ok": false, "error": Validator.error("ground_in_use",
				"Something is standing on that ground.")}
	var hs: Array[int] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var h := world.height_at(x, z)
			if h >= 0:
				hs.append(h)
	if hs.is_empty():
		return {"ok": false, "error": Validator.error("no_open_ground",
			"I could not get the lie of that ground.")}
	hs.sort()
	var lo: int = hs[0]
	var hi: int = hs[hs.size() - 1]
	if target < 0:
		target = hs[hs.size() / 2]
	if hi - lo < 2:
		return {"ok": false, "error": Validator.error("already_level",
			"That ground is as flat as I can make it.")}

	# Tall enough to clear anything standing above the target, deep enough to
	# fill the lowest hollow.
	var top := hi + 1
	var origin := Vector3i(rect.position.x, mini(lo, target), rect.position.y)
	var patch := VoxelPatch.new(origin,
		Vector3i(rect.size.x, top - origin.y + 8, rect.size.y))
	patch.archetype = "levelled ground"
	patch.footprint = rect
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var h := world.height_at(x, z)
			if h < 0:
				continue
			var lx := x - origin.x
			var lz := z - origin.z
			if h > target:
				# Cut: everything above the target, plus the room a person
				# needs to stand in, goes to air. Then a new top.
				for y in range(target + 1, h + 8):
					patch.put(lx, y - origin.y, lz, VoxelTypes.AIR)
				patch.put(lx, target - origin.y, lz, VoxelTypes.GRASS)
			elif h < target:
				for y in range(h + 1, target):
					patch.put(lx, y - origin.y, lz, VoxelTypes.DIRT)
				patch.put(lx, target - origin.y, lz, VoxelTypes.GRASS)
	patch.doors = [Vector3i(rect.get_center().x, target + 1, rect.position.y)]
	patch.compute_cost()
	patch.compute_build_order()
	return {"ok": true, "patch": patch}


## Take a building down. Air everywhere it stands, in reverse of the order it
## went up, so the roof comes off first.
static func demolition(rec: Dictionary) -> Dictionary:
	var built: VoxelPatch = rec["patch"]
	var patch := VoxelPatch.new(built.origin, built.size)
	patch.archetype = "demolition"
	patch.footprint = built.footprint
	for i in built.data.size():
		var m := built.data[i]
		if m == VoxelPatch.UNTOUCHED or m == VoxelTypes.AIR:
			continue
		patch.data[i] = VoxelTypes.AIR
		patch.touched += 1
	patch.doors = built.doors.duplicate()
	patch.compute_build_order()
	patch.build_order.reverse()
	# cost stays empty: pulling down is free. The refund is the dispatcher's.
	return {"ok": true, "patch": patch}


## What the stores get back from a demolition: a share of what went in.
static func salvage(rec: Dictionary) -> Dictionary:
	var built: VoxelPatch = rec["patch"]
	var out := {}
	var bill := Resources.bill(built.cost)
	for mat: String in bill:
		var n := int(float(bill[mat]) * 0.4)
		if n > 0:
			out[mat] = n
	return out
