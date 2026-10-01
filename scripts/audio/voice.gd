class_name Voice
## Villagers speak aloud, and (on the web) you can speak back.
##
## Output uses DisplayServer.tts_*: the OS voices on desktop, and on the web the
## browser's speechSynthesis through the same calls. Each villager gets a stable
## voice (voice id, pitch and rate picked from a hash of their id), so Mira
## sounds like Mira every session. Only the person you are talking to, or
## somebody close by, is voiced, and one at a time, so a busy street is not a
## chorus. Everything no-ops cleanly where there is no TTS (headless, a browser
## with no voices): supported() is false, the sound panel says so, nothing errors.
##
## Input: Voice.dictation_supported() is true in a browser with
## SpeechRecognition. install_mic() adds a microphone button to the web
## instruction bar (WebInput) that dictates into its text field; elsewhere it
## does nothing and the button never exists.
##
## Settings live in user://settings.cfg [voice], beside the audio buses.

const PATH := "user://settings.cfg"
## Lines of these kinds are speech to the player; the rest is work chatter.
const SPOKEN_KINDS := ["talk", "question", "refuse", "done", "plan"]
## Beyond this many metres a villager is not voiced unless you are in
## conversation with them.
const HEARING_M := 12.0
const MAX_CHARS := 220

static var enabled := true
static var volume := 0.8
static var listener: Node3D = null       ## the player, set by the HUD
static var focus_id := ""                ## who the player is talking to right now
static var last_spoken := ""             ## for tests and the HUD
static var spoken_count := 0
static var _loaded := false
static var _voice_ids: Array[String] = []
static var _voices_asked := false
static var _utterance := 1


# ------------------------------------------------------------------ support

## True when this machine/browser can speak. On the web the voice list loads
## after start-up, so an empty list is asked about again, not given up on.
static func supported() -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	_refresh_voices()
	return not _voice_ids.is_empty()


static func _refresh_voices() -> void:
	if not _voice_ids.is_empty():
		return
	# Only the browser fills its list in late; a desktop with no speech engine
	# says so once (and logs an engine error each time it is asked).
	if _voices_asked and not OS.has_feature("web"):
		return
	_voices_asked = true
	var all: Array = DisplayServer.tts_get_voices_for_language("en")
	if all.is_empty():
		all = DisplayServer.tts_get_voices()
	for v: Variant in all:
		if v is Dictionary and str((v as Dictionary).get("id", "")) != "":
			_voice_ids.append(str((v as Dictionary)["id"]))


