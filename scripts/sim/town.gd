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
##
## Scaled with the buildings. A hut used to be seven metres by six and cost
## about three hundred and fifty units; at eleven by nine it costs eight
## hundred, so a yard that still held six hundred timber would have refused
## the first thing anybody asked for. The ratio is what matters here and the
## ratio is unchanged: three or four ordinary buildings, then somebody digs.
const STARTING_STOCK := {
	"timber": 1450, "plank": 1000, "thatch": 800, "cobble": 1450,
	"gravel": 420, "sandstone": 280, "dark_oak": 210,
	"glass": 140, "brick": 210, "clay_tile": 95, "sand": 140,
	# The larder. Building materials are spent by the workers; these are what
	# the fields and the livestock put back, and they are the only numbers the
	# player earns rather than starts with.
	"food": 0, "cloth": 0,
}

## What a unit of each material is worth in coin, and what the larder fetches
## when it is sold on. Everything not named here is priced at DEFAULT_PRICE —
## a missing entry should cost something, not nothing.
const PRICE := {
	"thatch": 1, "gravel": 1, "sand": 1,
	"timber": 2, "cobble": 2,
	"plank": 3,
	"sandstone": 4, "brick": 4,
	"dark_oak": 5, "clay_tile": 5,
	"granite": 6, "concrete": 7, "glass": 8,
	"rebar_concrete": 10, "steel_frame": 14, "asphalt": 3, "chrome": 18,
	# The two the town makes rather than buys.
	"food": 7, "cloth": 11,
	# And two it makes out of those, at a bench or an oven. Worth more than
	# what went into them, which is the whole reason to hire a cook.
	"meals": 12, "tools": 16,
}
## What the town pays over the going rate when it buys in. A spread, so that
## selling and buying back is not free money.
const BUY_MARKUP := 1.5
const DEFAULT_PRICE := 4
## Enough in hand for the first few buildings without anyone counting, and
## little enough that a tower is a decision.
const STARTING_COINS := 12000

var tier := 1
## The town's inventory: material name -> how many units are in the stores.
##
## This one dictionary is the whole inventory. There is no per-worker pack and
## no chest to walk to — the crew draw from the yard wherever they happen to be
## working, because the game is about what you ask for, not about hauling. A
## unit is Resources.VOXELS_PER_UNIT of wall, which is roughly the amount a
## person would point at and call "some timber".
##
## Everything nameable in VoxelTypes.NAMES can appear here, plus the two the
## town makes rather than digs — food and cloth. A material with no entry is
## not a different case from one holding zero: both mean the stores have none,
## and the inventory screen shows every material either way so that "we have no
## clay tile" is something you can find out before you ask for a roof in it.
var stock: Dictionary = STARTING_STOCK.duplicate()
## The one number the player is shown.
##
## Materials are the physical yard and the workers still talk about them —
## being short of stone is a thing a person says, and it is what sends somebody
## out to dig. Coin is the same economy seen from the outside: the crew draws
## material and the purse pays for it, the fields and the animals sell into it,
## and knocking a building down gets some of it back. It is allowed to go
## negative, because a town in debt is a thing worth knowing and a purse that
## sticks at zero tells you nothing at all.
var coins := STARTING_COINS
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
	coins -= price_of(cost)


func refund(amount: Dictionary) -> void:
	for mat_name: String in amount:
		stock[mat_name] = int(stock.get(mat_name, 0)) + int(amount[mat_name])
	coins += price_of(amount)


## What a pile of material is worth. Used for both halves of every transaction,
## so a refund is exactly the price of what came back.
func price_of(amount: Dictionary) -> int:
	var total := 0
	for mat_name: String in amount:
		total += int(amount[mat_name]) * int(PRICE.get(mat_name, DEFAULT_PRICE))
	return total


## How many units of one material are in the stores. The inventory asks about
## materials nobody has ever had, so a missing key is zero rather than an error.
func units_of(mat_name: String) -> int:
	return int(stock.get(mat_name, 0))


## What the whole yard would fetch if it were sold. Shown on the inventory
## screen beside the purse, because "we have a lot of timber" and "we have
## twelve thousand coins" are otherwise two facts with no relation to
## each other.
func stock_worth() -> int:
	return price_of(stock)


