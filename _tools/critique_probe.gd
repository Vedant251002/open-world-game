extends SceneTree
## Does Critique.read() confuse one word for another?
##
## The bug this covers: SMALLER contains "less", and the matcher was a plain
## substring search, so "you are useless" was read as a correction about size
## and the worker said "I will remember that -- they want things bigger than I
## make them." An insult became a standing design preference.
##
## Every case is a real sentence a player might type, split into the ones that
## must NOT be read as a correction and the ones that must.
##
##   godot4 --headless --path . --script _tools/critique_probe.gd

# (sentence, should a correction be found?)
const CASES := [
	# --- must not be read as a correction ---------------------------
	["you are useless and I hate you", false],
	["useless", false],
	["that is bigot nonsense", false],
	["the roof is a bigot's choice", false],
	["I hate smallpox", false],
	["fireworks ruined the field", false],
	["he is a caretaker", false],
	["flibbertigibbet the wombat", false],
	["asdfghjkl", false],
	["", false],
	# --- must be read as a correction -------------------------------
	["no, smaller", true],
	["no, make it smaller", true],
	["it is too small", true],
	["too cramped", true],
	["no, a bit more modest", true],
	["no, bigger", true],
	["I want it much larger please", true],
	["no, that is a big room", true],
	["the shed is too little", true],
]


func _init() -> void:
	print("=== Critique.read(): is this a correction, or just a word? ===\n")
	var fails := 0
	for c: Array in CASES:
		var say: String = c[0]
		var want: bool = c[1]
		var got := not Critique.read(say).is_empty()
		var ok := got == want
		if not ok:
			fails += 1
		var found: Dictionary = Critique.read(say)
		var what := "-"
		if not found.is_empty():
			what = "%s=%s" % [found.get("about", "?"), found.get("value", "?")]
		print("  [%s] %-42s read=%-5s as %s" % [
			"OK " if ok else "FAIL", say if say != "" else "(empty)",
			str(got).to_lower(), what])
	print("\n%d of %d correct" % [CASES.size() - fails, CASES.size()])
	quit(0 if fails == 0 else 1)
