extends RefCounted
class_name WorkerMemory
## Per-worker memory, exactly the shape in game-design-doc.md §4.2.
##
## traits are static and define the character. disposition drifts with how you
## treat them. learned_preferences is the engine of progression: it accumulates
## as you correct things, and it is what lets a one-sentence instruction work by
## tier 4. episodic keeps the last twenty events and compresses the rest.
##
## Budget is about 600 tokens per worker per prompt, which is nothing.

const MAX_PREFERENCES := 15
## Forty rather than twenty. The episodic log used to be flavour for the
## planning prompt; now it is also what a worker answers from when you ask
## "what did I tell you to build", and twenty entries is a morning's work.
const MAX_EPISODIC := 40
const PREFERENCE_DECAY := 0.985      ## per in-game day

var worker_id := ""
var display_name := ""
var traits := {
	"speed": 0.5,
	"literalism": 0.5,
	"initiative": 0.5,
	"question_threshold": 0.5,
	"criticism_sensitivity": 0.5,
}
var disposition := {
	"trust_in_player": 0.5,
	"morale": 0.7,
	"confidence": 0.5,
}
var learned_preferences: Array[Dictionary] = []
var episodic: Array[Dictionary] = []
var open_questions: Array[Dictionary] = []
var skills := {"carpentry": 0, "masonry": 0, "machining": 0, "piloting": 0}

var _next_event := 1


static func make(id: String, name: String, t: Dictionary, d: Dictionary,
		sk: Dictionary) -> WorkerMemory:
	var m := WorkerMemory.new()
	m.worker_id = id
	m.display_name = name
	m.traits = t.duplicate()
	m.disposition = d.duplicate()
	m.skills = sk.duplicate()
	return m


# -------------------------------------------------------------- disposition

func nudge(key: String, amount: float) -> void:
	disposition[key] = clampf(float(disposition.get(key, 0.5)) + amount, 0.0, 1.0)


## How far the worker will run with an ambiguous instruction.
##
## Note the inversion that makes the whole game work (§4.3): high trust means
## MORE interpretation, not less. A worker who trusts you fills gaps
## confidently, which is wonderful once they know your preferences and a
## catastrophe before they do. Misinterpretation therefore peaks in the
## mid-game and falls away on its own as preferences accumulate.
func interpretation_looseness(preference_coverage: float) -> float:
	var t: float = traits["literalism"]
	var c: float = disposition["confidence"]
	var trust: float = disposition["trust_in_player"]
	var base := (1.0 - t) * 0.45 + c * 0.35 + trust * 0.30
	# Good coverage means the gaps get filled correctly, so looseness is safe.
	return clampf(base * (1.0 - preference_coverage * 0.45), 0.0, 1.0)


## Whether this worker stops and asks rather than guessing.
##
## question_threshold is the bar an instruction has to be murkier than before
## they will interrupt you, so a LOW threshold is the worker who asks about
## everything. That is also how Prompt._character() reads it when it describes
## the worker to the model — and the two were inverted with respect to each
## other, so Mira's prompt told her she asks a clarifying question before nearly
## every job, which is Tobias's entire personality and the opposite of hers.
##
## Trust and confidence both raise the bar, which is the inversion the design
## turns on (§4.3): a worker who trusts you fills the gap rather than asking
## about it, and filling gaps is exactly where the misinterpretation lives.
func will_ask(ambiguity: float) -> bool:
	var bar: float = traits["question_threshold"]
	bar *= 0.75 + float(disposition["trust_in_player"]) * 0.5
	bar *= 0.80 + float(disposition["confidence"]) * 0.4
	return ambiguity > clampf(bar, 0.02, 0.98)


## Work rate multiplier. Low morale is visible in the pace, per §4.3.
func work_rate() -> float:
	var s: float = traits["speed"]
	var morale: float = disposition["morale"]
	return (0.55 + s * 0.95) * (0.6 + morale * 0.55)


## Optional modules get dropped when a worker is unhappy with you.
func drops_optional() -> bool:
	return float(disposition["morale"]) < 0.35


func may_refuse() -> bool:
	return float(disposition["morale"]) < 0.18 and float(disposition["trust_in_player"]) < 0.3


# --------------------------------------------------------------- preferences

func learn(text: String, weight: float, source_event: int) -> void:
	for p in learned_preferences:
		if p["text"] == text:
			p["weight"] = clampf(float(p["weight"]) + weight * 0.6, 0.0, 1.0)
			p["source_event"] = source_event
			return
	learned_preferences.append({
		"text": text, "weight": clampf(weight, 0.0, 1.0), "source_event": source_event,
	})
	_trim_preferences()


## A preference about one field of a plan — the roof material, the size, a
## room. Kept as a sentence for the prompt and as (about, value) for the
## offline planner, which cannot read sentences. A new value for the same
## field replaces the old one: somebody who asked for thatch and then for
## tile wants tile, not a worker torn between them.
func learn_about(about: String, value: String, text: String, weight: float,
		source_event: int) -> void:
	for p in learned_preferences:
		if str(p.get("about", "")) == about:
			if str(p.get("value", "")) == value:
				p["weight"] = clampf(float(p["weight"]) + weight * 0.6, 0.0, 1.0)
			else:
				p["value"] = value
				p["text"] = text
				p["weight"] = clampf(weight, 0.0, 1.0)
			p["source_event"] = source_event
			return
	learned_preferences.append({
		"text": text, "weight": clampf(weight, 0.0, 1.0), "source_event": source_event,
		"about": about, "value": value,
	})
	_trim_preferences()


