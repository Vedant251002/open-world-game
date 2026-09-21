extends Node
class_name ToolTest
## What the player says is a tool call, not a guessed building.
##
## "Waht do you want" is not a question the keyword list knows, so it used to
## become a plan, a walk, and — once the model refused — a hut. reply is a
## tool. A hut is not the default. Run with: godot --path . -- --tooltest

var _fails: Array[String] = []


func _ready() -> void:
	var tools: Array = PlanSchema.tools_for(1, [])
	var names: Array[String] = []
	for t: Variant in tools:
		names.append(str(((t as Dictionary)["function"] as Dictionary)["name"]))
	if "reply" not in names:
		_fails.append("reply is not a tool")
	for verb: String in ["build", "go", "gather", "speak", "follow"]:
		if verb not in names:
			_fails.append("%s is not a tool" % verb)
	# A role that can only go must not be handed build.
	var narrow: Array = PlanSchema.tools_for(1, ["go"])
	var narrow_names: Array[String] = []
	for t2: Variant in narrow:
		narrow_names.append(str(((t2 as Dictionary)["function"] as Dictionary)["name"]))
	if "reply" not in narrow_names or "go" not in narrow_names or "build" in narrow_names:
		_fails.append("a go-only role was handed %s" % ", ".join(narrow_names))

	var talk := PlanSchema.from_tool_calls([{
		"name": "reply",
		"arguments": "{\"text\": \"Nothing in particular. What do you need?\"}",
	}])
	if str(talk.get("kind", "")) != "talk":
		_fails.append("a reply was kind %s" % str(talk.get("kind", "")))
	if str(talk.get("worker_line", "")).find("Nothing in particular") < 0:
		_fails.append("the reply text was dropped: %s" % str(talk.get("worker_line", "")))
	if not Steps.normalise(talk).is_empty():
		_fails.append("a reply produced work")

	var job := PlanSchema.from_tool_calls([
		{"name": "reply", "arguments": {"text": "The well, then."}},
		{"name": "go", "arguments": {"place": "well"}},
	])
	var steps := Steps.normalise(job)
	if steps.size() != 1 or str((steps[0] as Dictionary).get("do", "")) != "go":
		_fails.append("go did not come out as one step: %s" % str(steps))
	if str((steps[0] as Dictionary).get("place", "")) != "well":
		_fails.append("go lost its place")
	if str(job.get("worker_line", "")).find("well") < 0:
		_fails.append("the line said with the job was dropped")

	if ArchetypeLibrary.named_archetype("Waht do you want") != "":
		_fails.append("a typo named a building: %s" % ArchetypeLibrary.named_archetype("Waht do you want"))
	if ArchetypeLibrary.named_archetype("Hi") != "":
		_fails.append("a greeting named a building")
	if ArchetypeLibrary.named_archetype("build a hut") != "hut":
		_fails.append("build a hut did not name a hut")

	var mem := WorkerMemory.new()
	var none := ArchetypeLibrary.fallback("Waht do you want", mem, Plot.new(), 1)
	if not none.is_empty():
		_fails.append("an unnamed sentence still produced a plan")
	var hut := ArchetypeLibrary.fallback("build a hut", mem, Plot.new(), 1)
	if str(hut.get("kind", "")) == "talk" or Steps.normalise(hut).is_empty():
		_fails.append("build a hut produced no building")

	if _fails.is_empty():
		print("[tool] actions are tools, and an unnamed sentence is not a hut")
		get_tree().quit(0)
	else:
		for f: String in _fails:
			push_error("[tool] " + f)
			print("[tool] FAIL ", f)
		get_tree().quit(1)
