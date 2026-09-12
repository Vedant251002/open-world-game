extends Node
class_name SaveTest
## Does the town come back?
##
## Two boots of the same process. The first plays a few minutes — hires
## somebody, defines a job the presets do not have, fences a pen and stocks
## it, moves the player — then writes the save and reloads the scene. The
## second boot is main.gd starting exactly as it would for a player with a
## save: it reads the file, stands the town up, and this test checks that
## what was there is there. Statics carry the expectations across the reload;
## nothing else does, which is the point.
##
## The save goes to a scratch path. A test that could overwrite the player's
## town is not a test anybody wants to run twice.

static var second_boot := false
static var expect: Dictionary = {}

var main: Node
var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var player: Node3D
var livestock: Livestock
var world: VoxelWorld

var _armed := false
var _wait := 0.0
var _t := 0.0
var _phase := 0
var _fails: Array[String] = []
var _works: Array[VoxelPatch] = []
var _hand: Worker = null


func begin() -> void:
	SaveGame.path = "user://save/_savetest.save"
	SaveGame.enabled = true
	dispatch.llm.offline = true
	crew.job_done.connect(func(_w: Worker, p: VoxelPatch) -> void:
		_works.append(p))
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		print("[save]   %s (%s): %s" % [w.display_name(), kind, line]))
	for mat: String in Resources.SOURCE:
		town.stock[mat] = 9000
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		clock.speed = 60.0
		print("[save] armed after %.1fs (%s boot)" % [_wait, "second" if second_boot else "first"])
		if second_boot:
			_check_restored()
			_finish()
		return
	_t += delta

	match _phase:
		0:
			# Somebody from the street, given a job the presets do not have, so
			# the role has to be composed and then kept.
			_hand = crew.citizens()[0]
			dispatch.instruct(_hand, "hire you as a lamplighter: walks the streets at dusk lighting the lamps")
			if not _hand.hired or _hand.role == null or _hand.role.id != "lamplighter":
				_fails.append("the lamplighter was not hired")
			# And a shepherd with a pen, so there is a voxel change that is not
			# a founding building.
			var shep: Worker = crew.citizens()[0]
			dispatch.instruct(shep, "hire you as a shepherd")
			print("[save] telling the shepherd: fence a pen and put 4 sheep in it")
			dispatch.instruct(shep, "fence a pen and put 4 sheep in it")
			_phase = 1
			_t = 0.0
		1:
			var pen: VoxelPatch = null
			for p: VoxelPatch in _works:
				if p.archetype == "pen":
					pen = p
			if pen != null and livestock.count_of("sheep") >= 4:
				# A post of the fence, to look for after the reload.
				var post := Vector3i.ZERO
				for i in pen.build_order:
					if pen.data[i] != VoxelPatch.UNTOUCHED and pen.data[i] != VoxelTypes.AIR:
						post = pen.world_of(i)
						break
				expect["post"] = post
				expect["post_mat"] = world.get_voxel(post)
				print("[save] pen up, %d sheep; fence post at %s is %d" % [
					livestock.count_of("sheep"), str(post), int(expect["post_mat"])])
				_phase = 2
				_t = 0.0
			elif _t > 120.0:
				_fails.append("the pen and sheep never came (%d works, %d sheep)"
					% [_works.size(), livestock.count_of("sheep")])
				_finish()
		2:
			# Move the player, note everything, save, reload.
			player.global_position = player.global_position + Vector3(9.0, 0.0, -6.0)
			var mira: Worker = crew.get_worker("mira")
			mira.memory.learn("thatched roofs", 0.8, 0)
			expect["day"] = clock.day
			expect["hired"] = crew.hired().size()
			expect["buildings"] = town.buildings.size()
			expect["sheep"] = livestock.count_of("sheep")
			expect["coins"] = town.coins
			expect["player"] = player.global_position
			expect["lamplighter"] = _hand.memory.worker_id
			expect["shepherd_id"] = _pick_role("shepherd")
			expect["edits"] = world.export_edits().size()
			main.call("_save_now", "test")
			var back := SaveGame.read()
			if back.is_empty():
				_fails.append("the save did not read back")
				_finish()
				return
			print("[save] written: %d edited chunks, %d people, %d roles, %d buildings" % [
				(back["world"] as Dictionary).size(), (back["crew"] as Array).size(),
				(back["roles"] as Dictionary).size(), (back["town"]["buildings"] as Array).size()])
			if (back["roles"] as Dictionary).is_empty():
				_fails.append("no custom role was saved")
			if not _fails.is_empty():
				_finish()
				return
			second_boot = true
			print("[save] reloading the scene...")
			get_tree().reload_current_scene()
			_phase = 3


