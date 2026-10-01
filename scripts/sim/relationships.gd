extends RefCounted
class_name Relationships
## How each villager feels about you, from what you have actually done.
##
## Two numbers per person. trust is the existing disposition["trust_in_player"]
## (it already steers how loosely they read an order). affection is new, -1..1,
## and lives in WorkerMemory.relationship so it is saved with the person. The
## standing shown on the villager card blends the two:
##
##   Resentful < Wary < Stranger < Acquaintance < Friend < Confidant
##
## Everything is a static function over a WorkerMemory, so any system can record
## an event with one line (Relationships.record(mem, "trespass", day)), and the
## tests need no scene. Events are capped per day where they could be farmed
## (praise, gifts), and affection drifts a little toward neutral each morning.
##
## What it changes: the conversation prompt and the offline stock lines get
## warmer or curter (tint), and the work gets faster for a friend and slower,
## with some muttering, for somebody who resents you (work_factor, grumble).

enum Tier { RESENTFUL, WARY, STRANGER, ACQUAINTANCE, FRIEND, CONFIDANT }
const LABELS := ["Resentful", "Wary", "Stranger", "Acquaintance", "Friend", "Confidant"]
## Lower bound of standing for each tier from Wary upwards.
const BOUNDS := [-0.5, -0.15, 0.12, 0.30, 0.55]

## kind -> {aff, trust, cap (per day, 0 = none), say (their memory of it), val}
const EVENTS := {
	"praise": {"aff": 0.06, "trust": 0.02, "cap": 3, "val": 0.5,
		"say": "You were kind about my work."},
	"insult": {"aff": -0.14, "trust": -0.05, "cap": 0, "val": -0.7,
		"say": "You said something cruel to me."},
	"scolded": {"aff": -0.03, "trust": 0.0, "cap": 3, "val": 0.0, "say": ""},
	"order_done": {"aff": 0.04, "trust": 0.01, "cap": 4, "val": 0.0, "say": ""},
	"request_done": {"aff": 0.09, "trust": 0.03, "cap": 3, "val": 0.6,
		"say": "You saw to what I asked of you."},
	"gift": {"aff": 0.12, "trust": 0.03, "cap": 1, "val": 0.6,
		"say": "You gave me something, and meant it kindly."},
	"dismissed": {"aff": -0.20, "trust": -0.10, "cap": 0, "val": -0.5,
		"say": "You let me go."},
	"trespass": {"aff": -0.10, "trust": 0.0, "cap": 0, "val": 0.0, "say": ""},
}

const PRAISE := ["well done", "good job", "great job", "nice work", "good work",
	"great work", "excellent", "brilliant", "wonderful", "lovely", "beautiful",
	"thank you", "thanks", "love it", "love what", "impressive", "proud of you",
	"best builder", "you're the best", "you are the best", "perfect", "fantastic",
	"amazing", "splendid", "good on you", "bravo", "well built", "nicely done"]
const NOT_PRAISE := ["not good", "not great", "not very good", "isn't good", "wasn't good",
	"not a good", "no thanks", "not perfect", "not impressive", "not nice"]
const INSULT := ["idiot", "stupid", "useless", "lazy", "worthless", "incompetent",
	"fool", "hopeless", "pathetic", "moron", "shut up", "i hate you", "you suck",
	"you're terrible", "you are terrible", "dunce", "the worst", "good for nothing",
	"waste of space", "clumsy oaf"]
const GIFT := ["a gift", "present for you", "this is for you", "gift for you"]

## Set by bind(): called as (memory, old_tier, new_tier) when the label changes.
static var tier_listener: Callable = Callable()


# ---------------------------------------------------------------- reading it

static func affection(mem: WorkerMemory) -> float:
	return clampf(float(mem.relationship.get("affection", 0.0)), -1.0, 1.0)


