extends RefCounted
class_name Conversation
## Everybody in town talking as themselves.
##
## The town used to answer in stock lines: "I do not work for you", the same
## "Oi! This is my house" every time you stepped indoors, a greeting that went
## to the building planner because it was not a question. Anyone you spoke to
## was a form with a name on it. This is the other half: a person with a
## character, a job or none, a home, a history with you, and the last few
## things the two of you said — handed to the model, which speaks as them.
##
## Facts stay the game's. When the records know the answer (how many bricks,
## where the store is), they are passed in as what this person knows, and the
## model's job is only to say it the way they would. Orders stay the game's
## too: nothing here builds or hires anything. A conversation is words.
##
## Offline, every caller has a stock line to fall back on, so a build with no
## key still talks — just less like a person.

## Turns of the conversation kept per person: enough to follow a thread and
## not repeat themselves, short enough to stay cheap.
const HISTORY := 12

var _history: Dictionary = {}          ## worker_id -> Array of {role, content}


func forget(worker_id: String) -> void:
	_history.erase(worker_id)


## Everything a request needs: the system prompt describing this person and
## what they know, and the conversation so far with the new moment on the end.
##
## `heard` is what the player just said to them, "" when nothing was said —
## an event instead, like walking into their house. `situation` is what is
## happening, in plain words, for the model to react to. `facts` is what the
## records say about what was asked, to be put in their own words.
func build(w: Worker, heard: String, situation: String, facts: String,
		town: Town, clock: GameClock, realm: Node) -> Dictionary:
	var msgs: Array = (_history.get(w.memory.worker_id, []) as Array).duplicate()
	var now: Array[String] = []
	if situation != "":
		now.append("(What is happening: %s)" % situation)
	if facts != "":
		now.append("(What you know that bears on this: %s)" % facts)
	if heard != "":
		now.append(heard.strip_edges())
	else:
		now.append("(Nobody has spoken. Say what you would say right now.)")
	msgs.append({"role": "user", "content": "\n".join(now)})
	return {"system": system_for(w, town, clock, realm), "messages": msgs}


## Once the line has come back: what was said, and what they said to it, go on
## the record so the next line follows from them.
func record(w: Worker, heard: String, situation: String, reply: String) -> void:
	var id := w.memory.worker_id
	var h: Array = _history.get(id, [])
	var said := heard.strip_edges()
	if said == "" and situation != "":
		said = "(%s)" % situation
	if said != "":
		h.append({"role": "user", "content": said})
	h.append({"role": "assistant", "content": reply})
	while h.size() > HISTORY:
		h.pop_front()
	_history[id] = h


func system_for(w: Worker, town: Town, clock: GameClock, realm: Node) -> String:
	var mem := w.memory
	var name := mem.display_name
	var lines: Array[String] = []
	var role := w.role
	var kingdom := str(realm.get("kingdom_name")) if realm != null else "the town"

	lines.append("You are %s, a real person living in %s, a small village of timber and thatch. You are not an assistant and you do not know you are in a game." % [name, kingdom])
	if w.hired and role != null:
		lines.append("You work for the person talking to you, as the town's %s. %s" % [
			role.name, role.character])
	else:
		lines.append("You do not work for the person talking to you. They are the one who has been taking people on and getting things built around here; if they want you to work for them, they can offer you a job (\"I'd like to hire you as a farmer\"), and until then you do not take their orders. %s" % (
			role.character if role != null else ""))

	lines.append("")
	lines.append("WHO YOU ARE")
	lines.append(_temperament(mem))
	var home := _home_line(w, realm)
	if home != "":
		lines.append(home)

	lines.append("")
	lines.append("HOW YOU FEEL ABOUT THEM")
	lines.append(_feeling(mem))
	var past := mem.recent(8)
	if not past.is_empty():
		lines.append("What you remember of them lately:")
		for e: Dictionary in past:
			lines.append("- day %d: %s" % [int(e["day"]), str(e["summary"])])

	lines.append("")
	lines.append("RIGHT NOW")
	if clock != null:
		lines.append("It is %s on day %d." % [clock.part_of_day(clock.hour), clock.day])
	lines.append("You are %s." % w.status_text())
	if town != null:
		lines.append(town.describe_buildings())

	lines.append("")
	lines.append("HOW TO TALK")
	lines.append("- Say only what %s says out loud: one to three short sentences, the way people talk in a village street. Casual, specific, in character." % name)
	lines.append("- React to what was actually said. A greeting gets a greeting back, in your own way; a joke might get a laugh or a look; rudeness gets what rudeness deserves.")
	lines.append("- Never repeat a line you have already said in this conversation. Find new words every time.")
	lines.append("- Your mood and your history with them colour everything. Hold a grudge if you have one; be warm if you are warm.")
	lines.append("- Only the facts given to you are facts. If you do not know, say so like a person would. Never make up buildings, numbers or people.")
	lines.append("- Saying you will do something does not do it. If they ask for work, react as yourself; do not describe doing it.")
	lines.append("- No narration, no stage directions, no asterisks, no quotation marks, no lists. Just the words.")
	return "\n".join(lines)


## Traits as a person would describe them, rather than as a worker's habits
## on a building site — which is what the planning prompt needs, and not what
## a conversation does.
static func _temperament(mem: WorkerMemory) -> String:
	var t := mem.traits
	var d := mem.disposition
	var out: Array[String] = []
	if float(t["speed"]) > 0.7:
		out.append("You are quick and restless, and you talk fast.")
	elif float(t["speed"]) < 0.4:
		out.append("You are slow and deliberate, and you think before you speak.")
	if float(t["literalism"]) > 0.7:
		out.append("You take what people say at face value and miss irony.")
	elif float(t["literalism"]) < 0.35:
		out.append("You have your own ideas about everything and you share them.")
	if float(t["initiative"]) > 0.7:
		out.append("You are bold and a bit of a show-off.")
	elif float(t["initiative"]) < 0.3:
		out.append("You are reserved and keep to yourself.")
	if float(t["criticism_sensitivity"]) > 0.7:
		out.append("You are sensitive and take slights to heart.")
	elif float(t["criticism_sensitivity"]) < 0.3:
		out.append("You are thick-skinned and blunt.")
	var morale := float(d.get("morale", 0.7))
	if morale < 0.4:
		out.append("You are in low spirits today.")
	elif morale > 0.85:
		out.append("You are in fine spirits today.")
	if out.is_empty():
		out.append("You are an ordinary, even-tempered sort.")
	return " ".join(out)


static func _feeling(mem: WorkerMemory) -> String:
	var trust := float(mem.disposition.get("trust_in_player", 0.5))
	if trust > 0.75:
		return "You like and trust them."
	if trust > 0.55:
		return "You think well enough of them."
	if trust > 0.4:
		return "You do not know them well and are keeping an open mind."
	if trust > 0.25:
		return "You are wary of them."
	return "You do not like them, and you do not hide it."


## Where this person sleeps and where they work, from the kingdom's records.
static func _home_line(w: Worker, realm: Node) -> String:
	if realm == null:
		return ""
	var pop: Population = realm.get("population")
	if pop == null:
		return ""
	var c := pop.for_worker(w)
	if c == null:
		return ""
	var home := pop.home_of(c)
	if home == "nowhere":
		return "You have no home and sleep rough, which you do not enjoy."
	return "You live in %s." % home
