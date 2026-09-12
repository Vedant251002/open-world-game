extends Node
class_name RoleTest
## Can the player invent a job, give it to somebody in the street, and have
## that person be held to it?
##
## Offline throughout, so it is the keyword composer being tested and not a
## model — which is the composer an exported build without a key gets, and
## the one that has to be good enough on its own. What is checked is the
## boundary, not the prose: a shepherd comes out able to keep sheep and unable
## to build, an order outside the job is refused in a sentence, an order
## inside it is carried out, and a job that needs something the town has not
## got says so rather than pretending.

var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var player: Node3D
var farm: Farm
var livestock: Livestock
var world: VoxelWorld

var _armed := false
var _wait := 0.0
var _t := 0.0
var _phase := 0
var _fails: Array[String] = []
var _refusals: Array[String] = []
var _accepted := 0
var _lines: Array[String] = []
var _pick: Worker = null
var _was_at := Vector3.ZERO
var _sheep_before := 0
var _well := Vector3.ZERO
var _far_from := Vector3.ZERO
var _beat := -1
var _accepted_for := ""
var _coins_before := 0
var _works: Array[String] = []          ## archetypes of finished patches
var _buildings_before := 0
var _foreman: Worker = null
var _morning_toasts := 0
var _mira_morning := false
var _clerk: Worker = null
var _trader: Worker = null


