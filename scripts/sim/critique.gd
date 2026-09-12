extends RefCounted
class_name Critique
## What a worker learns from being told they got it wrong.
##
## The design's whole progression rests on this (game-design-doc.md §4.3): a
## one-sentence order works by tier 4 because the crew have learned what you
## mean by then, and they learn it from corrections. WorkerMemory.learn() has
## been there since the start, and the planning prompt has always read what
## was learned; nothing ever called learn(). "No, thatch roof" went to the
## model as a building order and came back as a roof.
##
## A correction is a sentence that is about the last thing they did — "no",
## "I said", "too big", "should have" — or a standing preference: "always",
## "never", "I like", "remember". Either way it names a topic the planner has
## a field for: a material, a roof, a size, a floor count, which way the door
## faces, a room to have or not. That is deliberate. The prompt can use a free
## sentence; the offline planner cannot, and a preference that only works with
## a key is a preference for half the players.
##
## What comes back is one sentence for the prompt ("they want thatch roofs"),
## a structured (about, value) the offline planner applies, a weight, and how
## much it stings — a sensitive worker's morale takes it harder.

const CORRECTING := ["no,", "no ", "nope", "wrong", "not that", "that's not", "that is not",
	"thats not", "i said", "i wanted", "i asked for", "i told you", "should have",
	"should be", "should ", "shouldn't", "should not", "next time", "too ", "not what i",
	"why did you", "you were supposed", "you were meant", "i meant", "i didn't want",
	"i did not want", "i don't want that", "not like that", "that's wrong", "that is wrong"]
const STANDING := ["always", "never", "remember", "i like", "i prefer", "i don't like",
	"i do not like", "i hate", "from now on", "in future", "in the future", "keep them",
	"keep it", "keep the", "make them all", "everything should", "i want all",
	"i don't want", "i do not want", "i want"]
## Words for a size, a floor count, an orientation, and the rooms.
const SMALLER := ["smaller", "too big", "too large", "too tall", "too wide", "too much",
	"less", "tiny", "modest", "small", "little", "cosy", "cozy"]
const BIGGER := ["bigger", "larger", "too small", "too little", "too cramped", "big",
	"large", "grand", "huge", "roomier", "more room", "wider"]
const FACINGS := {
	"face_street": ["face the street", "facing the street", "toward the street", "onto the street", "door on the street"],
	"face_plaza": ["face the plaza", "face the square", "facing the plaza", "toward the plaza", "toward the square", "onto the square"],
	"face_water": ["face the water", "facing the water", "toward the water", "face the river", "face the sea", "onto the water"],
	"face_north": ["face north", "facing north"],
}


## The correction in an instruction, or {} if it is not one.
##
##   {"text": sentence, "about": field, "value": what, "weight": 0..1,
##    "sting": 0..1, "standing": bool}
static func read(instruction: String) -> Dictionary:
	var t := " " + instruction.strip_edges().to_lower().replace(",", " , ") \
		.replace(".", " ").replace("!", " ").replace("?", " ") + " "
	t = t.replace("  ", " ")
	var correcting := _starts_or_has(t, CORRECTING)
	var standing := _has(t, STANDING)
	if not correcting and not standing:
		return {}

	var topic := _topic(t)
	if topic.is_empty():
		# "I want a hut" is an order with an opener in it, not a lesson: only a
		# correction with nothing to learn is worth answering with a question.
		if not correcting:
			return {}
		return {"about": "", "standing": standing, "weight": 0.0, "sting": 0.08}

	var about := str(topic["about"])
	var value := str(topic["value"])
	# "no, thatch roof" is a want and "no thatch" is a do-not-want: the comma
	# is the difference. So a bare "no" counts only when the topic follows it
	# directly, and the strong negators count anywhere.
	var spoken := value.replace("_", " ")
	var negated := _has(t, ["never", "don't", "do not", "without", "hate", "dislike",
		"no more", " not "]) or t.find(" no %s" % spoken) >= 0 \
		or t.find(" no %ss" % spoken) >= 0
	if negated and about in ["walls", "roof_material", "roof", "module"]:
		value = "not:" + value
	if negated and about == "size":
		value = "bigger" if value == "smaller" else "smaller"

	return {
		"text": _sentence(about, value),
		"about": about, "value": value,
		"weight": 0.75 if standing else 0.55,
		"sting": 0.0 if standing and not correcting else 0.12,
		"standing": standing,
	}


