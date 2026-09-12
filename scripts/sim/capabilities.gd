extends RefCounted
class_name Capabilities
## Everything a person in this town can be asked to do.
##
## A role is a subset of this list plus a character. The list is the thing that
## decides how rich a role can be — an AI composing a "driver" from it can only
## reach for what is here, and cannot describe driving into existence. So the
## list is deliberately wide, and deliberately honest about which entries the
## engine can carry out today.
##
## `ready` is the whole truth of an entry. A ready capability has an executor
## in Dispatcher and a job the worker can take; a planned one is declared here
## so a role can be defined against it now, listed to the player as coming,
## and refused in character if a plan reaches for it — "I was taken on for
## that, but the town has no means for it yet." That refusal is fail-closed
## and legible, which is the whole of pillar P3, and it turns this file into
## the roadmap: every `ready: false` is a piece of engine work, and every role
## players define against it is a vote for doing it next.
##
## `tags` are the words in a role description that suggest this capability,
## for the offline composer. The model reads `says`; the fallback reads tags.

const LIST := {
	# --- moving about -------------------------------------------------------
	"go": {
		"says": "walk to a named place — a building, the well, the field, home, or to you",
		"ready": true,
		"tags": ["walk", "go", "travel", "visit", "run", "messenger", "errand"],
	},
	"follow": {
		"says": "follow you around, at your back",
		"ready": true,
		"tags": ["follow", "escort", "companion", "bodyguard", "accompany", "guard"],
	},
	"wait": {
		"says": "stay put where they are told",
		"ready": true,
		"tags": ["wait", "stand", "stay", "watch", "guard", "sentry", "doorman"],
	},
	"patrol": {
		"says": "walk a round between places, over and over, for a set time",
		"ready": true,
		"tags": ["patrol", "guard", "watchman", "police", "night", "rounds", "security", "sentry"],
	},
	"scout": {
		"says": "walk out in a direction and come back with what the ground is like",
		"ready": true,
		"tags": ["scout", "explore", "survey", "prospect", "ranger", "look", "find"],
	},

	# --- working at a place -------------------------------------------------
	"station": {
		"says": "work at a building for a shift — the oven, the counter, the forge, the gate",
		"ready": true,
		"tags": ["work", "shift", "shopkeeper", "cook", "baker", "smith", "clerk",
			"barman", "innkeeper", "teacher", "doctor", "nurse", "priest", "guard",
			"keeper", "attendant", "tend", "serve", "run the"],
	},
	"rest": {
		"says": "go home and rest, and come back in better spirits",
		"ready": true,
		"tags": ["rest", "sleep", "home"],
	},

	# --- building and land --------------------------------------------------
	"build": {
		"says": "put up a building on a plot",
		"ready": true,
		"tags": ["build", "builder", "construct", "carpenter", "mason", "architect", "erect"],
	},
	"enclose": {
		"says": "fence a piece of ground with a gate in it",
		"ready": true,
		"tags": ["fence", "pen", "enclose", "corral", "shepherd", "farmer", "rancher", "herder"],
	},
	"sow": {
		"says": "plough a field and sow it",
		"ready": true,
		"tags": ["farm", "farmer", "plough", "sow", "plant", "crop", "grow", "gardener", "field"],
	},
	"harvest": {
		"says": "walk the field and bring in whatever is ripe",
		"ready": true,
		"tags": ["harvest", "reap", "pick", "farmer", "gather crops", "farmhand", "gardener"],
	},
	"gather": {
		"says": "go out past the town and dig, fell or quarry a material",
		"ready": true,
		"tags": ["dig", "mine", "miner", "quarry", "fell", "lumberjack", "woodcutter",
			"logger", "gather", "fetch", "labourer", "forager"],
	},

	# --- animals ------------------------------------------------------------
	"stock": {
		"says": "bring animals back and turn them out somewhere",
		"ready": true,
		"tags": ["hen", "hens", "sheep", "cow", "cows", "animal", "animals", "livestock",
			"shepherd", "herder", "rancher", "farmer", "flock", "herd", "drover"],
	},
	"collect": {
		"says": "go round the animals and pick up what they have left — eggs, wool, milk",
		"ready": true,
		"tags": ["egg", "eggs", "milk", "wool", "collect", "shepherd", "farmer",
			"dairy", "farmhand", "gather produce"],
	},

	# --- talking ------------------------------------------------------------
	"speak": {
		"says": "say something out loud — greet, announce, report back",
		"ready": true,
		"tags": ["talk", "speak", "greet", "announce", "crier", "herald", "host", "report"],
	},
	"answer": {
		"says": "answer questions about the town from its records",
		"ready": true,
		"tags": ["answer", "clerk", "steward", "advisor", "record", "know", "ask"],
	},

	# --- running the place --------------------------------------------------
	"delegate": {
		"says": "give one of the other hired people an order, in your own words",
		"ready": true,
		"tags": ["foreman", "manager", "mayor", "boss", "overseer", "steward",
			"captain", "chief", "delegate", "in charge", "run the town", "supervisor"],
	},
	"recruit": {
		"says": "find somebody in the town and take them on as a given job",
		"ready": true,
		"tags": ["recruit", "recruiter", "hire", "hiring", "headhunter", "foreman",
			"manager", "steward", "mayor"],
	},
	"report": {
		"says": "give an account of the stores, the purse and the town",
		"ready": true,
		"tags": ["accountant", "treasurer", "bookkeeper", "report", "steward",
			"clerk", "auditor", "quartermaster", "manager"],
	},

	# --- trades, land works, and what is still to come ------------------------
	# The planned ones (ready: false) are engine work, named plainly. They are
	# here so a role can be defined against them today and the town can say
	# what it lacks.
	"drive": {
		"says": "drive you, or goods, from one place to another",
		"ready": false, "needs": "a vehicle to drive",
		"tags": ["drive", "driver", "taxi", "coach", "carriage", "cart", "chauffeur", "transport"],
	},
	"carry": {
		"says": "carry goods from one store to another",
		"ready": false, "needs": "goods that can be held",
		"tags": ["carry", "porter", "haul", "courier", "delivery", "deliver", "load"],
	},
	"trade": {
		"says": "sell from the stores, or buy in, at the market",
		"ready": true,
		"tags": ["trade", "trader", "merchant", "sell", "buy", "market", "shop", "vendor", "dealer"],
	},
	"cook": {
		"says": "turn food into meals at an oven — worth more than what went in",
		"ready": true,
		"tags": ["cook", "chef", "kitchen", "meal", "bake", "baker", "food"],
	},
	"craft": {
		"says": "make tools out of timber and plank at a bench",
		"ready": true,
		"tags": ["craft", "make", "smith", "blacksmith", "tailor", "potter", "artisan", "tools"],
	},
	"repair": {
		"says": "mend a building that has been damaged",
		"ready": false, "needs": "buildings that can be damaged",
		"tags": ["repair", "mend", "fix", "maintain", "handyman"],
	},
	"demolish": {
		"says": "take a building down and salvage some of its material",
		"ready": true,
		"tags": ["demolish", "tear down", "knock down", "remove", "clear", "wrecker"],
	},
	"pave": {
		"says": "lay a road between two places",
		"ready": true,
		"tags": ["road", "pave", "path", "street", "paver", "roadbuilder"],
	},
	"level": {
		"says": "flatten a piece of ground",
		"ready": true,
		"tags": ["level", "flatten", "dig out", "excavate", "terrace", "earthwork", "landscaper"],
	},
	"plant_tree": {
		"says": "plant trees",
		"ready": true,
		"tags": ["tree", "trees", "forester", "orchard", "hedge", "arborist", "plant trees"],
	},
	"water": {
		"says": "water the crops so they grow at the wet rate",
		"ready": true,
		"tags": ["water", "irrigate", "gardener", "farmer"],
	},
	"tend": {
		"says": "feed and see to the animals so they give twice as often for a while",
		"ready": true,
		"tags": ["tend", "feed", "look after", "vet", "shepherd", "herder", "stable hand", "groom"],
	},
	"fish": {
		"says": "fish the water's edge for food",
		"ready": true,
		"tags": ["fish", "fisher", "fisherman", "angler", "net"],
	},
	"hunt": {
		"says": "hunt the woods for food",
		"ready": true,
		"tags": ["hunt", "hunter", "trap", "trapper", "game"],
	},
	"defend": {
		"says": "stand guard and see off trouble",
		"ready": false, "needs": "anything to defend against",
		"tags": ["defend", "fight", "soldier", "guard", "warrior", "protect", "militia", "knight"],
	},
	"heal": {
		"says": "treat the sick and the hurt",
		"ready": false, "needs": "sickness and injury",
		"tags": ["heal", "doctor", "nurse", "medic", "physician", "healer", "treat"],
	},
	"teach": {
		"says": "teach another person a skill, over a few hours",
		"ready": true,
		"tags": ["teach", "teacher", "tutor", "train", "instruct", "school", "mentor"],
	},
	"decorate": {
		"says": "dress up the front of a building",
		"ready": true,
		"tags": ["decorate", "paint", "painter", "flowers", "beautify", "dress", "florist"],
	},
	"clean": {
		"says": "keep a place swept and tidy",
		"ready": false, "needs": "dirt",
		"tags": ["clean", "sweep", "cleaner", "tidy", "janitor", "maid", "wash"],
	},
}


