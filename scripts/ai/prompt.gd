extends RefCounted
class_name Prompt
## Builds the instruction -> spec prompt, per game-design-doc.md §5.1.
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
  "spec": {
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
  },
  "assumptions": ["<plain sentence, addressed to your employer>", ...],
  "confidence": <0.0-1.0>,
  "worker_line": "<one line you say out loud before you leave>",
  "cost_estimate": {"<material>": <units>}
}

If the instruction is too vague for you to act on, given your character:
{
  "kind": "question",
  "question": "<the single thing you need to know>",
  "worker_line": "<how you say it, in character>"
}"""

const RULES := """RULES
- Use ONLY the vocabulary listed under AVAILABLE. Never invent a material, module, roof or orientation.
- Never state a coordinate, a distance from another building, a cost you were not given, or a balance number.
- Footprint is in whole metres and must fit the plot you were given.
- 'width' is the frontage along the street; 'depth' runs back from it.
- Every module you list must earn its place. Mark the ones the building cannot work without as "required".
- State EVERY assumption you make in "assumptions", in plain language, addressed to your employer.
  If you filled a gap in the instruction, say what you filled it with and why.
  This is the most important field: your employer must be able to see why you did what you did."""


static func system(mem: WorkerMemory, ctx: Dictionary) -> String:
	var tier := int(ctx.get("tier", 1))
	var lines: Array[String] = []

	lines.append("You are %s, a builder in a small town. You convert your employer's spoken instruction into a work plan." % mem.display_name)
	lines.append("")
	lines.append("YOUR CHARACTER")
	lines.append(_character(mem))
	lines.append("")
	lines.append("AVAILABLE (tier %d)" % tier)
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
	var m := plot.size_m()
	var build_w := maxf(m.x - 2.0, 4.0)
	var build_d := maxf(m.y - 2.0, 4.0)
	lines.append("HOW MUCH WILL FIT")
	lines.append("- the building may be at most %d by %d metres. The rest of the plot is the ground it stands on."
		% [int(build_w), int(build_d)])
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

	var recent := mem.recent(3)
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
