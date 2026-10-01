extends Node
class_name MusicConductor
## Generative background music that mostly is not there.
##
## Pre-rendered voices (plucked string, breathy flute, three slow pads - all in
## D major pentatonic, so any note sits well over any pad) are played by a
## small composer that wanders the scale:
##
##   silence 55-120 s  ->  a piece of 50-85 s  ->  silence ...
##
## Within a piece a pad swells in and a lead voice plays short phrases - a
## random walk with a bias to resolve on D, A or the octave - separated by
## rests. The mood follows the hour:
##
##   morning (5-10)   bright flute over a D pad, brisk
##   day     (10-17.5) plucked melody, a bass note under each phrase
##   evening (17.5-21) slow flute over the warmer G pad
##   night   (21-5)   a few low plucks over the dark pad, very sparse and quiet
##
## It holds its tongue in storms and while raiders are about.

const PL := [50, 54, 57, 59, 62, 64, 66, 69, 71, 74, 76, 78]    ## pluck_<midi>
const FL := [69, 71, 74, 76, 78, 81]                            ## flute_<midi>
const PAD_LEVEL := 0.32

var dir: AudioDirector

var _state := "wait"
var _wait := 14.0
var _left := 0.0
var _mood := "day"
var _beat := 0.5
var _phrase: Array = []
var _phrase_i := 0
var _note_wait := 0.0
var _idx := 6
var _pads: Dictionary = {}                 ## name -> {p, cur, tgt}
var _pad_name := ""
var _pluck_pool: Array[AudioStreamPlayer] = []
var _flute_pool: Array[AudioStreamPlayer] = []
var _first := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_playing() -> bool:
	return _state == "play"


func mood_for(h: float) -> String:
	if h >= 5.0 and h < 10.0:
		return "morning"
	if h >= 10.0 and h < 17.5:
		return "day"
	if h >= 17.5 and h < 21.0:
		return "evening"
	return "night"


func _can_play() -> bool:
	if dir == null or not dir.unlocked or dir.is_paused():
		return false
	if dir.wx_state == "storm":
		return false
	if dir.warfare != null and not dir.warfare.raiders.is_empty():
		return false
	return true


func _process(delta: float) -> void:
	if dir == null or not dir.unlocked:
		return
	_fade_pads(delta)
	if _state == "wait":
		if not _can_play():
			return
		_wait -= delta
		if _wait <= 0.0:
			_begin()
		return
	# playing
	if not _can_play():
		_end(true)
		return
	_left -= delta
	if _left <= 0.0:
		_end(false)
		return
	_note_wait -= delta
	if _note_wait <= 0.0:
		_next_note()


func _begin() -> void:
	_mood = mood_for(dir.hour)
	_state = "play"
	_left = randf_range(50.0, 85.0)
	_phrase = []
	match _mood:
		"morning":
			_beat = 0.58
			_idx = 2
			_pad_name = "pad_day"
		"day":
			_beat = 0.5
			_idx = 6
			_pad_name = "pad_day"
		"evening":
			_beat = 0.8
			_idx = 2
			_pad_name = "pad_eve"
		_:
			_beat = 0.95
			_idx = 4
			_pad_name = "pad_night"
	var level: float = PAD_LEVEL * {"morning": 0.8, "day": 0.7, "evening": 0.95, "night": 0.7}[_mood]
	_set_pad(_pad_name, level)
	_note_wait = randf_range(4.0, 7.0)         # let the pad arrive first


func _end(quick: bool) -> void:
	_state = "wait"
	for n: String in _pads:
		_pads[n]["tgt"] = 0.0
		_pads[n]["rate"] = 0.9 if quick else 0.3
	var gap := randf_range(55.0, 120.0)
	if dir.hour >= 21.0 or dir.hour < 5.0:
		gap *= 1.4
	if _first:
		_first = false
	_wait = gap


# ---------------------------------------------------------------------- pad

