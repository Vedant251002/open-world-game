extends Node3D
class_name NameTag
## The name over a person's head: name, a small role line under it, and above
## it a badge when they want something from you.
##
## The old tag was a plain Label3D, which scales with perspective like any other
## object: a smudge across the plaza and a name the size of a door when you
## stood beside them. Here the scale is driven from the camera distance every
## frame so the tag holds roughly the same size on screen between a couple of
## metres and fourteen, then lets go and shrinks and fades with distance so a
## whole town of them does not turn into a wall of text.

const PX := 0.0024                  ## metres per font pixel at scale one
const REF_DIST := 4.0               ## distance at which scale is one
const FADE_FROM := 17.0
const FADE_TO := 30.0

var worker: Worker
var focused := false                ## the crosshair is on them: brighter, bigger

var _name: Label3D
var _role: Label3D
var _badge: Sprite3D
var _glyph: Label3D
var _alpha := 1.0
var _focus := 0.0
var _status := ""
var _role_timer := 0.0
var _phase := randf() * TAU

static var _disc: Texture2D = null


func setup(w: Worker) -> void:
	worker = w
	position.y = 2.02
	_name = _label(w.memory.display_name, 64, 800, 16)
	_name.modulate = w.body.cloth_colour.lightened(0.62).lerp(Color(1, 0.96, 0.88), 0.45)
	_name.render_priority = 4
	_name.outline_render_priority = 3
	add_child(_name)
	_role = _label("", 40, 600, 11)
	_role.modulate = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.95)
	_role.position.y = -0.155
	_role.render_priority = 4
	_role.outline_render_priority = 3
	add_child(_role)

	_badge = Sprite3D.new()
	_badge.texture = _disc_texture()
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.pixel_size = 0.0030
	_badge.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_badge.render_priority = 5
	_badge.position.y = 0.23
	_badge.visible = false
	_badge.set_meta("no_highlight", true)
	add_child(_badge)
	_glyph = _label("?", 62, 800, 0)
	_glyph.render_priority = 6
	_glyph.position.y = 0.23
	_glyph.visible = false
	add_child(_glyph)
	_refresh_role()


func _label(text: String, size: int, weight: int, outline: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(weight)
	l.font_size = size
	l.pixel_size = PX
	l.outline_size = outline
	l.outline_modulate = Color(0.04, 0.03, 0.02, 0.92)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	return l


## A dark disc with a gold ring, drawn once and shared.
static func _disc_texture() -> Texture2D:
	if _disc != null:
		return _disc
	var n := 96
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / (n * 0.5)
			var a := clampf((1.0 - d) * n * 0.5, 0.0, 1.0)
			var ring := smoothstep(0.78, 0.86, d)
			var col := Color(0.09, 0.07, 0.05).lerp(Color(0.96, 0.76, 0.38), ring)
			img.set_pixel(x, y, Color(col, a * 0.96))
	img.generate_mipmaps()
	_disc = ImageTexture.create_from_image(img)
	return _disc


func _refresh_role() -> void:
	var r := ""
	if worker.role != null and worker.role.id != "builder":
		r = worker.role.name
	elif worker.role != null:
		r = "Builder"
	_role.text = r.to_lower().capitalize() if r != "" else ""
	_role.visible = r != ""


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or worker == null:
		return
	_role_timer -= delta
	if _role_timer <= 0.0:
		_role_timer = 1.0
		_refresh_role()
		_status = ""
		if worker.pending_question != "" or worker.state == Worker.State.ASKING:
			_status = "?"
		elif worker.state == Worker.State.REPORTING:
			_status = "!"
	var d := cam.global_position.distance_to(global_position)
	_focus = move_toward(_focus, 1.0 if focused else 0.0, delta * 8.0)
	# Constant screen size across the working range; the floor stops it
	# growing as you walk up to someone, the fade stops it cluttering the
	# distance. A focused tag gets a little larger and always stays solid.
	var s := clampf(d, 1.5, 14.0) / REF_DIST * (1.0 + 0.12 * _focus)
	scale = Vector3.ONE * s
	_alpha = 1.0 - smoothstep(FADE_FROM, FADE_TO, d)
	_alpha = maxf(_alpha, _focus * 0.9) if d < 40.0 else 0.0
	# Close enough that the head is off the top of the screen: let it go.
	_alpha *= smoothstep(0.7, 1.4, d)
	var shown := _alpha > 0.02
	_name.visible = shown
	_role.visible = shown and _role.text != ""
	var bubble_up: bool = worker.bubble != null and worker.bubble.visible
	var badge := shown and _status != "" and not bubble_up
	_badge.visible = badge
	_glyph.visible = badge
	if not shown:
		return
	var a := _alpha
	var base := _name.modulate
	base.a = a
	_name.modulate = base
	_name.outline_modulate.a = 0.92 * a
	var rc := _role.modulate
	rc.a = 0.95 * a
	_role.modulate = rc
	_role.outline_modulate.a = 0.92 * a
	if badge:
		var bob := sin(Time.get_ticks_msec() * 0.006 + _phase) * 0.018
		_badge.position.y = 0.23 + bob
		_glyph.position.y = 0.23 + bob
		_badge.modulate = Color(1, 1, 1, a)
		var gc := Color("#ffe08a") if _status == "?" else Color("#b9f0b0")
		_glyph.modulate = Color(gc, a)
		_glyph.text = _status
