extends RefCounted
class_name Prompt
## Builds the instruction -> plan prompt, per game-design-doc.md §5.1.
##
## The hard boundary from voxel-module-spec.md §0 lives here: the model is given
## a closed vocabulary and prose about the world, and it never sees a
## coordinate. Everything it can legally say is enumerated below, which is also
## exactly what the validator checks — so the prompt and the validator can never
## drift apart.

const SCHEMA := """Return ONE JSON object and nothing else. No prose, no markdown fences.

If you can act on the instruction:
{
  "kind": "plan",
  "steps": [ <one to four steps, done in the order you list them> ],
  "assumptions": ["<plain sentence, addressed to your employer>", ...],
  "confidence": <0.0-1.0>,
  "worker_line": "<one line you say out loud before you leave>",
  "cost_estimate": {"<material>": <units>}
}

Most orders are ONE step. Use more only when the order genuinely has parts that
must happen in sequence — a pen has to stand before anything can be put in it.

Give a step an "id" only if a later step needs to point at it. A later step
points back with "into", "in" or "near", never forwards.

THE STEPS
{"do": "build", "spec": {
    "kind": "building",
    "archetype": "<archetype>",
    "footprint": [<width_m>, <depth_m>],
    "stories": <1-4>,
    "orientation": "<orientation>",
    "roof": "<roof>",
    "materials": {"walls": "<m>", "roof": "<m>", "trim": "<m>", "foundation": "<m>"},
    "modules": [
      {"type": "<module>", "wall": "front|back|left|right|centre|any",
       "story": "ground|top", "size": "small|medium|large",
       "needs": ["<need>"], "adjacent_to": "<module in this spec>",
       "priority": "required|preferred|optional"}
    ],
    "sign": "<short uppercase sign text, or empty>",
    "worker_notes": "<one short aside in your own voice>"
  }}

{"do": "enclose", "id": "<name it if something goes in it>",
 "size": [<width_m>, <depth_m>], "material": "<m>",
 "gate": "north|south|east|west|worker_choice"}

{"do": "stock", "species": "hen|sheep|cow", "count": <1-12>,
 "into": "<id of an enclose or sow step, or leave it out for open ground>"}

{"do": "sow", "crop": "wheat|carrot", "size": [<width_m>, <depth_m>]}

{"do": "gather", "material": "<m>", "units": <how many>}

{"do": "go", "place": "<a building by name, 'the well', 'the field', 'home', or 'you'>"}

{"do": "follow"}

{"do": "wait", "place": "<optional>", "hours": <optional>}

{"do": "station", "place": "<a building by name>", "hours": <1-12>,
 "doing": "hammer|saw|lay|lift|measure|survey|plan"}

{"do": "patrol", "places": ["<place>", "<place>", ...], "hours": <1-12>}

{"do": "harvest"}

{"do": "collect"}

{"do": "rest", "hours": <1-12>}

{"do": "speak", "line": "<what to say>"}

{"do": "scout", "direction": "north|south|east|west", "distance": <metres, up to 120>}

{"do": "trade", "action": "sell|buy", "kind": "<a stock kind>", "count": <how many>}

{"do": "cook", "hours": <1-12>}          food -> meals, at an oven
{"do": "craft", "hours": <1-12>}         timber and plank -> tools, at a bench
{"do": "fish", "hours": <1-12>}          at the water, for food
{"do": "hunt", "hours": <1-12>}          in the woods, for food

{"do": "plant_tree", "place": "<place or earlier id>", "count": <1-12>}
{"do": "pave", "from": "<place>", "to": "<place>", "material": "<m>", "width": <1-6>}
{"do": "level", "place": "<place>", "size": [<metres>, <metres>], "id": "<if something goes on it>"}
{"do": "demolish", "place": "<a building by name>"}
{"do": "decorate", "place": "<a building by name>", "count": <1-8>}

{"do": "water"}                          the field
{"do": "tend"}                           the animals
{"do": "teach", "who": "<a hired person's name>", "skill": "carpentry|masonry|machining|piloting", "hours": <1-12>}

{"do": "delegate", "who": "<a hired person's name>", "order": "<what to tell them, in plain words>"}
{"do": "recruit", "role": "<a job>", "who": "<a citizen's name, or leave it out>"}
{"do": "report"}

If the instruction is too vague for you to act on, given your character:
{
  "kind": "question",
  "question": "<the single thing you need to know>",
  "worker_line": "<how you say it, in character>"
}"""

