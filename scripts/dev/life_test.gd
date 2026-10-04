extends Node
class_name LifeTest
## A day in the village, fast: where everybody is in the working day, whether
## the village hands work out among itself, whether everybody goes to their
## own bed at night, and whether they get up again in the morning.
##
##   godot --path . -- --lifetest --fresh --nosound --nosave
##
## Writes life_day.png (the square by day), life_night.png (a couple asleep)
## to user://shots and prints PASS or FAIL.

var main: Node
var out_dir := "user://shots"

var _t := 0.0
var _phase := 0
var _fails: Array[String] = []
var _delegations: Array[String] = []


func begin() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var crew: Crew = main.crew
	var clock: GameClock = main.clock
	match _phase:
		0:
			if _t < 6.0 or main.world.busy() and _t < 25.0:
				return
			if main.daily_life == null or main.council == null:
				_fails.append("daily life / council were not raised")
				_finish()
				return
			main.council.delegated.connect(func(_r: Worker, _l: Worker, d: Worker, job: String) -> void:
				_delegations.append("%s: %s" % [d.display_name(), job]))
			main.player.set_input_enabled(false)
			main.player.teleport(main.village.well_pos + Vector3(-9, 0.3, -9), PI)
			clock.hour = 9.0
			_phase = 1
			_t = 0.0
		1:
			# The working day: partners at their trades, indoors.
			if _t < 30.0:
				return
			for pid: String in ["greta", "lena", "anselm"]:
				var w := crew.get_worker(pid)
				var where := _where(w)
				print("[life] 09:xx %s is %s (%s)" % [pid, where, w.status_text()])
				var want := str(VillagePlan.WORKPLACE[pid])
				# Stopped in the street to talk, or sent on an errand, is fine.
				if where != want and not w.engaged and w.state == Worker.State.IDLE 						and not w.indoor_walking():
					_fails.append("%s should be at the %s by day, is %s" % [pid, want, where])
			main.council._scan_t = 0.0
			_phase = 2
			_t = 0.0
		2:
			# Give the village time to notice something and hand it out.
			if _t < 100.0 and _delegations.is_empty():
				return
			print("[life] delegations after %.0f s: %s" % [_t, str(_delegations)])
			if _delegations.is_empty():
				_fails.append("nobody handed out any work in 100 s of daylight")
			_shot("life_day")
			clock.hour = 23.2
			_phase = 3
			_t = 0.0
		3:
			# Night: the households asleep in their own beds.
			if _t < 75.0:
				return
			var asleep := 0
			for wid: String in ["tobias", "greta", "ren", "lena", "mira", "anselm"]:
				var w2 := crew.get_worker(wid)
				if w2.busy() and not w2.sleeping:
					print("[life] 23:xx %s still working: %s" % [wid, w2.status_text()])
					continue
				var where2 := _where(w2)
				print("[life] 23:xx %s sleeping=%s in %s" % [wid, w2.sleeping, where2])
				if w2.sleeping and where2 == "cottage":
					asleep += 1
				elif not w2.busy():
					var hrec: Dictionary = main.daily_life._home_rec(w2)
					var nv := IndoorNav.of(hrec.get("patch", null))
					print("[life]   %s at %s, door %s (usable %s), nav walkable at door %s, anchor %s, state %s" % [
						wid, str(w2.global_position.round()), str(nv.exit_point().round()) if nv else "-",
						nv.usable() if nv else false,
						main.nav.walkable_at(nv.exit_point()) if nv else false,
						str(w2.routine_anchor.round()), w2.state])
					_fails.append("%s is not in bed at night (%s, %s)" % [wid, where2, w2.status_text()])
			print("[life] %d of the households asleep at home" % asleep)
			var cits := 0
			for c: Worker in crew.citizens():
				if c.sleeping:
					cits += 1
			print("[life] %d citizens asleep too" % cits)
			_frame_bed("tobias")
			_phase = 4
			_t = 0.0
		4:
			if _t < 3.0:
				return
			await _shot("life_night")
			clock.hour = 7.6
			_phase = 5
			_t = 0.0
		5:
			if _t < 6.0:
				return
			for w3: Worker in crew.workers:
				if w3.sleeping:
					_fails.append("%s is still asleep at 07:36" % w3.display_name())
			# "Go to your home": his own front door, and in.
			var tob := crew.get_worker("tobias")
			var said := Answers.reply("where do you live?", tob, main.town, main.village,
				clock, main.player, main.farm, main.livestock)
			print("[life] Tobias, where do you live? -> %s" % said)
			if said.find("live in") < 0:
				_fails.append("Tobias cannot say where he lives: %s" % said)
			if tob.busy():
				tob.drop_everything()
			main.dispatch.take_plan_for_test(tob, "go to your home",
				[{"do": "go", "place": "your home"}])
			_phase = 6
			_t = 0.0
		6:
			var tob2 := crew.get_worker("tobias")
			if _t < 60.0 and _where(tob2) != "cottage":
				return
			print("[life] after 'go to your home' Tobias is %s (%s)" % [_where(tob2), tob2.status_text()])
			if _where(tob2) != "cottage" or tob2.home_building_id < 0 					or tob2.indoors.patch != (main.daily_life._home_rec(tob2)["patch"]):
				_fails.append("Tobias did not go into his own house")
			_finish()


func _where(w: Worker) -> String:
	if w.indoors == null:
		return "outdoors"
	for rec: Dictionary in main.town.buildings:
		if rec.get("patch", null) == w.indoors.patch:
			return str(rec["archetype"])
	return "somewhere"


## The camera at the foot of a bed, looking up it.
func _frame_bed(wid: String) -> void:
	var w: Worker = main.crew.get_worker(wid)
	var feet := w.global_position
	var yaw := w.rotation.y
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var eye := feet + fwd * 1.6 + Vector3(0, 1.0, 0)
	var at := feet - fwd * 0.6
	var d := at - eye
	main.player.teleport(eye - Vector3(0, 1.55, 0), atan2(-d.x, -d.z))
	main.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	main.sky.hour = 23.2


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[life] %s" % path)


func _finish() -> void:
	for f: String in _fails:
		print("[life] FAIL: " + f)
	print("[life] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
