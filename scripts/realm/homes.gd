extends Node
## Whose house is whose, and what every building in town is for.
##
## Population already gives everybody a bed; nothing said so out loud. This
## is where the map reads it from — the store and who keeps it, the hut and
## who sleeps in it — and where a home stops being a building you can walk
## through. Step into somebody's house and whoever lives there stops what
## they are doing, comes over, and tells you what they think of it. Stay,
## and you are put out of the door.
##
## Taverns and inns have beds too, but a bar is somewhere you are meant to
## walk into; only the plain dwellings are private.

const PRIVATE := ["hut", "cottage", "apartment", "tower_block"]
const CHECK_EVERY := 0.25
## How long the owner lets you stand there before showing you out.
const SHOW_OUT_AFTER := 5.0
## Walk back in within this long and there is no warning the second time.
const REPEAT_S := 45.0
## Further than this and they come straight to the door rather than being
## heard from across town.
const FETCH_M := 30.0
## How close a posted worker's spot has to be to a door to count as working
## there, for the directory.
const POST_M := 10.0

## Said only with no model to speak for them. With one, whoever lives there
## reacts in their own words, to this visit and every one before it.
const SCOLD := [
	"Oi! This is my house. Out.",
	"What do you think you are doing in my home? Get out.",
	"You do not just walk into somebody's house. Out, now.",
	"Excuse me! Nobody asked you in.",
]
const SCOLD_AGAIN := [
	"You again? I told you — out, and stay out.",
	"Back in my house? Have you no manners at all?",
]
const SHOW_OUT := [
	"Right, that is enough. Out you go.",
	"I said out. Go on.",
]

var realm: Realm
var _t := 0.0
var _inside_id := -1
var _inside_for := 0.0
var _owner: Worker = null
var _last_scold := {}              ## building id -> msec it last happened


func setup(r: Realm) -> void:
	realm = r


# --------------------------------------------------------------- trespass

func tick(delta: float) -> void:
	if realm.player == null or realm.town == null or realm.crew == null:
		return
	if _inside_id >= 0:
		_inside_for += delta
	_t += delta
	if _t < CHECK_EVERY:
		return
	_t = 0.0
	var rec := home_at(realm.player.global_position)
	var bid := int(rec["id"]) if not rec.is_empty() else -1
	if bid != _inside_id:
		_inside_id = bid
		_inside_for = 0.0
		_owner = null
		if bid >= 0:
			_walked_in(rec)
		return
	if bid >= 0 and _owner != null and _inside_for >= SHOW_OUT_AFTER:
		_show_out(rec)


## The private home the point is inside, if anybody lives there. An empty
## house is just a building.
func home_at(at: Vector3) -> Dictionary:
	var v := VoxelChunk.VOXEL_M
	var cell := Vector2i(floori(at.x / v), floori(at.z / v))
	for rec: Dictionary in realm.town.buildings:
		if str(rec["archetype"]) not in PRIVATE:
			continue
		var patch: VoxelPatch = rec.get("patch", null)
		if patch == null or not patch.footprint.has_point(cell):
			continue
		if residents(int(rec["id"])).is_empty():
			continue
		return rec
	return {}


## The people who sleep in a building, as bodies you could meet.
func residents(bid: int) -> Array[Worker]:
	var out: Array[Worker] = []
	if realm.population == null:
		return out
	for c: Population.Citizen in realm.population.alive():
		if c.home_id != bid:
			continue
		var w := c.worker(realm.crew)
		if w != null and is_instance_valid(w):
			out.append(w)
	return out


func _walked_in(rec: Dictionary) -> void:
	var bid := int(rec["id"])
	var here := realm.player.global_position
	var who: Worker = null
	var best := INF
	for w: Worker in residents(bid):
		var d := w.global_position.distance_to(here)
		if d < best:
			best = d
			who = w
	if who == null:
		return
	_owner = who
	var door := realm.door_of(rec)
	# Stop what they were doing. A stroll is dropped; somebody on a job for
	# you keeps the job and only speaks — the wall does not come down because
	# you went indoors.
	if not who.busy() or (who.state == Worker.State.WALKING and not who.hired):
		who.stop_wandering()
		if best > FETCH_M and door != Vector3.INF:
			# Out of earshot and very likely not being simulated. They come
			# home, rather than shouting across the valley.
			who.global_position = door + Vector3(0, 0.3, 0)
			who.set_physics_process(true)
			who.visible = true
		elif door != Vector3.INF:
			who.walk_to(door, "idle")
	var again := _last_scold.has(bid) \
			and Time.get_ticks_msec() - int(_last_scold[bid]) < int(REPEAT_S * 1000.0)
	var why := "The newcomer who runs things has just walked into your home, %s, without knocking or being asked in. They are standing inside right now. You have stopped what you were doing to deal with it. Tell them what you think and get them out." % _where(rec)
	if again:
		why = "The newcomer who runs things has walked into your home, %s, uninvited AGAIN, straight after you put them out. You are losing patience." % _where(rec)
	_say(who, why, _pick(SCOLD_AGAIN if again else SCOLD))
	who.memory.remember(realm.clock.day if realm.clock != null else 0,
		"You walked into my house without asking.", -0.3)
	who.memory.nudge("trust_in_player", -0.08 if again else -0.04)
	_last_scold[bid] = Time.get_ticks_msec()
	if again:
		_inside_for = SHOW_OUT_AFTER          # no second warning


