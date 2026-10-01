extends Node
## Crises: the moments the town is in real trouble, and what the player does
## about them.
##
## The other realm systems own the trouble itself (Weather the fire and the
## storm, Events the wolves and the bandits' letter, Warfare the raid, Health
## the sickness, Population the hunger). This one watches them and wraps each in
## the same drama so none of them is a line in a log you notice an hour later:
##
##   * an alarm (Sfx.alert) and a toast the moment it starts,
##   * somebody nearby shouting about it in their own voice,
##   * a banner at the top of the screen (scripts/ui/crisis_banner.gd) with its
##     live status and ONE suggested order, in words the player can type,
##   * an aftermath: what was lost and saved, in the chronicle and a closing
##     banner, when it ends.
##
## The player's answer is an ordinary spoken order. try_order() understands the
## common wordings offline ("put out the fire", "everyone to the bakery with
## buckets", "defend the town", "repair the roofs", "buy food", "quarantine"),
## so it works with no API key; with one, the model's planner reaches the same
## verbs (fight_fire, repair, decide ...) and situation() tells it what is going on.
##
## Nothing here can trap the player: every crisis burns out, passes, or is
## settled by a default after a while, with its cost written into the aftermath.
##
## Detection is by polling the owning systems (hourly, and once a second of
## real time), so a crisis started by anything at all -- an event, a lightning
## strike, a test -- gets its drama without that system knowing this exists.

signal began(crisis: Dictionary)
signal ended(crisis: Dictionary, report: String)
signal changed

const MIN_DAY := 3                 ## nothing befalls the town before this
const FAMINE_FROM_DAY := 6
const REPORT_SECONDS := 10.0       ## how long the aftermath stays on the banner
const NOTICE_SECONDS := 14.0
const RAID_GIVE_UP_HOURS := 10.0   ## raiders nobody opposes eventually leave, with spoils
const STORM_REPAIR_DAYS := 2       ## then the rain has got in whether or not it is mended
const SCAN_EVERY := 1.0

var realm: Realm
## key -> {key, kind, title, status, action, severity, since, deaths, data}
var active: Dictionary = {}
## kind -> how many have begun / ended (also how a test sees them)
var started_count: Dictionary = {}
var ended_count: Dictionary = {}
## The last aftermath: {title, line, kind, until}
var last_report: Dictionary = {}
## A passing notice that is not a crisis (winter coming, the festival).
var notice: Dictionary = {}
## Food rationing, a choice made in a famine: everyone eats a little less.
var rationed := false

var _rng := RandomNumberGenerator.new()
var _scan_t := 0.0
var _silent_scan := false      ## after a load, adopt what is already going on quietly
var _last_shout := {}          ## key -> abs hour
var _storm_damage_day := 0


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	if realm.population != null and realm.population.has_signal("died"):
		realm.population.died.connect(_on_died)


func _weather() -> Node:
	return realm.system("Weather")


func _abs_hour() -> float:
	return float(realm.clock.day) * 24.0 + realm.clock.hour


# ------------------------------------------------------------------- public

## Anything going wrong right now?
func any() -> bool:
	return not active.is_empty()


func has(kind: String) -> bool:
	for k: String in active:
		if str(active[k]["kind"]) == kind:
			return true
	return false


func kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in active:
		out.append(str(active[k]["kind"]))
	return out


## What the banner shows: the worst crisis, else a fresh aftermath, else a
## notice, else {}. {title, status, action, tone ("alert"|"warn"|"good"|"info"), more}
func banner() -> Dictionary:
	if not active.is_empty():
		var worst: Dictionary = {}
		for k: String in active:
			var c: Dictionary = active[k]
			if worst.is_empty() or float(c["severity"]) > float(worst["severity"]):
				worst = c
		return {"title": worst["title"], "status": worst["status"], "action": worst["action"],
			"tone": "alert" if float(worst["severity"]) >= 0.5 else "warn",
			"more": active.size() - 1, "kind": worst["kind"]}
	var now := Time.get_ticks_msec() / 1000.0
	if not last_report.is_empty() and now < float(last_report["until"]):
		return {"title": last_report["title"], "status": last_report["line"], "action": "",
			"tone": "good" if bool(last_report.get("good", true)) else "warn", "more": 0,
			"kind": last_report["kind"], "report": true}
	if not notice.is_empty() and now < float(notice["until"]):
		return {"title": notice["title"], "status": notice["status"], "action": notice.get("action", ""),
			"tone": notice.get("tone", "info"), "more": 0, "kind": "notice"}
	return {}


## The live crisis of this kind ({} if none): title, status, action, severity.
func crisis_of(kind: String) -> Dictionary:
	for k: String in active:
		if str(active[k]["kind"]) == kind:
			return active[k]
	return {}


