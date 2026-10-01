extends RefCounted
class_name Personality
## Who somebody is changes what they make.
##
## WorkerMemory.traits already shaped how a worker talks and how quickly they
## walk. This makes it show in the work itself, deterministically, so the same
## person given the same order builds the same thing every time:
##
##   proud       adds a flourish nobody asked for: a wider porch or an extra window
##   careless    cuts a corner: a metre off the footprint and the last optional
##               room left out. They will admit it if you ask (see admission()).
##   meticulous  slower but tidier: even-width walls, a proper footing.
##
## Everything here is pure on its inputs and offline. Dispatcher calls apply()
## on a plan's build specs and re-validates; if the changed spec does not pass
## the validator the original is used untouched, so a quirk can never turn an
## acceptable order into a refused one.

const PROUD := "proud"
const CARELESS := "careless"
const METICULOUS := "meticulous"

const ADMIT_WORDS := ["corner", "shortcut", "short cut", "rush", "sloppy", "rough",
	"skimp", "cheat", "skip", "missing", "left out", "leave out", "properly",
	"honest", "smaller than", "do it right", "did you cut", "cut any"]


## The dominant temperament, or "" for an even-keeled sort. Order matters: a
## bold hand is proud before it is anything else.
static func kind_of(mem: WorkerMemory) -> String:
	var t := mem.traits
	var speed := float(t.get("speed", 0.5))
	var initiative := float(t.get("initiative", 0.5))
	if initiative >= 0.75:
		return PROUD
	if speed <= 0.35:
		return METICULOUS
	if speed >= 0.8:
		return CARELESS
	return ""


## Work-rate multiplier for temperament (Relationships.work_factor is the other
## half). A meticulous hand takes their time.
static func pace(mem: WorkerMemory) -> float:
	return 0.9 if kind_of(mem) == METICULOUS else 1.0


## Short words for the card: how they would describe themselves to a stranger.
static func chips(mem: WorkerMemory) -> Array[String]:
	var t := mem.traits
	var out: Array[String] = []
	match kind_of(mem):
		PROUD: out.append("Proud")
		CARELESS: out.append("Hasty")
		METICULOUS: out.append("Meticulous")
	var sens := float(t.get("criticism_sensitivity", 0.5))
	if sens > 0.7:
		out.append("Sensitive")
	elif sens < 0.3:
		out.append("Thick-skinned")
	var lit := float(t.get("literalism", 0.5))
	if lit > 0.8:
		out.append("Literal")
	elif lit < 0.3:
		out.append("Strong-willed")
	var q := float(t.get("question_threshold", 0.5))
	if q < 0.3:
		out.append("Asks first")
	elif q > 0.8:
		out.append("Gets on with it")
	if out.size() > 4:
		out.resize(4)
	if out.is_empty():
		out.append("Even-tempered")
	return out


## One sentence on how that shows in their work.
static func describe(mem: WorkerMemory) -> String:
	match kind_of(mem):
		PROUD: return "Takes pride in the work and tends to add a flourish nobody asked for."
		CARELESS: return "Quick off the mark, and sometimes cuts a corner to be done."
		METICULOUS: return "Slow and careful. Squares every wall and checks it twice."
	return "Steady, takes orders as they come."


# -------------------------------------------------------------------- applying

## A building spec as this person would really make it.
##   {"spec": Dictionary, "notes": Array[String], "quirk": String, "detail": String}
## The input is never modified. With no temperament, or nothing to change, the
## spec comes back as it went in with no notes (a meticulous worker's pace note
## is added regardless, since that is about time and not shape).
static func apply(spec: Dictionary, mem: WorkerMemory) -> Dictionary:
	var out := {"spec": spec, "notes": [] as Array[String], "quirk": "", "detail": ""}
	if str(spec.get("kind", "building")) != "building" or not (spec.get("footprint", null) is Array):
		return out
	var kind := kind_of(mem)
	if kind == "":
		return out
	var s: Dictionary = spec.duplicate(true)
	var name := mem.display_name
	var notes: Array[String] = []
	var detail := ""
	match kind:
		PROUD:
			detail = _flourish(s, mem)
			if detail != "":
				notes.append("%s took pride in it and gave it %s nobody asked for." % [name, detail])
		CARELESS:
			detail = _cut_corner(s)
			if detail != "":
				notes.append("%s was in a hurry: %s. They will say so if you ask." % [name, detail])
		METICULOUS:
			detail = _tidy(s)
			if detail != "":
				notes.append("%s squared it up properly (%s), which takes a little longer." % [name, detail])
			else:
				notes.append("%s works slowly and carefully, so it takes a little longer." % name)
	if detail == "" and notes.is_empty():
		return out
	out["spec"] = s if detail != "" else spec
	out["notes"] = notes
	out["quirk"] = kind if detail != "" else ""
	out["detail"] = detail
	return out


