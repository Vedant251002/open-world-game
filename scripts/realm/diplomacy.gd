extends RefCounted
class_name Diplomacy
## Talking with the neighbours, in words.
##
## The Neighbours system (neighbours.gd) holds the towns, their tempers and
## the rules for what an errand does. This is the conversation in front of it:
## the player says something to a leader or an envoy, and it becomes one of the
## things Neighbours already knows how to do — a gift, a caravan, a treaty, a
## demand, a declaration — with a reply in the leader's voice.
##
## Offline (no key) the whole thing is keywords and templates, and it is the
## reference behaviour: `evaluate()` decides, `reply()` words it. With a key,
## one model call per exchange plays the leader and returns a reply plus a
## small structured decision; `validate()` holds that decision to the rules, so
## the model can colour and soften a deal but cannot hand out an alliance to a
## town that despises us or conjure coins we have not got.
##
## Outcomes land in the chronicle, which is how the Village Crier and the
## crew's "what happened lately" pick them up.

signal replied(town_name: String, line: String, outcome: Dictionary)

const ACTIONS := ["gift", "trade", "alliance", "peace", "war", "demand", "apology", "none"]
const DECISIONS := ["accept", "counter", "refuse", "none"]
const MAX_COINS := 500
const DEFAULT_GIFT := 100

var realm: Realm
var nb: Node                       ## the Neighbours system
## Per town: the counter-offer on the table, {action, coins, then}.
var pending: Dictionary = {}
## Per town: the last few lines, [{role, content}], for the model.
var history: Dictionary = {}
var _serial := 0
var _inflight: Dictionary = {}     ## tag -> {town, text, base}


func setup(r: Realm) -> void:
	realm = r
	nb = r.system("Neighbours")
	var llm := _llm()
	if llm != null and not llm.line_ready.is_connected(_on_line):
		llm.line_ready.connect(_on_line)


func _llm() -> LLM:
	if realm == null or realm.dispatch == null:
		return null
	return realm.dispatch.get("llm") as LLM


func online() -> bool:
	var l := _llm()
	return l != null and l.available()


# ============================================================== understanding

const _NUMBER_WORDS := {"ten": 10, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
	"hundred": 100, "a hundred": 100, "two hundred": 200, "three hundred": 300,
	"four hundred": 400, "five hundred": 500, "thousand": 1000}


## The first amount in the text: digits ("150", "1.5k", "200 coins"), or a few
## number words. 0 when there is none.
static func amount_in(text: String) -> int:
	var t := text.to_lower()
	var digits := ""
	var i := 0
	while i < t.length():
		var ch := t[i]
		if ch >= "0" and ch <= "9":
			digits += ch
			i += 1
			continue
		if digits != "":
			if ch == "k":
				return mini(int(digits) * 1000, 100000)
			break
		i += 1
	if digits != "":
		return mini(int(digits), 100000)
	var best := 0
	var best_len := 0
	for w: String in _NUMBER_WORDS:
		if t.find(w) >= 0 and w.length() > best_len:
			best = int(_NUMBER_WORDS[w])
			best_len = w.length()
	return best


static func _has(t: String, words: Array) -> bool:
	for w: String in words:
		if t.find(w) >= 0:
			return true
	return false


