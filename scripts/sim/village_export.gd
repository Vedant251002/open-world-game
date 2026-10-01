extends RefCounted
class_name VillageExport
## A village as a short piece of text that anybody can paste into their game.
##
## "Share my village" turns the town into a code: seed + landscape + identity,
## every building as the spec it was generated from and the plot it stands on,
## the people (name, trade, temperament, a few memories), a few chronicle
## lines and the date. JSON, deflated, base64'd, with a short header:
##
##     DV1.<raw size>.<base64>
##
## Nothing is hosted anywhere: the code IS the village. "Visit a village"
## (village_visit.gd) turns one back into a read-only world.
##
## A code comes from outside, so it is untrusted input. decode() never trusts a
## type, a length or a number: oversized text is refused before it is
## decompressed, the decompression is capped at the size the header claims, and
## the result is rebuilt from scratch through sanitise(), which keeps only
## fields it knows, with known archetypes, materials, modules and roles, bounded
## counts, bounded strings and bounded numbers. Anything structurally wrong
## rejects the whole code with a reason; soft values (a trait of 7.0) are
## clamped. The Validator and the generator then check every spec again when
## the building is actually raised.

const VERSION := 1
const PREFIX := "DV1"
const MAX_CODE_CHARS := 60000          ## the pasted text
const MAX_RAW_BYTES := 200000          ## the JSON, uncompressed
const MAX_BUILDINGS := 48
const MAX_CREW := 24
const MAX_MODULES := 20
const MAX_CHRONICLE := 8
const MAX_MEMORIES := 3
const MAX_NAME := 22                   ## village name (VillageIdentity.MAX_NAME)
const MAX_PERSON := 16
const MAX_LINE := 140
const MAX_PLOT_ID := 400
const MAX_STORIES := 6
const KNOWN_ROLES := ["citizen", "builder", "shopkeeper", "farmer"]
const TRAITS := ["speed", "literalism", "initiative", "question_threshold", "criticism_sensitivity"]


# ================================================================== exporting

## The village as plain data, from the live game.
static func build_data(identity: VillageIdentity, world_seed: int, town: Town, crew: Crew,
		chronicle: Chronicle, day: int, owner: String = "") -> Dictionary:
	var buildings: Array = []
	for rec: Dictionary in town.buildings:
		var spec: Dictionary = rec.get("spec", {})
		if spec.is_empty():
			spec = _spec_for_archetype(str(rec.get("archetype", "")))
		if spec.is_empty():
			continue                      # nothing known about how it was made
		var patch: VoxelPatch = rec["patch"]
		buildings.append({
			"plot": int(rec["plot_id"]), "gs": int(rec.get("gen_seed", 4242)),
			"street": str(rec.get("street", "")), "spec": spec.duplicate(true),
			"at": [patch.footprint.position.x, patch.footprint.position.y],
		})
	var people: Array = []
	if crew != null:
		for w: Worker in crew.workers:
			if not is_instance_valid(w):
				continue
			var mem := w.memory
			var recalled: Array = []
			for e: Dictionary in mem.episodic:
				var sm := str(e.get("summary", ""))
				if sm != "" and (float(e.get("valence", 0.0)) != 0.0 or str(e.get("kind", "")) == "order"):
					recalled.append(sm)
			recalled = recalled.slice(maxi(recalled.size() - MAX_MEMORIES, 0))
			var prefs: Array = []
			for p: Dictionary in mem.learned_preferences:
				prefs.append(str(p.get("text", "")))
			people.append({
				"name": mem.display_name, "role": w.role.id if w.role != null else "citizen",
				"hired": w.hired, "traits": mem.traits.duplicate(),
				"mem": recalled, "prefs": prefs.slice(0, 2),
			})
	var lines: Array = []
	if chronicle != null:
		for e: Dictionary in chronicle.recent(MAX_CHRONICLE):
			lines.append({"day": int(e["day"]), "text": str(e["text"])})
	var dt := Time.get_date_dict_from_system()
	return {
		"v": VERSION, "name": identity.village_name, "colour": identity.colour_idx,
		"emblem": identity.emblem_idx, "landscape": identity.landscape, "seed": world_seed,
		"day": day, "tier": town.tier, "owner": owner,
		"date": "%04d-%02d-%02d" % [int(dt["year"]), int(dt["month"]), int(dt["day"])],
		"buildings": buildings, "crew": people, "chronicle": lines,
	}


