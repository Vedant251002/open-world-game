extends Node
## Seasons that matter.
##
## Weather owns the calendar (four seasons of twelve days, the sky, the rain);
## this makes the calendar bite:
##
##   spring  crops grow fast; newcomers arrive and the flocks have young
##   summer  crops grow fastest
##   autumn  growth slows to a crawl; the harvest festival if the stores are
##           full (the town is merrier, the larder lighter); the first frost
##           is announced a day ahead
##   winter  nothing grows and the first frost kills whatever is still in the
##           field; everybody eats half again as much and the hearths burn
##           timber; a bare larder is a crisis (see Crisis)
##
## and tells the player what is coming: "Winter in 3 days -- the stores hold 40
## days of food." The look of each season (snow, turning leaves, falling
## petals) lives in scripts/obj/season_fx.gd; this just tells it the date.
##
## The growth rate is written onto the Farm each day (Farm.season_rate), so the
## farm needs no idea what a season is.

## Daily growth multiplier by season. Farm.advance_days multiplies by it.
const GROWTH := {"spring": 1.35, "summer": 1.2, "autumn": 0.45, "winter": 0.0}
## Winter appetites: half again on the larder, and a hearth in every house.
const WINTER_FOOD_FACTOR := 1.5
const WINTER_TIMBER_PER_HEAD := 0.4
## The festival falls on this day of autumn, and wants this many days of food.
const FESTIVAL_DAY := 6
const FESTIVAL_FOOD_DAYS := 10.0
const FEAST_FOOD_EACH := 1
const WARN_DAYS := [3, 1]

var realm: Realm
var festival_year := -1       ## the last year the festival was held (or missed)
var _warned: Dictionary = {}  ## "year:days" -> true, so a warning is given once
var _last_season := ""
var _cold_note_day := 0
var _rng := RandomNumberGenerator.new()


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	_last_season = season()       # the season the game starts in is not news
	_refresh()


func _weather() -> Node:
	return realm.system("Weather")


func season() -> String:
	var wx := _weather()
	return str(wx.call("season")) if wx != null else "spring"


## The multiplier crops grow by today.
func growth_rate() -> float:
	return float(GROWTH.get(season(), 1.0))


## "AUTUMN  ·  DAY 3/12" -- for the HUD.
func hud_label() -> String:
	var wx := _weather()
	if wx == null:
		return ""
	return "%s  ·  %d/%d" % [season().to_upper(), int(wx.call("day_of_season")), RealmWeather.DAYS_PER_SEASON]


## How many days the larder would last at the winter appetite -- what the
## warnings quote, because winter is what they are warning about.
func winter_food_days() -> float:
	var pop := maxi(realm.population.count(), 1)
	return float(realm.town.units_of("food")) / (float(pop) * WINTER_FOOD_FACTOR)


## Days of food at the appetite of the season it is now.
func food_days() -> float:
	var pop := maxi(realm.population.count(), 1)
	var each := WINTER_FOOD_FACTOR if season() == "winter" else 1.0
	return float(realm.town.units_of("food")) / (float(pop) * each)


## Writes today's date onto everything that looks at it: the farm's growth
## rate and the picture of the season.
func _refresh() -> void:
	var wx := _weather()
	if wx == null:
		return
	var s := season()
	if realm.farm != null:
		realm.farm.season_rate = float(GROWTH.get(s, 1.0))
	var look: Node = wx.call("season_fx") if wx.has_method("season_fx") else null
	if look != null:
		look.call("set_look", s, int(wx.call("day_of_season")))


# ---------------------------------------------------------------------- clock

func on_hour(_hour: float, _day: int) -> void:
	# Cheap (a handful of shader parameters and one number), and it keeps the
	# farm and the picture right after a load whose save pre-dates this system.
	_refresh()


func on_day(day: int) -> void:
	var wx := _weather()
	if wx == null:
		return
	_refresh()
	var s := season()
	var dos := int(wx.call("day_of_season"))
	if s != _last_season:
		_last_season = s
		_season_begins(s)
	_warn_winter(wx)
	match s:
		"autumn":
			if dos == FESTIVAL_DAY:
				_festival(wx)
		"winter":
			_winter_day(day)
		"spring":
			if dos == 2:
				_arrivals()
			elif dos == 4:
				_young_animals()


func _announce(title: String, status: String, action: String, tone: String) -> void:
	var cr := realm.system("Crisis")
	if cr != null and cr.has_method("announce"):
		cr.call("announce", title, status, action, tone)


