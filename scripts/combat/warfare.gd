extends Node3D
class_name Warfare
## The army, the enemy, and everything in the air between them.
##
## One manager for the whole of fighting, because every part of it needs to
## know about every other: a projectile needs the list of bodies it might hit,
## a soldier needs the nearest raider, a raider needs the nearest building, a
## blast needs everyone within reach, and all of them need the stores — a
## soldier's rifle is loaded from the same pile of shot the player's is.
##
## The town does not start at war. Nothing hostile exists until there is
## something worth taking — an armoury or a barracks — and from then on a raid
## comes every couple of days at first light. In between, the orders are the
## player's: recruit, make, arm, defend, attack. All through the text field,
## like everything else, except for pulling the trigger: a gun you can only
## fire by typing "fire" is not a gun, so that one is a key.

signal status(text: String)
signal raid_began(count: int)
signal raid_over(won: bool)

const RECRUIT_COST := 150
const RAID_EVERY_DAYS := 2
const MAX_PROJECTILES := 64
const MAX_PUFFS := 90

var world: VoxelWorld
var nav: NavGrid
var town: Town
var village: Village
var clock: GameClock
var player: Node3D
var crew: Crew
var livestock: Livestock
var wildlife: Wildlife

var soldiers: Array[Fighter] = []
var raiders: Array[Fighter] = []
var projectiles: Array[Projectile] = []
var _puffs: Array[Node3D] = []

## What the player has taken from the stores to carry, and which is in hand.
var player_weapons: Array[String] = []
var player_weapon_i := -1
var player_reload := 0.0
var player_health := 100.0

var _next_raid_day := -1
var _raid_active := false
var shots_fired := 0
var hits_landed := 0
var blasts := 0
var raiders_fallen := 0
var soldiers_fallen := 0


func setup(w: VoxelWorld, n: NavGrid, t: Town, v: Village, c: GameClock, p: Node3D,
		cr: Crew, ls: Livestock, wl: Wildlife) -> void:
	world = w
	nav = n
	town = t
	village = v
	clock = c
	player = p
	crew = cr
	livestock = ls
	wildlife = wl
	set_process(true)


func _process(delta: float) -> void:
	player_reload = maxf(player_reload - delta, 0.0)
	if player_health < 100.0:
		player_health = minf(player_health + 1.5 * delta, 100.0)
	_prune()
	_tick_raids()


func _prune() -> void:
	var live_s: Array[Fighter] = []
	for s: Fighter in soldiers:
		if is_instance_valid(s) and not s.is_dead():
			live_s.append(s)
	soldiers = live_s
	var live_r: Array[Fighter] = []
	for r: Fighter in raiders:
		if is_instance_valid(r) and not r.is_dead():
			live_r.append(r)
	if _raid_active and live_r.is_empty() and not raiders.is_empty():
		_raid_active = false
		status.emit("The raid is beaten off.")
		raid_over.emit(true)
	raiders = live_r
	var live_p: Array[Projectile] = []
	for pr: Projectile in projectiles:
		if is_instance_valid(pr):
			live_p.append(pr)
	projectiles = live_p


# ----------------------------------------------------------- what is where

## The buildings the fight is about.
func _has(archetype: String) -> Dictionary:
	if town == null:
		return {}
	for rec: Dictionary in town.buildings:
		if str(rec["archetype"]) == archetype:
			return rec
	return {}


## Where a person stands to use a building: in front of its door.
func stand_at(rec: Dictionary) -> Vector3:
	var patch: VoxelPatch = rec.get("patch", null)
	if patch == null:
		return Vector3.INF
	var fr := patch.footprint
	var v := VoxelChunk.VOXEL_M
	var centre := Vector3((fr.position.x + fr.size.x * 0.5) * v, 0.0,
		(fr.position.y + fr.size.y * 0.5) * v)
	var front: Vector3i = patch.front
	var half := (fr.size.x if absi(front.x) > 0 else fr.size.y) * v * 0.5
	var at := centre + Vector3(front) * (half + 2.2)
	at.y = world.ground_m(at.x, at.z)
	return at


func armoury_stand() -> Vector3:
	var rec := _has("armoury")
	return stand_at(rec) if not rec.is_empty() else Vector3.INF


func barracks_stand() -> Vector3:
	var rec := _has("barracks")
	return stand_at(rec) if not rec.is_empty() else Vector3.INF


