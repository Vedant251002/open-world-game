extends RefCounted
class_name RoomLayout
## Furnishes one room the way a person would, rather than by scattering.
##
## The old placer took the room's list of things and dropped each on the next
## free square of a grid: a counter in the middle of the tavern floor, a bed
## alone in a corridor, crates strewn across a shop. Every piece was inside the
## room and none of it looked placed. This lays a room out the way it is
## actually used:
##
##   - the thing the room is FOR goes first, where it belongs — the bed with its
##     head to the quiet wall, the fireplace against the chimney breast, the
##     counter across the shop facing the door with the shelves behind it;
##   - the things that go WITH it go next to it — a nightstand either side of
##     the bed, a chest at its foot, firewood beside the hearth, chairs round
##     the table and tucked under it;
##   - storage lines the walls and fills corners, never the middle of the room;
##   - the way in is kept clear: nothing stands in a doorway's approach, and
##     nothing tall stands in front of a window.
##
## Furniture is packed as real rectangles measured off the prop's own voxels,
## so a 2.2 m bed is a 2.2 m bed and two things can stand a hand's width apart
## without either going through the other.
##
## All coordinates here are patch-local voxels, as floats: a room rect r covers
## [r.position, r.end) and its walls are the voxel lines just outside it.

const V := VoxelChunk.VOXEL_M
## Gap between a prop's back and the plaster, in voxels (about 4 cm).
const CLR := 0.15
## Anything taller than this blocks a window if it stands in front of one. A
## bed's headboard comes just under it; a shelf or a dresser does not.
const TALL_M := 1.4
## How far into a room a doorway's approach is kept free, in voxels.
const DOOR_DEPTH := 5.0
const DIRS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
## Types that give light. One per room at least; the fire counts.
const LIGHT_TYPES := ["lantern", "candle", "hearth_fire", "oven_block", "forge_block",
	"kiln_block"]
## Plain dwellings, where the bed is for two and the table has chairs.
const HOMES := ["cottage", "hut", "house"]
## What stands in for a tall piece where it would cover a window.
const LOW_STAND_IN := {"shelf": "crate", "bread_rack": "flour_sack", "dresser": "chest",
	"wardrobe": "chest"}

var g: BuildingGenerator
var patch: VoxelPatch
var r: Rect2i
var base := 0
var mtype := ""
var arche := ""
var rng: DetRng
var flue := Vector2i(-1, -1)
var flue_side := Vector2i.ZERO
var pref_wall := Vector2i.ZERO      ## the wall the spec asked this module to be on

var occ: Array[Rect2] = []          ## floor taken by furniture
var rugs: Array[Rect2] = []
var clear_zones: Array[Rect2] = []  ## doorway approaches, stairs
var aisle: Array[Rect2] = []        ## room left round each table group
var wall_items: Array = []          ## [n, lo, hi, y0, y1] anything on a wall
var door_runs: Array = []           ## [n, lo, hi] openings in this room's walls
var lights := 0
var placed_types: Array[String] = []


func _init(gen: BuildingGenerator, rect: Rect2i, story_base: int, module_type: String,
		archetype: String, step_rng: DetRng) -> void:
	g = gen
	patch = gen.patch
	r = rect
	base = story_base
	mtype = module_type
	arche = archetype
	rng = step_rng
	_find_doors()
	_keep_stairs_clear()


# ===================================================================== recipes

func furnish(wanted: Array) -> void:
	match mtype:
		"bed_area":
			_bedroom()
		"hearth":
			_living()
		"entrance":
			_entrance()
		"counter":
			_shopfront()
		"seating":
			_hall()
		"oven":
			_bakehouse()
		"storage", "cellar", "warehouse_rack", "stockroom":
			if arche in HOMES:
				_spare()
			else:
				_storeroom()
		"workbench":
			_workshop()
		"stable", "pen":
			_stable()
		"forge":
			_forge()
		"spare_room":
			_spare()
		_:
			_generic(wanted)
	if lights == 0:
		_wall_light()


## A bed with its head to the quiet wall, a nightstand either side, a chest at
## its foot and a rug under the end of it; the press against another wall.
func _bedroom() -> void:
	var walls := _quiet_walls()
	var twin := arche in ["tavern", "inn", "barracks"]
	if twin:
		var ns := against("nightstand", walls, "centre")
		if not ns.is_empty():
			on_top("candle", ns, 0.55)
			for side: int in [-1, 1]:
				var b := beside("bed", ns, side, 0.3)
				if not b.is_empty():
					in_front("chest", b, 0.3)
	else:
		var bed := against("bed_double" if arche in HOMES else "bed", walls, "centre")
		if bed.is_empty():
			bed = against("bed", walls, "centre")
		if not bed.is_empty():
			var lit := false
			for side: int in [-1, 1]:
				var ns2 := beside("nightstand", bed, side, 0.2)
				if not ns2.is_empty() and not lit:
					on_top("candle", ns2, 0.55)
					lit = true
			in_front("chest", bed, 0.4)
			rug_at(_point_ahead(bed, -0.35), bed["f"])
	var others := _without(walls, _wall_of_last())
	against("wardrobe", others, "corner")
	against("washstand", others, "corner")
	against("basket", _walls_all(), "corner")
	_wall_light()


