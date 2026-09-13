extends Node
## Prices that move, trade at them, and the tax that pays for a kingdom.
##
## Town's price list is what a thing is worth in the abstract. This is what
## it fetches today: brick is dear when the yard is empty and cheap when it
## is stacked to the eaves, and the player who notices that sells at the top
## of it. Tax is the other half of the purse — a rate the player sets, taken
## every morning from the people and the trades, and felt in their mood when
## it is set high.
##
## Every fifth day a travelling market pitches by the well; it buys dear and
## sells cheap for the day, and its stalls are the only thing here that is
## drawn rather than counted.

## Where a price sits when the yard holds this much. Kinds not named here
## are taken to be "about right" at two hundred units.
const BASELINE_DEFAULT := 200
const MULT_MIN := 0.5
const MULT_MAX := 2.0
const MARKET_EVERY := 5
const TAX_MAX := 0.3
## Per head and per staffed trade, per day, at a rate of one.
const TAX_PER_HEAD := 6
const TAX_PER_TRADE := 20
const TRADE_HOURS := 0.5
## Plurals and plain words for what the stores call things.
const ALIASES := {
	"wood": "timber", "logs": "timber", "stone": "cobble", "cobbles": "cobble",
	"bricks": "brick", "planks": "plank", "boards": "plank", "tiles": "clay_tile",
	"grain": "food", "wheat": "food", "bread": "meals", "meal": "meals",
	"tool": "tools", "glass panes": "glass", "oak": "dark_oak", "iron": "tools",
	"herbs": "herb", "fish": "fish", "berry": "berries",
}

var realm: Realm
var mult: Dictionary = {}          ## kind -> price multiplier
var rate := 0.05                   ## tax rate
var tax_yesterday := 0
var tax_total := 0
var _stock_yesterday: Dictionary = {}
var _jobs: Array[Dictionary] = []  ## {worker, kind, n, sell, at}
var _stalls: Node3D = null
var _market_day := false


func setup(r: Realm) -> void:
	realm = r
	if realm.town != null:
		_stock_yesterday = realm.town.stock.duplicate()
	_market_day = realm.clock != null and realm.clock.day % MARKET_EVERY == 0
	if _market_day:
		_pitch_stalls()


# ------------------------------------------------------------------- prices

func base_of(kind: String) -> int:
	return int(Town.PRICE.get(kind, Town.DEFAULT_PRICE))


## What a unit fetches when the town sells it today.
func price(kind: String) -> int:
	var p := float(base_of(kind)) * float(mult.get(kind, 1.0))
	if _market_day:
		p *= 1.1
	return maxi(int(round(p)), 1)


## What a unit costs the town to buy in today.
func buy_price(kind: String) -> int:
	var p := float(base_of(kind)) * float(mult.get(kind, 1.0)) * Town.BUY_MARKUP
	if _market_day:
		p *= 0.8
	return maxi(int(ceil(p)), 1)


func is_market_day() -> bool:
	return _market_day


func tax_holiday() -> bool:
	var law: Node = realm.system("Law")
	return law != null and law.has_method("tax_holiday") and bool(law.call("tax_holiday"))


# ---------------------------------------------------------------------- day

func on_day(day: int) -> void:
	_drift()
	_collect_tax()
	var was := _market_day
	_market_day = day % MARKET_EVERY == 0
	if _market_day and not was:
		_pitch_stalls()
		realm.say("Market day. The traders are by the well until dusk.")
		realm.note("market", "The travelling market came to the plaza.")
	elif was and not _market_day:
		_strike_stalls()
	_stock_yesterday = realm.town.stock.duplicate()


## Prices chase the yard: plenty pulls them down, scarcity and yesterday's
## consumption push them up. A third of the way each day, so a glut takes a
## few days to be felt and a corner in bricks cannot be run in an afternoon.
func _drift() -> void:
	var stock := realm.town.stock
	var kinds := {}
	for k: String in stock:
		kinds[k] = true
	for k: String in Town.PRICE:
		kinds[k] = true
	for k: String in kinds:
		var have := int(stock.get(k, 0))
		var base := int(Town.STARTING_STOCK.get(k, BASELINE_DEFAULT))
		var ratio := float(have) / float(maxi(base, 1))
		var target := clampf(1.5 - 0.5 * ratio, MULT_MIN, MULT_MAX)
		var used := int(_stock_yesterday.get(k, 0)) - have
		if used > 0:
			target = minf(target + 0.15, MULT_MAX)
		mult[k] = lerpf(float(mult.get(k, 1.0)), target, 0.34)


