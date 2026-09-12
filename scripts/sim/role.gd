extends RefCounted
class_name Role
## A job somebody in the town can hold.
##
## Mira, Tobias and Ren were the only three people you could talk to, and they
## were all builders because the game only knew how to build. A role is what
## turns "worker" from the one kind of person there is into one of many: a
## name, a subset of Capabilities, and a character written in prose.
##
## The subset is the point. It is data, chosen from a closed list, and it is
## what the planner is allowed to use when this person is given an order — so
## a shepherd asked to put up a tavern says it is not their trade rather than
## quietly becoming a builder. A role never adds anything to the engine; it
## chooses from what the engine has. That is what makes it safe for the player
## to invent any role they like.

var id := ""
var name := ""
## The player's own words, kept as they were typed. This is the brief the
## character was composed from and what the town remembers being asked for.
var description := ""
var capabilities: Array[String] = []
## One short paragraph about who this person is on the job, in the second
## person, written for the model to become. Empty for a role composed offline.
var character := ""
## Something they do without being told, if the role has such a thing — "walk
## the walls at night", "bring in whatever is ripe each morning". Empty for
## most roles. Not scheduled by anything yet; kept so that a defined role does
## not have to be redefined when it is.
var standing := ""
var created_day := 0
## "model", "fallback" or "builtin" — which composer produced this. Said in the
## roster, because a role composed by keywords from a description is a coarser
## thing than one a model wrote, and the player should know which they got.
var source := "builtin"


static func make(role_id: String, display: String, caps: Array,
		about: String = "") -> Role:
	var r := Role.new()
	r.id = role_id
	r.name = display
	for c: Variant in caps:
		var s := str(c)
		if Capabilities.known(s) and s not in r.capabilities:
			r.capabilities.append(s)
	r.description = about
	return r


func can(capability: String) -> bool:
	return capability in capabilities


## The capabilities this role has that the town can actually carry out today.
func ready_capabilities() -> Array[String]:
	var out: Array[String] = []
	for c: String in capabilities:
		if Capabilities.is_ready(c):
			out.append(c)
	return out


## What the role is waiting on the town for.
func planned_capabilities() -> Array[String]:
	var out: Array[String] = []
	for c: String in capabilities:
		if not Capabilities.is_ready(c):
			out.append(c)
	return out


## "shepherd — stock, enclose, collect, follow", for the roster and the log.
func summary() -> String:
	var ready := ready_capabilities()
	var later := planned_capabilities()
	var s := "%s — %s" % [name, ", ".join(ready) if not ready.is_empty() else "nothing yet"]
	if not later.is_empty():
		s += "  (waiting on: %s)" % ", ".join(later)
	return s


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "description": description,
		"capabilities": capabilities.duplicate(), "character": character,
		"standing": standing, "created_day": created_day, "source": source,
	}


static func from_dict(d: Dictionary) -> Role:
	var r := Role.make(str(d.get("id", "")), str(d.get("name", "")),
		d.get("capabilities", []), str(d.get("description", "")))
	r.character = str(d.get("character", ""))
	r.standing = str(d.get("standing", ""))
	r.created_day = int(d.get("created_day", 0))
	r.source = str(d.get("source", "fallback"))
	return r


## A role id from whatever the player typed: "Night Watchman" -> night_watchman.
static func id_of(text: String) -> String:
	var s := text.strip_edges().to_lower()
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			if not out.ends_with("_") and out != "":
				out += "_"
	return out.trim_suffix("_")
