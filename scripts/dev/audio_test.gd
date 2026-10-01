extends Node
class_name AudioTest
## Headless check of the soundscape (run with the dummy audio driver):
##
##   godot --headless --audio-driver Dummy --path . -- --audiotest --nosave
##
## Boots the real game, then drives the AudioDirector through a day, a night,
## rain and a storm by setting the clock and weather and ticking its layers by
## hand, asserting that the right things start - and, above all, that nothing
## errors. Exits 0 on pass.

var main: Node
var fails: Array[String] = []

const ASSETS := ["wind_loop", "rain_loop", "water_loop", "murmur_loop", "crickets_loop",
	"thunder_1", "thunder_2", "pad_day", "pad_eve", "pad_night",
	"bird_tweet_1", "bird_tweet_3", "bird_trill_2", "bird_warble_3", "bird_thrush_2",
	"bird_cuckoo", "bird_dove", "owl_1", "owl_2",
	"hen_1", "hen_3", "sheep_1", "sheep_2", "cow_1", "cow_2",
	"hammer_1", "hammer_3", "stone_1", "stone_2", "saw_1", "saw_2",
	"step_grass_3", "step_dirt_3", "step_stone_3", "step_wood_3", "step_sand_2", "step_splash_2",
	"ui_click", "ui_hover", "ui_chime", "ui_milestone", "ui_built", "ui_alert", "ui_page",
	"pluck_50", "pluck_78", "flute_69", "flute_81"]


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails.append(what)
		print("[audiotest] FAIL: %s" % what)


func begin() -> void:
	await get_tree().process_frame
	var res: Variant = await _run()
	var code: int = 1 if res == null else int(res)
	print("[audiotest] %s (%d failures)" % ["PASS" if code == 0 else "FAIL", fails.size()])
	get_tree().quit(code)


