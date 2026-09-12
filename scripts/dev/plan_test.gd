extends Node
class_name PlanTest
## What the town actually does with a sentence.
##
## Runs instructions through the offline planner and the pre-validator — the
## whole brain of an exported build, since those ship without an API key — and
## prints what each one becomes. Every case here is one a player typed and got
## something wrong back.
##
## The rule being tested is not "everything works". It is that nothing is
## silently substituted: a request the town cannot meet must come back as a
## sentence saying so, and a request it can meet must come back as the thing
## that was asked for.

var world: VoxelWorld
var village: Village
var gen: WorldGen

## instruction -> what should happen.
##   {"arch": expected archetype, "floors": expected stories,
##    "refuse": error code we expect, or "" to expect a buildable plan}
const CASES := [
	{"say": "build a ten floor building", "arch": "hut", "floors": 10,
		"refuse": "bad_stories"},
	{"say": "build a ten floor apartment block", "arch": "apartment", "floors": 10,
		"refuse": "archetype_above_tier"},
	{"say": "build an airport", "arch": "aircraft_hangar", "floors": 0,
		"refuse": "archetype_above_tier"},
	{"say": "build a hangar for the planes", "arch": "aircraft_hangar",
		"floors": 0, "refuse": "archetype_above_tier"},
	{"say": "build a tower block", "arch": "tower_block", "floors": 0,
		"refuse": "archetype_above_tier"},
	{"say": "build a two floor cottage", "arch": "cottage", "floors": 2,
		"refuse": ""},
	{"say": "build a small bakery", "arch": "bakery", "floors": 0, "refuse": ""},
	{"say": "put up a 2 storey workshop", "arch": "workshop", "floors": 2,
		"refuse": ""},
	{"say": "build a big tavern", "arch": "tavern", "floors": 0, "refuse": ""},
]

## Multi-step plans, as the model would return them, checked against the same
## pre-validator the game runs.
##
## These are written out by hand rather than asked for, because what is being
## tested is the boundary and not the model: given this exact JSON, does the
## town accept it, and when it refuses does it refuse for the right reason and
## in a sentence a worker could say? The first case is the one this whole thing
## was built for — the order that used to match on the word "hens", go straight
## to the flock, and leave the fence unbuilt and unmentioned.
const PLANS := [
	{"name": "fence a pen and put hens in it",
		"steps": [
			{"do": "enclose", "id": "coop", "size": [8, 6], "material": "timber",
				"gate": "south"},
			{"do": "stock", "species": "hen", "count": 6, "into": "coop"},
		], "refuse": ""},
	{"name": "one building, the old shape",
		"steps": [
			{"do": "build", "spec": {"kind": "building", "archetype": "cottage",
				"footprint": [13, 11], "stories": 1, "orientation": "face_street",
				"roof": "gable",
				"materials": {"walls": "timber", "roof": "thatch"},
				"modules": [{"type": "entrance", "wall": "front",
					"priority": "required"}]}},
		], "refuse": ""},
	{"name": "sow a field then fence it",
		"steps": [
			{"do": "sow", "id": "plot", "crop": "wheat", "size": [6, 6]},
			{"do": "enclose", "size": [9, 9], "material": "timber",
				"near": "plot"},
		], "refuse": ""},
	{"name": "hens into a pen nobody built",
		"steps": [
			{"do": "stock", "species": "hen", "count": 6, "into": "coop"},
		], "refuse": "dangling_reference"},
	{"name": "hens into an errand",
		"steps": [
			{"do": "gather", "id": "wood", "material": "timber", "units": 40},
			{"do": "stock", "species": "hen", "count": 4, "into": "wood"},
		], "refuse": "reference_has_no_ground"},
	{"name": "a pen the size of a field",
		"steps": [{"do": "enclose", "size": [40, 40], "material": "timber"}],
		"refuse": "enclosure_too_large"},
	{"name": "an animal we have never seen",
		"steps": [{"do": "stock", "species": "ostrich", "count": 2}],
		"refuse": "unknown_species"},
	{"name": "a verb nobody taught us",
		"steps": [{"do": "summon", "target": "the tavern"}],
		"refuse": "unknown_verb"},
	{"name": "a fence made of something we have not got",
		"steps": [{"do": "enclose", "size": [6, 6], "material": "carbon_composite"}],
		"refuse": "material_above_tier"},
	{"name": "a project, not an order",
		"steps": [
			{"do": "enclose", "size": [6, 6]}, {"do": "enclose", "size": [6, 6]},
			{"do": "enclose", "size": [6, 6]}, {"do": "enclose", "size": [6, 6]},
			{"do": "enclose", "size": [6, 6]},
		], "refuse": "plan_too_long"},
]

var _fails: Array[String] = []