static func _flourish(s: Dictionary, mem: WorkerMemory) -> String:
	var mods: Array = s.get("modules", [])
	var flip := (mem.worker_id + str(s.get("archetype", ""))).hash() % 2 == 0
	var order := ["porch", "window"] if flip else ["window", "porch"]
	for what: String in order:
		if what == "porch":
			for m: Variant in mods:
				var md: Dictionary = m
				if str(md.get("type", "")) == "entrance" and str(md.get("size", "medium")) != "large":
					md["size"] = "large"
					return "a wider porch"
		else:
			for m: Variant in mods:
				var md2: Dictionary = m
				if str(md2.get("type", "")) == "window_bank":
					var sz := str(md2.get("size", "medium"))
					if sz != "large":
						md2["size"] = "medium" if sz == "small" else "large"
						return "an extra window"
					break
			var has := false
			for m: Variant in mods:
				if str((m as Dictionary).get("type", "")) == "window_bank":
					has = true
			if not has:
				mods.append({"type": "window_bank", "wall": "any", "size": "small",
					"priority": "optional"})
				s["modules"] = mods
				return "an extra window"
	return ""


static func _cut_corner(s: Dictionary) -> String:
	var bits: Array[String] = []
	var fp: Array = s["footprint"]
	var w := int(fp[0])
	var d := int(fp[1])
	if w >= 9 and d >= 9:
		s["footprint"] = [w - 1, d - 1]
		bits.append("trimmed it a metre each way")
	var mods: Array = s.get("modules", [])
	if mods.size() > 2:
		for i in range(mods.size() - 1, -1, -1):
			var md: Dictionary = mods[i]
			if str(md.get("priority", "preferred")) == "optional":
				bits.append("left the %s out" % str(md.get("type", "room")).replace("_", " "))
				mods.remove_at(i)
				break
	if bits.is_empty():
		return ""
	return " and ".join(bits)


static func _tidy(s: Dictionary) -> String:
	var bits: Array[String] = []
	var fp: Array = s["footprint"]
	var w := int(fp[0])
	var d := int(fp[1])
	var ew := maxi(8, w - (w % 2))
	var ed := maxi(8, d - (d % 2))
	if ew != w or ed != d:
		s["footprint"] = [ew, ed]
		bits.append("even walls")
	var mats: Dictionary = s.get("materials", {})
	if mats.get("foundation", null) == null:
		mats["foundation"] = "cobble"
		s["materials"] = mats
		bits.append("a proper footing")
	return ", ".join(bits)


# ------------------------------------------------------------------- honesty

## What they say when you ask about corners, or "" if the question is about
## something else or there is nothing to own up to.
static func admission(mem: WorkerMemory, question: String) -> String:
	var q := question.to_lower()
	var asked := false
	for w: String in ADMIT_WORDS:
		if q.find(w) >= 0:
			asked = true
			break
	if not asked:
		return ""
	var quirks := mem.of_kind("quirk")
	for i in range(quirks.size() - 1, -1, -1):
		var e: Dictionary = quirks[i]
		if str(e.get("quirk", "")) == CARELESS:
			return "I will be straight with you: I was in a hurry, so I %s. I can do it again properly if you like." % str(e.get("detail", "cut a corner"))
	return ""


## Put the quirk on the record so it can be owned up to, and so Answers and the
## conversation prompt can see it.
static func note_quirk(mem: WorkerMemory, day: int, quirk: String, detail: String) -> void:
	if quirk == "":
		return
	var summary := ""
	match quirk:
		PROUD: summary = "Added %s of my own to the last job." % detail
		CARELESS: summary = "Cut a corner on the last job: %s." % detail
		METICULOUS: summary = "Took extra care over the last job: %s." % detail
	mem.remember(day, summary, 0.05, {"kind": "quirk", "quirk": quirk, "detail": detail})
