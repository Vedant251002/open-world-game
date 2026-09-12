extends Node3D
class_name Wildlife
## Everything alive that nobody owns: the birds, the fish, the deer at the
## edge of the woods, the dog by the well.
##
## Livestock is stocked on purpose and stays put. Wildlife is the opposite: it
## is wherever you are, in the numbers the place can carry, and it is not
## there when you are not. So this keeps a small population alive around the
## player and lets the rest of the valley be empty — a crow on every roof in a
## town nobody is looking at is a hundred crows for no one.
##
## Where each thing goes is decided by what the ground says. A gull wants
## water within sight; a fish wants water under it; a deer wants grass beyond
## the last street; an owl wants a ridge and the dark.

const TICK := 2.5                 ## seconds between population checks
const NEAR := 90.0                ## the radius that is kept stocked
const BEAST_NEAR := 55.0          ## inside this the quadrupeds are simulated
const FAR := 150.0                ## beyond this, gone
const BIRDS := 7
const FISH := 10
const DUCKS := 3
const WILD := 6                   ## deer, rabbits and foxes together

var world: VoxelWorld
var clock: GameClock
var town: Town
var village: Village
var player: Node3D

var birds: Array[Bird] = []
var fish: Array[Fish] = []
var beasts: Array[Animal] = []     ## the wild quadrupeds and the town pets
var _t := 0.0
var _pets_placed := false


func setup(w: VoxelWorld, c: GameClock, t: Town, v: Village, p: Node3D) -> void:
	world = w
	clock = c
	town = t
	village = v
	player = p
	set_process(true)


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	var here := player.global_position
	if not _pets_placed:
		_place_pets()
	_cull(here)
	_thin(here)
	_stock_birds(here)
	_stock_water(here)
	_stock_wild(here)


# ------------------------------------------------------------- bookkeeping

## Anything too far away to matter is removed. It is not paused and kept —
## wildlife is not scenery you come back to, and a crow that flew off is a
## crow that flew off.
func _cull(here: Vector3) -> void:
	var keep_b: Array[Bird] = []
	for b: Bird in birds:
		if is_instance_valid(b) and b.global_position.distance_to(here) < FAR:
			keep_b.append(b)
		elif is_instance_valid(b):
			b.queue_free()
	birds = keep_b
	var keep_f: Array[Fish] = []
	for f: Fish in fish:
		if is_instance_valid(f) and f.global_position.distance_to(here) < FAR:
			keep_f.append(f)
		elif is_instance_valid(f):
			f.queue_free()
	fish = keep_f
	var keep_a: Array[Animal] = []
	for a: Animal in beasts:
		if not is_instance_valid(a):
			continue
		# The pets stay whatever the distance; the wild does not.
		if not a.is_wild() or a.global_position.distance_to(here) < FAR:
			keep_a.append(a)
		else:
			a.queue_free()
	beasts = keep_a


## Things in range keep thinking; things out of it do not, so a school of
## fish on the far side of the town is ten positions and nothing else.
func _thin(here: Vector3) -> void:
	for b: Bird in birds:
		var near := b.global_position.distance_to(here) < NEAR
		if b.is_processing() != near:
			b.set_process(near)
			b.visible = near
	for f: Fish in fish:
		var near := f.global_position.distance_to(here) < NEAR
		if f.is_processing() != near:
			f.set_process(near)
			f.visible = near
	for a: Animal in beasts:
		# A closer line for the quadrupeds. Each one is a character body in the
		# physics world, and a deer stood still at sixty metres looks exactly
		# like a deer thinking about it. It stays visible; it stops moving.
		var near := a.global_position.distance_to(here) < BEAST_NEAR
		if a.is_physics_processing() != near:
			a.set_physics_process(near)


func _near_count(list: Array, here: Vector3, kinds: Array = []) -> int:
	var n := 0
	for x: Node3D in list:
		if not is_instance_valid(x):
			continue
		if x.global_position.distance_to(here) > NEAR:
			continue
		if not kinds.is_empty() and str(x.get("kind")) not in kinds:
			continue
		n += 1
	return n


func count_of(species: String) -> int:
	var n := 0
	for b: Bird in birds:
		if is_instance_valid(b) and b.kind == species:
			n += 1
	for f: Fish in fish:
		if is_instance_valid(f) and f.kind == species:
			n += 1
	for a: Animal in beasts:
		if is_instance_valid(a) and a.kind == species:
			n += 1
	return n


func species_seen() -> Dictionary:
	var out := {}
	for list: Array in [birds, fish, beasts]:
		for x: Node3D in list:
			if is_instance_valid(x):
				var k := str(x.get("kind"))
				out[k] = int(out.get(k, 0)) + 1
	return out