func run() -> int:
	var mem := WorkerMemory.make("mira", "Mira",
		{"speed": 0.9, "literalism": 0.9, "initiative": 0.4,
			"question_threshold": 0.9, "criticism_sensitivity": 0.9},
		{"trust_in_player": 0.6, "morale": 0.8, "confidence": 0.5},
		{"carpentry": 1, "masonry": 1, "machining": 0, "piloting": 0})
	var plot: Plot = village.plots[0]
	var town := Town.new()
	var ctx := {
		"world": world, "village": village, "worldgen": gen, "tier": town.tier,
		"occupied_rects": [], "built_fronts": {},
	}
	print("[plan] town is tier %d, which allows up to %d floors" % [
		town.tier, Vocabulary.max_stories(town.tier)])

	for c: Dictionary in CASES:
		_check(str(c["say"]), c, mem, plot, ctx)

	print("[plan] ---")
	for c: Dictionary in PLANS:
		_check_plan(c, plot, ctx)
	_check_enclosure(ctx)
	_check_schema()
	_check_standing_sentences()
	_check_learning(plot, ctx)

	print("[plan] ---")
	for f: String in _fails:
		print("[plan] FAIL: %s" % f)
	print("[plan] %s" % ("=== PASS ===" if _fails.is_empty() else "=== FAIL ==="))
	return 1 if not _fails.is_empty() else 0


func _check(say: String, want: Dictionary, mem: WorkerMemory, plot: Plot,
		ctx: Dictionary) -> void:
	var plan := ArchetypeLibrary.fallback(say, mem, plot, int(ctx["tier"]))
	var spec: Dictionary = plan["spec"]
	var arch := str(spec.get("archetype", "?"))
	var floors := int(spec.get("stories", 1))
	var err := Validator.check_spec(spec, plot, ctx)
	var code := str(err.get("code", "")) if not err.is_empty() else ""
	var said := str(err.get("question", "")) if not err.is_empty() else ""

	print("[plan] %-36s -> %-16s %d floor(s)  %s" % [
		'"' + say + '"', arch, floors,
		("refused: " + code) if code != "" else "buildable"])
	if said != "":
		print("[plan]      the worker says: %s" % said)

	if arch != str(want["arch"]):
		_fails.append("%s became a %s, expected a %s" % [say, arch, want["arch"]])
	var want_floors := int(want["floors"])
	if want_floors > 0 and floors != want_floors:
		_fails.append("%s planned %d floors, expected %d" % [say, floors, want_floors])
	if code != str(want["refuse"]):
		_fails.append("%s gave '%s', expected '%s'" % [
			say, code if code != "" else "no refusal",
			str(want["refuse"]) if str(want["refuse"]) != "" else "no refusal"])


## Every preset's standing task has to come out of the offline planner as the
## verb it names. The morning routine hands these sentences to the planner
## unaided, and one that fell through to the building planner would have the
## accountant putting up a hut at dawn.
func _check_standing_sentences() -> void:
	var want := {
		"bring in whatever is ripe each morning": "harvest",
		"cook a shift each morning": "cook",
		"work a shift at the store each day": "station",
		"give an account each morning": "report",
		"walk the round from the well to the edge of town all night": "patrol",
	}
	for sentence: String in want:
		var plan := ArchetypeLibrary.errand_plan(sentence)
		var verb := ""
		if not plan.is_empty():
			verb = str((plan["steps"][0] as Dictionary).get("do", ""))
		print("[plan] %-58s -> %s" % ['"' + sentence + '"', verb if verb != "" else "(a building)"])
		if verb != str(want[sentence]):
			_fails.append("'%s' became %s, expected %s" % [sentence,
				verb if verb != "" else "a building", str(want[sentence])])
		if verb == "patrol":
			var places: Array = (plan["steps"][0] as Dictionary).get("places", [])
			if places.size() != 2:
				_fails.append("the watchman's round has %d places: %s" % [places.size(), str(places)])


