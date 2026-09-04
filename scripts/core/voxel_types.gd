extends RefCounted
class_name VoxelTypes
## The closed material enum from voxel-module-spec.md §2.
##
## The LLM may only ever name a material from NAMES. Every physical and visual
## property below is engine-owned: the model chooses *brick*, the engine decides
## what brick costs and how hard it is to knock down.

const AIR := 0

# --- STRUCTURAL ---
const TIMBER := 1
const PLANK := 2
const BRICK := 3
const SANDSTONE := 4
const GRANITE := 5
const CONCRETE := 6
const REBAR_CONCRETE := 7
const STEEL_FRAME := 8
const CORRUGATED_STEEL := 9
const GLASS := 10
const REINFORCED_GLASS := 11
const PLASTIC_PANEL := 12
const CARBON_COMPOSITE := 13

# --- SURFACE ---
const THATCH := 14
const CLAY_TILE := 15
const ASPHALT_SHINGLE := 16
const SHEET_METAL := 17
const SOLAR_PANEL := 18

# --- GROUND ---
const DIRT := 19
const GRAVEL := 20
const COBBLE := 21
const ASPHALT := 22
const CONCRETE_SLAB := 23
const GRASS := 24
const SAND := 25

# --- TRIM ---
const DARK_OAK := 26
const PAINTED_WHITE := 27
const PAINTED_RED := 28
const CHROME := 29
const MATTE_BLACK := 30
const NEON_STRIP := 31

# --- engine-only (never nameable by the model) ---
const WATER := 32
const STONE := 33
const ROCK := 34
const LEAF := 35
const BARK := 36

const COUNT := 37

## name -> id. This dictionary IS the closed enum the validator checks against.
const NAMES := {
	"timber": TIMBER, "plank": PLANK, "brick": BRICK, "sandstone": SANDSTONE,
	"granite": GRANITE, "concrete": CONCRETE, "rebar_concrete": REBAR_CONCRETE,
	"steel_frame": STEEL_FRAME, "corrugated_steel": CORRUGATED_STEEL,
	"glass": GLASS, "reinforced_glass": REINFORCED_GLASS,
	"plastic_panel": PLASTIC_PANEL, "carbon_composite": CARBON_COMPOSITE,
	"thatch": THATCH, "clay_tile": CLAY_TILE, "asphalt_shingle": ASPHALT_SHINGLE,
	"sheet_metal": SHEET_METAL, "solar_panel": SOLAR_PANEL,
	"dirt": DIRT, "gravel": GRAVEL, "cobble": COBBLE, "asphalt": ASPHALT,
	"concrete_slab": CONCRETE_SLAB, "grass": GRASS, "sand": SAND,
	"dark_oak": DARK_OAK, "painted_white": PAINTED_WHITE,
	"painted_red": PAINTED_RED, "chrome": CHROME, "matte_black": MATTE_BLACK,
	"neon_strip": NEON_STRIP,
}

## Which category a material belongs to, used by the validator to reject e.g.
## "roof": "dirt".
const STRUCTURAL := ["timber", "plank", "brick", "sandstone", "granite",
	"concrete", "rebar_concrete", "steel_frame", "corrugated_steel", "glass",
	"reinforced_glass", "plastic_panel", "carbon_composite"]
const SURFACE := ["thatch", "clay_tile", "asphalt_shingle", "sheet_metal", "solar_panel"]
const GROUND := ["dirt", "gravel", "cobble", "asphalt", "concrete_slab", "grass", "sand"]
const TRIM := ["dark_oak", "painted_white", "painted_red", "chrome", "matte_black", "neon_strip"]

