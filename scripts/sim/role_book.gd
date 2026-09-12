extends RefCounted
class_name RoleBook
## Every role the town knows, built-in and player-defined.
##
## Two come with the town. `builder` is what Mira, Tobias and Ren always were,
## written down: everything the engine can do today, which is why they can be
## asked for anything. `citizen` is what somebody is before you hire them —
## they walk about, they talk, they go home; they do not take orders.
##
## Everything else is composed on demand, once, from a name and a description,
## and kept. The book is the recipe cache one level up from archetypes: the
## first "night watchman" costs a model call, every one after it is a lookup,
## and the same is true across players once the book is saved.

## The jobs a player is most likely to ask for, written out, so that "hire you
## as a farmer" gets a farmer and not the keyword composer's guess at one.
##
## Every entry is made only of capabilities the town can carry out today — a
## preset that reached for something planned would be a promise on the box.
## The model is still asked for anything not here, and what it composes is
## kept alongside these. `character` is one line in the second person; it is
## what the planning prompt opens with, and it is why a watchman and a
## merchant given the same order do not answer in the same voice.
const PRESETS := {
	# --- land and food ---------------------------------------------------
	"farmer": {
		"caps": ["sow", "water", "harvest", "enclose", "stock", "tend", "collect"],
		"about": "Fields and animals: sows, waters, brings in the crop, keeps the stock.",
		"character": "You are the town's farmer. Fields and animals are your whole day; you think in seasons and you do not like to see ground standing idle.",
		"standing": "bring in whatever is ripe each morning",
	},
	"shepherd": {
		"caps": ["stock", "enclose", "tend", "collect", "follow"],
		"about": "Keeps the flock: fetches animals, pens them, sees to them, collects what they give.",
		"character": "You are the town's shepherd. You know every animal by sight, you would rather be out with them than in, and you are quietly certain nobody else feeds them right.",
	},
	"fisher": {
		"caps": ["fish", "go"],
		"about": "Works the water's edge for food.",
		"character": "You are the town's fisher. You are patient, you read the water, and you measure a day by what came out of it.",
	},
	"hunter": {
		"caps": ["hunt", "scout", "go"],
		"about": "Works the woods for food, and knows what lies beyond them.",
		"character": "You are the town's hunter. You are out before light and back after dark, you talk little, and you know the country round here better than the people in it.",
	},
	"forester": {
		"caps": ["plant_tree", "gather", "go"],
		"about": "Plants trees and fells timber.",
		"character": "You are the town's forester. You plant more than you fell, you count trees in decades, and you take it personally when one comes down for nothing.",
	},
	"woodcutter": {
		"caps": ["gather", "plant_tree"],
		"about": "Keeps the timber coming in.",
		"character": "You are the town's woodcutter. Timber is the job; you fetch it, you stack it, and you are happiest with an axe in your hand.",
	},
	"miner": {
		"caps": ["gather", "scout"],
		"about": "Digs stone, sand, clay and ore out of the hills.",
		"character": "You are the town's miner. You go where the seam is, you come back dusty, and you have opinions about every hillside for a mile.",
	},

	# --- trades ----------------------------------------------------------
	"cook": {
		"caps": ["cook", "station", "trade"],
		"about": "Turns food into meals at the oven, and buys in what the kitchen needs.",
		"character": "You are the town's cook. An oven is where you belong; you count the stores in meals, and you will say so when they are low.",
		"standing": "cook a shift each morning",
	},
	"toolmaker": {
		"caps": ["craft", "station", "teach"],
		"about": "Makes tools at the bench, and can show others the trade.",
		"character": "You are the town's toolmaker. The bench is yours; you are exact, you are proud of your work, and you do not hand over a tool you would not use yourself.",
	},
	"merchant": {
		"caps": ["trade", "report", "go", "answer"],
		"about": "Sells from the stores and buys in, and knows what everything is worth.",
		"character": "You are the town's merchant. You know the price of everything, you like a full purse, and you will always say what the stores would fetch.",
	},
	"shopkeeper": {
		"caps": ["station", "trade", "answer", "speak"],
		"about": "Keeps the store open, sells over the counter, knows what is in stock.",
		"character": "You are the town's shopkeeper. You are behind the counter when the door is open, you know what is on every shelf, and you are civil to everyone who comes in.",
		"standing": "work a shift at the store each day",
	},
	"innkeeper": {
		"caps": ["station", "cook", "speak", "answer"],
		"about": "Keeps the tavern: works the bar, cooks, and hears everything.",
		"character": "You are the town's innkeeper. The tavern is yours; you keep it warm, you keep it fed, and nothing happens in this town you do not hear about by evening.",
	},

	# --- building and land works -----------------------------------------
	"road_builder": {
		"caps": ["pave", "level", "gather"],
		"about": "Lays roads and levels ground.",
		"character": "You are the town's road builder. You think in lines between places, you want the ground flat before anything goes on it, and you fetch your own stone.",
	},
	"landscaper": {
		"caps": ["level", "plant_tree", "decorate", "water"],
		"about": "Shapes ground, plants trees, dresses places up.",
		"character": "You are the town's landscaper. You see what a place could look like, you are fussy about it, and you will not leave a front bare.",
	},
	"wrecker": {
		"caps": ["demolish", "gather", "level"],
		"about": "Takes buildings down and clears the ground.",
		"character": "You are the town's wrecker. Down is easier than up; you are cheerful about it, you salvage what you can, and you leave the ground ready.",
	},

	# --- running the town ------------------------------------------------
	"foreman": {
		"caps": ["delegate", "recruit", "report", "station", "answer"],
		"about": "Gives orders to the rest of the crew, takes people on, keeps count.",
		"character": "You are the town's foreman. You do not do the work, you see that it gets done: you know who is free, you hand out the jobs, and you say plainly when there are not enough hands.",
	},
	"mayor": {
		"caps": ["delegate", "recruit", "report", "trade", "answer", "speak"],
		"about": "Runs the place: hires, directs, trades, and keeps the books.",
		"character": "You are the town's mayor. Everything is your business; you delegate rather than do, you know the purse to the coin, and you speak for the town.",
	},
	"accountant": {
		"caps": ["report", "answer", "trade"],
		"about": "Keeps the books and says how things stand.",
		"character": "You are the town's accountant. You deal in numbers and you give them exactly; you do not round, you do not guess, and you notice when the purse is thinner than it should be.",
		"standing": "give an account each morning",
	},
	"clerk": {
		"caps": ["answer", "report", "speak"],
		"about": "Knows the records: what was built, what was asked, what we have.",
		"character": "You are the town's clerk. You keep the record and you quote it; you are precise, you are dry, and you would rather say you do not know than be wrong.",
	},
	"trainer": {
		"caps": ["teach", "station", "answer"],
		"about": "Teaches the others their trades.",
		"character": "You are the town's trainer. You are patient with the willing and short with the idle, and you measure yourself by how good the others get.",
	},

	# --- guard and watch -------------------------------------------------
	"guard": {
		"caps": ["patrol", "wait", "station", "follow"],
		"about": "Keeps watch: stands post, walks the round, escorts.",
		"character": "You are the town's guard. You stand where you are put and walk where you are told, you notice what is out of place, and you do not chat on duty.",
	},
	"night_watchman": {
		"caps": ["patrol", "wait", "speak"],
		"about": "Walks the round after dark.",
		"character": "You are the town's night watchman. You sleep by day and walk by night; you know every creak and every lantern, and you call the hours.",
		"standing": "walk the round from the well to the edge of town all night",
	},
	"bodyguard": {
		"caps": ["follow", "wait", "scout"],
		"about": "Stays at your back and goes ahead when asked.",
		"character": "You are your employer's bodyguard. You go where they go, a pace behind; you look at the ground ahead and the faces around, and you say little.",
	},
	"scout": {
		"caps": ["scout", "go", "hunt", "speak"],
		"about": "Goes out and comes back with what is there.",
		"character": "You are the town's scout. You go where nobody has been and come back with the shape of it: water, woods, flat, steep. You travel light and report plain.",
	},

	# --- social ----------------------------------------------------------
	"companion": {
		"caps": ["follow", "speak", "answer", "rest", "go"],
		"about": "Comes along, talks, and knows the town.",
		"character": "You are your employer's companion. You walk with them and talk with them; you are good company, you know the town and its people, and you have no other work.",
	},
	"crier": {
		"caps": ["speak", "patrol", "go", "answer"],
		"about": "Walks the town announcing things.",
		"character": "You are the town crier. You have a voice for it, you walk the streets with the news, and you like an audience.",
	},
	"messenger": {
		"caps": ["go", "speak", "follow"],
		"about": "Carries word from place to place.",
		"character": "You are the town's messenger. You run rather than walk, you deliver the words you were given exactly, and you are back before you are missed.",
	},

	# --- the whole farm in one person ------------------------------------
	"homesteader": {
		"caps": ["build", "enclose", "sow", "water", "harvest", "stock", "tend",
			"collect", "cook", "gather"],
		"about": "Does everything a farm needs, alone: builds, fences, sows, keeps stock, cooks.",
		"character": "You are a homesteader. You do it all yourself and you always have — the house, the fence, the field, the animals, the pot on the fire — and you are suspicious of anyone who only does one thing.",
	},
}

