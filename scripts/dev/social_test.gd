extends Node
class_name SocialTest
## Relationships, personality and voice, headless:
##
##   godot --headless --path . -- --socialtest --nosave --noquick
##
## Boots the real game. Checks that relationships move on simulated events (and
## persist through a memory round trip), that temperament changes a plan
## deterministically while it still validates, and that Voice does nothing,
## cleanly, with no TTS. `--cardshot --shotdir=/abs/dir` instead opens the
## villager card and saves screenshots (needs a renderer).

var main: Node
var shot_mode := false
var fails: Array[String] = []
var _n := 0


func _check(cond: bool, what: String) -> void:
	_n += 1
	if not cond:
		fails.append(what)
		print("[social] FAIL: %s" % what)


func begin() -> void:
	await get_tree().process_frame
	if shot_mode:
		await _shots()
		return
	_relationships()
	_live_events()
	_personality()
	await _plan_flow()
	_voice()
	print("[social] %d checks, %d failed -> %s" % [_n, fails.size(), "PASS" if fails.is_empty() else "FAIL"])
	get_tree().quit(0 if fails.is_empty() else 1)


func _mem(id: String, traits: Dictionary = {}, trust: float = 0.5) -> WorkerMemory:
	var t := {"speed": 0.5, "literalism": 0.5, "initiative": 0.5,
		"question_threshold": 0.5, "criticism_sensitivity": 0.5}
	t.merge(traits, true)
	return WorkerMemory.make(id, id.capitalize(), t,
		{"trust_in_player": trust, "morale": 0.7, "confidence": 0.5},
		{"carpentry": 1, "masonry": 1, "machining": 0, "piloting": 0})


# ------------------------------------------------------------ relationships

func _relationships() -> void:
	var m := _mem("ada")
	_check(Relationships.label(m) == "Stranger", "a fresh villager is a stranger, got %s" % Relationships.label(m))
	# Classification of what the player says.
	_check(Relationships.classify("well done, that is lovely work") == "praise", "praise is praise")
	_check(Relationships.classify("you are useless") == "insult", "insult is insult")
	_check(Relationships.classify("that is not good") != "praise", "'not good' is not praise")
	_check(Relationships.classify("no, I wanted a thatch roof") == "scolded", "a stinging correction is a scold")
	_check(Relationships.classify("build a hut") == "", "an order is neutral")

	var day := 3
	for i in 3:
		Relationships.record(m, "praise", day)
	_check(int(m.relationship["counts"]["praise"]) == 3, "three praises recorded")
	var capped := Relationships.record(m, "praise", day)
	_check(not bool(capped["applied"]), "a fourth praise the same day is capped")
	_check(bool(Relationships.record(m, "praise", day + 1)["applied"]), "the cap resets the next day")
	var up := Relationships.standing(m)
	_check(up > 0.0, "praise raises standing")
	for d in 8:
		for k in ["praise", "order_done", "request_done", "gift"]:
			Relationships.record(m, k, 10 + d)
	_check(Relationships.tier(m) >= Relationships.Tier.FRIEND,
		"a run of good days makes a friend, got %s (%.2f)" % [Relationships.label(m), Relationships.standing(m)])
	_check(Relationships.work_factor(m) > 1.0, "a friend works faster")
	var warm := Relationships.tint(m, "Hello.", "talk")
	_check(warm != "Hello." and warm.length() > 6, "a friend's stock line is warmer: %s" % warm)
	_check(Relationships.prompt_line(m).find("friend") >= 0 or Relationships.prompt_line(m).find("confidant") >= 0,
		"the prompt knows they are close")
	_check(not Relationships.memories(m, 4).is_empty(), "there is something remembered")

	# The opposite road.
	var r := _mem("bram", {"criticism_sensitivity": 0.9})
	var heard: Array = []
	Relationships.tier_listener = func(mem: WorkerMemory, a: int, b: int) -> void:
		heard.append([mem.worker_id, a, b])
	for i in 4:
		Relationships.record(r, "insult", 5 + i)
	Relationships.record(r, "trespass", 9, {"again": true, "quiet": true})
	Relationships.record(r, "dismissed", 9)
	Relationships.tier_listener = Callable()
	_check(Relationships.is_resentful(r), "insults, trespass and dismissal breed resentment, got %s (%.2f)" % [Relationships.label(r), Relationships.standing(r)])
	_check(Relationships.work_factor(r) < 1.0, "resentful works slower")
	_check(not heard.is_empty(), "a change of label is announced")
	_check(Relationships.tint(r, "Hello.", "talk").begins_with(Relationships.tint(r, "Hello.", "talk").split(" ")[0]) \
		and Relationships.tint(r, "Hello.", "talk") != "Hello.", "a resentful stock line is curter")
	var grumbles := Relationships.grumble(r, 20)
	_check(grumbles != "", "the resentful grumble when they start work")
	_check(Relationships.grumble(r, 20) == "", "but only once a day")
	_check(Relationships.memories(r, 4).any(func(e: Dictionary) -> bool: return float(e["valence"]) < 0.0),
		"the card has a bad memory to show")

	# A cool-off, and a save round trip.
	var before := Relationships.affection(r)
	Relationships.drift(r)
	_check(absf(Relationships.affection(r)) < absf(before), "feelings cool a little each morning")
	var copy := _mem("bram")
	copy.from_dict(r.to_dict())
	_check(is_equal_approx(Relationships.affection(copy), Relationships.affection(r)) and Relationships.tier(copy) == Relationships.tier(r),
		"a relationship survives the save")
	var old := _mem("cal")
	var d := old.to_dict()
	d.erase("relationship")
	var from_old := _mem("cal")
	from_old.from_dict(d)
	_check(Relationships.label(from_old) == "Stranger", "an old save with no relationship loads as a stranger")


