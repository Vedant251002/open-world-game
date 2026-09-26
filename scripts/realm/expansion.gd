extends Node
## Land the town claims, the names its quarters go by, and the roads out.
##
## The founding grid is a few streets around a well. A kingdom grows past
## them: a strip claimed to the north becomes a row of plots the workers can
## build on, a boundary stone every twenty metres says whose it is, and a
## road laid out towards a neighbour makes the way there a road rather than a
## direction. Districts are names on rectangles, so "meet me in the Mill
## Quarter" and "where is the Old Town" mean something.
##
## Roads and claims are budgeted: a worker walks the line and a few dozen
## voxels go down each game hour, so a long road is a thing you watch being
## made and never a frame the player pays for.

const V := VoxelChunk.VOXEL_M
## The nav grid reaches forty metres past the founding bounds; claims stop
## there or the workers could not walk to the new plots.
const MAX_OUT_M := 38.0
const CLAIM_STEP_M := 40.0
const COIN_PER_M := 5
const STONE_EVERY_M := 20.0
const ROAD_VOXELS_PER_HOUR := 160
const ROAD_WIDTH_V := 6
const DIRS := {"north": Vector2i(0, -1), "south": Vector2i(0, 1),
	"east": Vector2i(1, 0), "west": Vector2i(-1, 0)}

var realm: Realm
## Metres claimed beyond the founding bounds, per side.
var claimed: Dictionary = {"north": 0.0, "south": 0.0, "east": 0.0, "west": 0.0}
var districts: Array[Dictionary] = []      ## {name, rect: Rect2i (voxels)}
var _added_plots: Array[Dictionary] = []  ## {origin, size, street, dir, ground}
var _road: Dictionary = {}                ## {worker_id, cells: Array[Vector2i], i}
var _next_plot_id := 1000


func setup(r: Realm) -> void:
	realm = r


# ------------------------------------------------------------------- claims

func bounds_m() -> Rect2:
	var b := realm.village.bounds_v
	var r := Rect2(b.position.x * V, b.position.y * V, b.size.x * V, b.size.y * V)
	r = r.grow_individual(float(claimed["west"]), float(claimed["north"]),
		float(claimed["east"]), float(claimed["south"]))
	return r


func claim(side: String, metres: float, worker: Worker) -> bool:
	if not DIRS.has(side):
		return false
	var have := float(claimed[side])
	var add := minf(metres, MAX_OUT_M - have)
	if add <= 1.0:
		worker.speak("We have all the %s land the roads can reach. Build outward first." % side)
		return true
	var cost := int(add) * COIN_PER_M
	if realm.town.coins < cost:
		worker.speak("Claiming %d metres %s costs %d coins; we have %d." % [int(add), side, cost, realm.town.coins])
		return true
	realm.town.coins -= cost
	claimed[side] = have + add
	var stones := _place_stones(side)
	var plots := _cut_plots(side, have, have + add)
	worker.speak("Claimed %d metres to the %s: %d new plots, and stones to mark it." % [int(add), side, plots])
	realm.note("land", "The town claimed %d metres of land to the %s for %d coins (%d plots, %d stones)." % [
		int(add), side, cost, plots, stones])
	return true


## Sandstone posts along the new edge, on ground, wherever the ground is there.
func _place_stones(side: String) -> int:
	var r := bounds_m()
	var n := 0
	var pts: Array[Vector2] = []
	match side:
		"north":
			for x in range(int(r.position.x), int(r.end.x), int(STONE_EVERY_M)):
				pts.append(Vector2(x, r.position.y))
		"south":
			for x in range(int(r.position.x), int(r.end.x), int(STONE_EVERY_M)):
				pts.append(Vector2(x, r.end.y))
		"east":
			for z in range(int(r.position.y), int(r.end.y), int(STONE_EVERY_M)):
				pts.append(Vector2(r.end.x, z))
		"west":
			for z in range(int(r.position.y), int(r.end.y), int(STONE_EVERY_M)):
				pts.append(Vector2(r.position.x, z))
	for p: Vector2 in pts:
		var col := VoxelWorld.column_of(Vector3(p.x, 0.0, p.y))
		if not realm.world.column_meshable(col.x, col.y):
			continue
		var v := VoxelWorld.to_voxel(Vector3(p.x, 0.0, p.y))
		var y := realm.world.height_at(v.x, v.z)
		if realm.world.get_voxel(Vector3i(v.x, y, v.z)) == VoxelTypes.WATER:
			continue
		realm.world.set_voxel(Vector3i(v.x, y + 1, v.z), VoxelTypes.SANDSTONE)
		realm.world.set_voxel(Vector3i(v.x, y + 2, v.z), VoxelTypes.SANDSTONE)
		n += 1
	return n