func begin() -> void:
	dispatch.llm.offline = true
	dispatch.refused.connect(func(_w: Worker, e: Dictionary) -> void:
		_refusals.append(str(e.get("code", "?"))))
	dispatch.plan_accepted.connect(func(w: Worker, _a: Array) -> void:
		_accepted += 1
		_accepted_for = w.display_name())
	crew.job_done.connect(func(_w: Worker, p: VoxelPatch) -> void:
		_works.append(p.archetype))
	dispatch.status.connect(func(t: String) -> void:
		if t.begins_with("Morning:"):
			_morning_toasts += 1
			if t.find("Mira") >= 0:
				_mira_morning = true
			print("[role]   toast: %s" % t))
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		_lines.append(line)
		print("[role]   %s (%s): %s" % [w.display_name(), kind, line]))
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
		print("[role] armed after %.1fs" % _wait)
		return
	_t += delta

	match _phase:
		0:
			_check_catalogue()
			_check_citizens()
			_check_composer()
			_phase = 1
			_t = 0.0
		1:
			# Somebody in the street, told to do something before being hired.
			_pick = crew.citizens()[0]
			_was_at = _pick.global_position
			print("[role] telling %s (not hired): build a hut" % _pick.display_name())
			_lines.clear()
			dispatch.instruct(_pick, "build a hut")
			if _lines.is_empty() or _lines[0].find("do not work for you") < 0:
				_fails.append("a citizen took an order without being hired")
			if _pick.hired:
				_fails.append("giving a citizen an order hired them")
			_phase = 2
			_t = 0.0
		2:
			# Citizens should be moving about on their own.
			if _t > 6.0:
				var moved := 0
				for c: Worker in crew.citizens():
					if c.global_position.distance_to(c.home) > 0.5 or not c._path.is_empty():
						moved += 1
				print("[role] %d of %d citizens are out and about" % [moved, crew.citizens().size()])
				if moved < crew.citizens().size() / 3:
					_fails.append("citizens are standing still (%d of %d moving)"
						% [moved, crew.citizens().size()])
				_phase = 3
				_t = 0.0
		3:
			# Hire, offline: the keyword composer writes the job up on the spot.
			var before := crew.hired().size()
			print("[role] telling %s: hire you as a shepherd" % _pick.display_name())
			dispatch.instruct(_pick, "hire you as a shepherd")
			if crew.hired().size() != before + 1:
				_fails.append("hiring did not add to the crew (%d -> %d)"
					% [before, crew.hired().size()])
			if not _pick.hired or _pick.role == null or _pick.role.id != "shepherd":
				_fails.append("%s is not a shepherd after being hired as one"
					% _pick.display_name())
			else:
				print("[role] %s is now: %s" % [_pick.display_name(), _pick.role.summary()])
				for must: String in ["stock", "enclose", "collect"]:
					if not _pick.role.can(must):
						_fails.append("the shepherd cannot %s" % must)
				if _pick.role.can("build"):
					_fails.append("the shepherd can build, which is not shepherding")
			if not crew.roles.has("shepherd"):
				_fails.append("the shepherd role was not kept in the book")
			_phase = 4
			_t = 0.0
		4:
			# Outside the job: refused, in a sentence, with the right code.
			_refusals.clear()
			_lines.clear()
			print("[role] telling the shepherd: build a hut")
			dispatch.instruct(_pick, "build a hut")
			if "outside_role" not in _refusals:
				_fails.append("the shepherd was not refused a building (got %s)"
					% str(_refusals))
			elif _lines.is_empty() or _lines[_lines.size() - 1].find("not my trade") < 0:
				_fails.append("the refusal was not said in character: %s" % str(_lines))
			_phase = 5
			_t = 0.0
		5:
			# Inside the job: carried out.
			_sheep_before = livestock.count_of("sheep")
			_accepted = 0
			print("[role] telling the shepherd: bring 4 sheep")
			dispatch.instruct(_pick, "bring 4 sheep")
			if _accepted == 0:
				_fails.append("the shepherd's own trade was not accepted")
			_phase = 6
			_t = 0.0
		6:
			if int(_t / 5.0) != _beat:
				_beat = int(_t / 5.0)
				print("[role]   t=%4.1fs %s: %s | stock=%s" % [_t, _pick.display_name(),
					_pick.debug_state(), "yes" if not _pick.job_stock.is_empty() else "no"])
			if livestock.count_of("sheep") > _sheep_before:
				print("[role] sheep: %d -> %d" % [_sheep_before, livestock.count_of("sheep")])
				_phase = 7
				_t = 0.0
			elif _t > 40.0:
				_fails.append("the sheep never arrived (%s)" % _pick.status_text())
				_phase = 7
				_t = 0.0
		7:
			# An errand: go somewhere named, offline.
			if _pick.busy():
				if _t > 30.0:
					_fails.append("the shepherd is still busy after the sheep: %s" % _pick.status_text())
					_phase = 9
				return
			_well = dispatch.village.well_pos
			_was_at = _pick.global_position
			print("[role] telling the shepherd: go to the well  (%.0f m away)"
				% _was_at.distance_to(_well))
			_accepted = 0
			dispatch.instruct(_pick, "go to the well")
			if _accepted == 0:
				_fails.append("'go to the well' was not accepted")
			_phase = 8
			_t = 0.0
		8:
			var d := _pick.global_position.distance_to(_well)
			if d < 4.0:
				print("[role] at the well, %.1f m off" % d)
				_phase = 9
				_t = 0.0
			elif _t > 45.0:
				_fails.append("never reached the well (%.0f m off, %s)" % [d, _pick.status_text()])
				_phase = 9
				_t = 0.0
		9:
			# A job the town cannot do yet: definable, refused when asked for.
			_refusals.clear()
			_lines.clear()
			var second: Worker = crew.citizens()[0]
			print("[role] telling %s: hire you as a driver: drives people from place to place in a cart"
				% second.display_name())
			dispatch.instruct(second, "hire you as a driver: drives people from place to place in a cart")
			if not second.hired or second.role == null or second.role.id != "driver":
				_fails.append("the driver was not hired")
			elif not second.role.can("drive"):
				_fails.append("the driver role has no drive in it: %s" % second.role.summary())
			elif Capabilities.is_ready("drive"):
				_fails.append("drive is marked ready, which it is not")
			else:
				print("[role] driver: %s" % second.role.summary())
				# This is refused by the validator before any plan is made.
				var steps: Array = [{"do": "drive", "place": "the well"}]
				var err := Validator.check_plan(steps, dispatch.village.plots[0],
					{"tier": 1, "role": second.role})
				if str(err.get("code", "")) != "unknown_verb":
					# drive is not a verb yet at all — so it cannot be planned. The
					# role still lists it, honestly, as waiting on the town.
					_fails.append("planning a drive step gave %s" % str(err))
			_phase = 10
			_t = 0.0
		10:
			# Letting somebody go puts them back in the street.
			var n := crew.hired().size()
			dispatch.instruct(_pick, "you're fired")
			if _pick.hired or crew.hired().size() != n - 1:
				_fails.append("dismissal did not take")
			# And the three are not dismissable.
			var mira: Worker = crew.get_worker("mira")
			dispatch.instruct(mira, "you're fired")
			if not mira.hired:
				_fails.append("Mira was dismissed, and she is the game")
			_phase = 11
			_t = 0.0
		11:
			# Far citizens stop simulating.
			_far_from = player.global_position
			player.global_position = _far_from + Vector3(400, 0, 400)
			_phase = 12
			_t = 0.0
		12:
			if _t > 1.5:
				var off := 0
				for c: Worker in crew.citizens():
					if not c.is_physics_processing():
						off += 1
				print("[role] with the player 560 m away, %d of %d citizens are culled"
					% [off, crew.citizens().size()])
				if off < crew.citizens().size():
					_fails.append("citizens keep simulating out of sight (%d of %d culled)"
						% [off, crew.citizens().size()])
				player.global_position = _far_from
				_phase = 13
				_t = 0.0
		13:
			# A foreman: an order that becomes an order to somebody else.
			_foreman = crew.citizens()[0]
			dispatch.instruct(_foreman, "hire you as a foreman")
			if not _foreman.hired or not _foreman.role.can("delegate"):
				_fails.append("the foreman cannot delegate: %s" % (_foreman.role.summary() if _foreman.role else "no role"))
				_phase = 15
				return
			_accepted_for = ""
			print("[role]   foreman before the order: %s | errand=%s holding=%s pondering='%s'" % [
				_foreman.debug_state(), str(_foreman.job_errand.get("kind", "-")),
				str(_foreman._holding), _foreman.pondering])
			print("[role] telling the foreman: tell mira to go to the well")
			dispatch.instruct(_foreman, "tell mira to go to the well")
			_phase = 14
			_t = 0.0
		14:
			if _accepted_for == "Mira":
				print("[role] Mira took the foreman's order")
				_phase = 15
				_t = 0.0
			elif _t > 20.0:
				_fails.append("Mira never got the foreman's order (last accepted: %s)" % _accepted_for)
				_phase = 15
				_t = 0.0
		15:
			# An accountant: the numbers, said out loud.
			_clerk = crew.citizens()[0]
			dispatch.instruct(_clerk, "hire you as an accountant")
			_lines.clear()
			print("[role] telling the accountant: give me a report")
			dispatch.instruct(_clerk, "give me a report")
			_phase = 16
			_t = 0.0
		16:
			var said := ""
			for l: String in _lines:
				if l.find("purse") >= 0:
					said = l
			if said != "":
				print("[role] report: %s" % said.substr(0, 90))
				_phase = 17
				_t = 0.0
			elif _t > 10.0:
				_fails.append("the accountant never reported (%s)" % str(_lines))
				_phase = 17
				_t = 0.0
		17:
			# A merchant: stock out, coins in.
			_trader = crew.citizens()[0]
			dispatch.instruct(_trader, "hire you as a merchant")
			_coins_before = town.coins
			print("[role] telling the merchant: sell 20 timber  (purse %d)" % town.coins)
			dispatch.instruct(_trader, "sell 20 timber")
			_phase = 18
			_t = 0.0
		18:
			if town.coins > _coins_before:
				print("[role] purse: %d -> %d" % [_coins_before, town.coins])
				_phase = 19
				_t = 0.0
			elif _t > 40.0:
				_fails.append("the merchant never sold anything (%s)" % _trader.status_text())
				_phase = 19
				_t = 0.0
		19:
			# Tending: the shepherd sees to the sheep, and they give faster.
			var shep: Worker = null
			for w: Worker in crew.hired():
				if w.role != null and w.role.id == "shepherd":
					shep = w
			if shep == null:
				# Dismissed earlier; take somebody on again.
				shep = crew.citizens()[0]
				dispatch.instruct(shep, "hire you as a shepherd")
			if shep.busy():
				if _t > 20.0:
					_fails.append("the shepherd is busy: %s" % shep.status_text())
					_phase = 21
				return
			print("[role] telling the shepherd: feed the sheep")
			dispatch.instruct(shep, "feed the sheep")
			_phase = 20
			_t = 0.0
		20:
			var tended := 0
			for a: Animal in livestock.animals:
				if is_instance_valid(a) and a.tended_hours > 0.0:
					tended += 1
			if tended > 0:
				print("[role] %d animals are being seen to" % tended)
				_phase = 21
				_t = 0.0
			elif _t > 40.0:
				_fails.append("nobody tended the animals")
				_phase = 21
				_t = 0.0
		21:
			# Trees: a forester plants a grove, which is a patch like a fence.
			var f: Worker = crew.citizens()[0]
			dispatch.instruct(f, "hire you as a forester")
			_works.clear()
			print("[role] telling the forester: plant 3 trees")
			dispatch.instruct(f, "plant 3 trees")
			_phase = 22
			_t = 0.0
		22:
			if "grove" in _works or "tree" in _works:
				print("[role] the grove is in")
				_phase = 23
				_t = 0.0
			elif _t > 90.0:
				_fails.append("the trees were never planted (works: %s)" % str(_works))
				_phase = 23
				_t = 0.0
		23:
			# Demolition: the register shrinks when the last voxel is gone.
			var mira: Worker = crew.get_worker("mira")
			if mira.busy():
				if _t > 30.0:
					_fails.append("Mira still busy before demolition: %s" % mira.status_text())
					_phase = 25
				return
			_buildings_before = town.buildings.size()
			_works.clear()
			print("[role] telling Mira: demolish the hut  (%d buildings)" % _buildings_before)
			dispatch.instruct(mira, "demolish the hut")
			_phase = 24
			_t = 0.0
		24:
			if town.buildings.size() < _buildings_before:
				print("[role] buildings: %d -> %d" % [_buildings_before, town.buildings.size()])
				_phase = 25
			elif _t > 150.0:
				_fails.append("the hut was never taken down (%d buildings, works %s, Mira: %s)"
					% [town.buildings.size(), str(_works), crew.get_worker("mira").status_text()])
				_phase = 25
		25:
			# Standing tasks: "every morning, go to the well", then a new day.
			var m2: Worker = crew.get_worker("mira")
			if m2.busy():
				if _t > 30.0:
					_fails.append("Mira still busy before the morning test: %s" % m2.status_text())
					_phase = 27
				return
			_lines.clear()
			dispatch.instruct(m2, "every morning, go to the well")
			if m2.standing_task() != "go to the well":
				_fails.append("the standing task was not set (got '%s')" % m2.standing_task())
			_lines.clear()
			dispatch.instruct(m2, "what do you do each morning?")
			if _lines.is_empty() or _lines[_lines.size() - 1].find("go to the well") < 0:
				_fails.append("Mira could not say her morning task: %s" % str(_lines))
			# A preset with a standing task of its own, and a citizen told to stop.
			var acct: Worker = null
			for w: Worker in crew.hired():
				if w.role != null and w.role.id == "accountant":
					acct = w
			if acct != null and acct.standing_task() == "":
				_fails.append("the accountant preset has no standing task")
			_accepted = 0
			_accepted_for = ""
			_morning_toasts = 0
			print("[role] a new day dawns (day %d -> %d)" % [clock.day, clock.day + 1])
			clock.advance(24.0)
			_phase = 26
			_t = 0.0
		26:
			# Mira reports home by the well, so "go to the well" is over the
			# moment it starts; the toast is the proof the morning gave it to
			# her, and _accepted staying at zero is the proof it did so quietly.
			if _mira_morning and _morning_toasts >= 2:
				print("[role] Mira was given her morning task without being asked (%d morning toasts)" % _morning_toasts)
				if _accepted > 0:
					_fails.append("a morning order put up the assumptions panel")
				if _morning_toasts == 0:
					_fails.append("no morning toast was shown")
				_phase = 27
			elif _t > 20.0:
				_fails.append("Mira never got her morning task (accepted for '%s', %s)"
					% [_accepted_for, crew.get_worker("mira").status_text()])
				_phase = 27
		27:
			# A correction, live: Mira takes it hard, remembers it, and the
			# order in the same breath is planned knowing it.
			var m3: Worker = crew.get_worker("mira")
			if m3.busy():
				if _t > 30.0:
					_fails.append("Mira busy before the correction: %s" % m3.status_text())
					_phase = 28
				return
			var morale_before := float(m3.memory.disposition["morale"])
			_lines.clear()
			print("[role] telling Mira: no, I wanted a thatch roof")
			dispatch.instruct(m3, "no, I wanted a thatch roof")
			var said := _lines[_lines.size() - 1] if not _lines.is_empty() else ""
			print("[role] Mira's morale %.2f -> %.2f; wants roof_material=%s" % [
				morale_before, float(m3.memory.disposition["morale"]), m3.memory.wants("roof_material")])
			if m3.memory.wants("roof_material") != "thatch":
				_fails.append("Mira did not learn thatch (%s)" % m3.memory.wants("roof_material"))
			if float(m3.memory.disposition["morale"]) >= morale_before:
				_fails.append("the correction did not sting Mira, who is sensitive")
			if said.find("thatch") < 0:
				_fails.append("Mira did not say what she learned: %s" % said)
			# And it is on the record, where "what did I tell you" can find it.
			var noted := false
			for e: Dictionary in m3.memory.episodic:
				if str(e.get("summary", "")).find("thatch") >= 0:
					noted = true
			if not noted:
				_fails.append("the lesson is not in Mira's memory")
			_phase = 28
		28:
			_report()
			get_tree().quit(1 if not _fails.is_empty() else 0)