## The fire against the chimney breast with wood stacked beside it, a rug on
## the hearth, the table in the middle of what is left with chairs round it,
## and the dresser on a side wall.
func _living() -> void:
	var fire := fireplace("hearth_fire")
	if not fire.is_empty():
		beside("firewood", fire, 1, 0.3)
		beside("pot", fire, -1, 0.3)
		var hearth_zone := _zone_ahead(fire, 4.5)
		rug_at(_point_ahead(fire, 1.1), fire["f"])
		clear_zones.append(hearth_zone)
	var home := arche in HOMES
	var target := _room_centre()
	if not fire.is_empty():
		target = _room_centre().lerp(_point_ahead(fire, 0.0), -0.25)
	if home:
		dining("table", "chair", target, 1, true)
		if against("dresser", _without(_quiet_walls(), _fire_wall(fire)), "corner").is_empty():
			against("chest", _without(_quiet_walls(), _fire_wall(fire)), "corner")
		against("shelf", _without(_quiet_walls(), _fire_wall(fire)), "corner")
	else:
		dining("table", "stool", target, 1, true, true)
		dining("table", "stool", target, 1, true, true)
		against("barrel", _quiet_walls(), "corner")
	against("basket", _walls_all(), "corner")
	_wall_light()


## A mat inside the door, a bench to sit and pull boots off, a plant.
func _entrance() -> void:
	var front_n := _front_door_wall()
	var side_walls := _without(_quiet_walls(), front_n)
	against("bench", side_walls, "centre")
	against("pot", _walls_all(), "corner")
	against("chest", side_walls, "corner")
	_wall_light()


## The counter across the room facing the way customers come in, the goods on
## the wall behind it, and the shopkeeper's space between the two.
func _shopfront() -> void:
	var back := _back_wall()
	var order: Array[Vector2i] = [back]
	order.append_array(_without(_quiet_walls(), back))
	var counter := {}
	for gap: float in [5.0, 4.5, 4.0]:
		counter = against("counter_block", order, "centre", NAN, gap)
		if not counter.is_empty():
			break
	if counter.is_empty():
		counter = against("counter_block", _quiet_walls(), "centre")
	var behind: Array[String] = ["shelf", "shelf", "barrel"]
	var on_counter := "scale"
	match arche:
		"bakery":
			behind = ["bread_rack", "bread_rack", "flour_sack"]
			on_counter = "bread_tray"
		"tavern", "inn":
			behind = ["shelf", "barrel", "barrel", "barrel"]
			on_counter = "tankard"
	if not counter.is_empty():
		var bn: Vector2i = counter["n"]
		on_top(on_counter, counter, 1.05, Vector2(-0.55, 0.0))
		if on_counter == "tankard":
			on_top("tankard", counter, 1.05, Vector2(0.15, 0.1))
		var c_mid := _along_mid(counter["rect"], bn)
		var spread := [0.0, -6.0, 6.0, -10.0, 10.0]
		var k := 0
		for t: String in behind:
			while k < spread.size():
				var at := c_mid + float(spread[k])
				var got := against(t, [bn], "target", at)
				if got.is_empty() and LOW_STAND_IN.has(t):
					# A window behind the counter: something low that does
					# not cover it, rather than nothing at all.
					got = against(LOW_STAND_IN[t], [bn], "target", at)
				k += 1
				if not got.is_empty():
					break
		if arche in ["tavern", "inn"]:
			for off: float in [-0.7, 0.0, 0.7]:
				in_front("stool", counter, 0.6, off, true)
	# The customer side: goods standing about where people can get at them.
	var sides := _without(_quiet_walls(), back)
	if arche == "store":
		against("barrel", sides, "corner")
		against("crate", sides, "corner")
		against("flour_sack", sides, "corner")
		against("basket", sides, "corner")
	elif arche == "bakery":
		against("basket", sides, "corner")
		against("flour_sack", sides, "corner")
	_wall_light()


## A hall of tables: long tables with a bench either side, laid out with room
## to walk between them, barrels in a corner, two lamps.
func _hall() -> void:
	var big := r.size.x * r.size.y * V * V > 22.0
	var target := _room_centre()
	for _i in 6:
		var got := false
		if big:
			got = dining("table_long", "bench", target, 1, false, true)
		if not got:
			got = dining("table", "stool", target, 1, true, true)
		if not got:
			break
	var corners := _quiet_walls()
	var bar := against("barrel", corners, "corner")
	if not bar.is_empty():
		beside("barrel", bar, 1, 0.1)
		beside("barrel", bar, -1, 0.1)
	_wall_light()
	_wall_light()