## Plots in the new strip, on the same pitch as the founding streets, with
## the street they face being the old edge. The ground is whatever it is.
func _cut_plots(side: String, from_m: float, to_m: float) -> int:
	var village := realm.village
	var b := village.bounds_v
	var pitch := int(Village.ROAD_PITCH / V)
	var half_road := int(Village.ROAD_WIDTH * 0.5 / V)
	var setback := int(Village.PLOT_SETBACK / V)
	var depth := int((to_m - from_m) / V) - half_road - setback * 2
	if depth < 40:
		return 0
	var n := 0
	var along: Array[int] = []
	if side == "north" or side == "south":
		for x in range(b.position.x, b.end.x - pitch + 1, pitch):
			along.append(x)
	else:
		for z in range(b.position.y, b.end.y - pitch + 1, pitch):
			along.append(z)
	for a: int in along:
		var origin := Vector3i()
		var size := Vector2i()
		var dir := Vector3i()
		match side:
			"north":
				origin = Vector3i(a + half_road + setback, 0, b.position.y - int(to_m / V) + setback)
				size = Vector2i(pitch - half_road * 2 - setback * 2, depth)
				dir = Vector3i(0, 0, 1)
			"south":
				origin = Vector3i(a + half_road + setback, 0, b.end.y + int(from_m / V) + half_road + setback)
				size = Vector2i(pitch - half_road * 2 - setback * 2, depth)
				dir = Vector3i(0, 0, -1)
			"east":
				origin = Vector3i(b.end.x + int(from_m / V) + half_road + setback, 0, a + half_road + setback)
				size = Vector2i(depth, pitch - half_road * 2 - setback * 2)
				dir = Vector3i(-1, 0, 0)
			"west":
				origin = Vector3i(b.position.x - int(to_m / V) + setback, 0, a + half_road + setback)
				size = Vector2i(depth, pitch - half_road * 2 - setback * 2)
				dir = Vector3i(1, 0, 0)
		var cx := origin.x + size.x / 2
		var cz := origin.z + size.y / 2
		# Ground not generated yet is taken to be the shelf; a plot on a lake
		# is skipped when the lake is known.
		var gy := realm.world.height_at(cx, cz)
		if gy < 0:
			gy = village.floor_voxel()
		elif realm.world.get_voxel(Vector3i(cx, gy, cz)) == VoxelTypes.WATER:
			continue
		var rec := {"origin": origin, "size": size, "dir": dir, "ground": gy,
			"street": "%s Edge" % side.capitalize()}
		_add_plot(rec)
		_added_plots.append(rec)
		n += 1
	return n


func _add_plot(rec: Dictionary) -> void:
	var p := Plot.new()
	p.id = _next_plot_id
	_next_plot_id += 1
	p.origin = rec["origin"]
	p.size_v = rec["size"]
	p.street_dir = rec["dir"]
	p.street_name = str(rec["street"])
	p.ground_y = int(rec["ground"])
	p.terrain_note = "rough" if p.ground_y != realm.village.floor_voxel() else "level"
	for other: Plot in realm.village.plots:
		if other.centre_m().distance_to(p.centre_m()) < 46.0:
			p.neighbours.append(other.id)
			other.neighbours.append(p.id)
	realm.village.plots.append(p)


# ---------------------------------------------------------------- districts

