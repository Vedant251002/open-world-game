extends Node
class_name Crier
## The Village Crier: one page of newspaper, printed each morning.
##
## Yesterday's chronicle and the state of the town go in; a masthead, a
## headline, a few short items, a gossip column, the weather and a notice come
## out. Offline the page is built from templates with enough variety that no
## two mornings read alike (each slot remembers what it said last and will not
## say it twice running). With an API key one short call a day rewrites the
## same facts in a livelier voice; if it fails the template page stands.
##
## Back issues are kept (KEEP of them) and saved with the game.

signal issue_printed(issue: Dictionary)

const KEEP := 30
const TAG := "crier"

var clock: GameClock
var town: Town
var crew: Crew
var realm: Realm
var identity: VillageIdentity
var farm: Farm
var llm: LLM

var issues: Array[Dictionary] = []     ## oldest first; see _print for the shape
## What happened since the last page went to press.
var _log := {"built": [], "harvest": {}}
## Yesterday's numbers, for "up", "down" and "joined us".
var _prev := {}
## slot -> index of the template used last, so it is not used twice running.
var _last_pick := {}
var _rng := RandomNumberGenerator.new()
var _asked_day := -1

## Chronicle kinds that make the front page, strongest first.
const KIND_RANK := {
	"raid": 10, "siege": 10, "fire": 9, "army": 8, "storm": 8, "drought": 8,
	"hunger": 7, "death": 7, "birth": 6, "wedding": 6, "event": 6, "arrival": 5,
	"crime": 5, "feast": 5, "omen": 4, "decree": 4, "tribute": 4, "allies": 4,
	"neighbours": 4, "walls": 4, "land": 4, "faith": 3, "court": 3, "law": 3,
	"market": 3, "tax": 2, "industry": 3, "upkeep": 2, "roads": 3, "health": 4,
}
## Which headline set a kind borrows.
const KIND_GROUP := {
	"raid": "raid", "siege": "raid", "army": "raid", "walls": "raid",
	"fire": "fire", "storm": "weather", "drought": "weather",
	"hunger": "hunger", "death": "death", "birth": "birth", "wedding": "wedding",
	"feast": "wedding", "arrival": "arrival", "event": "event", "omen": "omen",
	"crime": "crime", "law": "crime", "court": "crime", "decree": "decree",
	"tribute": "trade", "market": "trade", "tax": "trade", "industry": "trade",
	"allies": "neighbours", "neighbours": "neighbours", "land": "neighbours",
	"health": "health", "faith": "omen",
}