# ------------------------------------------------------------------- birds

func _stock_birds(here: Vector3) -> void:
	var night := clock != null and (clock.hour >= 20.0 or clock.hour < 5.0)
	var have := _near_count(birds, here, ["crow", "sparrow", "gull", "owl"])
	if have >= BIRDS:
		return
	var perches := _perches_near(here)
	if perches.is_empty():
		return
	var perch: Vector3 = perches[randi() % perches.size()]
	var species := "sparrow" if randf() < 0.5 else "crow"
	if _water_near(perch, 45.0) != Vector3.INF and randf() < 0.6:
		species = "gull"
	if night and randf() < 0.35 and count_of("owl") == 0:
		species = "owl"
	if not night and species == "owl":
		species = "crow"
	var b := Bird.new()
	b.name = "%s_%d" % [species, birds.size()]
	add_child(b)
	b.setup(species, world, perch)
	b.avoid = player
	b.perches = perches
	birds.append(b)


## Ridges of the buildings in reach, the tops of trees, and failing both a few
## spots on open ground. A bird will sit on any of them.
func _perches_near(here: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if town != null:
		for rec: Dictionary in town.buildings:
			var patch: VoxelPatch = rec.get("patch", null)
			if patch == null:
				continue
			var fr := patch.footprint
			var cx := fr.position.x + fr.size.x / 2
			var cz := fr.position.y + fr.size.y / 2
			var at := Vector3(cx * 0.25, 0.0, cz * 0.25)
			if at.distance_to(here) > 70.0:
				continue
			var h := world.height_at(cx, cz)
			if h > 0:
				out.append(Vector3(at.x, (h + 1) * 0.25, at.z))
	# Treetops: leaf voxels on top of a column.
	for _i in 10:
		var p := here + Vector3(randf_range(-50, 50), 0.0, randf_range(-50, 50))
		var v := VoxelWorld.to_voxel(p)
		var h := world.height_at(v.x, v.z)
		if h > 0 and world.get_voxel(Vector3i(v.x, h, v.z)) == VoxelTypes.LEAF:
			out.append(Vector3(p.x, (h + 1) * 0.25, p.z))
	if out.size() < 3:
		for _i in 3:
			var p2 := here + Vector3(randf_range(-30, 30), 0.0, randf_range(-30, 30))
			var g := world.ground_m(p2.x, p2.z)
			if g > 0.0:
				out.append(Vector3(p2.x, g, p2.z))
	return out


# ------------------------------------------------------------------- water

## Fish under the water and ducks on it, wherever there is enough of it.
func _stock_water(here: Vector3) -> void:
	var fish_have := _near_count(fish, here)
	var duck_have := _near_count(birds, here, ["duck"])
	if fish_have >= FISH and duck_have >= DUCKS:
		return
	var spot := _water_near(here, NEAR)
	if spot == Vector3.INF:
		return
	spot = _out_from_shore(spot, here)
	var depth := _depth_at(spot)
	if fish_have < FISH and depth >= 0.75:
		var species: String = ["carp", "trout", "perch"][randi() % 3]
		var n := randi_range(3, 5)
		for i in n:
			var f := Fish.new()
			f.name = "%s_%d" % [species, fish.size()]
			add_child(f)
			var at := spot + Vector3(randf_range(-1.5, 1.5), -randf_range(0.3, depth - 0.3),
				randf_range(-1.5, 1.5))
			f.setup(species, world, at)
			f.avoid = player
			f.pool = spot
			f.pool_r = 4.0
			f.surface_y = spot.y
			f.floor_y = spot.y - depth
			fish.append(f)
	if duck_have < DUCKS and depth >= 0.5:
		for i in 2:
			var d := Bird.new()
			d.name = "duck_%d" % birds.size()
			add_child(d)
			var at := spot + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			d.setup("duck", world, at)
			d.avoid = player
			d.pond = spot
			d.pond_r = 5.0
			d.surface_y = spot.y
			birds.append(d)


## The nearest open water within `r` of `at`, or INF.
##
## Rings of probes out from the point rather than a scatter: the sea is a big
## target but it is off to one side of the town, and a dozen random throws
## across a ninety metre disc missed it most of the time. Thirty-two probes on
## four rings find a shore reliably and cost nothing worth measuring.
func _water_near(at: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for ring in 4:
		var rad := r * (ring + 1) / 4.0
		for k in 8:
			var a := (k + randf() * 0.5) / 8.0 * TAU
			var p := at + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
			var v := VoxelWorld.to_voxel(p)
			var h := world.height_at(v.x, v.z)
			if h <= 0:
				continue
			if world.get_voxel(Vector3i(v.x, h, v.z)) == VoxelTypes.WATER and rad < best_d:
				best = Vector3(p.x, (h + 1) * 0.25, p.z)
				best_d = rad
		if best_d < INF:
			return best
	return best


## The first water found is the shoreline, by construction — it is the
## nearest wet probe to dry land. A pool centred there is half beach, and the
## fish in it swim up it. So walk on, away from where the player stands, until
## the point has water on every side or the walk runs out.
func _out_from_shore(spot: Vector3, here: Vector3) -> Vector3:
	var dir := spot - here
	dir.y = 0.0
	if dir.length() < 0.1:
		return spot
	dir = dir.normalized()
	var best := spot
	for step in 6:
		var p := spot + dir * (3.0 * (step + 1))
		if not _all_water(p, 4.0):
			continue
		best = p
		best.y = spot.y
		if step >= 2:
			break
	return best


func _all_water(p: Vector3, r: float) -> bool:
	for k in 8:
		var a := k / 8.0 * TAU
		var q := p + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var v := VoxelWorld.to_voxel(q)
		var h := world.height_at(v.x, v.z)
		if h <= 0 or world.get_voxel(Vector3i(v.x, h, v.z)) != VoxelTypes.WATER:
			return false
	return true


func _depth_at(surface: Vector3) -> float:
	var v := VoxelWorld.to_voxel(surface - Vector3(0, 0.1, 0))
	var y := v.y
	var n := 0
	while y >= 0 and world.get_voxel(Vector3i(v.x, y, v.z)) == VoxelTypes.WATER and n < 40:
		y -= 1
		n += 1
	return n * 0.25


# -------------------------------------------------------------------- land

## Deer, rabbits and a fox, on grass beyond the streets.
func _stock_wild(here: Vector3) -> void:
	if _near_count(beasts, here, ["deer", "rabbit", "fox"]) >= WILD:
		return
	for _i in 8:
		var a := randf() * TAU
		var d := randf_range(35.0, 85.0)
		var p := here + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var v := VoxelWorld.to_voxel(p)
		if village != null and village.bounds_v.grow(24).has_point(Vector2i(v.x, v.z)):
			continue
		var h := world.height_at(v.x, v.z)
		if h <= 0 or world.get_voxel(Vector3i(v.x, h, v.z)) != VoxelTypes.GRASS:
			continue
		if world.is_solid(Vector3i(v.x, h + 1, v.z)):
			continue
		var at := Vector3(p.x, (h + 1) * 0.25 + 0.1, p.z)
		var roll := randf()
		if roll < 0.35:
			_beast("deer", at, randi_range(1, 2), 6.0)
		elif roll < 0.8:
			_beast("rabbit", at, randi_range(2, 3), 4.0)
		else:
			_beast("fox", at, 1, 8.0)
		return


func _beast(species: String, at: Vector3, count: int, spread: float) -> void:
	for i in count:
		var an := Animal.new()
		an.name = "%s_%d" % [species, beasts.size()]
		add_child(an)
		var spot := at + Vector3(randf_range(-spread, spread) * 0.5, 0.0,
			randf_range(-spread, spread) * 0.5)
		spot.y = world.ground_m(spot.x, spot.z) + 0.1
		an.setup(species, world, clock, spot)
		an.avoid = player
		an.home = at
		an.roam = spread * 2.0
		if an.is_wild() and village != null:
			an.keep_out = village.bounds_v.grow(12)
		beasts.append(an)


## The town's own animals: a sheepdog that lies by the well and comes to see
## who you are, and a cat on the bakery step. Placed once and never culled.
func _place_pets() -> void:
	if village == null:
		return
	_pets_placed = true
	var well := village.well_pos
	_beast("dog", well + Vector3(4.0, 0.0, 3.0), 1, 1.0)
	var step := well + Vector3(-5.0, 0.0, -4.0)
	if town != null:
		for rec: Dictionary in town.buildings:
			if str(rec["archetype"]) in ["bakery", "store", "tavern"]:
				var patch: VoxelPatch = rec.get("patch", null)
				if patch != null:
					var fr := patch.footprint
					var front: Vector3i = patch.front
					step = Vector3((fr.position.x + fr.size.x / 2) * 0.25, 0.0,
						(fr.position.y + fr.size.y / 2) * 0.25) \
						+ Vector3(front) * (maxf(fr.size.x, fr.size.y) * 0.25 * 0.5 + 1.5)
					break
	_beast("cat", step, 1, 1.5)