## The oven against the chimney with the flour beside it, the baker's bench in
## the middle of the floor, racks of loaves on the side walls.
func _bakehouse() -> void:
	var oven := fireplace("oven_block")
	if not oven.is_empty():
		var s1 := beside("flour_sack", oven, 1, 0.2)
		if not s1.is_empty():
			beside("flour_sack", s1, 1, 0.1)
		beside("peel", oven, -1, 0.2)
		clear_zones.append(_zone_ahead(oven, 3.0))
	var sides := _without(_quiet_walls(), _fire_wall(oven))
	place_free("worktable", _room_centre())
	against("bread_rack", sides, "centre")
	against("bread_rack", sides, "centre")
	against("basket", _walls_all(), "corner")
	_wall_light()


## Shelves along the walls, barrels together in one corner, crates stacked in
## another, sacks wherever there is a gap. Nothing in the middle of the floor —
## except in a big store, where a rack down the middle is what makes it a store
## rather than an empty hall with shelves round the edge.
func _storeroom() -> void:
	var walls := _quiet_walls()
	var area := r.size.x * r.size.y * V * V
	var want_shelves := clampi(int(area / 9.0) + 1, 2, 6)
	var shelves := 0
	for pass_i in 2:
		for n: Vector2i in walls:
			if shelves >= want_shelves:
				break
			var got := against("shelf", [n], "centre" if pass_i == 0 else "corner")
			if got.is_empty():
				got = against("crate", [n], "centre")
			if not got.is_empty():
				shelves += 1
	var clusters := clampi(int(area / 14.0) + 1, 1, 4)
	for _c in clusters:
		var bar := against("barrel", walls, "corner")
		if not bar.is_empty():
			var b2 := beside("barrel", bar, 1, 0.1)
			if b2.is_empty():
				beside("barrel", bar, -1, 0.1)
		var cr := against("crate", walls, "corner")
		if not cr.is_empty():
			on_top("crate", cr, 0.75)
			beside("crate", cr, 1, 0.1)
	if arche in ["workshop", "forge"]:
		place_free("workbench", _room_centre())
		against("lumber", walls, "centre")
		against("lumber", walls, "centre")
		place_free("sawhorse", _room_centre())
	elif area > 30.0:
		# Back-to-back racks down the middle of a big store.
		var mid := place_free("shelf", _room_centre(), Vector2i(0, 1))
		if not mid.is_empty():
			place_free("shelf", (mid["rect"] as Rect2).get_center() - Vector2(0, 2.2),
				Vector2i(0, -1))
	against("flour_sack", walls, "corner")
	against("basket", walls, "corner")
	_wall_light()
	if area > 30.0:
		_wall_light()


## The bench along the long wall with the tools hung above it, a stool at it,
## timber stacked and a sawhorse out on the floor.
func _workshop() -> void:
	var walls := _quiet_walls()
	var wb := against("workbench", walls, "centre")
	if not wb.is_empty():
		wall_mount("tool_rack", [wb["n"]], 1.15, "target", _along_mid(wb["rect"], wb["n"]))
		in_front("stool", wb, -0.6, 0.3, true)
	var others := _without(walls, _wall_of_last())
	against("lumber", others, "corner")
	place_free("sawhorse", _room_centre())
	against("crate", walls, "corner")
	against("barrel", walls, "corner")
	wall_mount("tool_rack", others, 1.15, "centre")
	_wall_light()


func _stable() -> void:
	var walls := _quiet_walls()
	against("trough", walls, "centre")
	for _i in 3:
		var h := against("hay", walls, "corner")
		if not h.is_empty():
			on_top("hay", h, 0.6)
	against("bucket", walls, "corner")
	_wall_light()


func _forge() -> void:
	var f := fireplace("forge_block")
	if f.is_empty():
		f = against("forge_block", _quiet_walls(), "centre")
	if not f.is_empty():
		in_front("anvil", f, 1.2)
		beside("barrel", f, 1, 0.3)
	wall_mount("tool_rack", _quiet_walls(), 1.15, "centre")
	against("crate", _quiet_walls(), "corner")
	_wall_light()


## A room the plan did not name. In a home it is the pantry; anywhere else, a
## box room — but furnished either way, because a bare room reads as unbuilt.
func _spare() -> void:
	var walls := _quiet_walls()
	if arche in HOMES:
		against("shelf", walls, "centre")
		var b := against("barrel", walls, "corner")
		if not b.is_empty():
			beside("barrel", b, 1, 0.1)
		against("flour_sack", walls, "corner")
		against("basket", walls, "corner")
	else:
		against("chest", walls, "centre")
		var c := against("crate", walls, "corner")
		if not c.is_empty():
			on_top("crate", c, 0.75)
		against("stool", walls, "corner")
	_wall_light()