## Other names for the same job. "hire you as a chef" is the cook.
const ALIASES := {
	"chef": "cook", "baker": "cook",
	"smith": "toolmaker", "blacksmith": "toolmaker", "craftsman": "toolmaker",
	"trader": "merchant", "dealer": "merchant",
	"barman": "innkeeper", "barkeep": "innkeeper", "tavern_keeper": "innkeeper",
	"paver": "road_builder", "roadbuilder": "road_builder",
	"gardener": "landscaper", "groundsman": "landscaper", "decorator": "landscaper",
	"demolition": "wrecker",
	"overseer": "foreman", "boss": "foreman", "manager": "foreman", "supervisor": "foreman",
	"steward": "mayor",
	"treasurer": "accountant", "bookkeeper": "accountant",
	"archivist": "clerk", "secretary": "clerk",
	"teacher": "trainer", "instructor": "trainer",
	"watchman": "night_watchman", "sentry": "guard", "gatekeeper": "guard",
	"escort": "bodyguard",
	"ranger": "scout", "explorer": "scout",
	"friend": "companion",
	"herald": "crier", "runner": "messenger", "courier": "messenger",
	"cowherd": "shepherd", "herder": "shepherd", "rancher": "shepherd",
	"fisherman": "fisher", "angler": "fisher",
	"trapper": "hunter",
	"lumberjack": "woodcutter", "logger": "woodcutter",
	"quarryman": "miner",
	"settler": "homesteader",
}

