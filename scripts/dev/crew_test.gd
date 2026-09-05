extends Node
class_name CrewTest
## Does the delegation loop actually close?
##
## Instruction in, assumptions on screen, worker walks to a plot, building
## appears in the world over in-game hours, worker walks back and says so. That
## chain is the game; if any link is broken there is nothing to play.
##
## Runs against the offline plan library rather than the API, so it is free,
## deterministic and does not need a key.

var world: VoxelWorld
var gen: WorldGen
var village: Village
var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var player: Player
var farm: Farm
var livestock: Livestock
var hud: Hud

var _armed := false
var _wait := 0.0
var _t := 0.0
var _assumptions: Array = []
var _assume_worker := ""
var _done_patch: VoxelPatch = null
var _asked := ""
var _fails: Array[String] = []
var _phase := 0
var _follow_checked := false
var _last_beat := -1
var _before: Array[Vector3] = []
var _turn_from := 0.0
var _aim_at: Worker = null


func begin() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	dispatch.plan_accepted.connect(func(w: Worker, a: Array) -> void:
		_assume_worker = w.display_name()
		_assumptions = a)
	crew.job_done.connect(func(_w: Worker, p: VoxelPatch) -> void:
		_done_patch = p)
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		print("[crew]   %s (%s): %s" % [w.display_name(), kind, line]))
	# The stores are EconomyTest's subject, not this one's. Filling them keeps
	# a shortfall from masquerading as a broken delegation loop — and if one
	# happens anyway it says so rather than timing out silently.
	dispatch.short_of.connect(func(w: Worker, missing: Dictionary) -> void:
		print("[crew]   !! %s is held short of %s" % [w.display_name(),
			Resources.describe(missing)]))
	for mat: String in Resources.SOURCE:
		town.stock[mat] = 9000
	# And the plan library rather than the API, which is what the header has
	# always claimed. A free model takes the better part of two minutes per
	# call; waiting for it here would turn the loop test into a slow, flaky
	# copy of --aitest, which already covers the live path properly.
	dispatch.llm.offline = true
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		# In-game hours run fast here: the point is the loop, not the wait.
		clock.speed = 90.0
		print("[crew] armed after %.1fs" % _wait)
		return

	_t += delta
	match _phase:
		0:
			_check_look()
			_check_follow()
			var mira: Worker = crew.get_worker("mira")
			print("[crew] telling Mira: build a small bakery near the well")
			dispatch.instruct(mira, "build a small bakery near the well")
			_phase = 1
			_t = 0.0
		1:
			# Mira's, specifically. A free model can take most of a minute, and
			# accepting whoever answered first would let a later worker's plan
			# stand in for hers.
			if not _assumptions.is_empty() and _assume_worker == "Mira":
				print("[crew] %s's assumptions (%d):" % [_assume_worker,
					_assumptions.size()])
				for a: Variant in _assumptions:
					print("[crew]   - %s" % str(a))
				_phase = 2
				_t = 0.0
			elif _t > 12.0:
				_fails.append("no plan came back for Mira within 12 s")
				_phase = 3
		2:
			if _done_patch != null:
				_check_built()
				_phase = 3
				_t = 0.0
			elif _t > 60.0:
				var m: Worker = crew.get_worker("mira")
				_fails.append("Mira never finished (stuck in state %s)"
					% m.status_text())
				_phase = 3
		3:
			var tobias: Worker = crew.get_worker("tobias")
			print("[crew] telling Tobias: plant a big wheat field")
			_assumptions = []
			dispatch.instruct(tobias, "plant a big wheat field")
			_phase = 4
			_t = 0.0
		4:
			if farm.tile_count() > 0 and not _assumptions.is_empty():
				print("[crew] Tobias's assumptions (%d):" % _assumptions.size())
				for a: Variant in _assumptions:
					print("[crew]   - %s" % str(a))
				_phase = 5
				_t = 0.0
			elif int(_t) % 15 == 0 and int(_t) != _last_beat:
				_last_beat = int(_t)
				print("[crew]   t=%3ds tobias: %s" % [
					int(_t), crew.get_worker("tobias").debug_state()])
			elif _t > 120.0:
				# Tobias walks at half Mira's pace by design, and a worker looks
				# for watered ground before flat ground, which can put the field
				# a good way off. This budget is timing his walk, not his work.
				var tw: Worker = crew.get_worker("tobias")
				_fails.append("no field was ever ploughed (Tobias: %s)"
					% tw.status_text())
				_phase = 6
		5:
			var t2: Worker = crew.get_worker("tobias")
			# Finished ploughing, not finished walking home: the report walk is
			# part of the loop but it is not part of the field.
			if t2.job_field == null and farm.tile_count() > 0:
				_check_farm()
				_phase = 6
				_t = 0.0
			elif _t > 90.0:
				_fails.append("Tobias never finished the field (%s)" % t2.status_text())
				_phase = 6
		6:
			var ren: Worker = crew.get_worker("ren")
			var before := livestock.count_of("hen")
			print("[crew] telling Ren: bring some hens")
			dispatch.instruct(ren, "bring some hens")
			if livestock.count_of("hen") <= before:
				_fails.append("no hens arrived")
			else:
				print("[crew] hens: %d -> %d, %d animals in all" % [
					before, livestock.count_of("hen"), livestock.total()])
			_phase = 7
			_t = 0.0
		7:
			# Walk, so the crew falls in behind the direction of travel, then
			# stand still long enough for them to finish catching up. Recording
			# their positions the instant the player stops measures the tail of
			# the walk, not the effect of turning.
			player.set_touch_move(Vector2(0.0, -1.0) if _t < 4.0 else Vector2.ZERO)
			if _t > 7.0:
				_before.clear()
				for w: Worker in crew.workers:
					_before.append(w.global_position)
				_turn_from = player.yaw
				_phase = 8
				_t = 0.0
		8:
			# Now turn on the spot, the way you would to look at one of them.
			player.set_touch_move(Vector2.ZERO)
			player.yaw = _turn_from + PI * minf(_t / 1.5, 1.0)
			if _t > 3.0:
				_check_turning()
				_phase = 9
				_t = 0.0
		9:
			# Aim straight at the nearest one, the way a player would, and give
			# the look ray a few ticks to report what it found.
			if _aim_at != null:
				var to := _aim_at.global_position - player.global_position
				player.yaw = atan2(-to.x, -to.z)
			if _t > 0.5:
				_check_can_talk()
				_phase = 10
		10:
			_report()
			get_tree().quit(1 if not _fails.is_empty() else 0)


