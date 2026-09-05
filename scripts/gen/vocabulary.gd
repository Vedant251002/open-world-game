extends RefCounted
class_name Vocabulary
## The closed vocabulary from voxel-module-spec.md §3, plus the engine-side
## module definitions the model never sees.
##
## Rule zero: the model emits intent from this list, the engine emits geometry.
## Adding a module or a material is an engine change, not a prompt change — so
## everything the model is allowed to say lives here, in one file, and the
## validator checks against exactly this.

const ORIENTATIONS := ["face_street", "face_plaza", "face_water", "face_north",
	"match_neighbour", "worker_choice"]
const ROOFS := ["flat", "gable", "hip", "shed", "sawtooth", "dome", "hangar_arch"]
const WALLS := ["front", "back", "left", "right", "centre", "any"]
const SIZES := ["small", "medium", "large"]
const NEEDS := ["chimney", "water", "power", "ventilation", "road_access", "runway_access"]
const FACES := ["entrance", "street", "interior", "runway"]
const PRIORITIES := ["required", "preferred", "optional"]

## Module catalogue by tech tier, per voxel-module-spec.md §3.3.
const TIER_MODULES := {
	1: ["entrance", "window_bank", "hearth", "oven", "counter", "seating",
		"storage", "workbench", "bed_area", "well", "stable", "pen", "sign",
		"stairwell", "cellar"],
	2: ["forge", "kiln", "mill", "assembly_line", "loading_dock", "chimney_stack",
		"office", "reception", "warehouse_rack", "crane_rail", "fuel_store",
		"water_tower", "rail_platform"],
	3: ["garage_bay", "lift", "server_room", "power_room", "generator", "hvac",
		"cold_store", "fuel_pump", "charge_point", "clinic_bay", "classroom",
		"retail_floor", "stockroom", "control_room", "comms_mast",
		"security_post", "armoury", "range_lane"],
	4: ["hangar_bay", "runway_apron", "helipad", "radar_dome", "fabrication_cell",
		"clean_room", "reactor_housing", "coolant_loop", "launch_pad",
		"drone_nest", "shield_pylon"],
}

## Archetypes the model may name. Purely a label for the town register and for
## worker dialogue — it never selects a prebuilt model.
const ARCHETYPES := {
	1: ["hut", "cottage", "workshop", "bakery", "store", "stable", "barn",
		"tavern", "well_house", "shrine", "guard_post", "smokehouse"],
	2: ["mill", "forge", "brickworks", "warehouse", "foundry", "inn",
		"pottery", "tannery", "station", "granary", "pump_house"],
	3: ["clinic", "school", "garage", "shop", "office", "power_house",
		"fire_station", "market_hall", "library", "depot"],
	4: ["aircraft_hangar", "fabrication_plant", "control_tower", "clean_lab",
		"reactor_house", "drone_yard", "launch_facility"],
}

