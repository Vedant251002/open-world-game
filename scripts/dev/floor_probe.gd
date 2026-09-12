extends Node
class_name FloorProbe
## Does a body that is not the player get a floor? Stands a fighter fifty
## metres from the well and watches whether it stays up. `-- --floorprobe`.

var world: VoxelWorld
var village: Village
var warfare: Warfare
var nav: NavGrid

var _t := 0.0
var _f: Fighter = null
var _last := -1.0


func _process(delta: float) -> void:
	if world != null and world.busy() and _t < 15.0:
		_t += delta
		return
	_t += delta
	if _f == null:
		var at := village.well_pos + Vector3(-36.0, 0.0, -30.0)
		at.y = world.ground_m(at.x, at.z) + 0.3
		_f = Fighter.new()
		warfare.add_child(_f)
		_f.setup("raider", world, nav, warfare, at, "")
		warfare.raiders.append(_f)
		_f.march(village.well_pos)
		print("[floor] stood at %s, ground %.2f" % [str(at), world.ground_m(at.x, at.z)])
		_last = _t
		return
	if _t - _last >= 1.0:
		_last = _t
		var p := _f.global_position
		var v := VoxelWorld.to_voxel(p)
		var cpos := Vector3i(v.x >> 5, v.y >> 5, v.z >> 5)
		var below := Vector3i(v.x >> 5, (v.y - 1) >> 5, v.z >> 5)
		var c: VoxelChunk = world.chunks.get(cpos)
		print("[floor] t=%.0f at %s floor=%s body_here=%s body_below=%s chunk=%s shape=%s meshed=%s agents=%d" % [
			_t, str(p.round()), str(_f.is_on_floor()), str(world._bodies.has(cpos)),
			str(world._bodies.has(below)), str(c != null),
			str(c != null and c.shape != null), str(world._meshed.has(cpos)),
			world._agents.size()])
	if _t > 14.0:
		print("[floor] === %s ===" % ("PASS" if _f.global_position.y > 0.0 else "FAIL"))
		get_tree().quit()
