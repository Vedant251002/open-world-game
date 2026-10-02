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

## Long enough for the first call of a session, which is not the same as the
## rest. Measured in the running game: about two seconds once the town has
## settled, but four to six for the first order while the world is still
## streaming in — at three seconds every game's first order timed out here and
## went to the model. A failure costs this long before the model is asked, so
## it is no longer than the slow case needs.
const TIMEOUT := 8.0

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
##
## enclose and pave joined once a role's questions (RoleQuestions) gave size,
## width and gate a fixed scale to be picked from.
const SIMPLE := ["go", "follow", "wait", "rest", "station", "harvest", "collect",
	"water", "tend", "report", "fish", "hunt", "cook", "craft", "scout",
	"gather", "stock", "trade", "sow", "plant_tree", "level", "demolish",
	"decorate", "teach", "enclose", "pave"]

## A sentence holding one of these is holding more than one job, and splitting
## it is not a thing a classifier does — it answers about the whole sentence at
## once. "Fence the top field and put the hens in it" would come back as one
## verb with the other half silently dropped, which is the exact failure the
## step list was built to end. Cheaper to never ask.
const SPLITS := [" and ", " then ", " after that", " once you", " when you",
	";", ",", " also ", " plus ", " & "]

## Wording the classifier cannot carry into a one-verb step. A refusal ("don't
## go to the well") comes back as the verb it refuses, and a condition ("wait
## until noon") loses its condition; both would be carried out as the opposite
## of the order.
const HOLDS := [" not ", " dont ", " never ", " stop ", " no ", " cancel ", " nevermind ",
	" if ", " unless ", " until ", " till ", " instead ", " without ", " except ",
	" before ", " while ", " because "]

## Amounts the question scales cannot say exactly. "Sell 50 timber" would sell
## the nearest bucket, not 50, so these still go to the model untouched.
## Digits count as amounts too.
const AMOUNTS := ["four", "five", "seven", "eight", "nine", "ten", "eleven",
	"twenty", "thirty", "forty", "fifty", "hundred", "several", "all", "every",
	"everything", "minute", "minutes", "metres", "meters", "more"]
## Amounts a scale does say exactly — "a couple", "half a day", "a dozen". Let
## through only when the step that comes back has an amount field filled from
## them; otherwise the amount would be silently dropped.
const SCALE_WORDS := ["one", "two", "three", "six", "twelve", "dozen", "half",
	"couple", "few", "hour", "hours", "day", "days", "small", "big", "large",
	"little", "narrow", "wide", "far", "medium", "short", "long", "full"]

## Where the questions go. Overridable for the same reason the proxy URL is:
## the only honest way to test this whole path is to stand something in front
## of it that answers on demand, and a test that can only run against a live
## third-party service is a test that does not run.
##   --classifier=http://127.0.0.1:8899/v1/classify   or   CLASSIFIER_URL
var endpoint := ENDPOINT

var enabled := true
var calls_made := 0
var taken := 0          ## orders answered here
var passed := 0         ## orders handed to the model
var last_error := ""
var last_ms := 0
## The classifier's last reply, as sent — for working out why an order it was
## sure of went to the model anyway.
var last_raw := ""

var _busy := {}         ## worker_id -> true


func _ready() -> void:
	var from_env := OS.get_environment("CLASSIFIER_URL")
	if from_env != "":
		endpoint = from_env
	for a: String in args():
		if a.begins_with("--classifier="):
			endpoint = a.substr(13)


## Both halves of the command line.
##
## The game's own flags are passed after a bare `--`, which Godot keeps in
## get_cmdline_user_args() and leaves out of get_cmdline_args() — so a switch
## read from the wrong one is a switch that silently does nothing. That is not
## hypothetical: it is how this file shipped, and --noquick did nothing at all
## until a test ran the game and watched the override fail to apply.
static func args() -> PackedStringArray:
	var all := OS.get_cmdline_args()
	all.append_array(OS.get_cmdline_user_args())
	return all