## Whether Mira is on, or has finished, a go errand this morning.
func m2_went() -> bool:
	var m: Worker = crew.get_worker("mira")
	return not m.job_errand.is_empty() and str(m.job_errand.get("kind", "")) == "go"


func _check_catalogue() -> void:
	var ready := Capabilities.ready_ids()
	var all := Capabilities.all_ids()
	print("[role] catalogue: %d capabilities, %d ready" % [all.size(), ready.size()])
	# Every ready capability that is a verb must have a step the planner can
	# make of it, or "ready" is a lie.
	for id: String in ready:
		if id == "answer":
			continue          # questions, not plans
		if not Steps.known(id):
			_fails.append("capability %s is ready but has no step" % id)
	# And every verb must be a capability, or a role could never include it.
	for verb: String in Steps.VERBS:
		if not Capabilities.known(verb):
			_fails.append("verb %s is not a capability" % verb)


func _check_citizens() -> void:
	var cits := crew.citizens()
	print("[role] %d citizens in the streets, %d in the crew" % [cits.size(), crew.hired().size()])
	if cits.size() < 6:
		_fails.append("only %d citizens were spawned" % cits.size())
	if crew.hired().size() != 3:
		_fails.append("the starting crew is %d, not 3" % crew.hired().size())
	for c: Worker in cits:
		if c.hired or c.role == null or c.role.id != "citizen":
			_fails.append("%s is a citizen with the wrong role" % c.display_name())
			break
	# Two citizens should not be dressed the same.
	if cits.size() >= 2 and cits[0].body.cloth_colour == cits[1].body.cloth_colour \
			and cits[0].body.hair_colour == cits[1].body.hair_colour:
		_fails.append("the first two citizens are dressed identically")