## The nearest standing building to a point, for a raider to go and break.
func nearest_building(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for rec: Dictionary in town.buildings:
		var at := stand_at(rec)
		if at == Vector3.INF:
			continue
		var d := at.distance_to(from)
		if d < best_d:
			best_d = d
			best = {"at": at, "rec": rec}
	return best


## Everything one side's shots can hit. "" means everyone, for a blast.
func bodies_for(side: String, shooter: Node3D) -> Array:
	var out: Array = []
	if side != "town":
		for s: Fighter in soldiers:
			if s != shooter:
				out.append(s)
		if side == "raider" or side == "":
			if crew != null:
				for w: Worker in crew.workers:
					out.append(w)
			if player != null:
				out.append(player)
			if livestock != null:
				for a: Animal in livestock.animals:
					if is_instance_valid(a):
						out.append(a)
			if wildlife != null:
				for a: Animal in wildlife.beasts:
					if is_instance_valid(a):
						out.append(a)
	if side != "raider":
		for r: Fighter in raiders:
			if r != shooter:
				out.append(r)
		if side == "town" and shooter == player:
			# The player can hit the animals too. That is what a gun is.
			if livestock != null:
				for a: Animal in livestock.animals:
					if is_instance_valid(a):
						out.append(a)
			if wildlife != null:
				for a: Animal in wildlife.beasts:
					if is_instance_valid(a):
						out.append(a)
	return out


func nearest_enemy(f: Fighter, within: float) -> Node3D:
	var pool: Array = raiders if f.side == "town" else soldiers
	var best: Node3D = null
	var best_d := within
	for e: Fighter in pool:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var d := e.global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = e
	# A raider with no soldier to fight will take the player.
	if best == null and f.side == "raider" and player != null:
		var dp := player.global_position.distance_to(f.global_position)
		if dp < within:
			best = player
	return best


# ------------------------------------------------------------------ firing

## Whether the shooter has anything to fire. Soldiers and the player draw on
## the stores; a raider has what he came with.
func can_fire(who: Node3D) -> bool:
	var weapon := _weapon_of(who)
	var spec := Arsenal.weapon(weapon)
	if spec.is_empty():
		return false
	if who is Fighter and (who as Fighter).side == "raider":
		return (who as Fighter).ammo > 0
	return town.units_of(str(spec["ammo"])) > 0


func _weapon_of(who: Node3D) -> String:
	if who is Fighter:
		return (who as Fighter).weapon
	if who == player:
		return player_weapon()
	return ""


## One shot, from a muzzle toward a point. Returns false if there was nothing
## to fire it with.
func fire(who: Node3D, weapon: String, from: Vector3, aim: Vector3, target: Node3D = null) -> bool:
	var spec := Arsenal.weapon(weapon)
	if spec.is_empty() or not can_fire(who):
		return false
	if projectiles.size() >= MAX_PROJECTILES:
		return false
	var side := "town"
	if who is Fighter:
		side = (who as Fighter).side
		if side == "raider":
			(who as Fighter).ammo -= 1
	if side == "town":
		town.stock[str(spec["ammo"])] = town.units_of(str(spec["ammo"])) - 1

	var dir := (aim - from).normalized()
	# A lob for the things that arc: aim up so gravity brings it down there.
	var kind := str(spec["projectile"])
	var speed := float(spec["speed"])
	if kind == "shell" or kind == "grenade":
		dir = _lob(from, aim, speed)
	# Spread, in degrees, as a cone.
	var spread := deg_to_rad(float(spec.get("spread", 1.0)))
	if spread > 0.0:
		var axis := dir.cross(Vector3.UP).normalized()
		if axis.length_squared() < 0.001:
			axis = Vector3.RIGHT
		dir = dir.rotated(axis, randf_range(-spread, spread))
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))

	var p := Projectile.new()
	add_child(p)
	p.setup(world, self, from, dir * speed, spec, who, side)
	if kind == "rocket":
		p.target = target
		p.target_point = aim
	projectiles.append(p)
	shots_fired += 1
	return true


## The launch direction that lands a ballistic thing roughly on the target.
## Solved for the high-ish arc a mortar uses, falling back to a 40 degree
## throw when the target is out of reach.
func _lob(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	var h := to.y - from.y
	var g := Projectile.GRAVITY
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * dist * dist + 2.0 * h * v2)
	var ang := deg_to_rad(40.0)
	if disc >= 0.0 and dist > 0.01:
		# The lower of the two solutions: flatter, faster, less time to miss.
		ang = atan((v2 - sqrt(disc)) / (g * dist))
		ang = maxf(ang, deg_to_rad(12.0))
	var fd := flat.normalized() if dist > 0.01 else Vector3.FORWARD
	return (fd * cos(ang) + Vector3.UP * sin(ang)).normalized()


