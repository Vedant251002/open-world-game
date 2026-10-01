extends Node3D
class_name Scaffolding
## Timber poles and plank platforms round a building that is going up.
##
## Built in lifts, one per storey-ish (every LIFT_M of wall). A lift is shown
## once the walls have risen to within a lift of it, and pops in with a small
## overshoot, so the frame appears to climb with the work. Each lift is a single
## baked mesh from the same painted boxes as the villagers: a whole frame round
## a house is a handful of draw calls.

const LIFT_M := 2.0           ## vertical spacing of the working platforms
const STANDOFF_M := 0.9       ## how far the frame stands off the wall
const POLE_GAP_M := 2.4
const POLE := 0.09

var _lifts: Array[Node3D] = []
var _lift_y: Array[float] = []
var _shown := 0
var _pop: Array[float] = []   ## seconds since each lift appeared
var rect_m := Rect2()         ## footprint with stand-off, world metres, xz
var base_y := 0.0
var top_y := 0.0


## footprint_m: the building's footprint in world metres (xz). height_m: how
## tall the finished walls and roof will be, above ground.
func build(footprint_m: Rect2, ground_y: float, height_m: float) -> void:
	base_y = ground_y
	top_y = ground_y + height_m
	rect_m = footprint_m.grow(STANDOFF_M)
	var n := maxi(1, int(ceil(height_m / LIFT_M)))
	var timber := Color("#8b6a43")
	var timber_dk := Color("#6e5233")
	var plank := Color("#b7915e")
	for k in n:
		var lift := Node3D.new()
		lift.visible = false
		add_child(lift)
		var b := BoxKit.Batch.new()
		var y0 := k * LIFT_M
		var y1 := minf(y0 + LIFT_M, height_m + 0.6)
		_poles(b, lift, y0, y1, timber)
		# Ledgers and the plank deck at the top of the lift, except the last one
		# sits at working height under the eaves.
		var deck_y := y1 - 0.12
		_ring(b, lift, deck_y - 0.05, timber_dk)
		_ring(b, lift, deck_y - 0.55, timber_dk)
		_deck(b, lift, deck_y, plank)
		_braces(b, lift, y0, y1, timber_dk)
		b.flush()
		_lifts.append(lift)
		_lift_y.append(ground_y + y0)
		_pop.append(99.0)


func _perimeter_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var r := rect_m
	var nx := maxi(1, int(round(r.size.x / POLE_GAP_M)))
	var nz := maxi(1, int(round(r.size.y / POLE_GAP_M)))
	for i in nx + 1:
		var x := r.position.x + r.size.x * float(i) / float(nx)
		pts.append(Vector2(x, r.position.y))
		pts.append(Vector2(x, r.end.y))
	for j in range(1, nz):
		var z := r.position.y + r.size.y * float(j) / float(nz)
		pts.append(Vector2(r.position.x, z))
		pts.append(Vector2(r.end.x, z))
	return pts


func _poles(b: BoxKit.Batch, parent: Node3D, y0: float, y1: float, col: Color) -> void:
	for p in _perimeter_points():
		b.box(parent, Vector3(p.x - POLE * 0.5, base_y + y0, p.y - POLE * 0.5),
			Vector3(POLE, y1 - y0 + 0.02, POLE), col, 0.95)


func _ring(b: BoxKit.Batch, parent: Node3D, y: float, col: Color) -> void:
	var r := rect_m
	var t := 0.06
	b.box(parent, Vector3(r.position.x, base_y + y, r.position.y - t * 0.5), Vector3(r.size.x, t, t), col, 0.95)
	b.box(parent, Vector3(r.position.x, base_y + y, r.end.y - t * 0.5), Vector3(r.size.x, t, t), col, 0.95)
	b.box(parent, Vector3(r.position.x - t * 0.5, base_y + y, r.position.y), Vector3(t, t, r.size.y), col, 0.95)
	b.box(parent, Vector3(r.end.x - t * 0.5, base_y + y, r.position.y), Vector3(t, t, r.size.y), col, 0.95)


## A walkway one board and a bit wide on the outer side of the poles.
func _deck(b: BoxKit.Batch, parent: Node3D, y: float, col: Color) -> void:
	var r := rect_m
	var w := 0.8
	var th := 0.07
	var yy := base_y + y
	# Two shades alternate along each run so it reads as boards, not a slab.
	var seg := 1.2
	var x := r.position.x - w * 0.5
	var i := 0
	while x < r.end.x + w * 0.5 - 0.01:
		var l := minf(seg, r.end.x + w * 0.5 - x)
		var c := col if i % 2 == 0 else col.darkened(0.08)
		b.box(parent, Vector3(x, yy, r.position.y - w * 0.5), Vector3(l, th, w), c, 0.9)
		b.box(parent, Vector3(x, yy, r.end.y - w * 0.5), Vector3(l, th, w), c, 0.9)
		x += l
		i += 1
	var z := r.position.y + w * 0.5
	while z < r.end.y - w * 0.5 - 0.01:
		var l2 := minf(seg, r.end.y - w * 0.5 - z)
		var c2 := col if i % 2 == 0 else col.darkened(0.08)
		b.box(parent, Vector3(r.position.x - w * 0.5, yy, z), Vector3(w, th, l2), c2, 0.9)
		b.box(parent, Vector3(r.end.x - w * 0.5, yy, z), Vector3(w, th, l2), c2, 0.9)
		z += l2
		i += 1


## One cross brace on each long face, a diagonal made of stepped boxes.
func _braces(b: BoxKit.Batch, parent: Node3D, y0: float, y1: float, col: Color) -> void:
	var r := rect_m
	var steps := 6
	var h := (y1 - y0 - 0.7) / float(steps)
	if h <= 0.05:
		return
	var run := minf(r.size.x, 4.0) / float(steps)
	for s in steps:
		var yy := base_y + y0 + 0.2 + s * h
		b.box(parent, Vector3(r.position.x + s * run, yy, r.position.y - 0.03), Vector3(run + 0.05, 0.05, 0.06), col, 0.95)
		b.box(parent, Vector3(r.end.x - (s + 1) * run, yy, r.end.y - 0.03), Vector3(run + 0.05, 0.05, 0.06), col, 0.95)


## Shows the lifts that the walls have reached. height_laid_m is how tall the
## wall is now, above ground.
func set_height(height_laid_m: float) -> void:
	var want := 0
	for k in _lifts.size():
		# A lift stands once the wall is within half a lift of its floor.
		if height_laid_m >= float(k) * LIFT_M - LIFT_M * 0.5 or k == 0:
			want = k + 1
	while _shown < want:
		_lifts[_shown].visible = true
		_pop[_shown] = 0.0
		_lifts[_shown].scale = Vector3(1.0, 0.01, 1.0)
		_shown += 1
	set_process(true)


func show_all() -> void:
	set_height(1000.0)


func _process(delta: float) -> void:
	var busy := false
	for k in _shown:
		if _pop[k] < 0.5:
			_pop[k] += delta
			busy = true
			var t := clampf(_pop[k] / 0.45, 0.0, 1.0)
			# Overshoot ease so each lift springs up rather than slides.
			var s := 1.0 + 1.7 * pow(t - 1.0, 3.0) + 0.7 * pow(t - 1.0, 2.0)
			var lift := _lifts[k]
			lift.scale = Vector3(1.0, maxf(s, 0.01), 1.0)
			# Scale about the lift's own floor, not the world origin.
			lift.position.y = _lift_y[k] * (1.0 - lift.scale.y)
	if not busy:
		set_process(false)