## Engine-side module definitions. The model picks which and roughly where; all
## of this is ours.
##   min_m / max_m : footprint bounds in metres
##   height_m      : clear height the module wants
##   needs         : implied needs the model does not have to state
##   props         : Tier B furniture spawned inside, as [type, count]
##   wants_wall    : true if the module is meaningless without an exterior wall
##   blocks_window : the exterior wall in front of this module gets no windows
const MODULES := {
	# --- tier 1 ---
	"entrance":     {"min_m": [1.5, 1.5], "max_m": [5, 4],
		"props": [["mat", 1], ["lantern", 1], ["basket", 1]],
		"wants_wall": true, "blocks_window": false},
	"window_bank":  {"min_m": [2, 1.5], "max_m": [8, 3], "props": [],
		"wants_wall": true, "blocks_window": false},
	"hearth":       {"min_m": [2, 2], "max_m": [4, 3], "needs": ["chimney"],
		"props": [["hearth_fire", 1], ["firewood", 2], ["stool", 2], ["rug", 1]],
		"wants_wall": true},
	"oven":         {"min_m": [2, 2], "max_m": [5, 4], "needs": ["chimney"],
		"props": [["oven_block", 1], ["peel", 1], ["flour_sack", 2],
			["bread_tray", 1], ["basket", 2]], "wants_wall": true},
	"counter":      {"min_m": [2, 1], "max_m": [7, 3],
		"props": [["counter_block", 1], ["scale", 1], ["lantern", 1],
			["basket", 1], ["bread_tray", 1]]},
	"seating":      {"min_m": [2.5, 2.5], "max_m": [8, 8],
		"props": [["table", 3], ["stool", 6], ["bench", 2], ["lantern", 2],
			["rug", 1], ["tankard", 2]]},
	"storage":      {"min_m": [1.5, 1.5], "max_m": [6, 6],
		"props": [["crate", 4], ["barrel", 3], ["shelf", 2], ["basket", 2],
			["lantern", 1], ["pot", 2]], "blocks_window": true},
	"workbench":    {"min_m": [2, 1.5], "max_m": [6, 3],
		"props": [["bench", 1], ["tool_rack", 2], ["crate", 2], ["lantern", 1],
			["pot", 1]]},
	"bed_area":     {"min_m": [2, 2], "max_m": [6, 5],
		"props": [["bed", 1], ["chest", 1], ["rug", 1], ["candle", 1],
			["stool", 1], ["basket", 1]]},
	"well":         {"min_m": [2, 2], "max_m": [4, 4], "needs": ["water"],
		"props": [["bucket", 1]]},
	"stable":       {"min_m": [3, 3], "max_m": [9, 7], "needs": ["road_access"],
		"props": [["hay", 3], ["trough", 1]], "wants_wall": true},
	"pen":          {"min_m": [3, 3], "max_m": [10, 8], "props": [["trough", 1]]},
	"sign":         {"min_m": [1, 1], "max_m": [3, 1.5], "props": [["signboard", 1]],
		"wants_wall": true},
	"stairwell":    {"min_m": [1.5, 2.5], "max_m": [3, 5], "props": [["stair", 1]]},
	"cellar":       {"min_m": [2, 2], "max_m": [6, 6],
		"props": [["barrel", 4], ["crate", 2], ["lantern", 1]], "blocks_window": true},

	# --- tier 2 ---
	"forge":        {"min_m": [3, 3], "max_m": [7, 6], "needs": ["chimney", "ventilation"],
		"props": [["anvil", 1], ["forge_block", 1], ["tool_rack", 1]], "wants_wall": true},
	"kiln":         {"min_m": [2.5, 2.5], "max_m": [6, 5], "needs": ["chimney"],
		"props": [["kiln_block", 1], ["crate", 2]], "wants_wall": true},
	"mill":         {"min_m": [4, 4], "max_m": [10, 9], "needs": ["water"],
		"props": [["millstone", 1], ["flour_sack", 4]]},
	"assembly_line": {"min_m": [4, 2.5], "max_m": [16, 6], "needs": ["power"],
		"props": [["bench", 3], ["crate", 3]]},
	"loading_dock": {"min_m": [3, 3], "max_m": [10, 6], "needs": ["road_access"],
		"props": [["crate", 4], ["pallet", 2]], "wants_wall": true, "blocks_window": true},
	"chimney_stack": {"min_m": [1.5, 1.5], "max_m": [3, 3], "needs": ["chimney"],
		"props": []},
	"office":       {"min_m": [2.5, 2.5], "max_m": [7, 6],
		"props": [["desk", 1], ["stool", 2], ["shelf", 2], ["candle", 1],
			["rug", 1]]},
	"reception":    {"min_m": [2.5, 2], "max_m": [8, 5],
		"props": [["counter_block", 1], ["bench", 1]], "wants_wall": true},
	"warehouse_rack": {"min_m": [3, 2], "max_m": [14, 6],
		"props": [["shelf", 4], ["crate", 5]], "blocks_window": true},
	"crane_rail":   {"min_m": [4, 1.5], "max_m": [16, 3], "props": []},
	"fuel_store":   {"min_m": [2, 2], "max_m": [6, 5], "needs": ["ventilation"],
		"props": [["barrel", 4]], "blocks_window": true},
	"water_tower":  {"min_m": [2.5, 2.5], "max_m": [5, 5], "needs": ["water"], "props": []},
	"rail_platform": {"min_m": [4, 2], "max_m": [18, 5], "needs": ["road_access"],
		"props": [["bench", 2]], "wants_wall": true},

	# --- tier 3 ---
	"garage_bay":   {"min_m": [3.5, 5], "max_m": [9, 10], "needs": ["road_access"],
		"props": [["tool_rack", 1], ["pallet", 1]], "wants_wall": true, "blocks_window": true},
	"lift":         {"min_m": [2, 2], "max_m": [3.5, 3.5], "needs": ["power"], "props": []},
	"server_room":  {"min_m": [2.5, 2.5], "max_m": [7, 6], "needs": ["power", "ventilation"],
		"props": [["rack", 3]], "blocks_window": true},
	"power_room":   {"min_m": [2.5, 2.5], "max_m": [7, 6], "needs": ["power"],
		"props": [["generator_block", 1]], "blocks_window": true},
	"generator":    {"min_m": [2, 2], "max_m": [5, 5], "needs": ["ventilation"],
		"props": [["generator_block", 1]], "blocks_window": true},
	"hvac":         {"min_m": [2, 2], "max_m": [5, 5], "needs": ["ventilation"], "props": []},
	"cold_store":   {"min_m": [2, 2], "max_m": [7, 6], "needs": ["power"],
		"props": [["crate", 3]], "blocks_window": true},
	"fuel_pump":    {"min_m": [2, 2], "max_m": [5, 4], "needs": ["road_access"], "props": []},
	"charge_point": {"min_m": [1.5, 1.5], "max_m": [4, 3], "needs": ["power", "road_access"],
		"props": []},
	"clinic_bay":   {"min_m": [2.5, 3], "max_m": [7, 7], "needs": ["water", "power"],
		"props": [["bed", 2], ["shelf", 1]]},
	"classroom":    {"min_m": [4, 4], "max_m": [10, 9],
		"props": [["desk", 4], ["stool", 6]]},
	"retail_floor": {"min_m": [4, 4], "max_m": [16, 12],
		"props": [["shelf", 4], ["counter_block", 1]]},
	"stockroom":    {"min_m": [2.5, 2.5], "max_m": [8, 7],
		"props": [["shelf", 3], ["crate", 4]], "blocks_window": true},
	"control_room": {"min_m": [3, 3], "max_m": [8, 7], "needs": ["power"],
		"props": [["desk", 2], ["rack", 1]]},
	"comms_mast":   {"min_m": [1.5, 1.5], "max_m": [3, 3], "needs": ["power"], "props": []},
	"security_post": {"min_m": [2, 2], "max_m": [4, 4],
		"props": [["desk", 1], ["stool", 1]], "wants_wall": true},
	"armoury":      {"min_m": [2.5, 2.5], "max_m": [7, 6],
		"props": [["rack", 2], ["chest", 2]], "blocks_window": true},
	"range_lane":   {"min_m": [3, 8], "max_m": [6, 22], "props": [["bench", 1]],
		"blocks_window": true},

	# --- tier 4 ---
	"hangar_bay":   {"min_m": [10, 12], "max_m": [34, 30], "needs": ["runway_access"],
		"props": [["tool_rack", 2], ["pallet", 3]], "wants_wall": true, "blocks_window": true},
	"runway_apron": {"min_m": [8, 8], "max_m": [34, 20], "needs": ["runway_access"],
		"props": [], "wants_wall": true},
	"helipad":      {"min_m": [8, 8], "max_m": [18, 18], "props": []},
	"radar_dome":   {"min_m": [3, 3], "max_m": [8, 8], "needs": ["power"], "props": []},
	"fabrication_cell": {"min_m": [4, 4], "max_m": [14, 12], "needs": ["power", "ventilation"],
		"props": [["bench", 2], ["rack", 2]]},
	"clean_room":   {"min_m": [3, 3], "max_m": [10, 9], "needs": ["power", "ventilation"],
		"props": [["bench", 2]], "blocks_window": true},
	"reactor_housing": {"min_m": [5, 5], "max_m": [14, 14], "needs": ["power", "water"],
		"props": [["generator_block", 2]], "blocks_window": true},
	"coolant_loop": {"min_m": [3, 3], "max_m": [10, 8], "needs": ["water"], "props": []},
	"launch_pad":   {"min_m": [10, 10], "max_m": [24, 24], "props": []},
	"drone_nest":   {"min_m": [2.5, 2.5], "max_m": [7, 6], "needs": ["power"],
		"props": [["rack", 2]]},
	"shield_pylon": {"min_m": [2, 2], "max_m": [5, 5], "needs": ["power"], "props": []},
}


static func modules_for_tier(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in range(1, tier + 1):
		for m: String in TIER_MODULES.get(t, []):
			out.append(m)
	return out


static func archetypes_for_tier(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in range(1, tier + 1):
		for a: String in ARCHETYPES.get(t, []):
			out.append(a)
	return out


static func module_tier(module: String) -> int:
	for t in TIER_MODULES:
		if module in TIER_MODULES[t]:
			return t
	return 99


static func def(module: String) -> Dictionary:
	return MODULES.get(module, {})


## Implied needs plus the ones the model stated.
static func needs_of(module_spec: Dictionary) -> Array:
	var out: Array = []
	for n: String in def(module_spec.get("type", "")).get("needs", []):
		if n not in out:
			out.append(n)
	for n: Variant in module_spec.get("needs", []):
		if n is String and n not in out:
			out.append(n)
	return out


## Rough area in square metres a size class asks for.
static func size_area(size: String) -> float:
	match size:
		"small": return 5.0
		"large": return 26.0
		_: return 12.0


## Max stories the tier allows, per voxel-module-spec.md §3.1.
static func max_stories(tier: int) -> int:
	return 4 if tier <= 2 else 8