func _show_out(rec: Dictionary) -> void:
	var door := realm.door_of(rec)
	if door == Vector3.INF:
		return
	var p := realm.player as Player
	if p != null:
		p.teleport(door + Vector3(0, 0.4, 0), p.yaw, p.pitch)
	else:
		realm.player.global_position = door + Vector3(0, 0.4, 0)
	if _owner != null and is_instance_valid(_owner):
		_say(_owner, "They ignored you and stayed in your home, so you have just marched them out of the door yourself. Say something as you do it.",
			_pick(SHOW_OUT))
		realm.say("%s put you out of the house." % _owner.display_name())
	_last_scold[int(rec["id"])] = Time.get_ticks_msec()
	_inside_id = -1
	_inside_for = 0.0
	_owner = null


## Through the dispatcher, which hands it to the model to say as this person,
## or says the stock line if there is no model.
func _say(who: Worker, situation: String, fallback: String) -> void:
	var d: Node = realm.dispatch
	if d != null and d.has_method("converse"):
		d.call("converse", who, "", situation, "", fallback, "refuse")
	else:
		who.speak(fallback, "refuse")


static func _where(rec: Dictionary) -> String:
	var street := str(rec.get("street", ""))
	var arch := str(rec["archetype"]).replace("_", " ")
	return "the %s on %s" % [arch, street] if street != "" else "your %s" % arch


static func _pick(pool: Array) -> String:
	return str(pool[randi() % pool.size()])


# -------------------------------------------------------------- directory

## Every building, what it is and who belongs to it, for the map.
## Each entry: {name, street, rect_m, lines, private}.
func directory() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var industry: Node = realm.system("Industry")
	var v := VoxelChunk.VOXEL_M
	for rec: Dictionary in realm.town.buildings:
		var bid := int(rec["id"])
		var arch := str(rec["archetype"])
		var patch: VoxelPatch = rec.get("patch", null)
		if patch == null:
			continue
		var fr := patch.footprint
		var lines: Array[String] = []

		var keepers: Array[String] = []
		for w: Worker in _posted_at(rec):
			keepers.append("%s (%s)" % [w.display_name(), w.role.name])
		if industry != null and industry.has_method("staff_of"):
			for c: Variant in industry.call("staff_of", bid):
				keepers.append((c as Population.Citizen).name)
		if not keepers.is_empty():
			lines.append("works here: " + ", ".join(keepers))

		var sleepers: Array[String] = []
		for w: Worker in residents(bid):
			sleepers.append(w.display_name())
		var is_private := arch in PRIVATE
		if not sleepers.is_empty():
			lines.append(("home of " if is_private else "lodging: ") + _and(sleepers))
		elif is_private:
			lines.append("empty — nobody lives here yet")

		out.append({
			"name": arch.replace("_", " ").capitalize(),
			"street": str(rec.get("street", "")),
			"rect_m": Rect2(fr.position.x * v, fr.position.y * v, fr.size.x * v, fr.size.y * v),
			"lines": lines,
			"private": is_private and not sleepers.is_empty(),
		})
	return out


## Where each of your people is: at their post, or with you.
func crew_lines() -> Array[String]:
	var out: Array[String] = []
	for w: Worker in realm.crew.hired():
		var job := w.role.name if w.role != null else "hand"
		var where := "with you"
		if w.employer == null:
			var rec := _nearest_building(w.home)
			if not rec.is_empty():
				where = "at the " + str(rec["archetype"]).replace("_", " ")
			elif w.home.distance_to(realm.village.well_pos) < 20.0:
				where = "by the well"
			else:
				where = "out of town"
		out.append("%s — %s, %s" % [w.display_name(), job, where])
	return out


func _posted_at(rec: Dictionary) -> Array[Worker]:
	var out: Array[Worker] = []
	for w: Worker in realm.crew.hired():
		if w.employer != null:
			continue
		if _nearest_building(w.home) == rec:
			out.append(w)
	return out


func _nearest_building(at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := POST_M
	for rec: Dictionary in realm.town.buildings:
		var door := realm.door_of(rec)
		if door == Vector3.INF:
			continue
		var d := Vector2(door.x - at.x, door.z - at.z).length()
		if d < best_d:
			best_d = d
			best = rec
	return best


static func _and(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]