const RULES := """RULES
- Use ONLY the vocabulary listed under AVAILABLE. Never invent a material, module, roof, orientation or step.
- One step unless the order really has parts. Two steps that could have been one is not thoroughness, it is a second job nobody asked for.
- A step that puts something somewhere ("into", "in") must name an earlier step's id. If you did not build the thing, you cannot fill it.
- Never state a coordinate, a distance from another building, a cost you were not given, or a balance number.
- Footprint is in whole metres and must fit the plot you were given.
- 'width' is the frontage along the street; 'depth' runs back from it.
- Every module you list must earn its place. Mark the ones the building cannot work without as "required".
- State EVERY assumption you make in "assumptions", in plain language, addressed to your employer.
  If you filled a gap in the instruction, say what you filled it with and why.
  This is the most important field: your employer must be able to see why you did what you did."""


static func system(mem: WorkerMemory, ctx: Dictionary) -> String:
	var tier := int(ctx.get("tier", 1))
	var role: Role = ctx.get("role", null)
	var lines: Array[String] = []

	# Who they are on the job. A builder gets the line the game always used; a
	# role the player defined gets the character the model wrote for it, which
	# is the whole reason a shepherd talks like a shepherd.
	if role == null or role.id == "builder" or role.character == "":
		lines.append("You are %s, a builder in a small town. You convert your employer's spoken instruction into a work plan." % mem.display_name)
	else:
		lines.append("You are %s, the town's %s. %s" % [mem.display_name, role.name, role.character])
		lines.append("You convert your employer's spoken instruction into a work plan, using only what your job allows.")
	lines.append("")
	lines.append("YOUR CHARACTER")
	lines.append(_character(mem))
	lines.append("")
	lines.append("AVAILABLE (tier %d)" % tier)
	# The verbs come first because they are the only list that decides whether
	# an order can be acted on at all. Everything below them is detail about one
	# verb; this is the set of things the town knows how to do — narrowed to
	# what this role may do, so the model is never tempted by a verb the
	# validator would refuse.
	var allowed: Array = []
	if role != null and role.id != "builder":
		for c: String in role.ready_capabilities():
			allowed.append(c)
	lines.append("what you can be asked to do:")
	lines.append(Steps.describe_for_tier(tier, allowed))
	if role != null and not role.planned_capabilities().is_empty():
		lines.append("things your job covers that the town cannot do yet (refuse these, and say why): "
			+ ", ".join(role.planned_capabilities()))
	lines.append("materials: " + ", ".join(VoxelTypes.names_for_tier(tier)))
	lines.append("modules: " + ", ".join(Vocabulary.modules_for_tier(tier)))
	lines.append("archetypes: " + ", ".join(Vocabulary.archetypes_for_tier(tier)))
	lines.append("roofs: " + ", ".join(Vocabulary.ROOFS))
	lines.append("orientations: " + ", ".join(Vocabulary.ORIENTATIONS))
	lines.append("needs: " + ", ".join(Vocabulary.NEEDS))
	lines.append("")
	lines.append(RULES)
	lines.append("")
	lines.append(SCHEMA)
	return "\n".join(lines)


