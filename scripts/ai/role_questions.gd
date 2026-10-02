extends RefCounted
class_name RoleQuestions
## The questions the classifier is asked about every order a role is given.
##
## A role is written up once and then given orders for the rest of the game.
## The expensive part of understanding an order — knowing which of this
## person's jobs it is and which details that job needs — is the same every
## time, so it is worked out once, when the role is made, and kept with it.
## After that an order is a handful of multiple-choice questions to the
## classifier (QuickIntent), and the answers are turned into a step by this
## file, with no model in the loop.
##
## The shape of a set is fixed by the engine and the wording is the role's:
##
##   {
##     "v": 1,
##     "source": "template" | "model",
##     "action_ask": "Which of the cook's jobs is this order?",
##     "verbs":  {"cook": {"means": "bake or cook food at an oven",
##                         "fields": ["hours", "place"], "required": []}},
##     "fields": {"hours": {"ask": "How long is the shift?",
##                          "options": {"an hour": 1, ...},
##                          "clarify": "How long shall I work?"},
##                "place": {"ask": "Which building?", "from": "places",
##                          "clarify": "Where shall I do it?"}},
##   }
##
## Which verbs and fields appear, and what a field's answers may be, come from
## Steps and the town — never from a model. A model may only reword `means`,
## `ask` and `clarify` for its role (merge() drops everything else), so a set
## can never offer the classifier an answer the validator would refuse.

const VERSION := 1

## Verbs the classifier never takes, whatever the role. Each of them carries
## words rather than a choice — a building described, a line to say, an order
## for somebody else, a round of places in order — and a list cannot hold that.
const MODEL_ONLY := ["build", "speak", "patrol", "delegate", "recruit"]

## Fields filled from a list the town supplies at the moment of the order.
## The value is the key in the labels the dispatcher hands QuickIntent.
const FROM := {
	"place": "places", "from": "places", "to": "places",
	"material": "materials", "species": "species", "crop": "crops",
	"direction": "directions", "skill": "skills", "who": "who",
	"action": "trade_actions", "kind": "goods", "gate": "directions",
}

## Fields answered from a fixed scale: the label the classifier picks, and the
## value that goes into the step. Every value sits inside the validator's
## bounds for that field.
const SCALES := {
	"hours": {"an hour": 1, "a couple of hours": 2, "half a day": 4, "a full day": 8},
	"count": {"one": 1, "a couple": 2, "a few": 3, "half a dozen": 6, "a dozen": 12},
	"units": {"a little": 20, "a load": 60, "a big load": 150},
	"size": {"small": "small", "medium": "medium", "large": "large"},
	"width": {"narrow": 2, "ordinary": 3, "wide": 5},
	"distance": {"a short way": 40, "a fair way": 80, "a long way": 120},
}

## What "small", "medium" and "large" mean in metres, per verb — a small pen
## and a small field are not the same size. Inside Steps' bounds for each.
const SIZES := {
	"enclose": {"small": [6, 6], "medium": [10, 10], "large": [16, 16]},
	"sow": {"small": [5, 5], "medium": [8, 8], "large": [12, 12]},
	"level": {"small": [5, 5], "medium": [10, 10], "large": [16, 16]},
}

## The fields that carry an amount, for the guard that lets "a few" and "half a
## day" through only when the step has somewhere to put them.
const AMOUNT_FIELDS := ["hours", "count", "units", "size", "width", "distance"]

## The plain question for each field, before any role has reworded it.
const ASKS := {
	"place": "Which place is named as where to do it? A building or a spot in the town.",
	"from": "Where does the road start?",
	"to": "Where does the road go to?",
	"material": "Which material is named?",
	"species": "Which kind of animal is named?",
	"crop": "Which crop is named?",
	"direction": "Which compass direction is named?",
	"gate": "Which side is the gate to go on?",
	"skill": "Which skill is to be taught?",
	"who": "Which named person is it about?",
	"action": "Is this selling or buying?",
	"kind": "Which goods are being bought or sold?",
	"hours": "How long is it to be done for?",
	"count": "How many are asked for?",
	"units": "How much is asked for?",
	"size": "How big is it to be?",
	"width": "How wide is the road to be?",
	"distance": "How far out is it?",
}