const HEADLINES := {
	"raid": ["RAIDERS AT THE GATE", "TROUBLE FROM THE ROAD", "{V} STANDS ITS GROUND",
		"STEEL IN THE NIGHT, SAYS WATCH", "BLADES DRAWN OVER {V}"],
	"fire": ["FIRE! {V} TURNS OUT WITH BUCKETS", "SMOKE OVER THE ROOFTOPS",
		"A BAD NIGHT FOR THATCH", "SPARKS FLY IN {V}"],
	"weather": ["THE SKY HAS ITS SAY", "WEATHER WREAKS HAVOC IN {V}",
		"NATURE LEAVES ITS CARD AT {V}", "THE ELEMENTS DO NOT ASK LEAVE"],
	"hunger": ["EMPTY BOWLS IN {V}", "BELLIES RUMBLE ALONG THE LANE",
		"LARDER WATCH: THE TOWN IS HUNGRY"],
	"death": ["{V} MOURNS", "A GRAVE DAY FOR {V}", "BELLS TOLL ON THE GREEN"],
	"birth": ["A NEW VOICE IN {V}", "THE CRADLE RINGS: A BIRTH IS REPORTED",
		"WELCOME, LITTLE ONE"],
	"wedding": ["BELLS FOR A WEDDING", "HAPPY NEWS FROM THE GREEN",
		"{V} MAKES MERRY"],
	"arrival": ["STRANGERS AT THE WELL", "NEW FACES IN {V}", "THE ROAD BRINGS A NEIGHBOUR"],
	"event": ["NEWS FROM BEYOND THE HEDGES", "SOMETHING STIRS IN {V}",
		"THE MORNING BRINGS A SURPRISE", "ALL AGOG IN {V}"],
	"omen": ["SIGNS AND PORTENTS", "OLD WIVES MUTTER OF OMENS", "STRANGE TIDINGS FOR {V}"],
	"crime": ["MISCHIEF IN {V}", "THE WATCH IS ASKING QUESTIONS", "LAW AND ORDER, SUCH AS IT IS"],
	"decree": ["A DECREE IS READ AT THE WELL", "NEW RULES FOR {V}", "BY ORDER, SAYS THE CRIER"],
	"trade": ["COINS CHANGE HANDS", "BUSY DAY AT THE STALLS", "TRADE TALK IN {V}"],
	"neighbours": ["WORD FROM THE NEIGHBOURS", "RIDERS BRING NEWS", "{V} AND ITS NEIGHBOURS"],
	"health": ["SNIFFLES AND WORSE", "THE HEALER IS BUSY", "A SICKLY SEASON?"],
	"built": ["{V} RAISES ANOTHER ROOF", "HAMMERS RING IN {V}", "NEW WALLS, NEW HOPES",
		"BUILDERS DOWN TOOLS, PROUDLY", "ONE BUILDING MORE FOR {V}"],
	"harvest": ["THE FIELDS GIVE UP THEIR BOUNTY", "A GOOD DAY AT THE SICKLE",
		"BASKETS FULL IN {V}", "HARVEST HOME"],
	"hired": ["NEW HANDS FOR THE TOWN", "{V} TAKES ON HELP", "A STEADY JOB FOR A STEADY SOUL"],
	"request": ["A NEIGHBOUR'S WISH COMES TRUE", "GOOD TURN DONE IN {V}"],
	"quiet": ["A QUIET DAY IN {V}", "NOTHING TO REPORT, SAYS THE WATCH",
		"ALL IS WELL, MORE OR LESS", "THE KETTLE IS ON IN {V}",
		"{V} HOLDS ITS BREATH, THEN EXHALES", "NO NEWS IS GOOD NEWS"],
}

const FILLER_LEDES := [
	"Nothing grand has happened since the last issue, and the Crier is, for once, quite content with that.",
	"The town went about its business yesterday, which is the best business to go about.",
	"Dogs were walked, bread was baked and no one fell in the well. We call that a result.",
	"It was one of those days that history skips and neighbours remember fondly.",
	"The lanes were quiet and the chimneys did their duty; there is little else to say.",
]


func setup(c: GameClock, t: Town, cr: Crew, r: Realm, ident: VillageIdentity, f: Farm, l: LLM) -> void:
	clock = c
	town = t
	crew = cr
	realm = r
	identity = ident
	farm = f
	llm = l
	_rng.randomize()
	clock.day_passed.connect(_on_day)
	town.building_added.connect(_on_built)
	if farm != null:
		farm.harvested.connect(_on_harvest)
	if llm != null:
		llm.line_ready.connect(_on_line)


func _on_built(rec: Dictionary) -> void:
	(_log["built"] as Array).append({
		"arch": str(rec.get("archetype", "building")),
		"street": str(rec.get("street", "")),
		"builder": _person(str(rec.get("builder", ""))),
	})


## A worker id as the paper prints it: "cit_cal" is Cal, not "Cit Cal".
func _person(id: String) -> String:
	if id == "":
		return ""
	if crew != null:
		var w := crew.get_worker(id)
		if w != null:
			return w.display_name()
	return id.trim_prefix("cit_").capitalize()


func _on_harvest(kind: String, amount: int) -> void:
	var h: Dictionary = _log["harvest"]
	h[kind] = int(h.get(kind, 0)) + amount


func _on_day(day: int) -> void:
	print_issue(day)


## The first page for a brand-new town; a loaded save already has its issues.
func ensure_first() -> void:
	if issues.is_empty():
		print_issue(clock.day, true)


# ------------------------------------------------------------------- access

