class_name UiTheme
## One place for how the interface looks, and how big it is.
##
## The HUD used to build its own stylebox and set font sizes per label, which
## meant a change to either had to be made in a dozen places and there was no
## way to answer "is this readable on a phone" except by counting pixels by
## hand. Everything here is driven by one scale factor and one palette, so
## answering that question is a single number.
##
## The design language is deliberately restrained: near-black translucent
## panels, a single warm accent for anything the player can act on, a single
## red for anything that has gone wrong, and nothing else. A busy interface in
## a game whose entire premise is talking to people about buildings would be
## arguing with itself.

## Interface scale, 0.6 to 1.6. Set from the settings menu.
const DEFAULT_SCALE := 1.0
const MIN_SCALE := 0.6
const MAX_SCALE := 1.6

## The palette. Named by role, not by colour, so a change is one edit.
const INK := Color(0.94, 0.93, 0.90)          ## primary text
const DIM := Color(0.66, 0.65, 0.62)          ## secondary text
const FAINT := Color(0.44, 0.44, 0.42)        ## disabled / hints
const ACCENT := Color(0.98, 0.80, 0.36)       ## anything actionable: money, prompts
const WARN := Color(1.0, 0.84, 0.46)          ## waiting on an answer
const ALERT := Color(0.96, 0.46, 0.38)        ## refused, or in debt
const PANEL := Color(0.043, 0.047, 0.055, 0.82)
const PANEL_SOLID := Color(0.055, 0.059, 0.067, 0.96)
const EDGE := Color(1, 1, 1, 0.10)
const EDGE_STRONG := Color(1, 1, 1, 0.22)

## Font sizes at scale 1.0, in design pixels.
const FS_TINY := 13
const FS_SMALL := 15
const FS_BODY := 18
const FS_LABEL := 21
const FS_HEAD := 28
const FS_DISPLAY := 44

## One live scale, read by every builder. Not a const because the settings menu
## changes it while the game is running and the HUD has to rebuild.
static var scale: float = DEFAULT_SCALE


static func _apply_scale() -> void:
	scale = clampf(scale, MIN_SCALE, MAX_SCALE)


## Scaled font size. Every font size in the game goes through here, which is
## what makes the whole interface respond to one setting.
static func fs(base: int) -> int:
	return maxi(9, int(round(base * scale)))


## Scaled pixel length, for margins and control sizes.
static func px(base: float) -> float:
	return base * scale


## The standard panel. Semi-transparent, one-pixel edge, a radius small enough
## to read as a tool rather than a card.
static func panel(alpha: float = 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * alpha)
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px(3)))
	sb.set_content_margin_all(px(12))
	return sb


## A panel that means "this is the thing you are currently doing" — the order
## bar, the subtitle. Brighter edge, slightly more opaque, so the eye finds it
## without a border animation.
static func panel_active() -> StyleBoxFlat:
	var sb := panel()
	sb.bg_color = Color(PANEL_SOLID.r, PANEL_SOLID.g, PANEL_SOLID.b, 0.94)
	sb.border_color = EDGE_STRONG
	return sb


## A label with the game's type treatment: the colour, the size, and a shadow.
##
## The shadow is not decoration. The HUD is drawn over a bright noon sky as
## often as over a dark interior, and white text on pale sky is unreadable
## without it. A hard 1px drop shadow is cheaper than an outline and, against
## a photographic background, reads better than a halo.
static func label(text: String, size: int, colour: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The crosshair.
##
## It was a 6x6 ColorRect, which is three pixels of white line and nothing else:
## no centre dot, no outline, and no change of state when there is something to
## talk to. What it is now is a four-blade cross with a gap in the middle, a
## dark outline on every blade so it survives a bright sky, and a centre dot
## that only appears when there is a target — which is the single most useful
## piece of information the interface can give you and cost one boolean.
static func crosshair(blade: float, gap: float, thickness: float) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	var span := blade + gap
	var s := px(span) * 2.0
	root.offset_left = -s * 0.5
	root.offset_right = s * 0.5
	root.offset_top = -s * 0.5
	root.offset_bottom = s * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := Color(1, 1, 1, 0.88)
	var edge := Color(0, 0, 0, 0.55)
	var t := maxf(px(thickness), 1.0)

	# Four blades, each drawn twice: once dark and slightly larger as an
	# outline, once bright on top. Doing it as two rects rather than a shader
	# keeps this a plain Control with no material and no draw call ordering to
	# reason about.
	for i in 4:
		var horiz := i < 2
		var up := i % 2 == 0
		var ox := 0.0
		var oy := 0.0
		if horiz:
			ox = (0.0 if up else 1.0) * px(span) * 0.5 + px(gap) * 0.5
		else:
			oy = (0.0 if up else 1.0) * px(span) * 0.5 + px(gap) * 0.5
		for pass_i in 2:
			var r := ColorRect.new()
			var w := t + (1.0 if pass_i == 0 else 0.0)
			var ln := px(blade)
			if horiz:
				r.offset_left = ox
				r.offset_right = ox + ln
				r.offset_top = -w * 0.5
				r.offset_bottom = w * 0.5
			else:
				r.offset_left = -w * 0.5
				r.offset_right = w * 0.5
				r.offset_top = oy
				r.offset_bottom = oy + ln
			r.color = edge if pass_i == 0 else col
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(r)
	return root


## The centre dot that appears only when the look ray has hit something.
static func crosshair_dot() -> ColorRect:
	var d := ColorRect.new()
	var s := maxf(px(3), 2.0)
	d.anchor_left = 0.5
	d.anchor_right = 0.5
	d.anchor_top = 0.5
	d.anchor_bottom = 0.5
	d.offset_left = -s * 0.5
	d.offset_right = s * 0.5
	d.offset_top = -s * 0.5
	d.offset_bottom = s * 0.5
	d.color = ACCENT
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## A button that matches the rest of the interface. Godot's default button is a
## grey slab with a focus ring and it does not belong here next to a
## hand-built panel.
static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs(FS_SMALL))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_stylebox_override("normal", _btn_style(0.10))
	b.add_theme_stylebox_override("hover", _btn_style(0.20))
	b.add_theme_stylebox_override("pressed", _btn_style(0.30))
	b.add_theme_stylebox_override("focus", _btn_style(0.20, ACCENT))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _btn_style(alpha: float, border: Color = EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, alpha + 0.30)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px(3)))
	sb.set_content_margin_all(px(9))
	sb.content_margin_left = px(14)
	sb.content_margin_right = px(14)
	return sb
