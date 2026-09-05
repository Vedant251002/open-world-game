extends RefCounted
class_name Props
## Tier B object voxels, per voxel-module-spec.md §1.
##
## These are entities with their own transform at 0.05 m — twenty times finer
## than the world grid — and they are never written into chunk data. That
## separation is what lets a barrel be knocked over later without inheriting
## every hard problem in voxel physics.
##
## Each prop is a short list of boxes in 0.05 m units, meshed once per type and
## reused by every instance.

const U := 0.05                     ## object voxel size, metres

## How far a prop is lifted off whatever it stands on, in metres.
##
## Four millimetres, and it is not cosmetic. A prop is placed with its origin
## exactly on the floor plane, so the bottom face of a rug, a chest or a candle
## base ends up perfectly coplanar with the top face of the floor slab — and two
## coplanar surfaces at the same depth flicker against each other as the camera
## moves. Measured across eighteen interiors, that was every bright patch on the
## floor. Invisible at four millimetres; unmissable at zero.
const GROUND_LIFT := 0.004

## [x, y, z, w, h, d, material] in object voxels. Origin is the base centre, so
## a prop can be dropped straight onto a floor position.
##
## Every prop faces +Z and has its back at -Z. That one convention is what
## lets the generator stand a bed, a counter or an oven against a wall without
## knowing anything about the shape: it turns the prop so +Z points into the
## room and slides it back until -Z touches the plaster. Anything authored
## the other way round ends up with its back to the room.
const DEFS := {
	"table": [
		[-14, 14, -9, 28, 2, 18, VoxelTypes.PLANK],
		[-12, 0, -7, 3, 14, 3, VoxelTypes.DARK_OAK],
		[9, 0, -7, 3, 14, 3, VoxelTypes.DARK_OAK],
		[-12, 0, 4, 3, 14, 3, VoxelTypes.DARK_OAK],
		[9, 0, 4, 3, 14, 3, VoxelTypes.DARK_OAK],
	],
	"stool": [
		[-5, 8, -5, 10, 2, 10, VoxelTypes.PLANK],
		[-4, 0, -4, 2, 8, 2, VoxelTypes.DARK_OAK],
		[2, 0, -4, 2, 8, 2, VoxelTypes.DARK_OAK],
		[-4, 0, 2, 2, 8, 2, VoxelTypes.DARK_OAK],
		[2, 0, 2, 2, 8, 2, VoxelTypes.DARK_OAK],
	],
	"bench": [
		[-14, 8, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-13, 0, -4, 3, 8, 8, VoxelTypes.DARK_OAK],
		[10, 0, -4, 3, 8, 8, VoxelTypes.DARK_OAK],
		[-14, 10, -5, 28, 10, 2, VoxelTypes.PLANK],
	],
	# Headboard, pillow and blanket all at the -Z end, which is the end that
	# goes against the wall. They used to be at opposite ends of the bed.
	"bed": [
		[-13, 4, -22, 26, 3, 44, VoxelTypes.PLANK],
		[-13, 7, -14, 26, 4, 36, VoxelTypes.THATCH],
		[-13, 7, -21, 26, 6, 8, VoxelTypes.PAINTED_WHITE],
		[-13, 7, -23, 26, 13, 2, VoxelTypes.DARK_OAK],
		[-13, 0, -22, 3, 4, 3, VoxelTypes.DARK_OAK],
		[10, 0, -22, 3, 4, 3, VoxelTypes.DARK_OAK],
		[-13, 0, 19, 3, 4, 3, VoxelTypes.DARK_OAK],
		[10, 0, 19, 3, 4, 3, VoxelTypes.DARK_OAK],
	],
	"chest": [
		[-9, 0, -6, 18, 10, 12, VoxelTypes.PLANK],
		[-9, 10, -6, 18, 4, 12, VoxelTypes.DARK_OAK],
		[-2, 5, -7, 4, 5, 1, VoxelTypes.MATTE_BLACK],
	],
	"crate": [
		[-7, 0, -7, 14, 14, 14, VoxelTypes.PLANK],
		[-8, 0, -8, 16, 2, 16, VoxelTypes.DARK_OAK],
		[-8, 12, -8, 16, 2, 16, VoxelTypes.DARK_OAK],
	],
	"barrel": [
		[-6, 0, -6, 12, 18, 12, VoxelTypes.DARK_OAK],
		[-7, 3, -7, 14, 2, 14, VoxelTypes.MATTE_BLACK],
		[-7, 13, -7, 14, 2, 14, VoxelTypes.MATTE_BLACK],
	],
	"shelf": [
		[-16, 0, -5, 2, 40, 10, VoxelTypes.DARK_OAK],
		[14, 0, -5, 2, 40, 10, VoxelTypes.DARK_OAK],
		[-16, 10, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-16, 22, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-16, 34, -5, 32, 2, 10, VoxelTypes.PLANK],
		[-12, 12, -3, 6, 8, 6, VoxelTypes.CLAY_TILE],
		[2, 24, -3, 6, 8, 6, VoxelTypes.SANDSTONE],
	],
	"counter_block": [
		[-22, 0, -8, 44, 18, 16, VoxelTypes.PLANK],
		[-23, 18, -9, 46, 3, 18, VoxelTypes.GRANITE],
	],
	"oven_block": [
		[-16, 0, -14, 32, 26, 28, VoxelTypes.BRICK],
		[-7, 4, 13, 14, 12, 2, VoxelTypes.MATTE_BLACK],
		[-5, 6, 12, 10, 8, 2, VoxelTypes.EMBER],
		[-10, 26, -10, 20, 8, 20, VoxelTypes.BRICK],
	],
	"kiln_block": [
		[-12, 0, -12, 24, 22, 24, VoxelTypes.SANDSTONE],
		[-5, 3, 11, 10, 10, 2, VoxelTypes.MATTE_BLACK],
		[-3, 5, 10, 6, 6, 2, VoxelTypes.EMBER],
	],
	"forge_block": [
		[-14, 0, -10, 28, 14, 20, VoxelTypes.COBBLE],
		[-9, 14, -6, 18, 3, 12, VoxelTypes.MATTE_BLACK],
		[-4, 17, -3, 8, 4, 6, VoxelTypes.PAINTED_RED],
	],
	"anvil": [
		[-5, 0, -4, 10, 8, 8, VoxelTypes.DARK_OAK],
		[-4, 8, -3, 8, 4, 6, VoxelTypes.STEEL_FRAME],
		[-8, 12, -3, 16, 5, 6, VoxelTypes.STEEL_FRAME],
	],
	"millstone": [
		[-16, 0, -16, 32, 6, 32, VoxelTypes.GRANITE],
		[-14, 6, -14, 28, 5, 28, VoxelTypes.GRANITE],
		[-2, 11, -2, 4, 16, 4, VoxelTypes.DARK_OAK],
	],
	"desk": [
		[-18, 12, -10, 36, 3, 20, VoxelTypes.PLANK],
		[-18, 0, -10, 5, 12, 20, VoxelTypes.DARK_OAK],
		[13, 0, -10, 5, 12, 20, VoxelTypes.DARK_OAK],
		[-8, 15, -5, 10, 2, 8, VoxelTypes.PAINTED_WHITE],
	],
	"rack": [
		[-14, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[11, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[-14, 14, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-14, 30, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-10, 16, -4, 8, 12, 8, VoxelTypes.MATTE_BLACK],
	],
	"tool_rack": [
		[-16, 20, -2, 32, 3, 4, VoxelTypes.DARK_OAK],
		[-12, 8, -1, 3, 12, 2, VoxelTypes.STEEL_FRAME],
		[-4, 6, -1, 3, 14, 2, VoxelTypes.STEEL_FRAME],
		[6, 9, -1, 3, 11, 2, VoxelTypes.STEEL_FRAME],
	],
	"hay": [
		[-11, 0, -11, 22, 12, 22, VoxelTypes.THATCH],
		[-8, 12, -8, 16, 6, 16, VoxelTypes.THATCH],
	],
	"trough": [
		[-16, 0, -6, 32, 3, 12, VoxelTypes.DARK_OAK],
		[-16, 3, -6, 2, 7, 12, VoxelTypes.DARK_OAK],
		[14, 3, -6, 2, 7, 12, VoxelTypes.DARK_OAK],
		[-16, 3, -6, 32, 7, 2, VoxelTypes.DARK_OAK],
		[-16, 3, 4, 32, 7, 2, VoxelTypes.DARK_OAK],
	],
	"firewood": [
		[-10, 0, -5, 20, 4, 4, VoxelTypes.BARK],
		[-10, 0, 1, 20, 4, 4, VoxelTypes.BARK],
		[-10, 4, -2, 20, 4, 4, VoxelTypes.BARK],
	],
	"bucket": [
		[-4, 0, -4, 8, 9, 8, VoxelTypes.DARK_OAK],
		[-5, 8, -5, 10, 2, 10, VoxelTypes.MATTE_BLACK],
	],
	"signboard": [
		[-1, 0, -1, 2, 30, 2, VoxelTypes.DARK_OAK],
		[-12, 22, -1, 24, 12, 2, VoxelTypes.PLANK],
	],
	"pallet": [
		[-12, 0, -10, 24, 3, 20, VoxelTypes.PLANK],
		[-12, 3, -10, 24, 2, 4, VoxelTypes.DARK_OAK],
		[-12, 3, 6, 24, 2, 4, VoxelTypes.DARK_OAK],
	],
	"flour_sack": [
		[-6, 0, -5, 12, 12, 10, VoxelTypes.PAINTED_WHITE],
		[-4, 12, -3, 8, 3, 6, VoxelTypes.PAINTED_WHITE],
	],
	"peel": [
		[-1, 0, -1, 2, 26, 2, VoxelTypes.DARK_OAK],
		[-5, 26, -1, 10, 8, 2, VoxelTypes.PLANK],
	],
	"scale": [
		[-6, 0, -6, 12, 3, 12, VoxelTypes.DARK_OAK],
		[-1, 3, -1, 2, 10, 2, VoxelTypes.MATTE_BLACK],
		[-7, 13, -3, 14, 2, 6, VoxelTypes.MATTE_BLACK],
	],
	"stair": [
		[-8, 0, -12, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 4, -8, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 8, -4, 16, 4, 4, VoxelTypes.PLANK],
		[-8, 12, 0, 16, 4, 4, VoxelTypes.PLANK],
	],
	"generator_block": [
		[-14, 0, -10, 28, 20, 20, VoxelTypes.STEEL_FRAME],
		[-10, 20, -6, 20, 5, 12, VoxelTypes.MATTE_BLACK],
		[8, 20, -2, 4, 14, 4, VoxelTypes.CORRUGATED_STEEL],
	],
	"mat": [
		[-10, 0, -6, 20, 1, 12, VoxelTypes.THATCH],
	],

	# --- light and warmth ---------------------------------------------------
	# Interiors were unlit. A voxel room with no light source and no global
	# illumination is a black box with a bright window in it, which is exactly
	# what the first interior screenshots showed.
	# Iron and flame. The frame was chrome to begin with and every lantern in
	# the town came out as a mirror-blue blob: a polished metal reflects the sky
	# even indoors, so anything small and shiny reads as ice, not iron.
	# A bracket on the wall, not a box on the floor. Standing them on the
	# boards put a blown-out glowing crate in the middle of every room, which
	# is not what a lantern looks like from any angle.
	"lantern": [
		[-2, -2, -1, 4, 10, 2, VoxelTypes.MATTE_BLACK],
		[-1, 6, 0, 2, 2, 7, VoxelTypes.MATTE_BLACK],
		[-1, 2, 6, 2, 5, 2, VoxelTypes.MATTE_BLACK],
		[-3, -4, 4, 6, 2, 6, VoxelTypes.MATTE_BLACK],
		[-2, -3, 5, 4, 6, 4, VoxelTypes.EMBER],
		[-3, -4, 4, 1, 6, 1, VoxelTypes.MATTE_BLACK],
		[2, -4, 4, 1, 6, 1, VoxelTypes.MATTE_BLACK],
		[-3, -4, 9, 1, 6, 1, VoxelTypes.MATTE_BLACK],
		[2, -4, 9, 1, 6, 1, VoxelTypes.MATTE_BLACK],
		[-3, 2, 4, 6, 2, 6, VoxelTypes.MATTE_BLACK],
	],
	"candle": [
		[-4, 0, -4, 8, 2, 8, VoxelTypes.MATTE_BLACK],
		[-1, 2, -1, 2, 16, 2, VoxelTypes.MATTE_BLACK],
		[-3, 18, -3, 6, 2, 6, VoxelTypes.MATTE_BLACK],
		[-2, 20, -2, 4, 7, 4, VoxelTypes.PAINTED_WHITE],
		[-1, 27, -1, 2, 3, 2, VoxelTypes.EMBER],
	],
	"hearth_fire": [
		[-9, 0, -9, 18, 2, 18, VoxelTypes.COBBLE],
		[-9, 2, -9, 18, 5, 2, VoxelTypes.COBBLE],
		[-9, 2, 7, 18, 5, 2, VoxelTypes.COBBLE],
		[-9, 2, -7, 2, 5, 14, VoxelTypes.COBBLE],
		[7, 2, -7, 2, 5, 14, VoxelTypes.COBBLE],
		[-6, 2, -2, 12, 3, 3, VoxelTypes.BARK],
		[-6, 2, 1, 12, 3, 3, VoxelTypes.BARK],
		[-5, 5, -3, 10, 3, 7, VoxelTypes.EMBER],
	],
	"rug": [
		[-17, 0, -12, 34, 1, 24, VoxelTypes.DARK_OAK],
		[-15, 1, -10, 30, 1, 20, VoxelTypes.PAINTED_RED],
		[-11, 2, -6, 22, 1, 12, VoxelTypes.THATCH],
	],
	"pot": [
		[-4, 0, -4, 8, 3, 8, VoxelTypes.CLAY_TILE],
		[-5, 3, -5, 10, 7, 10, VoxelTypes.CLAY_TILE],
		[-4, 10, -4, 8, 2, 8, VoxelTypes.DARK_OAK],
	],
	"basket": [
		[-6, 0, -6, 12, 8, 12, VoxelTypes.THATCH],
		[-7, 7, -7, 14, 2, 14, VoxelTypes.BARK],
	],
	"bread_tray": [
		[-11, 0, -7, 22, 2, 14, VoxelTypes.DARK_OAK],
		[-8, 2, -4, 5, 3, 8, VoxelTypes.THATCH],
		[-2, 2, -4, 5, 3, 8, VoxelTypes.THATCH],
		[4, 2, -4, 5, 3, 8, VoxelTypes.THATCH],
	],
	# --- crops -------------------------------------------------------------
	# Four stages each, because three is not enough to read as growth and five
	# is not enough more to notice. A crop is a Tier B entity rather than a
	# world voxel: it changes four times in its life, and re-meshing a 32-cube
	# chunk every time a sprout comes up would cost more than the rest of the
	# frame put together.
	# --- crops -------------------------------------------------------------
	# Four stages each, because three is not enough to read as growth and five
	# is not enough more to notice. A crop is a Tier B entity rather than a
	# world voxel: it changes four times in its life, and re-meshing a 32-cube
	# chunk every time a sprout comes up would cost more than the rest of the
	# frame put together.
	#
	# A dozen stalks a single object voxel thick, scattered across the square
	# metre the plant occupies. The first version was four fat posts and a field
	# of it looked like a fence, not a crop: at this scale the thing that reads
	# as wheat is the density, not the shape of any one stem.
	"wheat_0": [
		[0, 0, -6, 1, 2, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 3, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 2, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 3, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 2, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 3, 1, VoxelTypes.LEAF],
	],
	"wheat_1": [
		[0, 0, -6, 1, 5, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 8, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 7, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 6, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 5, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 8, 1, VoxelTypes.LEAF],
		[-7, 0, -8, 1, 7, 1, VoxelTypes.LEAF],
		[-2, 0, 2, 1, 6, 1, VoxelTypes.LEAF],
		[-7, 0, -5, 1, 5, 1, VoxelTypes.LEAF],
		[4, 0, -7, 1, 8, 1, VoxelTypes.LEAF],
	],
	"wheat_2": [
		[0, 0, -6, 1, 11, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 13, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 15, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 12, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 14, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 11, 1, VoxelTypes.LEAF],
		[-7, 0, -8, 1, 13, 1, VoxelTypes.LEAF],
		[-2, 0, 2, 1, 15, 1, VoxelTypes.LEAF],
		[-7, 0, -5, 1, 12, 1, VoxelTypes.LEAF],
		[4, 0, -7, 1, 14, 1, VoxelTypes.LEAF],
		[4, 0, -5, 1, 11, 1, VoxelTypes.LEAF],
		[-7, 0, -3, 1, 13, 1, VoxelTypes.LEAF],
		[-2, 0, -6, 1, 15, 1, VoxelTypes.LEAF],
		[0, 0, 5, 1, 12, 1, VoxelTypes.LEAF],
	],
	"wheat_3": [
		[0, 0, -6, 1, 14, 1, VoxelTypes.THATCH],
		[2, 0, 7, 1, 16, 1, VoxelTypes.THATCH],
		[2, 12, 7, 2, 4, 2, VoxelTypes.THATCH],
		[-5, 0, -1, 1, 18, 1, VoxelTypes.THATCH],
		[-5, 14, -1, 2, 4, 2, VoxelTypes.THATCH],
		[-7, 0, 1, 1, 15, 1, VoxelTypes.THATCH],
		[-2, 0, -4, 1, 17, 1, VoxelTypes.THATCH],
		[-2, 13, -4, 2, 4, 2, VoxelTypes.THATCH],
		[-7, 0, -1, 1, 14, 1, VoxelTypes.THATCH],
		[-7, 0, -8, 1, 16, 1, VoxelTypes.THATCH],
		[-7, 12, -8, 2, 4, 2, VoxelTypes.THATCH],
		[-2, 0, 2, 1, 18, 1, VoxelTypes.THATCH],
		[-2, 14, 2, 2, 4, 2, VoxelTypes.THATCH],
		[-7, 0, -5, 1, 15, 1, VoxelTypes.THATCH],
		[4, 0, -7, 1, 17, 1, VoxelTypes.THATCH],
		[4, 13, -7, 2, 4, 2, VoxelTypes.THATCH],
		[4, 0, -5, 1, 14, 1, VoxelTypes.THATCH],
		[-7, 0, -3, 1, 16, 1, VoxelTypes.THATCH],
		[-7, 12, -3, 2, 4, 2, VoxelTypes.THATCH],
		[-2, 0, -6, 1, 18, 1, VoxelTypes.THATCH],
		[-2, 14, -6, 2, 4, 2, VoxelTypes.THATCH],
		[0, 0, 5, 1, 15, 1, VoxelTypes.THATCH],
	],
	"carrot_0": [
		[0, 0, -6, 1, 2, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 3, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 2, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 3, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 2, 1, VoxelTypes.LEAF],
	],
	"carrot_1": [
		[0, 0, -6, 1, 4, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 5, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 6, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 4, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 5, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 6, 1, VoxelTypes.LEAF],
		[-7, 0, -8, 1, 4, 1, VoxelTypes.LEAF],
		[-2, 0, 2, 1, 5, 1, VoxelTypes.LEAF],
	],
	"carrot_2": [
		[0, 0, -6, 1, 6, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 9, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 8, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 7, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 6, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 9, 1, VoxelTypes.LEAF],
		[-7, 0, -8, 1, 8, 1, VoxelTypes.LEAF],
		[-2, 0, 2, 1, 7, 1, VoxelTypes.LEAF],
		[-7, 0, -5, 1, 6, 1, VoxelTypes.LEAF],
		[4, 0, -7, 1, 9, 1, VoxelTypes.LEAF],
		[4, 0, -5, 1, 8, 1, VoxelTypes.LEAF],
		[-7, 0, -3, 1, 7, 1, VoxelTypes.LEAF],
	],
	"carrot_3": [
		[-3, -1, -3, 6, 4, 6, VoxelTypes.PAINTED_RED],
		[0, 0, -6, 1, 8, 1, VoxelTypes.LEAF],
		[2, 0, 7, 1, 11, 1, VoxelTypes.LEAF],
		[-5, 0, -1, 1, 10, 1, VoxelTypes.LEAF],
		[-7, 0, 1, 1, 9, 1, VoxelTypes.LEAF],
		[-2, 0, -4, 1, 8, 1, VoxelTypes.LEAF],
		[-7, 0, -1, 1, 11, 1, VoxelTypes.LEAF],
		[-7, 0, -8, 1, 10, 1, VoxelTypes.LEAF],
		[-2, 0, 2, 1, 9, 1, VoxelTypes.LEAF],
		[-7, 0, -5, 1, 8, 1, VoxelTypes.LEAF],
		[4, 0, -7, 1, 11, 1, VoxelTypes.LEAF],
		[4, 0, -5, 1, 10, 1, VoxelTypes.LEAF],
		[-7, 0, -3, 1, 9, 1, VoxelTypes.LEAF],
	],

	"tankard": [
		[-2, 0, -2, 4, 5, 4, VoxelTypes.DARK_OAK],
		[-2, 5, -2, 4, 1, 4, VoxelTypes.THATCH],
		[2, 1, -1, 1, 3, 2, VoxelTypes.DARK_OAK],
	],
}

## Props that carry their own light, and what it looks like.
##   type -> [colour, energy, range_m, height_m]
##
## All of these are shadowless. They are fill: a room needs to read as lit from
## inside, and half a dozen shadow-casting omnis per building would cost more
## than the entire rest of the frame.
const LIGHTS := {
	"lantern":     [Color("#ffcf96"), 1.35, 6.5, -0.05],
	"candle":      [Color("#ffdcae"), 0.70, 3.8, 1.45],
	"hearth_fire": [Color("#ff9a52"), 1.70, 6.5, 0.45],
	"oven_block":  [Color("#ff8c44"), 1.10, 4.6, 0.45],
	"forge_block": [Color("#ff7c34"), 1.40, 5.4, 0.80],
	"kiln_block":  [Color("#ff9a52"), 0.90, 4.2, 0.35],
}

## Roughly how much floor a prop needs, in metres from its centre. Used to stop
## the placer standing a bench through a table: the spot grid is regular and the
## furniture is not.
const RADIUS := {
	"table": 0.80, "bench": 0.85, "bed": 1.20, "counter_block": 1.25,
	"shelf": 0.85, "desk": 0.95, "oven_block": 0.85, "forge_block": 0.80,
	"kiln_block": 0.70, "millstone": 0.85, "rack": 0.75, "trough": 0.85,
	"hearth_fire": 0.55, "rug": 0.90, "crate": 0.42, "barrel": 0.38,
	"chest": 0.48, "anvil": 0.32, "hay": 0.36, "generator_block": 0.75,
	"pallet": 0.65, "stair": 0.55, "tool_rack": 0.85, "signboard": 0.35,
}
const RADIUS_DEFAULT := 0.28

## Furniture that belongs against a wall rather than adrift in the middle of
## the room. The generator turns these to face the room and slides them back
## until they touch the plaster.
const WALL_BACKED := {
	"bed": true, "chest": true, "shelf": true, "counter_block": true,
	"bench": true, "desk": true, "oven_block": true, "forge_block": true,
	"kiln_block": true, "tool_rack": true, "hearth_fire": true,
	"rack": true, "trough": true, "millstone": false,
	"lantern": true, "signboard": true,
}

## Props that hang rather than stand, and how high off the floor in metres.
const MOUNT_Y := {
	"lantern": 1.55,
	"tool_rack": 0.95,
}


static func mount_y(type_name: String) -> float:
	return float(MOUNT_Y.get(resolve(type_name), 0.0))

static var _back_cache: Dictionary = {}
static var _depth_cache: Dictionary = {}


static func wall_backed(type_name: String) -> bool:
	var key := resolve(type_name)
	return bool(WALL_BACKED.get(key, false))


## How far the prop reaches behind its own origin, in metres.
##
## Measured off the boxes rather than kept in a table beside them, because a
## table beside them is a table that goes stale the first time somebody makes
## a bed longer.
static func back_extent(type_name: String) -> float:
	var key := resolve(type_name)
	if _back_cache.has(key):
		return _back_cache[key]
	var min_z := 0.0
	for b: Array in DEFS.get(key, []):
		min_z = minf(min_z, float(b[2]))
	var out := -min_z * U
	_back_cache[key] = out
	return out


## Front to back, in metres. A bed is 2.25 m long, and a room 3 m across
## cannot take one standing half a metre off the wall — so the placer needs
## to know the length before it picks which wall to use.
static func depth(type_name: String) -> float:
	var key := resolve(type_name)
	if _depth_cache.has(key):
		return _depth_cache[key]
	var lo := 0.0
	var hi := 0.0
	for b: Array in DEFS.get(key, []):
		lo = minf(lo, float(b[2]))
		hi = maxf(hi, float(b[2]) + float(b[5]))
	var out := (hi - lo) * U
	_depth_cache[key] = out
	return out

## Crop stages, in the order they grow. The Farm walks this list; the shapes
## above are the only thing that has to change to add a new crop.
const CROPS := {
	"wheat":  ["wheat_0", "wheat_1", "wheat_2", "wheat_3"],
	"carrot": ["carrot_0", "carrot_1", "carrot_2", "carrot_3"],
}

## Types that share a shape with another.
const ALIAS := {
	"signboard_text": "signboard",
	"stool_pair": "stool",
}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func exists(type_name: String) -> bool:
	return DEFS.has(type_name) or ALIAS.has(type_name)


static func resolve(type_name: String) -> String:
	return ALIAS.get(type_name, type_name)


static func radius(type_name: String) -> float:
	return float(RADIUS.get(resolve(type_name), RADIUS_DEFAULT))


## Object-voxel props use their own materials rather than the world shader: the
## world shader is world-space triplanar with a grain sized for 0.25 m voxels,
## which reads as mud at a twentieth of that scale.
static func material_for(mat_id: int) -> StandardMaterial3D:
	if _mat_cache.has(mat_id):
		return _mat_cache[mat_id]
	var props: Array = VoxelTypes.PROPS[mat_id]
	var m := StandardMaterial3D.new()
	m.albedo_color = props[0]
	m.roughness = float(props[1])
	m.metallic = float(props[2])
	if float(props[3]) > 0.0:
		m.emission_enabled = true
		m.emission = props[0]
		m.emission_energy_multiplier = float(props[3])
	_mat_cache[mat_id] = m
	return m


static func mesh_for(type_name: String) -> ArrayMesh:
	var key := resolve(type_name)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var boxes: Array = DEFS.get(key, DEFS["crate"])

	# One surface per material, built with SurfaceTool so normals and tangents
	# come out right without hand-rolling another mesher.
	var by_mat := {}
	for i in boxes.size():
		var b: Array = boxes[i]
		var mat: int = b[6]
		if not by_mat.has(mat):
			by_mat[mat] = []
		# The index travels with the box so each one can be given its own
		# hair of thickness below.
		by_mat[mat].append([b, i])

	var mesh := ArrayMesh.new()
	var i := 0
	for mat: int in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry: Array in by_mat[mat]:
			var b: Array = entry[0]
			# Every box is inflated by a slightly different hair, so that no two
			# boxes in the same prop can end up with a face on the same plane.
			#
			# A dozen props were built with a lid flush to the top of the body
			# or a shelf board flush to its upright, and two coplanar faces at
			# equal depth flicker against each other as the camera moves — a
			# crate lid is a seventy-centimetre square of it. A third of a
			# millimetre resolves the depth and is invisible at any range a
			# person can stand.
			var eps: float = float(int(entry[1]) % 12) * 0.0003
			_add_box(st,
				Vector3(b[0], b[1], b[2]) * U - Vector3(eps, eps, eps),
				Vector3(b[3], b[4], b[5]) * U + Vector3(eps, eps, eps) * 2.0)
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(i, material_for(mat))
		i += 1

	_mesh_cache[key] = mesh
	return mesh


static func _add_box(st: SurfaceTool, o: Vector3, s: Vector3) -> void:
	var p := [
		o,
		o + Vector3(s.x, 0, 0),
		o + Vector3(s.x, s.y, 0),
		o + Vector3(0, s.y, 0),
		o + Vector3(0, 0, s.z),
		o + Vector3(s.x, 0, s.z),
		o + s,
		o + Vector3(0, s.y, s.z),
	]
	# Faces wound clockwise from outside, which is Godot's front-face order.
	var faces := [
		[0, 3, 2, 1],   # -Z
		[5, 6, 7, 4],   # +Z
		[4, 7, 3, 0],   # -X
		[1, 2, 6, 5],   # +X
		[3, 7, 6, 2],   # +Y
		[4, 0, 1, 5],   # -Y
	]
	for f: Array in faces:
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[1]]); st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[2]]); st.add_vertex(p[f[3]])