## A passing notice on the banner that is not a crisis.
func announce(title: String, status: String, action: String = "", tone: String = "info") -> void:
	notice = {"title": title, "status": status, "action": action, "tone": tone,
		"until": Time.get_ticks_msec() / 1000.0 + NOTICE_SECONDS}
	Sfx.chime()
	changed.emit()


## Starts one on purpose (a test, a campaign, a scripted moment). Returns true
## if it began. Wolves, bandits and sickness go through the Events and Health
## systems exactly as they do on their own.
func trigger(kind: String) -> bool:
	match kind:
		"fire":
			var events: Node = realm.system("Events")
			var lit: bool = events != null and events.trigger("fire")
			scan()
			return lit and has("fire")
		"wolves":
			var ev: Node = realm.system("Events")
			var came: bool = ev != null and ev.trigger("wolves")
			scan()
			return came and has("wolves")
		"raid":
			if realm.warfare == null:
				return false
			realm.warfare.raid(_rng.randi_range(3, 5))
			scan()
			return not realm.warfare.raiders.is_empty()
		"sickness":
			var hl: Node = realm.system("Health")
			if hl == null:
				return false
			var n: int = int(hl.call("outbreak", "flux", 3))
			scan()
			return n > 0
		"storm":
			var wx: Node = _weather()
			if wx == null:
				return false
			wx.call("force", "storm")
			wx.call("storm_damage", 2)
			scan()
			return true
		"famine":
			realm.town.stock["food"] = 0
			scan()
			return has("famine")
	return false


# --------------------------------------------------------------------- clock

func on_hour(_hour: float, _day: int) -> void:
	scan()
	_hourly()


func on_day(day: int) -> void:
	scan()
	_daily(day)


