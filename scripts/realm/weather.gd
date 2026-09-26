extends Node
class_name RealmWeather
## The sky's moods, and what they do to the town.
##
## A year is four seasons of twelve days, so a game the length of an evening
## sees at least one whole turn of them — long enough that "wait for spring"
## is a plan somebody can actually make. The weather itself is a small state
## machine ticking on the game clock, not on real time, so a storm you spot
## rolling in is still rolling in ten minutes later when you get back from
## the quarry.
##
## Everything here either changes a number another system already owns (the
## farm waters, the population gets cold, a roof voxel goes to air) or draws a
## few cheap boxes. Nothing here should ever cost a frame: the sky palette is
## a handful of floats read back by sky_env, and the rain is one recycled
## MultiMesh, not six hundred raindrops each with their own node.

const DAYS_PER_SEASON := 12
const DAYS_PER_YEAR := DAYS_PER_SEASON * 4
const SEASONS := ["spring", "summer", "autumn", "winter"]
const STATES := ["clear", "overcast", "rain", "storm", "fog", "snow"]

## Chance per hour of moving from one state to another, by season. Missing
## keys mean "stays put" — nobody is meant to get out of every state, and a
## season that cannot reach one thing (spring cannot snow) simply omits it.
const TRANSITIONS := {
	"spring": {
		"clear":    {"overcast": 0.08, "rain": 0.02},
		"overcast": {"clear": 0.12, "rain": 0.15, "fog": 0.04},
		"rain":     {"overcast": 0.25, "storm": 0.06, "clear": 0.05},
		"storm":    {"rain": 0.40, "clear": 0.10},
		"fog":      {"clear": 0.30, "overcast": 0.15},
	},
	"summer": {
		"clear":    {"overcast": 0.05, "rain": 0.015},
		"overcast": {"clear": 0.22, "rain": 0.10, "storm": 0.03},
		"rain":     {"overcast": 0.30, "storm": 0.12, "clear": 0.10},
		"storm":    {"rain": 0.45, "clear": 0.15},
		"fog":      {"clear": 0.35},
	},
	"autumn": {
		"clear":    {"overcast": 0.12, "fog": 0.05, "rain": 0.02},
		"overcast": {"clear": 0.10, "rain": 0.20, "fog": 0.06},
		"rain":     {"overcast": 0.28, "storm": 0.08, "clear": 0.05},
		"storm":    {"rain": 0.42, "clear": 0.08},
		"fog":      {"clear": 0.28, "overcast": 0.18},
	},
	"winter": {
		"clear":    {"overcast": 0.14, "fog": 0.04},
		"overcast": {"clear": 0.10, "snow": 0.16, "rain": 0.04, "fog": 0.04},
		"rain":     {"snow": 0.22, "overcast": 0.28, "clear": 0.04},
		"snow":     {"overcast": 0.16, "clear": 0.06},
		"storm":    {"snow": 0.30, "rain": 0.15, "clear": 0.08},
		"fog":      {"clear": 0.22, "overcast": 0.16},
	},
}

## How the sky looks in each state. Neutral in "clear" so a clear day is
## exactly the palette sky_env already had before weather existed.
const VISUALS := {
	"clear":    {"tint": Color(1.0, 1.0, 1.0), "fog": 0.00, "cloud": 0.00, "precip": ""},
	"overcast": {"tint": Color(0.78, 0.80, 0.85), "fog": 0.08, "cloud": 0.30, "precip": ""},
	"rain":     {"tint": Color(0.60, 0.65, 0.72), "fog": 0.18, "cloud": 0.34, "precip": "rain"},
	"storm":    {"tint": Color(0.40, 0.43, 0.50), "fog": 0.30, "cloud": 0.42, "precip": "rain"},
	"fog":      {"tint": Color(0.82, 0.83, 0.85), "fog": 0.55, "cloud": 0.10, "precip": ""},
	"snow":     {"tint": Color(0.80, 0.87, 0.99), "fog": 0.20, "cloud": 0.25, "precip": "snow"},
}

