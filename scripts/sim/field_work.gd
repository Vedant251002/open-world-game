extends RefCounted
class_name FieldWork
## Ploughing and sowing a field over in-game time.
##
## The same shape as Construction, and for the same reason: the gap between
## being told and seeing the result is where the game lives. A worker sent to
## plant wheat is gone for the afternoon, and you find out on the way back
## whether they laid the field where you meant.

var farm: Farm
var rect: Rect2i                  ## world voxels
var crop := "wheat"

var finished := false
var tilled := 0
var sown := 0

## Voxel columns ploughed per in-game hour, before the worker's own pace.
var tiles_per_hour := 26.0

var _order: Array[Vector2i] = []
var _cursor := 0
var _carry := 0.0


func _init(f: Farm, area: Rect2i, kind: String) -> void:
	farm = f
	rect = area
	crop = kind
	# Row by row, the way anyone actually ploughs, so a field half done looks
	# half done rather than moth-eaten.
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_order.append(Vector2i(x, z))


func total() -> int:
	return _order.size()


func progress() -> float:
	if total() == 0:
		return 1.0
	return float(_cursor) / float(total())


func advance(hours: float) -> void:
	if finished:
		return
	_carry += hours * tiles_per_hour
	var n := int(_carry)
	if n <= 0:
		return
	_carry -= n
	_work(n)


func complete_now() -> void:
	_work(total())


func _work(n: int) -> void:
	var end := mini(_cursor + n, _order.size())
	while _cursor < end:
		var c: Vector2i = _order[_cursor]
		_cursor += 1
		if farm.till(c.x, c.y):
			tilled += 1
		# Sow straight behind the plough. Tilling a whole field and then walking
		# it again would be more accurate and much duller to watch.
		if farm.plant(c.x, c.y, crop):
			sown += 1
	if _cursor >= _order.size():
		finished = true


func summary() -> String:
	return "%d tiles ploughed, %d sown with %s" % [tilled, sown, crop]