## -1..1: how they stand with you, blending affection with trust.
static func standing(mem: WorkerMemory) -> float:
	var trust := float(mem.disposition.get("trust_in_player", 0.5))
	return clampf(0.65 * affection(mem) + 0.35 * (trust * 2.0 - 1.0), -1.0, 1.0)


static func tier(mem: WorkerMemory) -> int:
	var s := standing(mem)
	var t := 0
	for b: float in BOUNDS:
		if s >= b:
			t += 1
	return t


static func label(mem: WorkerMemory) -> String:
	return LABELS[tier(mem)]


## 0..1 for a meter, 0.5 neutral.
static func meter(mem: WorkerMemory) -> float:
	return (standing(mem) + 1.0) * 0.5


static func is_resentful(mem: WorkerMemory) -> bool:
	return tier(mem) == Tier.RESENTFUL


# --------------------------------------------------------------- writing it

## Something happened between the player and this person. Returns
## {"applied": bool, "delta": float} (applied is false when a daily cap held it
## back). opts: "again" (bool, a repeat offence hits harder), "quiet" (do not
## write an episodic memory, because the caller already did), "no_trust" (the
## caller already nudged trust).
static func record(mem: WorkerMemory, kind: String, day: int, opts: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = EVENTS.get(kind, {})
	if ev.is_empty():
		return {"applied": false, "delta": 0.0}
	var rel := mem.relationship
	var caps: Dictionary = rel.get("caps", {})
	if int(caps.get("day", -1)) != day:
		caps = {"day": day}
	var cap := int(ev.get("cap", 0))
	if cap > 0 and int(caps.get(kind, 0)) >= cap:
		rel["caps"] = caps
		mem.relationship = rel
		return {"applied": false, "delta": 0.0}
	caps[kind] = int(caps.get(kind, 0)) + 1

	var before := tier(mem)
	var d := float(ev["aff"])
	var sens := float(mem.traits.get("criticism_sensitivity", 0.5))
	if d < 0.0:
		d *= 0.6 + sens * 0.8              # thin skin remembers longer
		if bool(opts.get("again", false)):
			d *= 1.7
	rel["affection"] = clampf(affection(mem) + d, -1.0, 1.0)
	rel["caps"] = caps
	var counts: Dictionary = rel.get("counts", {})
	counts[kind] = int(counts.get(kind, 0)) + 1
	rel["counts"] = counts
	rel["last"] = kind
	mem.relationship = rel

	if not bool(opts.get("no_trust", false)):
		mem.nudge("trust_in_player", float(ev["trust"]))
	if kind == "insult":
		mem.nudge("morale", -0.1 * (0.4 + sens))
	elif kind == "praise":
		mem.nudge("morale", 0.04)
	var say := str(ev.get("say", ""))
	if say != "" and not bool(opts.get("quiet", false)):
		mem.remember(day, say, float(ev["val"]), {"kind": "rel", "rel": kind})

	var after := tier(mem)
	if after != before and tier_listener.is_valid():
		tier_listener.call(mem, before, after)
	return {"applied": true, "delta": d}


## Each morning: strong feelings cool a little, and a grudge is not forever.
static func drift(mem: WorkerMemory) -> void:
	if not mem.relationship.has("affection"):
		return
	mem.relationship["affection"] = affection(mem) * 0.97


## What kind of thing a line said to somebody was: "praise", "insult", "gift",
## "scolded" (a correction that stings), or "".
static func classify(text: String) -> String:
	var t := " " + text.to_lower().strip_edges().replace("’", "'") + " "
	for w: String in INSULT:
		if t.find(w) >= 0:
			return "insult"
	for w: String in GIFT:
		if t.find(w) >= 0:
			return "gift"
	var negated := false
	for w: String in NOT_PRAISE:
		if t.find(w) >= 0:
			negated = true
	if not negated:
		for w: String in PRAISE:
			if t.find(w) >= 0:
				return "praise"
	var learned := Critique.read(text)
	if not learned.is_empty() and float(learned.get("sting", 0.0)) > 0.0:
		return "scolded"
	return ""


## A sentence the player typed to this person: file it under what it was.
static func on_said(mem: WorkerMemory, text: String, day: int) -> String:
	var k := classify(text)
	if k != "":
		record(mem, k, day)
	return k


# ------------------------------------------------------------ what it changes

## Work-rate multiplier. 1.0 for the unremarkable middle.
static func work_factor(mem: WorkerMemory) -> float:
	match tier(mem):
		Tier.RESENTFUL: return 0.8
		Tier.WARY: return 0.94
		Tier.FRIEND: return 1.06
		Tier.CONFIDANT: return 1.12
	return 1.0


## A mutter as they start work, or "" (most of the time, and for most people).
## At most once a day each.
static func grumble(mem: WorkerMemory, day: int) -> String:
	var t := tier(mem)
	if t != Tier.RESENTFUL and t != Tier.CONFIDANT:
		return ""
	var rel := mem.relationship
	if int(rel.get("grumbled", -1)) == day:
		return ""
	rel["grumbled"] = day
	mem.relationship = rel
	var pool: Array = []
	if t == Tier.RESENTFUL:
		pool = ["Fine. If I must.", "Hm. Do not expect it to be pretty.",
			"Another one. Of course.", "I will get to it. Eventually."]
	else:
		pool = ["Gladly, for you.", "Leave it with me, I will do it properly.",
			"Nothing I would rather do."]
	return str(pool[(mem.worker_id + str(day)).hash() % pool.size()])


## Stock lines, warmer or curter. Only used when no model is speaking for them
## (Dispatcher.converse falls back to these); with a key the prompt carries the
## relationship instead (see prompt_line).
static func tint(mem: WorkerMemory, line: String, kind: String = "talk") -> String:
	if kind != "talk" or line.length() < 2 or line.length() > 70 or line.ends_with("?"):
		return line
	var base := line.rstrip(".!… ")
	if base == "":
		return line
	match tier(mem):
		Tier.RESENTFUL:
			var curt := ["Hmph.", "Mm.", "What now."]
			return "%s %s" % [curt[(mem.worker_id + line).hash() % curt.size()], line]
		Tier.FRIEND:
			return "%s, friend." % base
		Tier.CONFIDANT:
			var warm := ["%s — and glad of it.", "%s. You know you can always ask me.",
				"%s, my friend."]
			return str(warm[(mem.worker_id + line).hash() % warm.size()]) % base
	return line


## One or two sentences for the model: how they feel, and how to act on it.
static func prompt_line(mem: WorkerMemory) -> String:
	var counts: Dictionary = mem.relationship.get("counts", {})
	var bits: Array[String] = []
	match tier(mem):
		Tier.RESENTFUL:
			bits.append("You resent them. Be curt and cool, hold your grudge, and do not warm to them quickly.")
		Tier.WARY:
			bits.append("You are wary of them: polite at most, and watching what they do.")
		Tier.STRANGER:
			bits.append("They are still more or less a stranger to you.")
		Tier.ACQUAINTANCE:
			bits.append("You know them a little and get on well enough.")
		Tier.FRIEND:
			bits.append("You count them a friend. Be warm and easy with them, and tease a little if it suits you.")
		Tier.CONFIDANT:
			bits.append("You would trust them with anything. Speak openly and fondly, as to a close confidant.")
	if int(counts.get("insult", 0)) > 0 and tier(mem) <= Tier.WARY:
		bits.append("They have insulted you before and you have not forgotten it.")
	if int(counts.get("praise", 0)) >= 3 and tier(mem) >= Tier.ACQUAINTANCE:
		bits.append("They have been generous with praise for your work.")
	if int(counts.get("trespass", 0)) > 0 and tier(mem) <= Tier.STRANGER:
		bits.append("They once walked into your home uninvited.")
	return " ".join(bits)


# ------------------------------------------------------------- the card text

## "What they remember about you", in their own voice. Most striking first.
## Each is {"day": int, "text": String, "valence": float}.
static func memories(mem: WorkerMemory, n: int = 4) -> Array[Dictionary]:
	var scored: Array = []
	var total := mem.episodic.size()
	var seen := {}
	for i in total:
		var e: Dictionary = mem.episodic[i]
		var kind := str(e.get("kind", ""))
		if kind in ["plan", "asked", "told"]:
			continue
		var text := _nice(e)
		if text == "" or seen.has(text):
			continue
		seen[text] = true
		var val := float(e.get("valence", 0.0))
		var score := absf(val) * 2.0 + float(i) / maxf(float(total), 1.0)
		if kind in ["rel", "quirk"]:
			score += 0.5
		scored.append({"score": score, "day": int(e.get("day", 0)), "text": text, "valence": val})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var out: Array[Dictionary] = []
	for s: Dictionary in scored:
		if out.size() >= n:
			break
		out.append({"day": s["day"], "text": s["text"], "valence": s["valence"]})
	return out


static func _nice(e: Dictionary) -> String:
	var s := str(e.get("summary", "")).strip_edges()
	if s == "":
		return ""
	if s.begins_with("Player "):
		s = "You " + s.substr(7)
	elif s.begins_with("Learned: "):
		s = "You taught me: " + s.substr(9)
	elif s.begins_with("Built the "):
		s = "I built the " + s.substr(10)
	elif s.begins_with("Told to "):
		s = "You asked me to " + s.substr(8)
	elif s.begins_with("Taken on as "):
		s = "You took me on as " + s.substr(12)
	return s


## "Trusts you", "Keeps their distance"... one phrase under the label.
static func blurb(mem: WorkerMemory) -> String:
	match tier(mem):
		Tier.RESENTFUL: return "Holds a grudge and does the minimum."
		Tier.WARY: return "Keeps their distance."
		Tier.STRANGER: return "Does not know you well yet."
		Tier.ACQUAINTANCE: return "Knows you and gets on well enough."
		Tier.FRIEND: return "Glad of your company; works a little harder for you."
		Tier.CONFIDANT: return "Would trust you with anything."
	return ""


## A word for how they are today, from morale.
static func mood_word(mem: WorkerMemory) -> String:
	var m := float(mem.disposition.get("morale", 0.7))
	if m < 0.25: return "Miserable"
	if m < 0.4: return "Low"
	if m < 0.6: return "Flat"
	if m < 0.8: return "Content"
	return "Cheerful"


# ----------------------------------------------------------------- the wiring

## Hook every source of relationship events to the live game. Called once from
## Main. hud: instruction_given; crew: step_done on hired workers; clock: the
## morning drift. Request fulfilment, when that system exists, calls
## record(mem, "request_done", day) itself (see Requests hook note in Main).
static func bind(hud: Node, crew: Crew, clock: GameClock) -> void:
	if hud != null and hud.has_signal("instruction_given"):
		hud.instruction_given.connect(func(w: Worker, t: String) -> void:
			if w != null and is_instance_valid(w):
				on_said(w.memory, t, clock.day))
	if crew != null:
		for w: Worker in crew.workers:
			_watch(w, clock)
		crew.roster_changed.connect(func() -> void:
			for w2: Worker in crew.workers:
				_watch(w2, clock))
	if clock != null:
		clock.day_passed.connect(func(_d: int) -> void:
			if crew != null:
				for w3: Worker in crew.workers:
					if is_instance_valid(w3):
						drift(w3.memory))


static func _watch(w: Worker, clock: GameClock) -> void:
	if not is_instance_valid(w) or w.has_meta("rel_watch"):
		return
	w.set_meta("rel_watch", true)
	w.step_done.connect(func(wk: Worker) -> void:
		if is_instance_valid(wk) and wk.hired:
			record(wk.memory, "order_done", clock.day))