const FLAMMABLE := [VoxelTypes.TIMBER, VoxelTypes.PLANK, VoxelTypes.THATCH]

const PRECIP_MAX := 400
const PRECIP_RADIUS := 15.0
const PRECIP_TOP := 9.0
const PRECIP_BOTTOM := -1.0
const PRECIP_UPDATE_DT := 0.05
const SKY_REFRESH_DT := 0.5
const FX_UPDATE_DT := 0.1

var realm: Realm

var _rng := RandomNumberGenerator.new()
## Shifts which day of the year day 1 is, so not every new town starts in
## spring. Picked once and then saved, so a reload keeps its own calendar.
var _season_offset := 0
var _state := "clear"
var _wind := Vector2(1.0, 0.0)
var _dry_days := 0        ## consecutive rainless summer days, for drought
var _rained_today := false
## Holds the state through the on_hour right after force() sets it, so a test
## (or another system) that forces "rain" sees rain actually happen before
## the roll has a chance to carry it away again.
var _forced_hold := 0

var _thunder_said := false
var _lightning_timer := 0.0
var _lightning_restore := false
var _lightning_saved_energy := 0.0

var _fires: Array[Dictionary] = []   ## {id, rec, hp, started, embers: [{pos, at}]}
var _next_fire_id := 0
var _fire_fx: Dictionary = {}        ## fire id -> Node3D of ember/smoke boxes

var _precip: MultiMeshInstance3D = null
var _precip_kind := ""
var _precip_positions: PackedVector3Array = PackedVector3Array()
var _precip_speeds: PackedFloat32Array = PackedFloat32Array()

var _precip_t := 0.0
var _sky_refresh_t := 0.0
var _fx_t := 0.0


func setup(r: Realm) -> void:
	realm = r
	_rng.randomize()
	_season_offset = _rng.randi() % DAYS_PER_YEAR
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			force(a.substr(10))
	_build_precip()
	_refresh_sky()


# -------------------------------------------------------------- seasons & sun

func _day_of_year(day: int = -1) -> int:
	var d := ((realm.clock.day if day < 0 else day) - 1) + _season_offset
	return ((d % DAYS_PER_YEAR) + DAYS_PER_YEAR) % DAYS_PER_YEAR


func season() -> String:
	if realm == null or realm.clock == null:
		return "spring"
	return SEASONS[(_day_of_year() / DAYS_PER_SEASON) % SEASONS.size()]


## A little texture on top of the plain name — "early spring", "high summer",
## "late autumn" — because a season is a stretch of days, not a light switch.
func season_word() -> String:
	var pos := _day_of_year() % DAYS_PER_SEASON
	var part := "early"
	if pos >= 8:
		part = "late"
	elif pos >= 4:
		part = "high"
	return "%s %s" % [part, season()]


const TEMP_MEAN := 13.0
const TEMP_AMPLITUDE := 12.0


## Pure in the day number, deliberately: two calls the same day always agree,
## so nothing has to remember yesterday's reading. The curve peaks at
## midsummer and troughs at midwinter; the noise is seeded off the day
## itself, so it is "random" without needing a saved history.
func temperature(day: int = -1) -> float:
	var doy := _day_of_year(day)
	var angle := TAU * float(doy - DAYS_PER_SEASON * 1.5) / float(DAYS_PER_YEAR)
	var base := TEMP_MEAN + TEMP_AMPLITUDE * cos(angle)
	var d := realm.clock.day if day < 0 else day
	var noise_rng := RandomNumberGenerator.new()
	noise_rng.seed = hash("weather_temp_%d" % d)
	return base + noise_rng.randf_range(-3.0, 3.0)


func is_raining() -> bool:
	return _state == "rain" or _state == "storm"