static func dictation_supported() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval(
		"!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true)
	return bool(v) if v != null else false


# ----------------------------------------------------------------- settings

static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	enabled = bool(cf.get_value("voice", "enabled", true))
	volume = clampf(float(cf.get_value("voice", "volume", 0.8)), 0.0, 1.0)


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("voice", "enabled", enabled)
	cf.set_value("voice", "volume", volume)
	cf.save(PATH)


static func set_enabled(on: bool) -> void:
	load_settings()
	enabled = on
	if not on:
		stop()


static func set_volume(v: float) -> void:
	load_settings()
	volume = clampf(v, 0.0, 1.0)


# ------------------------------------------------------------------ profile

## A stable voice for one person. voice_ids may be empty (nothing to choose
## from); pitch and rate are still returned so tests can check stability.
static func profile_for(worker_id: String, voice_ids: Array) -> Dictionary:
	var h: int = absi(worker_id.hash())
	var id := ""
	if not voice_ids.is_empty():
		id = str(voice_ids[h % voice_ids.size()])
	return {
		"voice": id,
		"pitch": 0.82 + float((h >> 8) % 55) / 100.0,      # 0.82 .. 1.36
		"rate": 0.90 + float((h >> 16) % 22) / 100.0,      # 0.90 .. 1.11
	}


# ----------------------------------------------------------------- speaking

## Whether this line should be voiced right now, and how loud (0..1), given
## the distance to the listener. Pure of the TTS engine, so it is testable.
static func loudness(worker_id: String, kind: String, line: String, dist_m: float) -> float:
	load_settings()
	if not enabled or kind not in SPOKEN_KINDS:
		return 0.0
	var t := line.strip_edges()
	if t == "" or t == "…" or t == "...":
		return 0.0
	if worker_id == focus_id and focus_id != "":
		return volume
	if dist_m > HEARING_M:
		return 0.0
	return volume * clampf(1.0 - dist_m / (HEARING_M * 1.25), 0.15, 1.0)


## Called from Worker._say for every line. Safe anywhere.
static func speak(worker: Node3D, worker_id: String, line: String, kind: String) -> void:
	load_settings()
	if not enabled or not supported():
		return
	var dist := 0.0
	if listener != null and is_instance_valid(listener) and worker != null:
		dist = listener.global_position.distance_to(worker.global_position)
	var loud := loudness(worker_id, kind, line, dist)
	if loud <= 0.0:
		return
	var master := 0.0 if AudioBuses.muted else AudioBuses.volume(AudioBuses.MASTER)
	var vol := int(round(loud * master * 100.0))
	if vol <= 0:
		return
	# One voice at a time, and the person you are talking to wins.
	var talking := DisplayServer.tts_is_speaking()
	var is_focus := worker_id == focus_id and focus_id != ""
	if talking and not is_focus:
		return
	var p := profile_for(worker_id, _voice_ids)
	var text := _clean(line)
	if text == "":
		return
	_utterance += 1
	last_spoken = worker_id
	spoken_count += 1
	DisplayServer.tts_speak(text, str(p["voice"]), clampi(vol, 1, 100),
		float(p["pitch"]), float(p["rate"]), _utterance, is_focus)


## A short line in a middling voice, to judge the volume by.
static func sample() -> void:
	if not supported():
		return
	var p := profile_for("sample", _voice_ids)
	var master := 0.0 if AudioBuses.muted else AudioBuses.volume(AudioBuses.MASTER)
	DisplayServer.tts_speak("Good morning. The bread is in.", str(p["voice"]),
		clampi(int(round(volume * master * 100.0)), 1, 100), 1.0, 1.0, 0, true)


static func stop() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()


static func _clean(line: String) -> String:
	var t := line.replace("*", "").replace("_", " ").replace("—", ", ").strip_edges()
	if t.length() > MAX_CHARS:
		t = t.substr(0, MAX_CHARS)
		var cut := maxi(t.rfind(". "), t.rfind(", "))
		if cut > 60:
			t = t.substr(0, cut + 1)
	return t


# -------------------------------------------------------------------- input

## Adds a mic button to the web instruction bar. WebInput exposes the text
## field and button row on window.__dgt.el; with no SpeechRecognition (Firefox,
## some iOS) the button is simply never created.
const MIC_JS := """
(function () {
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var d = window.__dgt;
  if (!SR || !d || !d.el || d.mic) { return; }
  var input = d.el.input, row = d.el.row;
  var b = document.createElement('button');
  b.type = 'button';
  b.setAttribute('aria-label', 'Dictate');
  b.textContent = '\\uD83C\\uDF99';
  b.style.cssText = 'font-size:18px;padding:13px 14px;border-radius:8px;'
    + 'border:1px solid #6a655c;background:#332f2a;color:#f4f0e9;-webkit-appearance:none;';
  var rec = null, live = false;
  function stop() { live = false; b.style.background = '#332f2a'; try { rec && rec.stop(); } catch (e) {} }
  b.addEventListener('click', function () {
    if (live) { stop(); return; }
    try {
      rec = new SR();
      rec.lang = navigator.language || 'en-US';
      rec.interimResults = true;
      rec.continuous = false;
      rec.onresult = function (ev) {
        var s = '';
        for (var i = 0; i < ev.results.length; i++) { s += ev.results[i][0].transcript; }
        input.value = s;
      };
      rec.onend = function () { live = false; b.style.background = '#332f2a'; input.focus(); };
      rec.onerror = function () { live = false; b.style.background = '#332f2a'; };
      rec.start();
      live = true;
      b.style.background = '#8a3b2e';
    } catch (e) { live = false; }
  });
  row.insertBefore(b, input.nextSibling);
  d.mic = b;
})();
"""


static func install_mic() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(MIC_JS, true)