func district_at(at: Vector3) -> Dictionary:
	var v := VoxelWorld.to_voxel(at)
	for d: Dictionary in districts:
		if (d["rect"] as Rect2i).has_point(Vector2i(v.x, v.z)):
			return d
	return {}


func _name_district(name: String, side: String, at: Vector3) -> void:
	var b := realm.village.bounds_v
	var rect := Rect2i()
	if DIRS.has(side):
		var dir: Vector2i = DIRS[side]
		var half := b.size / 2
		rect = Rect2i(b.position + Vector2i(maxi(dir.x, 0) * half.x, maxi(dir.y, 0) * half.y),
			Vector2i(half.x if dir.x != 0 else b.size.x, half.y if dir.y != 0 else b.size.y))
	else:
		var v := VoxelWorld.to_voxel(at)
		rect = Rect2i(v.x - 60, v.z - 60, 120, 120)
	for d: Dictionary in districts:
		if str(d["name"]).to_lower() == name.to_lower():
			d["rect"] = rect
			return
	districts.append({"name": name, "rect": rect})


# -------------------------------------------------------------------- roads

func start_road(worker: Worker, to: Vector3, label: String) -> bool:
	if not _road.is_empty():
		worker.speak("There is a road being laid already; let it finish.")
		return true
	var from := realm.village.well_pos
	var cells: Array[Vector2i] = []
	var a := VoxelWorld.to_voxel(from)
	var bv := VoxelWorld.to_voxel(to)
	var steps := maxi(absi(bv.x - a.x), absi(bv.z - a.z))
	var seen := {}
	for i in steps + 1:
		var tt := float(i) / float(maxi(steps, 1))
		var cx := int(round(lerpf(a.x, bv.x, tt)))
		var cz := int(round(lerpf(a.z, bv.z, tt)))
		var dx := absi(bv.x - a.x) >= absi(bv.z - a.z)
		for w in range(-ROAD_WIDTH_V / 2, ROAD_WIDTH_V / 2):
			var c := Vector2i(cx, cz + w) if dx else Vector2i(cx + w, cz)
			if seen.has(c):
				continue
			seen[c] = true
			if realm.village.is_paved(c.x, c.y):
				continue
			cells.append(c)
	if cells.is_empty():
		worker.speak("That way is paved already.")
		return true
	_road = {"worker_id": worker.memory.worker_id, "cells": cells, "i": 0, "label": label}
	var hours := float(cells.size()) / float(ROAD_VOXELS_PER_HOUR) + 1.0
	var stand := to
	stand.y = realm.world.ground_m(stand.x, stand.z)
	worker.take_errand_job("station", stand, hours, "Laying a road %s. %d hours of cobbles." % [label, int(hours)],
		{"where": label, "doing": "lay"})
	realm.note("roads", "%s started a road %s." % [worker.display_name(), label])
	return true


func on_hour(_hour: float, _day: int) -> void:
	if _road.is_empty():
		return
	var cells: Array[Vector2i] = _road["cells"]
	var i := int(_road["i"])
	var laid := 0
	while i < cells.size() and laid < ROAD_VOXELS_PER_HOUR:
		var c: Vector2i = cells[i]
		i += 1
		if realm.town.units_of("cobble") <= 0:
			var w: Worker = realm.crew.get_worker(str(_road["worker_id"]))
			if w != null:
				w.speak("Out of cobble; the road stops here.")
			realm.note("roads", "The road %s stopped for want of cobble." % str(_road["label"]))
			_road = {}
			return
		var col := VoxelWorld.column_of(Vector3(c.x * V, 0.0, c.y * V))
		if not realm.world.column_meshable(col.x, col.y):
			continue
		var y := realm.world.height_at(c.x, c.y)
		var here := realm.world.get_voxel(Vector3i(c.x, y, c.y))
		if here == VoxelTypes.GRASS or here == VoxelTypes.DIRT or here == VoxelTypes.SAND:
			realm.world.set_voxel(Vector3i(c.x, y, c.y), VoxelTypes.COBBLE)
			realm.town.stock["cobble"] = int(realm.town.stock["cobble"]) - 1
			laid += 1
	_road["i"] = i
	if i >= cells.size():
		var w2: Worker = realm.crew.get_worker(str(_road["worker_id"]))
		if w2 != null:
			w2.speak("The road %s is laid." % str(_road["label"]))
			if not w2.job_errand.is_empty():
				w2.drop_everything()
		realm.note("roads", "The road %s was finished." % str(_road["label"]))
		_road = {}