func latest() -> Dictionary:
	return issues[issues.size() - 1] if not issues.is_empty() else {}


func unread_count() -> int:
	var n := 0
	for i: Dictionary in issues:
		if not bool(i.get("read", false)):
			n += 1
	return n


func mark_read(issue: Dictionary) -> void:
	issue["read"] = true


func name_of_village() -> String:
	if identity != null and identity.village_name != "":
		return identity.village_name
	return realm.kingdom_name.capitalize() if realm != null else "the town"


# ------------------------------------------------------------------ printing

## Builds and files the morning's issue (template first, then the optional
## rewrite). Returns it.
func print_issue(day: int, first := false) -> Dictionary:
	_rng.seed = hash("crier-%d-%s" % [day, name_of_village()])
	var f := _facts(day)
	var v := name_of_village()
	var issue := {
		"day": day, "edition": issues.size() + 1, "village": v, "read": false,
		"season": _season_word(), "source": "template",
	}
	var lead := _lead(f)
	issue["headline"] = lead["headline"]
	issue["lede"] = lead["lede"]
	issue["items"] = _items(f, lead)
	issue["gossip"] = _gossip(f)
	issue["forecast"] = _forecast(day)
	issue["notice"] = _notice(f)
	if first:
		issue["headline"] = "THE FIRST ISSUE: {V} HAS A PAPER".replace("{V}", v.to_upper())
		issue["lede"] = "From today the Crier will go round the lanes each morning with what happened, what is said and what the town wants."
	issues.append(issue)
	if issues.size() > KEEP:
		issues = issues.slice(issues.size() - KEEP)
	_remember(f)
	issue_printed.emit(issue)
	_maybe_rewrite(issue)
	return issue


func _remember(f: Dictionary) -> void:
	_prev = {"hired": f["hired_names"], "pop": f["pop"], "prices": f["prices"],
		"coins": town.coins}
	_log = {"built": [], "harvest": {}}


# ---------------------------------------------------------------- the facts

func _market() -> Node:
	return realm.system("market") if realm != null else null


func _weather() -> Node:
	return realm.system("weather") if realm != null else null


func _season_word() -> String:
	var w := _weather()
	return str(w.call("season_word")) if w != null else ""


func _facts(day: int) -> Dictionary:
	var chron: Array[Dictionary] = []
	if realm != null and realm.chronicle != null:
		for e: Dictionary in realm.chronicle.entries:
			if int(e["day"]) >= day - 1 and str(e["kind"]) != "founding":
				chron.append(e)
	var hired_names: Array = []
	if crew != null:
		for w: Worker in crew.hired():
			hired_names.append(w.memory.display_name)
	var new_hands: Array = []
	for n: Variant in hired_names:
		if _prev.has("hired") and not (n in (_prev["hired"] as Array)):
			new_hands.append(str(n))
	var prices := {}
	var m := _market()
	if m != null:
		for k: String in ["food", "timber", "plank", "cloth", "cobble", "meals"]:
			prices[k] = int(m.call("price", k))
	var pop := 0
	var homeless := 0
	var hungry := 0
	if realm != null and realm.population != null:
		pop = realm.population.count()
		homeless = realm.population.homeless()
		hungry = realm.population.hungry()
	return {
		"day": day, "chron": chron, "built": (_log["built"] as Array).duplicate(),
		"harvest": (_log["harvest"] as Dictionary).duplicate(),
		"hired_names": hired_names, "new_hands": new_hands, "prices": prices,
		"pop": pop, "homeless": homeless, "hungry": hungry,
	}


# ----------------------------------------------------------------- picking

## A choice from `options` for `slot` that is never the one chosen last time.
func _pick(slot: String, options: Array) -> Variant:
	if options.is_empty():
		return ""
	var idx := _rng.randi() % options.size()
	if options.size() > 1 and int(_last_pick.get(slot, -1)) == idx:
		idx = (idx + 1 + _rng.randi() % (options.size() - 1)) % options.size()
	_last_pick[slot] = idx
	return options[idx]


