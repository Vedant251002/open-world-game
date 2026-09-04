extends CanvasLayer
class_name MapScreen
## The town map.
##
## Two layers on purpose. The land underneath is sampled from the same height
## function the world is built from, shaded with a raked light so hills read as
## hills — soft, because it is terrain. The town on top is drawn as vectors:
## streets, plot outlines, building footprints, labels. Vectors stay crisp at
## any zoom and are what the player actually reads a map for.
##
## Sampling runs on a worker thread. WorldGen holds no state, so the map can ask
## it about a thousand square metres of land the player has never walked to
## while the game carries on.

const SAMPLES := 384              ## terrain texture resolution, per side
const MARGIN := 1.5               ## texture covers this multiple of the view
const MIN_SPAN := 90.0
const MAX_SPAN := 1400.0

var world: VoxelWorld
var gen: WorldGen
var village: Village
var player: Player

var open := false
var centre := Vector2.ZERO         ## world metres
var span := 300.0                  ## metres across the viewport

var buildings: Array[Dictionary] = []   ## {rect_m, name, front}
var workers: Array = []                 ## Worker nodes, drawn live

var _root: Control
var _land: TextureRect
var _overlay: Control
var _hud: Control
var _tex_centre := Vector2(1e9, 1e9)
var _tex_span := 0.0
var _pending := false
var _mutex := Mutex.new()
var _result: Array = []
var _dragging := false
var _font: Font

# --- palette: muted, so the ink layer on top stays legible ---
const C_DEEP := Color("#33556b")
const C_SHALLOW := Color("#5d8ea4")
const C_SAND := Color("#d9c79a")
const C_GRASS_LOW := Color("#8aa063")
const C_GRASS_HIGH := Color("#a6a473")
const C_ROCK := Color("#9c9890")
const C_SNOW := Color("#d6d6cf")
const C_PAPER := Color("#efe6d2")
const C_INK := Color("#2b2118")
const C_ROAD := Color("#e8dcbf")
const C_PLOT := Color("#7c6a4e")
const C_BUILDING := Color("#7a4a2e")


func setup(w: VoxelWorld, g: WorldGen, v: Village, p: Player) -> void:
	world = w
	gen = g
	village = v
	player = p
	centre = Vector2(v.well_pos.x, v.well_pos.z)
	_font = ThemeDB.fallback_font
	layer = 20
	_build_ui()
	visible = false
	set_process(true)
	set_process_unhandled_input(true)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.04, 0.03, 0.82)
	_root.add_child(backdrop)

	# The map sits in a framed panel rather than filling the screen, so it reads
	# as a thing you are holding.
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 56
	frame.offset_top = 44
	frame.offset_right = -56
	frame.offset_bottom = -44
	var style := StyleBoxFlat.new()
	style.bg_color = C_PAPER
	style.border_color = Color("#3a2c1e")
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 18
	frame.add_theme_stylebox_override("panel", style)
	_root.add_child(frame)

	var clip := Control.new()
	clip.clip_contents = true
	frame.add_child(clip)

	_land = TextureRect.new()
	_land.set_anchors_preset(Control.PRESET_FULL_RECT)
	_land.stretch_mode = TextureRect.STRETCH_SCALE
	_land.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip.add_child(_land)

	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(C_PAPER.r, C_PAPER.g, C_PAPER.b, 0.13)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(wash)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	clip.add_child(_overlay)

	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	frame.add_child(_hud)


# ------------------------------------------------------------------- opening

func toggle() -> void:
	set_open(not open)


func set_open(v: bool) -> void:
	open = v
	visible = v
	if player != null:
		player.set_input_enabled(not v)
	if v:
		_request_texture(true)
		_overlay.queue_redraw()
		_hud.queue_redraw()


func note_building(patch: VoxelPatch, display_name: String) -> void:
	var fr := patch.footprint
	buildings.append({
		"rect_m": Rect2(fr.position.x * 0.25, fr.position.y * 0.25,
			fr.size.x * 0.25, fr.size.y * 0.25),
		"name": display_name.replace("_", " "),
		"front": patch.front,
	})
	if open:
		_overlay.queue_redraw()


