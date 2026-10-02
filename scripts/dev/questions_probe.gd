extends SceneTree
## The model writing a role's questions, live, and what that does to the
## classifier.
##
## For each role: the one call that rewords its question set, the set it comes
## back as, and then the same orders put to classifier.dev twice — once with
## the engine's plain wording and once with the role's own — so the effect of
## the rewording is a number rather than a hope.
##
##   godot4 --headless --path . --script res://scripts/dev/questions_probe.gd

const ROLES := {
	"woodcutter": ["chop some timber", "fell a few trees for wood", "go to the well"],
	"guard": ["stand guard at the well", "follow me", "keep watch by the bakery for a couple of hours"],
	"merchant": ["give me a report", "sell some food", "buy in some timber"],
	"cook": ["work the oven for half a day", "bake some bread", "go to the tavern"],
}

## A role the player made up, the way the game makes it: name, description,
## capabilities as the role composer would pick them.
const CUSTOM := {"id": "baker", "name": "baker",
	"about": "Bakes bread and pies at the oven and sells them at the store.",
	"caps": ["cook", "trade", "station", "go", "wait", "speak"],
	"orders": ["bake some pies", "sell the bread", "work the counter at the store", "knead dough for a full day"]}

var _llm: LLM
var _q: QuickIntent
var _sets := {}
var _got := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_llm = LLM.new()
	root.add_child(_llm)
	_q = QuickIntent.new()
	root.add_child(_q)
	_q.decided.connect(func(id: String, plan: Dictionary) -> void: _got[id] = plan)
	_llm.questions_ready.connect(func(key: String, raw: Dictionary) -> void: _sets[key] = raw)
	await process_frame
	print("[q] model: %s" % _llm.describe() if _llm.has_method("describe") else "[q] model: %s %s" % [_llm.provider, _llm.model])

	var book := RoleBook.new()
	var roles: Array[Role] = []
	for id: String in ROLES:
		roles.append(book.get_role(id))
	var custom := Role.make(CUSTOM["id"], CUSTOM["name"], CUSTOM["caps"], CUSTOM["about"])
	custom.character = "You are the town's baker. You are up before dawn and you judge a day by the bread."
	roles.append(custom)

	var plain_taken := 0
	var own_taken := 0
	var orders := 0
	var failed := 0
	for role: Role in roles:
		var base := RoleQuestions.template(role)
		var t0 := Time.get_ticks_msec()
		_llm.compose_questions(role.id, role, base)
		while not _sets.has(role.id):
			await process_frame
		var raw: Dictionary = _sets[role.id]
		var ms := Time.get_ticks_msec() - t0
		if raw.is_empty():
			failed += 1
			print("\n[q] %s: the call failed (%s), template kept" % [role.name, _llm.last_error])
		var own := RoleQuestions.merge(base, raw)
		print("\n[q] === %s  (%s, %dms)" % [role.name, own["source"], ms])
		print("     ask: %s" % own["action_ask"])
		for v: String in own["verbs"]:
			print("     %-10s %s" % [v, own["verbs"][v]["means"]])
		for f: String in own["fields"]:
			print("     [%s] %s  /  says: %s" % [f, own["fields"][f]["ask"], own["fields"][f]["clarify"]])
		var list: Array = ROLES.get(role.id, CUSTOM["orders"])
		for order: String in list:
			orders += 1
			var a := await _ask(order, role, base)
			var b := await _ask(order, role, own)
			if not a.is_empty():
				plain_taken += 1
			if not b.is_empty():
				own_taken += 1
			print("     \"%s\"\n        plain: %s\n        own:   %s" % [order,
				str(a) if not a.is_empty() else "model", str(b) if not b.is_empty() else "model"])
	print("\n[q] %d orders: plain wording took %d, the roles' own wording took %d; %d of %d calls failed" % [
		orders, plain_taken, own_taken, failed, roles.size()])
	quit(1 if failed == roles.size() else 0)


var _n := 0


func _ask(order: String, role: Role, qs: Dictionary) -> Dictionary:
	_n += 1
	var id := "p%d" % _n
	var labels := {
		"questions": qs,
		"verbs": RoleQuestions.verbs_in(qs, QuickIntent.SIMPLE),
		"places": ["bakery", "store", "tavern", "well", "field", "home", "gate"],
		"who": ["Mira", "Tobias"],
		"materials": Array(VoxelTypes.names_for_tier(1)),
		"goods": Town.PRICE.keys(),
		"species": Steps.SPECIES.duplicate(), "crops": Steps.CROPS.duplicate(),
		"directions": Steps.DIRECTIONS.duplicate(), "skills": Steps.SKILLS.duplicate(),
		"trade_actions": Steps.TRADE_ACTIONS.duplicate(),
	}
	if not _q.submit(order, id, labels):
		return {}
	while not _got.has(id):
		await process_frame
	var plan: Dictionary = _got[id]
	return (plan.get("steps", [{}]) as Array)[0] if not plan.is_empty() else {}