func _pick_role(id: String) -> String:
	for w: Worker in crew.hired():
		if w.role != null and w.role.id == id:
			return w.memory.worker_id
	return ""


## Second boot. main.gd has read the scratch save and stood the town up; this
## is what a player would find.
func _check_restored() -> void:
	_ok(clock.day == int(expect["day"]), "day %d came back as %d" % [int(expect["day"]), clock.day])
	_ok(crew.hired().size() == int(expect["hired"]),
		"%d hired came back as %d" % [int(expect["hired"]), crew.hired().size()])
	_ok(town.buildings.size() == int(expect["buildings"]),
		"%d buildings came back as %d" % [int(expect["buildings"]), town.buildings.size()])
	_ok(livestock.count_of("sheep") == int(expect["sheep"]),
		"%d sheep came back as %d" % [int(expect["sheep"]), livestock.count_of("sheep")])
	_ok(town.coins == int(expect["coins"]), "coins %d came back as %d" % [int(expect["coins"]), town.coins])

	var lamp: Worker = crew.get_worker(str(expect["lamplighter"]))
	_ok(lamp != null and lamp.hired and lamp.role != null and lamp.role.id == "lamplighter",
		"the lamplighter is still the lamplighter (%s)"
		% (lamp.role.summary() if lamp != null and lamp.role != null else "gone"))
	_ok(crew.roles.has("lamplighter") and crew.roles.get_role("lamplighter").source != "builtin",
		"the composed role is in the book")
	var shep: Worker = crew.get_worker(str(expect["shepherd_id"]))
	_ok(shep != null and shep.hired and shep.role.id == "shepherd", "the shepherd is still the shepherd")
	var remembered := false
	if shep != null:
		for e: Dictionary in shep.memory.episodic:
			if str(e.get("summary", "")).find("Taken on") >= 0:
				remembered = true
	_ok(remembered, "the shepherd remembers being taken on")

	var mira: Worker = crew.get_worker("mira")
	var learned := false
	for p: Dictionary in mira.memory.learned_preferences:
		if str(p.get("text", "")).find("thatched") >= 0:
			learned = true
	_ok(learned, "Mira still knows you like thatched roofs")

	var post: Vector3i = expect["post"]
	_ok(world.get_voxel(post) == int(expect["post_mat"]),
		"the fence post at %s is still there (%d, wanted %d)" % [
			str(post), world.get_voxel(post), int(expect["post_mat"])])
	var at: Vector3 = expect["player"]
	var d := Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length()
	_ok(d < 1.0, "the player is back where they stood (%.1f m off)" % d)
	_ok(world.export_edits().size() >= int(expect["edits"]),
		"%d edited chunks came back as %d" % [int(expect["edits"]), world.export_edits().size()])
	# The founding bakery is a building again, not a shell: somebody can be
	# sent to it.
	var bakery := dispatch._resolve_place("bakery", mira)
	_ok(not bakery.is_empty(), "the bakery can still be found")
	var props := 0
	for n: Node in main.get_node("Props").get_children():
		props += 1
	_ok(props > 20, "the furniture came back (%d props)" % props)


func _ok(cond: bool, what: String) -> void:
	print("[save]   %s %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _finish() -> void:
	SaveGame.erase()
	print("[save] ---")
	for f: String in _fails:
		print("[save] FAIL: %s" % f)
	print("[save] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
	get_tree().quit(1 if not _fails.is_empty() else 0)
