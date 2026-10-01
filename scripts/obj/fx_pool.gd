extends MultiMeshInstance3D
class_name FxPool
## A fixed pool of little cubes that fly, fall and fade: dust, smoke, sparks,
## confetti, fireflies.
##
## Not GPUParticles3D, on purpose. The web build runs gl_compatibility, where
## GPU particles are the part of the renderer that breaks first and differ most
## between browsers; a MultiMesh updated on the CPU is one draw call, behaves
## identically everywhere, and at a few hundred cubes costs less than the
## draw call does. Live particles are kept packed at the front of the buffer and
## the instance count is set to match, so an idle pool draws nothing.

class P:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var col := Color.WHITE
	var size := 0.1
	var grow := 0.0           ## size added per second
	var life := 1.0
	var age := 0.0
	var gravity := 0.0
	var drag := 0.0
	var wind := 0.0           ## how much the shared breeze pushes it
	var yaw := 0.0
	var spin := 0.0
	var fade_in := 0.0
	var flicker := 0.0        ## 0 steady; >0 pulses its alpha at this rate
	var phase := 0.0
	var wobble := 0.0         ## lazy sideways drift, metres per second
	var flap := false         ## beats its wings (squashes on a fast sine)

var capacity := 160
var wind := Vector3.ZERO
var _live: Array[P] = []
var _mm: MultiMesh


## additive: glowing things (sparks, fireflies); otherwise ordinary alpha.
func setup(cap: int, additive: bool = false) -> FxPool:
	capacity = cap
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mm.mesh = box
	_mm.instance_count = cap
	_mm.visible_instance_count = 0
	multimesh = _mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	m.render_priority = 3
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles are scattered across the whole town; the box that is culled
	# against has to cover it or they vanish when the pool's origin leaves view.
	custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 400, 1000))
	top_level = true
	set_process(false)
	return self


func count() -> int:
	return _live.size()


func full() -> bool:
	return _live.size() >= capacity


## Returns the particle so the caller can set the rarer fields, or null when
## the pool is full — a burst that does not fit is simply a smaller burst.
func emit(pos: Vector3, vel: Vector3, col: Color, size: float, life: float,
		gravity: float = 0.0, drag: float = 0.0) -> P:
	if _live.size() >= capacity:
		return null
	var p := P.new()
	p.pos = pos
	p.vel = vel
	p.col = col
	p.size = size
	p.life = life
	p.gravity = gravity
	p.drag = drag
	p.yaw = randf() * TAU
	p.phase = randf() * 100.0
	_live.append(p)
	set_process(true)
	return p


func clear() -> void:
	_live.clear()
	_mm.visible_instance_count = 0
	set_process(false)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var i := 0
	while i < _live.size():
		var p := _live[i]
		p.age += delta
		if p.age >= p.life:
			_live[i] = _live[_live.size() - 1]
			_live.pop_back()
			continue
		p.vel.y -= p.gravity * delta
		if p.drag > 0.0:
			p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		p.pos += (p.vel + wind * p.wind) * delta
		if p.wobble > 0.0:
			p.pos += Vector3(sin(p.age * 1.7 + p.phase), sin(p.age * 2.9 + p.phase * 1.7) * 0.45,
				cos(p.age * 1.3 + p.phase * 0.6)) * p.wobble * delta
		p.size += p.grow * delta
		p.yaw += p.spin * delta
		var t := p.age / p.life
		var a := p.col.a
		# Ease in over fade_in seconds, out over the last third of its life.
		if p.fade_in > 0.0:
			a *= clampf(p.age / p.fade_in, 0.0, 1.0)
		if t > 0.66:
			a *= clampf((1.0 - t) / 0.34, 0.0, 1.0)
		if p.flicker > 0.0:
			a *= 0.55 + 0.45 * sin(p.age * p.flicker + p.phase)
		var s := maxf(p.size, 0.001)
		var sy := s
		if p.flap:
			sy = s * (0.25 + 0.75 * absf(sin(p.age * 16.0 + p.phase)))
		var basis := Basis(Vector3.UP, p.yaw).scaled(Vector3(s, sy, s))
		_mm.set_instance_transform(i, Transform3D(basis, p.pos))
		_mm.set_instance_color(i, Color(p.col.r, p.col.g, p.col.b, a))
		i += 1
	_mm.visible_instance_count = _live.size()
	if _live.is_empty():
		set_process(false)