## The current wish for one field, or "" if there is none worth acting on.
func wants(about: String, at_least: float = 0.4) -> String:
	for p in learned_preferences:
		if str(p.get("about", "")) == about and float(p["weight"]) >= at_least:
			return str(p.get("value", ""))
	return ""


func _trim_preferences() -> void:
	if learned_preferences.size() <= MAX_PREFERENCES:
		return
	learned_preferences.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
	learned_preferences = learned_preferences.slice(0, MAX_PREFERENCES)


func decay(days: float) -> void:
	var f := pow(PREFERENCE_DECAY, days)
	var kept: Array[Dictionary] = []
	for p in learned_preferences:
		p["weight"] = float(p["weight"]) * f
		if float(p["weight"]) > 0.08:
			kept.append(p)
	learned_preferences = kept


## How much of an instruction's ambiguity this worker can fill from what they
## already know about you. Feeds interpretation_looseness.
func preference_coverage(topics: PackedStringArray) -> float:
	if topics.is_empty():
		return 0.0
	var hit := 0.0
	for t: String in topics:
		for p in learned_preferences:
			if str(p["text"]).findn(t) >= 0:
				hit += float(p["weight"])
				break
	return clampf(hit / float(topics.size()), 0.0, 1.0)


# ------------------------------------------------------------------ episodic

## One thing that happened, in the worker's own words, plus whatever facts
## about it a later question might turn on.
##
## `about` is where the structure lives: "kind" says what sort of event this is
## (order, plan, done, errand, asked, told), and the rest is whatever that kind
## needs — the instruction as the player said it, the street, the archetype,
## the id of the order a completion closes. The summary stays as prose because
## the prompt reads that; the facts are there so Answers does not have to parse
## prose to find out where the bakery went.
func remember(day: int, summary: String, valence: float,
		about: Dictionary = {}) -> int:
	var id := _next_event
	_next_event += 1
	var entry := {"id": id, "day": day, "summary": summary, "valence": valence}
	for k: Variant in about:
		entry[k] = about[k]
	episodic.append(entry)
	if episodic.size() > MAX_EPISODIC:
		episodic = episodic.slice(episodic.size() - MAX_EPISODIC)
	return id


## Every order the player gave this worker, oldest first.
func orders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in episodic:
		if str(e.get("kind", "")) == "order":
			out.append(e)
	return out


## The entries of one kind, most recent last.
func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in episodic:
		if str(e.get("kind", "")) == kind:
			out.append(e)
	return out


## What became of an order: the completion that names it, or nothing yet.
func outcome_of(order_id: int) -> Dictionary:
	for e: Dictionary in episodic:
		if int(e.get("order", -1)) == order_id and str(e.get("kind", "")) != "order":
			return e
	return {}


func recent(n: int) -> Array[Dictionary]:
	if episodic.size() <= n:
		return episodic.duplicate()
	return episodic.slice(episodic.size() - n)


func ask(day: int, text: String) -> void:
	open_questions.append({"day": day, "text": text})
	if open_questions.size() > 5:
		open_questions.pop_front()


func answer_question(index: int) -> void:
	if index >= 0 and index < open_questions.size():
		open_questions.remove_at(index)


func practise(skill: String, amount: float = 1.0) -> void:
	if not skills.has(skill):
		return
	skills[skill] = mini(int(skills[skill]) + int(amount), 5)


## A worker with masonry 0 produces visibly rougher stonework. The engine
## degrades the generated output, never the spec — the model has no idea this
## is happening, which is exactly right.
func craft_quality(skill: String) -> float:
	return clampf(0.45 + float(skills.get(skill, 0)) * 0.14, 0.0, 1.0)


# --------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	return {
		"worker_id": worker_id,
		"display_name": display_name,
		"traits": traits,
		"disposition": disposition,
		"learned_preferences": learned_preferences,
		"episodic": episodic,
		"open_questions": open_questions,
		"skills": skills,
		"next_event": _next_event,
	}


func from_dict(d: Dictionary) -> void:
	worker_id = str(d.get("worker_id", worker_id))
	display_name = str(d.get("display_name", display_name))
	traits = d.get("traits", traits)
	disposition = d.get("disposition", disposition)
	skills = d.get("skills", skills)
	_next_event = int(d.get("next_event", 1))

	learned_preferences.clear()
	for p: Variant in d.get("learned_preferences", []):
		if p is Dictionary:
			learned_preferences.append(p)
	episodic.clear()
	for e: Variant in d.get("episodic", []):
		if e is Dictionary:
			episodic.append(e)
	open_questions.clear()
	for q: Variant in d.get("open_questions", []):
		if q is Dictionary:
			open_questions.append(q)
