extends RefCounted
class_name EnclosureGenerator
## A fenced rectangle of open ground, with one gate.
##
## The smallest thing that is not a building. It exists because a pen was the
## clearest case of an order the town could nearly meet and had no way to
## express: "pen" was already a module, so the only place a fence could exist
## was *inside* a building, which is not where anybody keeps hens.
##
## The important part is what this does NOT do. It emits a VoxelPatch, exactly
## like BuildingGenerator, which means it inherits the entire rest of the
## pipeline for free — the stores settle its bill before a post goes in, the
## worker walks out and lays it down over in-game hours, the nav grid learns
## about it, and it comes apart the same way. A verb that needed its own
## execution path would have been a second game bolted to the side of this one;
## a verb that returns a patch is just another thing to build.
##
## It is a fence, not a wall: posts and two rails. That is a tenth of the voxels
## of a solid enclosure, which matters because the stores are a real gate, and
## an eight-by-six pen that cost as much timber as a cottage would simply never
## get built.

const V := VoxelChunk.VOXEL_M
const POST_EVERY := 8         ## voxels — a post every two metres
const FENCE_H := 5            ## voxels — 1.25 m, chest high on a person
const TOP_RAIL := 5           ## local height of the top rail, above ground
const LOW_RAIL := 2           ## and the lower one, so stock cannot walk under
## Three metres, not two. The nav grid samples four corners of a metre cell,
## so a two-metre gap between two posts could leave no cell clear and the
## inside of a finished pen unreachable — a farmhand sent to collect the eggs
## stood at the fence forever.
const GATE_W := 12            ## voxels — three metres, wide enough to drive cows through
const MAX_SLOPE := 3          ## voxels of fall across the site before it is a hillside


## Open, roughly level ground near a point, clear of anything already standing.
##
## Rings outward in half-site steps, the same search Farm.find_field runs and
## for the same reason: land as near the asked-for spot as the ground allows,
## and give up rather than wander. Nine rings is about forty metres — beyond
## that the right answer is to ask where, not to put the hens over the horizon.
static func find_site(world: VoxelWorld, near: Vector3, want: Vector2i,
		avoid: Array) -> Rect2i:
	var c := VoxelWorld.to_voxel(near)
	var sx := maxi(want.x / 2, 4)
	var sz := maxi(want.y / 2, 4)
	for radius in range(0, 9):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var r := Rect2i(c.x + dx * sx, c.z + dz * sz, want.x, want.y)
				if _clear(world, r, avoid):
					return r
	return Rect2i()


static func _clear(world: VoxelWorld, r: Rect2i, avoid: Array) -> bool:
	for other: Rect2i in avoid:
		if other.intersects(r):
			return false
	var lo := 1 << 30
	var hi := -(1 << 30)
	# The perimeter is what carries the fence, but the inside has to be standable
	# or the pen is a decorative rectangle with nothing able to be in it.
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var h := world.height_at(x, z)
			if h < 0:
				return false
			var top := world.get_voxel(Vector3i(x, h, z))
			if top == VoxelTypes.WATER:
				return false
			if world.is_solid(Vector3i(x, h + 1, z)):
				return false
			lo = mini(lo, h)
			hi = maxi(hi, h)
			if hi - lo > MAX_SLOPE:
				return false
	return true