func available() -> bool:
	return enabled and endpoint != ""


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

	# Words that change what the order means, or that ask for an amount this
	# cannot carry. Digits count as amounts.
	var plain := low
	for ch: String in [".", "!", "?", "\"", "'", "\u2019"]:
		plain = plain.replace(ch, "")
	plain = plain.replace("-", " ")
	for h: String in HOLDS:
		if plain.find(h) >= 0:
			return false
	var amount := false
	for word: String in plain.split(" ", false):
		if word in AMOUNTS or word.to_int() != 0 or word.contains("0"):
			return false
		if word in SCALE_WORDS:
			amount = true
	labels = labels.duplicate()
	labels["_amount"] = amount
	if not labels.has("questions"):
		labels["questions"] = _plain_questions(labels)

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
			last_raw = body.get_string_from_utf8()
			var plan := _read(last_raw, labels)
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
	var err := http.request(endpoint,
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
## They come from the role's own set (RoleQuestions): which of this person's
## jobs it is, worded for their trade, and one question per detail any of
## those jobs can carry. They are independent — the classifier does not know
## that "which animal" only matters when the job turned out to be stock — so
## the cost of a detail that turns out to be irrelevant is one decision, and
## the saving is the second round trip that asking in two passes would need.
func _dimensions(labels: Dictionary) -> Dictionary:
	var verbs: Array = labels.get("verbs", [])
	var qs: Dictionary = labels.get("questions", {})
	if verbs.is_empty() or qs.is_empty():
		return {}
	var meanings: Array[String] = []
	var fields: Array[String] = []
	for v: String in verbs:
		var e: Dictionary = (qs.get("verbs", {}) as Dictionary).get(v, {})
		meanings.append("%s = %s" % [v, str(e.get("means", v))])
		for f: Variant in e.get("fields", []):
			if str(f) not in fields:
				fields.append(str(f))
	var dims := {
		"action": {
			"labels": verbs + [OTHER],
			"instructions": "%s %s. Answer %s if it is anything else, if it is more than one job, or if it is a question rather than an order." % [
				str(qs.get("action_ask", "Which single job is this person being told to do?")),
				"; ".join(meanings), OTHER],
		},
	}
	for f: String in fields:
		var q: Dictionary = (qs.get("fields", {}) as Dictionary).get(f, {})
		var options := _distinct(RoleQuestions.options_for(qs, f, labels))
		if options.is_empty():
			continue
		dims[DIM + f] = {"labels": options + [NONE],
			"instructions": str(q.get("ask", "Which %s?" % f))}
	return dims


## A dimension name for a field, kept apart from "action" — trade has a field
## called action, and the two answers must not land on one key.
const DIM := "f_"
## classifier.dev takes up to a hundred labels a question, the escape included.
const MAX_LABELS := 99


static func _distinct(options: Array) -> Array:
	var out: Array = []
	for o: Variant in options:
		var s := str(o).strip_edges()
		if s != "" and s.length() <= 200 and s not in out:
			out.append(s)
		if out.size() >= MAX_LABELS:
			break
	return out


## A set for labels that came without one: the engine's plain wording over the
## verbs on offer. What a caller that predates role questions gets.
static func _plain_questions(labels: Dictionary) -> Dictionary:
	return RoleQuestions.template(Role.make("worker", "worker", labels.get("verbs", [])))


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
	if not labels.has("questions"):
		labels = labels.duplicate()
		labels["questions"] = _plain_questions(labels)

	var verb := _pick(d, "action", ACCEPT)
	if verb == "" or verb == OTHER or verb not in SIMPLE:
		return {}
	# The role may have been narrowed since the labels were built. Cheap to
	# check twice; the validator would refuse it anyway, but refusing here
	# means the model still gets its turn instead of the player getting a no.
	if verb not in (labels.get("verbs", []) as Array):
		return {}

	var step := {"do": verb}
	if not _fill(step, verb, d, labels):
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


## The fields for one verb, from the role's questions and the answers in hand.
## False when a required one did not come back well enough to use — the model
## has it then, which is better than a confident guess at the wrong animal —
## or when the order named an amount and nothing in the step carries it.
func _fill(step: Dictionary, verb: String, d: Dictionary, labels: Dictionary) -> bool:
	var qs: Dictionary = labels.get("questions", {})
	var e: Dictionary = (qs.get("verbs", {}) as Dictionary).get(verb, {})
	if e.is_empty():
		return false
	var required: Array = e.get("required", [])
	var carried_amount := false
	var said_amount := bool(labels.get("_amount", false))
	for f: Variant in e.get("fields", []):
		var field := str(f)
		# An amount nobody said is not an amount. The classifier will pick
		# "one" for "sell the bread" if asked how many; the step's own default
		# is what the player meant.
		if field in RoleQuestions.AMOUNT_FIELDS and not said_amount:
			if field in required:
				return false        # "fence a pen": how big is the model's to ask
			continue
		var options := _distinct(RoleQuestions.options_for(qs, field, labels))
		var got := _pick(d, DIM + field, FIELD_ACCEPT, options)
		if got == "" or got == NONE:
			if field in required:
				return false
			continue
		var value: Variant = RoleQuestions.value_of(qs, verb, field, got)
		if value == null:
			return false
		step[field] = value
		if field in RoleQuestions.AMOUNT_FIELDS:
			carried_amount = true
	if said_amount and not carried_amount:
		return false
	return true


## One answer, if it came back at or above the bar. "" for everything else,
## including a dimension the service did not answer at all.
func _pick(d: Dictionary, name: String, floor_at: float, options: Array = []) -> String:
	var got: Variant = d.get(name, null)
	if not (got is Dictionary):
		return ""
	var g: Dictionary = got
	var label := str(g.get("label", ""))
	var conf := float(g.get("confidence", 0.0))
	if label == "" or conf < floor_at:
		return ""
	# A label that was never on offer is the service making something up; it
	# would reach the validator as a refusal instead of going to the model.
	if not options.is_empty() and label != NONE and label not in options:
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
