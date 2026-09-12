extends RefCounted
class_name Steps
## The closed verb vocabulary: what an order is allowed to *be*.
##
## Vocabulary.gd answers "what can a building be made of". This answers the
## question one level up — "what can the player ask for at all" — and it exists
## because for a long time the answer was "a building, plus four sentences the
## dispatcher pattern-matched on the way past". Those keyword lists could not
## compose: "fence the top field and put the hens in it" matched STOCK_WORDS,
## went straight to the livestock branch, and the fence was never built or
## mentioned again. The order was not refused, it was half-heard, which is the
## one failure this game is not allowed to have (pillar P3).
##
## Rule zero is unchanged (voxel-module-spec.md §0): the model emits intent from
## this list, the engine emits geometry. A verb is an engine change, never a
## prompt change — which is exactly why this is a table and not a code
## generator. Everything the model can say is enumerated here, the validator
## checks against exactly this table, and a step outside it comes back as a
## sentence a worker says to your face rather than as something the game tries
## to run.

## A plan is a short list, not a program. Four is the ceiling because:
##
##   - the free model on the gateway truncates a five-module building spec at
##     around sixteen hundred tokens, and a truncated plan is not a poor plan,
##     it is no plan at all;
##   - a worker holds one order in their head. Past four steps you are not
##     giving an instruction, you are writing a project, and the answer to that
##     is a second worker, not a longer list;
##   - every step is validated before the first one starts, and the cost of
##     being wrong grows with the length of what was accepted.
const MAX_STEPS := 4