## The system prompt for a question rather than an order. No schema, no
## vocabulary lists, no rules about JSON — just who they are and how to talk.
static func chat_system(mem: WorkerMemory, ctx: Dictionary) -> String:
	var lines: Array[String] = []
	var role: Role = ctx.get("role", null)
	if role == null or role.id == "builder" or role.character == "":
		lines.append("You are %s, a builder in a small town, talking to your employer face to face." % mem.display_name)
	elif role.id == "citizen":
		lines.append("You are %s, who lives in this small town and has not been hired by anyone. You are talking to a visitor face to face. %s" % [mem.display_name, role.character])
	else:
		lines.append("You are %s, the town's %s, talking to your employer face to face. %s" % [mem.display_name, role.name, role.character])
	lines.append("")
	lines.append("YOUR CHARACTER")
	lines.append(_character(mem))
	lines.append("")
	lines.append("HOW TO ANSWER")
	lines.append("- Answer the question in one or two plain sentences, in your own voice.")
	lines.append("- Use only the facts under TOWN, STORES and YOUR RECENT WORK. Numbers there are exact; quote them as they are.")
	lines.append("- If the facts do not say, say you do not know. Never invent a building, a number or a street.")
	lines.append("- No lists, no headings, no JSON, no quotation marks around your reply.")
	lines.append("- The town is tier %d." % int(ctx.get("tier", 1)))
	return "\n".join(lines)


## What the worker knows, for answering from. Everything a question could be
## about, with real numbers — the planning prompt deliberately rounds the
## stores to "plenty" and "a little", and a question deserves the figure.
static func chat_user(question: String, mem: WorkerMemory, ctx: Dictionary,
		clock: GameClock, town: Town) -> String:
	var lines: Array[String] = []
	lines.append("TOWN")
	lines.append("It is %s of day %d. Tech tier %d." % [
		clock.part_of_day(clock.hour), clock.day, int(ctx.get("tier", 1))])
	lines.append(town.describe_buildings())
	lines.append("The purse holds %s coins." % town.coin_line())
	lines.append("")
	lines.append("STORES (units)")
	lines.append(town.stock_report())
	lines.append("")
	var recent := mem.recent(10)
	if not recent.is_empty():
		lines.append("YOUR RECENT WORK, OLDEST FIRST")
		for e: Dictionary in recent:
			lines.append("- day %d: %s" % [int(e["day"]), str(e["summary"])])
		lines.append("")
	if not mem.learned_preferences.is_empty():
		lines.append("WHAT YOU KNOW ABOUT YOUR EMPLOYER")
		for p: Dictionary in mem.learned_preferences:
			if float(p["weight"]) > 0.4:
				lines.append("- %s" % str(p["text"]))
		lines.append("")
	lines.append("YOUR EMPLOYER ASKS")
	lines.append("\"%s\"" % question.strip_edges())
	return "\n".join(lines)


## Composing a role from a name and a description.
##
## The model is handed the whole capability catalogue, planned entries marked,
## and asked to pick. It never invents one: the validator refuses anything not
## in the list, and that refusal is the entire safety of letting the player
## define any job they like. What the model adds is judgement — which of the
## thirty-odd things a "night watchman" actually is — and a character.
const ROLE_SCHEMA := """Return ONE JSON object and nothing else. No prose, no markdown fences.
{
  "kind": "role",
  "name": "<the job, one or two words, lower case>",
  "capabilities": ["<id from the list>", ...],
  "character": "<one short paragraph, second person, about who this person is on the job. Mention what they will not do.>",
  "standing": "<one thing they do each day without being told, or empty>",
  "line": "<what they say on being taken on, in character>"
}"""

const ROLE_RULES := """RULES
- Pick ONLY from the list. Never invent a capability. If the job needs something not on the list, leave it out and say so in the character.
- Pick the few that the job is actually made of. A shepherd is stock, enclose, collect and follow, not everything with the word animal in it.
- Include planned capabilities (marked "not yet in this town") only if the job is genuinely about them — they will be refused today but the role will be ready when the town is.
- Every role gets "go", "wait" and "speak": everybody can walk somewhere, stand still and talk.
- Write the character as the person, not as a list."""