func _fill(s: String, extra: Dictionary = {}) -> String:
	var out := s.replace("{V}", name_of_village().to_upper() if s.begins_with("{V}") or s == s.to_upper() \
		else name_of_village())
	for k: Variant in extra:
		out = out.replace("{%s}" % str(k), str(extra[k]))
	return out


func _arch_name(a: String) -> String:
	return a.replace("_", " ")


func _article(w: String) -> String:
	return "an" if w.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"


# -------------------------------------------------------------- the lead

func _lead(f: Dictionary) -> Dictionary:
	var best := {}
	var best_rank := -1
	for e: Dictionary in f["chron"]:
		var r := int(KIND_RANK.get(str(e["kind"]), 1))
		# Yesterday's news outranks this morning's tail of it only on a tie.
		if r > best_rank or (r == best_rank and int(e["day"]) > int(best.get("day", 0))):
			best = e
			best_rank = r
	var group := ""
	var lede := ""
	var used := ""
	if best_rank >= 3:
		group = str(KIND_GROUP.get(str(best["kind"]), "event"))
		lede = str(best["text"])
		used = lede
	elif not (f["built"] as Array).is_empty():
		group = "built"
		var b: Dictionary = (f["built"] as Array)[0]
		var what := _arch_name(str(b["arch"]))
		lede = "%s %s has gone up%s." % [_article(what).capitalize(), what,
			(" on %s" % str(b["street"])) if str(b["street"]) != "" else ""]
	elif not (f["harvest"] as Dictionary).is_empty():
		group = "harvest"
		lede = _harvest_text(f["harvest"])
	elif not (f["new_hands"] as Array).is_empty():
		group = "hired"
		lede = "%s has taken a post with the town." % ", ".join(f["new_hands"])
	elif best_rank >= 0:
		group = str(KIND_GROUP.get(str(best["kind"]), "event"))
		lede = str(best["text"])
		used = lede
	else:
		group = "quiet"
		lede = str(_pick("lede", FILLER_LEDES))
	if lede != "":
		lede = lede.substr(0, 1).to_upper() + lede.substr(1)
	return {"headline": _fill(str(_pick("head_" + group, HEADLINES[group]))),
		"lede": lede, "used": used, "group": group}


func _harvest_text(h: Dictionary) -> String:
	var parts: Array[String] = []
	for k: Variant in h:
		parts.append("%d %s" % [int(h[k]), str(k)])
	return "The field gave up %s." % " and ".join(parts)


# ---------------------------------------------------------------- items

func _items(f: Dictionary, lead: Dictionary) -> Array:
	var out: Array = []
	var seen := {str(lead["used"]): true}
	for b: Dictionary in f["built"]:
		if group_is(lead, "built") and out.is_empty() and b == (f["built"] as Array)[0]:
			continue
		var what := _arch_name(str(b["arch"]))
		var by := str(b["builder"])
		var street := str(b["street"])
		out.append({"kicker": "BUILDING", "text": str(_pick("built", [
			"%s %s is finished%s%s." % [_article(what).capitalize(), what, (" on " + street) if street != "" else "", (", by %s's hand" % by) if by != "" else ""],
			"Passers-by report %s new %s%s; %s." % [_article(what), what, (" on " + street) if street != "" else "", "the mortar is barely dry"],
			"The register gains %s %s%s.%s" % [_article(what), what, (" on " + street) if street != "" else "", (" Credit to %s." % by) if by != "" else ""],
		]))})
	if not (f["harvest"] as Dictionary).is_empty() and not group_is(lead, "harvest"):
		out.append({"kicker": "HARVEST", "text": str(_pick("harvest", [
			_harvest_text(f["harvest"]),
			"Baskets came in from the field: %s, all told." % _harvest_short(f["harvest"]),
			"Good news from the furrows: %s in the store." % _harvest_short(f["harvest"]),
		]))})
	if not (f["new_hands"] as Array).is_empty() and not group_is(lead, "hired"):
		var nm := ", ".join(f["new_hands"])
		out.append({"kicker": "HIRING", "text": str(_pick("hired", [
			"%s has joined the town's payroll." % nm,
			"A new face on the work crew: %s." % nm,
			"%s has put on an apron and a purposeful look." % nm,
		]))})
	for e: Dictionary in f["chron"]:
		var t := str(e["text"])
		if seen.has(t) or out.size() >= 5:
			continue
		seen[t] = true
		out.append({"kicker": _kicker(str(e["kind"])), "text": t})
	# Prices
	var mk := _market_item(f)
	if mk != "" and out.size() < 5:
		out.append({"kicker": "MARKET", "text": mk})
	# Filler so a quiet day still has three items, never the same three.
	var fillers := _fillers(f)
	var tries := 0
	while out.size() < 3 and not fillers.is_empty() and tries < 8:
		tries += 1
		var fi: Dictionary = fillers.pop_at(_rng.randi() % fillers.size())
		if int(_last_pick.get("filler_" + str(fi["key"]), -1)) == int(f["day"]) - 1 and fillers.size() > 0:
			continue
		_last_pick["filler_" + str(fi["key"])] = int(f["day"])
		out.append({"kicker": fi["kicker"], "text": fi["text"]})
	return out.slice(0, 5)