## Anything else: the vocabulary's own list, wall pieces to walls and the rest
## to corners first and open floor after.
func _generic(wanted: Array) -> void:
	for entry: Variant in wanted:
		var e: Array = entry
		var t := str(e[0])
		for _k in int(e[1]):
			if Props.LIGHTS.has(Props.resolve(t)) and Props.mount_y(t) > 0.0:
				_wall_light()
			elif Props.mount_y(t) > 0.0:
				wall_mount(t, _quiet_walls(), Props.mount_y(t), "centre")
			elif Props.wall_backed(t):
				against(t, _quiet_walls(), "centre")
			elif t in ["rug", "mat"]:
				rug_at(_room_centre(), Vector2i(0, 1), t)
			else:
				if against(t, _walls_all(), "corner").is_empty():
					place_free(t, _room_centre())


# =================================================================== placement

## Stands a piece with its back to one of `walls`, trying them in order.
##
## mode: "centre" (middle of the wall first), "corner" (ends first), "target"
## (nearest to `target` along the wall). `gap` is the distance from the wall in
## voxels — the default is flush, a counter stands well out from it.
func against(type: String, walls: Array, mode: String = "centre",
		target: float = NAN, gap: float = CLR) -> Dictionary:
	if not Props.exists(type):
		return {}
	var h := float(Props.extent(type)[4])
	for nv: Variant in walls:
		var n: Vector2i = nv
		var f := -n
		var fp := footprint(type, f)
		var along_z := n.x != 0
		var fixed: float
		if n.x < 0:
			fixed = r.position.x + gap - fp.position.x
		elif n.x > 0:
			fixed = r.end.x - gap - fp.end.x
		elif n.y < 0:
			fixed = r.position.y + gap - fp.position.y
		else:
			fixed = r.end.y - gap - fp.end.y
		var lo: float
		var hi: float
		if along_z:
			lo = r.position.y - fp.position.y
			hi = r.end.y - fp.end.y
		else:
			lo = r.position.x - fp.position.x
			hi = r.end.x - fp.end.x
		if hi < lo:
			continue
		for c: float in _candidates(lo, hi, mode, target):
			var origin := Vector2(fixed, c) if along_z else Vector2(c, fixed)
			var rect := Rect2(origin + fp.position, fp.size)
			if not fits(rect, type):
				continue
			if gap <= CLR + 0.01 and h > TALL_M:
				if _window_behind(n, rect) or _wall_busy(n, rect, 0.0, h):
					continue
			var out := commit(type, origin, f, rect)
			out["n"] = n
			if gap <= CLR + 0.01:
				wall_items.append([n, _lo(rect, n), _hi(rect, n), 0.0, h])
			return out
	return {}


## Next to an already placed piece, against the same wall, facing the same way.
func beside(type: String, host: Dictionary, side: int, gap: float = 0.2) -> Dictionary:
	if host.is_empty() or not Props.exists(type):
		return {}
	var f: Vector2i = host["f"]
	var hr: Rect2 = host["rect"]
	var fp := footprint(type, f)
	var origin := Vector2.ZERO
	if f.y != 0:
		origin.y = (hr.position.y - fp.position.y) if f.y > 0 else (hr.end.y - fp.end.y)
		origin.x = (hr.end.x + gap - fp.position.x) if side > 0 else (hr.position.x - gap - fp.end.x)
	else:
		origin.x = (hr.position.x - fp.position.x) if f.x > 0 else (hr.end.x - fp.end.x)
		origin.y = (hr.end.y + gap - fp.position.y) if side > 0 else (hr.position.y - gap - fp.end.y)
	var rect := Rect2(origin + fp.position, fp.size)
	if not fits(rect, type):
		return {}
	var n: Vector2i = host.get("n", -f)
	var h := float(Props.extent(type)[4])
	if h > TALL_M and (_window_behind(n, rect) or _wall_busy(n, rect, 0.0, h)):
		return {}
	var out := commit(type, origin, f, rect)
	out["n"] = n
	return out


## In front of a placed piece: a chest at the foot of a bed, an anvil before the
## forge. `facing_host` turns it round to face the host — a stool at a counter.
func in_front(type: String, host: Dictionary, gap: float, along_off: float = 0.0,
		facing_host: bool = false) -> Dictionary:
	if host.is_empty() or not Props.exists(type):
		return {}
	var f: Vector2i = host["f"]
	var hr: Rect2 = host["rect"]
	var my_f := -f if facing_host else f
	var fp := footprint(type, my_f)
	var origin := Vector2.ZERO
	var off := along_off / V
	if f.y != 0:
		origin.x = hr.get_center().x + off - (fp.position.x + fp.size.x * 0.5)
		origin.y = (hr.end.y + gap - fp.position.y) if f.y > 0 else (hr.position.y - gap - fp.end.y)
	else:
		origin.y = hr.get_center().y + off - (fp.position.y + fp.size.y * 0.5)
		origin.x = (hr.end.x + gap - fp.position.x) if f.x > 0 else (hr.position.x - gap - fp.end.x)
	var rect := Rect2(origin + fp.position, fp.size)
	if not fits(rect, type):
		return {}
	return commit(type, origin, my_f, rect)


