extends Node
class_name Chronicle
## The history of the kingdom, one line at a time.
##
## Everything that happens and matters is written here by whichever system it
## happened in: a raid beaten off, a marriage, a bad harvest, a decree. It is
## what the crew read from when you ask "what happened yesterday", and it is
## what makes a kingdom feel like it has been going on without you — a town
## with no past is a level, and a level is not a place.

const KEEP := 400

var realm: Realm
var entries: Array[Dictionary] = []      ## {day, hour, kind, text}


func setup(r: Realm) -> void:
	realm = r
	add("founding", "The town was founded around the well.")


func add(kind: String, text: String) -> void:
	var day := realm.clock.day if realm != null and realm.clock != null else 1
	var hour := realm.clock.hour if realm != null and realm.clock != null else 8.0
	entries.append({"day": day, "hour": hour, "kind": kind, "text": text})
	if entries.size() > KEEP:
		entries = entries.slice(entries.size() - KEEP)


func recent(n: int) -> Array[Dictionary]:
	if entries.size() <= n:
		return entries.duplicate()
	return entries.slice(entries.size() - n)


func on_day(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if int(e["day"]) == day:
			out.append(e)
	return out


func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if str(e["kind"]) == kind:
			out.append(e)
	return out


## "what happened today / yesterday / lately / on day 3"
func try_answer(_worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if not (Realm.has_phrase(t, ["what happened", "what has happened", "any news",
			"what is new", "what's new", "whats new", "tell me the news",
			"what have i missed", "history", "chronicle"])):
		return ""
	var today := realm.clock.day
	var lines: Array[Dictionary] = []
	var when := "lately"
	if t.find("yesterday") >= 0:
		lines = on_day(today - 1)
		when = "yesterday"
	elif t.find("today") >= 0:
		lines = on_day(today)
		when = "today"
	elif t.find("day ") >= 0:
		var d := Realm.count_in(t, -1)
		if d > 0:
			lines = on_day(d)
			when = "on day %d" % d
	else:
		lines = recent(5)
	if lines.is_empty():
		return "Nothing worth telling %s." % when
	var parts: Array[String] = []
	for e: Dictionary in lines.slice(maxi(lines.size() - 5, 0)):
		parts.append(str(e["text"]).trim_suffix("."))
	return "%s: %s." % [when.capitalize(), "; ".join(parts)]


func describe(n: int = 6) -> String:
	var parts: Array[String] = []
	for e: Dictionary in recent(n):
		parts.append("day %d: %s" % [int(e["day"]), str(e["text"])])
	return "\n".join(parts)


func snapshot() -> Dictionary:
	return {"entries": entries}


func restore(d: Dictionary) -> void:
	entries.clear()
	for e: Variant in d.get("entries", []):
		if e is Dictionary:
			entries.append(e)
