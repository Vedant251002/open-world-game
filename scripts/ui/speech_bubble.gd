extends Node3D
class_name SpeechBubble
## What somebody just said, in a rounded bubble over their head.
##
## Label3D has no background, so the old bubble was bare text with an outline
## and vanished against any wall. This draws a real panel behind the words: a
## quad whose fragment shader cuts a rounded box and a small tail out of it, so
## it is crisp at any size and costs one draw call per speaker. The quad is
## sized from the measured text, so a two-word answer gets a small bubble rather
## than a banner.
##
## Like the name tag it is scaled from the camera distance so it stays readable
## across the plaza and does not fill the screen when you are standing next to
## the speaker, and it pops in and fades out rather than blinking.

const PX := 0.0030                  ## metres per font pixel at scale one
const FONT_SIZE := 38
const WRAP_PX := 440.0
const PAD := Vector2(20.0, 13.0)
const TAIL_PX := 15.0
const REF_DIST := 5.0
const MAX_CHARS := 150

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec2 box = vec2(1.0, 0.4);
uniform float tail = 0.05;
uniform float radius = 0.07;
uniform float border = 0.010;
uniform vec4 fill : source_color = vec4(0.10, 0.085, 0.07, 0.94);
uniform vec4 edge : source_color = vec4(0.95, 0.76, 0.38, 1.0);
uniform float alpha = 1.0;
void vertex() {
	// Billboard, keeping the node's scale.
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 total = vec2(box.x, box.y + tail);
	vec2 p = (UV - 0.5) * total;
	vec2 q = p - vec2(0.0, -tail * 0.5);
	vec2 hb = box * 0.5;
	vec2 d = abs(q) - hb + vec2(radius);
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
	float below = q.y - hb.y;
	float tw = (tail - below) * 0.8;
	float sdt = max(abs(q.x) - tw, max(below - tail, -below - radius * 0.6));
	sd = min(sd, sdt);
	float aa = max(fwidth(sd), 0.0005);
	float a = 1.0 - smoothstep(-aa, aa, sd);
	float ring = smoothstep(-border - aa, -border + aa, sd);
	ALBEDO = mix(fill.rgb, edge.rgb, ring);
	ALPHA = a * mix(fill.a, 1.0, ring) * alpha;
}
"""

static var _shader: Shader = null

var _panel: MeshInstance3D
var _quad: QuadMesh
var _mat: ShaderMaterial
var _text: Label3D
var _left := 0.0
var _total := 0.0
var _age := 0.0
var _tint := Color.WHITE


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = 0
	_quad = QuadMesh.new()
	_panel = MeshInstance3D.new()
	_panel.mesh = _quad
	_panel.material_override = _mat
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.set_meta("no_highlight", true)
	add_child(_panel)

	_text = Label3D.new()
	_text.font = UiTheme.font(600)
	_text.font_size = FONT_SIZE
	_text.pixel_size = PX
	_text.width = WRAP_PX
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_text.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_text.outline_size = 0
	_text.render_priority = 2
	add_child(_text)
	position.y = 2.38
	visible = false
	set_process(false)


## `kind` picks the accent: a question is gold, a refusal rose, news green.
func say(line: String, kind: String, hold: float) -> void:
	if line.length() > MAX_CHARS:
		line = line.substr(0, MAX_CHARS - 1).strip_edges() + "…"
	_tint = _accent(kind)
	var f := _text.font
	var wrap_flags := TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY
	var sz := f.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, WRAP_PX,
		FONT_SIZE, -1, wrap_flags)
	var w := maxf(sz.x + PAD.x * 2.0, 64.0)
	var h := sz.y + PAD.y * 2.0
	var box := Vector2(w, h) * PX
	var tail := TAIL_PX * PX
	_quad.size = Vector2(box.x, box.y + tail)
	_panel.position = Vector3(0.0, (box.y + tail) * 0.5, 0.0)
	_text.text = line
	_text.position = Vector3(0.0, tail + box.y * 0.5, 0.0)
	_mat.set_shader_parameter("box", box)
	_mat.set_shader_parameter("tail", tail)
	_mat.set_shader_parameter("radius", minf(box.y * 0.5, 0.075))
	_mat.set_shader_parameter("edge", Color(_tint.r, _tint.g, _tint.b, 1.0))
	_mat.set_shader_parameter("fill", Color(0.085, 0.07, 0.058, 0.95))
	_text.modulate = Color(0.97, 0.94, 0.88).lerp(_tint, 0.18)
	_left = hold
	_total = hold
	_age = 0.0
	visible = true
	set_process(true)


func hide_now() -> void:
	_left = 0.0
	visible = false
	set_process(false)


static func _accent(kind: String) -> Color:
	match kind:
		"refuse": return Color("#ff9d8a")
		"question": return Color("#ffd466")
		"done": return Color("#9be88f")
		"work": return Color("#a9c7e6")
		_: return Color("#e8c88a")


func _process(delta: float) -> void:
	_left -= delta
	_age += delta
	if _left <= 0.0:
		hide_now()
		return
	var cam := get_viewport().get_camera_3d()
	var d := 6.0
	if cam != null:
		d = cam.global_position.distance_to(global_position)
	# Pops in over a tenth of a second, fades over the last half.
	var pop := clampf(_age / 0.12, 0.0, 1.0)
	var out := clampf(_left / 0.5, 0.0, 1.0)
	var near := smoothstep(0.7, 1.6, d)
	var far := 1.0 - smoothstep(18.0, 30.0, d)
	var a := out * near * far
	scale = Vector3.ONE * (clampf(d, 1.6, 14.0) / REF_DIST) * (0.85 + 0.15 * (1.0 - pow(1.0 - pop, 3.0)))
	_mat.set_shader_parameter("alpha", a * pop)
	var c := _text.modulate
	c.a = a * pop
	_text.modulate = c
	_text.visible = a > 0.02
