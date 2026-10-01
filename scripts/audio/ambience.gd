extends Node
class_name Ambience
## The sound of the place itself, layered and crossfaded by time and weather.
##
## Looping beds (each fades smoothly towards a target level, and stops
## entirely when silent so the mixer is not mixing nothing):
##   wind      - always there, gusting; stronger with weather
##   rain      - with rain or storm
##   crickets  - warm nights
##   water     - positional, at the nearest water within ~20 m
##   murmur    - positional, at the centre of nearby villagers; a market hum
## and scheduled one-shots with randomised timing:
##   birdsong  - tweets, trills, warbles, thrush, dove, cuckoo; thick at dawn,
##               gone in rain, thin in winter
##   owl       - at night, sometimes answered from another tree
##   thunder   - in storms
## Walking indoors closes a low-pass on the whole bus (AudioBuses.set_muffle),
## which is done by the director.

const BASE := {"wind": 0.55, "rain": 0.6, "crickets": 0.3, "water": 0.85, "murmur": 0.5}

var dir: AudioDirector

var _chan: Dictionary = {}
var _t := 0.0
var _slow := 0.0
var _water_target := Vector3.ZERO
var _water_level := 0.0
var _murmur_target := Vector3.ZERO
var _murmur_level := 0.0
var _bird_wait := 6.0
var _owl_wait := 20.0
var _thunder_wait := 8.0
var _pending: Array[Dictionary] = []       ## calls answering one another
var _was_storm := false
var _wind_level := 0.45
var _rain_level := 0.0
var _cricket_level := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if dir == null or not dir.unlocked:
		return
	_t += delta
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.25
		_plan_levels()
	_update_beds(delta)
	_schedule_birds(delta)
	_schedule_owl(delta)
	_schedule_thunder(delta)


# --------------------------------------------------------------------- beds

func _bed(name: String, positional: bool) -> Dictionary:
	if _chan.has(name):
		return _chan[name]
	var stream := AudioLib.get_loop(name + "_loop")
	if stream == null:
		return {}
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 9.0
		p3.max_distance = 45.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.top_level = true
		p3.bus = AudioBuses.AMBIENCE
		p3.stream = stream
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.bus = AudioBuses.AMBIENCE
		p2.stream = stream
		p = p2
	add_child(p)
	var ch := {"p": p, "cur": 0.0, "tgt": 0.0, "rate": 0.8}
	_chan[name] = ch
	return ch


func _set_target(name: String, level: float, positional: bool = false, rate: float = 0.8) -> void:
	var ch: Dictionary = _chan.get(name, {})
	if ch.is_empty():
		if level < 0.004:
			return                      # nothing to fade, nothing to build
		ch = _bed(name, positional)
		if ch.is_empty():
			return
	ch["tgt"] = level
	ch["rate"] = rate


func _update_beds(delta: float) -> void:
	# Wind gusts: two incommensurate slow waves, so the swell never repeats.
	var g := clampf(0.5 + 0.5 * sin(_t * 0.37) * sin(_t * 0.113 + 1.0) + 0.25 * sin(_t * 0.9 + 2.0), 0.0, 1.0)
	var wind_ch: Dictionary = _chan.get("wind", {})
	if not wind_ch.is_empty():
		var p: AudioStreamPlayer = wind_ch["p"]
		p.pitch_scale = 0.92 + 0.12 * g
	for name: String in _chan:
		var ch: Dictionary = _chan[name]
		var tgt: float = ch["tgt"]
		if name == "wind":
			tgt *= 0.62 + 0.55 * g
		tgt *= 1.0 - 0.4 * dir.indoor * (0.6 if name == "rain" else 1.0)
		var cur: float = ch["cur"]
		cur += (tgt - cur) * (1.0 - exp(-delta * float(ch["rate"])))
		ch["cur"] = cur
		var p: Node = ch["p"]
		if cur < 0.004 and float(ch["tgt"]) < 0.004:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * 2.0)
		p.volume_db = linear_to_db(cur * float(BASE[name]))
	# Positional beds follow their targets smoothly.
	var wc: Dictionary = _chan.get("water", {})
	if not wc.is_empty():
		var wp: AudioStreamPlayer3D = wc["p"]
		wp.global_position = wp.global_position.lerp(_water_target, clampf(delta * 3.0, 0.0, 1.0))
	var mc: Dictionary = _chan.get("murmur", {})
	if not mc.is_empty():
		var mp: AudioStreamPlayer3D = mc["p"]
		mp.global_position = mp.global_position.lerp(_murmur_target, clampf(delta * 2.0, 0.0, 1.0))