func group_is(lead: Dictionary, g: String) -> bool:
	return str(lead["group"]) == g


func _harvest_short(h: Dictionary) -> String:
	var parts: Array[String] = []
	for k: Variant in h:
		parts.append("%d %s" % [int(h[k]), str(k)])
	return ", ".join(parts)


func _kicker(kind: String) -> String:
	match kind:
		"raid", "siege", "army", "walls": return "WATCH"
		"fire": return "FIRE"
		"death": return "OBITUARY"
		"birth", "wedding", "feast": return "HEARTH & HOME"
		"arrival": return "ARRIVALS"
		"event", "omen": return "NEWS"
		"crime", "law", "court": return "THE WATCH"
		"market", "tax", "tribute", "industry": return "TRADE"
		"storm", "drought": return "WEATHER"
		"request": return "GOOD TURNS"
		"faith": return "THE SHRINE"
	return "ABOUT TOWN"


func _market_item(f: Dictionary) -> String:
	var prices: Dictionary = f["prices"]
	if prices.is_empty():
		return ""
	var prev: Dictionary = _prev.get("prices", {})
	var moves: Array[String] = []
	for k: Variant in prices:
		if prev.has(k) and int(prices[k]) != int(prev[k]):
			var d := int(prices[k]) - int(prev[k])
			moves.append("%s %s to %dc" % [str(k), "up" if d > 0 else "down", int(prices[k])])
	if not moves.is_empty():
		return str(_pick("market_move", [
			"At the stalls: %s." % ", ".join(moves.slice(0, 3)),
			"Prices on the move: %s." % ", ".join(moves.slice(0, 3)),
			"The market-folk murmur that %s." % " and ".join(moves.slice(0, 2)),
		]))
	var k2: String = ["food", "timber", "plank", "cloth", "cobble"][_rng.randi() % 5]
	if not prices.has(k2):
		return ""
	return str(_pick("market_flat", [
		"%s fetches %dc a unit at the stalls; nobody is complaining." % [k2.capitalize(), int(prices[k2])],
		"Market watch: %s steady at %dc." % [k2, int(prices[k2])],
		"The going rate for %s is %dc, give or take a haggle." % [k2, int(prices[k2])],
	]))