## On a surface: a candle on the nightstand, scales on the counter, a second
## crate on the first. Takes no floor; `at` is in the host's own frame.
func on_top(type: String, host: Dictionary, height: float, at: Vector2 = Vector2.ZERO) -> void:
	if host.is_empty() or not Props.exists(type):
		return
	var f: Vector2i = host["f"]
	var c: Vector2 = (host["rect"] as Rect2).get_center()
	# Host frame: +Z is f, +X is f turned a quarter to the right.
	var fx := Vector2(f.y, -f.x)
	var p := c + (fx * at.x + Vector2(f) * at.y) / V
	_emit(type, p, f, height)


## The firebox against the chimney stack: the stack is a hollow 5x5 column
## flush to the outside wall, and the fireplace stands on its room side, so the
## breast and the flue read as one thing going up through the ceiling.
func fireplace(type: String) -> Dictionary:
	if flue.x < 0 or flue_side == Vector2i.ZERO:
		return against(type, _quiet_walls(), "centre")
	var f := -flue_side
	var fp := footprint(type, f)
	var origin := Vector2.ZERO
	var cx := float(flue.x) + 0.5
	var cz := float(flue.y) + 0.5
	match flue_side:
		Vector2i(-1, 0):
			origin = Vector2(float(flue.x) + 3.0 + CLR - fp.position.x, cz - fp.get_center().y)
		Vector2i(1, 0):
			origin = Vector2(float(flue.x) - 2.0 - CLR - fp.end.x, cz - fp.get_center().y)
		Vector2i(0, -1):
			origin = Vector2(cx - fp.get_center().x, float(flue.y) + 3.0 + CLR - fp.position.y)
		_:
			origin = Vector2(cx - fp.get_center().x, float(flue.y) - 2.0 - CLR - fp.end.y)
	var rect := Rect2(origin + fp.position, fp.size)
	if not fits(rect, type, false, true):
		return against(type, _quiet_walls(), "centre")
	var out := commit(type, origin, f, rect)
	out["n"] = flue_side
	return out


## A table and what you sit on round it, as one group: placed together or not
## at all. Seats are tucked a little under the table, which is how a table is
## left when nobody is at it.
func dining(table: String, seat: String, target: Vector2, per_side: int,
		ends: bool, with_aisle: bool = false) -> bool:
	var axes: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0)]
	if r.size.y > r.size.x:
		axes = [Vector2i(1, 0), Vector2i(0, 1)]
	var tuck := -0.8 if seat == "chair" else 0.2
	for f: Vector2i in axes:
		var tfp := footprint(table, f)
		for c: Vector2 in _floor_candidates(target, 1200 if with_aisle else 300, 2 if with_aisle else 1):
			var origin := c - tfp.get_center()
			var tr := Rect2(origin + tfp.position, tfp.size)
			if not fits(tr, table, with_aisle):
				continue
			var seats: Array = []
			var ok := true
			var long_half := (tr.size.x if f.y != 0 else tr.size.y) * 0.5
			var offs: Array[float] = [0.0]
			if per_side >= 2:
				offs = [-long_half * 0.5, long_half * 0.5]
			for side: Vector2i in [f, -f]:
				for o: float in offs:
					var s := _seat(seat, tr, side, o, tuck)
					if s.is_empty() or not fits(s["rect"], seat, with_aisle):
						ok = false
						break
					seats.append(s)
				if not ok:
					break
			if not ok:
				continue
			if ends:
				var perp := Vector2i(f.y, -f.x)
				for side2: Vector2i in [perp, -perp]:
					var s2 := _seat(seat, tr, side2, 0.0, tuck)
					if not s2.is_empty() and fits(s2["rect"], seat, with_aisle) \
							and _clear_of(s2["rect"], seats):
						seats.append(s2)
			commit(table, origin, f, tr)
			var group := tr
			for s3: Dictionary in seats:
				commit(seat, s3["origin"], s3["f"], s3["rect"])
				group = group.merge(s3["rect"])
			aisle.append(group.grow(3.0))
			return true
	return false


## Free-standing on the open floor, as near `target` as there is room.
func place_free(type: String, target: Vector2, f: Vector2i = Vector2i(0, 1)) -> Dictionary:
	if not Props.exists(type):
		return {}
	var fp := footprint(type, f)
	for c: Vector2 in _floor_candidates(target, 200):
		var origin := c - fp.get_center()
		var rect := Rect2(origin + fp.position, fp.size)
		if fits(rect, type):
			return commit(type, origin, f, rect)
	return {}


func rug_at(centre: Vector2, f: Vector2i, type: String = "rug") -> void:
	var fp := footprint(type, f)
	var origin := centre - fp.get_center()
	var rect := Rect2(origin + fp.position, fp.size)
	if not _inside_room(rect):
		return
	for o: Rect2 in rugs:
		if o.intersects(rect):
			return
	for x in range(int(floor(rect.position.x)), int(ceil(rect.end.x))):
		for z in range(int(floor(rect.position.y)), int(ceil(rect.end.y))):
			if not patch.solid_at(x, base, z) or patch.solid_at(x, base + 1, z):
				return
	rugs.append(rect)
	_emit(type, origin, f, 0.0)


