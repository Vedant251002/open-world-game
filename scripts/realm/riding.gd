extends Node
## Horses: bought, stabled, ridden by the player, lent to the workers.
##
## A horse is a livestock animal like a hen, until somebody gets on it. Then
## it is the thing carrying the player: parked under them every physics
## tick, legs swinging with their speed, its own wandering switched off, and
## the player's walk scaled up to a canter with the eyes lifted to where a
## rider's are. Get off, and it is a horse again where you left it.
##
## Workers borrow horses the same way for long errands — a horse under a
## worker is just a worker who walks faster and looks the part — and a cart
## hitched behind the rider is a few boxes that follow at a rope's length.

const MOUNT_REACH := 2.6
const RIDE_SPEED := 2.2
const RIDE_EYE := 1.0
const HORSE_PRICE := 300
const SADDLE_Y := 1.1
const CART_CAPACITY := 200

var realm: Realm
var mount: Animal = null            ## the horse under the player
var _lent: Dictionary = {}          ## worker_id -> Animal
var cart: Node3D = null
var _t := 0.0
var _hint_near: Animal = null
var _was_in_water := false


func setup(r: Realm) -> void:
	realm = r


# ------------------------------------------------------------------- horses

func horses() -> Array[Animal]:
	var out: Array[Animal] = []
	if realm.livestock == null:
		return out
	for a: Animal in realm.livestock.animals:
		if is_instance_valid(a) and a.kind == "horse":
			out.append(a)
	return out


func free_horse(near: Vector3) -> Animal:
	var best: Animal = null
	var best_d := 1e9
	for h: Animal in horses():
		if h == mount or _lent.values().has(h):
			continue
		var d := h.global_position.distance_to(near)
		if d < best_d:
			best = h
			best_d = d
	return best


func has_stable() -> bool:
	return not realm.building("stable").is_empty()


func has_cart() -> bool:
	return cart != null


func cart_capacity() -> int:
	return CART_CAPACITY if has_cart() else 0


# ----------------------------------------------------------------- mounting

func mount_horse(h: Animal) -> bool:
	if h == null or not is_instance_valid(h) or mount != null or realm.player == null:
		return false
	mount = h
	_seat(h)
	realm.player.set("speed_scale", RIDE_SPEED)
	realm.player.set("eye_offset", RIDE_EYE)
	realm.player.set("mount", h)
	realm.say("Mounted.")
	return true


func dismount() -> void:
	if mount == null:
		return
	if is_instance_valid(mount):
		_unseat(mount, realm.player.global_position + Vector3(1.2, 0.0, 0.0))
	mount = null
	realm.player.set("speed_scale", 1.0)
	realm.player.set("eye_offset", 0.0)
	realm.player.set("mount", null)
	realm.say("Dismounted.")


func _seat(h: Animal) -> void:
	h.set_physics_process(false)
	h.collision_layer = 0
	h.collision_mask = 0
	h.velocity = Vector3.ZERO


func _unseat(h: Animal, at: Vector3) -> void:
	at.y = realm.world.ground_m(at.x, at.z) + 0.3
	h.global_position = at
	h.home = at
	h.collision_mask = 1
	h.set_physics_process(true)


## A worker takes a horse for the errand they are on; it comes back when the
## errand ends. Other systems call this before a long walk.
func lend(worker: Worker) -> bool:
	if worker == null or _lent.has(worker.memory.worker_id):
		return false
	var h := free_horse(worker.global_position)
	if h == null:
		return false
	_lent[worker.memory.worker_id] = h
	_seat(h)
	return true


func _return_lent(worker_id: String) -> void:
	var h: Animal = _lent.get(worker_id)
	_lent.erase(worker_id)
	var w: Worker = realm.crew.get_worker(worker_id) if realm.crew != null else null
	if h != null and is_instance_valid(h):
		_unseat(h, w.global_position + Vector3(1.5, 0.0, 0.0) if w != null else realm.village.well_pos)


# --------------------------------------------------------------------- cart