## `step` is a validated "enclose" step. Returns {"ok": true, "patch": ...} or
## {"ok": false, "error": ...} in the same shape BuildingGenerator.build uses,
## so the dispatcher does not have to care which generator answered.
static func build(step: Dictionary, world: VoxelWorld, site: Rect2i,
		_ctx: Dictionary) -> Dictionary:
	if site.size.x <= 0 or site.size.y <= 0:
		return {"ok": false, "error": Validator.error("no_open_ground",
			"There is no open ground near here big enough to fence. Where would you like it?")}

	var mat_name := str(step.get("material", "timber"))
	var mat := VoxelTypes.id_of(mat_name)
	if mat < 0:
		return {"ok": false, "error": Validator.error("bad_material",
			"I have never worked with %s. What should I use?" % mat_name.replace("_", " "),
			mat_name)}

	var lo := 1 << 30
	var hi := -(1 << 30)
	for z in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			var h := world.height_at(x, z)
			if h < 0:
				continue
			lo = mini(lo, h)
			hi = maxi(hi, h)
	if lo > hi:
		return {"ok": false, "error": Validator.error("no_open_ground",
			"I could not get the lie of that ground.")}

	var origin := Vector3i(site.position.x, lo, site.position.y)
	var size := Vector3i(site.size.x, (hi - lo) + FENCE_H + 2, site.size.y)
	var patch := VoxelPatch.new(origin, size)
	patch.archetype = "pen"
	patch.footprint = site
	# plot_id stays -1. A pen is not a building, so it never joins the town
	# register and never claims a plot — main.gd's job_done handler looks a plot
	# up by this id and quietly does nothing when there is none, which is
	# exactly right and needed no change to make true.

	var gate := _gate_side(step, site)
	var gate_cells := _gate_cells(site, gate)
	patch.front = _gate_normal(gate)

	for z in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			var on_edge := x == site.position.x or x == site.end.x - 1 \
				or z == site.position.y or z == site.end.y - 1
			if not on_edge:
				continue
			if Vector2i(x, z) in gate_cells:
				continue
			var h := world.height_at(x, z)
			if h < 0:
				continue
			var lx := x - origin.x
			var lz := z - origin.z
			var base := h - origin.y

			# Corners and every two metres get a full post; everything between
			# is two rails, which is what makes this a fence you can see through
			# rather than a wall you cannot.
			var corner := (x == site.position.x or x == site.end.x - 1) \
				and (z == site.position.y or z == site.end.y - 1)
			var post := corner \
				or (x - site.position.x) % POST_EVERY == 0 \
				or (z - site.position.y) % POST_EVERY == 0
			if post:
				for dy in range(1, FENCE_H + 1):
					patch.put(lx, base + dy, lz, mat)
			else:
				patch.put(lx, base + TOP_RAIL, lz, mat)
				patch.put(lx, base + LOW_RAIL, lz, mat)

	if patch.touched == 0:
		return {"ok": false, "error": Validator.error("nothing_to_build",
			"There was nothing to put a fence on there.")}

	# The gate is the door, so the fence grows outward from it in build order —
	# same as a building growing from its entrance. It reads as somebody walking
	# the line rather than the rectangle fading in.
	if not gate_cells.is_empty():
		var g: Vector2i = gate_cells[gate_cells.size() / 2]
		var gh := world.height_at(g.x, g.y)
		patch.doors = [Vector3i(g.x, maxi(gh, lo) + 1, g.y)]
	patch.interior_cells = [Rect2i(site.position + Vector2i.ONE,
		site.size - Vector2i(2, 2))]

	patch.compute_cost()
	patch.compute_build_order()
	return {"ok": true, "patch": patch, "gate": gate}


## Where the animals should actually stand: the middle of the pen, and how far
## they may drift without leaning on the rails.
static func inside_of(site: Rect2i, world: VoxelWorld) -> Dictionary:
	var c := site.get_center()
	var x := float(c.x) * V
	var z := float(c.y) * V
	# Half the shorter side, less enough clearance that nothing stands inside a
	# post. Sixty centimetres, not a metre: an inset of a metre on each side of
	# a five by four pen left a usable circle a metre across, which reads as a
	# pen with one hen in it and a great deal of grass.
	var spread := maxf(float(mini(site.size.x, site.size.y)) * V * 0.5 - 0.6, 0.6)
	return {"centre": Vector3(x, world.ground_m(x, z), z), "spread": spread}


static func _gate_side(step: Dictionary, site: Rect2i) -> String:
	var want := str(step.get("gate", "worker_choice"))
	if want in ["north", "south", "east", "west"]:
		return want
	# Worker's choice: the long side, because that is where a gate goes when
	# nobody has said otherwise — you want room to swing it and room to stand.
	return "south" if site.size.x >= site.size.y else "east"


static func _gate_normal(gate: String) -> Vector3i:
	match gate:
		"north": return Vector3i(0, 0, -1)
		"south": return Vector3i(0, 0, 1)
		"west": return Vector3i(-1, 0, 0)
	return Vector3i(1, 0, 0)


## The run of perimeter cells left out to make the opening, centred on its side.
static func _gate_cells(site: Rect2i, gate: String) -> Array:
	var out: Array = []
	var horizontal := gate == "north" or gate == "south"
	var span := site.size.x if horizontal else site.size.y
	var width := mini(GATE_W, maxi(span - 4, 1))
	var start := (span - width) / 2
	for i in width:
		if horizontal:
			var z := site.position.y if gate == "north" else site.end.y - 1
			out.append(Vector2i(site.position.x + start + i, z))
		else:
			var x := site.position.x if gate == "west" else site.end.x - 1
			out.append(Vector2i(x, site.position.y + start + i))
	return out