## Turning round must not move the crew.
##
## They used to take their slot from the player's facing, so the moment he
## turned his head the whole crew slid round to stay at his back — you could
## never get one in the crosshair, and therefore never speak to one, which
## is the only verb in the game. The slot now hangs off the direction he has
## been walking, and that only changes while he is actually moving.
func _check_turning() -> void:
	var worst := 0.0
	for i in mini(_before.size(), crew.workers.size()):
		var w: Worker = crew.workers[i]
		if w.busy():
			continue
		worst = maxf(worst, w.global_position.distance_to(_before[i]))
	print("[crew] after turning 180 degrees the crew moved at most %.2f m" % worst)
	if worst > 1.0:
		_fails.append("the crew relocated %.2f m when the player only turned "
			% worst + "round — they are still chasing his facing")

	# And the point of all that: somebody has to be in front of him now.
	var forward := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var best := -1.0
	var who := ""
	for w2: Worker in crew.workers:
		var to := w2.global_position - player.global_position
		to.y = 0.0
		if to.length() < 0.1 or to.length() > 12.0:
			continue
		var dot := forward.dot(to.normalized())
		if dot > best:
			best = dot
			who = w2.display_name()
			_aim_at = w2
	var degrees := rad_to_deg(acos(clampf(best, -1.0, 1.0)))
	print("[crew] nearest to the crosshair: %s at %.0f degrees off centre" % [
		who, degrees])
	if best < 0.7:
		_fails.append("after turning to face them the closest worker is %.0f "
			% degrees + "degrees off centre — still not lookable-at")


## The whole point: with one of them in the crosshair, does the game offer to
## let you speak to them? This is what the player was actually complaining
## about — not where the crew stood, but that they could never be addressed.
func _check_can_talk() -> void:
	if _aim_at == null:
		_fails.append("nobody was near enough to aim at after turning round")
		return
	var looking := player.looked_at_worker()
	var name_seen := "nobody" if looking == null else str(looking.name)
	print("[crew] aimed at %s, the look ray reports: %s" % [
		_aim_at.display_name(), name_seen])
	if looking == null:
		_fails.append("aiming straight at %s picks up nobody — you cannot "
			% _aim_at.display_name() + "give them an order")
	elif looking != _aim_at:
		_fails.append("aimed at %s but the game offered %s — the order would go "
			% [_aim_at.display_name(), name_seen] + "to the wrong worker")


## Mouse-look has to survive the HUD.
##
## A captured mouse reports its position at the centre of the screen, so any
## HUD control that sits there and stops the pointer eats the motion events
## before the player script sees them and the camera locks up. That is exactly
## what a six-pixel crosshair did. Nothing on this layer is meant to be clicked
## except the instruction field, so that is the rule the test enforces.
func _check_look() -> void:
	if hud == null:
		return
	var blockers: Array[String] = []
	_find_blockers(hud, blockers)
	if blockers.is_empty():
		print("[crew] HUD passes the pointer through everywhere but the text field")
	else:
		_fails.append("HUD controls that would eat mouse-look: %s"
			% ", ".join(blockers))