## The correction loop: a sentence is read as a preference about one field,
## it is learned, and the next offline plan honours it. This is what makes
## the crew get better at a player over time without a key.
func _check_learning(plot: Plot, ctx: Dictionary) -> void:
	var cases := {
		"no, I wanted a thatch roof": ["roof_material", "thatch"],
		"never use brick": ["walls", "not:brick"],
		"too big": ["size", "smaller"],
		"I like a flat roof": ["roof", "flat"],
		"make them all two floors": ["stories", "2"],
		"the door should face the plaza": ["orientation", "face_plaza"],
		"I don't want seating": ["module", "not:seating"],
		"remember, always put in a chimney": ["module", "hearth"],
		"no, stone walls": ["walls", "cobble"],
		"it should have been smaller": ["size", "smaller"],
	}
	for say: String in cases:
		var got := Critique.read(say)
		var want: Array = cases[say]
		var ok := str(got.get("about", "")) == str(want[0]) and str(got.get("value", "")) == str(want[1])
		print("[plan] %-40s -> %s = %s   %s" % ['"' + say + '"', str(got.get("about", "-")),
			str(got.get("value", "-")), "" if ok else "(wanted %s = %s)" % [want[0], want[1]]])
		if not ok:
			_fails.append("'%s' was read as %s=%s, expected %s=%s" % [say,
				str(got.get("about", "-")), str(got.get("value", "-")), want[0], want[1]])
		if ok and str(got.get("text", "")) == "":
			_fails.append("'%s' learned nothing sayable" % say)
	# Not corrections, and must not be mistaken for them.
	for say2: String in ["build a hut", "bring some hens", "go to the well", "what do we have?",
			"i want a hut", "remember to build a hut", "i want six hens", "demolish the hut",
			"every morning, go to the well", "plant 3 trees", "tell mira to go to the well",
			"hire you as a shepherd", "sell 20 timber", "feed the sheep", "fence a pen and put 4 sheep in it",
			"bring in whatever is ripe each morning", "work a shift at the store each day",
			"walk the round from the well to the edge of town all night", "build a small bakery near the well"]:
		if not Critique.read(say2).is_empty():
			_fails.append("'%s' was taken as a correction" % say2)
	# A bare "no" is a question back, not a lesson.
	var bare := Critique.read("no")
	if bare.is_empty() or str(bare.get("about", "x")) != "":
		_fails.append("a bare 'no' should be a correction with no topic")

	# And then the part that matters: what is learned changes the next plan.
	var mem := WorkerMemory.make("t", "T",
		{"speed": 0.5, "literalism": 0.5, "initiative": 0.5, "question_threshold": 0.5,
			"criticism_sensitivity": 0.5},
		{"trust_in_player": 0.5, "morale": 0.7, "confidence": 0.5},
		{"carpentry": 1, "masonry": 1, "machining": 0, "piloting": 0})
	var before: Dictionary = ArchetypeLibrary.fallback("build a hut", mem, plot, int(ctx["tier"]))["spec"]
	var base_fp: Array = before["footprint"]
	for say3: String in ["no, I wanted a thatch roof", "always keep them small",
			"never use timber", "I don't want storage", "make them all two floors"]:
		var l := Critique.read(say3)
		mem.learn_about(str(l["about"]), str(l["value"]), str(l["text"]), float(l["weight"]), 0)
	var after: Dictionary = ArchetypeLibrary.fallback("build a hut", mem, plot, int(ctx["tier"]))["spec"]
	var mats: Dictionary = after["materials"]
	var fp: Array = after["footprint"]
	var kinds: Array[String] = []
	for m: Dictionary in after["modules"]:
		kinds.append(str(m["type"]))
	print("[plan] after five lessons, a hut is: %s walls, %s roof, %d floors, %.0f x %.0f m, rooms %s" % [
		str(mats["walls"]), str(mats["roof"]), int(after["stories"]), float(fp[0]), float(fp[1]),
		", ".join(kinds)])
	if str(mats["roof"]) != "thatch":
		_fails.append("the roof is %s, not thatch" % str(mats["roof"]))
	if str(mats["walls"]) == "timber":
		_fails.append("the walls are still timber after 'never use timber'")
	if float(fp[0]) >= float(base_fp[0]):
		_fails.append("the hut did not get smaller (%.0f vs %.0f)" % [float(fp[0]), float(base_fp[0])])
	if "storage" in kinds:
		_fails.append("storage is still in after 'I don't want storage'")
	if int(after["stories"]) != 2:
		_fails.append("the hut has %d floors, not 2" % int(after["stories"]))
	# The prompt says so too.
	var prose := Prompt.context(mem, plot, ctx, GameClock.new(), Town.new())
	if prose.find("thatch") < 0:
		_fails.append("the prompt does not mention thatch after learning it")
	# A newer wish for the same field replaces the older one.
	var l2 := Critique.read("no, clay tile roofs")
	mem.learn_about(str(l2["about"]), str(l2["value"]), str(l2["text"]), float(l2["weight"]), 0)
	if mem.wants("roof_material") != "clay_tile":
		_fails.append("the newer roof wish did not replace the older one")
	var n_roof := 0
	for p2: Dictionary in mem.learned_preferences:
		if str(p2.get("about", "")) == "roof_material":
			n_roof += 1
	if n_roof != 1:
		_fails.append("%d roof preferences are held at once" % n_roof)