static func known(id: String) -> bool:
	return LIST.has(id)


static func is_ready(id: String) -> bool:
	return LIST.has(id) and bool(LIST[id]["ready"])


static func says(id: String) -> String:
	return str(LIST.get(id, {}).get("says", id))


## Why a planned capability cannot be done yet, for the worker to say.
static func lacks(id: String) -> String:
	return str(LIST.get(id, {}).get("needs", "the means"))


static func ready_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in LIST:
		if bool(LIST[id]["ready"]):
			out.append(id)
	return out


static func all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in LIST:
		out.append(id)
	return out


## The catalogue as the model is shown it when composing a role. Planned
## entries are listed, because a role is a description of a job and not a
## promise the town can keep today — but they are marked, so the model can say
## so in the character it writes.
static func describe_for_role() -> String:
	var lines: Array[String] = []
	for id: String in LIST:
		var c: Dictionary = LIST[id]
		var mark := "" if bool(c["ready"]) else "   (not yet in this town: needs %s)" % str(c["needs"])
		lines.append("- %s — %s%s" % [id, str(c["says"]), mark])
	return "\n".join(lines)


## Score every capability against a description by its tags. The offline
## composer: crude, but it makes "shepherd" come out as stock, enclose and
## collect without anybody having to ask a model, which is what an exported
## build without a key has to do.
static func match_description(text: String) -> Dictionary:
	var t := " %s " % text.to_lower().replace(",", " ").replace(".", " ") \
		.replace("-", " ").replace("/", " ")
	var scores := {}
	for id: String in LIST:
		var n := 0
		for tag: String in LIST[id]["tags"]:
			if t.find(" %s " % tag) >= 0:
				n += 1
		if n > 0:
			scores[id] = n
	return scores