func _set_pad(name: String, level: float) -> void:
	var e: Dictionary = _pads.get(name, {})
	if e.is_empty():
		var s := AudioLib.get_loop(name)
		if s == null:
			return
		var p := AudioStreamPlayer.new()
		p.bus = AudioBuses.MUSIC
		p.stream = s
		add_child(p)
		e = {"p": p, "cur": 0.0, "tgt": 0.0, "rate": 0.3}
		_pads[name] = e
	e["tgt"] = level
	e["rate"] = 0.35


func _fade_pads(delta: float) -> void:
	for n: String in _pads:
		var e: Dictionary = _pads[n]
		var cur: float = e["cur"]
		cur += (float(e["tgt"]) - cur) * (1.0 - exp(-delta * float(e["rate"])))
		e["cur"] = cur
		var p: AudioStreamPlayer = e["p"]
		if cur < 0.003 and float(e["tgt"]) < 0.003:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play()
		p.volume_db = linear_to_db(cur)


# ------------------------------------------------------------------- notes

func _voice(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	if pool.size() >= 6:
		return null
	var np := AudioStreamPlayer.new()
	np.bus = AudioBuses.MUSIC
	add_child(np)
	pool.append(np)
	return np


func _play_note(kind: String, midi: int, db: float) -> void:
	var pool := _pluck_pool if kind == "pluck" else _flute_pool
	var s := AudioLib.get_stream("%s_%d" % [kind, midi])
	if s == null:
		return
	var p := _voice(pool)
	if p == null:
		return
	p.stream = s
	p.volume_db = db + randf_range(-2.0, 1.0)
	p.play()


func _next_note() -> void:
	if _phrase.is_empty():
		_phrase = _make_phrase()
		_phrase_i = 0
		# A bass note under the start of a phrase, in the day and evening.
		if _mood == "day" or _mood == "evening":
			var bass: int = [50, 57][randi() % 2]
			_play_note("pluck", bass, -13.0)
	var item: Array = _phrase[_phrase_i]
	_phrase_i += 1
	var humanise := randf_range(0.93, 1.08)
	match _mood:
		"morning", "evening":
			_play_note("flute", FL[clampi(int(item[0]), 0, FL.size() - 1)], -9.0)
			if _mood == "evening" and randf() < 0.3:
				_play_note("pluck", PL[clampi(int(item[0]) + 1, 0, 6)], -15.0)
		"day":
			_play_note("pluck", PL[clampi(int(item[0]), 0, PL.size() - 1)], -11.0)
		_:
			_play_note("pluck", PL[clampi(int(item[0]), 0, PL.size() - 1)], -15.0)
	_note_wait = float(item[1]) * _beat * humanise
	if _phrase_i >= _phrase.size():
		_phrase = []
		var rest := randf_range(4.0, 9.0)
		if _mood == "night":
			rest = randf_range(7.0, 14.0)
		_note_wait += rest * _beat


## A short phrase: [[scale_index, beats], ...]. A random walk with a pull
## towards the resting notes, ending long.
func _make_phrase() -> Array:
	var lo := 0
	var hi := 5
	var rest_notes: Array = [0, 2, 5]
	var count := randi_range(4, 7)
	match _mood:
		"day":
			lo = 4
			hi = 11
			rest_notes = [4, 7, 9]
		"night":
			lo = 1
			hi = 7
			rest_notes = [1, 4, 7]
			count = randi_range(2, 4)
	var out: Array = []
	var steps := [-2, -1, -1, 0, 1, 1, 1, 2]
	var i := clampi(_idx, lo, hi)
	for n in count:
		i = clampi(i + steps[randi() % steps.size()], lo, hi)
		var beats: float = [1.0, 1.0, 1.5, 2.0, 2.0, 3.0][randi() % 6]
		if _mood == "evening" or _mood == "night":
			beats += 1.0
		if n == count - 1:
			var best: int = rest_notes[0]
			for r: int in rest_notes:
				if absi(r - i) < absi(best - i):
					best = r
			i = best
			beats = 3.0 + randf() * 1.5
		out.append([i, beats])
	_idx = i
	return out
