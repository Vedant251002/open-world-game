extends SceneTree
## A role's classifier questions: built right, kept right, read right.
##
## Three things are checked, all without a network:
##   - every role the game ships with gets a set, and every step that set can
##     produce passes the validator — so the classifier is never offered an
##     answer that would be refused;
##   - a model's rewording can change the words and nothing else, and the set
##     survives a save;
##   - an order with an amount in it is only taken when the amount lands in
##     the step.
## Run it with
##   godot4 --headless --path . --script res://scripts/dev/role_questions_test.gd

var failures := 0

var LISTS := {
	"places": ["bakery", "well", "field"],
	"materials": ["timber", "stone"],
	"species": ["hen", "sheep"],
	"crops": ["wheat", "carrot"],
	"directions": ["north", "south", "east", "west"],
	"skills": ["carpentry", "masonry"],
	"trade_actions": ["sell", "buy"],
	"goods": ["timber", "food"],
	"who": ["Mira"],
}


func _init() -> void:
	# The town's real names, as the dispatcher would hand them over.
	LISTS["materials"] = Array(VoxelTypes.names_for_tier(1)).filter(
		func(m: String) -> bool: return Resources.gatherable(m)).slice(0, 3)
	print("  materials offered: %s" % str(LISTS["materials"]))
	_every_role_has_a_valid_set()
	_model_words_only()
	_saved_with_the_role()
	_scales_into_steps()
	_amount_guard()
	print("\n[role-questions] %s" % ("all good" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## Every preset and both built-ins: a set, no verb the classifier must never
## take, and every verb's every answer validated as a real step.
func _every_role_has_a_valid_set() -> void:
	var book := RoleBook.new()
	var steps_checked := 0
	for id: String in book.roles:
		var role: Role = book.roles[id]
		var qs := RoleQuestions.of(role)
		if qs.is_empty() or int(qs.get("v", 0)) != RoleQuestions.VERSION:
			_fail("%s: no question set" % id)
			continue
		for verb: String in qs["verbs"]:
			if verb in RoleQuestions.MODEL_ONLY:
				_fail("%s: offers %s, which only the model can fill" % [id, verb])
			if not role.can(verb):
				_fail("%s: offers %s, which the role cannot do" % [id, verb])
			var e: Dictionary = qs["verbs"][verb]
			for f: String in e["fields"]:
				if not (qs["fields"] as Dictionary).has(f):
					_fail("%s/%s: field %s has no question" % [id, verb, f])
			# Each field at each of its answers, one at a time, with the
			# required ones filled — the validator must accept every one.
			var base := {"do": verb}
			for r: String in e["required"]:
				var opts := RoleQuestions.options_for(qs, r, LISTS)
				base[r] = RoleQuestions.value_of(qs, verb, r, str(opts[0]))
			var ctx := {"tier": 9, "role": role}
			steps_checked += _validate(id, base, ctx)
			for f2: String in e["fields"]:
				for label: Variant in RoleQuestions.options_for(qs, f2, LISTS):
					var st := base.duplicate()
					st[f2] = RoleQuestions.value_of(qs, verb, f2, str(label))
					steps_checked += _validate(id, st, ctx)
		# What every role must be able to take from the classifier.
		for must: String in ["go", "wait"]:
			if role.can(must) and not (qs["verbs"] as Dictionary).has(must):
				_fail("%s: can %s but has no question for it" % [id, must])
	print("  ok   %d roles, %d steps validated" % [book.roles.size(), steps_checked])


func _validate(id: String, step: Dictionary, ctx: Dictionary) -> int:
	# Place names are resolved by the dispatcher against the live town, not
	# by the validator; everything else is checked here exactly as a plan is.
	var err := Validator.check_step(step, {}, null, ctx)
	if not err.is_empty():
		_fail("%s: %s refused: %s" % [id, str(step), str(err.get("code", err))])
	return 1


func _model_words_only() -> void:
	var role := RoleBook.new().get_role("farmer")
	var base := RoleQuestions.template(role)
	var raw := {
		"kind": "questions",
		"action_ask": "Which of the farmer's jobs is it?",
		"verbs": {
			"sow": {"means": "plough and plant a field, put seed in", "fields": ["evil"]},
			"build": {"means": "put up a barn"},          # not the farmer's
		},
		"fields": {
			"crop": {"ask": "Which crop is to be sown?", "clarify": "Wheat or carrots, then?",
				"options": {"gold": 1}},
			"nonsense": {"ask": "?"},
		},
		"extra": "ignored",
	}
	var got := RoleQuestions.merge(base, raw)
	_check(got["source"] == "model", "rewording marks the set as the model's")
	_check(got["action_ask"] == "Which of the farmer's jobs is it?", "action question reworded")
	_check(str(got["verbs"]["sow"]["means"]).begins_with("plough and plant"), "a job reworded")
	_check(got["verbs"]["sow"]["fields"] == base["verbs"]["sow"]["fields"],
		"a job's fields are the engine's, not the model's")
	_check(not (got["verbs"] as Dictionary).has("build"), "no job added by the model")
	_check(not (got["fields"] as Dictionary).has("nonsense"), "no field added by the model")
	_check(got["fields"]["crop"]["clarify"] == "Wheat or carrots, then?", "clarify reworded")
	_check(got["fields"]["crop"].get("from", "") == "crops"
		and not (got["fields"]["crop"] as Dictionary).has("options"),
		"a field's answers are the engine's, not the model's")
	var nothing := RoleQuestions.merge(base, {"kind": "questions", "verbs": 5})
	_check(nothing["source"] == "template", "a useless reply leaves the template as it was")


func _saved_with_the_role() -> void:
	var role := Role.make("baker", "baker", ["cook", "trade", "go", "wait"], "bakes")
	role.source = "model"
	role.questions = RoleQuestions.merge(RoleQuestions.template(role),
		{"verbs": {"cook": {"means": "bake bread at the oven"}}})
	var back := Role.from_dict(JSON.parse_string(JSON.stringify(role.to_dict())))
	_check(str(back.questions.get("verbs", {}).get("cook", {}).get("means", "")) == "bake bread at the oven",
		"the set survives a save and a load")
	var old := Role.from_dict({"id": "x", "name": "x", "capabilities": ["go"]})
	_check(old.questions.is_empty() and not RoleQuestions.of(old).is_empty(),
		"a role saved before sets existed gets one when first asked")


## Scales turn a picked word into the number the step needs.
func _scales_into_steps() -> void:
	var q := QuickIntent.new()
	var role := Role.make("hand", "hand", ["stock", "cook", "enclose", "sow", "go"])
	var labels := LISTS.duplicate()
	labels["verbs"] = ["stock", "cook", "enclose", "sow", "go"]
	labels["questions"] = RoleQuestions.template(role)
	labels["_amount"] = true
	_take(q, "a dozen hens", labels, {"action": ["stock", 0.97],
		"f_species": ["hen", 0.95], "f_count": ["a dozen", 0.9]},
		{"do": "stock", "species": "hen", "count": 12})
	_take(q, "half a day at the oven", labels, {"action": ["cook", 0.97],
		"f_hours": ["half a day", 0.9], "f_place": [QuickIntent.NONE, 0.9]},
		{"do": "cook", "hours": 4})
	_take(q, "a medium pen", labels, {"action": ["enclose", 0.97],
		"f_size": ["medium", 0.9]}, {"do": "enclose", "size": [10, 10]})
	_take(q, "a small field of carrots", labels, {"action": ["sow", 0.97],
		"f_size": ["small", 0.9], "f_crop": ["carrot", 0.9]},
		{"do": "sow", "size": [5, 5], "crop": "carrot"})
	_check(q._read(_reply({"action": ["enclose", 0.97], "f_size": [QuickIntent.NONE, 0.9]}),
		labels).is_empty(), "a pen with no size goes to the model")
	labels["_amount"] = false
	_check(q._read(_reply({"action": ["enclose", 0.97], "f_size": ["medium", 0.9]}),
		labels).is_empty(), "a pen with no size said goes to the model, not a guessed size")
	_take(q, "sell the bread (no amount said)", labels.merged({"verbs": ["stock"]}, true),
		{"action": ["stock", 0.97], "f_species": ["hen", 0.95], "f_count": ["one", 0.9]},
		{"do": "stock", "species": "hen"})
	# The dimensions offer this role's jobs and nothing else.
	var dims := q._dimensions(labels)
	_check((dims["action"]["labels"] as Array) == ["stock", "cook", "enclose", "sow", "go",
		QuickIntent.OTHER], "the action question offers exactly the role's jobs")
	_check(str(dims["action"]["instructions"]).find("cook = ") >= 0,
		"each job's meaning goes to the classifier")
	_check(dims.has("f_count") and not dims.has("f_skill"),
		"a field is asked only when one of the jobs carries it")
	q.free()


## "A few hens" is fine when the count lands; an amount nothing carries is not.
func _amount_guard() -> void:
	var q := QuickIntent.new()
	var labels := LISTS.duplicate()
	labels["verbs"] = ["stock", "go"]
	labels["questions"] = RoleQuestions.template(Role.make("h", "h", ["stock", "go"]))
	labels["_amount"] = true
	_check(q._read(_reply({"action": ["go", 0.97], "f_place": ["well", 0.95]}),
		labels).is_empty(), "an amount said to a job with nowhere to put it goes to the model")
	_check(q._read(_reply({"action": ["stock", 0.97], "f_species": ["hen", 0.95],
		"f_count": [QuickIntent.NONE, 0.9]}), labels).is_empty(),
		"an amount the classifier did not catch goes to the model")
	_check(not q._read(_reply({"action": ["stock", 0.97], "f_species": ["hen", 0.95],
		"f_count": ["a few", 0.9]}), labels).is_empty(), "an amount that lands is taken")
	q.free()


func _take(q: QuickIntent, what: String, labels: Dictionary, dims: Dictionary,
		want: Dictionary) -> void:
	var plan: Dictionary = q._read(_reply(dims), labels)
	var steps: Array = plan.get("steps", [])
	if steps.is_empty():
		_fail("%s: handed over, should have been taken" % what)
		return
	var got: Dictionary = steps[0]
	if JSON.stringify(got) != JSON.stringify(want) and str(got) != str(want):
		_fail("%s: got %s, wanted %s" % [what, str(got), str(want)])
		return
	print("  ok   took %s -> %s" % [what, str(got)])


func _reply(dims: Dictionary) -> String:
	var out := {}
	for k: String in dims:
		var pair: Array = dims[k]
		out[k] = {"label": pair[0], "confidence": pair[1], "model": "jev"}
	return JSON.stringify({"results": [{"dimensions": out}]})


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_fail(what)


func _fail(line: String) -> void:
	failures += 1
	print("  FAIL %s" % line)
