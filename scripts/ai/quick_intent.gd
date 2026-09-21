extends Node
class_name QuickIntent
## The fast front door: a guess at the whole order, taken before the model is
## asked, and thrown away the moment it is not certain.
##
## This is the same bargain _try_gather already makes — "a shortcut rather than
## a translation: it produces the same step the model would have produced, and
## anything it is not certain about it declines and lets the model have" — with
## the word list replaced by a classifier that can be asked about wording it
## has never seen. "Nip over to the well" has no keyword in it and costs a
## round trip to the model today; it is one question to a classifier.
##
## What it is NOT is a second planner. It cannot describe a building, it cannot
## say a line out loud, and it cannot hold two jobs in one order, because a
## classifier picks from a list somebody wrote in advance and none of those are
## a list. Every one of those goes to the model untouched, which is why the
## model is still the thing that plans and this is only the thing that answers
## first when the answer is obvious.
##
## The rule that keeps it honest is the one the whole game is built on (pillar
## P3): half-hearing an order is worse than admitting you did not catch it. So
## it declines far more than it accepts — on a sentence with two clauses in it,
## on any verb whose fields cannot come out of a list, on a confidence below
## ACCEPT, and on every network failure there is. Declining costs nothing: the
## model was going to be asked anyway.

## Emitted for every order handed to submit(): a plan to run, or {} to say
## "not mine, ask the model". Exactly one of the two, always, or the worker
## would be left standing.
signal decided(worker_id: String, plan: Dictionary)

## No key, no account. That is the whole reason this is reachable from a
## browser build at all — the game's own proxy exists to hold a secret, and
## there is no secret here to hold.
const ENDPOINT := "https://classifier.dev/v1/classify"

## Short on purpose. The model is the fallback and it is already the slow path;
## a front door that takes two seconds to fail has made every order worse. If
## the answer is not back before a player would notice, it is not worth having.
const TIMEOUT := 3.0

## How sure it has to be before the order is taken out of the model's hands.
##
## High, and deliberately higher than it sounds. On the closest public test to
## this job — one intent out of seventy-seven, no training — this class of
## model is right about four times in five, and at its own "very sure" mark it
## is right about five times in six. One wrong order in six is not a fast path,
## it is a bug the player has to notice and correct. So the bar is set where
## almost everything falls through to the model, and what does not is the
## handful of orders nobody could misread.
const ACCEPT := 0.90
## The same bar, lower, for a field once the verb is already settled. Picking
## "sheep" out of seven animals is a much easier question than picking the verb
## out of twenty, and a wrong material is visible and correctable in a way a
## wrong verb is not.
const FIELD_ACCEPT := 0.70

## The label every dimension carries so it can say "that was not in the order".
## Without it the classifier must pick something, and a forced pick out of a
## list is where the confident wrong answers come from.
const NONE := "not_mentioned"
## The same escape on the verb itself.
const OTHER := "something_else"

## The verbs this may produce, and nothing else.
##
## The test for being on this list is not "is it a common order" but "can every
## field it needs come out of a list somebody wrote in advance". That is why
## build is missing (a building is described, not chosen), speak is missing (a
## line is written, not chosen), patrol is missing (an order of places is not a
## choice), and delegate and recruit are missing (both end in plain words meant
## for somebody else).
const SIMPLE := ["go", "follow", "wait", "rest", "station", "harvest", "collect",
	"water", "tend", "report", "fish", "hunt", "cook", "craft", "scout",
	"gather", "stock", "trade", "sow", "plant_tree", "level", "demolish",
	"decorate", "teach"]

## A sentence holding one of these is holding more than one job, and splitting
## it is not a thing a classifier does — it answers about the whole sentence at
## once. "Fence the top field and put the hens in it" would come back as one
## verb with the other half silently dropped, which is the exact failure the
## step list was built to end. Cheaper to never ask.
const SPLITS := [" and ", " then ", " after that", " once you", " when you",
	";", ",", " also ", " plus ", " & "]