## Works out how loud each bed should be from the world state. Four times a
## second is plenty: the beds smooth themselves.
func _plan_levels() -> void:
	var st := dir.wx_state
	var night := dir.night
	var wind := 0.45
	match st:
		"overcast":
			wind = 0.62
		"rain":
			wind = 0.72
		"storm":
			wind = 1.0
		"fog":
			wind = 0.3
		"snow":
			wind = 0.7
	wind *= 1.0 - 0.18 * night
	_set_target("wind", wind, false, 0.4)

	var rain := dir.raining()
	_set_target("rain", rain, false, 0.5)

	var cricket_season := 1.0
	match dir.season:
		"winter":
			cricket_season = 0.0
		"autumn":
			cricket_season = 0.55
		"spring":
			cricket_season = 0.8
	var calm := 1.0 - minf(rain * 1.5, 1.0)
	_set_target("crickets", night * cricket_season * calm * (0.0 if st == "snow" else 1.0), false, 0.3)

	_plan_water()
	_plan_murmur()


func _plan_water() -> void:
	var p := dir.player
	var w := dir.world
	if p == null or w == null:
		return
	var pp := p.global_position
	var best := 999.0
	var best_pos := pp
	if p.in_water:
		best = 0.0
	else:
		for r: float in [2.0, 4.0, 7.0, 10.0, 14.0, 19.0]:
			if r >= best:
				break
			for a in 12:
				var ang := TAU * a / 12.0 + r * 0.7
				var x := pp.x + cos(ang) * r
				var z := pp.z + sin(ang) * r
				var vx := floori(x / VoxelWorld.VOXEL_M)
				var vz := floori(z / VoxelWorld.VOXEL_M)
				var h := w.height_at(vx, vz)
				if h < 0:
					continue
				if w.get_voxel(Vector3i(vx, h, vz)) == VoxelTypes.WATER:
					best = r
					best_pos = Vector3(x, (h + 1) * VoxelWorld.VOXEL_M, z)
					break
	if best > 20.0:
		_set_target("water", 0.0, true, 0.6)
		return
	_water_target = best_pos
	var lvl := pow(clampf(1.0 - best / 20.0, 0.0, 1.0), 1.2)
	if not _chan.has("water") and lvl > 0.004:
		_set_target("water", lvl, true, 0.6)
		var wp: AudioStreamPlayer3D = _chan["water"]["p"]
		wp.global_position = best_pos
	else:
		_set_target("water", lvl, true, 0.6)


func _plan_murmur() -> void:
	var p := dir.player
	var c := dir.crew
	if p == null or c == null:
		return
	var pp := p.global_position
	var score := 0.0
	var centre := Vector3.ZERO
	var wsum := 0.0
	for w: Worker in c.workers:
		if not is_instance_valid(w):
			continue
		var d := w.global_position.distance_to(pp)
		if d > 34.0:
			continue
		# People standing beside you are company, not a crowd.
		var wgt := clampf((d - 4.0) / 5.0, 0.0, 1.0) * (1.0 - d / 34.0)
		score += wgt
		centre += w.global_position * wgt
		wsum += wgt
	if wsum <= 0.01:
		_set_target("murmur", 0.0, true, 0.5)
		return
	centre /= wsum
	_murmur_target = centre
	var activity := 1.0 - 0.85 * dir.night
	var lvl := clampf(score / 1.6, 0.0, 1.0) * activity * (1.0 - 0.6 * dir.raining())
	if not _chan.has("murmur") and lvl > 0.004:
		_set_target("murmur", lvl, true, 0.5)
		var mp: AudioStreamPlayer3D = _chan["murmur"]["p"]
		mp.global_position = centre
	else:
		_set_target("murmur", lvl, true, 0.5)


# ----------------------------------------------------------------- one-shots

func _around(min_d: float, max_d: float, min_h: float, max_h: float) -> Vector3:
	var a := randf() * TAU
	var d := randf_range(min_d, max_d)
	var base := dir.player.global_position if dir.player != null else Vector3.ZERO
	return base + Vector3(cos(a) * d, randf_range(min_h, max_h), sin(a) * d)