# ------------------------------------------------------------------ talking

func _side_in(t: String) -> String:
	for side: String in DIRS:
		if Realm.has_word(t, [side, side + "ern", side + "wards", side + "ward"]):
			return side
	return ""


func verbs() -> Dictionary:
	return {
		"road_out": {
			"says": "lay a road from the well out to the town's edge on one side, or towards a neighbouring town by name",
			"optional": ["side", "town"],
			"types": {"side": ["north", "south", "east", "west"]},
		},
		"claim": {
			"says": "extend the town's ground on one side by some metres",
			"required": ["side"],
			"optional": ["metres"],
			"types": {"side": ["north", "south", "east", "west"], "metres": "int"},
			"instant": true,
		},
		"name_district": {
			"says": "give a name to one side of the town, or to where your employer stands",
			"required": ["name"],
			"optional": ["side"],
			"types": {"side": ["north", "south", "east", "west", "here"]},
			"instant": true,
		},
	}


func run(worker: Worker, step: Dictionary) -> String:
	match str(step.get("do", "")):
		"road_out":
			if not _road.is_empty():
				return "There is a road being laid already; let it finish."
			var town_name := str(step.get("town", "")).strip_edges()
			if town_name != "":
				var nb: Node = realm.system("Neighbours")
				if nb != null and nb.has_method("by_name"):
					var town: Dictionary = nb.call("by_name", town_name)
					if town.is_empty():
						return "I do not know a town called %s." % town_name
					start_road(worker, nb.call("edge_point", town), "towards %s" % town["name"])
					return "started"
			var side := str(step.get("side", ""))
			if not DIRS.has(side):
				return "A road to where? North, south, east, west, or a town by name."
			var d: Vector2i = DIRS[side]
			var r := bounds_m()
			var to := realm.village.well_pos + Vector3(d.x, 0.0, d.y) * (maxf(r.size.x, r.size.y) * 0.5 + 6.0)
			start_road(worker, to, "to the %s edge" % side)
			return "started"
		"claim":
			var side2 := str(step.get("side", ""))
			if not DIRS.has(side2):
				return "Which way? North, south, east or west."
			claim(side2, float(step.get("metres", int(CLAIM_STEP_M))), worker)
			return "done"
		"name_district":
			var name := str(step.get("name", "")).strip_edges().capitalize()
			if name == "" or name.length() > 30:
				return "Call it what?"
			var side3 := str(step.get("side", "here"))
			if not DIRS.has(side3):
				side3 = ""
			_name_district(name, side3, worker.global_position if side3 == "" else Vector3.ZERO)
			worker.speak("The %s it is." % name)
			realm.note("land", "The %s was named the %s." % [side3 + " side" if side3 != "" else "area here", name])
			return "done"
	return "failed"


## The words after the last of the anchors, title-cased: "name the north side
## Mill Quarter" -> "Mill Quarter"; "call this area the Old Town" -> "Old Town".
func _name_after(text: String, anchors: Array) -> String:
	var t := text.strip_edges().trim_suffix(".")
	var low := t.to_lower()
	var best := -1
	for a: String in anchors:
		var i := low.rfind(" " + a + " ")
		if i > best:
			best = i + a.length() + 2
	if best < 0:
		return ""
	var rest := t.substr(best).strip_edges()
	if rest.to_lower().begins_with("the "):
		rest = rest.substr(4)
	if rest.to_lower().begins_with("as "):
		rest = rest.substr(3)
	if rest == "" or rest.length() > 30:
		return ""
	return rest.capitalize()