## A lamp on a wall: not over a door, not across a window, not where a shelf
## already is. The longest clear walls first, so lamps spread out.
func _wall_light() -> void:
	var walls := _quiet_walls()
	var used := {}
	for it: Array in wall_items:
		if float(it[3]) > 1.0:
			used[it[0]] = true
	walls.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(used.has(a)) < int(used.has(b)))
	wall_mount("lantern", walls, Props.mount_y("lantern"), "centre")


func wall_mount(type: String, walls: Array, y: float, mode: String = "centre",
		target: float = NAN) -> Dictionary:
	if not Props.exists(type):
		return {}
	var e := Props.extent(type)
	var y0 := y - 0.2
	var y1 := y + float(e[4]) + 0.1
	for nv: Variant in walls:
		var n: Vector2i = nv
		var f := -n
		var fp := footprint(type, f)
		var along_z := n.x != 0
		var fixed: float
		if n.x < 0:
			fixed = r.position.x + CLR - fp.position.x
		elif n.x > 0:
			fixed = r.end.x - CLR - fp.end.x
		elif n.y < 0:
			fixed = r.position.y + CLR - fp.position.y
		else:
			fixed = r.end.y - CLR - fp.end.y
		var lo := (r.position.y if along_z else r.position.x) + 1.0 \
			- (fp.position.y if along_z else fp.position.x)
		var hi := (r.end.y if along_z else r.end.x) - 1.0 \
			- (fp.end.y if along_z else fp.end.x)
		if hi < lo:
			continue
		for c: float in _candidates(lo, hi, mode, target):
			var origin := Vector2(fixed, c) if along_z else Vector2(c, fixed)
			var rect := Rect2(origin + fp.position, fp.size)
			if _over_door(n, rect) or _window_behind(n, rect, y0, y1) \
					or _wall_busy(n, rect, y0, y1):
				continue
			# The wall itself has to be there: a stair hole or a chimney
			# breast in the way is not a wall to hang a lamp on.
			if _solid_in(rect, int(y / V), int(y1 / V) + 1):
				continue
			var out := commit(type, origin, f, rect, y, false)
			out["n"] = n
			wall_items.append([n, _lo(rect, n) - 1.0, _hi(rect, n) + 1.0, y0, y1])
			return out
	return {}


# ================================================================== the checks

## Whether a piece can stand on this rectangle: inside the room, on floor, not
## through anything solid, clear of other furniture and of every doorway.
func fits(rect: Rect2, type: String, check_aisle: bool = false,
		allow_zones: bool = false) -> bool:
	if not _inside_room(rect):
		return false
	var shrunk := rect.grow(-0.04)
	for o: Rect2 in occ:
		if o.intersects(shrunk):
			return false
	if not allow_zones:
		for z: Rect2 in clear_zones:
			if z.intersects(shrunk):
				return false
	if check_aisle:
		for a: Rect2 in aisle:
			if a.intersects(shrunk):
				return false
	var h := float(Props.extent(type)[4])
	var top := clampi(int(ceil(h / V)), 1, 8)
	for x in range(int(floor(shrunk.position.x)), int(ceil(shrunk.end.x))):
		for z in range(int(floor(shrunk.position.y)), int(ceil(shrunk.end.y))):
			if not patch.solid_at(x, base, z):
				return false
			for y in range(base + 1, base + 1 + top):
				if patch.solid_at(x, y, z):
					return false
	return true


func _inside_room(rect: Rect2) -> bool:
	return rect.position.x >= r.position.x - 0.01 and rect.position.y >= r.position.y - 0.01 \
		and rect.end.x <= r.end.x + 0.01 and rect.end.y <= r.end.y + 0.01


func _solid_in(rect: Rect2, y_from: int, y_to: int) -> bool:
	for x in range(int(floor(rect.position.x + 0.05)), int(ceil(rect.end.x - 0.05))):
		for z in range(int(floor(rect.position.y + 0.05)), int(ceil(rect.end.y - 0.05))):
			for y in range(base + 1 + y_from, base + 1 + y_to):
				if patch.solid_at(x, y, z):
					return true
	return false


## Glass in the wall behind this rectangle, between the given heights.
func _window_behind(n: Vector2i, rect: Rect2, y0: float = 0.0, y1: float = 2.6) -> bool:
	var line := _wall_line(n)
	var a0 := int(floor(_lo(rect, n))) - 1
	var a1 := int(ceil(_hi(rect, n))) + 1
	for a in range(a0, a1):
		for y in range(base + 1 + int(y0 / V), base + 2 + int(y1 / V)):
			var v := patch.peek(line, y, a) if n.x != 0 else patch.peek(a, y, line)
			if v == VoxelTypes.GLASS:
				return true
	return false


func _over_door(n: Vector2i, rect: Rect2) -> bool:
	for d: Array in door_runs:
		if d[0] == n and _hi(rect, n) > float(d[1]) - 1.0 and _lo(rect, n) < float(d[2]) + 1.0:
			return true
	return false