func _run() -> int:
	# --- buses and settings -------------------------------------------------
	AudioBuses.ensure()
	for b: String in AudioBuses.ALL:
		_check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	AudioBuses.set_volume(AudioBuses.MUSIC, 0.25)
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.25)) < 0.01,
		"music volume applies")
	AudioBuses.set_volume(AudioBuses.MUSIC, AudioBuses.DEFAULTS["Music"])
	AudioBuses.set_muted(true)
	_check(AudioServer.is_bus_mute(0), "mute applies to master")
	AudioBuses.set_muted(false)
	var had_file := FileAccess.file_exists(AudioBuses.PATH)
	if not had_file:
		AudioBuses.set_volume(AudioBuses.SFX, 0.33)
		AudioBuses.save()
		AudioBuses.volumes.clear()
		AudioBuses.load_settings()
		_check(absf(AudioBuses.volume("SFX") - 0.33) < 0.001, "settings round trip")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioBuses.PATH))
		AudioBuses.set_volume(AudioBuses.SFX, AudioBuses.DEFAULTS["SFX"])

	# --- assets -------------------------------------------------------------
	var bytes := 0
	for n: String in ASSETS:
		var s := AudioLib.get_stream(n)
		_check(s != null, "asset %s loads" % n)
	for n: String in ["wind_loop", "rain_loop", "pad_day"]:
		var l := AudioLib.get_loop(n) as AudioStreamWAV
		_check(l != null and l.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % n)
	for f in DirAccess.get_files_at("res://assets/audio"):
		if f.ends_with(".wav"):
			bytes += FileAccess.get_file_as_bytes("res://assets/audio/" + f).size()
	print("[audiotest] %d wav files, %.2f MB source" % [DirAccess.get_files_at("res://assets/audio").size() / 2, bytes / 1048576.0])
	_check(bytes < 4 * 1048576, "source audio under 4 MB")

	# --- the director -------------------------------------------------------
	var d: AudioDirector = main.get("audio")
	_check(d != null, "director exists")
	if d == null:
		return 1
	_check(d.unlocked, "unlocked headless")
	var realm: Realm = main.get("realm")
	var clock: GameClock = main.get("clock")
	var wx: Node = realm.system("Weather") if realm != null else null
	_check(wx != null, "weather system found")

	# Clear morning: birds, wind, no rain, no crickets.
	_scenario(clock, wx, 7.0, "clear")
	var heard_birds := _tick(d, 60.0, func() -> bool: return _playing_3d(d) > 0)
	_check(heard_birds, "birdsong plays on a clear morning")
	_check(d.ambience._chan.has("wind") and float(d.ambience._chan["wind"]["tgt"]) > 0.2, "wind bed on")
	_check(not d.ambience._chan.has("rain") or float(d.ambience._chan["rain"]["tgt"]) < 0.01, "no rain on a clear day")
	_check(not d.ambience._chan.has("crickets") or float(d.ambience._chan["crickets"]["tgt"]) < 0.01, "no crickets by day")

	# Music starts after the opening silence, and stops again.
	d.music._wait = 0.0
	var began := _tick(d, 30.0, func() -> bool: return d.music.is_playing())
	_check(began, "music piece begins")
	var heard_note := _tick(d, 40.0, func() -> bool:
		for p in d.music._pluck_pool + d.music._flute_pool:
			if p.playing:
				return true
		return false)
	_check(heard_note, "music plays notes")
	d.music._left = 0.5
	_tick(d, 3.0, func() -> bool: return false)
	_check(not d.music.is_playing(), "piece ends, leaving silence")
	_check(d.music._wait > 40.0, "silence between pieces is long (%.0fs)" % d.music._wait)

	# Rain: no birds, rain bed, wind up.
	_scenario(clock, wx, 14.0, "rain")
	_tick(d, 8.0, func() -> bool: return false)
	_check(d.ambience._chan.has("rain") and float(d.ambience._chan["rain"]["tgt"]) > 0.3, "rain bed on in rain")
	_check(d.ambience._chan.has("rain") and float(d.ambience._chan["rain"]["cur"]) > 0.05, "rain bed fades in")

	# Storm: thunder, music held back.
	_scenario(clock, wx, 15.0, "storm")
	d.music._wait = 0.0
	var thunder := _tick(d, 40.0, func() -> bool:
		for c in d.ambience.get_children():
			if c is AudioStreamPlayer and c.stream != null and "thunder" in str(c.stream.resource_path):
				return true
		return false)
	_check(thunder, "thunder rolls in a storm")
	_check(not d.music.is_playing(), "no music in a storm")

	# Summer night: crickets, owl; birds quiet. Find a summer day first.
	for day in range(1, 49):
		clock.day = day
		if str(wx.call("season")) == "summer":
			break
	_scenario(clock, wx, 23.0, "clear")
	_tick(d, 10.0, func() -> bool: return false)
	_check(d.ambience._chan.has("crickets") and float(d.ambience._chan["crickets"]["tgt"]) > 0.2, "crickets on a summer night")
	d.ambience._owl_wait = 0.0
	_check(_tick(d, 5.0, func() -> bool: return _playing_3d(d) > 0), "owl hoots at night")
	_check(d.music.mood_for(23.0) == "night" and d.music.mood_for(8.0) == "morning"
		and d.music.mood_for(13.0) == "day" and d.music.mood_for(19.0) == "evening", "moods by hour")

	# Footsteps on every surface, work sounds, animals, UI.
	for k in ["grass", "dirt", "stone", "wood", "sand", "splash"]:
		d.world_sfx._step(k, -10.0, 1.0)
	d.ui("ui_click")
	d.notify("ui_chime")
	d.notify("ui_milestone", true)
	Sfx.click()
	Sfx.hover()
	Sfx.page()
	var crew: Crew = main.get("crew")
	if crew != null and not crew.workers.is_empty():
		var w: Worker = crew.workers[0]
		d.world_sfx._strike(w, {"t": 0.0, "mode": "hammer", "left": 1})
		d.world_sfx._strike(w, {"t": 0.0, "mode": "saw", "left": 2})
		_check(_playing_3d(d) > 0, "work sounds play")
	d.world_sfx._animal_wait = 0.0
	_tick(d, 2.0, func() -> bool: return false)

	# A button gets its sound hooks.
	var b := Button.new()
	UiTheme.style_button(b)
	_check(b.has_meta("_sfx"), "buttons are hooked")
	b.free()

	# Pause-menu sound panel builds.
	var panel := SoundPanel.build()
	_check(panel != null, "sound panel builds")
	panel.free()

	# Leave the world as we found it.
	wx.call("force", "clear")
	return 0 if fails.is_empty() else 1


func _scenario(clock: GameClock, wx: Node, hour: float, state: String) -> void:
	clock.hour = hour
	if wx != null:
		wx.call("force", state)
	var d: AudioDirector = main.get("audio")
	d._update_env()
	# Sit the player somewhere with open sky so the roof check does not interfere.
	d.indoor = 0.0


func _playing_3d(d: AudioDirector) -> int:
	var n := 0
	for p in d._pool3d:
		if p.playing:
			n += 1
	return n


## Ticks the layers by hand, 0.25 s at a time, until `until` is true or the
## simulated time runs out.
func _tick(d: AudioDirector, seconds: float, until: Callable) -> bool:
	var t := 0.0
	while t < seconds:
		d._update_env()
		d.ambience._process(0.25)
		d.music._process(0.25)
		d.world_sfx._process(0.25)
		t += 0.25
		if until.call():
			return true
	return false