## Overrides the state directly — for a test, or another system narrating a
## storm brewing for a siege. Holds through the very next on_hour so it is
## not immediately rolled away again.
func force(state: String) -> void:
	if state not in STATES:
		return
	var prev := _state
	_state = state
	_forced_hold = 1
	if state == "storm" and prev != "storm":
		_thunder_said = false
		_lightning_timer = _rng.randf_range(5.0, 15.0)
	_refresh_sky()


func burning() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fire: Dictionary in _fires:
		out.append(fire["rec"])
	return out


# ------------------------------------------------------------------- the day

func on_day(_day: int) -> void:
	if season() == "summer" and not _rained_today:
		_dry_days += 1
		if _dry_days == 10:
			realm.note("drought", "No rain in ten days now. The fields are suffering for it.")
			realm.say("It has not rained in ten days. The crops are struggling.")
	else:
		_dry_days = 0
	_rained_today = false


func on_hour(_hour: float, _day: int) -> void:
	if realm == null or realm.clock == null:
		return
	var cur_season := season()
	if _state == "snow" and cur_season != "winter":
		_state = "overcast"
	if _forced_hold > 0:
		_forced_hold -= 1
	else:
		_roll_weather(cur_season)

	if is_raining():
		_rained_today = true
		_water_fields()
	if _state == "snow" or temperature() < 2.0:
		_chill_homeless()
	if _state == "storm" and _rng.randf() < 0.22:
		_storm_damage()
	if _state in ["clear", "overcast"] and _dry_days >= 2 and temperature() > 26.0 \
			and _rng.randf() < 0.01:
		var rec := _pick_flammable_building()
		if not rec.is_empty():
			ignite(rec, "the dry heat")

	for fire: Dictionary in _fires.duplicate():
		_tick_fire_progress(fire)
	_refresh_sky()


func _roll_weather(cur_season: String) -> void:
	var table: Dictionary = TRANSITIONS.get(cur_season, {})
	var options: Dictionary = table.get(_state, {})
	var prev := _state
	var r := _rng.randf()
	var acc := 0.0
	for to_state: String in options:
		acc += float(options[to_state])
		if r < acc:
			_state = to_state
			break
	_wind = (_wind + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))) \
		.limit_length(2.5)
	if _state == "storm" and prev != "storm":
		_thunder_said = false
		_lightning_timer = _rng.randf_range(15.0, 40.0)


# -------------------------------------------------------------------- effects

func _water_fields() -> void:
	if realm.farm == null or realm.farm.tiles.is_empty():
		return
	var min_x := 1 << 30
	var max_x := -(1 << 30)
	var min_z := 1 << 30
	var max_z := -(1 << 30)
	for key: Vector2i in realm.farm.tiles:
		min_x = mini(min_x, key.x)
		max_x = maxi(max_x, key.x)
		min_z = mini(min_z, key.y)
		max_z = maxi(max_z, key.y)
	realm.farm.water(Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1), 1.0)


## Snow and hard cold bite the people with no roof over them — everyone
## indoors is already kept warm by Population's own daily upkeep.
func _chill_homeless() -> void:
	if realm.population == null:
		return
	for c: Population.Citizen in realm.population.alive():
		if c.home_id < 0:
			c.needs["warm"] = maxf(float(c.needs["warm"]) - 0.06, 0.0)
			c.mood = maxf(c.mood - 0.015, 0.0)


## A storm takes a couple of thatch tiles off a roof, chosen from whatever is
## actually standing there now rather than what was originally built — a
## building already missing its roof cannot lose it twice.
func _storm_damage() -> void:
	if realm.town.buildings.is_empty():
		return
	var rec: Dictionary = realm.town.buildings[_rng.randi() % realm.town.buildings.size()]
	var patch: VoxelPatch = rec.get("patch")
	if patch == null:
		return
	var fp: Rect2i = patch.footprint
	if fp.size.x <= 0 or fp.size.y <= 0:
		return
	var knocked := 0
	for _try in 10:
		if knocked >= 2:
			break
		var fx := _rng.randi_range(fp.position.x, fp.end.x - 1)
		var fz := _rng.randi_range(fp.position.y, fp.end.y - 1)
		var top := realm.world.height_at(fx, fz)
		if top < 0:
			continue
		if realm.world.get_voxel(Vector3i(fx, top, fz)) == VoxelTypes.THATCH:
			realm.world.set_voxel(Vector3i(fx, top, fz), VoxelTypes.AIR)
			knocked += 1
	if knocked > 0:
		realm.note("storm", "The storm tore thatch off the %s's roof." %
			str(rec.get("archetype", "building")).replace("_", " "))


