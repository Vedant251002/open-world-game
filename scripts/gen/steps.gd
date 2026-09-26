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
		"says": "put up, redesign or extend a building; brief is what it is for and how it should look, in words",
		"required": [],
		"optional": ["brief", "spec", "id"],
		"produces": "site",
	},
	"enclose": {
		"tier": 1,
		"says": "fence a rectangle of open ground, one gate in it",
		"required": ["size"],
		"optional": ["id", "material", "gate", "near"],
		"produces": "site",
	},
	"stock": {
		"tier": 1,
		"says": "fetch live animals and turn them out",
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
		"says": "dig, fell or quarry a material from the ground beyond the town",
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
		"says": "walk to a place",
		"required": ["place"],
		"optional": ["id"],
		"produces": "site",
	},
	"follow": {
		"tier": 1,
		"says": "fall in behind your employer",
		"required": [],
		"optional": [],
		"produces": "",
	},
	"wait": {
		"tier": 1,
		"says": "stay put, here or at a place",
		"required": [],
		"optional": ["place", "hours"],
		"produces": "",
	},
	"station": {
		"tier": 1,
		"says": "work a shift at a building",
		"required": ["place"],
		"optional": ["hours", "doing"],
		"produces": "site",
	},
	"patrol": {
		"tier": 1,
		"says": "walk a round between places, over and over",
		"required": ["places"],
		"optional": ["hours"],
		"produces": "",
	},
	"harvest": {
		"tier": 1,
		"says": "bring in what is ripe in the field",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"collect": {
		"tier": 1,
		"says": "go round the animals for eggs, wool and milk",
		"required": [],
		"optional": ["in"],
		"produces": "",
	},
	"rest": {
		"tier": 1,
		"says": "go home and rest",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"speak": {
		"tier": 1,
		"says": "say a line out loud",
		"required": ["line"],
		"optional": [],
		"produces": "",
	},
	"scout": {
		"tier": 1,
		"says": "walk out in a direction and report the ground",
		"required": ["direction"],
		"optional": ["distance"],
		"produces": "",
	},

	# --- trades and land works -------------------------------------------
	"trade": {
		"tier": 1,
		"says": "sell stock at the store, or buy some in",
		"required": ["action", "kind"],
		"optional": ["count"],
		"produces": "",
	},
	"cook": {
		"tier": 1,
		"says": "a shift at an oven: food into meals",
		"required": [],
		"optional": ["hours", "place"],
		"produces": "",
	},
	"craft": {
		"tier": 1,
		"says": "a shift at a bench: timber and iron into tools",
		"required": [],
		"optional": ["hours", "place"],
		"produces": "",
	},
	"fish": {
		"tier": 1,
		"says": "hours at the water for food",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"hunt": {
		"tier": 1,
		"says": "hours in the woods for meat",
		"required": [],
		"optional": ["hours"],
		"produces": "",
	},
	"plant_tree": {
		"tier": 1,
		"says": "plant trees at a place",
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
		"says": "flatten ground at a place",
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
		"says": "teach another hired person a skill",
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
		"says": "dress the front of a building",
		"required": ["place"],
		"optional": ["count"],
		"produces": "",
	},

	# --- running the place -------------------------------------------------
	"delegate": {
		"tier": 1,
		"says": "give another hired person an order in plain words",
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

	# --- who works for you ------------------------------------------------
	#
	# These used to be regular expressions at the top of Dispatcher.instruct:
	# one for "hire X as a Y", one for "you are my Y", one for "define a job
	# called Y"... and each heard one phrasing. They are verbs now, so "take
	# Ada on as a guard and send her to the gate" is one plan with two steps.
	"hire": {
		"tier": 1,
		"instant": true,
		"says": "take somebody on as a job; who is their name, or left out for whoever you are talking to",
		"required": ["role"],
		"optional": ["who", "description"],
		"produces": "",
		"anyone": true,
	},
	"dismiss": {
		"tier": 1,
		"instant": true,
		"says": "let a hired person go",
		"required": [],
		"optional": ["who"],
		"produces": "",
		"anyone": true,
	},
	"define_role": {
		"tier": 1,
		"instant": true,
		"says": "write a new job up without hiring anyone",
		"required": ["role"],
		"optional": ["description"],
		"produces": "",
		"anyone": true,
	},
	"learn": {
		"tier": 1,
		"instant": true,
		"says": "remember a taste or a correction: about is what it is about (walls, roof, size...), value what they want",
		"required": ["about", "value"],
		"optional": [],
		"produces": "",
		"anyone": true,
	},
	"standing": {
		"tier": 1,
		"instant": true,
		"says": "make an order your every-morning task; empty order clears it",
		"required": ["order"],
		"optional": [],
		"produces": "",
		"anyone": true,
	},
	"goal": {
		"tier": 1,
		"instant": true,
		"says": "take on a goal to organise the crew towards over days; empty goal drops it",
		"required": ["goal"],
		"optional": [],
		"produces": "",
		# Anybody may be handed one; whether they can hold it is the step's
		# to say, and it says so in character — "that wants somebody who can
		# give orders". A job nobody was given is not the same refusal.
		"anyone": true,
	},

	# --- the game itself ----------------------------------------------------
	"save": {
		"tier": 1,
		"says": "save the game",
		"required": [],
		"optional": [],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
	"restart": {
		"tier": 1,
		"says": "start the game over",
		"required": [],
		"optional": [],
		"produces": "",
		"anyone": true,
		"instant": true,
	},

	# --- the army -------------------------------------------------------------
	"enlist": {
		"tier": 1,
		"says": "take townsfolk on as soldiers",
		"required": [],
		"optional": ["count"],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
	"arm": {
		"tier": 1,
		"says": "hand a weapon out from the armoury; who: me arms your employer",
		"required": ["item"],
		"optional": ["who"],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
	"attack": {
		"tier": 1,
		"says": "send the soldiers at the raiders",
		"required": [],
		"optional": [],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
	"defend": {
		"tier": 1,
		"says": "post the soldiers to hold a place; place: me is where your employer stands",
		"required": ["place"],
		"optional": [],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
	"forge": {
		"tier": 1,
		"says": "a shift at the armoury making weapons or ammunition",
		"required": ["item"],
		"optional": ["count"],
		"produces": "",
		"anyone": true,
	},
	"drill": {
		"tier": 1,
		"says": "a practice raid, to test the defences",
		"required": [],
		"optional": [],
		"produces": "",
		"anyone": true,
		"instant": true,
	},
}

## Verbs other parts of the game add at startup — the realm systems' taxes,
## decrees and marriages, the war's musters — keyed by verb, with the node
## that carries them out beside. One catalogue, composed rather than written,
## so a system that exists is a system the model can be asked for.
static var _extra: Dictionary = {}
static var _owners: Dictionary = {}


## `owner` must have run(worker: Worker, step: Dictionary) -> String, returning
## "done", "started" or a refusal line. Each entry of `verbs` is shaped like
## the ones above; `types` may name a field's type where "string" is wrong:
## "int", or a list of allowed values.
static func register(owner: Object, verbs: Dictionary) -> void:
	for v: String in verbs:
		var entry: Dictionary = (verbs[v] as Dictionary).duplicate()
		if not entry.has("tier"):
			entry["tier"] = 1
		if not entry.has("required"):
			entry["required"] = []
		if not entry.has("optional"):
			entry["optional"] = []
		if not entry.has("produces"):
			entry["produces"] = ""
		# The kingdom's own orders are the player's to give through whoever
		# they are talking to; a role is not asked.
		if not entry.has("anyone"):
			entry["anyone"] = true
		_extra[v] = entry
		_owners[v] = owner


static func unregister_all() -> void:
	_extra.clear()
	_owners.clear()


static func owner_of(verb: String) -> Object:
	return _owners.get(verb, null)


## The whole catalogue: built-in first, then everything registered.
static func all() -> Dictionary:
	if _extra.is_empty():
		return VERBS
	var out := VERBS.duplicate()
	out.merge(_extra)
	return out


static func entry(verb: String) -> Dictionary:
	if VERBS.has(verb):
		return VERBS[verb]
	return _extra.get(verb, {})


## A verb anybody hired may use whatever their role — and, for the handful
## marked so, anybody at all.
static func for_anyone(verb: String) -> bool:
	return bool(entry(verb).get("anyone", false))


## A verb that is over the moment it is said — no walk, no shift — so a busy
## worker can still be given it, and a plan of nothing else is a reply
## rather than a job.
static func instant(verb: String) -> bool:
	return bool(entry(verb).get("instant", false))


## The declared type of a field on a registered verb, or "" for the default.
static func field_type(verb: String, field: String) -> Variant:
	var types: Dictionary = entry(verb).get("types", {})
	return types.get(field, "")

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
				out.append(tidy(s as Dictionary))
		return out
	if plan.get("spec", null) is Dictionary:
		return [{"do": "build", "spec": plan["spec"]}]
	return []


## Fields a verb does not take, holding the value of one it does.
##
## The router's schema is one object for every verb — sixty separate shapes
## cost more in tokens than the whole rest of the prompt — so the model sees
## `to` and `place` side by side and now and then puts the destination of a
## `go` in `to`. It is not wrong about what it meant, only about where to put
## it, and a refusal would spend a round trip saying so. Each entry below is
## one such near miss: the value moves to the field the verb actually has,
## and only when that field is empty.
const ALIASES := {
	"place": ["to", "at", "where", "destination", "target", "building"],
	"who": ["whom", "name", "person"],
	"order": ["task", "instruction"],
	"count": ["number", "amount", "quantity", "n"],
	"units": ["amount", "quantity"],
	"material": ["mat", "stuff"],
	"hours": ["duration", "time"],
	"line": ["say", "text", "words"],
	"role": ["job", "title"],
	"brief": ["description", "what", "text"],
}


## One step, with its fields put where this verb keeps them.
static func tidy(step: Dictionary) -> Dictionary:
	var verb := str(step.get("do", ""))
	if not known(verb):
		return step
	var e := entry(verb)
	var takes: Array = (e["required"] as Array) + (e["optional"] as Array)
	for want: String in ALIASES:
		if want not in takes or str(step.get(want, "")).strip_edges() != "":
			continue
		for other: String in ALIASES[want]:
			# Only a field this verb has no use for. "description" is a real
			# field of hire, and moving it into brief would be the same
			# mistake in the other direction.
			if other in takes or not step.has(other):
				continue
			if str(step[other]).strip_edges() == "":
				continue
			step[want] = step[other]
			step.erase(other)
			break
	return step


static func known(verb: String) -> bool:
	return VERBS.has(verb) or _extra.has(verb)


## Which tier first allows this verb, or 0 if nobody has heard of it. Mirrors
## Vocabulary.archetype_tier, and for the same reason: "we are not up to that
## yet" and "I have never heard of that" are different sentences, and the player
## is owed the right one.
static func verb_tier(verb: String) -> int:
	if not known(verb):
		return 0
	return int(entry(verb)["tier"])


static func produces_site(verb: String) -> bool:
	return known(verb) and str(entry(verb)["produces"]) == "site"


## The verb list as the model is shown it, one line each:
##
##   verb(field, optional?) — what it does
##
## Kept here rather than in Prompt so that adding a verb cannot leave the
## prompt describing four of them and the validator accepting five. The
## format is terse on purpose: this list is the largest thing in the router's
## prompt and the router's prompt is charged against a per-minute token
## budget, so every word here costs an order somewhere.
##
## `allowed` narrows the list to one role's capabilities. Empty means all of
## them, which is what the builder role amounts to.
static func describe_for_tier(tier: int, allowed: Array = []) -> String:
	var lines: Array[String] = []
	var table := all()
	for v: String in table:
		var e: Dictionary = table[v]
		if int(e["tier"]) > tier:
			continue
		if not allowed.is_empty() and capability_of(v) not in allowed \
				and not bool(e.get("anyone", false)):
			continue
		var fields: Array[String] = []
		for f: String in e["required"]:
			fields.append(f)
		for f2: String in e["optional"]:
			fields.append("%s?" % f2)
		lines.append("%s(%s) %s" % [v, ", ".join(fields), str(e["says"])])
	return "\n".join(lines)


## A one-line description of a step, in a worker's voice, for assumptions and
## for the log. Never shows an id or a coordinate.
static func describe(step: Dictionary) -> String:
	var verb := str(step.get("do", ""))
	match verb:
		"build":
			var spec: Dictionary = step.get("spec", {})
			if spec.is_empty():
				return "build: %s" % str(step.get("brief", "a building"))
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
		"hire":
			var who := str(step.get("who", "")).strip_edges()
			return "take %s on as %s" % [who.capitalize() if who != "" else "them",
				Validator.an(str(step.get("role", "")))]
		"dismiss":
			var who2 := str(step.get("who", "")).strip_edges()
			return "let %s go" % (who2.capitalize() if who2 != "" else "them")
		"define_role":
			return "write up the job of %s" % str(step.get("role", ""))
		"learn":
			return "remember: %s — %s" % [str(step.get("about", "")), str(step.get("value", ""))]
		"standing":
			var o := str(step.get("order", "")).strip_edges()
			return ("every morning, %s" % o) if o != "" else "drop the morning task"
		"goal":
			var g := str(step.get("goal", "")).strip_edges()
			return ("see to it that %s" % g) if g != "" else "drop the goal"
		"save":
			return "write the town down"
		"restart":
			return "start over"
	# A registered verb: its own line, with whatever it was given.
	var e := entry(verb)
	if not e.is_empty():
		var bits: Array[String] = []
		for f: String in (e["required"] as Array) + (e["optional"] as Array):
			if step.has(f):
				bits.append("%s %s" % [f, str(step[f])])
		return str(e["says"]).split(" — ")[0] + ((" (" + ", ".join(bits) + ")") if not bits.is_empty() else "")
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