func forget_building(patch: VoxelPatch) -> void:
	for b in buildings:
		if (b["rect_m"] as Rect2).position.x == patch.footprint.position.x * 0.25:
			buildings.erase(b)
			break
	if open:
		_overlay.queue_redraw()


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	if event.is_action_pressed("menu"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.82)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.22)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		centre -= mm.relative * (span / maxf(_overlay.size.x, 1.0))
		_after_move()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_HOME:
				centre = Vector2(village.well_pos.x, village.well_pos.z)
				_after_move()
			KEY_SPACE:
				centre = Vector2(player.global_position.x, player.global_position.z)
				_after_move()


func _zoom(factor: float) -> void:
	span = clampf(span * factor, MIN_SPAN, MAX_SPAN)
	_after_move()


func _after_move() -> void:
	_overlay.queue_redraw()
	_hud.queue_redraw()
	_request_texture(false)


# ------------------------------------------------------------------ terrain

func _process(_delta: float) -> void:
	_collect_texture()
	if open:
		_overlay.queue_redraw()


## Regenerates only when the view has drifted past the texture's margin, so
## panning slowly costs nothing.
func _request_texture(force: bool) -> void:
	if _pending:
		return
	var covered := _tex_span
	var drift := centre.distance_to(_tex_centre)
	if not force and covered > 0.0 and absf(covered - span * MARGIN) < covered * 0.25 \
			and drift < covered * 0.15:
		return
	_pending = true
	var want_centre := centre
	var want_span := span * MARGIN
	WorkerThreadPool.add_task(_sample_job.bind(want_centre, want_span), false, "map")


## Runs on a worker thread: WorldGen is a pure function of position, so this can
## survey land nobody has ever loaded.
func _sample_job(at: Vector2, world_span: float) -> void:
	var data := PackedByteArray()
	data.resize(SAMPLES * SAMPLES * 3)
	var step := world_span / float(SAMPLES)
	var half := world_span * 0.5
	var sea := float(gen.sea_voxel()) * VoxelChunk.VOXEL_M
	var inv := 1.0 / VoxelChunk.VOXEL_M

	# Heights first, so shading can use real neighbours rather than resampling.
	var h := PackedFloat32Array()
	h.resize(SAMPLES * SAMPLES)
	for j in SAMPLES:
		var wz := at.y - half + j * step
		for i in SAMPLES:
			var wx := at.x - half + i * step
			h[i + j * SAMPLES] = float(gen.height_at(int(wx * inv), int(wz * inv))) \
				* VoxelChunk.VOXEL_M

	for j in SAMPLES:
		for i in SAMPLES:
			var y: float = h[i + j * SAMPLES]
			var col := _land_colour(y, sea)

			# Raked light from the north-west, the cartographer's convention.
			var hx: float = h[mini(i + 1, SAMPLES - 1) + j * SAMPLES] - h[maxi(i - 1, 0) + j * SAMPLES]
			var hz: float = h[i + mini(j + 1, SAMPLES - 1) * SAMPLES] - h[i + maxi(j - 1, 0) * SAMPLES]
			var shade := clampf(1.0 + (-hx - hz) * 0.16 / maxf(step, 0.5), 0.55, 1.45)
			if y <= sea:
				shade = 1.0
			col = col * shade

			var o := (i + j * SAMPLES) * 3
			data[o] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)

	_mutex.lock()
	_result.append({"data": data, "centre": at, "span": world_span})
	_mutex.unlock()


static func _land_colour(y: float, sea: float) -> Color:
	if y <= sea - 3.0:
		return C_DEEP
	if y <= sea:
		return C_DEEP.lerp(C_SHALLOW, inverse_lerp(sea - 3.0, sea, y))
	if y <= sea + 1.4:
		return C_SAND
	if y <= sea + 16.0:
		return C_GRASS_LOW.lerp(C_GRASS_HIGH, inverse_lerp(sea + 1.4, sea + 16.0, y))
	if y <= sea + 26.0:
		return C_GRASS_HIGH.lerp(C_ROCK, inverse_lerp(sea + 16.0, sea + 26.0, y))
	return C_ROCK.lerp(C_SNOW, clampf(inverse_lerp(sea + 26.0, sea + 34.0, y), 0.0, 1.0))