func _schedule_birds(delta: float) -> void:
	if dir.player == null:
		return
	# Answering calls queued earlier.
	var i := _pending.size() - 1
	while i >= 0:
		_pending[i]["t"] -= delta
		if _pending[i]["t"] <= 0.0:
			var c: Dictionary = _pending[i]
			dir.play3d(c["s"], c["pos"], c["db"], c["pitch"], 6.0, AudioBuses.AMBIENCE, 80.0)
			_pending.remove_at(i)
		i -= 1
	_bird_wait -= delta
	if _bird_wait > 0.0:
		return
	# How busy the woods are: loud at dawn, quiet at noon, silent in rain.
	var h := dir.hour
	var busy := dir.daylight
	if h > 5.0 and h < 9.0:
		busy *= 1.7                       # the dawn chorus
	elif h > 11.0 and h < 15.0:
		busy *= 0.6
	busy *= 1.0 - clampf(dir.raining() * 1.4, 0.0, 1.0)
	if dir.wx_state == "fog" or dir.wx_state == "overcast":
		busy *= 0.7
	if dir.season == "winter" or dir.wx_state == "snow":
		busy *= 0.3
	if busy < 0.08:
		_bird_wait = 3.0
		return
	_bird_wait = randf_range(2.0, 7.0) / busy
	var s := _pick_call()
	var pos := _around(8.0, 34.0, 1.5, 8.0)
	var db := randf_range(-11.0, -5.0)
	var pitch := randf_range(0.94, 1.07)
	dir.play3d(s, pos, db, pitch, 6.0, AudioBuses.AMBIENCE, 80.0)
	# Another bird, a little way off, sometimes answers.
	if randf() < 0.4:
		var pos2 := _around(10.0, 38.0, 1.5, 8.0)
		_pending.append({"t": randf_range(0.8, 2.2), "s": _pick_call(), "pos": pos2,
			"db": db - randf_range(1.0, 4.0), "pitch": randf_range(0.93, 1.08)})


func _pick_call() -> String:
	var h := dir.hour
	var pool: Array = [["bird_tweet", 3, 3.0], ["bird_trill", 2, 2.0], ["bird_warble", 3, 2.2],
		["bird_thrush", 2, 1.2]]
	if h > 12.5:
		pool.append(["bird_dove", 0, 0.7])
	if (dir.season == "spring" or dir.season == "summer") and h < 11.0:
		pool.append(["bird_cuckoo", 0, 0.4])
	var total := 0.0
	for e: Array in pool:
		total += float(e[2])
	var r := randf() * total
	for e: Array in pool:
		r -= float(e[2])
		if r <= 0.0:
			return e[0] if int(e[1]) == 0 else AudioLib.variant(e[0], int(e[1]))
	return "bird_tweet_1"


func _schedule_owl(delta: float) -> void:
	_owl_wait -= delta
	if _owl_wait > 0.0 or dir.player == null:
		return
	if dir.night < 0.75 or dir.raining() > 0.0:
		_owl_wait = 8.0
		return
	_owl_wait = randf_range(14.0, 42.0)
	var pos := _around(20.0, 45.0, 3.0, 9.0)
	dir.play3d("owl_1", pos, randf_range(-12.0, -7.0), randf_range(0.97, 1.03), 8.0, AudioBuses.AMBIENCE, 90.0)
	if randf() < 0.5:
		_pending.append({"t": randf_range(2.6, 4.5), "s": "owl_2", "pos": _around(25.0, 50.0, 3.0, 9.0),
			"db": randf_range(-15.0, -10.0), "pitch": 1.0})


func _schedule_thunder(delta: float) -> void:
	var storm := dir.wx_state == "storm"
	if storm and not _was_storm:
		_thunder_wait = randf_range(4.0, 10.0)
	_was_storm = storm
	if not storm:
		return
	_thunder_wait -= delta
	if _thunder_wait > 0.0:
		return
	_thunder_wait = randf_range(10.0, 30.0)
	# Not positional: thunder fills the sky. Nearer strikes are louder and
	# brighter; far ones roll.
	var s := AudioLib.get_stream("thunder_%d" % (1 + randi() % 2))
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = AudioBuses.AMBIENCE
	p.stream = s
	p.volume_db = randf_range(-9.0, -2.0)
	p.pitch_scale = randf_range(0.85, 1.1)
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
