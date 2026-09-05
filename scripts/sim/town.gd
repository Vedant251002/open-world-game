extends Node
class_name Town
## The register of what exists, what it is made of, and what is in the stores.
##
## The economy is deliberately thin (game-design-doc.md §9): resources exist so
## that demolition hurts, not so the player has a spreadsheet to manage. If
## anyone is thinking about stock levels instead of what Mira did to the roof,
## this file has grown too big.

signal building_added(record: Dictionary)
signal building_removed(record: Dictionary)
signal tier_changed(tier: int)

## The yard on day one, in units — roughly a cubic metre and a half of wall
## each (Resources.VOXELS_PER_UNIT). Enough for two or three cottages in the
## ordinary materials and nothing at all in the ambitious ones: concrete,
## steel, asphalt and chrome all start at zero, so the first time the player
## asks for a tower somebody has to go out and dig for it. That first refusal
## is the point of the whole economy, and it should arrive early.
const STARTING_STOCK := {
	"timber": 620, "plank": 430, "thatch": 340, "cobble": 620,
	"gravel": 180, "sandstone": 120, "dark_oak": 90,
	"glass": 60, "brick": 90, "clay_tile": 40, "sand": 60,
	# The larder. Building materials are spent by the workers; these are what
	# the fields and the livestock put back, and they are the only numbers the
	# player earns rather than starts with.
	"food": 0, "cloth": 0,
}

var tier := 1
var stock: Dictionary = STARTING_STOCK.duplicate()
var buildings: Array[Dictionary] = []      ## {id, archetype, plot_id, patch, front, day}
var occupied_rects: Array[Rect2i] = []
var built_fronts: Dictionary = {}          ## plot_id -> Vector3i

var _next_id := 1


func register(patch: VoxelPatch, plot: Plot, builder: String, day: int) -> Dictionary:
	var rec := {
		"id": _next_id,
		"archetype": patch.archetype,
		"plot_id": plot.id,
		"street": plot.street_name,
		"builder": builder,
		"day": day,
		"patch": patch,
		"front": patch.front,
		"materials": patch.cost.duplicate(),
	}
	_next_id += 1
	buildings.append(rec)
	occupied_rects.append(patch.footprint)
	built_fronts[plot.id] = patch.front
	plot.occupied_by = int(rec["id"])
	# Not charged here: the Dispatcher settles the bill before the worker
	# leaves, because a half-built house has already eaten its timber.
	building_added.emit(rec)
	return rec


func unregister(rec: Dictionary, plot: Plot) -> void:
	buildings.erase(rec)
	occupied_rects.erase((rec["patch"] as VoxelPatch).footprint)
	built_fronts.erase(plot.id)
	plot.occupied_by = -1
	building_removed.emit(rec)


func find_by_plot(plot_id: int) -> Dictionary:
	for b in buildings:
		if int(b["plot_id"]) == plot_id:
			return b
	return {}


# ------------------------------------------------------------------ resources

func spend(cost: Dictionary) -> void:
	for mat_name: String in cost:
		stock[mat_name] = maxi(int(stock.get(mat_name, 0)) - int(cost[mat_name]), 0)


func refund(amount: Dictionary) -> void:
	for mat_name: String in amount:
		stock[mat_name] = int(stock.get(mat_name, 0)) + int(amount[mat_name])


func can_afford(cost: Dictionary) -> bool:
	for mat_name: String in cost:
		if int(stock.get(mat_name, 0)) < int(cost[mat_name]):
			return false
	return true


## Idle workers top the stores up. Gathering is flavour, not a management game.
func gather(hours: float) -> void:
	for mat_name: String in ["timber", "plank", "thatch"]:
		stock[mat_name] = int(stock.get(mat_name, 0)) + int(hours * 3.0)


# ---------------------------------------------------------------- progression

## Tier advances on town needs met, not on a resource threshold (§7). The player
## pulls progression by delegating well, never by grinding.
const TIER_NEEDS := {
	2: ["cottage", "store", "workshop"],
	3: ["mill", "forge", "warehouse"],
	4: ["clinic", "school", "garage"],
}


func needs_met_for(next_tier: int) -> Array[String]:
	var missing: Array[String] = []
	var have: Array[String] = []
	for b in buildings:
		have.append(str(b["archetype"]))
	for need: String in TIER_NEEDS.get(next_tier, []):
		if need not in have:
			missing.append(need)
	return missing


func try_advance() -> bool:
	var next := tier + 1
	if not TIER_NEEDS.has(next):
		return false
	if not needs_met_for(next).is_empty():
		return false
	tier = next
	tier_changed.emit(tier)
	return true


# ------------------------------------------------------- prompt context prose

## Everything below turns town state into the prose the model reads. The model
## never sees a coordinate, a count of voxels or a balance number — only what a
## person standing in the street could tell you.

func describe_buildings() -> String:
	if buildings.is_empty():
		return "There is nothing here yet but the well and the streets around it."
	var parts: Array[String] = []
	for b in buildings:
		var mats: Dictionary = b["materials"]
		var main := "timber"
		var most := 0
		for mat_name: String in mats:
			if int(mats[mat_name]) > most and mat_name in VoxelTypes.STRUCTURAL:
				most = int(mats[mat_name])
				main = mat_name
		parts.append("a %s in %s on %s" % [
			str(b["archetype"]).replace("_", " "), main, str(b["street"])])
	return "Already standing: " + ", ".join(parts) + "."


func describe_neighbours(plot: Plot) -> String:
	var parts: Array[String] = []
	for nid: int in plot.neighbours:
		var b := find_by_plot(nid)
		if not b.is_empty():
			parts.append("a %s" % str(b["archetype"]).replace("_", " "))
	if parts.is_empty():
		return "the plots either side are still empty"
	return "next to " + ", ".join(parts)


func describe_stock() -> String:
	var parts: Array[String] = []
	for mat_name: String in stock:
		var n := int(stock[mat_name])
		var word := "plenty of"
		if n < 60:
			word = "almost no"
		elif n < 200:
			word = "a little"
		parts.append("%s %s" % [word, mat_name])
	return ", ".join(parts) + "."


func stock_line() -> String:
	var parts: Array[String] = []
	for mat_name: String in ["timber", "plank", "thatch", "cobble"]:
		parts.append("%s %d" % [mat_name.substr(0, 4), int(stock.get(mat_name, 0))])
	return "   ".join(parts)


## The larder, kept separate from the timber yard because it means something
## different: materials are what you spend, food is what you have made.
func larder_line() -> String:
	return "food %d   cloth %d" % [
		int(stock.get("food", 0)), int(stock.get("cloth", 0))]


# --------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	var recs: Array = []
	for b in buildings:
		recs.append({
			"id": b["id"], "archetype": b["archetype"], "plot_id": b["plot_id"],
			"street": b["street"], "builder": b["builder"], "day": b["day"],
			"materials": b["materials"],
		})
	return {"tier": tier, "stock": stock, "buildings": recs, "next_id": _next_id}