## The verbs. `produces` names what a later step may point back at: a "site" is
## a piece of ground this step claims, which is what `into` / `in` / `near`
## resolve to. A verb producing nothing can still be asked for, it just cannot
## be referred to afterwards.
const VERBS := {
	"build": {
		"tier": 1,
		"says": "put up a building on the plot you were given",
		"required": ["spec"],
		"optional": ["id"],
		"produces": "site",
	},
	"enclose": {
		"tier": 1,
		"says": "fence a rectangle of open ground, with one gate in it",
		"required": ["size"],
		"optional": ["id", "material", "gate", "near"],
		"produces": "site",
	},
	"stock": {
		"tier": 1,
		"says": "walk out, bring animals back and turn them out",
		"required": ["species"],
		"optional": ["count", "into"],
		"produces": "",
	},
	"sow": {
		"tier": 1,
		"says": "plough a field and sow it",
		"required": [],
		"optional": ["crop", "size", "in"],
		"produces": "site",
	},
	"gather": {
		"tier": 1,
		"says": "go out to the ground beyond the town and fetch a material",
		"required": ["material"],
		"optional": ["units"],
		"produces": "",
	},

	# --- errands: the verbs a role other than builder is mostly made of ------
	#
	# Every one of these is a walk with something at the end of it, and they
	# share one job on the worker (take_errand_job). That is what lets a night
	# watchman, a shopkeeper and a farmhand exist without each being a state
	# machine of their own.
	"go": {
		"tier": 1,
		"says": "walk to a place: a building by name, 'the well', 'the field', 'home', or 'you'",
		"required": ["place"],
		"optional": ["id"],
		"produces": "site",
	},
	"follow": {
		"tier": 1,
		"says": "fall in behind your employer and keep with them",
		"required": [],
		"optional": [],
		"produces": "",
	},
	"wait": {
		"tier": 1,
		"says": "stay where you are, or at a place, for some hours",
		"required": [],
		"optional": ["place", "hours"],
		"produces": "",
	},
	"station": {
		"tier": 1,
		"says": "work a shift at a building — some hours at the oven, the counter, the gate",
		"required": ["place"],
		"optional": ["hours", "doing"],
		"produces": "site",
	},
	"patrol": {
		"tier": 1,
		"says": "walk a round between two or more places, over and over, for some hours",
		"required": ["places"],
		"optional": ["hours"],
		"produces": "",
	},
	"harvest": {
		"tier": 1,
		"says": "walk the field and bring in what is ripe",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"collect": {
		"tier": 1,
		"says": "go round the animals and pick up the eggs, wool and milk",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"rest": {
		"tier": 1,
		"says": "go home and rest for some hours",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"speak": {
		"tier": 1,
		"says": "say a line out loud — to greet, announce, or report",
		"required": ["line"],
		"optional": [],
		"produces": "",
	},
	"scout": {
		"tier": 1,
		"says": "walk out some distance in a compass direction and report the ground",
		"required": ["direction"],
		"optional": ["distance"],
		"produces": "",
	},

	# --- trades and land works -------------------------------------------
	"trade": {
		"tier": 1,
		"says": "go to the store and sell some of the stock, or buy some in",
		"required": ["action", "kind"],
		"optional": ["count"],
		"produces": "",
	},
	"cook": {
		"tier": 1,
		"says": "a shift at an oven turning food into meals",
		"required": [],
		"optional": ["hours", "place"],
		"produces": "",
	},
	"craft": {
		"tier": 1,
		"says": "a shift at a bench turning timber and iron into tools",
		"required": [],
		"optional": ["hours", "place"],
		"produces": "",
	},
	"fish": {
		"tier": 1,
		"says": "some hours at the water's edge, for food",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"hunt": {
		"tier": 1,
		"says": "some hours in the woods, for food",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"plant_tree": {
		"tier": 1,
		"says": "plant one or more trees at a place",
		"required": [],
		"optional": ["place", "count"],
		"produces": "site",
	},
	"pave": {
		"tier": 1,
		"says": "lay a road between two places",
		"required": ["from", "to"],
		"optional": ["material", "width"],
		"produces": "site",
	},
	"level": {
		"tier": 1,
		"says": "flatten a piece of ground at a place",
		"required": [],
		"optional": ["place", "size", "id"],
		"produces": "site",
	},
	"water": {
		"tier": 1,
		"says": "water the field",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"tend": {
		"tier": 1,
		"says": "feed and see to the animals",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"teach": {
		"tier": 1,
		"says": "spend some hours teaching another hired person a skill",
		"required": ["who", "skill"],
		"optional": ["hours"],
		"produces": "",
	},
	"demolish": {
		"tier": 1,
		"says": "take a building down",
		"required": ["place"],
		"optional": [],
		"produces": "",
	},
	"decorate": {
		"tier": 1,
		"says": "dress the front of a building with lanterns, planters and the like",
		"required": ["place"],
		"optional": ["count"],
		"produces": "",
	},

	# --- running the place -------------------------------------------------
	"delegate": {
		"tier": 1,
		"says": "give another hired person an order, in plain words",
		"required": ["who", "order"],
		"optional": [],
		"produces": "",
	},
	"recruit": {
		"tier": 1,
		"says": "take somebody from the town on as a job",
		"required": ["role"],
		"optional": ["who"],
		"produces": "",
	},
	"report": {
		"tier": 1,
		"says": "say how the stores and the purse stand",
		"required": [],
		"optional": [],
		"produces": "",
	},
}

const SKILLS := ["carpentry", "masonry", "machining", "piloting"]
const TRADE_ACTIONS := ["sell", "buy"]

## Which capability a verb draws on. Every verb is one capability of the same
## name, so a role's capability list is exactly the set of verbs its plans may
## contain — there is no second mapping to keep in step.
static func capability_of(verb: String) -> String:
	return verb

## Fields whose value is the `id` of an earlier step rather than a literal.
## They are the whole reason this is a list and not four separate orders.
const REF_FIELDS := ["into", "in", "near"]

## Places a `go` / `station` / `patrol` step may name besides a building. A
## building is named by its archetype ("the bakery") or its street; the
## dispatcher resolves either to a doorway.
const PLACE_WORDS := ["well", "field", "home", "you", "here", "gate", "edge",
	"square", "plaza"]
const DIRECTIONS := ["north", "south", "east", "west"]
const SHIFT_MAX_HOURS := 12
const SCOUT_MAX_M := 120

## What a worker can be sent to fetch and turn out in a pen. Livestock only:
## the wild things come and go on their own and are nobody's to bring.
const SPECIES := ["hen", "rooster", "sheep", "cow", "goat", "pig", "horse"]
const CROPS := ["wheat", "carrot"]
## "worker_choice" everywhere a worker could reasonably decide for themselves,
## matching Vocabulary.ORIENTATIONS. A model that has to invent a compass point
## invents a wrong one.
const GATES := ["north", "south", "east", "west", "worker_choice"]

## Enclosure bounds in metres. Below three metres it is a crate; past twenty it
## is not a pen, it is a field with a fence round it, and the stores would never
## cover the timber.
const ENCLOSURE_MIN_M := 3
const ENCLOSURE_MAX_M := 20

## Field bounds in metres, matching what Farm.find_field will actually search
## for within forty metres of the worker.
const FIELD_MIN_M := 3
const FIELD_MAX_M := 12

const COUNT_MAX := 12
const UNITS_MAX := 400


## Every plan as a step list, whatever shape it arrived in.
##
## There is exactly one execution path downstream of this, which is the point.
## A bare "spec" is not a legacy shape to be tolerated — it is what the offline
## plan library emits, what every plan cached on disk holds, and what a model
## that skimmed the prompt will send anyway. All three are a one-step plan that
## builds a building, so all three become one here rather than each growing its
## own branch in the dispatcher.
static func normalise(plan: Dictionary) -> Array:
	var raw: Variant = plan.get("steps", null)
	if raw is Array and not (raw as Array).is_empty():
		var out: Array = []
		for s: Variant in raw as Array:
			if s is Dictionary:
				out.append(s)
		return out
	if plan.get("spec", null) is Dictionary:
		return [{"do": "build", "spec": plan["spec"]}]
	return []


static func known(verb: String) -> bool:
	return VERBS.has(verb)


## Which tier first allows this verb, or 0 if nobody has heard of it. Mirrors
## Vocabulary.archetype_tier, and for the same reason: "we are not up to that
## yet" and "I have never heard of that" are different sentences, and the player
## is owed the right one.
static func verb_tier(verb: String) -> int:
	if not VERBS.has(verb):
		return 0
	return int(VERBS[verb]["tier"])


static func produces_site(verb: String) -> bool:
	return VERBS.has(verb) and str(VERBS[verb]["produces"]) == "site"


## The verb list as the model is shown it, one line each. Kept here rather than
## in Prompt so that adding a verb cannot leave the prompt describing four of
## them and the validator accepting five.
## `allowed` narrows the list to one role's capabilities. Empty means all of
## them, which is what the builder role amounts to.
static func describe_for_tier(tier: int, allowed: Array = []) -> String:
	var lines: Array[String] = []
	for v: String in VERBS:
		if int(VERBS[v]["tier"]) > tier:
			continue
		if not allowed.is_empty() and capability_of(v) not in allowed:
			continue
		var fields: Array[String] = []
		for f: String in VERBS[v]["required"]:
			fields.append(f)
		for f: String in VERBS[v]["optional"]:
			fields.append("%s?" % f)
		lines.append("- %s — %s   fields: %s" % [v, str(VERBS[v]["says"]),
			", ".join(fields)])
	return "\n".join(lines)


## A one-line description of a step, in a worker's voice, for assumptions and
## for the log. Never shows an id or a coordinate.
static func describe(step: Dictionary) -> String:
	var verb := str(step.get("do", ""))
	match verb:
		"build":
			var spec: Dictionary = step.get("spec", {})
			return "put up %s" % Validator.an(str(spec.get("archetype", "building")))
		"enclose":
			var s: Array = step.get("size", [6, 6])
			return "fence %d by %d metres" % [int(s[0]), int(s[1])]
		"stock":
			var n := int(step.get("count", 0))
			var sp := str(step.get("species", "hen"))
			if n <= 0:
				return "bring some %s back" % plural(sp, 2)
			return "bring %d %s back" % [n, plural(sp, n)]
		"sow":
			return "sow a field with %s" % str(step.get("crop", "wheat"))
		"gather":
			return "fetch %s" % str(step.get("material", "timber")).replace("_", " ")
		"go":
			return "go to %s" % _place_words(str(step.get("place", "")))
		"follow":
			return "come with you"
		"wait":
			if step.has("place"):
				return "wait at %s" % _place_words(str(step["place"]))
			return "wait here"
		"station":
			var h := int(step.get("hours", 0))
			var at := _place_words(str(step.get("place", "")))
			return "work at %s%s" % [at, (" for %d hours" % h) if h > 0 else ""]
		"patrol":
			var ps: Array = step.get("places", [])
			var names: Array[String] = []
			for pl: Variant in ps:
				names.append(_place_words(str(pl)))
			return "walk the round: %s" % " to ".join(names)
		"harvest":
			return "bring in what is ripe"
		"collect":
			return "go round the animals for eggs and the rest"
		"rest":
			return "go home and rest"
		"speak":
			return "say \"%s\"" % str(step.get("line", ""))
		"scout":
			return "scout %s" % str(step.get("direction", "out"))
		"trade":
			return "%s %s %s" % [str(step.get("action", "sell")),
				str(step.get("count", "some")), str(step.get("kind", "")).replace("_", " ")]
		"cook":
			return "cook a shift"
		"craft":
			return "make tools"
		"fish":
			return "go fishing"
		"hunt":
			return "go hunting"
		"plant_tree":
			var n := int(step.get("count", 1))
			return "plant %d tree%s" % [n, "s" if n != 1 else ""]
		"pave":
			return "lay a road from %s to %s" % [_place_words(str(step.get("from", ""))),
				_place_words(str(step.get("to", "")))]
		"level":
			return "level the ground%s" % ((" at " + _place_words(str(step["place"]))) if step.has("place") else "")
		"water":
			return "water the field"
		"tend":
			return "see to the animals"
		"teach":
			return "teach %s %s" % [str(step.get("who", "")).capitalize(), str(step.get("skill", ""))]
		"demolish":
			return "take down %s" % _place_words(str(step.get("place", "")))
		"decorate":
			return "dress up %s" % _place_words(str(step.get("place", "")))
		"delegate":
			return "tell %s to %s" % [str(step.get("who", "")).capitalize(), str(step.get("order", ""))]
		"recruit":
			return "take somebody on as %s" % Validator.an(str(step.get("role", "")))
		"report":
			return "give an account of the town"
	return verb


## "4 sheep", not "4 sheeps". Said out loud by three different people.
static func plural(species: String, n: int) -> String:
	if n == 1 or species == "sheep":
		return species
	return species + "s"


static func _place_words(place: String) -> String:
	var p := place.strip_edges().to_lower()
	if p == "you" or p == "here":
		return "where you are"
	if p == "home":
		return "home"
	if p.begins_with("the "):
		return p
	return "the " + p.replace("_", " ")
