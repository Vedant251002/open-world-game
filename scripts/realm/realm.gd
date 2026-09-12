extends Node
class_name Realm
## The kingdom, as one door that every system of it plugs into.
##
## Law, weather, the market, the neighbours, the dynasty — each is its own
## file under scripts/realm/, and none of them touches Main, the dispatcher,
## the HUD or the answering layer directly. They talk to this. It hands them
## the world, routes orders and questions to whichever of them wants one,
## ticks them on the game clock, and keeps the chronicle they all write into.
##
## Two reasons for the indirection. The first is that a dozen systems each
## wiring themselves into main.gd is a dozen edits to one file, by people
## working at the same time, and that ends in tears. The second is that a
## system is loaded by path and skipped if it will not compile — so a
## half-written weather.gd is a missing weather, not a game that will not
## start.
##
## A system is a Node with `setup(realm)`, and any of these it cares to have:
##
##   try_order(worker, text) -> bool     an instruction it recognises; true if taken
##   try_answer(worker, text) -> String  a question it can answer; "" if not
##   on_day(day) / on_hour(hour, day)    the clock
##   hud_lines() -> Array[String]        short lines for the top-left roster
##   snapshot() -> Dictionary / restore(d)
##
## Systems reach the rest of the game through the fields below, say things
## with realm.say(), and write history with realm.chronicle.add().

signal status(text: String)

const SYSTEM_PATHS := [
	# Tier 1: the town is alive
	"res://scripts/realm/industry.gd",
	"res://scripts/realm/market.gd",
	# Tier 2: the world outside
	"res://scripts/realm/neighbours.gd",
	"res://scripts/realm/expansion.gd",
	"res://scripts/realm/weather.gd",
	# Tier 3: being a king
	"res://scripts/realm/law.gd",
	"res://scripts/realm/court.gd",
	"res://scripts/realm/dynasty.gd",
	"res://scripts/realm/faith.gd",
	# Tier 4: open-world texture
	"res://scripts/realm/riding.gd",
	"res://scripts/realm/foraging.gd",
	"res://scripts/realm/health.gd",
	"res://scripts/realm/upkeep.gd",
	# Tier 5: war with depth
	"res://scripts/realm/campaign.gd",
	# And the world talking back
	"res://scripts/realm/events.gd",
]

var world: VoxelWorld
var village: Village
var town: Town
var clock: GameClock
var player: Node3D
var crew: Crew
var livestock: Livestock
var wildlife: Wildlife
var warfare: Warfare
var nav: NavGrid
var props_root: Node3D
var farm: Farm
var dispatch: Node = null
var hud: Node = null
var sky: Node = null          ## SkyEnv: sun, moon, fog, the sky shader
var map: Node = null          ## MapScreen: note_building() and the like
var inventory: Node = null

var chronicle: Chronicle
var population: Population
var systems: Array[Node] = []
## The name of the place, once somebody gives it one.
var kingdom_name := "the town"
var kingdom_founded_day := 1


func setup(refs: Dictionary) -> void:
	world = refs.get("world")
	village = refs.get("village")
	town = refs.get("town")
	clock = refs.get("clock")
	player = refs.get("player")
	crew = refs.get("crew")
	livestock = refs.get("livestock")
	wildlife = refs.get("wildlife")
	warfare = refs.get("warfare")
	nav = refs.get("nav")
	props_root = refs.get("props_root")
	farm = refs.get("farm")
	dispatch = refs.get("dispatch")
	hud = refs.get("hud")
	sky = refs.get("sky")
	map = refs.get("map")
	inventory = refs.get("inventory")

	chronicle = Chronicle.new()
	chronicle.name = "Chronicle"
	add_child(chronicle)
	chronicle.setup(self)

	population = Population.new()
	population.name = "Population"
	add_child(population)
	population.setup(self)

	for path: String in SYSTEM_PATHS:
		_load_system(path)

	if clock != null:
		clock.day_passed.connect(_on_day)
		clock.hour_passed.connect(_on_hour)
	set_process(true)