## What the player means, as {kind, coins}. kind is one of: gift, trade,
## alliance, peace, war, demand, apology, ask, accept, decline, greet.
##
## Ordered by how much a mistake would cost: a declaration of war is only read
## when it is asked for outright, a threat before a plea, a plea before small
## talk — and a "no" in front of a word turns a request into a refusal rather
## than the request.
static func parse(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges().replace("’", "'")
	var coins := amount_in(t)
	var out := {"kind": "greet", "coins": coins}
	if t == "":
		return out
	var negated := _has(t, ["no thanks", "no thank", "never mind", "forget it", "i take it back",
		"not now", "we decline", "i decline", "no deal"])
	if negated or t in ["no", "nope", "nay", "refuse"]:
		out["kind"] = "decline"
		return out
	if t in ["yes", "yes.", "aye", "agreed", "deal", "fine", "very well", "done", "accepted"] \
			or _has(t, ["i accept", "we accept", "it is a deal", "it's a deal", "that is fair", "that's fair",
				"i agree", "we agree", "agreed", "very well", "yes, ", "yes please", "i'll pay", "i will pay",
				"we will pay", "pay it"]):
		out["kind"] = "accept"
		return out
	if _has(t, ["declare war", "war on you", "we are at war", "go to war", "march on", "burn your",
			"prepare for war", "this means war", "i declare"]):
		out["kind"] = "war"
	elif _has(t, ["threat", "or else", "tribute", "pay us", "pay me", "you will pay", "demand",
			"submit", "surrender", "kneel", "bow to", "obey", "or we will", "or i will", "else we",
			"hand over", "give us your"]):
		out["kind"] = "demand"
	elif _has(t, ["sorry", "apolog", "forgive", "make amends", "my mistake", "regret"]):
		out["kind"] = "apology"
	elif _has(t, ["peace", "truce", "ceasefire", "cease-fire", "end the war", "armistice",
			"lay down arms", "stop fighting", "end the fighting"]):
		out["kind"] = "peace"
	elif _has(t, ["alliance", "allies", "ally", "pact", "stand with us", "stand with me",
			"join forces", "fight beside", "defend each other", "mutual defence", "mutual defense"]):
		out["kind"] = "alliance"
	elif _has(t, ["gift", "present", "gold for", "give you", "give your", "send you", "send some coin",
			"send coins", "send coin", "donate", "token of", "bribe", "coins as", "purse"]):
		out["kind"] = "gift"
	elif _has(t, ["trade", "caravan", "barter", "merchants", "goods", "market", "sell you", "buy from",
			"buy your", "buy some", "exchange", "commerce", "wares", "open the road", "open the roads"]):
		out["kind"] = "trade"
	elif _has(t, ["what do you want", "what do you need", "what do you offer", "what do you sell",
			"what will you", "what can you", "what would you", "your terms", "what is your price",
			"how do you feel", "what do you think of", "who are you", "tell me about", "how are things",
			"what are you", "what's your", "what is your"]):
		out["kind"] = "ask"
	return out


# ================================================================== deciding

## What this town makes of that, by the rules and nobody's mood but its own.
##
## {decision: accept|counter|refuse|none, action, coins, then, note}
## `action` is what happens if it goes ahead; for a counter, `coins` is the
## gift they ask and `then` the action it would unlock.
func evaluate(town: Dictionary, intent: Dictionary) -> Dictionary:
	var kind := str(intent.get("kind", "greet"))
	var coins := int(intent.get("coins", 0))
	var d := float(town["disposition"])
	var treaty := str(town["treaty"])
	var purse := realm.town.coins if realm != null and realm.town != null else 0
	var v := {"decision": "none", "action": "none", "coins": 0, "then": "", "note": ""}
	match kind:
		"gift":
			coins = clampi(coins if coins > 0 else DEFAULT_GIFT, 1, MAX_COINS)
			if purse < coins:
				v["note"] = "poor"
				v["coins"] = coins
			else:
				v.merge({"decision": "accept", "action": "gift", "coins": coins}, true)
		"trade":
			if treaty == "war":
				v.merge({"decision": "refuse", "action": "trade", "note": "war"}, true)
			elif d < -0.3:
				v.merge({"decision": "counter", "action": "gift", "then": "trade",
					"coins": _gift_to_reach(d, -0.25)}, true)
			else:
				v.merge({"decision": "accept", "action": "trade"}, true)
		"alliance":
			if treaty == "war":
				v.merge({"decision": "refuse", "action": "alliance", "note": "war"}, true)
			elif treaty == "alliance":
				v["note"] = "already"
			elif d > 0.4:
				v.merge({"decision": "accept", "action": "alliance"}, true)
			elif d > 0.1:
				v.merge({"decision": "counter", "action": "gift", "then": "alliance",
					"coins": _gift_to_reach(d, 0.42)}, true)
			else:
				v.merge({"decision": "refuse", "action": "alliance"}, true)
		"peace":
			if treaty != "war":
				if treaty in ["peace", "alliance", "vassal"]:
					v["note"] = "already"
				elif d > -0.5:
					v.merge({"decision": "accept", "action": "peace"}, true)
				else:
					v.merge({"decision": "refuse", "action": "peace"}, true)
			elif d > -0.3:
				v.merge({"decision": "accept", "action": "peace"}, true)
			else:
				var price := _gift_to_reach(d, -0.28)
				if price > MAX_COINS:
					v.merge({"decision": "refuse", "action": "peace"}, true)
				else:
					v.merge({"decision": "counter", "action": "gift", "then": "peace",
						"coins": price}, true)
		"war":
			if treaty == "war":
				v["note"] = "already"
			else:
				v.merge({"decision": "accept", "action": "war"}, true)
		"demand":
			var pays := int(town["strength"]) < 25 or d > 0.5
			v.merge({"decision": "accept" if pays else "refuse", "action": "demand",
				"coins": 60 + int(town["strength"]) * 2 if pays else 0}, true)
		"apology":
			v.merge({"decision": "accept", "action": "apology"}, true)
		"accept":
			var p: Dictionary = pending.get(str(town["name"]), {})
			if p.is_empty():
				v["note"] = "nothing_pending"
			else:
				if purse < int(p["coins"]):
					v.merge({"decision": "none", "note": "poor", "coins": int(p["coins"])}, true)
				else:
					v.merge({"decision": "accept", "action": "gift", "coins": int(p["coins"]),
						"then": str(p.get("then", ""))}, true)
		"decline":
			v["note"] = "decline"
		"ask":
			v["note"] = "ask"
	v["intent"] = kind
	return v


## The gift that would lift this town's temper to `target`, rounded up to 10.
static func _gift_to_reach(d: float, target: float) -> int:
	# resolve("gift") adds 0.15 + coins/1000.
	var need := (target - d - 0.15) * 1000.0
	return maxi(DEFAULT_GIFT, int(ceil(need / 10.0)) * 10)


# ============================================================ validating a model

## Holds a model's structured decision to the rules. `base` is evaluate()'s
## verdict for the same words. The model may refuse or counter anything the
## rules would allow, and may accept what they would only counter when the
## town is not at war and the goodwill is there; it may never change what the
## player did (a declaration, a demand), pick an action nobody asked for, or
## ask for more than MAX_COINS.
func validate(town: Dictionary, base: Dictionary, raw: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	if raw.is_empty():
		return out
	var decision := str(raw.get("decision", ""))
	var action := str(raw.get("action", ""))
	if decision not in DECISIONS or action not in ACTIONS:
		return out
	var kind := str(base.get("intent", ""))
	# What the player did is not up for negotiation.
	if kind in ["war", "apology", "ask", "greet", "decline", "demand", "gift"]:
		return out
	var wanted := str(base.get("then", "")) if str(base.get("action", "")) == "gift" and kind != "gift" \
		else str(base.get("action", ""))
	if kind == "accept":
		return out
	var d := float(town["disposition"])
	var treaty := str(town["treaty"])
	var coins := clampi(int(raw.get("coins", 0)), 0, MAX_COINS)
	match decision:
		"refuse":
			out.merge({"decision": "refuse", "action": wanted if wanted != "" else action,
				"coins": 0, "then": ""}, true)
		"counter":
			if coins <= 0:
				coins = DEFAULT_GIFT
			var purse := realm.town.coins
			coins = mini(coins, maxi(purse, 0))
			if coins <= 0:
				return out
			out.merge({"decision": "counter", "action": "gift", "coins": coins,
				"then": wanted if wanted in ["trade", "alliance", "peace"] else str(base.get("then", ""))}, true)
		"accept":
			if str(base["decision"]) == "accept":
				out["decision"] = "accept"
			elif wanted in ["trade", "peace"] and treaty != "war" and d > -0.5:
				out.merge({"decision": "accept", "action": wanted, "coins": 0, "then": ""}, true)
			elif wanted == "alliance" and treaty != "war" and d > 0.1:
				out.merge({"decision": "accept", "action": "alliance", "coins": 0, "then": ""}, true)
			# Otherwise the rules stand: the model cannot buy us a friend.
	return out


# ================================================================= carrying out

## Does it. Returns {ok, summary, coins} where `summary` is the chronicle line
## (empty if nothing worth writing happened).
func apply(town: Dictionary, verdict: Dictionary) -> Dictionary:
	var name := str(town["name"])
	var leader := str(town["leader"])
	var action := str(verdict.get("action", "none"))
	var decision := str(verdict.get("decision", "none"))
	var res := {"ok": false, "summary": "", "coins": 0, "action": action, "decision": decision}
	if str(verdict.get("note", "")) == "decline":
		pending.erase(name)
	if decision == "counter":
		pending[name] = {"action": "gift", "coins": int(verdict["coins"]), "then": str(verdict.get("then", ""))}
		return res
	if decision == "refuse":
		pending.erase(name)
		if action == "demand":
			var before := float(town["disposition"])
			nb.resolve(town, "demand")        # it laughs; mood falls
			res["summary"] = "Our demand for tribute was laughed at in %s. %s is %s." % [
				name, leader, nb.mood_word(town)]
			res["ok"] = true
			_after_provocation(town, before)
			return res
		if action in ["trade", "alliance", "peace"]:
			nb.adjust(name, -0.03)
		return res
	if decision != "accept":
		return res
	pending.erase(name)
	match action:
		"gift":
			var coins := clampi(int(verdict["coins"]), 1, MAX_COINS)
			if realm.town.coins < coins:
				return res
			realm.town.coins -= coins
			nb.resolve(town, "gift", coins)
			res["coins"] = coins
			res["ok"] = true
			res["summary"] = "We sent %d coins to %s. %s is %s now." % [
				coins, name, leader, nb.mood_word(town)]
			# A gift that was the price of something carries the something out.
			var then := str(verdict.get("then", ""))
			if then in ["trade", "alliance", "peace"]:
				var follow := evaluate(town, {"kind": then, "coins": 0})
				if str(follow["decision"]) == "accept":
					var more := apply(town, follow)
					res["summary"] += " " + str(more["summary"])
					res["then_ok"] = bool(more["ok"])
					res["caravan"] = more.get("caravan", "")
		"trade":
			if str(town["treaty"]) == "none":
				town["treaty"] = "trade"
			nb.adjust(name, 0.05)
			var why: String = nb.start_caravan(town)
			res["ok"] = true
			res["caravan"] = why
			res["summary"] = "Trade agreed with %s. %s" % [name,
				"A caravan is on the road." if why == "" else why]
		"alliance":
			nb.resolve(town, "alliance")
			res["ok"] = str(town["treaty"]) == "alliance"
			res["summary"] = "An alliance with %s, sealed by %s." % [name, leader] if res["ok"] else ""
		"peace":
			var was_war := str(town["treaty"]) == "war"
			nb.resolve(town, "peace")
			res["ok"] = str(town["treaty"]) == "peace"
			if res["ok"]:
				res["summary"] = "%s with %s, sealed by %s." % [
					"Peace was made" if was_war else "A peace was agreed", name, leader]
		"war":
			nb.resolve(town, "war")
			res["ok"] = true
			res["summary"] = "We declared war on %s." % name
		"demand":
			var before := float(town["disposition"])
			nb.resolve(town, "demand")
			res["ok"] = true
			res["coins"] = int(verdict.get("coins", 0))
			res["summary"] = "%s paid us %d coins in tribute, under threat." % [name, int(verdict.get("coins", 0))]
			_after_provocation(town, before)
		"apology":
			nb.adjust(name, 0.1)
			res["ok"] = true
			res["summary"] = "We made our apologies to %s." % name
	if str(res["summary"]) != "" and realm != null:
		realm.note("neighbours", str(res["summary"]))
	return res


## Threats make enemies. A town pushed past endurance stops being merely sour
## and declares war on its own account.
func _after_provocation(town: Dictionary, before: float) -> void:
	if float(town["disposition"]) < -0.7 and str(town["treaty"]) in ["none", "trade"]:
		town["treaty"] = "war"
		realm.note("neighbours", "%s, insulted once too often, declared war on us." % town["name"])
		realm.say("%s has declared war!" % town["name"])
	elif before > float(town["disposition"]):
		realm.note("neighbours", "Our threats to %s were not forgotten." % town["name"])


# ================================================================== the dialogue

## The player says something to a town's leader. The reply comes by `replied`
## (at once offline; when the model answers otherwise).
func say(town_name: String, text: String) -> void:
	var town: Dictionary = nb.by_name(town_name)
	if town.is_empty() or text.strip_edges() == "":
		return
	var intent := parse(text)
	var base := evaluate(town, intent)
	_push(town_name, "user", text)
	if online() and str(intent["kind"]) not in ["accept", "decline"]:
		_serial += 1
		var tag := "dip%d" % _serial
		_inflight[tag] = {"town": town_name, "text": text, "base": base, "intent": intent}
		var req := _build(town, intent, base)
		_llm().talk("dip_" + town_name, str(req["system"]), req["messages"], tag,
			_fallback_marker(base))
		return
	_finish(town, base, "")


func _fallback_marker(base: Dictionary) -> String:
	# The line the model layer hands back when it fails; recognised in _on_line.
	return "⁣offline"


func _on_line(_worker_id: String, text: String, tag: String) -> void:
	if not _inflight.has(tag):
		return
	var job: Dictionary = _inflight[tag]
	_inflight.erase(tag)
	var town: Dictionary = nb.by_name(str(job["town"]))
	if town.is_empty():
		return
	var base: Dictionary = job["base"]
	if text.begins_with("⁣offline") or text.strip_edges() == "":
		_finish(town, base, "")
		return
	var parsed := split_reply(text)
	var verdict := validate(town, base, parsed["decision"])
	_finish(town, verdict, str(parsed["reply"]))


## The model's text into {reply, decision}: the spoken part, and the JSON on the
## line that starts with "@".
static func split_reply(text: String) -> Dictionary:
	var reply := text.strip_edges()
	var decision: Dictionary = {}
	var at := reply.rfind("@{")
	if at < 0:
		at = reply.rfind("{\"decision\"")
	if at >= 0:
		var body := reply.substr(at).trim_prefix("@")
		var end := body.rfind("}")
		if end >= 0:
			var v: Variant = JSON.parse_string(body.substr(0, end + 1))
			if v is Dictionary:
				decision = v
		reply = reply.substr(0, at).strip_edges()
	if reply.length() > 300:
		reply = reply.substr(0, 297).strip_edges() + "..."
	return {"reply": reply, "decision": decision}


func _finish(town: Dictionary, verdict: Dictionary, model_reply: String) -> void:
	var name := str(town["name"])
	var outcome := apply(town, verdict)
	var line := model_reply if model_reply != "" else reply(town, verdict, outcome)
	_push(name, "assistant", line)
	replied.emit(name, line, outcome)


func _push(town_name: String, role: String, content: String) -> void:
	var h: Array = history.get(town_name, [])
	h.append({"role": role, "content": content})
	while h.size() > 8:
		h.pop_front()
	history[town_name] = h


# ===================================================================== wording

const OPEN := {
	"proud": {"accept": "It pleases us to say yes.", "counter": "We are not accustomed to being asked so lightly.",
		"refuse": "You presume.", "none": "Speak, then."},
	"shrewd": {"accept": "Good business, then.", "counter": "Everything has a price.",
		"refuse": "There is nothing in it for us.", "none": "Go on."},
	"warm": {"accept": "Gladly, friend!", "counter": "Almost, friend, almost.",
		"refuse": "I am sorry, truly.", "none": "Come, sit, tell me."},
	"blunt": {"accept": "Fine.", "counter": "Not for nothing.", "refuse": "No.", "none": "Out with it."},
	"wary": {"accept": "Very well. We will watch how it goes.", "counter": "We would need a sign of good faith.",
		"refuse": "We do not trust you enough.", "none": "We are listening."},
	"pious": {"accept": "May it be blessed.", "counter": "Let there be an offering first.",
		"refuse": "The signs are against it.", "none": "Speak, and speak true."},
}

## What each action means, by decision. {town} {leader} {coins} {sells} {buys}
## {player} {mood} are filled in.
const BODY := {
	"gift": {"accept": "{coins} coins received. {town} will remember it.",
		"none": "You cannot spare {coins} coins, I think. Do not beggar yourself on my account."},
	"trade": {"accept": "{town} sells {sells} and pays well for {buys}. Send a caravan and we will deal.",
		"refuse": "No cart of yours crosses our fields while we are at odds."},
	"alliance": {"accept": "Then {town} stands with {player}. If riders come, we will ride.",
		"refuse": "An alliance? We hardly know you.",
		"none": "We are allied already."},
	"peace": {"accept": "Peace, then. Let the swords stay in their scabbards.",
		"refuse": "There can be no peace while the matter stands.",
		"none": "We are at ease with one another already."},
	"war": {"accept": "So it is war. {town} will be ready.", "none": "We are at war already, or had you not noticed?"},
	"demand": {"accept": "Take your {coins} coins and be gone.",
		"refuse": "Tribute? From {town}? Come and take it."},
	"apology": {"accept": "An apology costs little. I will accept it."},
	"counter_gift": {"trade": "Show some goodwill first: {coins} coins as a gift, and the roads are open.",
		"alliance": "An alliance wants proof. {coins} coins as a gift of good faith, and I will put my seal to it.",
		"peace": "Peace has a price: {coins} coins for what this quarrel has cost us.",
		"": "A gift of {coins} coins would help."},
}


## What the leader says, from the rules alone. Used offline, and whenever the
## model has nothing to add.
func reply(town: Dictionary, verdict: Dictionary, outcome: Dictionary = {}) -> String:
	var pers := str(town.get("personality", "wary"))
	var decision := str(verdict.get("decision", "none"))
	var action := str(verdict.get("action", "none"))
	var note := str(verdict.get("note", ""))
	var intent := str(verdict.get("intent", "greet"))
	var opener: String = (OPEN.get(pers, OPEN["wary"]) as Dictionary).get(decision, "")
	var body := ""
	if note == "nothing_pending":
		body = "Accept what? We have asked for nothing."
		opener = ""
	elif note == "decline":
		body = "Then there is nothing more to say about it."
		opener = ""
	elif note == "ask":
		body = "{town} is a %s. We sell %s and want %s. As to you, we are {mood}." % [
			str(town["kind"]), " and ".join(town["sells"]), " and ".join(town["buys"])]
	elif intent == "greet":
		body = "%s of {town} hears you." % str(town["leader"])
	elif decision == "counter":
		body = BODY["counter_gift"].get(str(verdict.get("then", "")), BODY["counter_gift"][""])
	elif note == "poor":
		body = BODY["gift"]["none"]
		opener = ""
	elif note == "already" and BODY.has(action):
		body = BODY[action].get("none", "That is settled already.")
		opener = ""
	elif BODY.has(action):
		body = (BODY[action] as Dictionary).get(decision, "")
	if body == "":
		body = "Hm."
	var caravan := str(outcome.get("caravan", ""))
	var shown_coins := int(verdict.get("coins", 0))
	var line := (opener + " " + body).strip_edges()
	line = line.format({
		"town": str(town["name"]), "leader": str(town["leader"]),
		"coins": shown_coins, "sells": " and ".join(town["sells"]),
		"buys": " and ".join(town["buys"]),
		"player": realm.kingdom_name.capitalize() if realm != null else "you",
		"mood": nb.mood_word(town) if nb != null else "",
	})
	# The follow-through of a gift that bought something (or a caravan that
	# could not leave).
	if str(outcome.get("action", "")) == "gift" and str(verdict.get("then", "")) != "":
		if bool(outcome.get("then_ok", false)):
			line += " And so: %s." % {"trade": "a caravan to us will be welcome",
				"alliance": "we are allied", "peace": "peace"}.get(str(verdict["then"]), "agreed")
	if caravan != "" and (action == "trade" or str(verdict.get("then", "")) == "trade"):
		line += " (%s)" % caravan
	return line


# ============================================================== the model's turn

## The prompt for a leader: who they are, what they want, how they feel about
## us, what we have just said — and the one line of structure we need back.
func _build(town: Dictionary, intent: Dictionary, base: Dictionary) -> Dictionary:
	var sys: Array[String] = []
	var treaty := str(town["treaty"])
	sys.append("You are %s, leader of %s, a %s. You are %s by temperament. You are speaking with the mayor of %s, a village a few days' walk away. You are not an assistant and you do not know you are in a game." % [
		town["leader"], town["name"], town["kind"], town.get("personality", "wary"),
		realm.kingdom_name])
	sys.append("Your town sells %s and wants %s. Your feeling toward them: %s. Treaty between you: %s. Your strength: %d fighters." % [
		" and ".join(town["sells"]), " and ".join(town["buys"]), nb.mood_word(town),
		"none yet" if treaty == "none" else treaty, int(town["strength"])])
	sys.append("Answer in character in one or two short sentences, under 200 characters, plain spoken, no stage directions.")
	sys.append("Then on a new line write exactly one JSON object after an @ sign, like: @{\"decision\":\"accept\",\"action\":\"trade\",\"coins\":0}")
	sys.append("decision is accept, counter, refuse or none. action is gift, trade, alliance, peace, war, demand, apology or none. For a counter, coins is the gift you want first (0 to %d); otherwise 0." % MAX_COINS)
	sys.append("The rules of your own mood: you would not ally with someone you scarcely know, you will not trade with an enemy at war with you, and you take threats badly. Your inclination right now toward what they ask is: %s." % str(base.get("decision", "none")))
	var msgs: Array = []
	for e: Variant in history.get(str(town["name"]), []):
		msgs.append(e)
	# The player's newest line is already the last of the history.
	return {"system": "\n".join(sys), "messages": msgs}


## A short line for the screen's header: what is on the table, if anything.
func pending_line(town: Dictionary) -> String:
	var p: Dictionary = pending.get(str(town["name"]), {})
	if p.is_empty():
		return ""
	return "On the table: a gift of %d coins, then %s. Say \"agreed\" to accept." % [
		int(p["coins"]), str(p.get("then", "an understanding"))]