var enabled := true
var calls_made := 0
var taken := 0          ## orders answered here
var passed := 0         ## orders handed to the model
var last_error := ""
var last_ms := 0

var _busy := {}         ## worker_id -> true


func available() -> bool:
	return enabled


## Take the order, or say you will not.
##
## Returns true when this has taken responsibility for the order and will emit
## `decided` — with a plan or with {}. Returns false when it has not looked at
## all, and the caller should go straight to the model.
func submit(instruction: String, worker_id: String, labels: Dictionary) -> bool:
	if not enabled or _busy.has(worker_id):
		return false
	var text := instruction.strip_edges()
	if text.length() < 2 or text.length() > 200:
		return false
	# Two jobs in one sentence, or something long enough to probably be two.
	var low := " %s " % text.to_lower()
	for s: String in SPLITS:
		if low.find(s) >= 0:
			return false

	var dims := _dimensions(labels)
	if dims.is_empty():
		return false

	_busy[worker_id] = true
	var started := Time.get_ticks_msec()
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_busy.erase(worker_id)
			last_ms = Time.get_ticks_msec() - started
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				# Every failure is the same failure: the model has it. A
				# browser that refuses the request on CORS grounds, a rate
				# limit, a timeout, the service being gone entirely — none of
				# them is worth a word to the player, because the order is
				# still about to be carried out.
				last_error = "http=%d result=%d" % [code, result]
				passed += 1
				decided.emit(worker_id, {})
				return
			last_error = ""
			var plan := _read(body.get_string_from_utf8(), labels)
			if plan.is_empty():
				passed += 1
			else:
				taken += 1
			decided.emit(worker_id, plan),
		CONNECT_ONE_SHOT)

	var payload := {
		"items": [text],
		"dimensions": dims,
		"tier": "fast",
	}
	calls_made += 1
	var err := http.request(ENDPOINT,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		_busy.erase(worker_id)
		last_error = "request=%d" % err
		passed += 1
		decided.emit(worker_id, {})
	return true


## The questions, all asked about the same sentence in one go.
##
## They are independent — the classifier does not know that "which animal" only
## matters when the verb turned out to be stock — so the cost of asking about a
## field that turns out to be irrelevant is one decision, and the saving is the
## second round trip that asking in two passes would need.
func _dimensions(labels: Dictionary) -> Dictionary:
	var verbs: Array = labels.get("verbs", [])
	if verbs.is_empty():
		return {}
	var dims := {
		"action": {
			"labels": verbs + [OTHER],
			"instructions": ("Which single job is this person being told to do?"
				+ " Answer %s if it is anything else, if it is more than one job,"
				+ " or if it is a question rather than an order.") % OTHER,
		},
	}
	_add(dims, "place", labels.get("places", []),
		"Which place is named as where to go or work? Buildings only.")
	_add(dims, "material", labels.get("materials", []),
		"Which material is being asked for?")
	_add(dims, "species", labels.get("species", []),
		"Which kind of animal is named?")
	_add(dims, "crop", labels.get("crops", []),
		"Which crop is named?")
	_add(dims, "direction", labels.get("directions", []),
		"Which compass direction is named?")
	_add(dims, "skill", labels.get("skills", []),
		"Which skill is being taught?")
	_add(dims, "trade_action", labels.get("trade_actions", []),
		"Is this a sale or a purchase?")
	_add(dims, "goods", labels.get("goods", []),
		"Which goods are being bought or sold?")
	_add(dims, "who", labels.get("who", []),
		"Which named person is being spoken about?")
	return dims


func _add(dims: Dictionary, name: String, options: Array, says: String) -> void:
	if options.is_empty():
		return
	dims[name] = {"labels": options + [NONE], "instructions": says}


## The reply, turned into a plan, or {} if anything at all is off.
func _read(raw: String, labels: Dictionary) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {}
	var top: Variant = json.data
	if not (top is Dictionary):
		return {}
	var results: Variant = (top as Dictionary).get("results", null)
	if not (results is Array) or (results as Array).is_empty():
		return {}
	var first: Variant = (results as Array)[0]
	if not (first is Dictionary):
		return {}
	var dims: Variant = (first as Dictionary).get("dimensions", null)
	if not (dims is Dictionary):
		return {}
	var d: Dictionary = dims

	var verb := _pick(d, "action", ACCEPT)
	if verb == "" or verb == OTHER or verb not in SIMPLE:
		return {}
	# The role may have been narrowed since the labels were built. Cheap to
	# check twice; the validator would refuse it anyway, but refusing here
	# means the model still gets its turn instead of the player getting a no.
	if verb not in (labels.get("verbs", []) as Array):
		return {}

	var step := {"do": verb}
	if not _fill(step, verb, d):
		return {}
	return {
		"kind": "plan",
		"steps": [step],
		"worker_line": "",
		# Said out loud so the shortcut is never invisible. A player who can
		# see which orders were taken on sight can tell you when one was taken
		# wrongly, and that is the only way this gets better.
		"assumptions": ["I knew that one without having to think it over."],
	}


## The fields for one verb, from the answers already in hand. False when a
## required one did not come back well enough to use — the model has it then,
## which is better than a confident guess at the wrong animal.
func _fill(step: Dictionary, verb: String, d: Dictionary) -> bool:
	match verb:
		"go", "station", "demolish", "decorate":
			var place := _pick(d, "place", FIELD_ACCEPT)
			if place == "" or place == NONE:
				return false
			step["place"] = place
		"gather":
			var m := _pick(d, "material", FIELD_ACCEPT)
			if m == "" or m == NONE:
				return false
			step["material"] = m
		"stock":
			var sp := _pick(d, "species", FIELD_ACCEPT)
			if sp == "" or sp == NONE:
				return false
			step["species"] = sp
		"scout":
			var dir := _pick(d, "direction", FIELD_ACCEPT)
			if dir == "" or dir == NONE:
				return false
			step["direction"] = dir
		"trade":
			var act := _pick(d, "trade_action", FIELD_ACCEPT)
			var kind := _pick(d, "goods", FIELD_ACCEPT)
			if act == "" or act == NONE or kind == "" or kind == NONE:
				return false
			step["action"] = act
			step["kind"] = kind
		"teach":
			var who := _pick(d, "who", FIELD_ACCEPT)
			var skill := _pick(d, "skill", FIELD_ACCEPT)
			if who == "" or who == NONE or skill == "" or skill == NONE:
				return false
			step["who"] = who
			step["skill"] = skill
		"sow":
			# The only optional field taken. A crop nobody named is the
			# dispatcher's default, which is what the model would have sent.
			var crop := _pick(d, "crop", FIELD_ACCEPT)
			if crop != "" and crop != NONE:
				step["crop"] = crop
	return true


## One answer, if it came back at or above the bar. "" for everything else,
## including a dimension the service did not answer at all.
func _pick(d: Dictionary, name: String, floor_at: float) -> String:
	var got: Variant = d.get(name, null)
	if not (got is Dictionary):
		return ""
	var g: Dictionary = got
	var label := str(g.get("label", ""))
	var conf := float(g.get("confidence", 0.0))
	if label == "" or conf < floor_at:
		return ""
	return label


## For the F3 panel: what this has been doing, in one line.
func describe() -> String:
	if not enabled:
		return "quick intent off"
	var total := calls_made if calls_made > 0 else 1
	return "quick intent: %d taken, %d passed on, %d%% taken, last %dms%s" % [
		taken, passed, int(100.0 * float(taken) / float(total)), last_ms,
		("  (" + last_error + ")") if last_error != "" else ""]
