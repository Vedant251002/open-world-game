extends Node3D
class_name Projectile
## A thing in flight: a ball, a grenade, a shell or a rocket.
##
## Not a physics body. The world is voxels, so the exact question "is there
## anything solid along the next five centimetres" is answered by reading the
## voxels along the next five centimetres, which is both cheaper than a
## collision query and never misses a thin wall between two samples. Each
## kind differs in what it does when it arrives:
##
##   bullet   — flies flat and fast, drops a little, stops in whatever it hits
##              and hurts whoever that was.
##   grenade  — thrown in an arc, bounces off the ground and walls, and goes
##              off when the fuse runs out wherever it happens to be lying.
##   shell    — lobbed high by a mortar, comes down under gravity, explodes on
##              the first thing it touches.
##   rocket   — leaves the tube slowly, lights, accelerates hard, steers toward
##              its target, and explodes on contact or when it runs out.
##
## Anything that explodes hands the rest to Blast.

const STEP := 0.05                ## metres between voxel samples along a move
const GRAVITY := 11.0             ## a little under real, so an arc is visible
const HIT_RADIUS := 0.55          ## how close to a body counts as hitting it

var kind := "bullet"
var side := "town"
var shooter: Node3D = null
var warfare: Node = null
var world: VoxelWorld
var velocity := Vector3.ZERO
var damage := 30.0
var blast_r := 0.0
var blast_power := 0.0
var fuse := 0.0                   ## grenades: seconds until it goes off
var life := 4.0                   ## everything else: seconds until it is gone
var target: Node3D = null         ## rockets: what to steer at
var target_point := Vector3.INF   ## rockets: or where, if nothing in particular

var _t := 0.0
var _lit := false
var _smoke := 0.0
var _resting := false


func setup(w: VoxelWorld, wf: Node, from: Vector3, vel: Vector3, spec: Dictionary,
		who: Node3D, which_side: String) -> void:
	world = w
	warfare = wf
	global_position = from
	velocity = vel
	shooter = who
	side = which_side
	kind = str(spec.get("projectile", "bullet"))
	damage = float(spec.get("damage", 0.0))
	blast_r = float(spec.get("blast", 0.0))
	blast_power = float(spec.get("power", 0.0))
	fuse = float(spec.get("fuse", 0.0))
	match kind:
		"bullet": life = 3.0
		"grenade": life = fuse + 0.5
		"shell": life = 12.0
		"rocket": life = 9.0
	_build()
	_face(velocity)
	set_physics_process(true)


# -------------------------------------------------------------------- shape

func _build() -> void:
	match kind:
		"bullet":
			BoxKit.add(self, Vector3(-0.012, -0.012, -0.05), Vector3(0.024, 0.024, 0.10),
				Color("#d8c27a"))
		"grenade":
			BoxKit.add(self, Vector3(-0.06, -0.06, -0.06), Vector3(0.12, 0.12, 0.12),
				Color("#2b2f2b"))
			BoxKit.add(self, Vector3(-0.02, 0.06, -0.02), Vector3(0.04, 0.04, 0.04),
				Color("#8a8070"))
		"shell":
			BoxKit.add(self, Vector3(-0.07, -0.07, -0.16), Vector3(0.14, 0.14, 0.32),
				Color("#4a4f55"))
			BoxKit.add(self, Vector3(-0.045, -0.045, 0.16), Vector3(0.09, 0.09, 0.08),
				Color("#7a5a30"))
		"rocket":
			BoxKit.add(self, Vector3(-0.06, -0.06, -0.28), Vector3(0.12, 0.12, 0.5),
				Color("#6c7076"))
			BoxKit.add(self, Vector3(-0.045, -0.045, 0.22), Vector3(0.09, 0.09, 0.12),
				Color("#b8302a"))
			for i in 4:
				var a := i * PI * 0.5
				var fin := Node3D.new()
				fin.position = Vector3(0, 0, -0.24)
				fin.rotation.z = a
				add_child(fin)
				BoxKit.add(fin, Vector3(0.05, -0.01, -0.04), Vector3(0.09, 0.02, 0.1),
					Color("#3a3d42"))
	for n: Node in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _face(v: Vector3) -> void:
	if v.length_squared() < 0.0001:
		return
	look_at(global_position + v, Vector3.UP)
	# look_at points -Z at the target; every model here faces +Z.
	rotate_object_local(Vector3.UP, PI)


# ------------------------------------------------------------------- flight

