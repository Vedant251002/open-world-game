extends SceneTree
## Does the deterministic plan library build what it is asked to build?
##
## The question the whole task matrix stalled on: can a builder actually
## build? That does not need a model. --offline drives the plan library, and
## the library is what decides which archetype a sentence names and what it
## comes out as. A plan that comes back empty here is a build order that can
## never work, whatever the gateway does.
##
## Run with:
##   godot4 --headless --path . --script _tools/plan_probe.gd
##
## Prints one line per sentence: the archetype guessed, the steps, and
## whether the plan is usable. No game, no world, no model.

var FAILS := 0
var CASES := [
	"build a small hut with a thatch roof",
	"put up a workshop, timber framed, with a big door",
	"build me a bakery facing the square",
	"build a bakery",
	"put up a house",
	"raise a tavern",
	"build a store",
	"build something useful",
	"build a windmill",
	"build a cottage by the well",
]


func _init() -> void:
	print("=== ArchetypeLibrary.fallback(): the offline build path ===\n")
	print("land_plan() is NOT this. It handles pens, stores and fields only and")
	print("returns {} for a named building on purpose -- _names_a_building() is")
	print("true, and a real building comes from the model. The offline path is")
	print("fallback(), which is what llm.gd:836 calls. The first version of this")
	print("probe asked land_plan() and reported 0/10 for a reason that had")
	print("nothing to do with building.\n")
	# A real Plot: _fit_to_plot() reads plot.size_m() and plot.street_dir, so
	# passing null threw at archetype_library.gd:984 and every case came back
	# empty. The fields are size_v (voxels) and street_dir (Vector3i), not
	# width/depth -- read from plot.gd rather than guessed, which is the third
	# wrong turn this probe took and the reason for the comment.
	var plot := Plot.new()
	plot.id = 0
	plot.size_v = Vector2i(80, 80)
	plot.street_dir = Vector3i(1, 0, 0)
	plot.ground_y = 0
	for say: String in CASES:
		var mem := WorkerMemory.new()
		mem.worker_id = "tobias"
		mem.display_name = "Tobias"
		var plan: Dictionary = ArchetypeLibrary.fallback(say, mem, plot, 1)
		# The plan is under "spec", not "steps". land_plan() -- the function
		# the first two versions of this probe called -- returns steps[], which
		# is why every case read as 0 steps and looked like building was
		# completely broken. fallback() returns a spec dict and the dispatcher
		# turns it into a build. Fourth wrong turn, same cause each time:
		# guessing the shape of the return value instead of reading it.
		var spec: Dictionary = plan.get("spec", {})
		var mods: Array = spec.get("modules", [])
		var kind := str(plan.get("kind", ""))
		# An empty plan is not automatically wrong: "build something useful"
		# names no building, and llm.gd:837 refuses to guess a job. What is
		# wrong is the silence -- fallback() returns {} and the dispatcher
		# substitutes the line "I cannot think that through just now, and I
		# will not guess at a job", so the player does hear something. Recorded
		# as a refusal here because that is what it is.
		var spoke := not str(plan.get("worker_line", "")).is_empty() or kind == "talk"
		var ok := not spec.is_empty() or kind == "talk"
		if not ok:
			FAILS += 1
		var verdict := "plan"
		if spec.is_empty():
			verdict = "refused" if spoke else "SILENT"
		print("  [%s] %-42s %-8s rooms=%-2d %sx%s x%dst" % [
			"ok  " if ok else "BAD ", say, verdict,
			mods.size(),
			str(spec.get("footprint", ["-"])[0]) if not spec.is_empty() else "-",
			str(spec.get("footprint", ["-", "-"])[1]) if not spec.is_empty() else "-",
			int(spec.get("stories", 1))])
		if not spec.is_empty():
			# materials is a Dictionary of role -> name, not a list. Reading it
			# as an Array threw on the first case, which is the fifth thing this
			# probe got wrong by assuming a shape. Read the declaration next
			# time.
			var mats: Variant = spec.get("materials", {})
			var mat_txt := "-"
			if mats is Dictionary:
				# Built as a real Array first: ", ".join() takes an array, not
				# a generator expression, and the one-liner form is a parse
				# error rather than a runtime one.
				var pairs: Array[String] = []
				for k: String in (mats as Dictionary):
					pairs.append("%s=%s" % [k, mats[k]])
				mat_txt = ", ".join(pairs)
			elif mats is Array:
				mat_txt = ", ".join(mats)
			print("          %s" % mat_txt)
			if not mods.is_empty():
				print("          first room: %s" % JSON.stringify(mods[0]).substr(0, 60))
		var line := str(plan.get("worker_line", ""))
		if line != "":
			print("          says: %s" % line)
		for a: String in plan.get("assumptions", []):
			print("          assumed: %s" % a)
	print("\n%d of %d produced a usable plan" % [CASES.size() - FAILS, CASES.size()])
	quit(0 if FAILS == 0 else 1)