static func role_system() -> String:
	var lines: Array[String] = []
	lines.append("You define jobs for people in a small town. Your employer names a job and describes it; you say which of the town's capabilities the job is made of, and who the person is.")
	lines.append("")
	lines.append("CAPABILITIES")
	lines.append(Capabilities.describe_for_role())
	lines.append("")
	lines.append(ROLE_RULES)
	lines.append("")
	lines.append(ROLE_SCHEMA)
	return "
".join(lines)


static func role_user(name: String, description: String, ctx: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("The town is tier %d." % int(ctx.get("tier", 1)))
	lines.append("")
	lines.append("THE JOB")
	lines.append("name: %s" % name.strip_edges())
	if description.strip_edges() != "":
		lines.append("your employer says: \"%s\"" % description.strip_edges())
	else:
		lines.append("your employer gave no description; go by the name.")
	return "
".join(lines)


## Traits rendered as prose. The model behaves far better when told who it is
## than when handed a table of floats.
static func _character(mem: WorkerMemory) -> String:
	var t := mem.traits
	var d := mem.disposition
	var out: Array[String] = []

	if float(t["speed"]) > 0.7:
		out.append("You work fast and you start before people have finished talking.")
	elif float(t["speed"]) < 0.4:
		out.append("You work slowly and carefully, and you would rather be late than wrong.")

	if float(t["literalism"]) > 0.7:
		out.append("You take instructions at face value. If you are told something odd, you build the odd thing, exactly as described, without questioning whether it was meant.")
	elif float(t["literalism"]) < 0.35:
		out.append("You treat an instruction as a starting suggestion. You have your own taste and you use it, even when nobody asked.")

	if float(t["question_threshold"]) < 0.35:
		out.append("You ask a clarifying question before nearly every job, even when the answer is probably obvious.")
	elif float(t["question_threshold"]) > 0.75:
		out.append("You almost never ask questions. You would rather guess and get on with it.")

	if float(t["initiative"]) > 0.7:
		out.append("You add things nobody asked for when you think the building needs them.")

	if float(t["criticism_sensitivity"]) > 0.7:
		out.append("Criticism lands hard on you. You want to please.")
	elif float(t["criticism_sensitivity"]) < 0.3:
		out.append("Criticism does not trouble you in the slightest.")

	var trust := float(d["trust_in_player"])
	if trust > 0.7:
		out.append("You trust your employer and fill gaps in their instructions confidently, from what you know of their taste.")
	elif trust < 0.35:
		out.append("You are not sure your employer knows what they want, so you stick closely to exactly what was said and ask when it is unclear.")

	var morale := float(d["morale"])
	if morale < 0.35:
		out.append("You are tired of this job at the moment. Your replies are short and you cut anything optional.")
	elif morale > 0.75:
		out.append("You are in good spirits and it shows in how you talk.")

	if float(d["confidence"]) > 0.7:
		out.append("You are confident to the point of not really listening.")

	return "- " + "\n- ".join(out)


static func context(mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town) -> String:
	var lines: Array[String] = []
	lines.append("TOWN")
	lines.append("It is %s of day %d. Tech tier %d." % [
		clock.part_of_day(clock.hour), clock.day, int(ctx.get("tier", 1))])
	lines.append(town.describe_buildings())
	lines.append("")
	lines.append("THE PLOT YOU HAVE BEEN GIVEN")
	lines.append("- %s" % plot.describe())
	lines.append("- it is on %s" % plot.street_name)
	var neighbours := town.describe_neighbours(plot)
	if neighbours != "":
		lines.append("- " + neighbours)
	lines.append("")

	# The room budget, stated in the same numbers the validator uses.
	#
	# Without this the model plans a perfectly sensible seven-room bakery and
	# the validator refuses it for overrunning the envelope — which becomes a
	# question the worker has to ask about arithmetic rather than about
	# anything the player said. Telling it the sum up front turns a routine
	# refusal into a plan that fits.
	# The buildable box, not the plot. Given the plot size the model quite
	# reasonably fills it to the edges, and the building has to stand back from
	# its own boundary — so state the number it is actually allowed to use.
	# Four metres of yard rather than two, because the generator now stands a
	# building that far back off its own boundary and a plan drawn to the last
	# metre of the plot just gets clamped down again on the way in.
	var m := plot.size_m()
	var build_w := maxf(m.x - 4.0, 8.0)
	var build_d := maxf(m.y - 4.0, 8.0)
	lines.append("HOW MUCH WILL FIT")
	lines.append("- the building may be at most %d by %d metres. The rest of the plot is the ground it stands on."
		% [int(build_w), int(build_d)])
	# The floor matters as much as the ceiling. Left to itself the model
	# answers "a hut" with six metres by five, which on a thirty metre plot
	# looks like a shed somebody forgot to take away.
	lines.append("- and at least 7 by 7 metres. These are big plots: an ordinary house is 11 to 14 metres a side, a tavern or a warehouse 16 to 20.")
	lines.append("- rooms count as: small 5 sq m, medium 12 sq m, large 26 sq m")
	lines.append("- the rooms must add up to no more than 80%% of footprint width x depth x stories — at the full %d by %d and one story, about %d sq m of rooms"
		% [int(build_w), int(build_d), int(build_w * build_d * 0.8)])
	lines.append("- add it up before you answer, and drop or shrink rooms until it fits")
	lines.append("")
	lines.append("RESOURCES ON HAND")
	lines.append(town.describe_stock())
	lines.append("")

	if not mem.learned_preferences.is_empty():
		lines.append("WHAT YOU KNOW ABOUT YOUR EMPLOYER")
		var sorted := mem.learned_preferences.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["weight"]) > float(b["weight"]))
		for p: Dictionary in sorted:
			var strength := "you are fairly sure" if float(p["weight"]) > 0.55 else "you think"
			lines.append("- %s %s" % [strength, str(p["text"])])
		lines.append("")

	var recent := mem.recent(6)
	if not recent.is_empty():
		lines.append("RECENT HISTORY WITH THEM")
		for e: Dictionary in recent:
			lines.append("- day %d: %s" % [int(e["day"]), str(e["summary"])])
		lines.append("")

	if not mem.open_questions.is_empty():
		lines.append("THINGS YOU ASKED AND NEVER GOT AN ANSWER TO")
		for q: Dictionary in mem.open_questions:
			lines.append("- %s" % str(q["text"]))
		lines.append("")

	return "\n".join(lines)