func _wall_busy(n: Vector2i, rect: Rect2, y0: float, y1: float) -> bool:
	for it: Array in wall_items:
		if it[0] != n:
			continue
		if _hi(rect, n) <= float(it[1]) or _lo(rect, n) >= float(it[2]):
			continue
		if y1 <= float(it[3]) or y0 >= float(it[4]):
			continue
		return true
	return false


func _clear_of(rect: Rect2, others: Array) -> bool:
	for o: Dictionary in others:
		if (o["rect"] as Rect2).intersects(rect.grow(-0.04)):
			return false
	return true


# ================================================================ the plumbing

## The prop's plan in voxels relative to its origin, turned to face f.
func footprint(type: String, f: Vector2i) -> Rect2:
	var e := Props.extent(type)
	var x0 := float(e[0]) / V
	var z0 := float(e[1]) / V
	var x1 := float(e[2]) / V
	var z1 := float(e[3]) / V
	match f:
		Vector2i(0, -1):
			return Rect2(-x1, -z1, x1 - x0, z1 - z0)
		Vector2i(1, 0):
			return Rect2(z0, -x1, z1 - z0, x1 - x0)
		Vector2i(-1, 0):
			return Rect2(-z1, x0, z1 - z0, x1 - x0)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func commit(type: String, origin: Vector2, f: Vector2i, rect: Rect2,
		y: float = 0.0, takes_floor: bool = true) -> Dictionary:
	if takes_floor and not (type in ["rug", "mat"]):
		occ.append(rect)
	_emit(type, origin, f, y)
	return {"type": type, "rect": rect, "f": f, "origin": origin}


func _emit(type: String, origin: Vector2, f: Vector2i, y: float) -> void:
	var pos := Vector3((patch.origin.x + origin.x) * V,
		(patch.origin.y + base + 1) * V + y,
		(patch.origin.z + origin.y) * V)
	patch.props.append({
		"type": type, "pos": pos, "yaw": atan2(float(f.x), float(f.y)),
		"module": mtype,
	})
	placed_types.append(type)
	if Props.resolve(type) in LIGHT_TYPES:
		lights += 1


func _seat(seat: String, tr: Rect2, side: Vector2i, along_off: float, tuck: float) -> Dictionary:
	var sf := -side
	var fp := footprint(seat, sf)
	var origin := Vector2.ZERO
	if side.y != 0:
		origin.x = tr.get_center().x + along_off - fp.get_center().x
		origin.y = (tr.end.y + tuck - fp.position.y) if side.y > 0 else (tr.position.y - tuck - fp.end.y)
	else:
		origin.y = tr.get_center().y + along_off - fp.get_center().y
		origin.x = (tr.end.x + tuck - fp.position.x) if side.x > 0 else (tr.position.x - tuck - fp.end.x)
	return {"origin": origin, "f": sf, "rect": Rect2(origin + fp.position, fp.size)}


func _candidates(lo: float, hi: float, mode: String, target: float) -> Array[float]:
	var out: Array[float] = []
	var c := lo
	while c <= hi + 0.001:
		out.append(c)
		c += 0.5
	var mid := (lo + hi) * 0.5
	match mode:
		"corner":
			out.sort_custom(func(a: float, b: float) -> bool:
				return minf(a - lo, hi - a) < minf(b - lo, hi - b))
		"target":
			var t := target if not is_nan(target) else mid
			out.sort_custom(func(a: float, b: float) -> bool:
				return absf(a - t) < absf(b - t))
		_:
			out.sort_custom(func(a: float, b: float) -> bool:
				return absf(a - mid) < absf(b - mid))
	return out


## Every floor point of the room, nearest `target` first. Cached per target:
## a room asks from its own centre over and over, and a sort of a couple of
## thousand points is the most expensive thing in furnishing one.
var _cand_cache: Dictionary = {}

func _floor_candidates(target: Vector2, limit: int, step: int = 1) -> Array[Vector2]:
	var ck := Vector4(target.x, target.y, float(limit), float(step))
	if _cand_cache.has(ck):
		return _cand_cache[ck]
	var pts: Array[Vector2] = []
	for x in range(r.position.x, r.end.x + 1, step):
		for z in range(r.position.y, r.end.y + 1, step):
			pts.append(Vector2(x, z))
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(target) < b.distance_squared_to(target))
	if pts.size() > limit:
		pts.resize(limit)
	_cand_cache[ck] = pts
	return pts


## Every opening in this room's four walls at floor level. Windows start well
## above the floor, so anything open at knee height is a way through.
func _find_doors() -> void:
	for n: Vector2i in DIRS:
		var line := _wall_line(n)
		var along_z := n.x != 0
		var lo := r.position.y if along_z else r.position.x
		var hi := r.end.y if along_z else r.end.x
		var start := -1
		for a in range(lo, hi + 1):
			var open := false
			if a < hi:
				open = true
				for y in range(base + 1, base + 4):
					var solid := patch.solid_at(line, y, a) if along_z else patch.solid_at(a, y, line)
					if solid:
						open = false
						break
			if open and start < 0:
				start = a
			elif not open and start >= 0:
				door_runs.append([n, start, a])
				clear_zones.append(_door_zone(n, float(start), float(a)))
				start = -1