func _collect_texture() -> void:
	_mutex.lock()
	var got: Dictionary = {}
	if not _result.is_empty():
		got = _result.pop_back()
		_result.clear()
	_mutex.unlock()
	if got.is_empty():
		return
	_pending = false
	var img := Image.create_from_data(SAMPLES, SAMPLES, false, Image.FORMAT_RGB8, got["data"])
	_land.texture = ImageTexture.create_from_image(img)
	_tex_centre = got["centre"]
	_tex_span = got["span"]
	_place_land()


## Positions the terrain texture so its world coverage lines up with the vector
## overlay, whatever the view has done since it was generated.
func _place_land() -> void:
	if _overlay == null or _tex_span <= 0.0:
		return
	var px_per_m := _overlay.size.x / span
	var size_px := _tex_span * px_per_m
	var half := _tex_span * 0.5
	var top_left := _world_to_screen(Vector2(_tex_centre.x - half, _tex_centre.y - half))
	_land.position = top_left
	_land.size = Vector2(size_px, size_px)


func _world_to_screen(w: Vector2) -> Vector2:
	var px_per_m := _overlay.size.x / span
	return (w - centre) * px_per_m + _overlay.size * 0.5


func _screen_scale() -> float:
	return _overlay.size.x / span


# ------------------------------------------------------------------- drawing

func _draw_overlay() -> void:
	_place_land()
	var s := _screen_scale()

	_draw_streets(s)
	_draw_plots(s)
	_draw_buildings(s)
	_draw_well(s)
	_draw_workers()
	_draw_player()


func _draw_streets(s: float) -> void:
	var half_w := Village.ROAD_WIDTH * s
	var lo := village.lines_x[0] * VoxelChunk.VOXEL_M
	var hi := village.lines_x[village.lines_x.size() - 1] * VoxelChunk.VOXEL_M
	var lo_z := village.lines_z[0] * VoxelChunk.VOXEL_M
	var hi_z := village.lines_z[village.lines_z.size() - 1] * VoxelChunk.VOXEL_M

	# Drawn twice: a dark casing, then the carriageway, which is what makes a
	# road look like a road rather than a coloured line.
	for pass_i in 2:
		var w := half_w + (3.0 if pass_i == 0 else 0.0)
		var col := C_INK if pass_i == 0 else C_ROAD
		for lx: int in village.lines_x:
			var x := lx * VoxelChunk.VOXEL_M
			_overlay.draw_line(_world_to_screen(Vector2(x, lo_z)),
				_world_to_screen(Vector2(x, hi_z)), col, w, true)
		for lz: int in village.lines_z:
			var z := lz * VoxelChunk.VOXEL_M
			_overlay.draw_line(_world_to_screen(Vector2(lo, z)),
				_world_to_screen(Vector2(hi, z)), col, w, true)


func _draw_plots(s: float) -> void:
	if s < 0.9:
		return                              # too far out to be readable
	for p in village.plots:
		if p.occupied_by >= 0:
			continue
		var r := Rect2(_world_to_screen(Vector2(p.origin.x, p.origin.z) * VoxelChunk.VOXEL_M),
			Vector2(p.size_v) * VoxelChunk.VOXEL_M * s)
		_overlay.draw_rect(r, Color(C_PLOT, 0.14), true)
		_overlay.draw_rect(r, Color(C_PLOT, 0.55), false, 1.0)


func _draw_buildings(s: float) -> void:
	for b in buildings:
		var rm: Rect2 = b["rect_m"]
		var r := Rect2(_world_to_screen(rm.position), rm.size * s)
		# A hard drop shadow to the south-east reads as height on a flat map.
		_overlay.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0, 0, 0, 0.30), true)
		_overlay.draw_rect(r, C_BUILDING, true)
		_overlay.draw_rect(r, C_INK, false, 1.5)

		if s > 1.6:
			var label := str(b["name"])
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var at := r.position + Vector2(r.size.x * 0.5 - w * 0.5, -5)
			_overlay.draw_string_outline(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 12, 3, C_PAPER)
			_overlay.draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)


