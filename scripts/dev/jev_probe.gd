extends SceneTree
## Real orders, the real classifier, the real role questions.
##
## quick_test and role_questions_test prove what is done with an answer; this
## asks classifier.dev itself, so it says how much of the command traffic the
## classifier actually takes and whether what it takes is right. Each case is
## an order, the role it is given to, and the step it should become — or "" for
## an order the classifier must hand to the model.
##
##   godot4 --headless --path . --script res://scripts/dev/jev_probe.gd
##   (add -- --role=<id> --say="..." to try one order)

const CASES := [
	# role, order, the step wanted ("" = must go to the model)
	["farmer", "go to the well", {"do": "go", "place": "well"}],
	["farmer", "bring in the harvest", {"do": "harvest"}],
	["farmer", "water the crops", {"do": "water"}],
	["farmer", "sow some carrots", {"do": "sow", "crop": "carrot"}],
	["farmer", "plant a small wheat field", {"do": "sow", "crop": "wheat", "size": [5, 5]}],
	["farmer", "fetch a couple of sheep", {"do": "stock", "species": "sheep", "count": 2}],
	["farmer", "feed the animals", {"do": "tend"}],
	["farmer", "pick up the eggs", {"do": "collect"}],
	["farmer", "fence off a medium pen", {"do": "enclose", "size": [10, 10]}],
	["shepherd", "bring a dozen hens back", {"do": "stock", "species": "hen", "count": 12}],
	["cook", "work the oven for half a day", {"do": "cook", "hours": 4}],
	["cook", "sell some food at the market", {"do": "trade", "action": "sell", "kind": "food"}],
	["merchant", "buy in some timber", {"do": "trade", "action": "buy", "kind": "timber"}],
	["merchant", "how do the books stand? give me a report", {"do": "report"}],
	["hunter", "go hunting for a full day", {"do": "hunt", "hours": 8}],
	["hunter", "scout out to the north", {"do": "scout", "direction": "north"}],
	["fisher", "catch some fish", {"do": "fish"}],
	["forester", "plant a few trees", {"do": "plant_tree", "count": 3}],
	["woodcutter", "chop some timber", {"do": "gather", "material": "timber"}],
	["guard", "follow me", {"do": "follow"}],
	["guard", "stand guard at the well", {"do": "wait", "place": "well"}],
	["companion", "go home and rest", {"do": "rest"}],
	["road_builder", "lay a road from the well to the field", {"do": "pave", "from": "well", "to": "field"}],
	["landscaper", "decorate the front of the bakery", {"do": "decorate", "place": "bakery"}],
	["wrecker", "knock the bakery down", {"do": "demolish", "place": "bakery"}],
	["trainer", "teach Mira carpentry", {"do": "teach", "who": "Mira", "skill": "carpentry"}],
	# The model's, every one.
	["builder", "build a bakery with a big window", ""],
	["farmer", "fence the field and put the hens in it", ""],
	["cook", "don't go to the well", ""],
	["shepherd", "bring seven sheep", ""],
	["farmer", "what do you think of the weather", ""],
	["farmer", "sing me a song", ""],
	["guard", "patrol between the well and the gate", ""],
]

var _q: QuickIntent
var _got := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_q = QuickIntent.new()
	root.add_child(_q)
	_q.decided.connect(func(id: String, plan: Dictionary) -> void: _got[id] = plan)
	var book := RoleBook.new()

	var cases: Array = CASES
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--say="):
			var role := "builder"
			for b: String in OS.get_cmdline_user_args():
				if b.begins_with("--role="):
					role = b.substr(7)
			cases = [[role, a.substr(6), null]]

	var right := 0
	var taken := 0
	var wrong := 0
	var should := 0
	var t0 := Time.get_ticks_msec()
	for i in cases.size():
		var c: Array = cases[i]
		var role: Role = book.get_role(str(c[0]))
		var labels := _labels(role)
		var id := "w%d" % i
		var asked := _q.submit(str(c[1]), id, labels)
		var plan: Dictionary = {}
		if asked:
			while not _got.has(id):
				await process_frame
			plan = _got[id]
		var step: Dictionary = (plan.get("steps", [{}]) as Array)[0] if not plan.is_empty() else {}
		var want: Variant = c[2]
		var verdict := ""
		if want == null:
			verdict = "  ?? "
		elif want is String:
			verdict = "  ok " if step.is_empty() else " BAD "
			if step.is_empty():
				right += 1
			else:
				wrong += 1
		else:
			should += 1
			if step.is_empty():
				verdict = " miss"
			elif _same(step, want):
				verdict = "  ok "
				right += 1
			else:
				verdict = " BAD "
				wrong += 1
		if not step.is_empty():
			taken += 1
		print("%s %-12s %-46s -> %s%s" % [verdict, str(c[0]), "\"%s\"" % str(c[1]),
			str(step) if not step.is_empty() else "model",
			"" if asked else "  (not asked: guard)"])
		if verdict == " miss" and asked:
			print("        why: %s" % _why(_q.last_raw))
	print("\n[jev] %d orders, %d taken by the classifier, %d of %d it should take, %d wrong, %d right overall, %.1fs" % [
		cases.size(), taken, taken - wrong if taken >= wrong else 0, should, wrong, right,
		float(Time.get_ticks_msec() - t0) / 1000.0])
	print("[jev] %s" % _q.describe())
	quit(1 if wrong > 0 else 0)


## Each answer and how sure it was, in one line.
func _why(raw: String) -> String:
	var j: Variant = JSON.parse_string(raw)
	if not (j is Dictionary) or not ((j as Dictionary).get("results", []) as Array).size():
		return raw.substr(0, 200)
	var dims: Dictionary = j["results"][0].get("dimensions", {})
	var out: Array[String] = []
	for k: String in dims:
		out.append("%s=%s(%.2f)" % [k, str(dims[k].get("label", "")), float(dims[k].get("confidence", 0))])
	return " ".join(out)


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: String in b:
		if str(a.get(k, "")) != str(b[k]):
			return false
	return true


## What the dispatcher would hand over for this role in a small town with a
## bakery, a well and a field.
func _labels(role: Role) -> Dictionary:
	var qs := RoleQuestions.of(role)
	var verbs := RoleQuestions.verbs_in(qs, QuickIntent.SIMPLE)
	var places: Array = ["bakery", "store", "tavern"]
	for w: String in Steps.PLACE_WORDS:
		places.append(w)
	return {
		"questions": qs,
		"verbs": verbs,
		"places": places,
		"who": ["Mira", "Tobias", "Ren"],
		"materials": Array(VoxelTypes.names_for_tier(1)),
		"goods": Town.PRICE.keys(),
		"species": Steps.SPECIES.duplicate(),
		"crops": Steps.CROPS.duplicate(),
		"directions": Steps.DIRECTIONS.duplicate(),
		"skills": Steps.SKILLS.duplicate(),
		"trade_actions": Steps.TRADE_ACTIONS.duplicate(),
	}
