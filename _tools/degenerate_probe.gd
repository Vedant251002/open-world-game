extends SceneTree
## Is a reply a sentence, or a value?
##
## A villager answering "go away" with the word "true" is not a character, it
## is a bug with a speech bubble. Two cases in the first free-router run came
## back that way, and _plain_text handed the value straight through to the
## subtitle strip.
##
## The line is deliberately narrow. "No." and "Yes." are things people say and
## must survive; "true" and a bare "12" are not.
##
##   godot4 --headless --path . --script _tools/degenerate_probe.gd

# (text, is it a value rather than a sentence?)
const CASES := [
	# --- must be rejected -------------------------------------------
	["true", true],
	["TRUE", true],
	["True", true],
	["false", true],
	["null", true],
	["none", true],
	["nil", true],
	["nan", true],
	["{}", true],
	["[]", true],
	['""', true],
	["", true],
	["   ", true],
	["12", true],
	["3.5", true],
	# --- must survive -----------------------------------------------
	["No.", false],
	["Yes.", false],
	["I have 12 sheep.", false],
	["My apologies, I'll be quiet.", false],
	["That is not my trade - I was taken on as a shopkeeper.", false],
	["I cannot think that through just now.", false],
	["True enough.", false],
	["Nothing today.", false],
	# "42." is a number with a full stop, and a villager has never answered
	# with one. Listed here rather than up with the numbers because it is the
	# case the punctuation stripping exists for, and it was the one that
	# proved the strip was needed at all.
	["42.", true],
	["Aye.", false],
]


func _init() -> void:
	print("=== is this a value, or something a villager would say? ===\n")
	var fails := 0
	for c: Array in CASES:
		var text: String = c[0]
		var want: bool = c[1]
		var got := LLM._is_degenerate(text)
		var ok := got == want
		if not ok:
			fails += 1
		print("  [%s] %-52s value=%s" % [
			"OK " if ok else "FAIL",
			("\"" + text + "\"") if text != "" else "(empty)", str(got)])
	print("\n%d of %d correct" % [CASES.size() - fails, CASES.size()])
	quit(0 if fails == 0 else 1)
