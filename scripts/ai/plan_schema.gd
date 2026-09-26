extends RefCounted
class_name PlanSchema
## The plan, as a JSON Schema the gateway can hold the model to.
##
## Generated from Steps and Vocabulary rather than written out, for the same
## reason the prompt is: three descriptions of the same shape drift, and the
## one that drifts silently is the one nobody reads. Add a verb to Steps.VERBS
## and it appears here, in the prompt, and in the validator, or in none of them.
##
## What this buys, precisely: a gateway with constrained decoding cannot emit a
## token that breaks the schema, so the reply always parses. That is aimed at
## the specific failure the free models on the old gateway had — a plan cut off
## mid-string, which costs forty seconds and yields nothing, because JSON that
## never closes is not a poor plan but no plan at all.
##
## It does NOT replace the validator. The schema constrains shape; the
## validator decides whether the town can do it, and turns "no" into a sentence
## a worker says out loud. A schema-perfect plan for a six-storey hut is still
## refused, and still refused in character.

## Sent as strict:false deliberately.
##
## Strict mode on Groq requires every property to be required and every object
## to close additionalProperties, which cannot express "a step has an id only
## if something refers to it" without flattening every verb into one object
## full of nulls. The schema below says what the plan actually looks like, and
## non-strict still guarantees the reply is valid JSON — which is the whole of
## what was broken. The rest was always the validator's job.
const STRICT := false


## `allowed` narrows the steps to one role's capabilities; empty means all.
## A shepherd's schema is a quarter the size of a builder's, and it is sent
## on every call.
##
## `mode` is which model this is for. The router (the small, fast one) sees
## every verb, and "build" as a brief in words; the designer (the large one)
## sees only "build", as the full spec. The router never has to hold a
## building in its head, and the designer never has to choose between fishing
## and fencing — which is the whole reason there are two.
static func for_tier(tier: int, allowed: Array = [], mode: String = "router") -> Dictionary:
	var kinds: Array = ["plan", "question"]
	if mode == "router":
		kinds.append("chat")
	return {
		"name": "delegate_plan",
		"strict": STRICT,
		"schema": {
			"type": "object",
			"properties": {
				"kind": {"type": "string", "enum": kinds},
				"steps": {
					"type": "array",
					"minItems": 1,
					"maxItems": Steps.MAX_STEPS,
					"items": {"anyOf": _step_schemas(tier, allowed, mode)},
				},
				"question": {
					"type": "string",
					"description": "Set only when kind is question.",
				},
				"assumptions": {
					"type": "array",
					"items": {"type": "string"},
					"description": "Every gap you filled, in plain sentences to your employer.",
				},
				"confidence": {"type": "number"},
				"worker_line": {"type": "string"},
			},
			"required": ["kind", "worker_line"],
		},
	}


## The router's schema, in one object rather than sixty.
##
## The obvious shape — one schema per verb under `anyOf` — is correct and
## unaffordable: with fifty-odd verbs, each repeating the material and stock
## enums, it came to five and a half thousand tokens of *input* on every
## call, which is most of a free tier's minute spent describing the question
## rather than asking it.
##
## So a step is one object here: `do` is an enum of every verb the caller may
## use, and the fields are the union of those verbs' fields, each typed once.
## That still guarantees the reply parses and still refuses an invented verb
## at the decoder; what it no longer does is tie a field to its verb. The
## validator was always going to check that — it is the one place that knows
## what the town can actually do — so the schema is not the right place to
## say it twice.
static func router_schema(tier: int, allowed: Array = []) -> Dictionary:
	var verbs: Array = []
	var props: Dictionary = {"do": {}}
	var table := Steps.all()
	for verb: String in table:
		var v: Dictionary = table[verb]
		if int(v["tier"]) > tier:
			continue
		if not allowed.is_empty() and Steps.capability_of(verb) not in allowed \
				and not bool(v.get("anyone", false)):
			continue
		verbs.append(verb)
		var fields: Array = ["brief", "id"] if verb == "build" \
			else (v["required"] as Array) + (v["optional"] as Array)
		for f: String in fields:
			_merge_field(props, f, _field(f, tier, verb))
	props["do"] = {"type": "string", "enum": verbs}
	return {
		"name": "delegate_plan",
		"strict": STRICT,
		"schema": {
			"type": "object",
			"properties": {
				"kind": {"type": "string", "enum": ["plan", "chat", "question"]},
				"steps": {
					"type": "array",
					"maxItems": Steps.MAX_STEPS,
					"items": {
						"type": "object",
						"properties": props,
						"required": ["do"],
					},
				},
				"question": {"type": "string",
					"description": "Set only when kind is question."},
				# No assumptions here. They belong to the design of a building,
				# which is the other model's, and every one written at this
				# stage is output tokens spent restating the order.
				"worker_line": {"type": "string"},
			},
			"required": ["kind", "worker_line"],
		},
	}