func _check_composer() -> void:
	# The keyword composer, on the names a player is most likely to type.
	var want := {
		"shepherd": ["stock", "enclose", "collect"],
		"farmer": ["sow", "harvest"],
		"guard": ["patrol", "wait"],
		"night watchman": ["patrol"],
		"builder": ["build"],
		"cook": ["cook", "station"],
		"foreman": ["delegate", "recruit"],
		"accountant": ["report"],
		"merchant": ["trade"],
		"forester": ["plant_tree"],
		"road builder": ["pave"],
	}
	for name: String in want:
		var r: Dictionary = ArchetypeLibrary.role_fallback(name, "")
		var caps: Array = r["capabilities"]
		var missing: Array[String] = []
		for c: String in want[name]:
			if c not in caps:
				missing.append(c)
		print("[role] offline '%s' -> %s" % [name, ", ".join(caps)])
		if not missing.is_empty():
			_fails.append("offline '%s' is missing %s" % [name, ", ".join(missing)])
		var err := Validator.check_role(r)
		if not err.is_empty():
			_fails.append("offline '%s' does not validate: %s" % [name, str(err["code"])])
	# And a role made of nothing the engine has is refused, not accepted empty.
	var bad := {"kind": "role", "name": "wizard", "capabilities": ["cast_spells"]}
	if str(Validator.check_role(bad).get("code", "")) != "unknown_capability":
		_fails.append("a role with an invented capability was not refused")


func _report() -> void:
	print("[role] ---")
	for f: String in _fails:
		print("[role] FAIL: %s" % f)
	print("[role] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