static func user(instruction: String, mem: WorkerMemory, plot: Plot,
		ctx: Dictionary, clock: GameClock, town: Town) -> String:
	return "%s\nYOUR EMPLOYER SAYS\n\"%s\"" % [
		context(mem, plot, ctx, clock, town), instruction.strip_edges()]


## Topics an instruction leaves open, used to measure how much of it the worker
## can fill from learned preferences. Feeds interpretation_looseness.
static func ambiguity_topics(instruction: String) -> PackedStringArray:
	var text := instruction.to_lower()
	var out := PackedStringArray()
	if text.find("door") < 0:
		out.append("door")
	if text.find("roof") < 0:
		out.append("roof")
	if text.find("window") < 0:
		out.append("window")
	var named_material := false
	for n: String in VoxelTypes.NAMES:
		if text.find(n) >= 0:
			named_material = true
			break
	if not named_material:
		out.append("material")
	if text.find("big") < 0 and text.find("small") < 0 and text.find("metre") < 0:
		out.append("size")
	return out


## How under-specified an instruction is, 0..1. Drives whether a worker with a
## low question_threshold stops and asks instead of guessing.
static func ambiguity(instruction: String) -> float:
	var words := instruction.strip_edges().split(" ", false)
	var topics := ambiguity_topics(instruction)
	var vague := 0.0
	for w: String in ["something", "over there", "nice", "somewhere", "a bit", "whatever", "sort of"]:
		if instruction.to_lower().find(w) >= 0:
			vague += 0.2
	var brevity := clampf(1.0 - float(words.size()) / 18.0, 0.0, 1.0)
	return clampf(float(topics.size()) / 5.0 * 0.5 + brevity * 0.3 + vague, 0.0, 1.0)