## For a record whose generation was never kept (a building from an old save):
## the stock spec of the same name, if the library has one.
static func _spec_for_archetype(arch: String) -> Dictionary:
	for s: Dictionary in GenTest.specs():
		if str(s.get("archetype", "")) == arch:
			return s
	return {}


static func encode(data: Dictionary) -> String:
	var raw := JSON.stringify(data).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return "%s.%d.%s" % [PREFIX, raw.size(), Marshalls.raw_to_base64(packed)]


# ================================================================== importing

## {ok: true, data} or {ok: false, error}. `data` is already sanitised.
static func decode(code_text: String) -> Dictionary:
	if code_text.length() > MAX_CODE_CHARS * 2:
		return _fail("That is far too long to be a village code.")
	# Pasted text wraps, picks up spaces and quotes.
	var code := code_text.strip_edges()
	for junk: String in ["\n", "\r", "\t", " ", "\"", "'", "`"]:
		code = code.replace(junk, "")
	if code.length() > MAX_CODE_CHARS:
		return _fail("That code is too long (the limit is %d characters)." % MAX_CODE_CHARS)
	if code == "":
		return _fail("Paste a village code first.")
	var parts := code.split(".")
	if parts.size() != 3 or parts[0] != PREFIX:
		return _fail("That does not look like a village code. It should begin with %s." % PREFIX)
	if not parts[1].is_valid_int() or parts[1].length() > 7:
		return _fail("The code's header is damaged.")
	var raw_size := int(parts[1])
	if raw_size < 20 or raw_size > MAX_RAW_BYTES:
		return _fail("The code claims a size no village has.")
	var b64 := str(parts[2])
	for i in b64.length():
		var ch := b64.unicode_at(i)
		var ok := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) \
			or ch == 43 or ch == 47 or ch == 61 or ch == 45 or ch == 95
		if not ok:
			return _fail("The code has characters a village code cannot contain.")
	b64 = b64.replace("-", "+").replace("_", "/")
	var packed := Marshalls.base64_to_raw(b64)
	if packed.is_empty() or packed.size() > MAX_CODE_CHARS:
		return _fail("The code could not be read.")
	# Capped at the size the header claims, which is itself capped.
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return _fail("The code is damaged: it does not unpack to the size it claims.")
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return _fail("The code unpacked, but not to a village.")
	return sanitise(json.data)


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "error": why}


# ============================================================== sanitising

