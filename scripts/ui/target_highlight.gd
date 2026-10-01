extends RefCounted
class_name TargetHighlight
## The glow on whatever the crosshair is resting on.
##
## A dot in the middle of the screen says "something is there"; this says what.
## It is a fresnel rim plus a faint fill, laid over the target's own meshes as a
## material_overlay, so it needs no cooperation from whoever built the model —
## a batched villager, a single crop mesh and anything else with MeshInstance3Ds
## in it light up the same way, and clearing it puts every mesh back exactly as
## it was. Additive blending means it can only ever brighten, never repaint.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 glow : source_color = vec4(1.0, 0.80, 0.42, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.8);
	float pulse = 0.88 + 0.12 * sin(TIME * 4.5);
	ALBEDO = glow.rgb * (0.11 + rim * 0.95) * pulse;
	ALPHA = 1.0;
}
"""

## The silhouette: the same mesh pushed out along its normals and drawn from
## the inside, so only a rim of it shows round the edge of the real thing.
const HULL := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 glow : source_color = vec4(1.0, 0.80, 0.42, 1.0);
void vertex() {
	VERTEX += NORMAL * 0.022;
}
void fragment() {
	ALBEDO = glow.rgb;
	ALPHA = 0.85 + 0.15 * sin(TIME * 4.5);
}
"""

static var _mat: ShaderMaterial = null
static var _current: Node = null
static var _meshes: Array[MeshInstance3D] = []


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		var hs := Shader.new()
		hs.code = HULL
		var hull := ShaderMaterial.new()
		hull.shader = hs
		_mat.next_pass = hull
	return _mat


## Lights `node` up and puts out whatever was lit before. Null clears.
static func set_target(node: Node) -> void:
	if node == _current:
		return
	clear()
	if node == null or not is_instance_valid(node):
		return
	_current = node
	_collect(node)
	for m in _meshes:
		m.material_overlay = material()
	if node.get("nametag") != null:
		(node.get("nametag") as Object).set("focused", true)


static func clear() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = null
	_meshes.clear()
	if _current != null and is_instance_valid(_current) and _current.get("nametag") != null:
		(_current.get("nametag") as Object).set("focused", false)
	_current = null


static func _collect(n: Node) -> void:
	if n is MeshInstance3D and not n.has_meta("no_highlight") \
			and (n as MeshInstance3D).mesh != null:
		_meshes.append(n)
	for c in n.get_children():
		_collect(c)