func _find_blockers(node: Node, into: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is LineEdit:
			continue
		var c := child as Control
		# Only what is actually on screen can eat a pointer. The instruction bar
		# and its phrase buttons are meant to be touched, and they are hidden
		# except while the player is giving an order.
		if c != null and c.is_visible_in_tree() 				and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append("%s(%s)" % [c.name, c.get_class()])
		_find_blockers(child, into)


## Idle workers should be trailing the employer, not standing at the well.
func _check_follow() -> void:
	if _follow_checked:
		return
	_follow_checked = true
	var far := 0
	for w: Worker in crew.workers:
		var d := w.global_position.distance_to(player.global_position)
		print("[crew] %s is %.1f m from the employer" % [w.display_name(), d])
		if d > 14.0:
			far += 1
	if far > 0:
		_fails.append("%d of the crew never came along" % far)


func _check_built() -> void:
	var p := _done_patch
	print("[crew] finished: %s on plot %d, %d voxels" % [
		p.archetype, p.plot_id, p.touched])

	# The patch is a plan; what matters is whether the world changed. Compare the
	# world column against the bare terrain the generator would have made there:
	# a building means the ground is now several metres taller than the land.
	var fr := p.footprint
	var cx := fr.position.x + fr.size.x / 2
	var cz := fr.position.y + fr.size.y / 2
	var land := gen.height_at(cx, cz)
	var now := world.height_at(cx, cz)
	print("[crew] column at the centre: terrain %d, world %d (+%.2f m)" % [
		land, now, float(now - land) * 0.25])
	if now - land < 8:
		_fails.append("the finished plot is no taller than bare ground")

	# A building is a solid shell round a hollow middle. Solid all the way up
	# would be a block of stone; hollow all the way up would be scaffolding.
	if not world.is_solid(Vector3i(cx, now, cz)):
		_fails.append("the top of the plot column is not solid — no roof")

	# Sample a spread of columns rather than the exact middle: with rooms at a
	# 2.5 m minimum a partition wall can run straight through the centre of the
	# footprint, and a wall there is a floor plan, not a fault.
	var best := 0
	for fz in [0.3, 0.5, 0.7]:
		for fx in [0.3, 0.5, 0.7]:
			var sx := fr.position.x + int(fr.size.x * fx)
			var sz := fr.position.y + int(fr.size.y * fz)
			var air := 0
			for dy in range(2, 9):
				if not world.is_solid(Vector3i(sx, land + dy, sz)):
					air += 1
			best = maxi(best, air)
	print("[crew] best headroom found in the footprint: %d of 7 voxels" % best)
	if best < 5:
		_fails.append("no room inside the building has standing height")

	if town.buildings.is_empty():
		_fails.append("the town register never heard about it")
	else:
		print("[crew] town now has %d building(s), tier %d" % [
			town.buildings.size(), town.tier])


## A field is only a field if it grows. Push four days through it and demand
## that something ripened.
func _check_farm() -> void:
	print("[crew] field: %d tiles, %d sown" % [
		farm.tile_count(), farm.planted_count()])
	if farm.planted_count() == 0:
		_fails.append("the field was ploughed but never sown")
		return

	# The soil has to have actually changed in the world, not just in a table.
	var soil := 0
	for key: Vector2i in farm.tiles:
		var t: Dictionary = farm.tiles[key]
		var v := world.get_voxel(Vector3i(key.x, int(t["y"]), key.y))
		if v == VoxelTypes.FARMLAND or v == VoxelTypes.WET_FARMLAND:
			soil += 1
	print("[crew] %d of %d tiles are tilled soil in the world" % [
		soil, farm.tile_count()])
	if soil < farm.tile_count() / 2:
		_fails.append("the ground was never actually turned over")

	# Long enough for a dry field. Wet ground ripens in three days and dry in
	# seven, and where the worker sited the field is their choice, not the
	# test's — so allow for the slow case.
	farm.advance_days(8.0)
	print("[crew] after eight days: %d ripe" % farm.ripe_count())
	if farm.ripe_count() == 0:
		_fails.append("nothing ripened in eight days")
		return

	# And picking one has to put food in the larder.
	var before := int(town.stock.get("food", 0))
	for key: Vector2i in farm.tiles:
		if farm.ripe_at(key):
			var got := farm.harvest(key)
			print("[crew] harvested %s; food %d -> %d" % [
				got, before, int(town.stock.get("food", 0))])
			break
	if int(town.stock.get("food", 0)) <= before:
		_fails.append("harvesting put nothing in the larder")


func _report() -> void:
	if _assumptions.is_empty():
		_fails.append("the plan carried no assumptions — pillar P3 broken")
	print("[crew] ---")
	for f: String in _fails:
		print("[crew] FAIL: %s" % f)
	print("[crew] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