func _season_begins(s: String) -> void:
	var line := ""
	match s:
		"spring":
			line = "Spring has come: the ground is soft and the crops grow fast. Newcomers will be on the road."
		"summer":
			line = "Summer: the long days. Crops grow fastest now, and the fields want water."
		"autumn":
			line = "Autumn. Growth is slow now: bring in what is ripe, and fill the larder before winter."
		"winter":
			line = "Winter has come. Nothing grows, the frost has killed what was left standing, and every hearth wants wood."
	if line != "":
		realm.say(line)
		realm.note("season", line)


## "Winter in 3 days -- the stores hold 40 days of food."
func _warn_winter(wx: Node) -> void:
	if season() == "winter":
		return
	var away := int(wx.call("days_until", "winter"))
	if away not in WARN_DAYS:
		return
	var yr := int(wx.call("year_of"))
	var key := "%d:%d" % [yr, away]
	if _warned.has(key):
		return
	_warned[key] = true
	var days := int(winter_food_days())
	var line := "Winter in %d day%s -- the stores hold %d days of food." % [away, "" if away == 1 else "s", days]
	var enough := days >= 30
	var action := "" if enough else "Say: \"bring in the harvest\" or \"buy food\""
	if away == 1:
		var standing := 0
		if realm.farm != null:
			standing = realm.farm.planted_count()
		if standing > 0:
			line += " The first frost comes tonight; %d plants are still in the field." % standing
			action = "Say: \"bring in the harvest\" now"
	realm.say(line)
	realm.note("season", line)
	_announce("WINTER IN %d DAY%s" % [away, "" if away == 1 else "S"], line.substr(line.find("--") + 3),
		action, "info" if enough else "warn")


## Every winter day: the frost takes anything planted, the larder and the
## woodpile are drawn on harder.
func _winter_day(day: int) -> void:
	var wx := _weather()
	var lost := 0
	if realm.farm != null:
		lost = realm.farm.frost_kill()
	if lost > 0:
		var line := "The frost has killed %d plants still in the field." % lost
		realm.say(line)
		realm.note("season", line)
	var pop := realm.population.count()
	if pop <= 0:
		return
	# The extra half a loaf each.
	var extra := int(ceil(float(pop) * (WINTER_FOOD_FACTOR - 1.0)))
	var food := realm.town.units_of("food")
	realm.town.stock["food"] = maxi(food - extra, 0)
	# Wood for the fires.
	var need := int(ceil(float(pop) * WINTER_TIMBER_PER_HEAD))
	var timber := realm.town.units_of("timber")
	var burned := mini(need, timber)
	realm.town.stock["timber"] = timber - burned
	if burned < need:
		# A cold house: the housed feel it too.
		for c: Population.Citizen in realm.population.alive():
			if c.home_id >= 0:
				c.needs["warm"] = maxf(float(c.needs["warm"]) - 0.2, 0.0)
				c.mood = clampf(c.mood - 0.02, 0.0, 1.0)
		if day - _cold_note_day >= 3:
			_cold_note_day = day
			realm.say("The woodpile is bare. The houses are cold.")
			realm.note("season", "There was not wood enough to keep the hearths lit.")
	elif day - _cold_note_day >= 6:
		_cold_note_day = day
		realm.note("season", "The winter hearths burned %d timber today, and the larder gave up %d extra food." % [burned, extra])
	var dos := int(wx.call("day_of_season")) if wx != null else 0
	if dos == 1:
		_announce("WINTER", "Nothing grows now. The town eats half again as much.", "", "info")


## Autumn: the harvest festival, if the larder is full enough to afford one.
func _festival(wx: Node) -> void:
	var yr := int(wx.call("year_of"))
	if festival_year == yr:
		return
	festival_year = yr
	var pop := realm.population.alive()
	if pop.is_empty():
		return
	if food_days() >= FESTIVAL_FOOD_DAYS:
		var feast := mini(pop.size() * FEAST_FOOD_EACH, realm.town.units_of("food"))
		realm.town.stock["food"] = realm.town.units_of("food") - feast
		for c: Population.Citizen in pop:
			c.mood = clampf(c.mood + 0.15, 0.0, 1.0)
			c.needs["fed"] = 1.0
		var line := "The harvest festival: the whole town feasted on the well-stocked larder, and is merrier for it."
		realm.say(line)
		realm.note("festival", "%s (%d people, %d food.)" % [line, pop.size(), feast])
		_announce("HARVEST FESTIVAL", "The stores are full: the town feasts, and spirits soar.", "", "good")
		Sfx.milestone()
		var look: Node = wx.call("season_fx") if wx.has_method("season_fx") else null
		if look != null and look.has_method("confetti"):
			look.call("confetti", realm.village.well_pos)
		# Somebody says something about it.
		var w := realm.crew.workers[0] if realm.crew != null and not realm.crew.workers.is_empty() else null
		if w != null and is_instance_valid(w):
			(w as Worker).speak("A good harvest, and enough to share. Long may it last!", "done")
	else:
		var line2 := "There is no harvest festival this year: the stores are too thin to feast on."
		realm.say(line2)
		realm.note("festival", line2)
		_announce("NO FESTIVAL", "The stores hold only %d days of food. Fill the larder before winter." % int(food_days()),
			"Say: \"bring in the harvest\"", "warn")


