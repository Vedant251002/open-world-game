extends RefCounted
class_name PlanShot
## A floor plan of a generated building, drawn from the patch rather than
## photographed: walls, glass, doorways and every piece of furniture as the
## rectangle it actually occupies, turned the way it actually faces.
##
## A camera in a room shows one corner of it and a table leg; a plan shows
## whether the bed is on the right wall, whether the counter faces the door,
## and whether anything stands in a doorway — the things a layout is judged
## by. `--plans` writes one per founding building to user://shots.

const PX := 8                     ## pixels per voxel

const COLOURS := {
	"bed": Color("#c0504d"), "bed_double": Color("#c0504d"),
	"nightstand": Color("#8a6d4a"), "wardrobe": Color("#5c3d24"),
	"chest": Color("#7a5230"), "table": Color("#c99a5b"), "table_long": Color("#c99a5b"),
	"chair": Color("#e0b070"), "stool": Color("#e0b070"), "bench": Color("#d8a860"),
	"dresser": Color("#6b4a2e"), "shelf": Color("#4a6b8a"), "bread_rack": Color("#4a6b8a"),
	"counter_block": Color("#9b59b6"), "hearth_fire": Color("#e67e22"),
	"oven_block": Color("#e67e22"), "forge_block": Color("#e67e22"),
	"workbench": Color("#a0522d"), "worktable": Color("#a0522d"),
	"barrel": Color("#7f8c8d"), "crate": Color("#95a5a6"), "rug": Color("#e8a0a0"),
	"mat": Color("#d4c070"), "lantern": Color("#ffe066"), "candle": Color("#ffe066"),
	"hay": Color("#f1c40f"), "trough": Color("#6d8a4a"),
}


static func draw(patch: VoxelPatch, base_y: int, path: String) -> void:
	var w := patch.size.x
	var d := patch.size.z
	var img := Image.create(w * PX, d * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color("#2d3a2a"))
	var y := base_y + 2
	for z in d:
		for x in w:
			var c := Color("#2d3a2a")
			var v := patch.peek(x, y, z)
			var floor_v := patch.peek(x, base_y, z)
			if v == VoxelTypes.GLASS or patch.peek(x, base_y + 7, z) == VoxelTypes.GLASS:
				c = Color("#5dade2")
			elif v != VoxelPatch.UNTOUCHED and v != VoxelTypes.AIR:
				c = Color("#1b1b1b")
			elif floor_v != VoxelPatch.UNTOUCHED and floor_v != VoxelTypes.AIR:
				c = Color("#efe6d2")
			img.fill_rect(Rect2i(x * PX, z * PX, PX, PX), c)
	for p: Dictionary in patch.props:
		var t := Props.resolve(str(p["type"]))
		var pos: Vector3 = p["pos"]
		var ly := int(floor(pos.y / VoxelChunk.VOXEL_M + 0.01)) - patch.origin.y
		if ly <= base_y or ly > base_y + BuildingGenerator.STORY_H:
			continue
		var lx := pos.x / VoxelChunk.VOXEL_M - patch.origin.x
		var lz := pos.z / VoxelChunk.VOXEL_M - patch.origin.z
		var e := Props.extent(t)
		var yaw := float(p.get("yaw", 0.0))
		var corners: Array[Vector2] = []
		for cx: float in [float(e[0]), float(e[2])]:
			for cz: float in [float(e[1]), float(e[3])]:
				# local +X -> (cos, -sin), local +Z -> (sin, cos)
				var wx := cx * cos(yaw) + cz * sin(yaw)
				var wz := -cx * sin(yaw) + cz * cos(yaw)
				corners.append(Vector2(lx + wx / VoxelChunk.VOXEL_M, lz + wz / VoxelChunk.VOXEL_M))
		var lo := corners[0]
		var hi := corners[0]
		for q: Vector2 in corners:
			lo = lo.min(q)
			hi = hi.max(q)
		var col: Color = COLOURS.get(t, Color("#bdc3c7"))
		var rect := Rect2i(int(lo.x * PX), int(lo.y * PX),
			maxi(int((hi.x - lo.x) * PX), 3), maxi(int((hi.y - lo.y) * PX), 3))
		if t in ["rug", "mat"]:
			col.a = 0.55
			_blend_rect(img, rect, col)
		else:
			img.fill_rect(rect, col)
			# A dark stripe on the front edge, so the facing is visible.
			var fx := sin(yaw)
			var fz := cos(yaw)
			var stripe := rect
			if absf(fz) > 0.5:
				stripe = Rect2i(rect.position.x, rect.end.y - 2 if fz > 0 else rect.position.y,
					rect.size.x, 2)
			else:
				stripe = Rect2i(rect.end.x - 2 if fx > 0 else rect.position.x, rect.position.y,
					2, rect.size.y)
			img.fill_rect(stripe, col.darkened(0.6))
	img.save_png(ProjectSettings.globalize_path(path))


static func _blend_rect(img: Image, r: Rect2i, c: Color) -> void:
	var clip := r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	for yy in range(clip.position.y, clip.end.y):
		for xx in range(clip.position.x, clip.end.x):
			img.set_pixel(xx, yy, img.get_pixel(xx, yy).blend(c))