func tick(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_EVERY:
		_scan_t = 0.0
		scan()


## One pass over everything that can go wrong.
func scan() -> void:
	if realm == null or realm.clock == null:
		return
	var seen: Dictionary = {}
	_scan_fire(seen)
	_scan_wolves(seen)
	_scan_raid(seen)
	_scan_sickness(seen)
	_scan_famine(seen)
	_scan_storm(seen)
	# Whatever is no longer going on has ended.
	for k: String in active.keys():
		if not seen.has(k):
			_conclude(k)
	_silent_scan = false


# ---------------------------------------------------------------------- fire

func _scan_fire(seen: Dictionary) -> void:
	var wx := _weather()
	if wx == null or not wx.has_method("fires"):
		return
	for fire: Dictionary in wx.call("fires"):
		var key := "fire:%d" % int(fire["id"])
		var rec: Dictionary = fire["rec"]
		var name := str(rec.get("archetype", "building")).replace("_", " ")
		var brigade: int = (wx.call("fighters_of", fire) as Array).size()
		var hp := int(fire["hp"])
		var status := ""
		if brigade > 0:
			status = "%d on the bucket line  ·  the fire is at %d%%" % [brigade, hp]
		else:
			status = "Nobody is fighting it  ·  it is spreading"
		var action := "Say: \"everyone to the %s with buckets\"" % name if brigade == 0 \
			else "Keep them at it, or send more: \"put out the fire\""
		if not active.has(key):
			_begin(key, "fire", "FIRE AT THE %s" % name.to_upper(), status, action, 0.9,
				{"fire_id": int(fire["id"]), "name": name, "pos": realm.door_of(rec)})
		else:
			_update(key, status, action, 0.9 if brigade == 0 else 0.6)
		seen[key] = true


# --------------------------------------------------------------------- wolves

func _scan_wolves(seen: Dictionary) -> void:
	var ev := realm.system("Events")
	if ev == null:
		return
	var live: Dictionary = ev.get("live")
	if not live.has("wolves"):
		return
	var w: Dictionary = live["wolves"]
	var alive := 0
	for a: Variant in w["pack"]:
		if is_instance_valid(a) and float((a as Node).get("_dying")) <= 0.0:
			alive += 1
	if alive == 0:
		return
	var status := "%d wolves among the pens  ·  %d animals left" % [alive,
		realm.livestock.total() if realm.livestock != null else 0]
	var action := "Say: \"hunt the wolves\" (soldiers or armed hands drive them off)"
	if not active.has("wolves"):
		var pos: Vector3 = realm.village.well_pos
		for a2: Variant in w["pack"]:
			if is_instance_valid(a2):
				pos = (a2 as Node3D).global_position
				break
		_begin("wolves", "wolves", "WOLVES AT THE PENS", status, action, 0.7,
			{"count": int(w["count"]), "stock0": realm.livestock.total() if realm.livestock != null else 0,
			"pos": pos})
	else:
		_update("wolves", status, action, 0.7)
	seen["wolves"] = true


# ---------------------------------------------------------------------- raid

func _scan_raid(seen: Dictionary) -> void:
	var wf := realm.warfare
	if wf == null or wf.raiders.is_empty():
		return
	var soldiers := wf.soldiers.size()
	var status := "%d raiders  ·  %d soldiers to meet them" % [wf.raiders.size(), soldiers]
	var action := "Say: \"defend the town\"" if soldiers > 0 \
		else "No soldiers! Say: \"defend the town\", or build a barracks and arm people"
	if not active.has("raid"):
		var pos := realm.village.well_pos
		if is_instance_valid(wf.raiders[0]):
			pos = (wf.raiders[0] as Node3D).global_position
		_begin("raid", "raid", "RAIDERS AT THE GATES", status, action, 1.0,
			{"count": wf.raiders.size(), "raiders_fallen0": wf.raiders_fallen,
			"soldiers_fallen0": wf.soldiers_fallen, "coins0": realm.town.coins, "pos": pos})
	else:
		_update("raid", status, action, 1.0)
		var c: Dictionary = active["raid"]
		# Nobody to oppose them: after a day they take what they can carry and go.
		if soldiers == 0 and _abs_hour() - float(c["since"]) >= RAID_GIVE_UP_HOURS:
			_raiders_withdraw()
	seen["raid"] = true


func _raiders_withdraw() -> void:
	var wf := realm.warfare
	var took := mini(maxi(realm.town.coins / 8, 20), maxi(realm.town.coins, 0))
	realm.town.coins -= took
	for r: Fighter in wf.raiders:
		if is_instance_valid(r):
			r.queue_free()
	wf.raiders = []
	if active.has("raid"):
		active["raid"]["data"]["took"] = took
		active["raid"]["data"]["withdrew"] = true
	realm.say("The raiders have taken what they could carry and gone.")


# ------------------------------------------------------------------ sickness

func _scan_sickness(seen: Dictionary) -> void:
	var hl := realm.system("Health")
	if hl == null:
		return
	var sick: Dictionary = hl.get("sick")
	if sick.size() < 2 and not active.has("sickness"):
		return
	if sick.is_empty():
		return
	var bed: Dictionary = hl.get("bedridden")
	var status := "%d are ill  ·  %d in bed" % [sick.size(), bed.size()]
	var action := "Say: \"quarantine\" to shut the town, or \"treat the sick\" (herbs, a healer)"
	if not active.has("sickness"):
		_begin("sickness", "sickness", "SICKNESS IN THE TOWN", status, action, 0.6,
			{"peak": sick.size(), "ill0": sick.size(), "pos": realm.village.well_pos})
	else:
		active["sickness"]["data"]["peak"] = maxi(int(active["sickness"]["data"]["peak"]), sick.size())
		_update("sickness", status, action, 0.6)
	seen["sickness"] = true


# -------------------------------------------------------------------- famine

## The days the larder would feed everyone for, at this season's appetite.
func food_days() -> float:
	var seasons := realm.system("Seasons")
	if seasons != null and seasons.has_method("food_days"):
		return float(seasons.call("food_days"))
	var pop := maxi(realm.population.count(), 1)
	return float(realm.town.units_of("food")) / float(pop)


func _scan_famine(seen: Dictionary) -> void:
	var pop := realm.population
	if pop == null or pop.count() < 4 or realm.clock.day < FAMINE_FROM_DAY:
		return
	var days := food_days()
	var hungry := pop.hungry()
	var on := active.has("famine")
	# In: nearly bare larder and somebody feeling it. Out: comfortably stocked.
	if not on and not (days < 2.0 and (hungry > 0 or realm.town.units_of("food") == 0)):
		return
	if on and days >= 4.0:
		return
	var winter := str(_weather().call("season")) == "winter" if _weather() != null else false
	var title := "A HARD WINTER: THE LARDER IS BARE" if winter else "FOOD IS RUNNING OUT"
	var status := "%d day%s of food left  ·  %d going hungry" % [int(days), "" if int(days) == 1 else "s", hungry]
	var action := "Say: \"buy food\", \"bring in the harvest\" or \"ration the food\""
	if not on:
		_begin("famine", "famine", title, status, action, 0.55,
			{"mood0": pop.mood_avg(), "hungry_peak": hungry, "pos": realm.village.well_pos})
	else:
		active["famine"]["data"]["hungry_peak"] = maxi(int(active["famine"]["data"]["hungry_peak"]), hungry)
		_update("famine", status, action, 0.55 + 0.1 * float(mini(hungry, 4)))
	seen["famine"] = true


# --------------------------------------------------------------------- storm

func _scan_storm(seen: Dictionary) -> void:
	var wx := _weather()
	if wx == null or not wx.has_method("storm_damaged"):
		return
	var dmg: Dictionary = wx.call("storm_damaged")
	var raging: bool = str(wx.call("state")) == "storm"
	if dmg.is_empty() and not (raging and active.has("storm")):
		return
	if dmg.is_empty():
		return
	var status := "%d roof%s torn open  ·  %s" % [dmg.size(), "" if dmg.size() == 1 else "s",
		"the storm is still on us" if raging else "the rain is getting in"]
	var action := "Say: \"repair the roofs\""
	if not active.has("storm"):
		_storm_damage_day = realm.clock.day
		_begin("storm", "storm", "STORM DAMAGE", status, action, 0.45,
			{"roofs": dmg.size(), "pos": _storm_pos(dmg)})
	else:
		active["storm"]["data"]["roofs"] = maxi(int(active["storm"]["data"]["roofs"]), dmg.size())
		_update("storm", status, action, 0.45)
		# Left too long, the rain gets in whether or not anybody mended it.
		if realm.clock.day - _storm_damage_day >= STORM_REPAIR_DAYS and not raging:
			_leave_unrepaired(dmg)
			return
	seen["storm"] = true


func _storm_pos(dmg: Dictionary) -> Vector3:
	for bid: int in dmg:
		var rec: Dictionary = realm.population._building_by_id(bid)
		if not rec.is_empty():
			return realm.door_of(rec)
	return realm.village.well_pos


func _leave_unrepaired(dmg: Dictionary) -> void:
	var up := realm.system("Upkeep")
	if up != null and up.has_method("set_condition"):
		for bid: int in dmg:
			up.call("set_condition", bid, minf(float(up.call("condition_of", bid)), 0.45))
	if active.has("storm"):
		active["storm"]["data"]["unrepaired"] = dmg.size()
	_weather().call("clear_storm_damage")


## Hammers on a torn roof: a hand who has walked to the door of a torn roof
## puts the thatch back (from the stores) the hour after they arrive. Called
## every hour. Whoever has nothing left to mend is stood down.
func _mend_roofs() -> void:
	var wx := _weather()
	if wx == null or not wx.has_method("storm_damaged"):
		return
	var dmg: Dictionary = wx.call("storm_damaged")
	for bid: int in dmg.keys():
		var rec: Dictionary = realm.population._building_by_id(bid)
		if rec.is_empty():
			dmg.erase(bid)
			continue
		var door := realm.door_of(rec)
		var mending := false
		for w: Worker in realm.crew.workers:
			if is_instance_valid(w) and bid in (w.job_errand.get("extra", {}).get("mend_ids", []) as Array) \
					and w.global_position.distance_to(door) < 9.0:
				mending = true
				break
		if not mending:
			continue
		for pos: Vector3i in dmg[bid]:
			if realm.world.get_voxel(pos) == VoxelTypes.AIR and realm.town.units_of("thatch") > 0:
				realm.world.set_voxel(pos, VoxelTypes.THATCH)
				realm.town.stock["thatch"] = int(realm.town.stock["thatch"]) - 1
		dmg.erase(bid)
		realm.note("storm", "The %s's roof was mended." % str(rec.get("archetype", "building")).replace("_", " "))
	# Stand down whoever has nothing left on their list.
	for w2: Worker in realm.crew.workers:
		if not is_instance_valid(w2):
			continue
		var ids: Array = w2.job_errand.get("extra", {}).get("mend_ids", [])
		if ids.is_empty():
			continue
		var left := false
		for id: Variant in ids:
			if dmg.has(int(id)):
				left = true
		if not left:
			w2.speak("That is the roofs done.", "done")
			w2.drop_everything()


# ------------------------------------------------------------------- lifecycle

func _begin(key: String, kind: String, title: String, status: String, action: String,
		severity: float, data: Dictionary) -> void:
	var c := {"key": key, "kind": kind, "title": title, "status": status, "action": action,
		"severity": severity, "since": _abs_hour(), "deaths": 0, "data": data}
	active[key] = c
	started_count[kind] = int(started_count.get(kind, 0)) + 1
	if not _silent_scan:
		Sfx.alert()
		_shout(key, "begin")
		realm.say(_toast_for(c))
		realm.note("crisis", "%s." % title.capitalize())
	began.emit(c)
	changed.emit()


func _update(key: String, status: String, action: String, severity: float) -> void:
	var c: Dictionary = active[key]
	c["status"] = status
	c["action"] = action
	c["severity"] = severity


func _toast_for(c: Dictionary) -> String:
	return "%s  --  %s" % [str(c["title"]).capitalize(), str(c["action"])]


## It is over: work out what it cost and say so.
func _conclude(key: String) -> void:
	if not active.has(key):
		return
	var c: Dictionary = active[key]
	var report := _aftermath(c)
	active.erase(key)
	ended_count[str(c["kind"])] = int(ended_count.get(str(c["kind"]), 0)) + 1
	var good: bool = bool(report["good"])
	last_report = {"title": str(report["title"]), "line": str(report["line"]), "kind": c["kind"],
		"good": good, "until": Time.get_ticks_msec() / 1000.0 + REPORT_SECONDS}
	realm.note("aftermath", str(report["line"]))
	realm.say(str(report["line"]))
	Sfx.chime()
	_shout(key, "end_good" if good else "end_bad", c)
	ended.emit(c, str(report["line"]))
	changed.emit()


## {title, line, good} for a finished crisis. The numbers come from what the
## owning systems recorded while it ran.
func _aftermath(c: Dictionary) -> Dictionary:
	var d: Dictionary = c["data"]
	var hours := _abs_hour() - float(c["since"])
	var deaths := int(c["deaths"])
	var dead_line := "" if deaths == 0 else " %d did not live to see it end." % deaths
	match str(c["kind"]):
		"fire":
			var wx := _weather()
			var rep: Dictionary = {}
			if wx != null:
				rep = (wx.get("fire_reports") as Dictionary).get(int(d["fire_id"]), {})
			var name := str(d.get("name", "building"))
			var lost := float(rep.get("lost", 0.0))
			var by_hand: bool = bool(rep.get("by_hand", false))
			var line := ""
			var good := true
			if lost >= 0.55:
				line = "The %s is gutted: the fire took %d%% of it. It will need rebuilding." % [name, int(lost * 100.0)]
				good = false
				_ruin(int(rep.get("building_id", -1)), 0.0)
			elif lost >= 0.15:
				line = "The %s was %s, but the fire took %d%% of its timber and thatch first." % [
					name, "saved" if by_hand else "left to burn out", int(lost * 100.0)]
				good = by_hand
				_ruin(int(rep.get("building_id", -1)), 1.0 - lost)
			else:
				line = "The %s was saved with hardly a scorch. The bucket line did it." % name if by_hand \
					else "The %s burned itself out with little harm." % name
			return {"title": "FIRE OUT", "line": line + dead_line, "good": good}
		"wolves":
			var alive_after := realm.livestock.total() if realm.livestock != null else 0
			var lost_stock := maxi(int(d.get("stock0", 0)) - alive_after, 0)
			var shot := int(d.get("count", 0)) - _wolves_left()
			var line2 := "The wolves are gone. %d shot, %d animals lost from the pens." % [maxi(shot, 0), lost_stock]
			if lost_stock == 0:
				line2 = "The wolves are gone, and the pens lost nothing. %d of the pack was shot." % maxi(shot, 0)
			return {"title": "WOLVES GONE", "line": line2 + dead_line, "good": lost_stock <= 1}
		"raid":
			var wf := realm.warfare
			var beaten := wf.raiders_fallen - int(d.get("raiders_fallen0", 0)) if wf != null else 0
			var fell := wf.soldiers_fallen - int(d.get("soldiers_fallen0", 0)) if wf != null else 0
			if bool(d.get("withdrew", false)):
				return {"title": "RAIDERS GONE", "line": "Nobody stood against them. They took %d coins and left; the town will remember it." % int(d.get("took", 0)) + dead_line, "good": false}
			var line3 := "The raid is beaten off: %d raiders down, %d of ours fallen." % [beaten, fell]
			return {"title": "RAID BEATEN", "line": line3 + dead_line, "good": fell == 0 or fell < beaten}
		"sickness":
			return {"title": "THE SICKNESS HAS PASSED",
				"line": "The sickness passed after %d days; it laid up as many as %d at once.%s" % [
					maxi(int(hours / 24.0), 1), int(d.get("peak", 0)), dead_line if deaths > 0 else " Nobody died."],
				"good": deaths == 0}
		"famine":
			var mood_drop := float(d.get("mood0", 0.7)) - realm.population.mood_avg()
			var line4 := "The larder is stocked again after %d days of want." % maxi(int(hours / 24.0), 1)
			if mood_drop > 0.05:
				line4 += " Spirits are lower for it."
			return {"title": "THE HUNGER IS OVER", "line": line4 + dead_line, "good": deaths == 0}
		"storm":
			var n := int(d.get("roofs", 0))
			if int(d.get("unrepaired", 0)) > 0:
				return {"title": "STORM DAMAGE", "line": "The storm tore %d roofs and nobody mended them in time; the rain has got in." % n, "good": false}
			return {"title": "ROOFS MENDED", "line": "The storm tore %d roof%s open; all are mended now." % [n, "" if n == 1 else "s"], "good": true}
	return {"title": "OVER", "line": "It is over.", "good": true}


func _wolves_left() -> int:
	var ev := realm.system("Events")
	if ev == null:
		return 0
	var live: Dictionary = ev.get("live")
	if not live.has("wolves"):
		return 0
	var n := 0
	for a: Variant in live["wolves"]["pack"]:
		if is_instance_valid(a) and float((a as Node).get("_dying")) <= 0.0:
			n += 1
	return n


## What the fire left: a building scorched to `sound` (0..1) wears as that.
func _ruin(building_id: int, sound: float) -> void:
	var up := realm.system("Upkeep")
	if up == null or building_id < 0 or not up.has_method("set_condition"):
		return
	up.call("set_condition", building_id, minf(float(up.call("condition_of", building_id)), sound))


func _on_died(_c: Variant) -> void:
	for k: String in active:
		active[k]["deaths"] = int(active[k]["deaths"]) + 1


# --------------------------------------------------------------- the day / hour

func _hourly() -> void:
	_mend_roofs()
	# A reminder shout every couple of hours while it lasts.
	for k: String in active:
		var last := float(_last_shout.get(k, -100.0))
		if _abs_hour() - last >= 2.0:
			_shout(k, "going")


func _daily(_day: int) -> void:
	# Hunger bites: the hungry lose health and heart.
	if active.has("famine") and realm.crew != null:
		var thin := 0
		for c: Population.Citizen in realm.population.alive():
			if float(c.needs["fed"]) < 0.4:
				c.mood = clampf(c.mood - 0.04, 0.0, 1.0)
				var w := c.worker(realm.crew)
				if w != null and is_instance_valid(w):
					w.health = maxf(w.health - 4.0, 15.0)
					thin += 1
		if thin > 0 and _rng.randf() < 0.5:
			realm.say("%d of the town are weak with hunger." % thin)
	# A rationed larder stretches: a quarter back, and nobody likes it.
	if rationed:
		if active.has("famine"):
			var back := realm.population.count() / 4
			realm.town.stock["food"] = realm.town.units_of("food") + back
			for c2: Population.Citizen in realm.population.alive():
				c2.mood = clampf(c2.mood - 0.02, 0.0, 1.0)
		else:
			rationed = false
			realm.note("crisis", "Rationing was lifted; the larder is full enough.")


# --------------------------------------------------------------------- voices

## Whoever is nearest the trouble says something about it, in their own voice.
func _shout(key: String, what: String, finished: Dictionary = {}) -> void:
	var c: Dictionary = active.get(key, finished)
	if c.is_empty():
		return
	_last_shout[key] = _abs_hour()
	var pos: Vector3 = c["data"].get("pos", realm.village.well_pos)
	var who := _nearest_voice(pos)
	if who == null:
		return
	var lines := _lines_for(str(c["kind"]), what, c["data"])
	if lines.is_empty():
		return
	who.speak(lines[_rng.randi() % lines.size()], "refuse" if what in ["begin", "going"] else "done")
	# A second voice for the alarm itself.
	if what == "begin":
		var second := _nearest_voice(pos, who)
		if second != null:
			var echoes := _lines_for(str(c["kind"]), "echo", c["data"])
			if not echoes.is_empty():
				second.speak(echoes[_rng.randi() % echoes.size()], "refuse")


func _nearest_voice(pos: Vector3, skip: Worker = null) -> Worker:
	var best: Worker = null
	var best_d := INF
	if realm.crew == null:
		return null
	for w: Worker in realm.crew.workers:
		if not is_instance_valid(w) or w == skip:
			continue
		var d := w.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = w
	return best


func _lines_for(kind: String, what: String, d: Dictionary) -> Array[String]:
	var name := str(d.get("name", "place"))
	var out: Array[String] = []
	match kind:
		"fire":
			match what:
				"begin": out = ["Fire! The %s is alight!" % name, "Smoke! Something is burning -- it is the %s!" % name,
					"Fire at the %s! Water, somebody, water!" % name]
				"echo": out = ["Get the buckets! The well, quickly!", "It will take the thatch next door if we stand here!"]
				"going": out = ["It is spreading! We need more hands!", "The %s will go if nobody comes!" % name,
					"Where is the bucket line?"]
				"end_good": out = ["It is out. Thank goodness it is out.", "We saved most of it."]
				"end_bad": out = ["All that work, gone to ash...", "It is a shell. A shell."]
		"wolves":
			match what:
				"begin": out = ["Wolves! Wolves in the pens!", "Bar the doors, there are wolves about!"]
				"echo": out = ["Get the children in!", "Somebody fetch a gun!"]
				"going": out = ["They are still at the animals!", "I can hear them from here."]
				"end_good": out = ["Quiet at last. The pens held.", "Good riddance to them."]
				"end_bad": out = ["We have lost half the flock to them.", "Never again, if I can help it."]
		"raid":
			match what:
				"begin": out = ["Raiders! Raiders at the gates!", "They have guns -- take cover!"]
				"echo": out = ["To arms! Somebody, anybody!", "Ring the bell!"]
				"going": out = ["They are still coming!", "Keep your heads down!"]
				"end_good": out = ["They are running! We held!", "That will teach them."]
				"end_bad": out = ["They took what they liked and we let them.", "We were not ready."]
		"sickness":
			match what:
				"begin": out = ["There is sickness in the street. Keep away from me.", "Half the town is down with something."]
				"echo": out = ["It started at the well, I would swear.", "Wash your hands and pray."]
				"going": out = ["Another one has taken to bed.", "Is there a healer in this town?"]
				"end_good": out = ["I think it is over. We are all up.", "Nobody left in bed. Thank heaven."]
				"end_bad": out = ["We buried too many.", "It is gone, but it took its share."]
		"famine":
			match what:
				"begin": out = ["The larder is empty. What are we to eat?", "There is nothing in the stores but dust."]
				"echo": out = ["My children have not eaten since yesterday.", "Is there no bread at all?"]
				"going": out = ["We are going hungry.", "I have started to see spots from the hunger."]
				"end_good": out = ["Food again. I could weep.", "Bread. Real bread."]
				"end_bad": out = ["We are thinner for it.", "I will not forget this winter."]
		"storm":
			match what:
				"begin": out = ["The roof is off the %s!" % name if name != "place" else "The roofs are coming off!",
					"Listen to the wind! The thatch is going!"]
				"echo": out = ["Get a ladder up there!", "It is raining in my bed!"]
				"going": out = ["Water is coming through the ceiling.", "Somebody mend that roof."]
				"end_good": out = ["Dry again. Bless whoever did it.", "Snug as a bug."]
				"end_bad": out = ["Everything is damp, and it will be till spring.", "We should have mended it at once."]
	return out


# ---------------------------------------------------------------------- orders

## Plain-English answers to a crisis, understood with no model.
func try_order(worker: Worker, text: String) -> bool:
	var t := text.to_lower()
	if worker == null:
		return false
	# Fire.
	var wx := _weather()
	var fire_words := Realm.has_phrase(t, ["put out", "fight the fire", "fight fire", "extinguish", "bucket",
		"douse", "quench", "stop the fire", "fire brigade", "fire line", "water the fire", "save the"])
	if wx != null and (fire_words and (t.find("fire") >= 0 or t.find("bucket") >= 0 or t.find("burning") >= 0
			or t.find("flame") >= 0 or t.find("blaze") >= 0) or Realm.has_phrase(t, ["with buckets", "bucket line"])):
		var fire: Dictionary = wx.call("fire_for_text", t, worker.global_position)
		if fire.is_empty():
			worker.speak("Nothing is burning.", "refuse")
			return true
		var big := Realm.has_phrase(t, ["everyone", "everybody", "all hands", "all of you", "all of us", "everyone"])
		wx.call("fight_fire", worker, fire, 8 if big else 3)
		_update_now()
		return true
	# Raiders and wolves.
	if Realm.has_phrase(t, ["defend the town", "defend the village", "defend us", "man the walls",
			"repel the", "beat off", "fight the raiders", "attack the raiders", "drive off the raiders",
			"defend the gate", "defend the pens"]):
		return _order_defend(worker)
	if Realm.has_phrase(t, ["hunt the wolves", "kill the wolves", "shoot the wolves", "drive off the wolves",
			"drive the wolves", "chase the wolves", "fight the wolves", "deal with the wolves"]):
		var ev := realm.system("Events")
		if ev == null or not (ev.get("live") as Dictionary).has("wolves"):
			worker.speak("There are no wolves about now.", "refuse")
			return true
		var line := ""
		if ev.has_method("pending_event") and str((ev.call("pending_event") as Dictionary).get("id", "")) == "wolves":
			ev.call("choose", "hunt")          # settles the question the event put to the king
			line = "The hunt is on."
		else:
			line = str(ev.call("hunt_wolves"))
		worker.speak(line, "plan")
		return true
	# Roofs.
	if Realm.has_phrase(t, ["repair the roof", "fix the roof", "mend the roof", "repair roofs", "fix roofs",
			"mend roofs", "patch the roof", "storm damage", "fix the storm", "repair the storm"]):
		return _order_mend(worker)
	# Sickness.
	if Realm.has_phrase(t, ["quarantine", "isolate the sick", "keep the sick apart"]):
		var ev2 := realm.system("Events")
		var l2: String = str(ev2.call("quarantine")) if ev2 != null and ev2.has_method("quarantine") else ""
		worker.speak(l2 if l2 != "" else "I will see the sick are kept apart.", "plan")
		return true
	if Realm.has_phrase(t, ["treat the sick", "tend the sick", "care for the sick", "heal the sick", "help the sick",
			"cure the sick"]):
		return _order_treat(worker)
	# Food.
	if Realm.has_phrase(t, ["buy food", "buy some food", "buy grain", "buy bread", "get some food", "feed the town",
			"feed everyone", "feed the people", "buy provisions"]) \
			or (Realm.has_word(t, ["buy", "purchase", "bring"]) and Realm.has_word(t, ["food", "grain", "bread", "provisions"])
			and not Realm.has_phrase(t, ["sell"])):
		return _order_buy_food(worker, t)
	if Realm.has_phrase(t, ["ration the food", "ration food", "rations", "ration the stores", "ration everyone"]):
		rationed = true
		worker.speak("Rations it is: a little less each, and the stores last.", "plan")
		realm.note("crisis", "The food was rationed.")
		return true
	return false


func _update_now() -> void:
	scan()
	changed.emit()


func _order_defend(worker: Worker) -> bool:
	var wf := realm.warfare
	if wf == null:
		return false
	if wf.raiders.is_empty():
		worker.speak("Nobody is attacking us.", "refuse")
		return true
	var r: Dictionary = wf.defend(realm.village.well_pos)
	if bool(r["ok"]):
		var r2: Dictionary = wf.attack()
		worker.speak(str(r2["line"]) if bool(r2["ok"]) else str(r["line"]), "plan")
	else:
		worker.speak("We have no soldiers. Shut yourself in; they will not stay long.", "refuse")
	return true


func _order_mend(worker: Worker) -> bool:
	var wx := _weather()
	if wx == null:
		return false
	var dmg: Dictionary = wx.call("storm_damaged")
	if dmg.is_empty():
		worker.speak("No roof is torn that I know of.", "refuse")
		return true
	var hands: Array[Worker] = [worker]
	for w: Worker in realm.crew.hired():
		if w != worker and not w.busy():
			hands.append(w)
	var ids := dmg.keys()
	var per: Array = []
	for i in hands.size():
		per.append([])
	for i2 in ids.size():
		(per[i2 % hands.size()] as Array).append(int(ids[i2]))
	var sent := 0
	for i3 in hands.size():
		var mine: Array = per[i3]
		if mine.is_empty():
			continue
		var w2: Worker = hands[i3]
		if w2.busy():
			w2.drop_everything()
		var legs: Array = []
		for bid2: int in mine:
			var rec: Dictionary = realm.population._building_by_id(bid2)
			if not rec.is_empty():
				legs.append(realm.door_of(rec))
		if legs.is_empty():
			continue
		w2.take_errand_job("patrol", legs[0], 2.0 * mine.size() + 2.0,
			"Up the ladder: %d roof%s to mend." % [mine.size(), "" if mine.size() == 1 else "s"] if sent == 0 else "",
			{"doing": "hammer", "mend_ids": mine, "where": "the torn roofs"}, legs)
		sent += 1
	return true


func _order_treat(worker: Worker) -> bool:
	var hl := realm.system("Health")
	if hl == null:
		return false
	var n := 0
	var short := false
	for w: Worker in hl.call("sick_workers"):
		if bool(hl.call("treat", w)):
			n += 1
		else:
			short = true
	if n == 0 and not short:
		worker.speak("Nobody is sick.", "refuse")
	elif n == 0:
		worker.speak("No herbs to treat them with. Somebody must forage.", "refuse")
	else:
		worker.speak("%d treated with herbs.%s" % [n, " Out of herbs for the rest." if short else ""], "done")
	scan()
	return true


func _order_buy_food(worker: Worker, t: String) -> bool:
	var want := Realm.count_in(t, maxi(realm.population.count() * 4, 20))
	var got := realm.town.buy("food", want)
	if got <= 0:
		worker.speak("The purse is empty; I cannot buy a crust.", "refuse")
	else:
		worker.speak("Bought %d food for the stores." % got, "done")
		realm.note("crisis", "%d food was bought in." % got)
	scan()
	return true


# --------------------------------------------------------------------- talking

func situation() -> String:
	if active.is_empty():
		return ""
	var bits: Array[String] = []
	for k: String in active:
		var c: Dictionary = active[k]
		bits.append("%s (%s) -- suggested order: %s" % [str(c["title"]).capitalize(), c["status"], c["action"]])
	return "CRISIS: " + "; ".join(bits) + "."


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["what should we do", "what do we do", "what should i do", "what's wrong", "what is wrong",
			"what's happening", "what is happening", "is there trouble", "are we in trouble", "any crisis",
			"what is the emergency", "what's the emergency"]):
		if active.is_empty():
			return "Nothing is wrong that I know of."
		var b := banner()
		return "%s. %s. %s." % [str(b["title"]).capitalize(), b["status"], b["action"]]
	return ""


func hud_lines() -> Array[String]:
	return []


# ------------------------------------------------------------------ persistence

func snapshot() -> Dictionary:
	return {"started": started_count, "ended": ended_count, "rationed": rationed,
		"storm_day": _storm_damage_day}


func restore(d: Dictionary) -> void:
	started_count = d.get("started", {})
	ended_count = d.get("ended", {})
	rationed = bool(d.get("rationed", false))
	_storm_damage_day = int(d.get("storm_day", 0))
	active.clear()
	_silent_scan = true       # what was already going on at save time is not news again