func _collect_tax() -> void:
	tax_yesterday = 0
	if rate <= 0.0 or tax_holiday():
		return
	var heads := realm.population.count()
	var trades := 0
	var industry: Node = realm.system("Industry")
	for rec: Dictionary in realm.town.buildings:
		if industry != null and industry.has_method("staff_of") \
				and not (industry.call("staff_of", int(rec["id"])) as Array).is_empty():
			trades += 1
	tax_yesterday = int(round(rate * (heads * TAX_PER_HEAD + trades * TAX_PER_TRADE)))
	if tax_yesterday <= 0:
		return
	realm.town.coins += tax_yesterday
	tax_total += tax_yesterday
	realm.note("tax", "Collected %d coins in tax." % tax_yesterday)
	# Heavy tax is felt; none at all is noticed too.
	var nudge := 0.0
	if rate > 0.15:
		nudge = -0.02 * ((rate - 0.15) / 0.15 + 1.0)
	for c: Population.Citizen in realm.population.alive():
		c.mood = clampf(c.mood + nudge, 0.0, 1.0)


func on_hour(_hour: float, _day: int) -> void:
	if _jobs.is_empty():
		return
	var now := _abs_hour()
	for job: Dictionary in _jobs.duplicate():
		if now >= float(job["at"]):
			_jobs.erase(job)
			_settle(job)


func _settle(job: Dictionary) -> void:
	var w: Worker = job["worker"]
	var kind := str(job["kind"])
	var n := int(job["n"])
	var town := realm.town
	if bool(job["sell"]):
		var have := int(town.stock.get(kind, 0))
		n = mini(n, have)
		if n <= 0:
			_say(w, "There is no %s left to sell." % kind)
			return
		var made := n * price(kind)
		town.stock[kind] = have - n
		town.coins += made
		_say(w, "Sold %d %s for %d coins." % [n, kind, made])
		realm.note("market", "Sold %d %s for %d coins." % [n, kind, made])
	else:
		var each := buy_price(kind)
		n = mini(n, town.coins / each)
		if n <= 0:
			_say(w, "We cannot afford any %s at %d a unit." % [kind, each])
			return
		town.coins -= n * each
		town.stock[kind] = int(town.stock.get(kind, 0)) + n
		_say(w, "Bought %d %s for %d coins." % [n, kind, n * each])
		realm.note("market", "Bought %d %s for %d coins." % [n, kind, n * each])


func _say(w: Worker, line: String) -> void:
	if is_instance_valid(w):
		w.speak(line)
	else:
		realm.say(line)


func _abs_hour() -> float:
	return realm.clock.day * 24.0 + realm.clock.hour


# ------------------------------------------------------------------ talking

func try_order(worker: Worker, text: String) -> bool:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["build", "put up", "construct", "erect", "make a", "plant",
			"recruit", "craft"]):
		return false
	# Tax.
	if Realm.has_word(t, ["tax", "taxes", "taxation", "levy"]):
		return _order_tax(worker, t)
	# Trade.
	var selling := Realm.has_word(t, ["sell", "trade off", "flog"]) \
		or Realm.has_phrase(t, ["sell off", "get rid of"])
	var buying := Realm.has_word(t, ["buy", "purchase", "order"]) \
		or Realm.has_phrase(t, ["buy in", "stock up on"])
	if not selling and not buying:
		return false
	var kind := _kind_in(t)
	if kind == "":
		worker.speak("%s what? Name a thing the yard holds." % ("Sell" if selling else "Buy"))
		return true
	var n := Realm.count_in(t, -1)
	if n < 0:
		if Realm.has_word(t, ["all", "everything", "the lot"]):
			n = int(realm.town.stock.get(kind, 0)) if selling else 50
		else:
			n = 20 if selling else 20
	if selling and int(realm.town.stock.get(kind, 0)) <= 0:
		worker.speak("We have no %s to sell." % kind)
		return true
	var store := realm.building("store")
	var where := realm.door_of(store) if not store.is_empty() else realm.village.well_pos
	var job := {"worker": worker, "kind": kind, "n": n, "sell": selling,
		"at": _abs_hour() + TRADE_HOURS}
	if worker.busy():
		worker.speak("I will %s the %s when I am done here." % ["sell" if selling else "buy", kind])
		job["at"] = _abs_hour() + 2.0
		_jobs.append(job)
		return true
	var line := "%s %d %s at %d a unit." % ["Selling" if selling else "Buying", n, kind,
		price(kind) if selling else buy_price(kind)]
	if not worker.take_errand_job("trade", where, TRADE_HOURS, line,
			{"where": "the store" if not store.is_empty() else "the well", "doing": "lift"}):
		_settle(job)
		return true
	_jobs.append(job)
	return true


