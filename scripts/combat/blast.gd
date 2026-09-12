extends RefCounted
class_name Blast
## An explosion: a crater, a shove, a flash and some flying dirt.
##
## The crater is the part that makes it real. The world is voxels, so a blast
## of radius r simply removes every voxel closer than r to the point, with a
## ragged edge so it is a hole and not a sphere. Buildings are voxels too, so a
## shell into a wall takes the wall out, and the nav grid is told so the crew
## stop trying to walk through the gap the way they would through a door.
##
## Water is left alone (a hole in the sea fills itself in an instant) and so
## is the bottom of the world.

const DEBRIS := 9
const FLASH_LIFE := 0.32


## Everything an explosion does, in order: the hole, the hurt, the show.
static func detonate(warfare: Node, world: VoxelWorld, nav: NavGrid, at: Vector3,
		radius: float, power: float, side: String, shooter: Node3D) -> void:
	_crater(world, nav, at, radius)
	_hurt(warfare, at, radius, power, side, shooter)
	_show(warfare, at, radius)
	if warfare.has_method("shake"):
		warfare.shake(at, radius, power)


static func _crater(world: VoxelWorld, nav: NavGrid, at: Vector3, radius: float) -> void:
	var c := VoxelWorld.to_voxel(at)
	var r_v := int(ceil(radius / VoxelChunk.VOXEL_M))
	var r2 := radius * radius
	var lo_y := 3
	for dy in range(-r_v, r_v + 1):
		var y := c.y + dy
		if y < lo_y or y >= world.voxel_height():
			continue
		for dz in range(-r_v, r_v + 1):
			for dx in range(-r_v, r_v + 1):
				var v := Vector3i(c.x + dx, y, c.z + dz)
				var p := VoxelWorld.centre_metres(v)
				var d2 := p.distance_squared_to(at)
				if d2 > r2:
					continue
				# Ragged: the last fifth of the radius only sometimes goes.
				if d2 > r2 * 0.64 and randf() < 0.4:
					continue
				var id := world.get_voxel(v)
				if id == VoxelTypes.AIR or id == VoxelTypes.WATER:
					continue
				world.set_voxel(v, VoxelTypes.AIR)
	if nav != null:
		nav.refresh_world_rect(Rect2i(c.x - r_v, c.z - r_v, r_v * 2 + 1, r_v * 2 + 1), 2)


static func _hurt(warfare: Node, at: Vector3, radius: float, power: float,
		side: String, shooter: Node3D) -> void:
	if not warfare.has_method("bodies_for"):
		return
	# Everyone, including the side that threw it: a grenade does not check.
	for b: Node3D in warfare.bodies_for("", null):
		if not is_instance_valid(b):
			continue
		var c := b.global_position + Vector3(0.0, 0.9, 0.0)
		var d := c.distance_to(at)
		var reach := radius * 1.25
		if d > reach:
			continue
		var f := 1.0 - d / reach
		var dmg := power * f * f
		if b.has_method("take_hit"):
			b.take_hit(dmg, at, shooter)
		# The shove. A character body is thrown back and up in proportion.
		if b is CharacterBody3D:
			var away := (c - at)
			away.y = maxf(away.y, 0.3)
			(b as CharacterBody3D).velocity += away.normalized() * (4.0 + 8.0 * f)


## A flash that swells and fades, and a handful of clods thrown out of the
## hole. All hand-moved Node3Ds; there is nothing here worth a particle system.
static func _show(warfare: Node, at: Vector3, radius: float) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	flash.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#ffb347")
	m.emission_enabled = true
	m.emission = Color("#ff7a1a")
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = m
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warfare.add_child(flash)
	flash.global_position = at
	var e := Effect.new()
	e.kind = "flash"
	e.life = FLASH_LIFE
	e.grow = radius * 2.0
	flash.add_child(e)

	for i in DEBRIS:
		var clod := Node3D.new()
		warfare.add_child(clod)
		clod.global_position = at + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
		var s := randf_range(0.12, 0.3)
		BoxKit.add(clod, Vector3(-s * 0.5, -s * 0.5, -s * 0.5), Vector3(s, s, s),
			Color("#5a4a36").lerp(Color("#8a7a62"), randf()))
		var d := Effect.new()
		d.kind = "debris"
		d.life = randf_range(1.0, 1.8)
		d.velocity = Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized() \
			* randf_range(5.0, 11.0) * clampf(radius / 4.0, 0.6, 1.5)
		d.spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		clod.add_child(d)


## The little bit of motion an explosion leaves behind. Attached under the
## thing it moves; removes both when done.
class Effect extends Node:
	var kind := "flash"
	var life := 1.0
	var grow := 1.0
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var _t := 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		var host := get_parent() as Node3D
		if host == null or _t >= life:
			if host != null:
				host.queue_free()
			return
		var k := _t / life
		match kind:
			"flash":
				var s := 0.5 + grow * (1.0 - pow(1.0 - k, 3.0))
				host.scale = Vector3(s, s, s)
				var mi := host as MeshInstance3D
				if mi != null and mi.material_override != null:
					var m := mi.material_override as StandardMaterial3D
					m.albedo_color.a = 1.0 - k
					m.emission_energy_multiplier = 3.0 * (1.0 - k)
			"debris":
				velocity.y -= 22.0 * delta
				host.global_position += velocity * delta
				host.rotation += spin * delta
				if k > 0.7:
					host.scale = Vector3.ONE * (1.0 - (k - 0.7) / 0.3)