func hitch_cart() -> void:
	if cart != null or realm.props_root == null:
		return
	cart = Node3D.new()
	cart.name = "Cart"
	realm.props_root.add_child(cart)
	var wood := Color("#7a5a3a")
	var dark := Color("#3a2c20")
	BoxKit.add(cart, Vector3(-0.7, 0.55, -1.0), Vector3(1.4, 0.12, 2.0), wood)       # bed
	BoxKit.add(cart, Vector3(-0.7, 0.67, -1.0), Vector3(0.08, 0.45, 2.0), wood)      # sides
	BoxKit.add(cart, Vector3(0.62, 0.67, -1.0), Vector3(0.08, 0.45, 2.0), wood)
	BoxKit.add(cart, Vector3(-0.7, 0.67, -1.0), Vector3(1.4, 0.45, 0.08), wood)      # tailboard
	BoxKit.add(cart, Vector3(-0.9, 0.0, -0.35), Vector3(0.12, 0.9, 0.9), dark)       # wheels
	BoxKit.add(cart, Vector3(0.78, 0.0, -0.35), Vector3(0.12, 0.9, 0.9), dark)
	BoxKit.add(cart, Vector3(-0.45, 0.5, 1.0), Vector3(0.08, 0.08, 1.3), wood)       # shafts
	BoxKit.add(cart, Vector3(0.37, 0.5, 1.0), Vector3(0.08, 0.08, 1.3), wood)
	for child in cart.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visibility_range_end = 100.0
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p := realm.player.global_position
	cart.global_position = Vector3(p.x, realm.world.ground_m(p.x, p.z), p.z) - Vector3(0, 0, 2.5)


func unhitch_cart() -> void:
	if cart != null:
		cart.queue_free()
		cart = null


# --------------------------------------------------------------------- tick

func tick(delta: float) -> void:
	var player := realm.player
	if player == null:
		return
	if mount != null:
		if not is_instance_valid(mount):
			mount = null
			player.set("speed_scale", 1.0)
			player.set("eye_offset", 0.0)
		else:
			var p := player.global_position
			mount.global_position = Vector3(p.x, p.y - SADDLE_Y + 0.9, p.z)
			mount.rotation.y = player.yaw + PI
			var planar := Vector2(player.velocity.x, player.velocity.z).length()
			mount.call("_animate", delta, planar * 0.5)
			if bool(player.get("in_water")) and not _was_in_water:
				dismount()
			_was_in_water = bool(player.get("in_water"))
	# Lent horses follow their riders; returned when the errand is done.
	for wid: String in _lent.keys():
		var w: Worker = realm.crew.get_worker(wid)
		var h: Animal = _lent[wid]
		if w == null or not is_instance_valid(w) or w.job_errand.is_empty() or not is_instance_valid(h):
			_return_lent(wid)
			continue
		var wp := w.global_position
		h.global_position = Vector3(wp.x, wp.y - 0.1, wp.z)
		h.rotation.y = w.rotation.y + PI
		h.call("_animate", delta, Vector2(w.velocity.x, w.velocity.z).length() * 0.5)
	if cart != null:
		var target := player.global_position - Vector3(sin(player.yaw), 0.0, cos(player.yaw)) * -2.6
		target.y = realm.world.ground_m(target.x, target.z)
		cart.global_position = cart.global_position.lerp(target, minf(delta * 4.0, 1.0))
		cart.rotation.y = lerp_angle(cart.rotation.y, player.yaw, minf(delta * 4.0, 1.0))
	# [E] near a horse: on or off. The press is checked every frame (it is
	# true for one frame only); the nearest-horse scan for the hint is not.
	if Input.is_action_just_pressed("talk"):
		if mount != null:
			dismount()
			return
		if player.has_method("looked_at_worker") and player.call("looked_at_worker") is Worker:
			return
		var h2 := free_horse(player.global_position)
		if h2 != null and h2.global_position.distance_to(player.global_position) <= MOUNT_REACH:
			mount_horse(h2)
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	_hint(player)