func _order_tax(worker: Worker, t: String) -> bool:
	var old := rate
	if Realm.has_word(t, ["no", "abolish", "remove", "scrap", "end", "zero"]) \
			or Realm.has_phrase(t, ["no tax", "without tax"]):
		rate = 0.0
	elif Realm.has_word(t, ["raise", "increase", "higher", "more", "up", "double"]):
		rate = minf(rate + (rate if Realm.has_word(t, ["double"]) else 0.05), TAX_MAX)
	elif Realm.has_word(t, ["lower", "cut", "reduce", "less", "down", "ease", "halve"]):
		rate = maxf(rate - (rate * 0.5 if Realm.has_word(t, ["halve"]) else 0.05), 0.0)
	else:
		var n := Realm.count_in(t, -1)
		if n < 0:
			return false
		rate = clampf(float(n) / 100.0, 0.0, TAX_MAX)
	var pct := int(round(rate * 100.0))
	if rate == old:
		worker.speak("The tax stays at %d percent." % pct)
	elif rate == 0.0:
		worker.speak("No tax, then. The people will like that; the purse will not.")
		realm.note("tax", "The tax was abolished.")
	else:
		worker.speak("The tax is %d percent from tomorrow." % pct)
		realm.note("tax", "The tax was set to %d percent." % pct)
	return true


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["price of", "what does", "cost", "worth", "how much is", "how much are",
			"fetch"]) and not Realm.has_phrase(t, ["how much do we have", "how many"]):
		var kind := _kind_in(t)
		if kind != "":
			var trend := ""
			var m := float(mult.get(kind, 1.0))
			if m > 1.15:
				trend = " — dear just now"
			elif m < 0.85:
				trend = " — going cheap"
			return "%s fetches %d a unit today, and costs %d to buy in%s." % [
				kind.capitalize(), price(kind), buy_price(kind), trend]
	if Realm.has_phrase(t, ["what sells", "worth selling", "best price", "what is dear",
			"what should we sell", "what should i sell"]):
		return _sells_well_line()
	if Realm.has_word(t, ["tax", "taxes"]):
		if rate <= 0.0:
			return "There is no tax. Say a number and there will be."
		return "The tax is %d percent; it brought %d coins yesterday and %d all told." % [
			int(round(rate * 100.0)), tax_yesterday, tax_total]
	if Realm.has_phrase(t, ["market day", "is there a market", "when is the market",
			"when does the market"]):
		if _market_day:
			return "It is market day — the traders are by the well until dusk."
		var left := MARKET_EVERY - (realm.clock.day % MARKET_EVERY)
		return "The market comes every %d days; next in %d." % [MARKET_EVERY, left]
	return ""


func _sells_well_line() -> String:
	var best: Array = []
	for k: String in mult:
		if int(realm.town.stock.get(k, 0)) > 0:
			best.append([k, float(mult[k])])
	best.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	if best.is_empty():
		return "Nothing is dear yet; prices settle after a few days."
	var bits: Array[String] = []
	for i in mini(3, best.size()):
		bits.append("%s at %d" % [str(best[i][0]), price(str(best[i][0]))])
	return "Best prices today: %s." % ", ".join(bits)