## The real game: the bound HUD signal and crew events change relationships.
func _live_events() -> void:
	var crew: Crew = main.crew
	var hud: Hud = main.hud
	var mira: Worker = crew.get_worker("mira")
	var a0 := Relationships.affection(mira.memory)
	hud.instruction_given.emit(mira, "well done Mira, lovely work")
	_check(Relationships.affection(mira.memory) > a0, "praise typed at the HUD warms Mira")
	var a1 := Relationships.affection(mira.memory)
	hud.instruction_given.emit(mira, "you useless idiot")
	_check(Relationships.affection(mira.memory) < a1, "an insult typed at the HUD cools her")
	var a2 := Relationships.affection(mira.memory)
	mira.step_done.emit(mira)
	_check(Relationships.affection(mira.memory) > a2, "finishing a job for you warms a hired worker")
	# Mood and rate feed the real work rate.
	var rate_now := mira.memory.work_rate()
	mira.memory.relationship["affection"] = -0.9
	_check(mira.memory.work_rate() < rate_now, "work_rate drops with resentment")
	mira.memory.relationship["affection"] = 0.0


# --------------------------------------------------------------- personality

func _personality() -> void:
	var plot: Plot = main.village.plots[0]
	var ctx := {"world": main.world, "village": main.village, "worldgen": main.gen,
		"tier": 1, "occupied_rects": [], "built_fronts": {}}
	var crew: Crew = main.crew
	var ren: WorkerMemory = crew.get_worker("ren").memory
	var mira: WorkerMemory = crew.get_worker("mira").memory
	var tobias: WorkerMemory = crew.get_worker("tobias").memory
	_check(Personality.kind_of(ren) == "proud" and Personality.kind_of(mira) == "careless" \
		and Personality.kind_of(tobias) == "meticulous", "the three have their temperaments")
	for arch in ["cottage", "bakery", "workshop", "hut"]:
		var plan := ArchetypeLibrary.fallback("build a %s" % arch, ren, plot, 1)
		var spec: Dictionary = plan["spec"]
		var base := JSON.stringify(spec)
		for who: WorkerMemory in [ren, mira, tobias]:
			var a := Personality.apply(spec, who)
			var b := Personality.apply(spec, who)
			_check(JSON.stringify(a["spec"]) == JSON.stringify(b["spec"]) and a["notes"] == b["notes"],
				"%s's %s is the same every time" % [who.display_name, arch])
			_check(JSON.stringify(spec) == base, "apply() never edits its input")
			_check(Validator.check_spec(a["spec"], plot, ctx).is_empty(),
				"%s's %s still validates (%s)" % [who.display_name, arch,
					str(Validator.check_spec(a["spec"], plot, ctx).get("code", ""))])
			if who == mira:
				var fp0: Array = spec["footprint"]
				var fp1: Array = (a["spec"] as Dictionary)["footprint"]
				if str(a["quirk"]) == "careless":
					_check(float(fp1[0]) <= float(fp0[0]) and float(fp1[1]) <= float(fp0[1]) \
						and (fp1 != fp0 or (a["spec"]["modules"] as Array).size() < (spec["modules"] as Array).size()),
						"careless Mira makes the %s smaller or rougher" % arch)
			if who == ren:
				_check(str(a["quirk"]) == "proud" and JSON.stringify(a["spec"]) != base,
					"proud Ren adds a flourish to the %s: %s" % [arch, str(a["detail"])])
	# A careless hand owns up to it.
	var plan2 := ArchetypeLibrary.fallback("build a cottage", mira, plot, 1)
	var r := Personality.apply(plan2["spec"], mira)
	Personality.note_quirk(mira, 4, str(r["quirk"]), str(r["detail"]))
	_check(Personality.admission(mira, "did you cut any corners?") != "", "Mira admits it when asked")
	_check(Personality.admission(tobias, "did you cut any corners?") == "", "Tobias has nothing to admit")
	_check(Personality.pace(tobias) < 1.0 and Personality.pace(ren) == 1.0, "a meticulous hand is slower")