## One field, seen from two verbs at once. Two enums become their union — a
## "place" is a building to one verb and a compass point to another, and the
## model may legitimately say either. Two different types are a field two
## verbs disagree about, and it is left out entirely: unconstrained beats
## constrained to the wrong thing.
static func _merge_field(props: Dictionary, name: String, spec: Dictionary) -> void:
	if not props.has(name):
		props[name] = spec
		return
	var was: Dictionary = props[name]
	if was.is_empty():
		return                          # already given up on this one
	if str(was.get("type", "")) != str(spec.get("type", "")):
		props[name] = {}
		return
	if was.has("enum") != spec.has("enum"):
		props[name] = {"type": was.get("type", "string")}
		return
	if was.has("enum"):
		var merged: Array = (was["enum"] as Array).duplicate()
		for e: Variant in spec["enum"] as Array:
			if e not in merged:
				merged.append(e)
		was["enum"] = merged


static func _step_schemas(tier: int, allowed: Array = [], mode: String = "router") -> Array:
	var out: Array = []
	var table := Steps.all()
	for verb: String in table:
		var v: Dictionary = table[verb]
		if int(v["tier"]) > tier:
			continue
		if mode == "design" and verb != "build":
			continue
		if not allowed.is_empty() and Steps.capability_of(verb) not in allowed \
				and not bool(v.get("anyone", false)):
			continue
		var props := {"do": {"type": "string", "enum": [verb]}}
		var required: Array = ["do"]
		var req: Array = v["required"]
		var opt: Array = v["optional"]
		if verb == "build":
			# The one verb with two shapes: a brief for the router, a spec
			# for the designer. Neither model is shown the other's.
			if mode == "design":
				req = ["spec"]
				opt = ["id"]
			else:
				req = ["brief"]
				opt = ["id"]
		for f: String in req:
			props[f] = _field(f, tier, verb)
			required.append(f)
		for f2: String in opt:
			props[f2] = _field(f2, tier, verb)
		out.append({
			"type": "object",
			"description": str(v["says"]),
			"properties": props,
			"required": required,
		})
	return out


