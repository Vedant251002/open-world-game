class_name AudioBuses
## The mixer: five buses under Master, their volumes, and the settings file.
##
##   Master -> Music, Ambience, SFX, UI
##
## Built at runtime rather than from a bus-layout resource so the effects (a
## reverb on the music, a low-pass on the ambience that closes when you step
## indoors, a limiter on the master) live next to the code that drives them.
## Volumes are linear 0..1 in the UI and in user://settings.cfg, [audio].

const MASTER := "Master"
const MUSIC := "Music"
const AMBIENCE := "Ambience"
const SFX := "SFX"
const UI := "UI"
## Order the sliders appear in.
const ALL: Array[String] = [MASTER, MUSIC, AMBIENCE, SFX, UI]
const LABELS := {"Master": "Master", "Music": "Music", "Ambience": "Ambience",
	"SFX": "Effects", "UI": "Interface"}
const DEFAULTS := {"Master": 0.85, "Music": 0.6, "Ambience": 0.8, "SFX": 0.9, "UI": 0.7}
const PATH := "user://settings.cfg"

static var volumes: Dictionary = {}
static var muted := false
static var _built := false


## Idempotent. Safe to call from anywhere, any number of times.
static func ensure() -> void:
	if _built:
		return
	_built = true
	for b: String in [MUSIC, AMBIENCE, SFX, UI]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, MASTER)
	var verb := AudioEffectReverb.new()
	verb.room_size = 0.55
	verb.damping = 0.6
	verb.wet = 0.22
	verb.dry = 1.0
	verb.hipass = 0.1
	AudioServer.add_bus_effect(AudioServer.get_bus_index(MUSIC), verb)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(AMBIENCE), lp)
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(MASTER), lim)
	load_settings()
	apply_all()


static func load_settings() -> void:
	volumes = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for b: String in ALL:
		volumes[b] = clampf(float(cf.get_value("audio", b.to_lower(), DEFAULTS[b])), 0.0, 1.0)
	muted = bool(cf.get_value("audio", "muted", false))


## The settings file may hold other sections one day: load, change ours, write.
static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	for b: String in ALL:
		cf.set_value("audio", b.to_lower(), volumes.get(b, DEFAULTS[b]))
	cf.set_value("audio", "muted", muted)
	cf.save(PATH)


static func apply_all() -> void:
	for b: String in ALL:
		apply(b)
	var mi := AudioServer.get_bus_index(MASTER)
	if mi >= 0:
		AudioServer.set_bus_mute(mi, muted)


static func apply(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v: float = volume(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	if bus != MASTER:
		AudioServer.set_bus_mute(i, v <= 0.001)


static func volume(bus: String) -> float:
	if volumes.is_empty():
		return float(DEFAULTS.get(bus, 1.0))
	return float(volumes.get(bus, DEFAULTS.get(bus, 1.0)))


static func set_volume(bus: String, v: float) -> void:
	ensure()
	volumes[bus] = clampf(v, 0.0, 1.0)
	apply(bus)


static func set_muted(m: bool) -> void:
	ensure()
	muted = m
	var mi := AudioServer.get_bus_index(MASTER)
	if mi >= 0:
		AudioServer.set_bus_mute(mi, m)


## How shut-in the ambience sounds: 0 outdoors, 1 behind walls.
static func set_muffle(amount: float) -> void:
	var bi := AudioServer.get_bus_index(AMBIENCE)
	if bi < 0 or AudioServer.get_bus_effect_count(bi) < 1:
		return
	var lp := AudioServer.get_bus_effect(bi, 0) as AudioEffectLowPassFilter
	if lp != null:
		lp.cutoff_hz = lerpf(20000.0, 1400.0, clampf(amount, 0.0, 1.0))