# ---------------------------------------------------------------------- fire

func _fire_for(rec: Dictionary) -> Dictionary:
	for fire: Dictionary in _fires:
		if int((fire["rec"] as Dictionary).get("id", -1)) == int(rec.get("id", -2)):
			return fire
	return {}


func _pick_flammable_building() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for rec: Dictionary in realm.town.buildings:
		if _fire_for(rec).is_empty():
			candidates.append(rec)
	if candidates.is_empty():
		return {}
	return candidates[_rng.randi() % candidates.size()]


## A building catches: lightning, the dry heat, a fire spreading next door, or
## another system's own reason. Called by everyone through this one door so a
## building can never be on fire twice.
func ignite(rec: Dictionary, why: String) -> void:
	if realm == null or rec.is_empty() or not _fire_for(rec).is_empty():
		return
	_next_fire_id += 1
	var fire := {"id": _next_fire_id, "rec": rec, "hp": 100.0, "started": _abs_hour(),
		"embers": []}
	_fires.append(fire)
	var name := str(rec.get("archetype", "building")).replace("_", " ")
	realm.say("The %s is on fire!" % name)
	realm.note("fire", "The %s caught fire, from %s." % [name, why])
	_spawn_fire_visual(fire)


func _abs_hour() -> float:
	return float(realm.clock.day) * 24.0 + realm.clock.hour


## Firefighting, ageing and, failing either of those, the fire finishing on
## its own. Voxels only burn while the fire is still alive at the end of this.
func _tick_fire_progress(fire: Dictionary) -> void:
	var age := _abs_hour() - float(fire["started"])
	var active: Array[Worker] = []
	if realm.crew != null:
		for w: Worker in realm.crew.hired():
			var extra: Dictionary = w.job_errand.get("extra", {})
			if int(extra.get("fire_id", -1)) == int(fire["id"]):
				active.append(w)

	if not active.is_empty():
		var rec: Dictionary = fire["rec"]
		var door := realm.door_of(rec)
		var far := realm.village.well_pos.distance_to(door) > 60.0
		var rate := 16.0 * active.size() * (0.55 if far else 1.0)
		fire["hp"] = maxf(float(fire["hp"]) - rate, 0.0)

	if float(fire["hp"]) <= 0.0:
		_extinguish(fire, active, true)
		return
	if age >= 6.0:
		_extinguish(fire, active, false)
		return
	_tick_fire_voxels(fire)
	_maybe_spread(fire)


## Eats a handful of flammable voxels each hour: last hour's embers finish
## burning through to air, and a few more catch. Sampled rather than scanned,
## so the cost is the same twelve edits whether the building is a hut or a
## tower block.
func _tick_fire_voxels(fire: Dictionary) -> void:
	var rec: Dictionary = fire["rec"]
	var patch: VoxelPatch = rec.get("patch")
	if patch == null or realm.world == null:
		return
	var abs_hour := _abs_hour()
	var edits := 0
	var keep: Array = []
	for e: Dictionary in (fire["embers"] as Array):
		if edits >= 12:
			keep.append(e)
			continue
		if abs_hour - float(e["at"]) >= 2.0:
			realm.world.set_voxel(e["pos"], VoxelTypes.AIR)
			edits += 1
		else:
			keep.append(e)
	fire["embers"] = keep

	var tries := 0
	while edits < 12 and tries < 60:
		tries += 1
		var lx := _rng.randi_range(0, maxi(patch.size.x - 1, 0))
		var ly := _rng.randi_range(0, maxi(patch.size.y - 1, 0))
		var lz := _rng.randi_range(0, maxi(patch.size.z - 1, 0))
		var wp := patch.origin + Vector3i(lx, ly, lz)
		if realm.world.get_voxel(wp) in FLAMMABLE:
			realm.world.set_voxel(wp, VoxelTypes.EMBER)
			(fire["embers"] as Array).append({"pos": wp, "at": abs_hour})
			edits += 1