func _draw_well(s: float) -> void:
	var p := _world_to_screen(Vector2(village.well_pos.x, village.well_pos.z))
	var r := maxf(4.0, 2.2 * s)
	_overlay.draw_circle(p, r + 2.0, Color(C_PAPER, 0.9))
	_overlay.draw_circle(p, r, C_INK)
	_overlay.draw_circle(p, r * 0.45, C_SHALLOW)
	if s > 1.0:
		var at := p + Vector2(r + 5, 4)
		_overlay.draw_string_outline(_font, at, "the well", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 12, 3, C_PAPER)
		_overlay.draw_string(_font, at, "the well", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)


func _draw_workers() -> void:
	for w: Variant in workers:
		if not is_instance_valid(w):
			continue
		var node: Node3D = w
		var p := _world_to_screen(Vector2(node.global_position.x, node.global_position.z))
		_overlay.draw_circle(p, 5.0, C_PAPER)
		_overlay.draw_circle(p, 3.5, Color("#c46a3a"))


func _draw_player() -> void:
	if player == null:
		return
	var p := _world_to_screen(Vector2(player.global_position.x, player.global_position.z))
	var yaw := player.yaw
	# Player forward is -Z rotated by yaw.
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := p + fwd * 11.0
	var a := p - fwd * 5.0 + side * 6.5
	var b := p - fwd * 5.0 - side * 6.5
	_overlay.draw_colored_polygon(PackedVector2Array([tip, a, p - fwd * 1.0, b]),
		Color("#f2f0e6"))
	_overlay.draw_polyline(PackedVector2Array([tip, a, p - fwd * 1.0, b, tip]),
		C_INK, 1.5, true)


# ---------------------------------------------------------------------- hud

func _draw_hud() -> void:
	var size := _hud.size
	var title := "THE TOWN"
	_hud.draw_string(_font, Vector2(18, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_INK)

	var sub := "%d buildings   %d plots free" % [buildings.size(), _free_plots()]
	_hud.draw_string(_font, Vector2(18, 50), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(C_INK, 0.7))

	_draw_scale_bar(Vector2(18, size.y - 22))
	_draw_compass(Vector2(size.x - 44, 46))

	var help := "drag to pan    wheel to zoom    SPACE you    HOME the well    M close"
	var w := _font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_hud.draw_string(_font, Vector2(size.x - w - 18, size.y - 22), help,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_INK, 0.75))


func _free_plots() -> int:
	var n := 0
	for p in village.plots:
		if p.occupied_by < 0:
			n += 1
	return n


func _draw_scale_bar(at: Vector2) -> void:
	# Round the bar to a sensible number of metres rather than a round number
	# of pixels — a scale bar that reads "37 m" is no use to anyone.
	var px_per_m := _overlay.size.x / span
	var target := 140.0
	var metres := target / px_per_m
	var nice := pow(10.0, floor(log(metres) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if nice * m >= metres:
			nice *= m
			break
	var length := nice * px_per_m

	_hud.draw_line(at, at + Vector2(length, 0), C_INK, 2.0)
	_hud.draw_line(at + Vector2(0, -4), at + Vector2(0, 4), C_INK, 2.0)
	_hud.draw_line(at + Vector2(length, -4), at + Vector2(length, 4), C_INK, 2.0)
	_hud.draw_string(_font, at + Vector2(length + 8, 4), "%d m" % int(nice),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_INK)


func _draw_compass(at: Vector2) -> void:
	_hud.draw_circle(at, 20.0, Color(C_PAPER, 0.85))
	_hud.draw_arc(at, 20.0, 0.0, TAU, 32, C_INK, 1.5, true)
	_hud.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -16), at + Vector2(5, 3), at + Vector2(-5, 3)]), C_INK)
	_hud.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, 16), at + Vector2(5, -3), at + Vector2(-5, -3)]),
		Color(C_INK, 0.35))
	_hud.draw_string(_font, at + Vector2(-4, -24), "N", HORIZONTAL_ALIGNMENT_CENTER,
		12, 11, C_INK)


# --------------------------------------------------------------------- debug

## Opens the map, waits for the land survey, saves a screenshot and quits.
func capture_and_quit() -> void:
	set_open(true)
	for _i in 240:
		await get_tree().process_frame
		if not _pending and _land.texture != null:
			break
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://audit"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(dir + "/map.png"))
	print("[map] saved %s/map.png" % dir)
	get_tree().quit()