func _fillers(f: Dictionary) -> Array:
	var out: Array = []
	var pop: int = f["pop"]
	if pop > 0:
		out.append({"key": "pop", "kicker": "THE CENSUS", "text": str(_pick("f_pop", [
			"%d souls now call %s home." % [pop, name_of_village()],
			"The count at the well comes to %d; the Crier did not miss anyone." % pop,
			"Population: %d, and every one of them has an opinion." % pop,
		]))})
		var gain: int = pop - int(_prev.get("pop", pop))
		if gain != 0:
			out.append({"key": "popmove", "kicker": "THE CENSUS", "text":
				"%s: the town is %s by %d since yesterday." % [name_of_village(), "bigger" if gain > 0 else "smaller", absi(gain)]})
	if town != null:
		out.append({"key": "purse", "kicker": "THE PURSE", "text": str(_pick("f_purse", [
			"The treasury stands at %s coins." % Town.grouped(town.coins),
			"Counted twice by candlelight: %s coins in the purse." % Town.grouped(town.coins),
			"%s coins in the chest, says whoever keeps the key." % Town.grouped(town.coins),
		]))})
		out.append({"key": "reg", "kicker": "THE REGISTER", "text":
			"%d buildings are now on the register of %s." % [town.buildings.size(), name_of_village()]})
		var food := int(town.stock.get("food", 0))
		out.append({"key": "larder", "kicker": "THE LARDER", "text": str(_pick("f_larder", [
			"The larder holds %d food." % food,
			"%d portions of food are in the stores." % food,
		]))})
	if clock != null:
		out.append({"key": "day", "kicker": "THE CALENDAR", "text":
			"Day %d of %s's reckoning, in %s." % [int(f["day"]), name_of_village(), _season_word().to_lower() if _season_word() != "" else "good order"]})
	return out


# ---------------------------------------------------------------- gossip

func _gossip(f: Dictionary) -> String:
	var cands: Array = []
	var pop := realm.population if realm != null else null
	var folks: Array = []
	if pop != null:
		for c: Variant in pop.alive():
			folks.append(c)
	if not folks.is_empty():
		var a: Variant = folks[_rng.randi() % folks.size()]
		var b: Variant = folks[_rng.randi() % folks.size()]
		for _i in 4:
			if b != a:
				break
			b = folks[_rng.randi() % folks.size()]
		for c: Variant in folks:
			if float(c.needs["fed"]) < 0.4:
				cands.append("%s is saying, to anyone who will hold still, that breakfast was more of an idea than a meal." % c.name)
				cands.append("%s has been heard to mutter that the larder is \"a rumour with a lid on\"." % c.name)
				break
		for c: Variant in folks:
			if int(c.home_id) < 0:
				cands.append("%s says the hay is not what it used to be, having tried several barns this week. A roof would settle it." % c.name)
				break
		for c: Variant in folks:
			if float(c.mood) > 0.85:
				cands.append("%s was whistling by the well all morning. Nobody dares ask why, in case it stops." % c.name)
				break
		for c: Variant in folks:
			if int(c.spouse_id) >= 0:
				cands.append("%s and a certain spouse were seen sharing one umbrella and a great many glances." % c.name)
				break
		if a != b:
			var topic: String = str(["the correct way to stack firewood", "whose goose it was",
				"who left the well bucket on the green", "how thick a loaf should be sliced",
				"the proper depth for a fence-post", "whether it counts as rain if you cannot hear it",
				"who owes whom a hen", "the shape of the Hall of Records' door"][_rng.randi() % 8])
			cands.append("%s and %s were overheard disagreeing over %s. Both left satisfied they had won." % [a.name, b.name, topic])
			cands.append("It is said, by those who say such things, that %s has quietly stopped speaking to %s over %s." % [a.name, b.name, topic])
			cands.append("%s thinks %s is rather too fond of giving opinions; %s thinks the same of %s. The Crier thinks they would be good friends." % [a.name, b.name, b.name, a.name])
	if crew != null:
		for w: Worker in crew.hired():
			var morale := float(w.memory.disposition.get("morale", 0.7))
			if morale < 0.45:
				cands.append("%s has been seen kicking a pebble down the lane with feeling. Kind words are said to be cheap." % w.memory.display_name)
			elif morale > 0.85:
				cands.append("%s is in tremendous spirits and has hummed the same tune for three days. The neighbours are divided." % w.memory.display_name)
	cands.append_array([
		"The well-bucket has been blamed again. The well-bucket declines to comment.",
		"Someone's goose has been seen in someone else's garden. The goose, as ever, was unrepentant.",
		"A rumour that the baker puts a pinch of something secret in the loaves has been confirmed: it is kindness, and a little too much salt.",
		"Old hands at the well say the weather will turn by Thursday. They say that every day, and are right now and then.",
		"The children have founded a Secret Society, whose secret is so poorly kept that it is now printed here.",
	])
	return str(_pick("gossip", cands))