func _maybe_spread(fire: Dictionary) -> void:
	if _rng.randf() > 0.05:
		return
	var rec: Dictionary = fire["rec"]
	var plot := realm.village.plot_by_id(int(rec.get("plot_id", -1)))
	if plot == null:
		return
	var options: Array[Dictionary] = []
	for nid: int in plot.neighbours:
		var nb := realm.town.find_by_plot(nid)
		if not nb.is_empty() and _fire_for(nb).is_empty():
			options.append(nb)
	if options.is_empty():
		return
	ignite(options[_rng.randi() % options.size()], "the fire next door")


func _extinguish(fire: Dictionary, active: Array[Worker], by_hand: bool) -> void:
	var rec: Dictionary = fire["rec"]
	var name := str(rec.get("archetype", "building")).replace("_", " ")
	for w: Worker in active:
		w.drop_everything()
	if by_hand and not active.is_empty():
		active[0].speak("Fire's out at the %s." % name, "done")
		realm.note("fire", "The fire at the %s was put out." % name)
	else:
		realm.say("The fire at the %s has burned itself out." % name)
		realm.note("fire", "The %s burned for hours before it finally went out." % name)
	_clear_fire_visual(fire)
	_fires.erase(fire)


func _fire_named_in(t: String) -> Dictionary:
	for fire: Dictionary in _fires:
		var arch := str((fire["rec"] as Dictionary).get("archetype", "")).replace("_", " ")
		if arch != "" and t.find(arch) >= 0:
			return fire
	return {}


## "put out the fire", "fight the fire at the bakery" — the worker given the
## order, plus every idle hired hand, turns out for it. The well is the water:
## a building far from it takes longer to save.
func _fight_fire(worker: Worker, fire: Dictionary) -> void:
	var rec: Dictionary = fire["rec"]
	var door := realm.door_of(rec)
	var name := str(rec.get("archetype", "building")).replace("_", " ")
	var brigade: Array[Worker] = [worker]
	if realm.crew != null:
		for w: Worker in realm.crew.hired():
			if w != worker and not w.busy():
				brigade.append(w)
	for i in brigade.size():
		var w2: Worker = brigade[i]
		var line := ("Forming a bucket line for the %s!" % name) if i == 0 else ""
		w2.take_errand_job("station", door, 30.0, line,
			{"doing": "hammer", "fire_id": int(fire["id"])})
	realm.note("fire", "The crew turned out to fight the fire at the %s." % name)


# -------------------------------------------------------------- fire visuals

func _spawn_fire_visual(fire: Dictionary) -> void:
	if realm.props_root == null:
		return
	var rec: Dictionary = fire["rec"]
	var patch: VoxelPatch = rec.get("patch")
	if patch == null:
		return
	var fp: Rect2i = patch.footprint
	if fp.size.x <= 0 or fp.size.y <= 0:
		return
	var v := VoxelChunk.VOXEL_M
	var cx := fp.position.x + fp.size.x * 0.5
	var cz := fp.position.y + fp.size.y * 0.5
	var top := realm.world.height_at(int(cx), int(cz))
	var centre := Vector3(cx * v, float(maxi(top, 0) + 1) * v, cz * v)

	var root := Node3D.new()
	root.name = "Fire%d" % int(fire["id"])
	root.position = centre
	realm.props_root.add_child(root)
	for i in 6:
		var ember := i % 2 == 0
		var colour := Color("#ff7a2a") if ember else Color(0.35, 0.35, 0.33, 0.65)
		var size := Vector3(0.22, 0.22, 0.22) if ember else Vector3(0.4, 0.5, 0.4)
		var box := BoxKit.add(root, Vector3(
			randf_range(-0.6, 0.6), randf_range(0.0, 1.2), randf_range(-0.6, 0.6)),
			size, colour)
		box.visibility_range_end = 120.0
		box.set_meta("base_y", box.position.y)
		box.set_meta("phase", randf() * TAU)
	_fire_fx[int(fire["id"])] = root