func hud_lines() -> Array[String]:
	if not _market_day:
		return []
	var cheapest := ""
	var low := 1e9
	for k: String in ["timber", "cobble", "plank", "brick", "food"]:
		if float(buy_price(k)) < low:
			low = float(buy_price(k))
			cheapest = k
	return ["market day · %s %dc" % [cheapest, int(low)]]


# ------------------------------------------------------------------- stalls

func _pitch_stalls() -> void:
	if _stalls != null or realm.props_root == null or realm.village == null:
		return
	_stalls = Node3D.new()
	_stalls.name = "MarketStalls"
	realm.props_root.add_child(_stalls)
	var well := realm.village.well_pos
	var cloths := [Color("#b8412f"), Color("#e6dccb"), Color("#3f6f8a"), Color("#c9a13a")]
	var spots := [Vector3(7.0, 0.0, 3.0), Vector3(-7.0, 0.0, 4.0), Vector3(3.0, 0.0, -7.5),
		Vector3(-4.0, 0.0, -7.0)]
	var n := 2 + (realm.clock.day / MARKET_EVERY) % 3
	for i in n:
		var at: Vector3 = well + spots[i]
		at.y = realm.world.ground_m(at.x, at.z)
		var stall := Node3D.new()
		stall.position = at
		_stalls.add_child(stall)
		var wood := Color("#7a5a3a")
		# Table, two legs each end, and a striped canopy on four poles.
		BoxKit.add(stall, Vector3(-1.1, 0.75, -0.5), Vector3(2.2, 0.08, 1.0), wood)
		for dx in [-1.0, 1.0]:
			BoxKit.add(stall, Vector3(dx - 0.05, 0.0, -0.4), Vector3(0.1, 0.75, 0.1), wood)
			BoxKit.add(stall, Vector3(dx - 0.05, 0.0, 0.3), Vector3(0.1, 0.75, 0.1), wood)
			BoxKit.add(stall, Vector3(dx - 0.05, 0.0, -0.65), Vector3(0.08, 2.1, 0.08), wood)
			BoxKit.add(stall, Vector3(dx - 0.05, 0.0, 0.57), Vector3(0.08, 2.1, 0.08), wood)
		BoxKit.add(stall, Vector3(-1.3, 2.1, -0.8), Vector3(2.6, 0.06, 1.6), cloths[i % cloths.size()])
		# Something on the table.
		BoxKit.add(stall, Vector3(-0.8, 0.83, -0.3), Vector3(0.5, 0.3, 0.5), Color("#d9b46a"))
		BoxKit.add(stall, Vector3(0.2, 0.83, -0.2), Vector3(0.6, 0.22, 0.4), Color("#8c3b2e"))
		for child in stall.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visibility_range_end = 80.0
				(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _strike_stalls() -> void:
	if _stalls != null:
		_stalls.queue_free()
		_stalls = null


# ------------------------------------------------------------------ helpers

func _kind_in(t: String) -> String:
	var words := t.replace(",", " ").replace(".", " ").replace("?", " ").split(" ", false)
	var stock := realm.town.stock
	for w: String in words:
		if stock.has(w) or Town.PRICE.has(w):
			return w
		if ALIASES.has(w):
			return str(ALIASES[w])
		if w.ends_with("s") and (stock.has(w.trim_suffix("s")) or Town.PRICE.has(w.trim_suffix("s"))):
			return w.trim_suffix("s")
	for a: String in ALIASES:
		if a.find(" ") >= 0 and t.find(a) >= 0:
			return str(ALIASES[a])
	if t.find("clay tile") >= 0:
		return "clay_tile"
	if t.find("dark oak") >= 0:
		return "dark_oak"
	return ""


func snapshot() -> Dictionary:
	return {"mult": mult, "rate": rate, "tax_total": tax_total, "tax_yesterday": tax_yesterday}


func restore(d: Dictionary) -> void:
	mult.clear()
	for k: Variant in d.get("mult", {}):
		mult[str(k)] = float(d["mult"][k])
	rate = float(d.get("rate", rate))
	tax_total = int(d.get("tax_total", 0))
	tax_yesterday = int(d.get("tax_yesterday", 0))