# -------------------------------------------------------------- forecast

func _forecast(day: int) -> String:
	var w := _weather()
	if w == null:
		return str(_pick("fc_none", ["Fair, says the Crier, with a hopeful glance at the sky.",
			"The sky has not briefed us, but we expect weather of some kind."]))
	var state := str(w.get("_state"))
	var t0 := float(w.call("temperature", day))
	var t1 := float(w.call("temperature", day + 1))
	var season := str(w.call("season_word")).to_lower()
	var trend := "much as today"
	if t1 - t0 > 1.5:
		trend = "warmer tomorrow"
	elif t0 - t1 > 1.5:
		trend = "colder tomorrow"
	var core := ""
	match state:
		"clear": core = str(_pick("fc_clear", ["Clear skies, %s." % season, "A fair, bright morning, %s." % season, "Sun and a few idle clouds, %s." % season]))
		"overcast": core = str(_pick("fc_over", ["Grey and thinking about rain, %s." % season, "Overcast; carry a hat and a hopeful attitude.", "A low grey lid on the sky, %s." % season]))
		"rain": core = str(_pick("fc_rain", ["Rain, steady and unhurried, %s." % season, "Wet through, %s; the fields will not complain." % season, "Showers, with puddles for the children."]))
		"storm": core = str(_pick("fc_storm", ["Storm over the town: keep to your doors and your roofs on.", "Thunder and wind, %s. Mind the shutters." % season]))
		"fog": core = str(_pick("fc_fog", ["Thick fog; you may meet your neighbour before you see him.", "Fog on the lanes, burning off by noon, perhaps."]))
		"snow": core = str(_pick("fc_snow", ["Snow falling, %s; wrap the little ones." % season, "A white morning, %s, and quiet." % season]))
		_: core = "Fair weather, %s." % season
	return "%s About %d degrees, %s." % [core, int(round(t0)), trend]


# ---------------------------------------------------------------- notice

func _notice(f: Dictionary) -> String:
	var cands: Array = []
	var key := {}
	if town != null:
		var tier := clampi(town.tier, 1, 4)
		if tier < 4:
			var miss := town.needs_met_for(tier + 1)
			if not miss.is_empty():
				var names: Array[String] = []
				for m: String in miss.slice(0, 3):
					names.append(m)
				cands.append("The Hall of Records is still waiting on: %s. Then, and only then, will the town call itself grander." % ", ".join(names))
				cands.append("WANTED: %s. A bigger name for %s depends on it." % [", ".join(names), name_of_village()])
		var food := int(town.stock.get("food", 0))
		if f["pop"] > 0 and food < int(f["pop"]):
			cands.append("The larder is low (%d food for %d mouths). Fields and hands wanted." % [food, int(f["pop"])])
		for pair: Array in [["well_house", "a proper well-house"], ["bakery", "a bakery"],
				["barn", "a barn for the harvest"], ["tavern", "a tavern for the evenings"],
				["store", "a store on the square"], ["workshop", "a workshop"],
				["watchtower", "a watchtower"], ["shrine", "a shrine"]]:
			var has := false
			for b: Dictionary in town.buildings:
				if str(b["archetype"]) == str(pair[0]):
					has = true
					break
			if not has:
				cands.append("NOTICE: %s still lacks %s. Anyone with a plan and some timber should see the foreman." % [name_of_village(), str(pair[1])])
				cands.append("The town would be glad of %s. Enquire within." % str(pair[1]))
	if int(f["homeless"]) > 0:
		cands.append("%d of our neighbours are sleeping rough. Roofs, beds and open doors are warmly requested." % int(f["homeless"]))
	if int(f["hungry"]) > 0:
		cands.append("%d people went hungry. The Crier asks the fields, kindly, to try harder." % int(f["hungry"]))
	if cands.is_empty():
		cands.append("The Crier knows of nothing the town lacks today, and distrusts the feeling. Suggestions welcome.")
	key["n"] = cands.size()
	return str(_pick("notice", cands))