func _clear_fire_visual(fire: Dictionary) -> void:
	var id := int(fire["id"])
	var node: Node3D = _fire_fx.get(id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_fire_fx.erase(id)


func _bob_fire_fx(dt: float) -> void:
	for id: int in _fire_fx:
		var root: Node3D = _fire_fx[id]
		if not is_instance_valid(root):
			continue
		for child: Node in root.get_children():
			if not (child is MeshInstance3D):
				continue
			var mi := child as MeshInstance3D
			var phase := float(mi.get_meta("phase", 0.0)) + dt * 1.6
			mi.set_meta("phase", phase)
			var base_y := float(mi.get_meta("base_y", mi.position.y))
			mi.position.y = base_y + sin(phase) * 0.12


# ------------------------------------------------------------------ lightning

func _flash_lightning() -> void:
	if realm.sky == null or realm.sky.sun == null:
		return
	_lightning_saved_energy = realm.sky.sun.light_energy
	realm.sky.sun.light_energy = maxf(_lightning_saved_energy, 1.0) + 2.2
	_lightning_restore = true
	if not _thunder_said:
		_thunder_said = true
		realm.say("Thunder.")
	if _rng.randf() < 0.12:
		var rec := _pick_flammable_building()
		if not rec.is_empty():
			ignite(rec, "a lightning strike")


# --------------------------------------------------------------- sky & rain

func _build_precip() -> void:
	if realm.props_root == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxKit.mesh(Vector3(0.014, 0.3, 0.014))
	mm.instance_count = PRECIP_MAX
	_precip = MultiMeshInstance3D.new()
	_precip.name = "Precipitation"
	_precip.multimesh = mm
	_precip.material_override = BoxKit.paint(Color(0.78, 0.84, 0.93, 0.55))
	_precip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_precip.visibility_range_end = 90.0
	_precip.visible = false
	realm.props_root.add_child(_precip)

	_precip_positions.resize(PRECIP_MAX)
	_precip_speeds.resize(PRECIP_MAX)
	for i in PRECIP_MAX:
		_precip_positions[i] = Vector3(_rng.randf_range(-PRECIP_RADIUS, PRECIP_RADIUS),
			_rng.randf_range(PRECIP_BOTTOM, PRECIP_TOP),
			_rng.randf_range(-PRECIP_RADIUS, PRECIP_RADIUS))
		_precip_speeds[i] = _rng.randf_range(4.0, 7.0)


func _set_precip_kind(kind: String) -> void:
	if kind == _precip_kind or _precip == null:
		return
	_precip_kind = kind
	if kind == "":
		_precip.visible = false
		return
	_precip.visible = true
	if kind == "snow":
		_precip.multimesh.mesh = BoxKit.mesh(Vector3(0.05, 0.05, 0.05))
		_precip.material_override = BoxKit.paint(Color(0.95, 0.97, 1.0, 0.85))
	else:
		_precip.multimesh.mesh = BoxKit.mesh(Vector3(0.014, 0.3, 0.014))
		_precip.material_override = BoxKit.paint(Color(0.78, 0.84, 0.93, 0.55))


## Falls a fixed cloud of boxes around the player and loops them back to the
## top — no allocation, no node creation, just the same PRECIP_MAX transforms
## written again. Called at most every PRECIP_UPDATE_DT seconds.
func _update_precip(dt: float) -> void:
	if _precip == null or _precip_kind == "" or realm.player == null:
		return
	var mm := _precip.multimesh
	var fall := 1.0 if _precip_kind == "rain" else 0.3
	var drift := _wind * (0.15 if _precip_kind == "rain" else 0.5)
	for i in PRECIP_MAX:
		var p: Vector3 = _precip_positions[i]
		p.y -= _precip_speeds[i] * dt * fall
		p.x += drift.x * dt
		p.z += drift.y * dt
		if p.y < PRECIP_BOTTOM:
			p.y = PRECIP_TOP
			p.x = _rng.randf_range(-PRECIP_RADIUS, PRECIP_RADIUS)
			p.z = _rng.randf_range(-PRECIP_RADIUS, PRECIP_RADIUS)
		_precip_positions[i] = p
		mm.set_instance_transform(i, Transform3D(Basis(), p))
	_precip.global_position = realm.player.global_position


func _refresh_sky() -> void:
	if realm.sky == null:
		return
	var v: Dictionary = VISUALS.get(_state, VISUALS["clear"])
	realm.sky.weather_tint = v["tint"]
	realm.sky.weather_fog = v["fog"]
	realm.sky.cloud_cover = v["cloud"]
	realm.sky.hour = realm.sky.hour   # re-trigger _apply_time() with the new fields
	_set_precip_kind(str(v["precip"]))


func tick(delta: float) -> void:
	_precip_t += delta
	if _precip_t >= PRECIP_UPDATE_DT:
		_update_precip(_precip_t)
		_precip_t = 0.0

	if _lightning_restore:
		_lightning_restore = false
		if realm.sky != null and realm.sky.sun != null:
			realm.sky.sun.light_energy = _lightning_saved_energy
	if _state == "storm":
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = _rng.randf_range(20.0, 60.0)
			_flash_lightning()

	if not _fire_fx.is_empty():
		_fx_t += delta
		if _fx_t >= FX_UPDATE_DT:
			_bob_fire_fx(_fx_t)
			_fx_t = 0.0

	_sky_refresh_t += delta
	if _sky_refresh_t >= SKY_REFRESH_DT:
		_sky_refresh_t = 0.0
		_refresh_sky()


# --------------------------------------------------------------- talking

func verbs() -> Dictionary:
	return {
		"fight_fire": {
			"says": "turn everyone free out with buckets against a fire — at a named building, or whichever is burning",
			"optional": ["place"],
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	if str(step.get("do", "")) != "fight_fire":
		return "failed"
	if _fires.is_empty():
		worker.speak("Nothing is burning right now.")
		return "done"
	var fire := _fire_named_in(str(step.get("place", "")).to_lower().replace("_", " "))
	if fire.is_empty():
		fire = _fires[0]
	if worker.busy():
		return "I am busy just now — I will get to it after."
	_fight_fire(worker, fire)
	return "started"


func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["on fire", "anything burning", "anything alight"]):
		if _fires.is_empty():
			return "Nothing is on fire."
		var names: Array[String] = []
		for fire: Dictionary in _fires:
			names.append(str((fire["rec"] as Dictionary).get("archetype", "building"))
				.replace("_", " "))
		return "Yes — the %s." % ", the ".join(names)
	if Realm.has_phrase(t, ["what season", "which season", "is it spring", "is it summer",
			"is it autumn", "is it winter"]):
		return "It is %s." % season_word()
	if Realm.has_phrase(t, ["when is winter", "when does winter", "when will winter",
			"when is summer", "when does summer", "when will summer",
			"when is spring", "when does spring", "when is autumn", "when does autumn"]):
		return _next_season_line(t)
	if Realm.has_phrase(t, ["how cold", "how hot", "what is the temperature", "temperature"]):
		return _temperature_line()
	if Realm.has_phrase(t, ["will it rain", "is it going to rain", "going to rain"]):
		return _forecast_line()
	if Realm.has_phrase(t, ["is it raining", "is it snowing", "what is the weather",
			"what's the weather", "hows the weather", "how is the weather",
			"weather like", "weather today"]):
		return _weather_line()
	return ""


func _weather_line() -> String:
	match _state:
		"clear": return "Clear skies, %s." % season_word()
		"overcast": return "Overcast, %s." % season_word()
		"rain": return "Raining, %s." % season_word()
		"storm": return "A storm is on us — %s." % season_word()
		"fog": return "Thick fog about."
		"snow": return "Snow is falling, %s." % season_word()
	return "Fair weather."


func _temperature_line() -> String:
	var temp := temperature()
	var word := "mild"
	if temp < 2.0:
		word = "bitterly cold"
	elif temp < 8.0:
		word = "cold"
	elif temp < 16.0:
		word = "cool"
	elif temp < 24.0:
		word = "mild"
	elif temp < 30.0:
		word = "warm"
	else:
		word = "hot"
	return "It is %s out — about %d degrees." % [word, int(round(temp))]


func _forecast_line() -> String:
	if is_raining():
		return "It is raining already."
	if _state == "overcast":
		return "It looks likely — the sky has gone grey."
	return "No sign of it yet."


func _next_season_line(t: String) -> String:
	var target := "winter"
	for s: String in SEASONS:
		if t.find(s) >= 0:
			target = s
	var cur := season()
	if cur == target:
		return "It is %s now." % target
	var cur_i := SEASONS.find(cur)
	var target_i := SEASONS.find(target)
	var seasons_away := (target_i - cur_i + SEASONS.size()) % SEASONS.size()
	var days_into := _day_of_year() % DAYS_PER_SEASON
	var days_left := DAYS_PER_SEASON - days_into
	var days_away := days_left + (seasons_away - 1) * DAYS_PER_SEASON
	return "%d days off, by my reckoning." % maxi(days_away, 1)


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if _state in ["rain", "storm", "snow", "fog"]:
		out.append("%s · %s" % [season(), _state])
	if not _fires.is_empty():
		var names: Array[String] = []
		for fire: Dictionary in _fires:
			names.append(str((fire["rec"] as Dictionary).get("archetype", "building"))
				.replace("_", " "))
		out.append("FIRE: %s" % ", ".join(names))
	return out


# ---------------------------------------------------------------- persistence

func _building_by_id(id: int) -> Dictionary:
	for rec: Dictionary in realm.town.buildings:
		if int(rec.get("id", -1)) == id:
			return rec
	return {}


func snapshot() -> Dictionary:
	var fires_out: Array = []
	for fire: Dictionary in _fires:
		var rec: Dictionary = fire["rec"]
		fires_out.append({"building_id": int(rec.get("id", -1)), "hp": float(fire["hp"]),
			"started": float(fire["started"]), "embers": fire["embers"]})
	return {
		"season_offset": _season_offset, "state": _state, "wind": _wind,
		"dry_days": _dry_days, "rained_today": _rained_today,
		# Informational only: temperature() is a pure function of the day and
		# the season offset above, so restoring it needs nothing further.
		"temperature": temperature(),
		"fires": fires_out,
	}


func restore(d: Dictionary) -> void:
	_season_offset = int(d.get("season_offset", _season_offset))
	_state = str(d.get("state", "clear"))
	_wind = d.get("wind", _wind)
	_dry_days = int(d.get("dry_days", 0))
	_rained_today = bool(d.get("rained_today", false))
	for fire: Dictionary in _fires.duplicate():
		_clear_fire_visual(fire)
	_fires.clear()
	_next_fire_id = 0
	for e: Dictionary in d.get("fires", []):
		var rec := _building_by_id(int(e.get("building_id", -1)))
		if rec.is_empty():
			continue
		_next_fire_id += 1
		var fire := {"id": _next_fire_id, "rec": rec, "hp": float(e.get("hp", 100.0)),
			"started": float(e.get("started", _abs_hour())), "embers": e.get("embers", [])}
		_fires.append(fire)
		_spawn_fire_visual(fire)
	_refresh_sky()