## Loads one system if it exists and compiles. A missing file is a system
## nobody has written yet; a broken one is logged and skipped, and the rest of
## the kingdom carries on without it.
func _load_system(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var script: Variant = load(path)
	if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
		push_warning("[realm] %s did not load; skipping it" % path)
		return
	var node: Variant = (script as GDScript).new()
	if not (node is Node):
		push_warning("[realm] %s is not a Node; skipping it" % path)
		return
	(node as Node).name = path.get_file().get_basename().capitalize().replace(" ", "")
	add_child(node)
	if (node as Node).has_method("setup"):
		(node as Node).call("setup", self)
	systems.append(node)


func _process(delta: float) -> void:
	for s: Node in systems:
		if s.has_method("tick"):
			s.call("tick", delta)


# ------------------------------------------------------------------ routing

## An instruction the dispatcher did not recognise as a build, an errand or
## a question. First system to take it wins.
func handle(worker: Worker, text: String) -> bool:
	if population.has_method("try_order") and population.try_order(worker, text):
		return true
	for s: Node in systems:
		if s.has_method("try_order") and bool(s.call("try_order", worker, text)):
			return true
	return false


## A question the town's own records could not answer.
func answer(worker: Worker, text: String) -> String:
	var a := chronicle.try_answer(worker, text)
	if a != "":
		return a
	a = population.try_answer(worker, text)
	if a != "":
		return a
	for s: Node in systems:
		if s.has_method("try_answer"):
			var r := str(s.call("try_answer", worker, text))
			if r != "":
				return r
	return ""


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	for line: String in population.hud_lines():
		out.append(line)
	for s: Node in systems:
		if s.has_method("hud_lines"):
			for line: Variant in s.call("hud_lines"):
				out.append(str(line))
	return out


func _on_day(day: int) -> void:
	population.on_day(day)
	for s: Node in systems:
		if s.has_method("on_day"):
			s.call("on_day", day)


func _on_hour(hour: float, day: int) -> void:
	for s: Node in systems:
		if s.has_method("on_hour"):
			s.call("on_hour", hour, day)


## Something the player should see now, as a toast.
func say(text: String) -> void:
	status.emit(text)


## Something the player should be able to look up later.
func note(kind: String, text: String) -> void:
	chronicle.add(kind, text)


## Everything the kingdom needs written down, keyed by system name; each
## system that keeps state contributes its own dictionary.
func snapshot() -> Dictionary:
	var d := {
		"name": kingdom_name, "founded": kingdom_founded_day,
		"chronicle": chronicle.snapshot(),
		"population": population.snapshot(),
	}
	for s: Node in systems:
		if s.has_method("snapshot"):
			d[s.name] = s.call("snapshot")
	return d


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	kingdom_name = str(d.get("name", kingdom_name))
	kingdom_founded_day = int(d.get("founded", kingdom_founded_day))
	chronicle.restore(d.get("chronicle", {}))
	population.restore(d.get("population", {}))
	for s: Node in systems:
		if s.has_method("restore") and d.has(s.name):
			s.call("restore", d[s.name])


func system(name: String) -> Node:
	for s: Node in systems:
		if s.name.to_lower() == name.to_lower():
			return s
	return null


# ----------------------------------------------------------------- helpers
# Things several systems need and none should have to write twice.

## A standing building of this archetype, or {}.
func building(archetype: String) -> Dictionary:
	for rec: Dictionary in town.buildings:
		if str(rec["archetype"]) == archetype:
			return rec
	return {}


func buildings_of(archetype: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in town.buildings:
		if str(rec["archetype"]) == archetype:
			out.append(rec)
	return out


## Where a person stands to use a building: in front of its door.
func door_of(rec: Dictionary) -> Vector3:
	var patch: VoxelPatch = rec.get("patch", null)
	if patch == null:
		return Vector3.INF
	var fr := patch.footprint
	var v := VoxelChunk.VOXEL_M
	var centre := Vector3((fr.position.x + fr.size.x * 0.5) * v, 0.0,
		(fr.position.y + fr.size.y * 0.5) * v)
	var front: Vector3i = patch.front
	var half := (fr.size.x if absi(front.x) > 0 else fr.size.y) * v * 0.5
	var at := centre + Vector3(front) * (half + 2.0)
	at.y = world.ground_m(at.x, at.z)
	return at


## The first number in a sentence, or the default.
static func count_in(text: String, fallback: int) -> int:
	var words := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
		"five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
		"dozen": 12, "twenty": 20, "thirty": 30, "fifty": 50, "hundred": 100}
	for w: String in text.to_lower().split(" ", false):
		var t := w.rstrip(",.?!")
		if t.is_valid_int():
			return clampi(int(t), 0, 10000)
		if words.has(t):
			return int(words[t])
	return fallback


static func has_word(text: String, words: Array) -> bool:
	var t := " %s " % text.to_lower().replace(",", " ").replace(".", " ").replace("?", " ")
	for w: String in words:
		if t.find(" %s " % w) >= 0:
			return true
	return false


static func has_phrase(text: String, phrases: Array) -> bool:
	var t := text.to_lower()
	for p: String in phrases:
		if t.find(p) >= 0:
			return true
	return false