## A step plan through the pre-validator, which is the only gate between the
## model and the town doing something.
func _check_plan(want: Dictionary, plot: Plot, ctx: Dictionary) -> void:
	var steps: Array = want["steps"]
	var err := Validator.check_plan(steps, plot, ctx)
	var code := str(err.get("code", "")) if not err.is_empty() else ""
	var said := str(err.get("question", "")) if not err.is_empty() else ""

	var shape: Array[String] = []
	for s: Variant in steps:
		shape.append(str((s as Dictionary).get("do", "?")))
	print("[plan] %-34s -> %-28s %s" % [
		'"' + str(want["name"]) + '"', " then ".join(shape),
		("refused: " + code) if code != "" else "accepted"])
	if said != "":
		print("[plan]      the worker says: %s" % said)

	if code != str(want["refuse"]):
		_fails.append("%s gave '%s', expected '%s'" % [
			str(want["name"]), code if code != "" else "no refusal",
			str(want["refuse"]) if str(want["refuse"]) != "" else "no refusal"])
	# Every refusal is a sentence somebody says out loud, not an error code with
	# a colon in it. That is pillar P3, and it is worth a test of its own
	# because it is the one property that silently stops being true.
	if code != "" and (said == "" or said.length() < 12 or said.find("_") >= 0):
		_fails.append("%s refused with '%s', which is not a sentence"
			% [str(want["name"]), said])


## The enclosure generator end to end: real ground, real voxels, a real gate.
func _check_enclosure(ctx: Dictionary) -> void:
	var step := {"do": "enclose", "size": [8, 6], "material": "timber",
		"gate": "south"}
	var near := village.well_pos + Vector3(22, 0, 18)
	var want := Vector2i(int(8.0 / VoxelChunk.VOXEL_M), int(6.0 / VoxelChunk.VOXEL_M))
	var site := EnclosureGenerator.find_site(world, near, want, [])
	if site.size.x == 0:
		_fails.append("found no open ground for an 8 by 6 pen near the well")
		print("[plan] enclosure                         -> NO GROUND")
		return

	var res := EnclosureGenerator.build(step, world, site, ctx)
	if not res["ok"]:
		_fails.append("enclosure refused: %s"
			% str((res["error"] as Dictionary).get("code", "?")))
		return

	var patch: VoxelPatch = res["patch"]
	var bill := Resources.bill(patch.cost)
	print("[plan] enclosure 8x6 timber              -> %d voxels, %s, gate %s" % [
		patch.touched, Resources.describe(bill), str(res["gate"])])

	# A pen the town could never pay for is a pen nobody will ever see, so the
	# cost is a test and not a statistic. A cottage runs to a few hundred units;
	# a fence has no business being in that range.
	var units := 0
	for m: String in bill:
		units += int(bill[m])
	if units > 60:
		_fails.append("an 8 by 6 pen costs %d units, which is house money" % units)
	if patch.doors.is_empty():
		_fails.append("the pen has no gate")
	if patch.build_order.size() != patch.touched:
		_fails.append("the pen's build order covers %d of %d voxels"
			% [patch.build_order.size(), patch.touched])


## The JSON Schema handed to the gateway.
##
## Generated from the same tables the prompt and the validator read, so the
## thing worth testing is not its contents but that it stays in step: a verb
## that exists in Steps and not in the schema is a verb the model will be
## prevented from using, which looks exactly like the model being stupid.
func _check_schema() -> void:
	for tier in [1, 4]:
		var wrapper := PlanSchema.for_tier(tier)
		var schema: Dictionary = wrapper["schema"]
		var text := JSON.stringify(wrapper)
		if JSON.new().parse(text) != OK:
			_fails.append("the tier %d schema is not valid JSON" % tier)
			continue

		var steps: Dictionary = schema["properties"]["steps"]
		var variants: Array = steps["items"]["anyOf"]
		var covered: Array[String] = []
		for v: Variant in variants:
			var props: Dictionary = (v as Dictionary)["properties"]
			covered.append(str((props["do"] as Dictionary)["enum"][0]))
		for verb: String in Steps.VERBS:
			if Steps.verb_tier(verb) <= tier and verb not in covered:
				_fails.append("tier %d schema is missing the %s step" % [tier, verb])

		print("[plan] tier %d schema: %d verbs, %d bytes of JSON" % [
			tier, covered.size(), text.length()])

	# A schema the size of the prompt is a schema that eats the token budget it
	# was added to protect. Groq's free tier allows 8K tokens a minute, and the
	# schema is sent on every single call. The builder's is the biggest, with
	# every verb in it; a role's is only its own verbs, and has to be small.
	var t1 := JSON.stringify(PlanSchema.for_tier(1))
	if t1.length() > 14000:
		_fails.append("the builder's tier 1 schema is %d bytes — too much of the budget"
			% t1.length())
	var shepherd := JSON.stringify(PlanSchema.for_tier(1,
		["go", "wait", "speak", "stock", "enclose", "collect", "tend"]))
	print("[plan] a shepherd's schema: %d bytes" % shepherd.length())
	if shepherd.length() > 4000:
		_fails.append("a shepherd's schema is %d bytes — the role filter is not narrowing it"
			% shepherd.length())