func note_hit(_p: Projectile, _body: Node3D) -> void:
	hits_landed += 1


func detonate(at: Vector3, radius: float, power: float, side: String, shooter: Node3D) -> void:
	blasts += 1
	Blast.detonate(self, world, nav, at, radius, power, side, shooter)


## Rocket smoke: a small grey cube that swells and fades. Capped, so a volley
## of rockets does not become a thousand nodes.
func puff(at: Vector3) -> void:
	if _puffs.size() >= MAX_PUFFS:
		var old: Node3D = _puffs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var mi := BoxKit.add(n, Vector3(-0.08, -0.08, -0.08), Vector3(0.16, 0.16, 0.16),
		Color("#9a9a96"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var e := Blast.Effect.new()
	e.kind = "flash"
	e.life = 1.1
	e.grow = 2.2
	n.add_child(e)
	_puffs.append(n)


## Camera shake, scaled by how close the player was.
func shake(at: Vector3, radius: float, power: float) -> void:
	if player == null or not player.has_method("kick"):
		return
	var d := player.global_position.distance_to(at)
	var k := clampf(1.0 - d / (radius * 6.0), 0.0, 1.0)
	if k > 0.0:
		player.kick(k * clampf(power / 100.0, 0.4, 1.6))


# ------------------------------------------------------------------ the army

## Puts soldiers on: costs coin, needs a barracks, arms them with whatever
## the stores can spare. Returns {ok, line, made}.
func recruit(n: int) -> Dictionary:
	var at := barracks_stand()
	if at == Vector3.INF:
		return {"ok": false, "line": "There is no barracks. Build one first, and I will find the men.", "made": 0}
	var made := 0
	for i in n:
		if town.coins < RECRUIT_COST:
			break
		town.coins -= RECRUIT_COST
		var s := Fighter.new()
		s.name = "soldier_%d" % soldiers.size()
		add_child(s)
		var spot := at + Vector3(randf_range(-2.0, 2.0), 0.2, randf_range(-1.0, 1.0))
		spot.y = world.ground_m(spot.x, spot.z) + 0.2
		s.setup("town", world, nav, self, spot, _draw_weapon())
		s.died.connect(_on_soldier_died)
		soldiers.append(s)
		made += 1
	if made == 0:
		return {"ok": false, "line": "Soldiers cost %d coins apiece and the purse will not stand one." % RECRUIT_COST, "made": 0}
	var armed := 0
	for s: Fighter in soldiers:
		if s.weapon != "":
			armed += 1
	var line := "%d %s signed on at the barracks" % [made, "soldier" if made == 1 else "soldiers"]
	line += ", %d of the company armed." % armed if armed < soldiers.size() \
		else ", and every one of them has a gun."
	return {"ok": true, "line": line, "made": made}


## The best gun the stores can spare, taken out of them.
func _draw_weapon() -> String:
	for w: String in ["rifle", "musket", "pistol", "grenade"]:
		if town.units_of(w) > 0:
			town.stock[w] = town.units_of(w) - 1
			return w
	return ""


func _on_soldier_died(_s: Fighter) -> void:
	soldiers_fallen += 1
	status.emit("A soldier is down.")


func _on_raider_died(_r: Fighter) -> void:
	raiders_fallen += 1


## Hands a weapon to every soldier who has not got one, or swaps them all to
## this kind if it is named. Returns {ok, line}.
func arm_soldiers(kind: String) -> Dictionary:
	if soldiers.is_empty():
		return {"ok": false, "line": "There are no soldiers to arm."}
	var given := 0
	for s: Fighter in soldiers:
		if s.weapon == kind:
			continue
		if town.units_of(kind) <= 0:
			break
		if s.weapon != "":
			town.stock[s.weapon] = town.units_of(s.weapon) + 1
		town.stock[kind] = town.units_of(kind) - 1
		s.arm(kind)
		given += 1
	if given == 0:
		return {"ok": false, "line": "There is not a %s in the stores to hand out." % Arsenal.label(kind)}
	return {"ok": true, "line": "%d of them now carry a %s." % [given, Arsenal.label(kind)]}


## Everybody to a point, and hold it.
func defend(at: Vector3) -> Dictionary:
	if soldiers.is_empty():
		return {"ok": false, "line": "There is nobody to send."}
	var i := 0
	for s: Fighter in soldiers:
		var spot := at + Vector3(cos(i * 1.1) * 2.5, 0.0, sin(i * 1.1) * 2.5)
		spot.y = world.ground_m(spot.x, spot.z)
		s.march(spot)
		i += 1
	return {"ok": true, "line": "The company is moving to hold it."}


## Everybody at the nearest raiders.
func attack() -> Dictionary:
	if soldiers.is_empty():
		return {"ok": false, "line": "There is nobody to send."}
	if raiders.is_empty():
		return {"ok": false, "line": "There is nobody to attack. The town is quiet."}
	for s: Fighter in soldiers:
		var t := nearest_enemy(s, 400.0)
		if t != null:
			s.attack(t)
	return {"ok": true, "line": "They are going in."}


# --------------------------------------------------------------- the enemy

## A raid: a party at the edge of what is loaded, coming for the town.
##
## Placed relative to the player, not the well. The world only exists around
## the player, and a raider stood on a column whose neighbours have not
## streamed in cannot be given a floor — the first version of this put them a
## hundred metres from the well, which was sometimes the edge of the world,
## and they fell through it before firing a shot.
func raid(count: int) -> void:
	var anchor := player.global_position if player != null else village.well_pos
	var ang := randf() * TAU
	if player != null:
		# From the side the player is facing away from, so they arrive rather
		# than appear in front of the camera.
		var fwd := -player.global_transform.basis.z
		ang = atan2(-fwd.x, -fwd.z) + randf_range(-0.7, 0.7)
	var origin := Vector3.INF
	for turn in 6:
		var a := ang + turn * (PI / 3.0)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var far := Vector3.INF
		for reach in range(30, 66, 4):
			var p := anchor + dir * float(reach)
			var v := VoxelWorld.to_voxel(p)
			if not world.column_meshable(v.x >> 5, v.z >> 5):
				break
			var h := world.height_at(v.x, v.z)
			if h <= 0 or world.get_voxel(Vector3i(v.x, h, v.z)) == VoxelTypes.WATER:
				break
			far = p
		if far != Vector3.INF and far.distance_to(anchor) >= 30.0:
			origin = far
			ang = a
			break
	if origin == Vector3.INF:
		status.emit("The raiders turned back at the edge of the valley.")
		return
	for i in count:
		var r := Fighter.new()
		r.name = "raider_%d" % raiders.size()
		add_child(r)
		var spot := origin + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		spot.y = world.ground_m(spot.x, spot.z) + 0.3
		var roll := randf()
		var arm := "musket" if roll < 0.6 else ("grenade" if roll < 0.85 else "")
		r.setup("raider", world, nav, self, spot, arm)
		r.ammo = 14 if arm == "musket" else (4 if arm == "grenade" else 0)
		r.died.connect(_on_raider_died)
		r.march(village.well_pos)
		raiders.append(r)
	_raid_active = true
	status.emit("Raiders! %d of them, from the %s." % [count, _compass(ang)])
	raid_began.emit(count)


func _compass(ang: float) -> String:
	var names := ["north", "north-east", "east", "south-east", "south",
		"south-west", "west", "north-west"]
	var idx := roundi(ang / (PI / 4.0))
	return names[((idx % 8) + 8) % 8]


## Raids start once the town has something worth taking, and come every
## couple of days at first light after that.
func _tick_raids() -> void:
	if clock == null or town == null:
		return
	var worth := not _has("armoury").is_empty() or not _has("barracks").is_empty()
	if not worth:
		return
	if _next_raid_day < 0:
		_next_raid_day = clock.day + 1
		status.emit("With an armoury in it the town is worth raiding. Expect company.")
		return
	if _raid_active or clock.day < _next_raid_day or clock.hour < 5.5 or clock.hour > 7.5:
		return
	_next_raid_day = clock.day + RAID_EVERY_DAYS
	raid(2 + town.buildings.size() / 3 + soldiers.size() / 3)


# -------------------------------------------------------------- the player

func player_weapon() -> String:
	if player_weapon_i < 0 or player_weapon_i >= player_weapons.size():
		return ""
	return player_weapons[player_weapon_i]


## Takes one from the stores to carry. Returns {ok, line}.
func arm_player(kind: String) -> Dictionary:
	if not Arsenal.is_weapon(kind):
		return {"ok": false, "line": "That is not something you can carry."}
	if kind in player_weapons:
		player_weapon_i = player_weapons.find(kind)
		return {"ok": true, "line": "You have it already — it is in your hands."}
	if town.units_of(kind) <= 0:
		return {"ok": false, "line": "There is not a %s in the stores. Have one made." % Arsenal.label(kind)}
	town.stock[kind] = town.units_of(kind) - 1
	player_weapons.append(kind)
	player_weapon_i = player_weapons.size() - 1
	return {"ok": true, "line": "Here. Left button fires it; Q swaps it for the next."}


func player_swap() -> void:
	if player_weapons.is_empty():
		return
	player_weapon_i = (player_weapon_i + 1) % player_weapons.size()


## Fires whatever the player is holding, from the camera, at what it is
## looking at.
func player_fire() -> bool:
	var weapon := player_weapon()
	if weapon == "" or player_reload > 0.0 or player == null:
		return false
	var spec := Arsenal.weapon(weapon)
	if not can_fire(player):
		status.emit("No %s left." % str(spec["ammo"]))
		return false
	var cam: Camera3D = player.get("camera")
	if cam == null:
		return false
	var origin: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var from := origin + fwd * 0.5 + Vector3(0.0, -0.12, 0.0)
	var aim := origin + fwd * float(spec.get("range", 60.0))
	# Aim at the surface in the crosshair if there is one nearer than that.
	var hit := _ray_world(origin, fwd, float(spec.get("range", 60.0)))
	if hit != Vector3.INF:
		aim = hit
	if fire(player, weapon, from, aim, null):
		player_reload = float(spec.get("reload", 1.0))
		if player.has_method("kick"):
			player.kick(0.25 if str(spec["projectile"]) == "bullet" else 0.6)
		return true
	return false


func _ray_world(from: Vector3, dir: Vector3, reach: float) -> Vector3:
	var steps := int(reach / 0.25)
	for i in range(1, steps + 1):
		var p := from + dir * (i * 0.25)
		if world.is_solid(VoxelWorld.to_voxel(p)):
			return p
	return Vector3.INF


## Damage to the player, from the outside.
func hurt_player(dmg: float) -> void:
	player_health -= dmg
	if player.has_method("kick"):
		player.kick(0.5)
	if player_health <= 0.0:
		player_health = 100.0
		status.emit("You were knocked down. You come to by the well.")
		if player.has_method("teleport"):
			player.teleport(village.spawn_pos + Vector3(0, 1.0, 0), PI)


## For the HUD: what is in hand and what is left to fire.
func player_status() -> String:
	var weapon := player_weapon()
	if weapon == "":
		return ""
	var spec := Arsenal.weapon(weapon)
	var ammo := str(spec["ammo"])
	var n := town.units_of(ammo)
	var s := "%s   %d %s" % [Arsenal.label(weapon), n, Arsenal.label(ammo)]
	if player_reload > 0.0:
		s += "   reloading"
	if player_weapons.size() > 1:
		s += "   [Q] %s" % Arsenal.label(player_weapons[(player_weapon_i + 1) % player_weapons.size()])
	return s


# ---------------------------------------------------------------- crafting

## What is short for a batch of something, or empty if it can be made.
func short_for(item: String, batches: int) -> Dictionary:
	return Resources.shortfall(Arsenal.bill(item, batches), town.stock)


## Takes the materials and returns the job for a worker to carry out. The
## finished goods land in the stores when the job completes.
func start_craft(item: String, count: int) -> CraftJob:
	var batches := Arsenal.batches_for(item, count)
	town.spend(Arsenal.bill(item, batches))
	var job := CraftJob.new()
	job.item = item
	job.batches = batches
	job.total_hours = float(Arsenal.item(item)["hours"]) * batches
	job.hours_left = job.total_hours
	job.town = town
	return job


## Straight into the stores, for tests and for the cases where nobody has to
## walk anywhere.
func craft_now(item: String, count: int) -> int:
	var batches := Arsenal.batches_for(item, count)
	town.spend(Arsenal.bill(item, batches))
	var made := batches * int(Arsenal.item(item)["batch"])
	town.stock[item] = town.units_of(item) + made
	return made


func army_line() -> String:
	if soldiers.is_empty():
		return "There is no army. Build a barracks and say \"recruit some soldiers\"."
	var armed := 0
	var kinds := {}
	for s: Fighter in soldiers:
		if s.weapon != "":
			armed += 1
			kinds[s.weapon] = int(kinds.get(s.weapon, 0)) + 1
	var parts: Array[String] = []
	for k: String in kinds:
		parts.append("%d with a %s" % [int(kinds[k]), Arsenal.label(k)])
	var out := "%d soldiers, %d of them armed" % [soldiers.size(), armed]
	if not parts.is_empty():
		out += " — " + ", ".join(parts)
	if not raiders.is_empty():
		out += ". %d raiders about." % raiders.size()
	return out + "."
