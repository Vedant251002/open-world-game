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