## Whether the town knows how to work a material yet. Below the tier it is not
## that the stores are empty — it is that nobody here could use it if they had
## it, which is a different sentence and the inventory says so.
func knows(mat_name: String) -> bool:
	var id := VoxelTypes.id_of(mat_name)
	if id < 0:
		return true               # food and cloth are not voxels and need no tier
	return VoxelTypes.tech_tier(id) <= tier


## Something the town made rather than bought: a basket of wheat, a fleece.
## Into the larder and onto the purse in one move, so the two cannot drift
## apart the way they would if every caller remembered one and forgot the other.
func produce(kind: String, count: int) -> void:
	stock[kind] = int(stock.get(kind, 0)) + count
	coins += count * int(PRICE.get(kind, DEFAULT_PRICE))


## Selling from the stores. Returns the coins made, which is zero if there was
## nothing to sell — a trader who sold nothing says so, they do not invent it.
func sell(kind: String, count: int) -> int:
	var have := int(stock.get(kind, 0))
	var n := mini(count, have)
	if n <= 0:
		return 0
	stock[kind] = have - n
	var made := n * int(PRICE.get(kind, DEFAULT_PRICE))
	coins += made
	return made


## Buying in. Returns how many were bought — fewer than asked when the purse
## runs short, and never a single one on credit.
func buy(kind: String, count: int) -> int:
	var each := int(ceil(float(PRICE.get(kind, DEFAULT_PRICE)) * BUY_MARKUP))
	var n := mini(count, coins / maxi(each, 1))
	if n <= 0:
		return 0
	coins -= n * each
	stock[kind] = int(stock.get(kind, 0)) + n
	return n


## Turning some of the stores into something else — grain into meals, timber
## and iron into tools. Whole batches only: a cook does not make half a meal.
## Returns how many batches went through.
func convert(inputs: Dictionary, outputs: Dictionary, batches: int) -> int:
	var done := 0
	while done < batches:
		for mat: String in inputs:
			if int(stock.get(mat, 0)) < int(inputs[mat]):
				return done
		for mat2: String in inputs:
			stock[mat2] = int(stock[mat2]) - int(inputs[mat2])
		for out: String in outputs:
			stock[out] = int(stock.get(out, 0)) + int(outputs[out])
		done += 1
	return done


func can_afford(cost: Dictionary) -> bool:
	for mat_name: String in cost:
		if int(stock.get(mat_name, 0)) < int(cost[mat_name]):
			return false
	return true


## Idle workers top the stores up. Gathering is flavour, not a management game.
func gather(hours: float) -> void:
	for mat_name: String in ["timber", "plank", "thatch"]:
		stock[mat_name] = int(stock.get(mat_name, 0)) + int(hours * 3.0)


## Market day, every day.
##
## Without this the purse only ever goes down, and a number that can only go
## down is a countdown rather than an economy. What comes in is the town
## trading with itself: the more of it there is, the more there is to trade,
## which is also the only place the tier ladder shows up as money.
const TRADE_BASE := 150
const TRADE_PER_BUILDING := 120


func market_day() -> void:
	coins += TRADE_BASE + TRADE_PER_BUILDING * buildings.size()


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
		if n < 140:
			word = "almost no"
		elif n < 460:
			word = "a little"
		parts.append("%s %s" % [word, mat_name])
	return ", ".join(parts) + "."


## The purse, grouped so four figures can be read at a glance rather than
## counted. This is the only economy the HUD shows: a row of abbreviated
## material counts is a spreadsheet, and nobody looked at it twice.
func coin_line() -> String:
	return grouped(coins)


## Thousands separated, because four figures counted digit by digit is not a
## number anybody reads at a glance.
static func grouped(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## The yard with the numbers left in. describe_stock() rounds everything to a
## feeling on purpose, because a plan should not be haggling over units; an
## answer to "how much timber have we got" should.
func stock_report() -> String:
	var parts: Array[String] = []
	var keys: Array = stock.keys()
	keys.sort()
	for mat_name: String in keys:
		var n := int(stock[mat_name])
		if n > 0:
			parts.append("%s %d" % [mat_name.replace("_", " "), n])
	if parts.is_empty():
		return "nothing at all"
	return ", ".join(parts) + ". Everything not listed: none."


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
	return {"tier": tier, "stock": stock, "coins": coins, "buildings": recs,
		"next_id": _next_id}