func try_answer(worker: Worker, text: String) -> String:
	var t := text.to_lower()
	if Realm.has_phrase(t, ["how big is our land", "how much land", "how far does the town",
			"our borders", "how large is the town", "how big is the town's land"]):
		var r := bounds_m()
		var claimed_any := false
		for s: String in claimed:
			if float(claimed[s]) > 0.0:
				claimed_any = true
		var line := "The town holds about %d by %d metres" % [int(r.size.x), int(r.size.y)]
		if claimed_any:
			var bits: Array[String] = []
			for s2: String in claimed:
				if float(claimed[s2]) > 0.0:
					bits.append("%d %s" % [int(claimed[s2]), s2])
			line += ", with %s claimed beyond the old streets" % ", ".join(bits)
		return line + "."
	if Realm.has_phrase(t, ["what is this district", "what is this area called", "where am i",
			"what is this part of town", "which district"]):
		var d := district_at(realm.player.global_position if realm.player != null else worker.global_position)
		if d.is_empty():
			return "This part of town has no name yet. Give it one."
		return "This is the %s." % d["name"]
	for d: Dictionary in districts:
		if t.find(str(d["name"]).to_lower()) >= 0 and Realm.has_phrase(t, ["where is", "where's", "how do i get"]):
			var rect: Rect2i = d["rect"]
			var c := Vector3((rect.position.x + rect.size.x * 0.5) * V, 0.0, (rect.position.y + rect.size.y * 0.5) * V)
			var off := c - realm.village.well_pos
			var dist := Vector2(off.x, off.z).length()
			if dist < 12.0:
				return "The %s is right here around the well." % d["name"]
			return "The %s is about %d metres %s of the well." % [d["name"], int(dist), _compass(off)]
	if Realm.has_phrase(t, ["road", "is the road"]) and not _road.is_empty():
		var cells: Array[Vector2i] = _road["cells"]
		var left := (cells.size() - int(_road["i"])) / ROAD_WIDTH_V
		return "The road %s has about %d metres to go." % [str(_road["label"]), int(left * V)]
	return ""


func hud_lines() -> Array[String]:
	if _road.is_empty():
		return []
	var cells: Array[Vector2i] = _road["cells"]
	var left := (cells.size() - int(_road["i"])) / ROAD_WIDTH_V
	return ["laying road · %d m to go" % int(left * V)]


static func _compass(off: Vector3) -> String:
	var a := fmod(atan2(off.x, -off.z) + TAU, TAU)
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return dirs[int(round(a / (TAU / 8))) % 8]


func snapshot() -> Dictionary:
	var plots: Array = []
	for rec: Dictionary in _added_plots:
		plots.append({"origin": rec["origin"], "size": rec["size"], "dir": rec["dir"],
			"ground": rec["ground"], "street": rec["street"]})
	var ds: Array = []
	for d: Dictionary in districts:
		ds.append({"name": d["name"], "rect": d["rect"]})
	var road := {}
	if not _road.is_empty():
		road = {"worker_id": _road["worker_id"], "cells": _road["cells"], "i": _road["i"], "label": _road["label"]}
	return {"claimed": claimed, "plots": plots, "districts": ds, "road": road}


func restore(d: Dictionary) -> void:
	for s: Variant in d.get("claimed", {}):
		claimed[str(s)] = float(d["claimed"][s])
	for rec: Variant in d.get("plots", []):
		if rec is Dictionary:
			var already := false
			for have: Dictionary in _added_plots:
				if have["origin"] == rec["origin"]:
					already = true
			if not already:
				_added_plots.append(rec)
				_add_plot(rec)
	districts.clear()
	for ds: Variant in d.get("districts", []):
		if ds is Dictionary:
			districts.append({"name": str(ds["name"]), "rect": ds["rect"]})
	var road: Dictionary = d.get("road", {})
	if not road.is_empty():
		var cells: Array[Vector2i] = []
		for c: Variant in road.get("cells", []):
			cells.append(c)
		_road = {"worker_id": str(road["worker_id"]), "cells": cells, "i": int(road["i"]),
			"label": str(road["label"])}