func _physics_process(delta: float) -> void:
	_t += delta
	if _t > life:
		if kind == "grenade" or kind == "shell" or kind == "rocket":
			_explode()
		else:
			queue_free()
		return

	match kind:
		"rocket":
			_rocket(delta)
		"grenade":
			if not _resting:
				velocity.y -= GRAVITY * delta
			if _t >= fuse:
				_explode()
				return
		"shell":
			velocity.y -= GRAVITY * delta
		_:
			velocity.y -= GRAVITY * 0.35 * delta

	if _resting:
		return
	var move := velocity * delta
	var hit := _sweep(move)
	if hit.is_empty():
		global_position += move
		_face(velocity)
		return

	# Something in the way.
	if hit.has("body"):
		var body: Node3D = hit["body"]
		if kind == "bullet":
			if body.has_method("take_hit"):
				body.take_hit(damage, global_position, shooter)
			if warfare != null and warfare.has_method("note_hit"):
				warfare.note_hit(self, body)
			queue_free()
			return
		global_position = hit["at"]
		_explode()
		return

	# The world.
	global_position = hit["at"]
	match kind:
		"bullet":
			_chip(hit["voxel"])
			queue_free()
		"grenade":
			_bounce(hit["normal"])
		_:
			_explode()


## Walks the move in small steps and reports the first thing it runs into:
## a voxel (with the face it came through) or a body.
func _sweep(move: Vector3) -> Dictionary:
	var dist := move.length()
	if dist < 0.0001:
		return {}
	var dir := move / dist
	var steps := maxi(int(ceil(dist / STEP)), 1)
	var from := global_position
	var bodies: Array = []
	if warfare != null and warfare.has_method("bodies_for"):
		bodies = warfare.bodies_for(side, shooter)
	var last_v := VoxelWorld.to_voxel(from)
	for i in range(1, steps + 1):
		var p := from + dir * (dist * float(i) / float(steps))
		var v := VoxelWorld.to_voxel(p)
		if v != last_v and world != null and world.is_solid(v):
			return {"at": from + dir * (dist * float(i - 1) / float(steps)),
				"voxel": v, "normal": _normal_between(last_v, v)}
		last_v = v
		for b: Node3D in bodies:
			if not is_instance_valid(b):
				continue
			var c := b.global_position + Vector3(0.0, 0.9, 0.0)
			if c.distance_squared_to(p) < HIT_RADIUS * HIT_RADIUS:
				return {"at": p, "body": b}
	return {}


## The face crossed going from one voxel to its neighbour, as an outward
## normal. Enough for a bounce; a grenade does not need the true surface.
static func _normal_between(a: Vector3i, b: Vector3i) -> Vector3:
	var d := b - a
	if absi(d.y) >= absi(d.x) and absi(d.y) >= absi(d.z):
		return Vector3(0.0, -signf(d.y), 0.0)
	if absi(d.x) >= absi(d.z):
		return Vector3(-signf(d.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, -signf(d.z))


func _bounce(n: Vector3) -> void:
	velocity = velocity.bounce(n) * 0.42
	# Rolling to a stop: once it is barely moving on the ground it lies there
	# until the fuse does the rest.
	if n.y > 0.5 and velocity.length() < 1.2:
		velocity = Vector3.ZERO
		_resting = true


## A bullet takes a chip out of soft material where it lands. Stone and steel
## are left alone; this is a mark, not a demolition.
func _chip(v: Vector3i) -> void:
	if world == null:
		return
	var id := world.get_voxel(v)
	if id in [VoxelTypes.DIRT, VoxelTypes.GRASS, VoxelTypes.SAND, VoxelTypes.THATCH,
			VoxelTypes.LEAF, VoxelTypes.FARMLAND]:
		if randf() < 0.35:
			world.set_voxel(v, VoxelTypes.AIR)


## Off the rail slowly, then the motor lights and it goes. Steering is a turn
## toward the target capped at a rate, which is what gives a rocket that
## slightly-too-late curve as it chases something moving.
func _rocket(delta: float) -> void:
	if not _lit and _t > 0.25:
		_lit = true
	if _lit:
		var want_dir := velocity.normalized()
		var aim := target_point
		if target != null and is_instance_valid(target):
			aim = target.global_position + Vector3(0.0, 0.9, 0.0)
		if aim != Vector3.INF:
			var to := (aim - global_position).normalized()
			var max_turn := 1.7 * delta
			var ang := want_dir.angle_to(to)
			if ang > 0.0001:
				var axis := want_dir.cross(to).normalized()
				want_dir = want_dir.rotated(axis, minf(ang, max_turn))
		var speed := minf(velocity.length() + 70.0 * delta, 62.0)
		velocity = want_dir * speed
		_smoke -= delta
		if _smoke <= 0.0 and warfare != null and warfare.has_method("puff"):
			_smoke = 0.045
			warfare.puff(global_position - velocity.normalized() * 0.3)
	else:
		velocity.y -= GRAVITY * 0.6 * delta


func _explode() -> void:
	if blast_r > 0.0 and warfare != null and warfare.has_method("detonate"):
		warfare.detonate(global_position, blast_r, blast_power, side, shooter)
	queue_free()