## Spawns one prop as a scene node. Props are entities: they carry their own
## transform and never touch chunk data.
static func spawn(type_name: String, pos: Vector3, yaw: float, parent: Node) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(type_name)
	mi.position = pos + Vector3(0.0, GROUND_LIFT, 0.0)
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	_attach_light(resolve(type_name), mi)
	return mi


static func _attach_light(key: String, to: Node3D) -> void:
	var spec: Array = LIGHTS.get(key, [])
	if spec.is_empty():
		return
	if "--nolights" in OS.get_cmdline_user_args():
		return
	var l := OmniLight3D.new()
	l.light_color = spec[0]
	l.light_energy = spec[1]
	l.omni_range = spec[2]
	l.position.y = spec[3]
	l.shadow_enabled = false
	# Almost no specular. A lantern is a warm glow, not a spotlight, and the
	# highlight it threw across the stepped underside of a thatch roof was the
	# last flicker left in the interiors: a point light a metre from a rough,
	# normal-perturbed ceiling makes a specular term that changes with every
	# sub-pixel camera movement and never settles. Diffuse light keeps the room
	# warm and lit; the highlight was contributing nothing but noise.
	l.light_specular = 0.10
	# Baked GI would double-count these — they are already emissive geometry.
	l.light_bake_mode = Light3D.BAKE_DISABLED
	l.distance_fade_enabled = true
	l.distance_fade_begin = 34.0
	l.distance_fade_length = 12.0
	to.add_child(l)
