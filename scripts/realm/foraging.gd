extends Node
## What the land gives to anyone who walks out and looks: berries, herbs,
## mushrooms, fish, and the meat of what the player shoots.
##
## Forage spots are seeded around the town past the last street — a bush
## with red on it, a ring of caps, a tuft of something green — and stand up
## as a few boxes when the player is near enough to see them. Press [E]
## beside one and it goes into the stores; three days later it has grown
## back. Water fished by hand for a few seconds gives fish. A deer brought
## down with anything from the armoury gives meat, if the player is close
## enough to have been the one who did it. Workers can be sent for all of
## it, and come back with a count.

const SPOTS := 18
const RING_MIN_M := 10.0
const RING_MAX_M := 80.0
const SEE_M := 90.0
const FORGET_M := 150.0
const PICK_REACH := 2.2
const REGROW_DAYS := 3
const FISH_HOLD_S := 3.0
const HUNT_REACH := 25.0
const MEAT := {"deer": 8, "rabbit": 2}
const KINDS := ["berries", "berries", "berries", "herb", "herb", "mushroom"]
const WORKER_HOURS := {"fish": 3.0, "hunt": 4.0, "gather": 2.0}

var realm: Realm
var spots: Array[Dictionary] = []   ## {x, z, kind, picked_day, node, fruit: Array}
var _jobs: Array[Dictionary] = []   ## {worker_id, kind, done_at, n, what}
var _t := 0.0
var _fish_hold := 0.0
var _counted: Dictionary = {}       ## animal instance id -> true
var _rng := RandomNumberGenerator.new()
var _hint_spot: Dictionary = {}


func setup(r: Realm) -> void:
	realm = r
	_rng.seed = hash("forage:%d" % (realm.village.seed_value if realm.village != null else 3))
	_seed_spots()


func _seed_spots() -> void:
	spots.clear()
	var b := realm.village.bounds_v
	var v := VoxelChunk.VOXEL_M
	var half := Vector2(b.size.x, b.size.y) * v * 0.5
	var centre := Vector2(b.position.x * v + half.x, b.position.y * v + half.y)
	for i in SPOTS:
		var ang := TAU * float(i) / float(SPOTS) + _rng.randf_range(-0.2, 0.2)
		var dir := Vector2(cos(ang), sin(ang))
		# Out past the plots in this direction, then a little further.
		var edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var dist := edge + _rng.randf_range(RING_MIN_M, RING_MAX_M)
		var p := centre + dir * dist
		spots.append({"x": p.x, "z": p.y, "kind": KINDS[_rng.randi() % KINDS.size()],
			"picked_day": -100, "node": null, "fruit": []})


# ------------------------------------------------------------------- spots

func ripe(s: Dictionary) -> bool:
	return realm.clock.day - int(s["picked_day"]) >= REGROW_DAYS


func pick(s: Dictionary) -> int:
	if not ripe(s):
		return 0
	var n := _rng.randi_range(3, 6)
	var kind := str(s["kind"])
	realm.town.stock[kind] = int(realm.town.stock.get(kind, 0)) + n
	if kind != "herb":
		realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + n * 2
	s["picked_day"] = realm.clock.day
	_show_fruit(s, false)
	return n


func nearest(kind: String, from: Vector3, only_ripe: bool = true) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	for s: Dictionary in spots:
		if kind != "" and str(s["kind"]) != kind:
			continue
		if only_ripe and not ripe(s):
			continue
		var d := Vector2(float(s["x"]) - from.x, float(s["z"]) - from.z).length()
		if d < best_d:
			best = s
			best_d = d
	return best


func _spawn(s: Dictionary) -> void:
	var x := float(s["x"])
	var z := float(s["z"])
	var col := VoxelWorld.column_of(Vector3(x, 0.0, z))
	if not realm.world.has_column(col.x, col.y):
		return
	var v := VoxelWorld.to_voxel(Vector3(x, 0.0, z))
	var top := realm.world.get_voxel(Vector3i(v.x, realm.world.height_at(v.x, v.z), v.z))
	if top == VoxelTypes.WATER or top == VoxelTypes.COBBLE:
		s["picked_day"] = 1 << 20      # never ripe: a spot that landed in the lake
		return
	var root := Node3D.new()
	root.position = Vector3(x, realm.world.ground_m(x, z), z)
	realm.props_root.add_child(root)
	var fruit: Array = []
	match str(s["kind"]):
		"berries":
			var leaf := Color("#2f5a2a")
			BoxKit.add(root, Vector3(-0.5, 0.0, -0.45), Vector3(1.0, 0.7, 0.9), leaf)
			BoxKit.add(root, Vector3(-0.3, 0.5, -0.3), Vector3(0.6, 0.4, 0.6), leaf.lightened(0.1))
			for i in 7:
				var at := Vector3(_rng.randf_range(-0.45, 0.35), _rng.randf_range(0.15, 0.8), _rng.randf_range(-0.4, 0.4))
				fruit.append(BoxKit.add(root, at, Vector3(0.1, 0.1, 0.1), Color("#b3202a")))
		"mushroom":
			for i in 5:
				var ang := TAU * i / 5.0
				var at := Vector3(cos(ang) * 0.5, 0.0, sin(ang) * 0.5)
				BoxKit.add(root, at + Vector3(-0.04, 0.0, -0.04), Vector3(0.08, 0.22, 0.08), Color("#e8dcc4"))
				fruit.append(BoxKit.add(root, at + Vector3(-0.12, 0.2, -0.12), Vector3(0.24, 0.08, 0.24), Color("#a0522d")))
		_:
			var green := Color("#5f8a3c")
			for i in 4:
				var at := Vector3(_rng.randf_range(-0.4, 0.3), 0.0, _rng.randf_range(-0.4, 0.3))
				fruit.append(BoxKit.add(root, at, Vector3(0.12, _rng.randf_range(0.25, 0.45), 0.12), green))
			BoxKit.add(root, Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 0.08, 0.7), Color("#3f5f2a"))
	for child in root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visibility_range_end = SEE_M
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s["node"] = root
	s["fruit"] = fruit
	_show_fruit(s, ripe(s))


