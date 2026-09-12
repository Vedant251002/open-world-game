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
static func for_tier(tier: int, allowed: Array = []) -> Dictionary:
	return {
		"name": "delegate_plan",
		"strict": STRICT,
		"schema": {
			"type": "object",
			"properties": {
				"kind": {"type": "string", "enum": ["plan", "question"]},
				"steps": {
					"type": "array",
					"minItems": 1,
					"maxItems": Steps.MAX_STEPS,
					"items": {"anyOf": _step_schemas(tier, allowed)},
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


static func _step_schemas(tier: int, allowed: Array = []) -> Array:
	var out: Array = []
	for verb: String in Steps.VERBS:
		var v: Dictionary = Steps.VERBS[verb]
		if int(v["tier"]) > tier:
			continue
		if not allowed.is_empty() and Steps.capability_of(verb) not in allowed:
			continue
		var props := {"do": {"type": "string", "enum": [verb]}}
		var required: Array = ["do"]
		for f: String in v["required"]:
			props[f] = _field(f, tier)
			required.append(f)
		for f2: String in v["optional"]:
			props[f2] = _field(f2, tier)
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
static func _field(name: String, tier: int) -> Dictionary:
	match name:
		"spec":
			return _building_spec(tier)
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
			return {"type": "string",
				"description": "name this step only if a later one refers to it"}
		"into", "in", "near":
			return {"type": "string",
				"description": "the id of an EARLIER step, never a later one"}
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
		"who":
			return {"type": "string", "description": "the name of one of the hired people"}
		"order":
			return {"type": "string", "description": "what to tell them, in plain words"}
		"role":
			return {"type": "string", "description": "the job, one or two words"}
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


## PackedStringArray does not survive JSON.stringify as a list of strings.
static func _names(packed: PackedStringArray) -> Array:
	var out: Array = []
	for n: String in packed:
		out.append(n)
	return out
