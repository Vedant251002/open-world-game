class_name Postcard
## The few sentences under a photograph of the village.
##
## Offline it is a template filled from the town's own numbers; with a key it
## is one short model call (see PhotoMode, which makes at most one per
## in-game day). Either way the facts come from the records.

const TEMPLATES := 4


## What the caption is told. `stats`: name, day, buildings, people, chronicle.
static func stats_for(realm: Realm, town: Town, crew: Crew, clock: GameClock) -> Dictionary:
	var name := "My Village"
	if realm != null and realm.kingdom_name.strip_edges() != "" \
			and realm.kingdom_name.to_lower() != "the town":
		name = realm.kingdom_name.strip_edges()
	var people := 0
	if realm != null and realm.population != null:
		people = realm.population.count()
	elif crew != null:
		people = crew.workers.size()
	var line := ""
	if realm != null and realm.chronicle != null:
		var recent := realm.chronicle.recent(1)
		if not recent.is_empty():
			line = str(recent[0]["text"]).strip_edges()
	return {
		"name": name, "day": clock.day if clock != null else 1,
		"buildings": town.buildings.size() if town != null else 0,
		"people": people, "chronicle": line,
	}


static func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## Offline caption. `variant` picks the template, so the regenerate button can
## cycle and the same day always reads the same way.
static func offline(stats: Dictionary, variant: int = -1) -> String:
	var name := str(stats["name"])
	var day := int(stats["day"])
	var b := int(stats["buildings"])
	var p := int(stats["people"])
	var chron := str(stats.get("chronicle", "")).trim_suffix(".")
	if variant < 0:
		variant = day + b
	var homes := _plural(b, "building", "buildings")
	var folk := _plural(p, "soul", "souls")
	var out := ""
	match variant % TEMPLATES:
		0:
			out = "%s, day %d. %s standing, %s about the place." % [name, day, homes.capitalize(), folk]
		1:
			out = "Wish you were here. %s has %s and %s, and it is only day %d." % [name, homes, folk, day]
		2:
			out = "Day %d in %s: %s up, %s getting on with it." % [day, name, homes, folk]
		_:
			out = "%s at day %d. %s, %s, and the kettle is on." % [name, day, homes.capitalize(), folk]
	if chron != "":
		out += " " + chron + "."
	return out


static func ai_system() -> String:
	return "You write the caption on the back of a postcard of a small voxel village. " \
		+ "One or two warm, slightly literary sentences, at most 30 words, in plain text. " \
		+ "Use only the facts given. No quotation marks, no hashtags, no emoji."


static func ai_user(stats: Dictionary) -> String:
	var s := "Village: %s. Day %d. %d buildings. %d people." % [
		stats["name"], int(stats["day"]), int(stats["buildings"]), int(stats["people"])]
	if str(stats.get("chronicle", "")) != "":
		s += " Latest news: %s" % stats["chronicle"]
	return s


## Tidies a model reply into something that fits under a picture.
static func clean(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ").replace("\"", "")
	if t.length() > 180:
		t = t.substr(0, 177).strip_edges() + "..."
	return t
