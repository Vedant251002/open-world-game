extends SceneTree
## Which of these were EVER read as a correction?
##
## Run against the current critique.gd, then against the version in git HEAD,
## so the comparison is measured rather than assumed. The point is to find out
## whether "bigger" and "much larger please" ever worked, or whether my test
## was asserting a behaviour the game never had.
##
##   godot4 --headless --path . --script _tools/critique_baseline.gd

const CASES := [
	"you are useless and I hate you",
	"useless",
	"that is bigot nonsense",
	"I hate smallpox",
	"fireworks ruined the field",
	"he is a caretaker",
	"no, smaller",
	"make it smaller",
	"it is too small",
	"too cramped",
	"a bit more modest",
	"bigger",
	"much larger please",
	"that is a big room",
	"the shed is too little",
	"bigger please",
	"no, bigger",
	"I want a bigger room",
	"make it bigger",
]


func _init() -> void:
	print("=== current build ===")
	for s: String in CASES:
		var d := Critique.read(s)
		print("  %-32s %s" % [s, ("%s=%s" % [d.get("about"), d.get("value")]) if not d.is_empty() else "-"])
	quit(0)