## Spring: people take to the road again.
func _arrivals() -> void:
	var pop := realm.population
	var free := pop.beds() - pop.housed()
	var law: Node = realm.system("Law")
	var open := law == null or not law.has_method("borders_open") or bool(law.call("borders_open"))
	if free <= 0 or not open:
		realm.note("season", "Spring brought nobody to the gate; there was no bed to offer them.")
		return
	var n := mini(_rng.randi_range(1, 3), free)
	var before := pop.count()
	for i in n:
		pop._arrive(1)
	var came := pop.count() - before
	if came > 0:
		realm.say("%d newcomer%s came in with the spring thaw." % [came, "" if came == 1 else "s"])
		realm.note("season", "%d newcomer%s arrived with the spring." % [came, "" if came == 1 else "s"])
		_announce("SPRING ARRIVALS", "%d newcomer%s came in with the thaw." % [came, "" if came == 1 else "s"], "", "good")


## Spring: lambs, chicks, calves.
func _young_animals() -> void:
	var stock := realm.livestock
	if stock == null or stock.animals.is_empty():
		return
	var kinds: Dictionary = {}
	for a: Animal in stock.animals:
		if is_instance_valid(a) and not kinds.has(a.kind):
			kinds[a.kind] = a.global_position
	var born := 0
	var names: Array[String] = []
	for kind: String in kinds:
		if stock.count_of(kind) < 1:
			continue
		var n := stock.stock_area(kind, kinds[kind], mini(2, maxi(stock.count_of(kind) / 2, 1)), 4.0)
		if n > 0:
			born += n
			names.append(kind)
	if born > 0:
		var line := "Spring: %d young among the %s." % [born, " and ".join(names)]
		realm.say(line)
		realm.note("season", line)


# -------------------------------------------------------------------- talking

func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["ready for winter", "prepared for winter", "enough for winter", "stores for winter",
			"enough food for winter", "will we last the winter"]):
		var wx := _weather()
		var away := int(wx.call("days_until", "winter")) if wx != null else 0
		var d := int(winter_food_days())
		var lead := "Winter is %d days off" % away if away > 0 else "It is winter"
		return "%s, and the stores hold %d days of food at the winter appetite. %s" % [
			lead, d, "We will manage." if d >= 30 else "It is not enough; we should lay in more."]
	if Realm.has_phrase(t, ["how long will the food last", "how many days of food", "how much food do we have",
			"days of food"]):
		return "The stores hold %d days of food, as things stand." % int(food_days())
	if Realm.has_phrase(t, ["harvest festival", "when is the festival", "the festival"]):
		return "The festival falls on day %d of autumn, and wants a full larder (%d days of food)." % [
			FESTIVAL_DAY, int(FESTIVAL_FOOD_DAYS)]
	return ""


func situation() -> String:
	var wx := _weather()
	if wx == null:
		return ""
	var away := int(wx.call("days_until", "winter"))
	if season() != "winter" and away > 0 and away <= 6:
		return "Winter is %d days away; the stores hold %d days of food at winter appetite." % [away, int(winter_food_days())]
	return ""


# ---------------------------------------------------------------- persistence

func snapshot() -> Dictionary:
	return {"festival_year": festival_year, "warned": _warned.keys(), "last_season": _last_season,
		"cold_note_day": _cold_note_day}


func restore(d: Dictionary) -> void:
	festival_year = int(d.get("festival_year", -1))
	_warned = {}
	for k: Variant in d.get("warned", []):
		_warned[str(k)] = true
	_last_season = str(d.get("last_season", ""))
	_cold_note_day = int(d.get("cold_note_day", 0))
	_refresh()