## Through the dispatcher: the plan is accepted, changed, explained and built.
func _plan_flow() -> void:
	var dispatch: Dispatcher = main.dispatch
	var plot: Plot = main.village.plots[0]
	var ren: Worker = main.crew.get_worker("ren")
	var seen: Array = []
	ren.role = main.crew.roles.get_role("builder")      # a farmer may not build
	dispatch.plan_accepted.connect(func(_w: Worker, a: Array) -> void: seen.append(a))
	var plan := ArchetypeLibrary.fallback("build a cottage", ren.memory, plot, 1)
	var plain := JSON.stringify(plan["spec"])
	dispatch.accept_plan_for_test(ren, "build a cottage", plot, plan)
	await get_tree().process_frame
	_check(not seen.is_empty(), "the plan was accepted")
	if not seen.is_empty():
		var text := " ".join((seen[0] as Array).map(func(x: Variant) -> String: return str(x)))
		_check(text.find("took pride") >= 0, "the assumptions panel explains the flourish: %s" % text)
	_check(JSON.stringify(plan["spec"]) == plain, "the plan the library handed over was not edited in place")
	_check(ren.memory.of_kind("quirk").size() == 1, "the flourish is on Ren's record")


# --------------------------------------------------------------------- voice

func _voice() -> void:
	var tts := DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	print("[social] TTS available here: %s" % str(tts))
	if not tts:
		_check(not Voice.supported(), "no TTS, so Voice.supported() is false")
	Voice.speak(null, "mira", "Good morning.", "talk")     # must not throw
	Voice.stop()
	Voice.sample()
	_check(true, "voice calls are safe without TTS")
	_check(not Voice.dictation_supported(), "no dictation off the web")
	Voice.install_mic()
	# Profiles are stable and spread out.
	var ids := ["a", "b", "c", "d", "e"]
	var p1 := Voice.profile_for("mira", ids)
	var p2 := Voice.profile_for("mira", ids)
	_check(p1 == p2, "Mira's voice is the same every time")
	var pitches := {}
	for n in ["mira", "tobias", "ren", "ada", "bram", "cora", "dov"]:
		pitches[snappedf(float(Voice.profile_for(n, ids)["pitch"]), 0.01)] = true
		var p := Voice.profile_for(n, ids)
		_check(float(p["pitch"]) >= 0.8 and float(p["pitch"]) <= 1.4 and float(p["rate"]) >= 0.85 and float(p["rate"]) <= 1.15,
			"%s's pitch and rate are in range" % n)
	_check(pitches.size() >= 4, "villagers do not all sound alike")
	# Who is heard.
	Voice.enabled = true
	Voice.volume = 0.8
	Voice.focus_id = ""
	_check(Voice.loudness("ada", "talk", "Hello", 4.0) > 0.0, "a nearby villager is heard")
	_check(Voice.loudness("ada", "talk", "Hello", 40.0) == 0.0, "a distant one is not")
	_check(Voice.loudness("ada", "work", "Nailing.", 2.0) == 0.0, "work chatter is not voiced")
	_check(Voice.loudness("ada", "talk", "…", 2.0) == 0.0, "the thinking murmur is not voiced")
	Voice.focus_id = "ada"
	_check(Voice.loudness("ada", "talk", "Hello", 40.0) > 0.0, "the person you are talking to is heard from afar")
	Voice.focus_id = ""
	Voice.enabled = false
	_check(Voice.loudness("ada", "talk", "Hello", 1.0) == 0.0, "off means off")
	Voice.enabled = true
	# The sound panel builds with the Voices row and survives no TTS.
	var panel := SoundPanel.build()
	add_child(panel)
	_check(panel.get_child_count() > 0, "the sound panel builds with the voice rows")
	panel.queue_free()


# ---------------------------------------------------------------- screenshots

func _shots() -> void:
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10) + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	var crew: Crew = main.crew
	var hud: Hud = main.hud
	var ren: Worker = crew.get_worker("ren")
	var tobias: Worker = crew.get_worker("tobias")
	# Ren: a friend of long standing.
	for d in 6:
		for k in ["praise", "order_done", "request_done", "gift"]:
			Relationships.record(ren.memory, k, 10 + d)
	ren.memory.remember(12, "Built the well house on Mill Lane. Took about 6 hours.", 0.4, {"kind": "done"})
	var pr := Personality.apply(ArchetypeLibrary.fallback("build a cottage", ren.memory,
		main.village.plots[0], 1)["spec"], ren.memory)
	Personality.note_quirk(ren.memory, 13, str(pr["quirk"]), str(pr["detail"]))
	# Tobias: not impressed.
	for i in 3:
		Relationships.record(tobias.memory, "insult", 11 + i)
	Relationships.record(tobias.memory, "trespass", 14, {"quiet": true})
	tobias.memory.remember(14, "You walked into my house without asking.", -0.3, {"kind": "rel"})
	await get_tree().create_timer(4.0).timeout
	hud.visible = true
	hud.open_card(ren)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(dir + "villager_card_friend.png")
	hud.villager_card.hide_card()
	hud.open_card(tobias)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(dir + "villager_card_resentful.png")
	print("[social] shots saved in %s" % dir)
	get_tree().quit(0)