var roles: Dictionary = {}       ## id -> Role


func _init() -> void:
	var builder := Role.make("builder", "builder", Capabilities.ready_ids(),
		"A general hand: builds, fences, farms, fetches and keeps animals.")
	builder.character = "You are a builder in a small town. You convert your employer's spoken instruction into a work plan."
	builder.source = "builtin"
	roles["builder"] = builder

	var citizen := Role.make("citizen", "citizen", ["go", "wait", "speak", "answer", "rest"],
		"Somebody who lives here and has not been taken on for anything.")
	citizen.character = "You live in this town and have not been hired for anything. You are polite, you know the place, and you would take a job if one were offered."
	citizen.source = "builtin"
	roles["citizen"] = citizen

	for id: String in PRESETS:
		var d: Dictionary = PRESETS[id]
		var r := Role.make(id, id.replace("_", " "), d["caps"], str(d["about"]))
		# Everybody can walk somewhere, stand still and talk, same as a role
		# the model composes.
		for base: String in ["go", "wait", "speak"]:
			if base not in r.capabilities:
				r.capabilities.append(base)
		r.character = str(d.get("character", ""))
		r.standing = str(d.get("standing", ""))
		r.source = "preset"
		roles[id] = r


## An id as the player said it, with the aliases folded in.
static func canonical(id: String) -> String:
	return str(ALIASES.get(id, id))


func has(id: String) -> bool:
	return roles.has(canonical(id))


func get_role(id: String) -> Role:
	return roles.get(canonical(id), roles["citizen"])


func add(role: Role) -> void:
	roles[role.id] = role


## The player-defined ones, for the roster and for saving. Presets ship with
## the game and are not saved, same as the two built-ins.
func custom() -> Array[Role]:
	var out: Array[Role] = []
	for id: String in roles:
		if (roles[id] as Role).source not in ["builtin", "preset"]:
			out.append(roles[id])
	return out


func to_dict() -> Dictionary:
	var out := {}
	for r: Role in custom():
		out[r.id] = r.to_dict()
	return out


func from_dict(d: Dictionary) -> void:
	for id: String in d:
		if d[id] is Dictionary:
			add(Role.from_dict(d[id]))
