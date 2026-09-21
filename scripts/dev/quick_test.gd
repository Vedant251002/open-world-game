extends SceneTree
## What the front door does with an answer, without asking anybody.
##
## Every case here is a reply the classifier could actually send, and the thing
## being checked is almost always that the order was NOT taken — because that
## is the behaviour the whole design rests on. A front door that accepts too
## much is worse than no front door, and the only way to know which one this is
## is to write down what it must refuse.
##
## No network and no world: this is the parsing and the bars, which is where a
## wrong order would come from. Run it with
##   godot4 --headless --path . --script res://scripts/dev/quick_test.gd

var failures := 0


func _init() -> void:
	var q := QuickIntent.new()

	var labels := {
		"verbs": ["go", "stock", "trade", "gather", "scout", "teach", "sow"],
		"places": ["bakery", "well", "field"],
		"materials": ["timber", "stone"],
		"species": ["hen", "sheep"],
		"crops": ["wheat", "carrot"],
		"directions": ["north", "south"],
		"skills": ["carpentry", "masonry"],
		"trade_actions": ["sell", "buy"],
		"goods": ["timber", "food"],
		"who": ["Mira"],
	}

	# --- what it should take ------------------------------------------------
	_step("a sure errand", q, _reply({
		"action": ["go", 0.97], "place": ["bakery", 0.95]}), labels,
		{"do": "go", "place": "bakery"})
	_step("a sure flock order", q, _reply({
		"action": ["stock", 0.95], "species": ["sheep", 0.88]}), labels,
		{"do": "stock", "species": "sheep"})
	_step("a sale with both halves", q, _reply({
		"action": ["trade", 0.93], "trade_action": ["sell", 0.9],
		"goods": ["timber", 0.85]}), labels,
		{"do": "trade", "action": "sell", "kind": "timber"})
	_step("a lesson", q, _reply({
		"action": ["teach", 0.94], "who": ["Mira", 0.9],
		"skill": ["carpentry", 0.88]}), labels,
		{"do": "teach", "who": "Mira", "skill": "carpentry"})
	# An optional field left out is not a reason to refuse: the dispatcher's
	# own default is exactly what the model would have sent.
	_step("sowing with no crop named", q, _reply({
		"action": ["sow", 0.95], "crop": [QuickIntent.NONE, 0.99]}), labels,
		{"do": "sow"})

	# --- what it must hand over --------------------------------------------
	_pass("an unsure verb", q, _reply({"action": ["go", 0.80],
		"place": ["bakery", 0.99]}), labels)
	_pass("the escape label", q, _reply({"action": [QuickIntent.OTHER, 0.99]}), labels)
	_pass("a verb it may not produce", q, _reply({"action": ["build", 0.99]}), labels)
	_pass("a verb outside this role", q, _reply({"action": ["demolish", 0.99]}),
		{"verbs": ["go"], "places": ["bakery"]})
	_pass("a place nobody named", q, _reply({"action": ["go", 0.99],
		"place": [QuickIntent.NONE, 0.99]}), labels)
	_pass("an unsure place", q, _reply({"action": ["go", 0.99],
		"place": ["bakery", 0.5]}), labels)
	_pass("half a sale", q, _reply({"action": ["trade", 0.99],
		"trade_action": ["sell", 0.95]}), labels)
	_pass("an animal nobody named", q, _reply({"action": ["stock", 0.99],
		"species": [QuickIntent.NONE, 0.99]}), labels)
	_pass("nonsense", q, "not json at all", labels)
	_pass("an empty reply", q, "{}", labels)
	_pass("no results", q, '{"results": []}', labels)
	_pass("no dimensions", q, '{"results": [{}]}', labels)

	# --- the guard that never asks at all ----------------------------------
	# Two jobs in one sentence is the failure the step list exists to prevent.
	# It must not even reach the classifier, because the classifier answers
	# about the whole sentence and would drop half of it with confidence.
	for s: String in ["fence the top field and put the hens in it",
			"go to the well, then come back",
			"chop timber and bring it here"]:
		if q.submit(s, "w1", labels):
			_fail("took a two-part order: \"%s\"" % s)
		else:
			print("  ok   handed over unasked: \"%s\"" % s)
	# And nothing at all to go on.
	if q.submit("x", "w1", {}):
		_fail("took an order with no labels to choose from")
	else:
		print("  ok   handed over with no labels")

	q.free()
	print("\n[quick] %s" % ("all good" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## One reply, in the shape classifier.dev actually sends.
func _reply(dims: Dictionary) -> String:
	var out := {}
	for k: String in dims:
		var pair: Array = dims[k]
		out[k] = {"label": pair[0], "confidence": pair[1], "model": "jev"}
	return JSON.stringify({"results": [{"dimensions": out}]})


func _step(what: String, q: QuickIntent, raw: String, labels: Dictionary,
		want: Dictionary) -> void:
	var plan: Dictionary = q._read(raw, labels)
	var steps: Array = plan.get("steps", [])
	if steps.is_empty():
		_fail("%s: handed over, should have been taken" % what)
		return
	var got: Dictionary = steps[0]
	for k: String in want:
		if str(got.get(k, "")) != str(want[k]):
			_fail("%s: %s was \"%s\", wanted \"%s\"" % [what, k,
				str(got.get(k, "")), str(want[k])])
			return
	if got.size() != want.size():
		_fail("%s: extra fields: %s" % [what, str(got)])
		return
	print("  ok   took %s -> %s" % [what, str(got)])


func _pass(what: String, q: QuickIntent, raw: String, labels: Dictionary) -> void:
	var plan: Dictionary = q._read(raw, labels)
	if not plan.is_empty():
		_fail("%s: was taken, should have gone to the model: %s" % [what, str(plan)])
		return
	print("  ok   handed over %s" % what)


func _fail(line: String) -> void:
	failures += 1
	print("  FAIL %s" % line)