## One field of one step. Everything the validator checks as an enum is an enum
## here too, so a wrong material is refused by the decoder before it costs a
## round trip.
static func _field(name: String, tier: int, verb: String = "") -> Dictionary:
	# A registered verb may say what a field is. Anything it does not say is
	# a string, like every other field nobody typed.
	if verb != "":
		var t: Variant = Steps.field_type(verb, name)
		if t is Array:
			return {"type": "string", "enum": t}
		if str(t) == "int":
			return {"type": "integer", "minimum": 0}
	match name:
		"spec":
			return _building_spec(tier)
		"brief":
			return {"type": "string",
				"description": "what it is for and how it should look, in their words"}
		"size":
			return {"type": "array", "minItems": 2, "maxItems": 2,
				"items": {"type": "integer"},
				"description": "width and depth in whole metres"}
		"material":
			return {"type": "string", "enum": _names(VoxelTypes.names_for_tier(tier))}
		"gate":
			return {"type": "string", "enum": Steps.GATES}
		"species":
			return {"type": "string", "enum": Steps.SPECIES}
		"crop":
			return {"type": "string", "enum": Steps.CROPS}
		"count":
			return {"type": "integer", "minimum": 1, "maximum": Steps.COUNT_MAX}
		"units":
			return {"type": "integer", "minimum": 1, "maximum": Steps.UNITS_MAX}
		"id":
			return {"type": "string"}
		"into", "in", "near":
			return {"type": "string", "description": "an earlier step's id"}
		"place":
			return {"type": "string",
				"description": "a building by its name, or: the well, the field, home, you"}
		"places":
			return {"type": "array", "minItems": 2, "maxItems": 6,
				"items": {"type": "string"}}
		"hours":
			return {"type": "integer", "minimum": 1, "maximum": Steps.SHIFT_MAX_HOURS}
		"doing":
			return {"type": "string", "enum": Humanoid.GESTURES}
		"line":
			return {"type": "string"}
		"direction":
			return {"type": "string", "enum": Steps.DIRECTIONS}
		"distance":
			return {"type": "integer", "minimum": 5, "maximum": Steps.SCOUT_MAX_M}
		"action":
			return {"type": "string", "enum": Steps.TRADE_ACTIONS}
		"kind":
			return {"type": "string", "enum": Town.PRICE.keys()}
		"skill":
			return {"type": "string", "enum": Steps.SKILLS}
		"item":
			return {"type": "string", "enum": _names(Arsenal.all_keys())}
		"who":
			return {"type": "string", "description": "a person's name"}
		"role":
			return {"type": "string", "description": "the job, one or two words"}
		"description":
			return {"type": "string", "description": "what the job involves, if your employer said"}
		"about":
			return {"type": "string", "enum": Critique.TOPICS}
		"value":
			return {"type": "string",
				"description": "what they want it to be; prefix not: for something they do not want"}
		"goal":
			return {"type": "string", "description": "the goal in plain words, or empty to drop it"}
		"order":
			return {"type": "string", "description": "what to tell them, in plain words"}
		"from", "to":
			return {"type": "string", "description": "a place, as for go"}
		"width":
			return {"type": "integer", "minimum": 1, "maximum": 6}
	return {"type": "string"}


## A role, as the composer is asked for it.
static func role_schema() -> Dictionary:
	return {
		"name": "delegate_role",
		"strict": STRICT,
		"schema": {
			"type": "object",
			"properties": {
				"kind": {"type": "string", "enum": ["role"]},
				"name": {"type": "string"},
				"capabilities": {
					"type": "array", "minItems": 1, "maxItems": 12,
					"items": {"type": "string", "enum": _names(Capabilities.all_ids())},
				},
				"character": {"type": "string"},
				"standing": {"type": "string"},
				"line": {"type": "string"},
			},
			"required": ["kind", "name", "capabilities", "character", "line"],
		},
	}


## A round of a goal, as the foreman is asked for it.
static func round_schema() -> Dictionary:
	return {
		"name": "delegate_round",
		"strict": STRICT,
		"schema": {
			"type": "object",
			"properties": {
				"kind": {"type": "string", "enum": ["round"]},
				"done": {"type": "boolean"},
				"orders": {
					"type": "array", "maxItems": Goal.MAX_ORDERS_PER_ROUND,
					"items": {
						"type": "object",
						"properties": {
							"who": {"type": "string"},
							"order": {"type": "string"},
						},
						"required": ["who", "order"],
					},
				},
				"note": {"type": "string"},
			},
			"required": ["kind", "done", "orders", "note"],
		},
	}