func _hint(player: Node3D) -> void:
	if mount != null:
		return
	var h := free_horse(player.global_position)
	if h != null and h.global_position.distance_to(player.global_position) <= MOUNT_REACH:
		if _hint_near != h:
			_hint_near = h
			realm.say("[E] mount the horse")
	else:
		_hint_near = null


func on_hour(_hour: float, _day: int) -> void:
	for wid: String in _lent.keys():
		var w: Worker = realm.crew.get_worker(wid)
		if w == null or w.job_errand.is_empty():
			_return_lent(wid)


# ------------------------------------------------------------------ talking

func verbs() -> Dictionary:
	return {
		"hitch_cart": {
			"says": "hitch the cart to a horse so it follows your employer",
			"instant": true,
		},
		"unhitch_cart": {
			"says": "leave the cart where it stands",
			"instant": true,
		},
		"buy_horse": {
			"says": "buy one or more horses for the stable",
			"optional": ["count"],
			"types": {"count": "int"},
		},
		"sell_horse": {
			"says": "sell a horse",
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"unhitch_cart":
			unhitch_cart()
			worker.speak("The cart stays here.")
			return "done"
		"hitch_cart":
			if horses().is_empty():
				return "There is no horse to pull it. Buy one first."
			hitch_cart()
			worker.speak("Cart's hitched. It will follow you.")
			realm.note("riding", "A cart was hitched.")
			return "done"
		"buy_horse":
			if not has_stable():
				return "We have nowhere to keep a horse. Build a stable and I will find one."
			var price := HORSE_PRICE
			var mk: Node = realm.system("Market")
			if mk != null and mk.has_method("buy_price"):
				price = maxi(int(mk.call("buy_price", "horse")) * 40, HORSE_PRICE)
			var n := maxi(int(step.get("count", 1)), 1)
			if realm.town.coins < price * n:
				return "A horse is %d coins; we have %d." % [price, realm.town.coins]
			realm.town.coins -= price * n
			var stable := realm.building("stable")
			var at := realm.door_of(stable)
			realm.note("riding", "%d horse%s bought for %d coins." % [n, "" if n == 1 else "s", price * n])
			realm.livestock.stock_area("horse", at, n, 3.0)
			if worker.busy():
				worker.speak("%d horse%s bought; they are at the stable." % [n, "" if n == 1 else "s"])
				return "done"
			worker.take_errand_job("go", at, 0.3, "Off to the stable for %s." % ("a horse" if n == 1 else "%d horses" % n),
				{"where": "the stable"})
			return "started"
		"sell_horse":
			var h := free_horse(worker.global_position)
			if h == null:
				return "No horse to sell."
			realm.livestock.animals.erase(h)
			h.queue_free()
			realm.town.coins += HORSE_PRICE / 2
			worker.speak("Sold a horse for %d coins." % (HORSE_PRICE / 2))
			return "done"
	return "failed"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["how many horses", "any horses", "do we have a horse", "do we have horses", "got a horse"]):
		var n := horses().size()
		if n == 0:
			return "No horses. A stable, then %d coins, and you can ride." % HORSE_PRICE
		return "%d horse%s%s." % [n, "" if n == 1 else "s", ", one under you" if mount != null else ""]
	if Realm.has_phrase(t, ["where is my horse", "where are the horses", "where is the horse"]):
		var h := free_horse(realm.player.global_position)
		if mount != null:
			return "Under you."
		if h == null:
			return "There is no horse."
		var off := h.global_position - realm.player.global_position
		return "About %d metres %s." % [int(Vector2(off.x, off.z).length()), _compass(off)]
	if Realm.has_phrase(t, ["is there a stable", "do we have a stable", "have a stable"]):
		return "There is a stable." if has_stable() else "No stable yet."
	return ""


func hud_lines() -> Array[String]:
	return ["riding"] if mount != null else []


static func _compass(off: Vector3) -> String:
	var a := fmod(atan2(off.x, -off.z) + TAU, TAU)
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return dirs[int(round(a / (TAU / 8))) % 8]


func snapshot() -> Dictionary:
	return {"cart": cart != null}


func restore(d: Dictionary) -> void:
	if bool(d.get("cart", false)) and realm.player != null:
		hitch_cart()
