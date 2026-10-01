class_name AudioLib
## Loads the synthesised sounds in res://assets/audio/ (see _tools/gen_audio.py).
## Streams are cached; a missing file is a silent no-op, never an error, so the
## game plays the same with a half-generated set.

const DIR := "res://assets/audio/"

static var _cache: Dictionary = {}
static var _missing: Dictionary = {}


static func get_stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	if _missing.has(sound):
		return null
	var path := DIR + sound + ".wav"
	if not ResourceLoader.exists(path):
		_missing[sound] = true
		return null
	var s := load(path) as AudioStream
	if s == null:
		_missing[sound] = true
		return null
	_cache[sound] = s
	return s


## Same, but set to loop end to end (imported WAVs arrive with looping off).
static func get_loop(sound: String) -> AudioStream:
	var s := get_stream(sound)
	var w := s as AudioStreamWAV
	if w != null and w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = maxi(int(w.get_length() * float(w.mix_rate)) - 1, 1)
	return s


## A random variant: variant("hen", 3) -> hen_1 .. hen_3.
static func variant(prefix: String, count: int) -> String:
	return "%s_%d" % [prefix, 1 + randi() % maxi(count, 1)]


## Asks the engine to start decoding on a worker thread, so the first birdsong
## or pluck does not stall a frame.
static func warm(names: Array) -> void:
	for n in names:
		var p := DIR + str(n) + ".wav"
		if ResourceLoader.exists(p) and not _cache.has(n):
			ResourceLoader.load_threaded_request(p)
