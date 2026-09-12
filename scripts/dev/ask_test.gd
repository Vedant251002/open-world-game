extends Node
class_name AskTest
## Can the crew answer a question, and are the answers true?
##
## Every case here has a known right answer sitting in the town's records, and
## the test is simply whether the worker says it. It runs the deterministic
## layer only — the model is never involved — because that is the layer that
## has to be right every time; the model's job is the questions this file has
## no pattern for.
##
## Run with:  godot --path . -- --asktest

var world: VoxelWorld
var village: Village
var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var player: Player
var farm: Farm
var livestock: Livestock

var _wait := 0.0
var _fails: Array[String] = []


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy() and _wait < 15.0:
		_wait += delta
		return
	set_process(false)
	_run()


func _ask(w: Worker, q: String) -> String:
	var a := Answers.reply(q, w, town, village, clock, player, farm, livestock)
	print("[ask] %-42s -> %s" % ["\"" + q + "\"", a if a != "" else "(nothing)"])
	return a


func _expect(q: String, a: String, needles: Array) -> void:
	for n: String in needles:
		if a.findn(n) < 0:
			_fails.append("\"%s\" should have mentioned \"%s\" — got: %s" % [q, n, a])


func _run() -> void:
	var w: Worker = crew.workers[0]

	# --- routing: what counts as a question ---
	for q: String in ["where is the bakery?", "how many bricks do we have",
			"what are you doing", "What did I ask you?", "do we have any glass",
			"tell me about the stores", "how much money is there"]:
		if not Answers.is_question(q):
			_fails.append("\"%s\" should be a question" % q)
	for q: String in ["can you build a hut", "could you fetch some stone",
			"build a bakery", "what about a tavern", "how about a store",
			"bring some hens", "wait here", "would you plant a field"]:
		if Answers.is_question(q):
			_fails.append("\"%s\" should be an order, not a question" % q)

	# --- the town: buildings that were here before the crew ---
	var a := _ask(w, "where is the bakery?")
	_expect("where is the bakery?", a, ["bakery", "row", "metres"])
	a = _ask(w, "who built the tavern?")
	_expect("who built the tavern?", a, ["before any of us"])
	a = _ask(w, "how many houses do we have?")
	_expect("how many houses do we have?", a, ["one", "hut", "low row"])
	a = _ask(w, "where is the forge?")
	_expect("where is the forge?", a, ["no forge"])
	a = _ask(w, "what have we built?")
	_expect("what have we built?", a, ["bakery", "tavern", "workshop"])

	# --- the stores, with the numbers the stores actually hold ---
	a = _ask(w, "how many bricks do we have?")
	_expect("how many bricks do we have?", a, [str(town.units_of("brick")), "nobody here can work"])
	a = _ask(w, "how much timber have we got")
	_expect("how much timber have we got", a, [str(town.units_of("timber")), "timber"])
	a = _ask(w, "how many iron do we have")
	_expect("how many iron do we have", a, ["none"])
	a = _ask(w, "how much stone is there?")
	_expect("how much stone is there?", a, [str(town.units_of("cobble")), "cobble"])
	a = _ask(w, "where does clay come from?")
	_expect("where does clay come from?", a, ["clay bank"])
	a = _ask(w, "what do we have?")
	_expect("what do we have?", a, ["timber", "coins"])

	# --- money, animals, time ---
	a = _ask(w, "how much money do we have?")
	_expect("how much money do we have?", a, [town.coin_line()])
	a = _ask(w, "how many hens are there?")
	_expect("how many hens are there?", a, [str(livestock.count_of("hen"))])
	a = _ask(w, "what day is it?")
	_expect("what day is it?", a, ["day %d" % clock.day])

	# --- memory: before and after an order ---
	a = _ask(w, "what did I ask you?")
	_expect("what did I ask you? (before)", a, ["not asked me"])
	a = _ask(w, "what are you doing?")
	_expect("what are you doing? (idle)", a, ["nothing"])

	var plot: Plot = null
	for p: Plot in village.plots:
		if p.occupied_by < 0 and not p.reserved:
			plot = p
			break
	w.start_thinking("build a big bakery with a chimney", plot)
	a = _ask(w, "what did I ask you?")
	_expect("what did I ask you? (after)", a, ["build a big bakery with a chimney",
		"working out"])
	a = _ask(w, "what are you doing?")
	_expect("what are you doing? (thinking)", a, ["bakery"])
	a = _ask(w, "where are you?")
	if a.find("beside you") < 0 and a.find("metres") < 0:
		_fails.append("\"where are you?\" should say how far — got: %s" % a)

	# A second order, and the first is still remembered behind it.
	w.stop_thinking()
	w._holding = false
	w.state = Worker.State.IDLE
	w.start_thinking("plant a wheat field", plot)
	a = _ask(w, "remind me what I told you")
	_expect("remind me what I told you", a, ["plant a wheat field", "big bakery"])

	# --- and a question nothing here can answer goes to the model ---
	a = _ask(w, "what do you think of the weather?")
	if a != "":
		_fails.append("an unanswerable question should fall through, got: %s" % a)

	for f: String in _fails:
		print("[ask] FAIL: %s" % f)
	print("[ask] === %s ===" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(0 if _fails.is_empty() else 1)