## Rebuilds a village from untrusted data, keeping only what is understood.
static func sanitise(raw: Dictionary) -> Dictionary:
	if not _is_num(raw.get("v", null)) or int(raw["v"]) != VERSION:
		return _fail("This village code is from a different version of the game.")
	var out := {"v": VERSION}
	var name := clean_text(raw.get("name", ""), MAX_NAME)
	if name == "":
		return _fail("The village has no name.")
	out["name"] = name
	out["owner"] = clean_text(raw.get("owner", ""), 24)
	if not _is_num(raw.get("seed", null)):
		return _fail("The village has no seed.")
	var seed_v := float(raw["seed"])
	if seed_v != floor(seed_v) or seed_v < 0.0 or seed_v > 2147483647.0:
		return _fail("The village's seed is out of range.")
	out["seed"] = int(seed_v)
	out["colour"] = clampi(int(_num(raw.get("colour", 0), 0)), 0, VillageIdentity.COLOURS.size() - 1)
	out["emblem"] = clampi(int(_num(raw.get("emblem", 0), 0)), 0, VillageIdentity.EMBLEMS.size() - 1)
	var land := str(raw.get("landscape", "")) if raw.get("landscape", "") is String else ""
	out["landscape"] = land if VillageIdentity.LANDSCAPES.has(land) else ""
	out["day"] = clampi(int(_num(raw.get("day", 1), 1)), 1, 100000)
	out["tier"] = clampi(int(_num(raw.get("tier", 1), 1)), 1, 5)
	var date := str(raw.get("date", "")) if raw.get("date", "") is String else ""
	out["date"] = date if _is_date(date) else ""

	# --- buildings
	var braw: Variant = raw.get("buildings", [])
	if not (braw is Array):
		return _fail("The buildings are not a list.")
	if (braw as Array).size() > MAX_BUILDINGS:
		return _fail("Too many buildings (the limit is %d)." % MAX_BUILDINGS)
	var buildings: Array = []
	var used := {}
	for b: Variant in braw as Array:
		if not (b is Dictionary):
			return _fail("A building is not a record.")
		var bd: Dictionary = b
		if not _is_num(bd.get("plot", null)):
			return _fail("A building has no plot.")
		var plot := int(bd["plot"])
		if plot < 0 or plot > MAX_PLOT_ID:
			return _fail("A building stands on a plot that cannot exist.")
		if used.has(plot):
			continue                      # two on one plot: keep the first
		used[plot] = true
		var spec := sanitise_spec(bd.get("spec", null))
		if spec.is_empty():
			return _fail("A building has a design this game does not know.")
		var gs := int(_num(bd.get("gs", 0), 0))
		var at: Array = [0, 0]
		if bd.get("at", null) is Array and (bd["at"] as Array).size() == 2:
			at = [clampi(int(_num((bd["at"] as Array)[0], 0)), -100000, 100000),
				clampi(int(_num((bd["at"] as Array)[1], 0)), -100000, 100000)]
		buildings.append({"plot": plot, "gs": clampi(gs, 0, 2147483647),
			"street": clean_text(bd.get("street", ""), 28), "spec": spec, "at": at})
	out["buildings"] = buildings

	# --- people
	var craw: Variant = raw.get("crew", [])
	if not (craw is Array):
		return _fail("The people are not a list.")
	if (craw as Array).size() > MAX_CREW:
		return _fail("Too many people (the limit is %d)." % MAX_CREW)
	var people: Array = []
	var names := {}
	for c: Variant in craw as Array:
		if not (c is Dictionary):
			return _fail("A person is not a record.")
		var cd: Dictionary = c
		var pname := clean_text(cd.get("name", ""), MAX_PERSON)
		if pname == "" or names.has(pname.to_lower()):
			continue
		names[pname.to_lower()] = true
		var role := str(cd.get("role", "citizen")) if cd.get("role", "") is String else "citizen"
		if not _known_role(role):
			role = "citizen"
		var traits := {}
		var tr: Variant = cd.get("traits", {})
		for k: String in TRAITS:
			var tv: Variant = (tr as Dictionary).get(k, 0.5) if tr is Dictionary else 0.5
			traits[k] = clampf(float(_num(tv, 0.5)), 0.0, 1.0)
		people.append({"name": pname, "role": role, "hired": bool(cd.get("hired", false)) \
			if cd.get("hired", false) is bool else false, "traits": traits,
			"mem": _lines(cd.get("mem", []), MAX_MEMORIES), "prefs": _lines(cd.get("prefs", []), 2)})
	out["crew"] = people

	# --- history
	var hraw: Variant = raw.get("chronicle", [])
	if not (hraw is Array):
		return _fail("The chronicle is not a list.")
	var hist: Array = []
	for h: Variant in hraw as Array:
		if hist.size() >= MAX_CHRONICLE:
			break
		if h is Dictionary:
			var t := clean_text((h as Dictionary).get("text", ""), MAX_LINE)
			if t != "":
				hist.append({"day": clampi(int(_num((h as Dictionary).get("day", 1), 1)), 0, 100000),
					"text": t})
	out["chronicle"] = hist
	out["ok"] = true
	return {"ok": true, "data": out}


