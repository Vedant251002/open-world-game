extends RefCounted
class_name Validator
## Fail-closed checks either side of generation, per voxel-module-spec.md §6.
##
## A rejection is never an error dialog. It carries a `question` — the line the
## worker walks back and says to your face. That is the difference between a bug
## and a gameplay beat, and it is the whole of design pillar P3.

## "a hut", but "an airport". Workers say these out loud.
static func an(word: String) -> String:
	var w := word.replace("_", " ")
	return ("an " if w.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + w


static func error(code: String, question: String, detail: String = "") -> Dictionary:
	return {"code": code, "question": question, "detail": detail}


# ------------------------------------------------------------- pre-generation

static func check_spec(spec: Dictionary, plot: Plot, ctx: Dictionary) -> Dictionary:
	var tier := int(ctx.get("tier", 1))

	if str(spec.get("kind", "building")) != "building":
		return error("unsupported_kind",
			"I only know how to put up buildings at the moment.")

	# --- is this even a thing we can build yet ---
	#
	# Without this an archetype from a tier above us passed straight through
	# and came out as whatever geometry the fallback happened to hold — ask
	# for an airport in a village of huts and you got a hut, silently. Being
	# told we are not up to it yet is the answer; a hut is not.
	var arch := str(spec.get("archetype", ""))
	if arch != "" and arch not in Vocabulary.archetypes_for_tier(tier):
		var known := Vocabulary.archetype_tier(arch)
		if known > 0:
			return error("archetype_above_tier",
				"We are not up to building %s yet — that needs a bigger town."
				% an(arch), arch)
		return error("unknown_archetype",
			"I would not know where to start with %s." % an(arch), arch)

	# --- enums ---
	var orientation := str(spec.get("orientation", "face_street"))
	if orientation not in Vocabulary.ORIENTATIONS:
		return error("bad_orientation",
			"Which way did you want it to face?", orientation)

	var roof := str(spec.get("roof", "gable"))
	if roof not in Vocabulary.ROOFS:
		return error("bad_roof", "What sort of roof did you have in mind?", roof)

	# --- materials ---
	var mats: Dictionary = spec.get("materials", {})
	for slot: String in ["walls", "roof", "trim", "foundation"]:
		if not mats.has(slot):
			continue
		var mat_name := str(mats[slot])
		if VoxelTypes.id_of(mat_name) < 0:
			return error("unknown_material",
				"I have never worked with %s. What should I use instead?" % mat_name, mat_name)
		if VoxelTypes.tech_tier(VoxelTypes.id_of(mat_name)) > tier:
			return error("material_above_tier",
				"Nobody round here knows how to make %s yet." % mat_name, mat_name)
	if mats.has("walls") and str(mats["walls"]) not in VoxelTypes.STRUCTURAL:
		return error("material_wrong_category",
			"You cannot hold a roof up with %s." % str(mats["walls"]))
	if mats.has("roof") and str(mats["roof"]) not in VoxelTypes.SURFACE \
			and str(mats["roof"]) not in VoxelTypes.STRUCTURAL:
		return error("material_wrong_category",
			"That is not something you can roof with.", str(mats["roof"]))

	# --- footprint ---
	var fp: Variant = spec.get("footprint", null)
	if not (fp is Array) or (fp as Array).size() != 2:
		return error("bad_footprint", "How big did you want it?")
	var fw := float((fp as Array)[0])
	var fd := float((fp as Array)[1])
	# Seven metres is the smallest thing worth calling a building and the
	# smallest the generator will lay out rooms in; the plot check below is
	# what actually stops the big end.
	if fw < 7.0 or fd < 7.0 or fw > 60.0 or fd > 60.0:
		return error("footprint_out_of_range",
			"That is not a size I can build to — anywhere from seven to sixty metres a side.")

	var plot_m := plot.size_m()
	var span := Vector2(fw, fd)
	if plot.street_dir.x != 0:
		span = Vector2(fd, fw)
	if span.x > plot_m.x - 1.0 or span.y > plot_m.y - 1.0:
		return error("footprint_exceeds_plot",
			"It will not fit on that plot — there is only %d by %d metres to work with."
			% [int(plot_m.x), int(plot_m.y)])

	# --- stories ---
	var stories := int(spec.get("stories", 1))
	if stories < 1 or stories > Vocabulary.max_stories(tier):
		return error("bad_stories",
			"I can manage up to %d floors with what we have." % Vocabulary.max_stories(tier))

	# --- modules ---
	var modules: Variant = spec.get("modules", [])
	if not (modules is Array):
		return error("bad_modules", "I could not follow what should go inside.")
	var allowed := Vocabulary.modules_for_tier(tier)
	var present: Array[String] = []
	var module_area := 0.0
	var required_count := 0

	for m: Variant in modules as Array:
		if not (m is Dictionary):
			return error("bad_module_entry", "One of those rooms made no sense to me.")
		var md: Dictionary = m
		var mtype := str(md.get("type", ""))
		if mtype not in allowed:
			if Vocabulary.module_tier(mtype) < 99:
				return error("module_above_tier",
					"We are not up to building a %s yet." % mtype.replace("_", " "), mtype)
			return error("unknown_module",
				"I do not know what a %s is." % mtype.replace("_", " "), mtype)
		present.append(mtype)

		var wall := str(md.get("wall", "any"))
		if wall not in Vocabulary.WALLS:
			return error("bad_wall", "Which wall should the %s go against?" % mtype, wall)
		var size := str(md.get("size", "medium"))
		if size not in Vocabulary.SIZES:
			return error("bad_size", "How big should the %s be?" % mtype, size)
		var priority := str(md.get("priority", "preferred"))
		if priority not in Vocabulary.PRIORITIES:
			return error("bad_priority", "Is the %s essential or not?" % mtype, priority)
		if priority == "required":
			required_count += 1
		for n: Variant in md.get("needs", []):
			if str(n) not in Vocabulary.NEEDS:
				return error("bad_need", "What does a %s need %s for?" % [mtype, str(n)], str(n))
		for f: Variant in [md.get("faces", null)]:
			if f != null and str(f) not in Vocabulary.FACES:
				return error("bad_faces", "Facing what, exactly?", str(f))

		module_area += Vocabulary.size_area(size)

	# adjacent_to must name something in this same spec.
	for m2: Variant in modules as Array:
		var adj := str((m2 as Dictionary).get("adjacent_to", ""))
		if adj != "" and adj not in present:
			return error("dangling_adjacency",
				"You said the %s should be next to the %s, but there is no %s in this plan."
				% [str((m2 as Dictionary).get("type", "room")).replace("_", " "),
					adj.replace("_", " "), adj.replace("_", " ")], adj)

	# Module footprints must sum to at most 80% of the envelope, per §6.
	var envelope := fw * fd * float(stories)
	if module_area > envelope * 0.8:
		return error("modules_exceed_envelope",
			"You have asked for more rooms than will fit in %d by %d metres."
			% [int(fw), int(fd)])

	# needs must be satisfiable on this plot.
	for m3: Variant in modules as Array:
		for need: String in Vocabulary.needs_of(m3 as Dictionary):
			if not _need_satisfiable(need, plot, ctx):
				return error("unsatisfiable_need",
					_need_question(need, str((m3 as Dictionary).get("type", "room"))), need)

	return {}


# ------------------------------------------------------------------ the plan

## The whole step list, checked before the first step starts.
##
## All of it, up front, deliberately. The alternative — validate each step as
## its turn comes — means a two-step order can have its fence built and then be
## refused for the hens, which is the "wall the town cannot finish" failure in
## a new coat: it looks like the order was understood right up until it stops
## halfway. So a plan is accepted whole or refused whole, and the refusal is
## still one sentence a worker says out loud.
static func check_plan(steps: Array, plot: Plot, ctx: Dictionary) -> Dictionary:
	if steps.is_empty():
		return error("empty_plan", "I am not sure what you want me to do.")
	if steps.size() > Steps.MAX_STEPS:
		return error("plan_too_long",
			"That is more than one job — give it to me a piece at a time.")

	# Ids of steps already seen, so a reference can only ever point backwards.
	# Forwards would be a plan that has to be solved before it can be run, and
	# the worker would have to build the pen after putting the hens in it.
	var seen: Dictionary = {}
	for i in steps.size():
		if not (steps[i] is Dictionary):
			return error("bad_step", "I did not follow the second half of that.")
		var step: Dictionary = steps[i]
		var e := check_step(step, seen, plot, ctx)
		if not e.is_empty():
			return e
		var id := str(step.get("id", ""))
		if id != "":
			if seen.has(id):
				return error("duplicate_step_id",
					"I have got muddled — you have asked me for two of the same thing.")
			seen[id] = str(step.get("do", ""))
	return {}


static func check_step(step: Dictionary, seen: Dictionary, plot: Plot,
		ctx: Dictionary) -> Dictionary:
	var tier := int(ctx.get("tier", 1))
	var verb := str(step.get("do", ""))

	# Same two sentences as an unbuildable archetype, and the same distinction:
	# "not yet" and "never heard of it" are different answers and the player is
	# owed the right one.
	if not Steps.known(verb):
		return error("unknown_verb",
			"I would not know how to go about that.", verb)
	if Steps.verb_tier(verb) > tier:
		return error("verb_above_tier",
			"We are not up to that sort of work yet — that needs a bigger town.",
			verb)

	# The role's say. A shepherd asked for a tavern is not a builder for the
	# afternoon; they say what they were taken on for. And a role that was
	# given a capability the town cannot carry out yet says that too, rather
	# than the plan quietly failing somewhere the player cannot see.
	var role: Role = ctx.get("role", null)
	if role != null:
		var cap := Steps.capability_of(verb)
		if not role.can(cap):
			return error("outside_role",
				"That is not my trade — I was taken on as a %s." % role.name, cap)
		if not Capabilities.is_ready(cap):
			return error("capability_not_ready",
				"I was taken on for that, but the town has no %s yet." % Capabilities.lacks(cap),
				cap)

	var schema: Dictionary = Steps.VERBS[verb]
	for field: String in schema["required"]:
		if not step.has(field):
			return error("step_missing_field",
				"You will have to tell me more than that.", "%s.%s" % [verb, field])

	# References resolve backwards, and only to a step that claimed ground.
	# Pointing "put the hens in it" at an errand is not a plan, it is a sentence
	# that parsed.
	for ref: String in Steps.REF_FIELDS:
		if not step.has(ref):
			continue
		var target := str(step[ref])
		if target == "" or target == "here":
			continue
		if not seen.has(target):
			return error("dangling_reference",
				"You have lost me — in what?", "%s.%s" % [verb, ref])
		if not Steps.produces_site(str(seen[target])):
			return error("reference_has_no_ground",
				"There is nowhere to put them — that job does not leave anything to put them in.",
				target)

	match verb:
		"build":
			if not (step.get("spec", null) is Dictionary):
				return error("bad_step", "I did not follow what to build.")
			return check_spec(step["spec"], plot, ctx)
		"enclose":
			return _check_enclose(step, tier)
		"stock":
			return _check_stock(step)
		"sow":
			return _check_sow(step)
		"gather":
			return _check_gather(step)
		"go", "wait", "station":
			return _check_place_step(step, verb)
		"patrol":
			return _check_patrol(step)
		"rest":
			return _check_hours(step, verb)
		"speak":
			if str(step.get("line", "")).strip_edges() == "":
				return error("nothing_to_say", "Say what?")
			return {}
		"scout":
			return _check_scout(step)
		"trade":
			return _check_trade(step)
		"cook", "craft", "fish", "hunt":
			return _check_hours(step, verb)
		"plant_tree":
			var n := int(step.get("count", 1))
			if n < 1 or n > 12:
				return error("bad_count", "I can put in up to a dozen at a go.")
			return {}
		"pave":
			if str(step.get("from", "")).strip_edges() == "" or str(step.get("to", "")).strip_edges() == "":
				return error("no_place", "A road goes from somewhere to somewhere. Which two?")
			if step.has("material"):
				var m := str(step["material"])
				if VoxelTypes.id_of(m) < 0:
					return error("bad_material", "I cannot lay a road in %s." % m, m)
				if VoxelTypes.tech_tier(VoxelTypes.id_of(m)) > tier:
					return error("material_above_tier", "We have no %s yet." % m.replace("_", " "), m)
			if step.has("width"):
				var w := int(step["width"])
				if w < 1 or w > 6:
					return error("bad_width", "Between one and six metres wide.")
			return {}
		"level":
			if step.has("size"):
				var sz: Array = step["size"]
				if sz.size() != 2 or int(sz[0]) < 3 or int(sz[0]) > 24:
					return error("bad_size", "Between three and twenty-four metres a side.")
			return {}
		"teach":
			if str(step.get("who", "")).strip_edges() == "":
				return error("no_pupil", "Teach whom?")
			if str(step.get("skill", "")) not in Steps.SKILLS:
				return error("unknown_skill", "I can teach %s." % ", ".join(Steps.SKILLS),
					str(step.get("skill", "")))
			return _check_hours(step, verb)
		"demolish", "decorate":
			if str(step.get("place", "")).strip_edges() == "":
				return error("no_place", "Which building?")
			return {}
		"delegate":
			if str(step.get("who", "")).strip_edges() == "":
				return error("no_one_named", "Tell whom?")
			if str(step.get("order", "")).strip_edges() == "":
				return error("nothing_to_say", "Tell them what?")
			return {}
		"recruit":
			if str(step.get("role", "")).strip_edges() == "":
				return error("role_needs_name", "Take them on as what?")
			return {}
	return {}


static func _check_trade(step: Dictionary) -> Dictionary:
	if str(step.get("action", "")) not in Steps.TRADE_ACTIONS:
		return error("bad_trade", "Buying or selling?", str(step.get("action", "")))
	var kind := str(step.get("kind", ""))
	if not Town.PRICE.has(kind):
		return error("not_traded", "Nobody at the market deals in %s." % kind.replace("_", " "), kind)
	if step.has("count"):
		var n := int(step["count"])
		if n < 1 or n > 500:
			return error("bad_count", "Between one and five hundred at a time.")
	return {}


static func _check_place_step(step: Dictionary, verb: String) -> Dictionary:
	if verb != "wait" or step.has("place"):
		var place := str(step.get("place", "")).strip_edges()
		if place == "" and verb != "wait":
			return error("no_place", "Where did you want me to go?")
	return _check_hours(step, verb)


static func _check_hours(step: Dictionary, _verb: String) -> Dictionary:
	if step.has("hours"):
		var h := float(step["hours"])
		if h < 0.0 or h > Steps.SHIFT_MAX_HOURS:
			return error("bad_hours",
				"That is longer than a day's work. How long did you mean?")
	return {}


static func _check_patrol(step: Dictionary) -> Dictionary:
	var places: Array = step.get("places", [])
	if places.size() < 2:
		return error("patrol_needs_places",
			"A round needs at least two places to walk between.")
	if places.size() > 6:
		return error("patrol_too_long", "That is a march, not a round. Fewer stops?")
	return _check_hours(step, "patrol")


static func _check_scout(step: Dictionary) -> Dictionary:
	var dir := str(step.get("direction", ""))
	if dir not in Steps.DIRECTIONS:
		return error("bad_direction", "Which way — north, south, east or west?", dir)
	if step.has("distance"):
		var d := int(step["distance"])
		if d < 5 or d > Steps.SCOUT_MAX_M:
			return error("bad_distance",
				"I can scout up to about %d metres out." % Steps.SCOUT_MAX_M)
	return {}


# ------------------------------------------------------------------ a role

## A role as the model, or the offline composer, has proposed it.
##
## The rule is the same one every other check here enforces: nothing gets in
## that is not in the closed list. A role that names a capability the engine
## has never heard of is refused, because a role that "can" do something the
## game cannot is the whole failure this design exists to avoid — a planner
## that confidently schedules nothing.
static func check_role(role: Dictionary) -> Dictionary:
	var name := str(role.get("name", "")).strip_edges()
	if name == "":
		return error("role_needs_name", "What do you want to call the job?")
	var caps: Array = role.get("capabilities", [])
	if caps.is_empty():
		return error("role_has_nothing",
			"I could not make a job out of that. What would they actually do?")
	for c: Variant in caps:
		if not Capabilities.known(str(c)):
			return error("unknown_capability",
				"Nobody in this town knows how to %s." % str(c).replace("_", " "),
				str(c))
	var any_ready := false
	for c2: Variant in caps:
		if Capabilities.is_ready(str(c2)):
			any_ready = true
			break
	if not any_ready:
		return error("role_not_ready_yet",
			"That job is all things the town has no means for yet. It can be written down, but nobody could do it today.")
	return {}


static func _check_enclose(step: Dictionary, tier: int) -> Dictionary:
	var size: Array = step.get("size", [])
	if size.size() != 2:
		return error("bad_enclosure_size", "How big did you want it?")
	var w := int(size[0])
	var d := int(size[1])
	if w < Steps.ENCLOSURE_MIN_M or d < Steps.ENCLOSURE_MIN_M:
		return error("enclosure_too_small",
			"That is too small to keep anything in. How big did you want it?")
	if w > Steps.ENCLOSURE_MAX_M or d > Steps.ENCLOSURE_MAX_M:
		return error("enclosure_too_large",
			"That is not a pen, that is a field with a fence round it. Smaller?")

	var mat := str(step.get("material", "timber"))
	if VoxelTypes.id_of(mat) < 0:
		return error("bad_material",
			"I have never worked with %s. What should I use?" % mat.replace("_", " "),
			mat)
	if VoxelTypes.tech_tier(VoxelTypes.id_of(mat)) > tier:
		return error("material_above_tier",
			"We have no %s in this town yet." % mat.replace("_", " "), mat)

	var gate := str(step.get("gate", "worker_choice"))
	if gate not in Steps.GATES:
		return error("bad_gate", "Which side did you want the gate?", gate)
	return {}


static func _check_stock(step: Dictionary) -> Dictionary:
	var species := str(step.get("species", ""))
	if species not in Steps.SPECIES:
		return error("unknown_species",
			"We have no %s anywhere near this town." % species.replace("_", " "),
			species)
	var n := int(step.get("count", 0))
	if n < 0 or n > Steps.COUNT_MAX:
		return error("bad_count",
			"I cannot drive that many back on my own. How many did you want?",
			str(n))
	return {}


static func _check_sow(step: Dictionary) -> Dictionary:
	var crop := str(step.get("crop", "wheat"))
	if crop not in Steps.CROPS:
		return error("unknown_crop",
			"I have no %s seed. Wheat or carrots?" % crop.replace("_", " "), crop)
	if step.has("size"):
		var size: Array = step["size"]
		if size.size() != 2:
			return error("bad_field_size", "How big did you want the field?")
		for n: int in [int(size[0]), int(size[1])]:
			if n < Steps.FIELD_MIN_M or n > Steps.FIELD_MAX_M:
				return error("bad_field_size",
					"A field wants to be between %d and %d metres a side."
					% [Steps.FIELD_MIN_M, Steps.FIELD_MAX_M])
	return {}


static func _check_gather(step: Dictionary) -> Dictionary:
	var mat := str(step.get("material", ""))
	if VoxelTypes.id_of(mat) < 0:
		return error("bad_material",
			"I have never heard of %s." % mat.replace("_", " "), mat)
	if not Resources.gatherable(mat):
		return error("not_gatherable",
			"You cannot dig %s out of the ground — it has to be made."
			% mat.replace("_", " "), mat)
	var units := int(step.get("units", 0))
	if units < 0 or units > Steps.UNITS_MAX:
		return error("bad_units", "That is more than I could carry in a week.",
			str(units))
	return {}


static func _need_satisfiable(need: String, plot: Plot, ctx: Dictionary) -> bool:
	match need:
		"road_access":
			return plot.street_dir != Vector3i.ZERO
		"runway_access":
			return bool(ctx.get("has_runway", false))
		"power":
			return int(ctx.get("tier", 1)) >= 3
		"water":
			return true      # the well serves the whole town at tier 1
		_:
			return true


static func _need_question(need: String, module: String) -> String:
	match need:
		"runway_access":
			return "There is no runway to put a %s beside." % module.replace("_", " ")
		"power":
			return "We have no power in this town yet — how would you run the %s?" \
				% module.replace("_", " ")
	return "I cannot get %s to that plot." % need


# ------------------------------------------------------------ post-generation

static func check_patch(patch: VoxelPatch, gen: BuildingGenerator,
		ctx: Dictionary) -> Dictionary:
	var world: VoxelWorld = ctx["world"]

	# --- no intersection with anything already standing ---
	var e := _check_clear(patch, world, gen)
	if not e.is_empty():
		return e

	# --- watertight, and every room reachable from the entrance ---
	e = _check_enclosure_and_reach(patch, gen)
	if not e.is_empty():
		return e

	# --- every required module actually got placed ---
	var placed: Array[String] = []
	for m: Dictionary in patch.modules:
		placed.append(str(m["type"]))
	for req: String in gen.required_modules():
		if req not in placed:
			return error("required_module_missing",
				"I could not find anywhere sensible for the %s." % req.replace("_", " "), req)

	# --- chimneys and vents must reach open sky ---
	e = _check_flues(patch, gen)
	if not e.is_empty():
		return e

	# --- props must not be inside a wall ---
	for p: Dictionary in patch.props:
		var v := VoxelWorld.to_voxel(p["pos"])
		var l := v - patch.origin
		if patch.solid_at(l.x, l.y, l.z):
			return error("prop_clipping",
				"I could not fit the furniture in there.", str(p.get("type", "")))

	return {}


## Nothing may be written where a building, a road or protected terrain already
## is. The plot itself is levelled ground, so only real structures matter.
static func _check_clear(patch: VoxelPatch, _world: VoxelWorld,
		gen: BuildingGenerator) -> Dictionary:
	var occupied: Array = ctx_occupied(gen)
	var rect := gen.footprint_rect_world()
	for other: Rect2i in occupied:
		if other.intersects(rect):
			return error("plot_occupied",
				"There is already something standing there.")
	# Roads are not buildable. There is no map edge to fall off any more, so the
	# only spatial refusal left is building across a street.
	var village: Village = gen.ctx["village"]
	for z in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if village.is_road(x, z):
				return error("blocks_road",
					"That would put the wall across the street.")
	return {}


static func ctx_occupied(gen: BuildingGenerator) -> Array:
	var out: Array = []
	for r: Variant in gen.ctx.get("occupied_rects", []):
		out.append(r)
	return out


## Flood fill from outside the patch. If outside air reaches an interior cell,
## the building has a hole in it. Then a second fill from the entrance across
## interior air proves every room is reachable.
static func _check_enclosure_and_reach(patch: VoxelPatch,
		gen: BuildingGenerator) -> Dictionary:
	var sx := patch.size.x
	var sy := patch.size.y
	var sz := patch.size.z

	# Only the ground story matters for enclosure and reach; upper floors are
	# reached through the stair hole and share the same envelope.
	var y0 := gen.story_base(0) + 1
	var y1 := gen.story_base(0) + BuildingGenerator.CLEAR_H
	var h := y1 - y0 + 1
	if h <= 0:
		return error("degenerate_envelope", "Something went wrong with the walls.")

	var open := PackedByteArray()
	open.resize(sx * h * sz)
	for y in range(y0, y1 + 1):
		for z in sz:
			for x in sx:
				open[(x + z * sx) + (y - y0) * sx * sz] = 0 if patch.solid_at(x, y, z) else 1

	# A doorway is a hole on purpose. Plug every opening before asking whether
	# the envelope leaks, otherwise the front door alone makes the whole
	# interior read as "outside" and the test says nothing at all.
	var sealed := open.duplicate()
	for d: Vector3i in patch.doors:
		var l := d - patch.origin
		for yy in range(l.y - 1, l.y + BuildingGenerator.DOOR_H + 1):
			if yy < y0 or yy > y1:
				continue
			for zz in range(l.z - BuildingGenerator.DOOR_W, l.z + BuildingGenerator.DOOR_W + 1):
				for xx in range(l.x - BuildingGenerator.DOOR_W, l.x + BuildingGenerator.DOOR_W + 1):
					if xx < 0 or zz < 0 or xx >= sx or zz >= sz:
						continue
					sealed[(xx + zz * sx) + (yy - y0) * sx * sz] = 0

	var outside := PackedByteArray()
	outside.resize(open.size())
	var queue: Array[int] = []
	# Seed from the patch border.
	for y in h:
		for z in sz:
			for x in sx:
				if x != 0 and z != 0 and x != sx - 1 and z != sz - 1:
					continue
				var i := (x + z * sx) + y * sx * sz
				if sealed[i] == 1 and outside[i] == 0:
					outside[i] = 1
					queue.append(i)
	_flood(queue, sealed, outside, sx, sz, h)

	var interior := gen.interior
	var leaks := 0
	var reach_seed := -1
	for y in h:
		for z in range(interior.position.y, interior.position.y + interior.size.y):
			for x in range(interior.position.x, interior.position.x + interior.size.x):
				var i := (x + z * sx) + y * sx * sz
				if sealed[i] == 0:
					continue
				if outside[i] == 1:
					leaks += 1
				if reach_seed < 0:
					reach_seed = i
	# A doorway is a legitimate hole, so allow a doorway-sized leak per opening.
	var allowance := (patch.doors.size() + 1) * BuildingGenerator.DOOR_W \
		* BuildingGenerator.DOOR_H * 3
	if leaks > allowance:
		return error("not_watertight",
			"I could not close it up properly — it is open to the weather.",
			"leaks=%d allowance=%d" % [leaks, allowance])

	# Reachability from the front door.
	if patch.doors.is_empty():
		return error("no_entrance", "I could not work out where the door goes.")
	var dl := patch.doors[0] - patch.origin
	var dy := clampi(dl.y - y0, 0, h - 1)
	var start := (dl.x + dl.z * sx) + dy * sx * sz
	if open[start] == 0:
		start = reach_seed
	if start < 0:
		return error("no_interior", "There is no room inside it.")

	var reached := PackedByteArray()
	reached.resize(open.size())
	reached[start] = 1
	_flood([start], open, reached, sx, sz, h)

	for m: Dictionary in patch.modules:
		if int(m["story"]) != 0 or str(m["priority"]) == "optional":
			continue
		# Probe a grid across the room rather than a single point: a chimney or
		# a stair can legitimately occupy the exact centre of a cell.
		var r: Rect2i = m["rect"]
		var bx := r.position.x - patch.origin.x
		var bz := r.position.y - patch.origin.z
		var ok := false
		for pz in range(1, r.size.y - 1, 3):
			for px in range(1, r.size.x - 1, 3):
				var lx := bx + px
				var lz := bz + pz
				if lx < 0 or lz < 0 or lx >= sx or lz >= sz:
					continue
				for yy in h:
					if reached[(lx + lz * sx) + yy * sx * sz] == 1:
						ok = true
						break
				if ok:
					break
			if ok:
				break
		if not ok:
			return error("module_unreachable",
				"You would not be able to get to the %s from the door."
				% str(m["type"]).replace("_", " "), str(m["type"]))
	return {}


static func _flood(queue: Array, open: PackedByteArray, mark: PackedByteArray,
		sx: int, sz: int, h: int) -> void:
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var y := i / (sx * sz)
		var rem := i % (sx * sz)
		var x := rem % sx
		var z := rem / sx
		for d: Vector3i in GreedyMesher.DIRS:
			var nx := x + d.x
			var ny := y + d.y
			var nz := z + d.z
			if nx < 0 or nz < 0 or ny < 0 or nx >= sx or nz >= sz or ny >= h:
				continue
			var j := (nx + nz * sx) + ny * sx * sz
			if open[j] == 1 and mark[j] == 0:
				mark[j] = 1
				queue.append(j)


static func _check_flues(patch: VoxelPatch, gen: BuildingGenerator) -> Dictionary:
	for m: Dictionary in patch.modules:
		var needs: Array = Vocabulary.def(str(m["type"])).get("needs", [])
		if "chimney" not in needs and "ventilation" not in needs:
			continue
		# Check the column the generator actually stood the flue in. The middle
		# of the room is exactly where a chimney is not.
		var flue: Vector2i = m.get("flue", Vector2i(-1, -1))
		var r: Rect2i = m["rect"]
		var lx := flue.x
		var lz := flue.y
		if lx < 0:
			lx = r.position.x - patch.origin.x + r.size.x / 2
			lz = r.position.y - patch.origin.z + r.size.y / 2
		var blocked := false
		for y in range(gen.story_base(int(m["story"])) + 2, patch.size.y):
			if patch.opaque_at(lx, y, lz):
				blocked = true
				break
		if blocked:
			return error("flue_blocked",
				"The smoke from the %s has nowhere to go." % str(m["type"]).replace("_", " "),
				str(m["type"]))
	return {}
