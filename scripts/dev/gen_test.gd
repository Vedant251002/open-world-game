extends Node
class_name GenTest
## Acceptance harness for the generator, per build-order.md slice 2.
##
##   - five hardcoded specs produce watertight buildings with reachable interiors
##   - the same seed produces byte-identical voxels, every time
##   - a deliberately broken spec returns a typed GeneratorError, never geometry
##
## Run with:  godot --path . -- --gentest

var world: VoxelWorld
var village: Village
var gen: WorldGen
var failures := 0


static func specs() -> Array[Dictionary]:
	return [
		{
			"kind": "building", "archetype": "hut", "tech_tier": 1,
			"footprint": [11, 9], "stories": 1, "orientation": "face_street",
			"roof": "gable",
			"materials": {"walls": "timber", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "entrance", "wall": "front", "priority": "required"},
				{"type": "hearth", "wall": "back", "size": "small", "priority": "required"},
				{"type": "bed_area", "wall": "left", "size": "medium", "priority": "preferred"},
			],
			"sign": "",
		},
		{
			"kind": "building", "archetype": "bakery", "tech_tier": 1,
			"footprint": [16, 13], "stories": 1, "orientation": "face_street",
			"roof": "gable",
			"materials": {"walls": "plank", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "entrance", "wall": "front", "priority": "required"},
				{"type": "oven", "wall": "back", "size": "medium",
					"needs": ["chimney"], "adjacent_to": "storage", "priority": "required"},
				{"type": "storage", "wall": "right", "size": "small", "priority": "preferred"},
				{"type": "counter", "wall": "front", "size": "medium", "priority": "required"},
				{"type": "seating", "wall": "left", "size": "medium", "priority": "optional"},
			],
			"sign": "BREAD",
		},
		{
			"kind": "building", "archetype": "workshop", "tech_tier": 1,
			"footprint": [14, 17], "stories": 1, "orientation": "face_north",
			"roof": "shed",
			"materials": {"walls": "timber", "roof": "thatch",
				"trim": "dark_oak", "foundation": "gravel"},
			"modules": [
				{"type": "entrance", "wall": "front", "priority": "required"},
				{"type": "workbench", "wall": "right", "size": "large", "priority": "required"},
				{"type": "storage", "wall": "back", "size": "medium", "priority": "preferred"},
			],
			"sign": "WORKSHOP",
		},
		{
			"kind": "building", "archetype": "tavern", "tech_tier": 1,
			"footprint": [19, 15], "stories": 2, "orientation": "face_plaza",
			"roof": "hip",
			"materials": {"walls": "timber", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "entrance", "wall": "front", "story": "ground", "priority": "required"},
				{"type": "hearth", "wall": "back", "story": "ground",
					"size": "medium", "priority": "required"},
				{"type": "seating", "story": "ground", "size": "large", "priority": "required"},
				{"type": "counter", "wall": "left", "story": "ground",
					"size": "medium", "priority": "preferred"},
				{"type": "bed_area", "story": "top", "size": "medium", "priority": "preferred"},
				{"type": "storage", "story": "top", "size": "small", "priority": "optional"},
			],
			"sign": "THE LONG REST",
		},
		{
			"kind": "building", "archetype": "store", "tech_tier": 1,
			"footprint": [13, 13], "stories": 1, "orientation": "worker_choice",
			"roof": "flat",
			"materials": {"walls": "sandstone", "roof": "thatch",
				"trim": "dark_oak", "foundation": "cobble"},
			"modules": [
				{"type": "entrance", "wall": "front", "priority": "required"},
				{"type": "storage", "wall": "back", "size": "large", "priority": "required"},
				{"type": "counter", "wall": "front", "size": "small", "priority": "preferred"},
			],
			"sign": "STORE",
		},
	]


## A spec that must be rejected: three large rooms in a five metre shed.
static func broken_spec() -> Dictionary:
	return {
		"kind": "building", "archetype": "hut", "tech_tier": 1,
		"footprint": [4, 4], "stories": 1, "orientation": "face_street",
		"roof": "gable",
		"materials": {"walls": "timber", "roof": "thatch",
			"trim": "dark_oak", "foundation": "cobble"},
		"modules": [
			{"type": "entrance", "wall": "front", "priority": "required"},
			{"type": "seating", "size": "large", "priority": "required"},
			{"type": "storage", "size": "large", "priority": "required"},
			{"type": "oven", "size": "large", "needs": ["chimney"], "priority": "required"},
		],
	}


func run() -> int:
	print("\n=== slice 2: generator + validator ===")
	var ctx := {
		"world": world, "village": village, "worldgen": gen, "tier": 1,
		"occupied_rects": [], "built_fronts": {},
	}

	var all := specs()
	for i in all.size():
		var plot: Plot = village.plots[i * 3 % village.plots.size()]
		var t0 := Time.get_ticks_usec()
		var res := BuildingGenerator.build(all[i], 12345, plot, ctx)
		var us := Time.get_ticks_usec() - t0

		if not res["ok"]:
			_fail("spec %d (%s) rejected: %s — %s" % [i, all[i]["archetype"],
				res["error"]["code"], res["error"]["question"]])
			continue
		var patch: VoxelPatch = res["patch"]
		print("  [ok] %-9s %2dx%2d m  %d modules, %d props, %d voxels, %d cost, %.1f ms" % [
			all[i]["archetype"], int(all[i]["footprint"][0]), int(all[i]["footprint"][1]),
			patch.modules.size(), patch.props.size(), patch.touched,
			patch.total_cost_units(), us / 1000.0])
		if not patch.dropped_modules.is_empty():
			print("        dropped optional: %s" % ", ".join(patch.dropped_modules))

		# --- determinism: same inputs, byte-identical output ---
		var res2 := BuildingGenerator.build(all[i], 12345, plot, ctx)
		if not res2["ok"]:
			_fail("spec %d was accepted once and rejected once" % i)
		elif (res2["patch"] as VoxelPatch).data != patch.data:
			_fail("spec %d is not deterministic" % i)

		# --- a different seed must actually change something ---
		var res3 := BuildingGenerator.build(all[i], 999, plot, ctx)
		if res3["ok"] and (res3["patch"] as VoxelPatch).data == patch.data:
			print("        note: seed 999 produced identical voxels")

	# --- the broken spec must be refused, with a question ---
	var bad := BuildingGenerator.build(broken_spec(), 12345, village.plots[1], ctx)
	if bad["ok"]:
		_fail("the broken spec produced geometry instead of an error")
	else:
		print("  [ok] broken spec refused: %s" % bad["error"]["code"])
		print("        worker says: \"%s\"" % bad["error"]["question"])

	# --- an unknown material must be refused before generation ---
	var alien := specs()[0].duplicate(true)
	alien["materials"]["walls"] = "unobtanium"
	var ares := BuildingGenerator.build(alien, 1, village.plots[2], ctx)
	if ares["ok"]:
		_fail("an unknown material was accepted")
	else:
		print("  [ok] unknown material refused: %s" % ares["error"]["code"])

	# --- a tier 4 module must be refused at tier 1 ---
	var future := specs()[0].duplicate(true)
	future["modules"].append({"type": "reactor_housing", "priority": "required"})
	var fres := BuildingGenerator.build(future, 1, village.plots[2], ctx)
	if fres["ok"]:
		_fail("a tier 4 module was accepted at tier 1")
	else:
		print("  [ok] out-of-tier module refused: %s" % fres["error"]["code"])

	print("=== %s ===\n" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	return failures


func _fail(msg: String) -> void:
	failures += 1
	printerr("  [FAIL] " + msg)