func _door_zone(n: Vector2i, a0: float, a1: float) -> Rect2:
	var w := a1 - a0 + 2.0
	match n:
		Vector2i(-1, 0):
			return Rect2(r.position.x, a0 - 1.0, DOOR_DEPTH, w)
		Vector2i(1, 0):
			return Rect2(r.end.x - DOOR_DEPTH, a0 - 1.0, DOOR_DEPTH, w)
		Vector2i(0, -1):
			return Rect2(a0 - 1.0, r.position.y, w, DOOR_DEPTH)
	return Rect2(a0 - 1.0, r.end.y - DOOR_DEPTH, w, DOOR_DEPTH)


## The flight and the hole above it, on every floor that has them.
func _keep_stairs_clear() -> void:
	if g.stories < 2:
		return
	var sx := float(g.interior.position.x + 1)
	var sz := float(g.interior.position.y + 1)
	var run := float(BuildingGenerator.STORY_H) / 2.0 + 4.0
	clear_zones.append(Rect2(sx - 1.0, sz - 1.0, 10.0, run + 2.0))


func _wall_line(n: Vector2i) -> int:
	match n:
		Vector2i(-1, 0):
			return r.position.x - 1
		Vector2i(1, 0):
			return r.end.x
		Vector2i(0, -1):
			return r.position.y - 1
	return r.end.y


func _lo(rect: Rect2, n: Vector2i) -> float:
	return rect.position.y if n.x != 0 else rect.position.x


func _hi(rect: Rect2, n: Vector2i) -> float:
	return rect.end.y if n.x != 0 else rect.end.x


func _along_mid(rect: Rect2, n: Vector2i) -> float:
	return (_lo(rect, n) + _hi(rect, n)) * 0.5


func _walls_all() -> Array[Vector2i]:
	return DIRS.duplicate()


## Walls to put things against, best first: no door in them, then opposite a
## door (what you see as you walk in), then the longest clear run of wall.
func _quiet_walls() -> Array[Vector2i]:
	var door_ns := {}
	for d: Array in door_runs:
		door_ns[d[0]] = true
	var score := {}
	for n: Vector2i in DIRS:
		var along_z := n.x != 0
		var span := float(r.size.y if along_z else r.size.x)
		for d: Array in door_runs:
			if d[0] == n:
				span -= float(d[2]) - float(d[1]) + 2.0 * DOOR_DEPTH
		var s := span
		if not door_ns.has(n):
			s += 40.0
		if door_ns.has(-n):
			s += 15.0
		if n == pref_wall:
			s += 8.0
		score[n] = s
	var out := DIRS.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(score[a]) > float(score[b]))
	return out


func _without(walls: Array, drop: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for nv: Variant in walls:
		if nv != drop:
			out.append(nv)
	return out


## The wall the room's main piece went on: the first thing stood flush to a
## wall is always the one the recipe placed first.
func _wall_of_last() -> Vector2i:
	if not wall_items.is_empty():
		return wall_items[0][0]
	return Vector2i.ZERO


func _fire_wall(fire: Dictionary) -> Vector2i:
	return fire.get("n", Vector2i.ZERO) if not fire.is_empty() else Vector2i.ZERO


func _front_door_wall() -> Vector2i:
	var fr := Vector2i(g.front.x, g.front.z)
	for d: Array in door_runs:
		if d[0] == fr:
			return fr
	return door_runs[0][0] if not door_runs.is_empty() else fr


## The wall to put a counter in front of: across from the way customers come
## in, and with no door of its own.
func _back_wall() -> Vector2i:
	var door_n := _front_door_wall()
	var want := -door_n
	for d: Array in door_runs:
		if d[0] == want:
			return _quiet_walls()[0]
	return want


func _room_centre() -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * 0.5


func _point_ahead(host: Dictionary, metres: float) -> Vector2:
	var hr: Rect2 = host["rect"]
	var f: Vector2i = host["f"]
	var c := hr.get_center()
	var half := (hr.size.y if f.y != 0 else hr.size.x) * 0.5
	return c + Vector2(f) * (half + metres / V)


## The floor in front of a piece, kept clear: you have to be able to stand at
## the fire or the oven.
func _zone_ahead(host: Dictionary, depth: float) -> Rect2:
	var hr: Rect2 = host["rect"]
	var f: Vector2i = host["f"]
	match f:
		Vector2i(0, 1):
			return Rect2(hr.position.x, hr.end.y, hr.size.x, depth)
		Vector2i(0, -1):
			return Rect2(hr.position.x, hr.position.y - depth, hr.size.x, depth)
		Vector2i(1, 0):
			return Rect2(hr.end.x, hr.position.y, depth, hr.size.y)
	return Rect2(hr.position.x - depth, hr.position.y, depth, hr.size.y)