static func _building_spec(tier: int) -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"kind": {"type": "string", "enum": ["building"]},
			"archetype": {"type": "string",
				"enum": _names(Vocabulary.archetypes_for_tier(tier))},
			"footprint": {"type": "array", "minItems": 2, "maxItems": 2,
				"items": {"type": "integer"}},
			"stories": {"type": "integer", "minimum": 1,
				"maximum": Vocabulary.max_stories(tier)},
			"orientation": {"type": "string", "enum": Vocabulary.ORIENTATIONS},
			"roof": {"type": "string", "enum": Vocabulary.ROOFS},
			# The material list is long and was here four times over. Walls
			# and roof keep the enum, because those are the two the decoder
			# most usefully constrains; trim and foundation are checked by the
			# validator like everything else.
			"materials": {
				"type": "object",
				"properties": {
					"walls": {"type": "string", "enum": _names(VoxelTypes.names_for_tier(tier))},
					"roof": {"type": "string", "enum": _names(VoxelTypes.names_for_tier(tier))},
					"trim": {"type": "string"},
					"foundation": {"type": "string"},
				},
				"required": ["walls", "roof"],
			},
			"modules": {
				"type": "array",
				"items": {
					"type": "object",
					"properties": {
						"type": {"type": "string",
							"enum": _names(Vocabulary.modules_for_tier(tier))},
						"wall": {"type": "string", "enum": Vocabulary.WALLS},
						"story": {"type": "string", "enum": ["ground", "top"]},
						"size": {"type": "string", "enum": Vocabulary.SIZES},
						"priority": {"type": "string", "enum": Vocabulary.PRIORITIES},
						"adjacent_to": {"type": "string"},
					},
					"required": ["type"],
				},
			},
			"sign": {"type": "string"},
		},
		"required": ["archetype", "footprint", "stories", "roof", "materials",
			"modules"],
	}


## One tool per thing this person can actually do, plus reply.
##
## The model calls one of these. It does not write a plan into the message and
## it does not get to wander off while it decides. reply is the tool for
## everything that is not a job — a greeting, a question, a typo, "what do you
## want". A work tool is only for a job they were actually given.
static func tools_for(tier: int, allowed: Array = []) -> Array:
	var tools: Array = [{
		"type": "function",
		"function": {
			"name": "reply",
			"description": ("Say something and do no work. Use this for a greeting, "
				+ "a question, chatter, a typo, or anything that is not a clear "
				+ "order to do one of the other tools. Do not also call a work tool."),
			"parameters": {
				"type": "object",
				"properties": {
					"text": {"type": "string",
						"description": "What you say out loud, one or two sentences, in your own voice."},
				},
				"required": ["text"],
			},
		},
	}]
	for verb: String in Steps.VERBS:
		var v: Dictionary = Steps.VERBS[verb]
		if int(v["tier"]) > tier:
			continue
		if not allowed.is_empty() and Steps.capability_of(verb) not in allowed:
			continue
		var props := {}
		var required: Array = []
		for f: String in v["required"]:
			props[f] = _field(f, tier)
			required.append(f)
		for f2: String in v["optional"]:
			props[f2] = _field(f2, tier)
		var params := {
			"type": "object",
			"properties": props,
		}
		if not required.is_empty():
			params["required"] = required
		tools.append({
			"type": "function",
			"function": {
				"name": verb,
				"description": str(v["says"]) + ". Only when they asked you to do this.",
				"parameters": params,
			},
		})
	return tools


## Tool calls, in the order the model made them, turned into the plan the
## rest of the game already runs. A reply and no work is kind "talk" and
## does not move anybody.
static func from_tool_calls(calls: Array) -> Dictionary:
	var said := ""
	var steps: Array = []
	for c: Variant in calls:
		if not (c is Dictionary):
			continue
		var call: Dictionary = c
		var name := str(call.get("name", ""))
		var args := _args(call.get("arguments", {}))
		if name == "reply":
			var text := str(args.get("text", "")).strip_edges()
			if text != "":
				said = text
			continue
		if not Steps.known(name) or steps.size() >= Steps.MAX_STEPS:
			continue
		var step := {"do": name}
		for k: Variant in args:
			step[str(k)] = args[k]
		steps.append(step)
	if steps.is_empty():
		if said == "":
			return {}
		return {"kind": "talk", "worker_line": said, "source": "model"}
	return {
		"kind": "plan",
		"steps": steps,
		"assumptions": [said if said != "" else "That is what you asked for, so that is what I will do."],
		"worker_line": said if said != "" else "I will see to that.",
		"confidence": 0.8,
		"source": "model",
	}


static func _args(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw
	if raw is String and str(raw).strip_edges() != "":
		var j := JSON.new()
		if j.parse(str(raw)) == OK and j.data is Dictionary:
			return j.data
	return {}


## PackedStringArray does not survive JSON.stringify as a list of strings.
static func _names(packed: PackedStringArray) -> Array:
	var out: Array = []
	for n: String in packed:
		out.append(n)
	return out
