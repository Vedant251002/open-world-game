extends RefCounted
class_name VillageIdentity
## Whose village this is: its name, its banner and the land it was founded on.
##
## Chosen on the title screen, kept in the save, and read back by the HUD, the
## map and the villagers' prompt context. The landscape is the one part that
## has to be known before the world is generated, so the title screen hands it
## over through `pending` and reloads the scene when it differs from what is
## already on screen.

const LANDSCAPES := {
	"meadow": {"name": "Meadow", "blurb": "Gentle green country with a pond or two. Easy land to start on."},
	"coast": {"name": "Coast", "blurb": "The sea lies to the south: beaches, shallows and fish."},
	"forest": {"name": "Forest", "blurb": "Deep woods close in on every side. Timber is no trouble."},
	"hills": {"name": "Hills", "blurb": "Rolling uplands and rocky ridges. Handsome, and hard on a plough."},
}
const LANDSCAPE_ORDER := ["meadow", "coast", "forest", "hills"]

## Banner cloth colours.
const COLOURS: Array[Color] = [
	Color("#b8433a"), Color("#2f6f9f"), Color("#3f8a4f"),
	Color("#c9962d"), Color("#7a4a9a"), Color("#2b2b33"),
]
const COLOUR_NAMES := ["Crimson", "Blue", "Green", "Ochre", "Violet", "Charcoal"]
## Emblems drawn by BannerIcon.draw_emblem.
const EMBLEMS := ["sun", "wheat", "tower", "tree", "wave", "star"]
const MAX_NAME := 22

## What the title screen leaves for the next boot (survives reload_current_scene).
static var pending: VillageIdentity = null
## Set by the title screen when it reloads the scene to apply a landscape: the
## reloaded title then begins on its own, since the player already pressed Begin.
static var auto_begin := false

var village_name := ""
var colour_idx := 0
var emblem_idx := 0
## "" is the classic unbiased terrain: what a save from before this existed was
## made on, and what tests and tools get. A person starting a game picks one of
## LANDSCAPES (Main defaults an interactive new game to "meadow").
var landscape := ""


static func default_name(seed_value: int) -> String:
	var a := ["Willow", "Amber", "Harrow", "Linden", "Marrow", "Thistle", "Fern", "Alder", "Brook", "Cinder"]
	var b := ["wick", "ford", "bury", "holm", "stead", "combe", "thorpe", "mere", "field", "ley"]
	return str(a[seed_value % a.size()]) + str(b[(seed_value / 7) % b.size()])


static func sanitise(n: String) -> String:
	var out := n.strip_edges().replace("\n", " ")
	if out.length() > MAX_NAME:
		out = out.substr(0, MAX_NAME).strip_edges()
	return out


func colour() -> Color:
	return COLOURS[clampi(colour_idx, 0, COLOURS.size() - 1)]


func emblem() -> String:
	return str(EMBLEMS[clampi(emblem_idx, 0, EMBLEMS.size() - 1)])


func landscape_name() -> String:
	return str((LANDSCAPES[landscape] as Dictionary)["name"]) if LANDSCAPES.has(landscape) else "Classic"


func to_dict() -> Dictionary:
	return {"name": village_name, "colour": colour_idx, "emblem": emblem_idx,
		"landscape": landscape}


static func from_dict(d: Dictionary) -> VillageIdentity:
	var v := VillageIdentity.new()
	v.village_name = sanitise(str(d.get("name", "")))
	v.colour_idx = clampi(int(d.get("colour", 0)), 0, COLOURS.size() - 1)
	v.emblem_idx = clampi(int(d.get("emblem", 0)), 0, EMBLEMS.size() - 1)
	var l := str(d.get("landscape", ""))
	v.landscape = l if LANDSCAPES.has(l) else ""
	return v