const CLARIFY := {
	"place": "Where shall I do it?",
	"from": "Where should the road start?",
	"to": "And where should it go to?",
	"material": "What material do you want?",
	"species": "Which animals?",
	"crop": "Which crop?",
	"direction": "Which way?",
	"gate": "Which side for the gate?",
	"skill": "Which skill shall I teach?",
	"who": "Who do you mean?",
	"action": "Selling or buying?",
	"kind": "Which goods?",
	"hours": "For how long?",
	"count": "How many?",
	"units": "How much?",
	"size": "How big?",
	"width": "How wide?",
	"distance": "How far?",
}


## Whether a field can be answered by the classifier at all.
static func classifiable(field: String) -> bool:
	return FROM.has(field) or SCALES.has(field)


## The set for a role, built from the engine alone. This is what every preset
## ships with and what a role gets the moment it exists; a model only ever
## rewords it.
static func template(role: Role) -> Dictionary:
	var verbs := {}
	var fields := {}
	var caps: Array = role.ready_capabilities() if role != null else []
	for cap: String in caps:
		var verb := cap
		if verb in MODEL_ONLY or not Steps.VERBS.has(verb):
			continue
		var e: Dictionary = Steps.VERBS[verb]
		if bool(e.get("instant", false)) or bool(e.get("anyone", false)):
			continue
		var required: Array = []
		var ok := true
		for f: String in e.get("required", []):
			if not classifiable(f):
				ok = false
				break
			required.append(f)
		if not ok:
			continue
		var use: Array = required.duplicate()
		for f2: String in e.get("optional", []):
			if classifiable(f2) and f2 not in use:
				use.append(f2)
		verbs[verb] = {
			"means": str(e.get("says", Capabilities.says(verb))),
			"fields": use,
			"required": required,
		}
		for f3: String in use:
			if fields.has(f3):
				continue
			var q := {"ask": str(ASKS.get(f3, "Which %s?" % f3)),
				"clarify": str(CLARIFY.get(f3, "Which %s?" % f3))}
			if FROM.has(f3):
				q["from"] = FROM[f3]
			else:
				q["options"] = (SCALES[f3] as Dictionary).duplicate()
			fields[f3] = q
	var name := role.name if role != null else "worker"
	return {
		"v": VERSION,
		"source": "template",
		"action_ask": "Which single job is this %s being told to do?" % name,
		"verbs": verbs,
		"fields": fields,
	}


## The set this role has, building the template the first time it is asked
## for — presets, and roles saved before sets existed, start with none.
static func of(role: Role) -> Dictionary:
	if role == null:
		return {}
	if role.questions.is_empty() or int(role.questions.get("v", 0)) != VERSION:
		role.questions = template(role)
	return role.questions


