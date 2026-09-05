extends Node3D
class_name Livestock
## The animals in the town, and the produce they leave behind.
##
## Kept as one manager rather than a scene per animal so the flock can be
## thinned when the player is nowhere near it: thirty hens each running their
## own physics on the far side of the valley is thirty character bodies nobody
## can see. Produce is dropped where the animal stood and picked up by walking
## over it, which is the only place in the game the player takes a physical
## action — and it is picking something up, not building, so pillar P1 stands.

signal stock_changed(kind: String, total: int)

const FAR := 78.0                ## beyond this an animal stops simulating
const PRODUCE_LIFE := 900.0      ## seconds before an unclaimed egg is cleaned up
const PICKUP_DIST := 1.35

var world: VoxelWorld
var clock: GameClock
var town: Town
var player: Node3D

var animals: Array[Animal] = []
var _drops: Array[Dictionary] = []      ## {node, kind, born}
var _drop_root: Node3D
var _t := 0.0


func setup(w: VoxelWorld, c: GameClock, t: Town, p: Node3D) -> void:
	world = w
	clock = c
	town = t
	player = p
	_drop_root = Node3D.new()
	_drop_root.name = "Produce"
	add_child(_drop_root)
	set_process(true)


## Puts a small flock on open ground near a point. Returns how many stood up:
## a spot with no room takes fewer than asked for, and that is fine.
func stock_area(species: String, centre: Vector3, count: int, spread: float) -> int:
	var made := 0
	for i in count:
		var a := float(i) / maxf(float(count), 1.0) * TAU + randf() * 0.7
		var r := spread * sqrt(randf())
		var at := centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := world.height_at(int(at.x / 0.25), int(at.z / 0.25))
		if h < 0:
			continue
		var top := world.get_voxel(Vector3i(int(at.x / 0.25), h, int(at.z / 0.25)))
		if top == VoxelTypes.WATER or world.is_solid(Vector3i(int(at.x / 0.25), h + 1,
				int(at.z / 0.25))):
			continue
		at.y = float(h + 1) * 0.25 + 0.15

		var an := Animal.new()
		an.name = "%s_%d" % [species, animals.size()]
		add_child(an)
		an.setup(species, world, clock, at)
		an.avoid = player
		an.home = centre
		an.roam = spread
		an.produced.connect(_on_produced)
		animals.append(an)
		made += 1
	return made


func _on_produced(kind: String, at: Vector3) -> void:
	# One drop per animal at a time is plenty; a field carpeted in eggs is a
	# performance problem wearing a joke.
	if _drops.size() > 40:
		return
	var mi := Props.spawn(_produce_prop(kind), at + Vector3(0, 0.05, 0),
		randf() * TAU, _drop_root)
	mi.scale = Vector3(0.6, 0.6, 0.6)
	_drops.append({"node": mi, "kind": kind, "born": _t})


static func _produce_prop(kind: String) -> String:
	match kind:
		"egg": return "basket"
		"wool": return "hay"
		"milk": return "bucket"
	return "basket"


func _process(delta: float) -> void:
	_t += delta
	if player == null:
		return
	var here := player.global_position

	# Animals far away stop thinking. They keep their position, so the flock is
	# where you left it when you come back.
	for a: Animal in animals:
		if not is_instance_valid(a):
			continue
		var near := a.global_position.distance_to(here) < FAR
		if a.is_physics_processing() != near:
			a.set_physics_process(near)
			a.visible = near

	var keep: Array[Dictionary] = []
	for d: Dictionary in _drops:
		var n: Node3D = d["node"]
		if not is_instance_valid(n):
			continue
		if n.global_position.distance_to(here) < PICKUP_DIST:
			_collect(str(d["kind"]))
			n.queue_free()
			continue
		if _t - float(d["born"]) > PRODUCE_LIFE:
			n.queue_free()
			continue
		# A slow spin, so a dropped egg reads as a thing to pick up rather than
		# a thing that has always been there.
		n.rotation.y += delta * 0.9
		keep.append(d)
	_drops = keep


func _collect(kind: String) -> void:
	var into := "food" if kind != "wool" else "cloth"
	town.stock[into] = int(town.stock.get(into, 0)) + (2 if kind == "wool" else 1)
	stock_changed.emit(into, int(town.stock[into]))


func count_of(species: String) -> int:
	var n := 0
	for a: Animal in animals:
		if is_instance_valid(a) and a.kind == species:
			n += 1
	return n


func total() -> int:
	return animals.size()


func drops_waiting() -> int:
	return _drops.size()