## One building design, rebuilt from known parts. {} when it is not one.
static func sanitise_spec(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var s: Dictionary = v
	var arch := str(s.get("archetype", "")) if s.get("archetype", "") is String else ""
	if Vocabulary.archetype_tier(arch) <= 0:
		return {}
	var fp: Variant = s.get("footprint", null)
	if not (fp is Array) or (fp as Array).size() != 2 or not _is_num((fp as Array)[0]) \
			or not _is_num((fp as Array)[1]):
		return {}
	var fw := clampi(int(float((fp as Array)[0])), 7, 60)
	var fd := clampi(int(float((fp as Array)[1])), 7, 60)
	var out := {
		"kind": "building", "archetype": arch,
		"tech_tier": clampi(int(_num(s.get("tech_tier", 1), 1)), 1, 4),
		"footprint": [fw, fd],
		"stories": clampi(int(_num(s.get("stories", 1), 1)), 1, MAX_STORIES),
		"orientation": _pick(s.get("orientation", ""), Vocabulary.ORIENTATIONS, "face_street"),
		"roof": _pick(s.get("roof", ""), Vocabulary.ROOFS, "gable"),
		"sign": clean_text(s.get("sign", ""), 24),
	}
	var mats := {}
	var mraw: Variant = s.get("materials", {})
	if mraw is Dictionary:
		for slot: String in ["walls", "roof", "trim", "foundation"]:
			var mv: Variant = (mraw as Dictionary).get(slot, null)
			if mv is String and VoxelTypes.id_of(mv) >= 0:
				mats[slot] = mv
	out["materials"] = mats
	var mods: Array = []
	var mlist: Variant = s.get("modules", [])
	if mlist is Array:
		for m: Variant in mlist as Array:
			if mods.size() >= MAX_MODULES:
				break
			if not (m is Dictionary):
				continue
			var mt := str((m as Dictionary).get("type", "")) if (m as Dictionary).get("type", "") is String else ""
			if not Vocabulary.MODULES.has(mt):
				continue
			var md := {"type": mt,
				"wall": _pick((m as Dictionary).get("wall", ""), Vocabulary.WALLS, "any"),
				"size": _pick((m as Dictionary).get("size", ""), Vocabulary.SIZES, "medium"),
				"priority": _pick((m as Dictionary).get("priority", ""), Vocabulary.PRIORITIES, "optional")}
			var needs: Array = []
			var nraw: Variant = (m as Dictionary).get("needs", [])
			if nraw is Array:
				for n: Variant in nraw as Array:
					if n is String and n in Vocabulary.NEEDS and n not in needs:
						needs.append(n)
			if not needs.is_empty():
				md["needs"] = needs
			var adj: Variant = (m as Dictionary).get("adjacent_to", "")
			if adj is String and Vocabulary.MODULES.has(adj):
				md["adjacent_to"] = adj
			mods.append(md)
	out["modules"] = mods
	return out


static func _known_role(id: String) -> bool:
	return id in KNOWN_ROLES or RoleBook.PRESETS.has(id)


static func _pick(v: Variant, allowed: Array, fallback: String) -> String:
	return str(v) if v is String and v in allowed else fallback


static func _lines(v: Variant, limit: int) -> Array:
	var out: Array = []
	if v is Array:
		for e: Variant in v as Array:
			if out.size() >= limit:
				break
			var t := clean_text(e, MAX_LINE)
			if t != "":
				out.append(t)
	return out


static func _is_num(v: Variant) -> bool:
	return (v is int or v is float) and not is_nan(float(v)) and not is_inf(float(v))


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if _is_num(v) else fallback


static func _is_date(s: String) -> bool:
	if s.length() != 10 or s[4] != "-" or s[7] != "-":
		return false
	return s.substr(0, 4).is_valid_int() and s.substr(5, 2).is_valid_int() and s.substr(8, 2).is_valid_int()


## Text from outside, made safe to put on a label, in a prompt and in a chat
## log: control and bidi characters gone, markup brackets defanged, trimmed and
## capped. Anything that is not a string becomes "".
static func clean_text(v: Variant, limit: int) -> String:
	if not (v is String):
		return ""
	var out := ""
	var s: String = v
	for i in mini(s.length(), limit * 4):
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or (c >= 0x200B and c <= 0x200F) \
				or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) \
				or c == 0xFEFF or c == 0x2028 or c == 0x2029:
			out += " " if c in [9, 10, 13] else ""
			continue
		if c == 91:        # [
			out += "("
		elif c == 93:      # ]
			out += ")"
		elif c == 60 or c == 62 or c == 123 or c == 125 or c == 96 or c == 92:     # < > { } ` \
			out += " "
		else:
			out += char(c)
	out = " ".join(out.split(" ", false)).strip_edges()
	return out.substr(0, limit).strip_edges()