## A model's rewording laid over the template. Only the three wording keys are
## taken, only for verbs and fields the template already has, and only as
## short plain strings — anything else in the reply is ignored, so the set's
## structure is always the engine's.
static func merge(base: Dictionary, raw: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var took := 0
	var ask := _clean(raw.get("action_ask", ""))
	if ask != "":
		out["action_ask"] = ask
		took += 1
	var rv: Variant = raw.get("verbs", {})
	if rv is Dictionary:
		for verb: Variant in rv:
			var v := str(verb)
			if not (out["verbs"] as Dictionary).has(v) or not (rv[verb] is Dictionary):
				continue
			var means := _clean((rv[verb] as Dictionary).get("means", ""))
			if means != "":
				out["verbs"][v]["means"] = means
				took += 1
	var rf: Variant = raw.get("fields", {})
	if rf is Dictionary:
		for field: Variant in rf:
			var f := str(field)
			if not (out["fields"] as Dictionary).has(f) or not (rf[field] is Dictionary):
				continue
			for key: String in ["ask", "clarify"]:
				var s := _clean((rf[field] as Dictionary).get(key, ""))
				if s != "":
					out["fields"][f][key] = s
					took += 1
	if took > 0:
		out["source"] = "model"
	return out


static func _clean(v: Variant) -> String:
	if not (v is String):
		return ""
	var s := (v as String).strip_edges().replace("\n", " ")
	return s.substr(0, 180) if s.length() > 180 else s


## The verbs this set can take, narrowed to the ones on offer right now.
static func verbs_in(qs: Dictionary, allowed: Array) -> Array:
	var out: Array = []
	for v: Variant in (qs.get("verbs", {}) as Dictionary):
		if allowed.is_empty() or v in allowed:
			out.append(str(v))
	return out


## The labels a field offers: the town's list, or the scale's words.
static func options_for(qs: Dictionary, field: String, lists: Dictionary) -> Array:
	var q: Dictionary = (qs.get("fields", {}) as Dictionary).get(field, {})
	if q.is_empty():
		return []
	if q.has("from"):
		return (lists.get(str(q["from"]), []) as Array).duplicate()
	return (q.get("options", {}) as Dictionary).keys()


## The value a picked label puts into the step.
static func value_of(qs: Dictionary, verb: String, field: String, label: String) -> Variant:
	var q: Dictionary = (qs.get("fields", {}) as Dictionary).get(field, {})
	if q.has("from"):
		return label
	var v: Variant = (q.get("options", {}) as Dictionary).get(label, null)
	if field == "size":
		return (SIZES.get(verb, SIZES["level"]) as Dictionary).get(str(v), null)
	return v


# -------------------------------------------------------------- the model's turn

## The one call made when a role is written up: the template, and a request to
## put it in this role's words.
static func prompt_system() -> String:
	return """You write the questions a fast multiple-choice classifier is asked about every order given to one worker in a small medieval town.

The classifier reads the player's order and must pick:
  1. which of this worker's jobs the order is (from the verbs listed), then
  2. an answer to each field question for that job, from a fixed list.

You are given the jobs and fields. Rewrite them in words that fit THIS worker, so the classifier picks well:
- "action_ask": one question asking which job the order is, naming the worker's trade.
- "verbs".<verb>."means": what that job means for this worker, with the everyday words a player would use for it (at most 20 words). Make jobs that could be confused clearly different.
- "fields".<field>."ask": the question the classifier answers about the order for that field (at most 20 words).
- "fields".<field>."clarify": what the worker says out loud, in character, when they need the player to tell them that field (at most 12 words).

Use only the verbs and fields you are given. Do not add options, verbs or fields.
Reply with JSON only, no prose:
{"kind": "questions", "action_ask": "...", "verbs": {"<verb>": {"means": "..."}}, "fields": {"<field>": {"ask": "...", "clarify": "..."}}}"""


static func prompt_user(role: Role, qs: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("WORKER: the town's %s" % role.name)
	if role.description != "":
		lines.append("ABOUT: %s" % role.description)
	if role.character != "":
		lines.append("CHARACTER: %s" % role.character)
	lines.append("")
	lines.append("JOBS:")
	for verb: String in (qs.get("verbs", {}) as Dictionary):
		var v: Dictionary = qs["verbs"][verb]
		lines.append("- %s: %s (fields: %s)" % [verb, str(v["means"]),
			", ".join(v["fields"]) if not (v["fields"] as Array).is_empty() else "none"])
	lines.append("")
	lines.append("FIELDS:")
	for field: String in (qs.get("fields", {}) as Dictionary):
		var f: Dictionary = qs["fields"][field]
		var answers := "one of the town's %s" % str(f["from"]) if f.has("from") \
			else ", ".join((f.get("options", {}) as Dictionary).keys())
		lines.append("- %s: %s  (answers: %s)" % [field, str(f["ask"]), answers])
	return "\n".join(lines)