## Which field of a plan the words are about, and what they want it to be.
static func _topic(t: String) -> Dictionary:
	# Materials, longest name first so "clay tile" beats "clay".
	var names: Array = []
	for n: String in VoxelTypes.NAMES:
		names.append(n)
	names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for n2: String in names:
		var spoken := n2.replace("_", " ")
		if not _word(t, spoken):
			continue
		var roofish := _has(t, ["roof", "roofs", "roofing", "thatched", "tiled"])
		if n2 in VoxelTypes.SURFACE or (roofish and n2 in VoxelTypes.STRUCTURAL):
			return {"about": "roof_material", "value": n2}
		if n2 in VoxelTypes.STRUCTURAL:
			return {"about": "walls", "value": n2}
	if _word(t, "thatched"):
		return {"about": "roof_material", "value": "thatch"}
	if _word(t, "tiled") or _word(t, "tiles"):
		return {"about": "roof_material", "value": "clay_tile"}
	if _word(t, "wooden") or _word(t, "wood"):
		return {"about": "walls", "value": "timber"}
	if _word(t, "stone"):
		return {"about": "walls", "value": "cobble"}

	for r: String in Vocabulary.ROOFS:
		var spoken2 := r.replace("_", " ")
		if _word(t, spoken2) or _word(t, spoken2 + " roof") or _word(t, spoken2 + " roofs"):
			return {"about": "roof", "value": r}
	if _word(t, "pitched") or _word(t, "peaked"):
		return {"about": "roof", "value": "gable"}

	for facing: String in FACINGS:
		for phrase: String in FACINGS[facing]:
			if t.find(phrase) >= 0:
				return {"about": "orientation", "value": facing}

	var floors := _floors(t)
	if floors > 0:
		return {"about": "stories", "value": str(floors)}
	if _word(t, "taller") or _has(t, ["more floors", "another floor", "two storey", "two story", "upstairs"]):
		return {"about": "stories", "value": "2"}
	if _word(t, "shorter") or _has(t, ["one floor", "single storey", "single story", "no upstairs", "ground floor only"]):
		return {"about": "stories", "value": "1"}

	var modules: Array = []
	modules.append_array(Vocabulary.TIER_MODULES[1])
	modules.append_array(Vocabulary.TIER_MODULES[2])
	for m: String in modules:
		var spoken3 := m.replace("_", " ")
		if _word(t, spoken3) or _word(t, spoken3 + "s"):
			return {"about": "module", "value": m}
	# A chimney at tier one is a hearth with a flue; the stack is a tier-two
	# module and a hut with one would be refused for it.
	if _word(t, "fireplace") or _word(t, "fire") or _word(t, "chimney") or _word(t, "chimneys"):
		return {"about": "module", "value": "hearth"}
	if _word(t, "windows") or _word(t, "window"):
		return {"about": "module", "value": "window_bank"}
	if _word(t, "bedroom") or _word(t, "bed"):
		return {"about": "module", "value": "bed_area"}
	if _word(t, "shop") or _word(t, "counter"):
		return {"about": "module", "value": "counter"}

	if _has(t, SMALLER):
		return {"about": "size", "value": "smaller"}
	if _has(t, BIGGER):
		return {"about": "size", "value": "bigger"}
	return {}


## The sentence the model reads, in the worker's own second-hand voice.
static func _sentence(about: String, value: String) -> String:
	var neg := value.begins_with("not:")
	var v := value.trim_prefix("not:").replace("_", " ")
	match about:
		"roof_material":
			return "they do not want %s roofs" % v if neg else "they want %s roofs" % v
		"walls":
			return "they do not want %s walls" % v if neg else "they want %s walls" % v
		"roof":
			return "they do not like a %s roof" % v if neg else "they like a %s roof" % v
		"orientation":
			var where := v.trim_prefix("face ")
			return "they want the door toward the %s" % where
		"stories":
			return "they want %s floor%s" % [v, "" if v == "1" else "s"]
		"module":
			return "they do not want a %s" % v if neg else "they want a %s" % v
		"size":
			return "they want things %s than I make them" % v
	return "they said: %s" % v


static func _floors(t: String) -> int:
	var words := t.replace("-", " ").split(" ", false)
	for i in words.size():
		var w := String(words[i])
		var n := -1
		if w.is_valid_int():
			n = int(w)
		elif ArchetypeLibrary.NUMBER_WORDS.has(w):
			n = int(ArchetypeLibrary.NUMBER_WORDS[w])
		if n > 0 and i + 1 < words.size():
			var next := String(words[i + 1])
			if next.begins_with("floor") or next.begins_with("store") or next.begins_with("story"):
				return clampi(n, 1, 6)
	return 0


static func _word(t: String, w: String) -> bool:
	return t.find(" %s " % w) >= 0


static func _has(t: String, words: Array) -> bool:
	for w: String in words:
		if t.find(w) >= 0:
			return true
	return false


static func _starts_or_has(t: String, words: Array) -> bool:
	var s := t.strip_edges()
	for w: String in words:
		if s.begins_with(w.strip_edges()) or t.find(" " + w) >= 0:
			return true
	return false


## What a worker says on being corrected. The sensitive take it hard; the
## thick-skinned barely notice; everybody remembers.
static func reaction(mem: WorkerMemory, learned: Dictionary) -> String:
	var sens := float(mem.traits.get("criticism_sensitivity", 0.5))
	var standing := bool(learned.get("standing", false))
	var text := str(learned.get("text", ""))
	if standing:
		if sens > 0.7:
			return "I will remember that — %s." % text
		return "Noted: %s." % text
	if sens > 0.7:
		return "Sorry. I will remember: %s."% text
	if sens < 0.3:
		return "Fair enough. %s, then." % text.capitalize()
	return "Right — %s. I have got it now." % text
