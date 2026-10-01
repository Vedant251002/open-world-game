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
	# A table is read from above and from a stool: a plank top with a linen
	# runner, an apron under it, and a bowl, a loaf and a mug so it is laid for a
	# meal rather than being a bare slab.
	"table": [
		[-14, 14, -9, 28, 2, 18, VoxelTypes.PLANK],
		[-12, 12, -7, 24, 2, 14, VoxelTypes.TIMBER],
		[-12, 0, -7, 3, 12, 3, VoxelTypes.TIMBER],
		[9, 0, -7, 3, 12, 3, VoxelTypes.TIMBER],
		[-12, 0, 4, 3, 12, 3, VoxelTypes.TIMBER],
		[9, 0, 4, 3, 12, 3, VoxelTypes.TIMBER],
		[-4, 16, -9, 8, 1, 18, VoxelTypes.PAINTED_RED],
		[-11, 16, -4, 5, 2, 5, VoxelTypes.CLAY_TILE],
		[7, 16, -3, 5, 3, 4, VoxelTypes.CLAY],
		[8, 16, 3, 3, 4, 3, VoxelTypes.TIMBER],
		[8, 20, 3, 3, 1, 3, VoxelTypes.PAINTED_WHITE],
	],
	"stool": [
		[-5, 8, -5, 10, 2, 10, VoxelTypes.PLANK],
		[-4, 10, -4, 8, 1, 8, VoxelTypes.PAINTED_RED],
		[-4, 0, -4, 2, 8, 2, VoxelTypes.TIMBER],
		[2, 0, -4, 2, 8, 2, VoxelTypes.TIMBER],
		[-4, 0, 2, 2, 8, 2, VoxelTypes.TIMBER],
		[2, 0, 2, 2, 8, 2, VoxelTypes.TIMBER],
		[-4, 3, -4, 8, 1, 1, VoxelTypes.TIMBER],
		[-4, 3, 3, 8, 1, 1, VoxelTypes.TIMBER],
	],
	"bench": [
		[-14, 8, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-13, 0, -4, 2, 8, 8, VoxelTypes.TIMBER],
		[11, 0, -4, 2, 8, 8, VoxelTypes.TIMBER],
		[-13, 3, -1, 26, 2, 2, VoxelTypes.TIMBER],
		[-14, 10, -5, 28, 3, 2, VoxelTypes.TIMBER],
		[-14, 15, -5, 28, 3, 2, VoxelTypes.TIMBER],
		[-13, 10, -5, 2, 8, 2, VoxelTypes.TIMBER],
		[11, 10, -5, 2, 8, 2, VoxelTypes.TIMBER],
	],
	# Headboard, pillows and blanket all at the -Z end, which is the end that
	# goes against the wall. Linen sheet, a red wool blanket folded over the
	# foot, and four turned posts so it reads as a bed from the doorway.
	"bed": [
		[-13, 5, -22, 26, 3, 44, VoxelTypes.TIMBER],
		[-12, 8, -21, 24, 4, 40, VoxelTypes.PAINTED_WHITE],
		[-13, 8, -4, 26, 5, 22, VoxelTypes.PAINTED_RED],
		[-13, 11, 12, 26, 2, 6, VoxelTypes.THATCH],
		[-10, 12, -20, 9, 3, 7, VoxelTypes.PAINTED_WHITE],
		[1, 12, -20, 9, 3, 7, VoxelTypes.PAINTED_WHITE],
		[-14, 0, -23, 28, 24, 2, VoxelTypes.TIMBER],
		[-14, 24, -23, 3, 2, 3, VoxelTypes.TIMBER],
		[11, 24, -23, 3, 2, 3, VoxelTypes.TIMBER],
		[-13, 0, 19, 3, 4, 3, VoxelTypes.TIMBER],
		[10, 0, 19, 3, 4, 3, VoxelTypes.TIMBER],
		[-13, 5, 19, 26, 9, 2, VoxelTypes.TIMBER],
		[-13, 0, -22, 3, 5, 3, VoxelTypes.TIMBER],
		[10, 0, -22, 3, 5, 3, VoxelTypes.TIMBER],
	],
	"chest": [
		[-9, 0, -6, 18, 10, 12, VoxelTypes.TIMBER],
		[-9, 10, -6, 18, 3, 12, VoxelTypes.PLANK],
		[-8, 13, -5, 16, 1, 10, VoxelTypes.TIMBER],
		[-7, 0, -7, 2, 13, 14, VoxelTypes.MATTE_BLACK],
		[5, 0, -7, 2, 13, 14, VoxelTypes.MATTE_BLACK],
		[-2, 6, 6, 4, 5, 1, VoxelTypes.MATTE_BLACK],
	],
	# Slatted, with a straw-packed top: a crate is a box of something.
	"crate": [
		[-6, 0, -6, 12, 14, 12, VoxelTypes.TIMBER],
		[-7, 0, -7, 2, 14, 2, VoxelTypes.TIMBER],
		[5, 0, -7, 2, 14, 2, VoxelTypes.TIMBER],
		[-7, 0, 5, 2, 14, 2, VoxelTypes.TIMBER],
		[5, 0, 5, 2, 14, 2, VoxelTypes.TIMBER],
		[-7, 12, -7, 14, 2, 14, VoxelTypes.TIMBER],
		[-7, 0, -7, 14, 2, 14, VoxelTypes.TIMBER],
		[-5, 14, -5, 10, 1, 10, VoxelTypes.THATCH],
	],
	# Octagonal in plan with a belly: two crossed boxes and a core. Iron hoops.
	"barrel": [
		[-5, 0, -5, 10, 18, 10, VoxelTypes.TIMBER],
		[-6, 3, -4, 12, 12, 8, VoxelTypes.TIMBER],
		[-4, 3, -6, 8, 12, 12, VoxelTypes.TIMBER],
		[-7, 3, -4, 14, 2, 8, VoxelTypes.MATTE_BLACK],
		[-4, 3, -7, 8, 2, 14, VoxelTypes.MATTE_BLACK],
		[-7, 12, -4, 14, 2, 8, VoxelTypes.MATTE_BLACK],
		[-4, 12, -7, 8, 2, 14, VoxelTypes.MATTE_BLACK],
		[-4, 18, -4, 8, 1, 8, VoxelTypes.TIMBER],
	],
	# Back panel, three boards, goods on every one: jars, flour, books, bottles,
	# a basket and apples. A shelf of nothing reads as a bookcase for ghosts.
	"shelf": [
		[-16, 0, -5, 2, 44, 10, VoxelTypes.TIMBER],
		[14, 0, -5, 2, 44, 10, VoxelTypes.TIMBER],
		[-14, 0, -5, 28, 44, 1, VoxelTypes.TIMBER],
		[-14, 10, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-14, 22, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-14, 34, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-16, 44, -5, 32, 2, 10, VoxelTypes.TIMBER],
		[-12, 12, -3, 5, 6, 5, VoxelTypes.CLAY_TILE],
		[-5, 12, -3, 4, 8, 4, VoxelTypes.CLAY_TILE],
		[3, 12, -3, 8, 7, 6, VoxelTypes.PAINTED_WHITE],
		[-12, 24, -3, 2, 8, 2, VoxelTypes.PAINTED_RED],
		[-9, 24, -3, 2, 6, 2, VoxelTypes.PAINTED_RED],
		[-4, 24, -3, 2, 8, 6, VoxelTypes.PAINTED_RED],
		[-2, 24, -3, 2, 7, 6, VoxelTypes.PAINTED_WHITE],
		[0, 24, -3, 3, 8, 6, VoxelTypes.TIMBER],
		[6, 24, -3, 6, 6, 6, VoxelTypes.CLAY_TILE],
		[-11, 36, -3, 9, 5, 6, VoxelTypes.THATCH],
		[2, 36, -3, 4, 3, 4, VoxelTypes.PAINTED_RED],
		[8, 36, -3, 4, 3, 4, VoxelTypes.PAINTED_RED],
	],
	# Three-tier wall rack of loaves for the bakery.
	"bread_rack": [
		[-16, 0, -5, 2, 44, 10, VoxelTypes.TIMBER],
		[14, 0, -5, 2, 44, 10, VoxelTypes.TIMBER],
		[-14, 0, -5, 28, 44, 1, VoxelTypes.TIMBER],
		[-14, 8, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-14, 21, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-14, 34, -5, 28, 2, 10, VoxelTypes.PLANK],
		[-16, 44, -5, 32, 2, 10, VoxelTypes.TIMBER],
		[-12, 10, -3, 7, 4, 7, VoxelTypes.CLAY],
		[-3, 10, -3, 7, 4, 7, VoxelTypes.CLAY],
		[6, 10, -3, 7, 4, 7, VoxelTypes.CLAY],
		[-11, 14, -2, 5, 1, 5, VoxelTypes.THATCH],
		[-2, 14, -2, 5, 1, 5, VoxelTypes.THATCH],
		[7, 14, -2, 5, 1, 5, VoxelTypes.THATCH],
		[-12, 23, -3, 10, 4, 5, VoxelTypes.CLAY],
		[0, 23, -3, 10, 4, 5, VoxelTypes.CLAY],
		[-11, 27, -2, 8, 1, 3, VoxelTypes.THATCH],
		[1, 27, -2, 8, 1, 3, VoxelTypes.THATCH],
		[-12, 36, -3, 24, 3, 6, VoxelTypes.PAINTED_WHITE],
		[-12, 39, -2, 8, 1, 4, VoxelTypes.PAINTED_RED],
	],
	# A shop or bar counter: panelled front, a plank top with a lip, goods and a
	# till on it.
	"counter_block": [
		[-22, 0, -8, 44, 18, 16, VoxelTypes.TIMBER],
		[-20, 3, 8, 12, 12, 1, VoxelTypes.TIMBER],
		[-6, 3, 8, 12, 12, 1, VoxelTypes.TIMBER],
		[8, 3, 8, 12, 12, 1, VoxelTypes.TIMBER],
		[-22, 0, 8, 44, 2, 1, VoxelTypes.TIMBER],
		[-23, 18, -9, 46, 3, 19, VoxelTypes.PLANK],
		[-19, 21, -4, 6, 3, 5, VoxelTypes.CLAY],
		[-12, 21, -4, 6, 3, 5, VoxelTypes.CLAY],
		[-4, 21, -3, 5, 6, 5, VoxelTypes.CLAY_TILE],
		[3, 21, -4, 7, 4, 7, VoxelTypes.THATCH],
		[4, 25, -3, 3, 2, 3, VoxelTypes.PAINTED_RED],
		[14, 21, -4, 9, 5, 8, VoxelTypes.TIMBER],
		[15, 26, -3, 7, 1, 6, VoxelTypes.MATTE_BLACK],
	],
	# Brick oven: stone plinth, brick body with a recessed fire mouth framed in
	# iron and glowing, a domed top and a flue. The mouth used to be a black box
	# with the fire hidden behind it.
	"oven_block": [
		[-16, 0, -14, 32, 6, 28, VoxelTypes.COBBLE],
		[-15, 6, -13, 30, 20, 26, VoxelTypes.BRICK],
		[-10, 26, -10, 20, 6, 20, VoxelTypes.BRICK],
		[-6, 32, -6, 12, 4, 12, VoxelTypes.BRICK],
		[-3, 36, -3, 6, 8, 6, VoxelTypes.BRICK],
		[-8, 8, 13, 3, 12, 2, VoxelTypes.MATTE_BLACK],
		[5, 8, 13, 3, 12, 2, VoxelTypes.MATTE_BLACK],
		[-8, 18, 13, 16, 2, 2, VoxelTypes.MATTE_BLACK],
		[-8, 6, 13, 16, 2, 2, VoxelTypes.MATTE_BLACK],
		[-5, 8, 13, 10, 10, 1, VoxelTypes.EMBER],
		[-14, 6, 13, 6, 2, 4, VoxelTypes.TIMBER],
	],
	"kiln_block": [
		[-12, 0, -12, 24, 4, 24, VoxelTypes.COBBLE],
		[-11, 4, -11, 22, 18, 22, VoxelTypes.SANDSTONE],
		[-8, 22, -8, 16, 4, 16, VoxelTypes.SANDSTONE],
		[-4, 26, -4, 8, 6, 8, VoxelTypes.SANDSTONE],
		[-7, 6, 11, 2, 10, 2, VoxelTypes.MATTE_BLACK],
		[5, 6, 11, 2, 10, 2, VoxelTypes.MATTE_BLACK],
		[-7, 14, 11, 14, 2, 2, VoxelTypes.MATTE_BLACK],
		[-7, 4, 11, 14, 2, 2, VoxelTypes.MATTE_BLACK],
		[-5, 6, 11, 10, 8, 1, VoxelTypes.EMBER],
	],
	# Forge: stone hearth with a coal bed, a brick hood against the wall and a
	# water bucket beside it.
	"forge_block": [
		[-14, 0, -10, 28, 14, 20, VoxelTypes.COBBLE],
		[-9, 14, -5, 18, 3, 13, VoxelTypes.MATTE_BLACK],
		[-7, 17, -3, 14, 2, 9, VoxelTypes.EMBER],
		[-14, 14, -10, 28, 30, 4, VoxelTypes.BRICK],
		[-12, 34, -10, 24, 4, 8, VoxelTypes.BRICK],
		[-14, 14, 6, 4, 6, 4, VoxelTypes.TIMBER],
	],
	"anvil": [
		[-5, 0, -4, 10, 8, 8, VoxelTypes.DARK_OAK],
		[-4, 8, -3, 8, 3, 6, VoxelTypes.MATTE_BLACK],
		[-3, 11, -2, 6, 3, 4, VoxelTypes.MATTE_BLACK],
		[-9, 14, -3, 18, 4, 6, VoxelTypes.MATTE_BLACK],
		[-13, 15, -2, 4, 2, 4, VoxelTypes.MATTE_BLACK],
	],
	"millstone": [
		[-16, 0, -16, 32, 6, 32, VoxelTypes.GRANITE],
		[-14, 6, -14, 28, 5, 28, VoxelTypes.GRANITE],
		[-2, 11, -2, 4, 16, 4, VoxelTypes.TIMBER],
		[-6, 14, -6, 12, 8, 12, VoxelTypes.TIMBER],
		[-4, 22, -4, 8, 4, 8, VoxelTypes.TIMBER],
		[-14, 11, 12, 28, 2, 2, VoxelTypes.TIMBER],
	],
	"desk": [
		[-18, 12, -10, 36, 3, 20, VoxelTypes.PLANK],
		[-17, 0, -9, 12, 12, 18, VoxelTypes.TIMBER],
		[-16, 2, 9, 10, 4, 1, VoxelTypes.TIMBER],
		[-16, 7, 9, 10, 4, 1, VoxelTypes.TIMBER],
		[13, 0, -9, 4, 12, 18, VoxelTypes.TIMBER],
		[-8, 15, -5, 10, 1, 8, VoxelTypes.PAINTED_WHITE],
		[5, 15, -4, 7, 2, 8, VoxelTypes.PAINTED_RED],
	],
	"rack": [
		[-14, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[11, 0, -6, 3, 44, 12, VoxelTypes.STEEL_FRAME],
		[-14, 14, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-14, 30, -6, 28, 2, 12, VoxelTypes.STEEL_FRAME],
		[-10, 16, -4, 8, 12, 8, VoxelTypes.MATTE_BLACK],
	],
	# A backing board on the wall with a hammer, a saw and a spade hung on it.
	"tool_rack": [
		[-17, 4, -2, 34, 18, 2, VoxelTypes.TIMBER],
		[-17, 20, -2, 34, 3, 4, VoxelTypes.TIMBER],
		[-12, 5, 0, 2, 14, 2, VoxelTypes.TIMBER],
		[-14, 16, 0, 6, 4, 3, VoxelTypes.MATTE_BLACK],
		[-4, 6, 0, 9, 11, 1, VoxelTypes.MATTE_BLACK],
		[-4, 17, 0, 9, 3, 2, VoxelTypes.TIMBER],
		[8, 7, 0, 2, 13, 2, VoxelTypes.TIMBER],
		[6, 4, 0, 6, 5, 2, VoxelTypes.MATTE_BLACK],
	],
	"hay": [
		[-11, 0, -11, 22, 12, 22, VoxelTypes.THATCH],
		[-8, 12, -8, 16, 6, 16, VoxelTypes.THATCH],
	],
	"trough": [
		[-16, 0, -6, 32, 3, 12, VoxelTypes.TIMBER],
		[-16, 3, -6, 2, 7, 12, VoxelTypes.TIMBER],
		[14, 3, -6, 2, 7, 12, VoxelTypes.TIMBER],
		[-16, 3, -6, 32, 7, 2, VoxelTypes.TIMBER],
		[-16, 3, 4, 32, 7, 2, VoxelTypes.TIMBER],
	],
	"firewood": [
		[-10, 0, -5, 20, 4, 4, VoxelTypes.BARK],
		[-10, 0, 1, 20, 4, 4, VoxelTypes.BARK],
		[-10, 4, -2, 20, 4, 4, VoxelTypes.BARK],
	],
	"bucket": [
		[-4, 0, -4, 8, 9, 8, VoxelTypes.TIMBER],
		[-5, 2, -5, 10, 1, 10, VoxelTypes.MATTE_BLACK],
		[-5, 7, -5, 10, 1, 10, VoxelTypes.MATTE_BLACK],
		[-4, 9, -1, 8, 1, 1, VoxelTypes.MATTE_BLACK],
	],
	"signboard": [
		[-1, 0, -1, 2, 30, 2, VoxelTypes.DARK_OAK],
		[-12, 22, -1, 24, 12, 2, VoxelTypes.PLANK],
	],
	"pallet": [
		[-12, 0, -10, 24, 3, 20, VoxelTypes.PLANK],
		[-12, 3, -10, 24, 2, 4, VoxelTypes.TIMBER],
		[-12, 3, 6, 24, 2, 4, VoxelTypes.TIMBER],
	],
	"flour_sack": [
		[-6, 0, -5, 12, 12, 10, VoxelTypes.PAINTED_WHITE],
		[-4, 12, -3, 8, 3, 6, VoxelTypes.PAINTED_WHITE],
		[-4, 11, -3, 8, 1, 6, VoxelTypes.THATCH],
	],
	"peel": [
		[-1, 0, -1, 2, 26, 2, VoxelTypes.DARK_OAK],
		[-5, 26, -1, 10, 8, 2, VoxelTypes.TIMBER],
	],
	"scale": [
		[-6, 0, -6, 12, 3, 12, VoxelTypes.DARK_OAK],
		[-1, 3, -1, 2, 10, 2, VoxelTypes.MATTE_BLACK],
		[-7, 13, -3, 14, 2, 6, VoxelTypes.MATTE_BLACK],
		[-8, 11, -3, 4, 1, 6, VoxelTypes.CLAY_TILE],
		[4, 11, -3, 4, 1, 6, VoxelTypes.CLAY_TILE],
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
	# A proper fireplace: a stone chimney breast against the wall, jambs, an oak
	# mantel, a sooted back, logs on a hearthstone and an iron pot on a crane.
	"hearth_fire": [
		[-12, 0, -9, 24, 2, 20, VoxelTypes.COBBLE],
		[-12, 2, -9, 24, 44, 6, VoxelTypes.COBBLE],
		[-12, 2, -3, 3, 26, 8, VoxelTypes.COBBLE],
		[9, 2, -3, 3, 26, 8, VoxelTypes.COBBLE],
		[-14, 28, -4, 28, 3, 10, VoxelTypes.TIMBER],
		[-9, 2, -3, 18, 24, 1, VoxelTypes.MATTE_BLACK],
		[-6, 2, -1, 12, 3, 3, VoxelTypes.BARK],
		[-6, 2, 3, 12, 3, 3, VoxelTypes.BARK],
		[-5, 4, -2, 10, 3, 8, VoxelTypes.EMBER],
		[-3, 7, 0, 6, 6, 3, VoxelTypes.EMBER],
		[-4, 14, 1, 8, 6, 6, VoxelTypes.MATTE_BLACK],
		[0, 20, 3, 1, 7, 1, VoxelTypes.MATTE_BLACK],
	],
	"rug": [
		[-17, 0, -12, 34, 1, 24, VoxelTypes.TIMBER],
		[-15, 1, -10, 30, 1, 20, VoxelTypes.PAINTED_RED],
		[-11, 2, -6, 22, 1, 12, VoxelTypes.THATCH],
	],
	"pot": [
		[-4, 0, -4, 8, 3, 8, VoxelTypes.CLAY_TILE],
		[-5, 3, -5, 10, 7, 10, VoxelTypes.CLAY_TILE],
		[-4, 10, -4, 8, 1, 8, VoxelTypes.TIMBER],
		[-3, 11, -3, 6, 5, 6, VoxelTypes.LEAF],
		[-1, 16, -1, 2, 3, 2, VoxelTypes.LEAF],
	],
	"basket": [
		[-6, 0, -6, 12, 7, 12, VoxelTypes.THATCH],
		[-7, 7, -7, 14, 1, 14, VoxelTypes.BARK],
		[-5, 7, -5, 10, 2, 10, VoxelTypes.CLAY],
		[-4, 9, -4, 3, 2, 3, VoxelTypes.PAINTED_RED],
		[1, 9, -3, 3, 2, 3, VoxelTypes.PAINTED_RED],
		[-2, 9, 1, 3, 2, 3, VoxelTypes.PAINTED_WHITE],
	],
	# Loaves are clay-brown with a pale scored top.
	"bread_tray": [
		[-11, 0, -7, 22, 2, 14, VoxelTypes.TIMBER],
		[-11, 2, -7, 22, 1, 1, VoxelTypes.TIMBER],
		[-11, 2, 6, 22, 1, 1, VoxelTypes.TIMBER],
		[-8, 2, -4, 5, 3, 8, VoxelTypes.CLAY],
		[-2, 2, -4, 5, 3, 8, VoxelTypes.CLAY],
		[4, 2, -4, 5, 3, 8, VoxelTypes.CLAY],
		[-7, 5, -3, 3, 1, 6, VoxelTypes.THATCH],
		[-1, 5, -3, 3, 1, 6, VoxelTypes.THATCH],
		[5, 5, -3, 3, 1, 6, VoxelTypes.THATCH],
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
		[-2, 5, -2, 4, 1, 4, VoxelTypes.PAINTED_WHITE],
		[2, 1, -1, 1, 3, 2, VoxelTypes.DARK_OAK],
	],
}

## Props that carry their own light, and what it looks like.
##   type -> [colour, energy, range_m, height_m, glow_m, glow_z]
##
## glow_m is the diameter of a soft additive halo drawn at the flame. It costs
## one quad and no lighting, so it is what makes a lamp read as lit from across
## the room and through a window at night, and it lets the real light stay few.
##
## All of these are shadowless. They are fill: a room needs to read as lit from
## inside, and half a dozen shadow-casting omnis per building would cost more
## than the entire rest of the frame.
const LIGHTS := {
	"lantern":     [Color("#ffb86e"), 1.55, 6.5, -0.05, 0.7, 0.30],
	"candle":      [Color("#ffc47e"), 0.80, 3.8, 1.45, 0.45, 0.0],
	"hearth_fire": [Color("#ff8a3c"), 2.00, 7.0, 0.45, 1.5, 0.30],
	"oven_block":  [Color("#ff7c36"), 1.30, 4.8, 0.45, 1.1, 0.95],
	"forge_block": [Color("#ff7430"), 1.50, 5.4, 0.80, 1.2, 0.20],
	"kiln_block":  [Color("#ff8a3c"), 1.00, 4.2, 0.35, 0.9, 0.75],
}

## Roughly how much floor a prop needs, in metres from its centre. Used to stop
## the placer standing a bench through a table: the spot grid is regular and the
## furniture is not.
const RADIUS := {
	"table": 0.80, "bench": 0.85, "bed": 1.20, "counter_block": 1.25,
	"shelf": 0.85, "desk": 0.95, "oven_block": 0.85, "forge_block": 0.80,
	"kiln_block": 0.70, "millstone": 0.85, "rack": 0.75, "trough": 0.85,
	"hearth_fire": 0.70, "bread_rack": 0.85, "rug": 0.90, "crate": 0.42, "barrel": 0.38,
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
	"rack": true, "bread_rack": true, "trough": true, "millstone": false,
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

const SHADOW_CASTERS := {"signboard": true, "hay": true, "trough": true}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func exists(type_name: String) -> bool:
	return DEFS.has(type_name) or ALIAS.has(type_name)


static func resolve(type_name: String) -> String:
	return ALIAS.get(type_name, type_name)


static func radius(type_name: String) -> float:
	return float(RADIUS.get(resolve(type_name), RADIUS_DEFAULT))


## Object-voxel props, textured.
##
## These used to get a bare StandardMaterial3D with albedo_color set and
## nothing else, which is the whole reason a bed looked like a flat plastic box
## while the wall behind it showed brick: the props were never given the PBR
## maps the world got. They are now a ShaderMaterial sharing the world's three
## texture arrays, so a blanket gets thatch and a chest gets oak grain the same
## way the walls do.
##
## Texture scale is the world's own (VoxelMaterials.TEX_SCALE, repeats per
## metre): the baked tiles are authored at their natural size, so the same
## number is right for a wall and for the table standing against it.
const PROP_SHADER := preload("res://scripts/core/voxel.gdshader")

## How hard the normal map pushes. Props are looked at from closer than walls —
## a bed two paces away rather than a house across the square — so their relief
## is worth more, not less.
const PROP_NORMAL_STRENGTH := {
	VoxelTypes.THATCH: 1.0, VoxelTypes.PLANK: 0.65, VoxelTypes.TIMBER: 0.65,
	VoxelTypes.DARK_OAK: 0.65, VoxelTypes.BARK: 1.1,
	VoxelTypes.BRICK: 1.0, VoxelTypes.COBBLE: 1.0, VoxelTypes.STONE: 0.8,
	VoxelTypes.ROCK: 1.0, VoxelTypes.GRANITE: 0.8, VoxelTypes.SANDSTONE: 0.85,
	VoxelTypes.CORRUGATED_STEEL: 1.0, VoxelTypes.SHEET_METAL: 0.6,
	VoxelTypes.STEEL_FRAME: 0.6, VoxelTypes.IRON_ORE: 1.0,
	VoxelTypes.GRAVEL: 1.1, VoxelTypes.SAND: 0.7, VoxelTypes.DIRT: 0.9,
	VoxelTypes.CLAY: 0.8, VoxelTypes.LEAF: 1.1,
	VoxelTypes.CARBON_COMPOSITE: 0.7, VoxelTypes.PAINTED_WHITE: 0.5,
	VoxelTypes.PAINTED_RED: 0.5, VoxelTypes.MATTE_BLACK: 0.5,
	VoxelTypes.CHROME: 0.5, VoxelTypes.PLASTIC_PANEL: 0.5,
	VoxelTypes.CONCRETE: 0.6, VoxelTypes.CONCRETE_SLAB: 0.6,
	VoxelTypes.REBAR_CONCRETE: 0.8, VoxelTypes.SOLAR_PANEL: 0.5,
	VoxelTypes.CLAY_TILE: 1.0, VoxelTypes.ASPHALT_SHINGLE: 1.0,
	VoxelTypes.FARMLAND: 0.9,
	VoxelTypes.WET_FARMLAND: 0.7, VoxelTypes.ASPHALT: 0.5,
	VoxelTypes.GRASS: 1.0, VoxelTypes.EMBER: 0.8, VoxelTypes.NEON_STRIP: 0.3,
}

## Cavity darkening. Lower than the world's for most of these: a blanket or a
## table top is a single mostly-flat surface and the texture's own AO lands in
## the wrong places, whereas on a wall it lands in the mortar and is right.
const PROP_AO_STRENGTH := {
	VoxelTypes.BRICK: 0.7, VoxelTypes.COBBLE: 0.7, VoxelTypes.STONE: 0.7,
	VoxelTypes.ROCK: 0.7, VoxelTypes.GRANITE: 0.65, VoxelTypes.SANDSTONE: 0.65,
	VoxelTypes.THATCH: 0.6, VoxelTypes.BARK: 0.7, VoxelTypes.LEAF: 0.6,
	VoxelTypes.IRON_ORE: 0.7, VoxelTypes.GRAVEL: 0.7,
	VoxelTypes.PAINTED_WHITE: 0.3, VoxelTypes.PAINTED_RED: 0.3,
	VoxelTypes.CHROME: 0.2, VoxelTypes.MATTE_BLACK: 0.25,
	VoxelTypes.CARBON_COMPOSITE: 0.35, VoxelTypes.SOLAR_PANEL: 0.3,
	VoxelTypes.SHEET_METAL: 0.35, VoxelTypes.STEEL_FRAME: 0.45,
	VoxelTypes.PLASTIC_PANEL: 0.4, VoxelTypes.GLASS: 0.1,
	VoxelTypes.REINFORCED_GLASS: 0.1, VoxelTypes.NEON_STRIP: 0.1,
	VoxelTypes.WATER: 0.1, VoxelTypes.EMBER: 0.5,
}

static func material_for(mat_id: int) -> Material:
	if _mat_cache.has(mat_id):
		return _mat_cache[mat_id]
	var props: Array = VoxelTypes.PROPS[mat_id]

	# The textured path, which is what almost every material gets.
	if VoxelTextures.ready():
		var layer := VoxelTextures.layer_of(VoxelTypes.name_of(mat_id))
		if layer >= 0:
			var m := ShaderMaterial.new()
			m.shader = PROP_SHADER
			# A prop is 0.05 m, and the shader reads world-space position, so
			# the texture is anchored to the world exactly as it is on a wall.
			# That means a prop's grain lines up with the grain of the same
			# material in the wall next to it, which is the thing that makes
			# two objects in one room look like they came from the same world.
			m.set_shader_parameter("tex_layer", layer)
			# Repeats per metre, the same as the wall's: the baked tiles are
			# authored at a natural size now, so a table's planks are planks.
			m.set_shader_parameter("tex_scale",
				float(VoxelMaterials.TEX_SCALE.get(mat_id, 1.0)) * VoxelTextures.res_scale())
			m.set_shader_parameter("normal_strength",
				PROP_NORMAL_STRENGTH.get(mat_id, 0.8))
			m.set_shader_parameter("ao_strength", PROP_AO_STRENGTH.get(mat_id, 0.5))
			m.set_shader_parameter("albedo_array", VoxelTextures.albedo_array())
			m.set_shader_parameter("normal_array", VoxelTextures.normal_array())
			m.set_shader_parameter("orm_array", VoxelTextures.orm_array())
			# The mesher's corner AO is meaningless here: a prop mesh carries no
			# vertex colour, so the shader must be told not to multiply by one.
			m.set_shader_parameter("hue_jitter", 0.06)
			# Props carry no emission of their own, so coals, fire mouths and
			# lamp flames rendered as dark lava. They glow warm, mostly flat.
			if mat_id == VoxelTypes.EMBER:
				m.set_shader_parameter("emission_color", Vector3(1.0, 0.42, 0.10))
				m.set_shader_parameter("emission_energy", 2.2)
				m.set_shader_parameter("emission_from_tex", 0.25)
			_mat_cache[mat_id] = m
			return m

	# Fallback for a material with no baked texture, or when the arrays failed
	# to load. Flat colour, as before — worse, but it renders.
	var flat := StandardMaterial3D.new()
	flat.albedo_color = props[0]
	flat.roughness = float(props[1])
	flat.metallic = float(props[2])
	if float(props[3]) > 0.0:
		flat.emission_enabled = true
		flat.emission = props[0]
		flat.emission_energy_multiplier = float(props[3])
	_mat_cache[mat_id] = flat
	return flat


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
		# Flat shading. The default smoothing group averages the normal of every
		# vertex that shares a position, so each corner of a box leaned toward
		# its three neighbours and a big face shaded in diagonal triangles
		# (a bed footboard came out half light, half dark).
		st.set_smooth_group(-1)
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
	# Furniture indoors does not cast sun shadows: the lights are shadowless, so
	# the only caster is the sun through a window, and a prop's shadow map
	# self-shadows its own big faces into black triangles (a counter top came
	# out solid black). Only the standing outdoor pieces keep theirs.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if SHADOW_CASTERS.has(resolve(type_name)) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	# In front of the fire, not inside the stonework: a light buried in the
	# oven's own brick lights none of it, and the oven came out black.
	l.position = Vector3(0.0, spec[3], float(spec[5]) if spec.size() > 5 else 0.0)
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
	if spec.size() > 5 and not "--noglow" in OS.get_cmdline_user_args():
		_add_glow(to, float(spec[4]), float(spec[3]), float(spec[5]))


static var _glow_mat: StandardMaterial3D


## A soft warm halo: one billboarded additive quad with a radial falloff,
## sharing a single material across every lamp in the world.
static func _add_glow(to: Node3D, size: float, y: float, z: float) -> void:
	if _glow_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.35, Color(1, 1, 1, 0.28))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex
		m.albedo_color = Color(1.0, 0.62, 0.28, 0.5)
		m.vertex_color_use_as_albedo = false
		m.disable_receive_shadows = true
		m.no_depth_test = false
		m.render_priority = 2
		_glow_mat = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	to.add_child(mi)
