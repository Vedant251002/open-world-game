extends RefCounted
class_name Resources
## Where building materials come from, before anybody builds with them.
##
## Every material in the palette is dug, felled or quarried out of the same
## world the town stands in. That is the whole point of the economy: an order
## for a concrete tower is an order for somebody to go and find stone, and the
## player finds that out before the first block is laid rather than after.
##
## One source per material, deliberately. A crafting tree with intermediate
## goods would be a second game bolted to the side of this one.

## material in Town.stock -> the world voxel it is won from.
const SOURCE := {
	"timber": VoxelTypes.BARK,
	"plank": VoxelTypes.BARK,
	"dark_oak": VoxelTypes.BARK,
	"thatch": VoxelTypes.LEAF,

	"cobble": VoxelTypes.STONE,
	"granite": VoxelTypes.STONE,
	"gravel": VoxelTypes.STONE,
	"concrete": VoxelTypes.STONE,
	"concrete_slab": VoxelTypes.STONE,
	"rebar_concrete": VoxelTypes.STONE,
	"asphalt": VoxelTypes.STONE,

	"sand": VoxelTypes.SAND,
	"sandstone": VoxelTypes.SAND,
	"glass": VoxelTypes.SAND,
	"reinforced_glass": VoxelTypes.SAND,

	"brick": VoxelTypes.CLAY,
	"clay_tile": VoxelTypes.CLAY,
	"dirt": VoxelTypes.DIRT,

	"steel_frame": VoxelTypes.IRON_ORE,
	"corrugated_steel": VoxelTypes.IRON_ORE,
	"sheet_metal": VoxelTypes.IRON_ORE,
	"chrome": VoxelTypes.IRON_ORE,
	"matte_black": VoxelTypes.IRON_ORE,
}

## How many units of the material one dug voxel is worth. Ore is worth less per
## voxel than stone is, which is what makes a steel building an expedition and a
## cobble one an afternoon.
const YIELD := {
	VoxelTypes.BARK: 14,
	VoxelTypes.LEAF: 10,
	VoxelTypes.STONE: 9,
	VoxelTypes.SAND: 9,
	VoxelTypes.CLAY: 7,
	VoxelTypes.DIRT: 9,
	VoxelTypes.IRON_ORE: 4,
}
const YIELD_DEFAULT := 8


## Voxels to a unit of stock.
##
## A patch counts its cost in voxels and a building is forty thousand of
## them, which is not a number anybody can hold in their head or a scale
## any store could ever meet. A unit is about a cubic metre and a half of
## wall — the amount a person would think of as "some timber".
const VOXELS_PER_UNIT := 24


## What a patch actually costs the stores, in units.
static func bill(patch_cost: Dictionary) -> Dictionary:
	var out := {}
	for mat: String in patch_cost:
		var units := int(ceil(float(patch_cost[mat]) / float(VOXELS_PER_UNIT)))
		if units > 0:
			out[mat] = units
	return out


static func source_of(material: String) -> int:
	return int(SOURCE.get(material, -1))


static func gatherable(material: String) -> bool:
	return SOURCE.has(material)


static func yield_of(source: int) -> int:
	return int(YIELD.get(source, YIELD_DEFAULT))


## What a worker calls the place they are going. Said out loud, so it wants to
## sound like somewhere rather than like a voxel id.
static func place_of(source: int) -> String:
	match source:
		VoxelTypes.BARK: return "the woods"
		VoxelTypes.LEAF: return "the woods"
		VoxelTypes.SAND: return "the shore"
		VoxelTypes.CLAY: return "the clay bank"
		VoxelTypes.IRON_ORE: return "the ore seam"
	return "the hillside"


## Everything in a cost the town cannot currently cover, as material -> short by.
static func shortfall(cost: Dictionary, stock: Dictionary) -> Dictionary:
	var out := {}
	for mat: String in cost:
		var short := int(cost[mat]) - int(stock.get(mat, 0))
		if short > 0:
			out[mat] = short
	return out


## "forty cobble and a hundred timber" — a shortfall a person could say.
static func describe(short: Dictionary) -> String:
	var parts: Array[String] = []
	for mat: String in short:
		parts.append("%d %s" % [int(short[mat]), mat.replace("_", " ")])
	if parts.size() <= 1:
		return "".join(parts)
	var last: String = parts.pop_back()
	return ", ".join(parts) + " and " + last