# ----------------------------------------------------------------- the LLM

func _maybe_rewrite(issue: Dictionary) -> void:
	if llm == null or not llm.available() or _asked_day == int(issue["day"]):
		return
	_asked_day = int(issue["day"])
	var items: Array[String] = []
	for it: Dictionary in issue["items"]:
		items.append("- %s: %s" % [str(it["kicker"]), str(it["text"])])
	var facts := "HEADLINE: %s\nLEDE: %s\nITEMS:\n%s\nGOSSIP: %s\nFORECAST: %s\nNOTICE: %s" % [
		issue["headline"], issue["lede"], "\n".join(items), issue["gossip"],
		issue["forecast"], issue["notice"]]
	var system := ("You are the editor of the one-page daily paper of %s, a warm, slightly literary village. "
		+ "Rewrite the facts you are given in a lively, affectionate village-paper voice. Keep every name and "
		+ "number exactly. Reply with exactly these lines and nothing else: HEADLINE: (capitals, short) / "
		+ "LEDE: (one or two sentences) / ITEM: (one line per item, same count and order) / GOSSIP: / "
		+ "FORECAST: / NOTICE:. Under 150 words in all.") % name_of_village()
	llm.talk(TAG, system, [{"role": "user", "content": facts}], TAG, "")


func _on_line(worker_id: String, text: String, tag: String) -> void:
	if tag != TAG or worker_id != TAG or text.strip_edges() == "":
		return
	var issue := latest()
	if issue.is_empty() or int(issue["day"]) != _asked_day:
		return
	apply_rewrite(issue, text)


## Folds a model's reply into an issue field by field; anything missing keeps
## its template text. Public so the test can feed it a canned reply.
func apply_rewrite(issue: Dictionary, text: String) -> bool:
	var items: Array[String] = []
	var got := 0
	for raw: String in text.split("\n"):
		var line := raw.strip_edges().trim_prefix("- ").trim_prefix("*")
		var cut := line.find(":")
		if cut < 0:
			continue
		var head := line.substr(0, cut).strip_edges().to_upper().replace("*", "")
		var body := line.substr(cut + 1).strip_edges().replace("*", "")
		if body == "" or body.length() > 400:
			continue
		match head:
			"HEADLINE": issue["headline"] = body.to_upper(); got += 1
			"LEDE": issue["lede"] = body; got += 1
			"GOSSIP": issue["gossip"] = body; got += 1
			"FORECAST": issue["forecast"] = body; got += 1
			"NOTICE": issue["notice"] = body; got += 1
			"ITEM": items.append(body)
	var src: Array = issue["items"]
	for i in mini(items.size(), src.size()):
		(src[i] as Dictionary)["text"] = items[i]
		got += 1
	if got >= 3:
		issue["source"] = "llm"
		issue_printed.emit(issue)
		return true
	return false


# ------------------------------------------------------------------- saving

func snapshot() -> Dictionary:
	return {"issues": issues, "log": _log, "prev": _prev, "last_pick": _last_pick,
		"asked": _asked_day}


func restore(d: Dictionary) -> void:
	issues.clear()
	for i: Variant in d.get("issues", []):
		if i is Dictionary:
			var issue: Dictionary = i
			issue["day"] = int(issue.get("day", 1))
			issue["edition"] = int(issue.get("edition", issues.size() + 1))
			issues.append(issue)
	var lg: Variant = d.get("log", {})
	if lg is Dictionary and (lg as Dictionary).has("built"):
		_log = {"built": (lg as Dictionary)["built"], "harvest": (lg as Dictionary).get("harvest", {})}
	_prev = d.get("prev", {}) if d.get("prev", {}) is Dictionary else {}
	_last_pick = d.get("last_pick", {}) if d.get("last_pick", {}) is Dictionary else {}
	_asked_day = int(d.get("asked", -1))