func _show_fruit(s: Dictionary, on: bool) -> void:
	for f: Variant in s["fruit"]:
		if is_instance_valid(f):
			(f as Node3D).visible = on


func _despawn(s: Dictionary) -> void:
	var node: Node3D = s["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()
	s["node"] = null
	s["fruit"] = []


# --------------------------------------------------------------------- tick

func tick(delta: float) -> void:
	var player := realm.player
	if player == null:
		return
	# [E] beside a ripe spot picks it; holding it at the water's edge fishes.
	if Input.is_action_just_pressed("talk"):
		if not (player.has_method("looked_at_worker") and player.call("looked_at_worker") is Worker):
			var s := nearest("", player.global_position)
			if not s.is_empty() and _dist(s, player.global_position) <= PICK_REACH:
				var n := pick(s)
				realm.say("Picked %d %s." % [n, s["kind"]])
	if Input.is_action_pressed("talk") and _near_water(player.global_position):
		_fish_hold += delta
		if _fish_hold >= FISH_HOLD_S:
			_fish_hold = 0.0
			var n2 := _rng.randi_range(1, 3)
			realm.town.stock["fish"] = int(realm.town.stock.get("fish", 0)) + n2
			realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + n2 * 3
			realm.say("Caught %d fish." % n2)
	else:
		_fish_hold = 0.0
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var p := player.global_position
	for s2: Dictionary in spots:
		var d := _dist(s2, p)
		if s2["node"] == null and d <= SEE_M:
			_spawn(s2)
		elif s2["node"] != null and d > FORGET_M:
			_despawn(s2)
		elif s2["node"] != null:
			_show_fruit(s2, ripe(s2))
	var near := nearest("", p)
	if not near.is_empty() and _dist(near, p) <= PICK_REACH:
		if _hint_spot != near:
			_hint_spot = near
			realm.say("[E] pick %s" % near["kind"])
	else:
		_hint_spot = {}
	_watch_kills(p)


func _dist(s: Dictionary, from: Vector3) -> float:
	return Vector2(float(s["x"]) - from.x, float(s["z"]) - from.z).length()


func _near_water(at: Vector3) -> bool:
	if bool(realm.player.get("in_water")):
		return true
	for off: Vector3 in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
		var v := VoxelWorld.to_voxel(at + off)
		var y := realm.world.height_at(v.x, v.z)
		if y >= 0 and realm.world.get_voxel(Vector3i(v.x, y, v.z)) == VoxelTypes.WATER:
			return true
	return false


## A wild animal that has just been brought down near the player is meat.
func _watch_kills(p: Vector3) -> void:
	if realm.wildlife == null:
		return
	for a: Animal in realm.wildlife.beasts:
		if not is_instance_valid(a):
			continue
		var id := a.get_instance_id()
		if _counted.has(id):
			continue
		if float(a.get("_dying")) > 0.0:
			_counted[id] = true
			var meat := int(MEAT.get(a.kind, 0))
			if meat > 0 and a.global_position.distance_to(p) <= HUNT_REACH:
				realm.town.stock["meat"] = int(realm.town.stock.get("meat", 0)) + meat
				realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + meat
				realm.say("Took a %s: %d meat." % [a.kind, meat])
				realm.note("hunt", "Took a %s in the woods." % a.kind)
	if _counted.size() > 200:
		_counted.clear()


# ------------------------------------------------------------------ workers

func on_hour(_hour: float, _day: int) -> void:
	var now := realm.clock.day * 24.0 + realm.clock.hour
	for job: Dictionary in _jobs.duplicate():
		if now < float(job["done_at"]):
			continue
		_jobs.erase(job)
		var w: Worker = realm.crew.get_worker(str(job["worker_id"]))
		var kind := str(job["kind"])
		var line := ""
		match kind:
			"fish":
				var n := _rng.randi_range(4, 8)
				realm.town.stock["fish"] = int(realm.town.stock.get("fish", 0)) + n
				realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + n * 3
				line = "Back with %d fish." % n
			"hunt":
				var skill := 0.5
				if w != null:
					skill = clampf(float(w.memory.skills.get("carpentry", 0)) * 0.2 + 0.5, 0.3, 1.0)
				var n2 := int(_rng.randi_range(4, 10) * skill)
				if n2 <= 0:
					line = "Nothing to be had out there today."
				else:
					realm.town.stock["meat"] = int(realm.town.stock.get("meat", 0)) + n2
					realm.town.stock["food"] = int(realm.town.stock.get("food", 0)) + n2
					line = "Back with %d meat." % n2
			"gather":
				var what := str(job["what"])
				var got := 0
				for i in 3:
					var s := nearest(what, realm.village.well_pos)
					if s.is_empty():
						break
					got += pick(s)
				line = "Back with %d %s." % [got, what] if got > 0 else "Nothing ripe out there just now."
		if w != null and is_instance_valid(w):
			if not w.job_errand.is_empty():
				w.drop_everything()
			w.speak(line)
		realm.note("forage", line)


func _water_near_town() -> Vector3:
	var well := realm.village.well_pos
	for r in range(12, 84, 4):
		for k in 12:
			var ang := TAU * k / 12.0
			var at := well + Vector3(cos(ang), 0.0, sin(ang)) * r
			var v := VoxelWorld.to_voxel(at)
			var y := realm.world.height_at(v.x, v.z)
			if y >= 0 and realm.world.get_voxel(Vector3i(v.x, y, v.z)) == VoxelTypes.WATER:
				# Stand on the bank, a step back toward the well.
				var bank := at - Vector3(cos(ang), 0.0, sin(ang)) * 3.0
				bank.y = realm.world.ground_m(bank.x, bank.z)
				return bank
	return Vector3.INF


func _send(worker: Worker, kind: String, target: Vector3, what: String, line: String) -> bool:
	if worker.busy():
		worker.speak("When I am done here.")
		return true
	var hours: float = WORKER_HOURS[kind]
	var stand := target
	stand.y = realm.world.ground_m(stand.x, stand.z)
	worker.take_errand_job("wait", stand, hours, line, {"where": "out " + kind + "ing", "doing": "survey"})
	_jobs.append({"worker_id": worker.memory.worker_id, "kind": kind, "what": what,
		"done_at": realm.clock.day * 24.0 + realm.clock.hour + hours})
	return true


## Fishing and hunting are the dispatcher's own verbs; the woods' small
## harvest is this system's.
func verbs() -> Dictionary:
	return {
		"forage": {
			"says": "go out and pick berries, herbs or mushrooms where they grow",
			"required": ["what"],
			"types": {"what": ["berries", "herb", "mushroom"]},
			"anyone": false,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	if str(step.get("do", "")) != "forage":
		return "failed"
	var what := str(step.get("what", "berries"))
	var s2 := nearest(what, realm.village.well_pos)
	if s2.is_empty():
		return "Nothing ripe of that just now; give it a few days."
	if worker.busy():
		return "When I am done here."
	_send(worker, "gather", Vector3(float(s2["x"]), 0.0, float(s2["z"])), what,
		"Off to gather %s." % what)
	return "started"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	for what: String in ["berries", "herb", "mushroom"]:
		var words: Array = {"berries": ["berries", "berry"], "herb": ["herbs", "herb"], "mushroom": ["mushrooms", "mushroom"]}[what]
		if Realm.has_word(t, words) and Realm.has_phrase(t, ["where", "any", "find"]) \
				and not Realm.has_phrase(t, ["how many", "how much"]):
			var s := nearest(what, realm.village.well_pos, false)
			if s.is_empty():
				return "No %s anywhere near." % what
			var off := Vector3(float(s["x"]), 0.0, float(s["z"])) - realm.village.well_pos
			return "%s about %d metres %s of the well%s." % [what.capitalize(), int(Vector2(off.x, off.z).length()),
				_compass(off), "" if ripe(s) else ", though it was picked lately"]
	if Realm.has_phrase(t, ["anywhere to fish", "where can i fish", "where to fish", "any fish", "fishing"]) \
			and not Realm.has_phrase(t, ["how many", "how much"]):
		var bank := _water_near_town()
		if bank == Vector3.INF:
			return "No water within reach of the town."
		var off2 := bank - realm.village.well_pos
		return "Water about %d metres %s of the well. Hold [E] at the edge." % [int(Vector2(off2.x, off2.z).length()), _compass(off2)]
	return ""


static func _compass(off: Vector3) -> String:
	var a := fmod(atan2(off.x, -off.z) + TAU, TAU)
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return dirs[int(round(a / (TAU / 8))) % 8]


func snapshot() -> Dictionary:
	var picked: Array = []
	for s: Dictionary in spots:
		picked.append(int(s["picked_day"]))
	return {"picked": picked}


func restore(d: Dictionary) -> void:
	var picked: Array = d.get("picked", [])
	for i in mini(picked.size(), spots.size()):
		spots[i]["picked_day"] = int(picked[i])