## Engine-side properties. tech_tier gates availability; cost drives the economy;
## the rest drive rendering and (later) destruction.
##   [albedo, roughness, metallic, emission_energy, tech_tier, cost, hardness, transparent]
const PROPS := {
	AIR:               [Color(0, 0, 0, 0), 1.0, 0.0, 0.0, 1, 0, 0, true],
	TIMBER:            [Color("#7d5a3c"), 0.90, 0.0, 0.0, 1, 1, 20, false],
	PLANK:             [Color("#a8804f"), 0.85, 0.0, 0.0, 1, 1, 18, false],
	BRICK:             [Color("#98462f"), 0.88, 0.0, 0.0, 2, 2, 40, false],
	SANDSTONE:         [Color("#c9ac7c"), 0.92, 0.0, 0.0, 1, 2, 45, false],
	GRANITE:           [Color("#5e5b58"), 0.72, 0.0, 0.0, 1, 3, 70, false],
	CONCRETE:          [Color("#9d9c98"), 0.90, 0.0, 0.0, 3, 3, 65, false],
	REBAR_CONCRETE:    [Color("#88898a"), 0.86, 0.0, 0.0, 3, 5, 110, false],
	STEEL_FRAME:       [Color("#5a6068"), 0.45, 0.85, 0.0, 2, 5, 95, false],
	CORRUGATED_STEEL:  [Color("#7e878e"), 0.50, 0.75, 0.0, 2, 3, 55, false],
	GLASS:             [Color("#a9d4de", 0.28), 0.22, 0.0, 0.0, 2, 4, 5, true],
	REINFORCED_GLASS:  [Color("#9ec4d0", 0.42), 0.25, 0.0, 0.0, 3, 8, 35, true],
	PLASTIC_PANEL:     [Color("#d8d4c8"), 0.55, 0.0, 0.0, 3, 3, 15, false],
	CARBON_COMPOSITE:  [Color("#2c2f34"), 0.35, 0.25, 0.0, 4, 12, 130, false],
	THATCH:            [Color("#b39152"), 0.98, 0.0, 0.0, 1, 1, 8, false],
	CLAY_TILE:         [Color("#8f4630"), 0.80, 0.0, 0.0, 2, 2, 25, false],
	ASPHALT_SHINGLE:   [Color("#40403f"), 0.95, 0.0, 0.0, 3, 2, 22, false],
	SHEET_METAL:       [Color("#8b949b"), 0.40, 0.80, 0.0, 2, 3, 40, false],
	SOLAR_PANEL:       [Color("#1a2a4a"), 0.18, 0.35, 0.0, 4, 9, 20, false],
	DIRT:              [Color("#6b533a"), 1.00, 0.0, 0.0, 1, 0, 6, false],
	GRAVEL:            [Color("#736e63"), 0.98, 0.0, 0.0, 1, 1, 10, false],
	COBBLE:            [Color("#66625c"), 0.88, 0.0, 0.0, 1, 1, 30, false],
	ASPHALT:           [Color("#37393c"), 0.94, 0.0, 0.0, 3, 2, 25, false],
	CONCRETE_SLAB:     [Color("#807f79"), 0.90, 0.0, 0.0, 2, 2, 55, false],
	GRASS:             [Color("#496f38"), 1.00, 0.0, 0.0, 1, 0, 4, false],
	SAND:              [Color("#c0aa7d"), 1.00, 0.0, 0.0, 1, 0, 3, false],
	DARK_OAK:          [Color("#4a3524"), 0.80, 0.0, 0.0, 1, 2, 20, false],
	PAINTED_WHITE:     [Color("#e6e3da"), 0.72, 0.0, 0.0, 2, 2, 15, false],
	PAINTED_RED:       [Color("#a3352c"), 0.72, 0.0, 0.0, 2, 2, 15, false],
	CHROME:            [Color("#c6cbd0"), 0.12, 1.00, 0.0, 3, 6, 40, false],
	MATTE_BLACK:       [Color("#1f2124"), 0.86, 0.10, 0.0, 3, 4, 30, false],
	NEON_STRIP:        [Color("#63e8ff"), 0.30, 0.0, 3.2, 3, 5, 5, false],
	WATER:             [Color("#27536b", 0.84), 0.04, 0.0, 0.0, 1, 0, 1, true],
	STONE:             [Color("#55524f"), 0.93, 0.0, 0.0, 1, 0, 60, false],
	ROCK:              [Color("#6a6560"), 0.95, 0.0, 0.0, 1, 0, 65, false],
	LEAF:              [Color("#3f6b30"), 0.98, 0.0, 0.0, 1, 0, 2, false],
	BARK:              [Color("#4f3b28"), 0.98, 0.0, 0.0, 1, 0, 12, false],
}

## Surface grain scale for the procedural detail shader — how big the noise
## features are on this material, in metres.
const GRAIN := {
	TIMBER: 0.55, PLANK: 0.50, BRICK: 0.30, SANDSTONE: 0.70, GRANITE: 0.90,
	CONCRETE: 1.30, REBAR_CONCRETE: 1.30, STEEL_FRAME: 1.60,
	CORRUGATED_STEEL: 0.22, GLASS: 3.0, REINFORCED_GLASS: 3.0,
	PLASTIC_PANEL: 1.4, CARBON_COMPOSITE: 0.28, THATCH: 0.18, CLAY_TILE: 0.35,
	ASPHALT_SHINGLE: 0.30, SHEET_METAL: 1.1, SOLAR_PANEL: 0.5, DIRT: 0.60,
	GRAVEL: 0.09, COBBLE: 0.16, ASPHALT: 0.60, CONCRETE_SLAB: 1.20,
	GRASS: 0.55, SAND: 0.22, DARK_OAK: 0.50, PAINTED_WHITE: 1.5,
	PAINTED_RED: 1.5, CHROME: 2.4, MATTE_BLACK: 1.2, NEON_STRIP: 2.0,
	WATER: 2.0, STONE: 0.8, ROCK: 0.7, LEAF: 0.14, BARK: 0.22,
}


static func id_of(mat_name: String) -> int:
	return NAMES.get(mat_name, -1)


static func is_transparent(id: int) -> bool:
	return bool(PROPS[id][7])


## Solid for the purpose of face culling and collision. Glass is solid but
## transparent, so it still occludes nothing behind it -- see mesher.
static func is_solid(id: int) -> bool:
	return id != AIR and id != WATER


static func albedo(id: int) -> Color:
	return PROPS[id][0]


static func tech_tier(id: int) -> int:
	return int(PROPS[id][4])


static func cost(id: int) -> int:
	return int(PROPS[id][5])


## Materials legal at or below a tech tier, as a plain list of names.
static func names_for_tier(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in NAMES:
		if tech_tier(NAMES[n]) <= tier:
			out.append(n)
	return out
