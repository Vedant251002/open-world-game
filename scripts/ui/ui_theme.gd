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
## Warm parchment and gold on dark, faintly brown glass: a lantern-lit village.
const INK := Color(0.96, 0.93, 0.86)          ## primary text (warm cream)
const DIM := Color(0.76, 0.72, 0.64)          ## secondary text
const FAINT := Color(0.56, 0.53, 0.47)        ## disabled / hints
const ACCENT := Color(0.96, 0.76, 0.38)       ## anything actionable: money, prompts
const GOLD := Color(0.91, 0.72, 0.36)         ## borders, ornaments
const WARN := Color(1.0, 0.84, 0.46)          ## waiting on an answer
const ALERT := Color(0.96, 0.46, 0.38)        ## refused, or in debt
const GOOD := Color(0.56, 0.80, 0.50)         ## working / fine
const SKY := Color(0.55, 0.74, 0.92)          ## night, water, info
const PARCHMENT := Color("#efe3c6")
const PARCH_DARK := Color("#d9c79a")
const SEPIA := Color("#3a2a1a")
const PANEL := Color(0.075, 0.062, 0.050, 0.80)
const PANEL_SOLID := Color(0.085, 0.072, 0.060, 0.97)
const EDGE := Color(0.95, 0.80, 0.50, 0.20)
const EDGE_STRONG := Color(0.95, 0.80, 0.50, 0.48)

const FONT_BODY := "res://assets/fonts/Manrope.ttf"
const FONT_DISPLAY := "res://assets/fonts/Cinzel.ttf"

## Font sizes at scale 1.0, in design pixels.
const FS_TINY := 13
const FS_SMALL := 15
const FS_BODY := 18
const FS_LABEL := 21
const FS_HEAD := 28
const FS_DISPLAY := 44

## Radii and spacing, one scale for every panel.
const R_SM := 6
const R_MD := 12
const R_LG := 16

static var _fonts: Dictionary = {}
static var _theme: Theme = null


## Manrope at a weight. Cached; falls back to the engine font if the file is
## missing so a bad export never leaves the game without text.
static func font(weight: int = 500) -> Font:
	return _make_font(FONT_BODY, weight, "b%d" % weight)


## Cinzel, for titles and numerals that should feel engraved.
static func display(weight: int = 600) -> Font:
	return _make_font(FONT_DISPLAY, weight, "d%d" % weight)


static func _make_font(path: String, weight: int, key: String) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(path):
		var base: Variant = load(path)
		if base is Font:
			var fv := FontVariation.new()
			fv.base_font = base
			var ts := TextServerManager.get_primary_interface()
			fv.variation_opentype = {ts.name_to_tag("wght"): float(weight)}
			f = fv
	_fonts[key] = f
	return f


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


## The standard panel: dark warm glass, a hairline gold edge and a soft
## drop shadow so it lifts off a bright sky as well as a dark interior.
static func panel(alpha: float = 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * alpha)
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px(R_MD)))
	sb.set_content_margin_all(px(14))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = int(px(10))
	sb.shadow_offset = Vector2(0, px(3))
	sb.anti_aliasing = true
	return sb


## Same glass, tighter: crew cards, chips, toasts.
static func card(alpha: float = 1.0, radius: int = R_SM + 2) -> StyleBoxFlat:
	var sb := panel(alpha)
	sb.set_corner_radius_all(int(px(radius)))
	sb.set_content_margin_all(px(9))
	sb.content_margin_left = px(12)
	sb.content_margin_right = px(12)
	sb.shadow_size = int(px(6))
	return sb


## A panel that means "this is the thing you are currently doing" — the order
## bar, the subtitle. Brighter gold edge, slightly more opaque.
static func panel_active() -> StyleBoxFlat:
	var sb := panel()
	sb.bg_color = Color(PANEL_SOLID.r, PANEL_SOLID.g, PANEL_SOLID.b, 0.92)
	sb.border_color = EDGE_STRONG
	return sb


## Opaque menu panel with a gold border, for the pause and title screens.
static func panel_menu() -> StyleBoxFlat:
	var sb := panel()
	sb.bg_color = PANEL_SOLID
	sb.border_color = EDGE_STRONG
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px(R_LG)))
	sb.set_content_margin_all(px(28))
	sb.shadow_size = int(px(28))
	sb.shadow_color = Color(0, 0, 0, 0.55)
	return sb


## A label with the game's type treatment: the colour, the size, and a shadow.
##
## The shadow is not decoration. The HUD is drawn over a bright noon sky as
## often as over a dark interior, so text carries a soft dark drop shadow.
static func label(text: String, size: int, colour: Color = INK, weight: int = 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Small-caps style section title (Cinzel, spaced).
static func title(text: String, size: int, colour: Color = ACCENT) -> Label:
	var l := label(text, size, colour, 700)
	l.add_theme_font_override("font", display(700))
	return l


## A keyboard key cap: "E", "M". Used in hint chips and prompts.
static func key_cap(key: String, size: int = FS_TINY) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.92, 0.75, 0.14)
	sb.border_color = Color(1, 0.9, 0.7, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(int(px(5)))
	sb.content_margin_left = px(7)
	sb.content_margin_right = px(7)
	sb.content_margin_top = px(1)
	sb.content_margin_bottom = px(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(label(key, size, INK, 800))
	return pc


## Key cap plus a word: "[E] speak".
static func chip(key: String, text: String, size: int = FS_TINY) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(px(6)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(key_cap(key, size))
	var l := label(text, size, DIM, 600)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


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


## A button that matches the rest of the interface.
static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	style_button(b, FS_SMALL)
	return b


## Applies the game's button look to any Button: normal / hover / pressed /
## focus / disabled states, warm text, gold on hover.
static func style_button(b: Button, size: int = FS_SMALL, primary: bool = false) -> void:
	b.add_theme_font_override("font", font(700 if primary else 600))
	b.add_theme_font_size_override("font_size", fs(size))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.add_theme_stylebox_override("normal", _btn_style(0, primary))
	b.add_theme_stylebox_override("hover", _btn_style(1, primary))
	b.add_theme_stylebox_override("pressed", _btn_style(2, primary))
	b.add_theme_stylebox_override("focus", _btn_style(1, primary, ACCENT))
	b.add_theme_stylebox_override("disabled", _btn_style(0, primary))
	# Sound: the soft click and hover (scripts/audio/sfx.gd). A no-op until the
	# audio director exists; safe to call again on the same button.
	Sfx.hook_button(b)


## state: 0 rest, 1 hover, 2 pressed.
static func _btn_style(state: int, primary: bool = false, border: Color = EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var base := Color(0.16, 0.13, 0.10, 0.82)
	if primary:
		base = Color(0.42, 0.30, 0.13, 0.92)
	var lift: float = [0.0, 0.10, -0.05][state]
	sb.bg_color = Color(base.r + lift, base.g + lift * 0.8, base.b + lift * 0.5, base.a)
	sb.border_color = border if border != EDGE else (EDGE_STRONG if state > 0 or primary else EDGE)
	if state == 1:
		sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px(R_SM + 2)))
	sb.set_content_margin_all(px(9))
	sb.content_margin_left = px(16)
	sb.content_margin_right = px(16)
	sb.anti_aliasing = true
	if state == 2:
		sb.content_margin_top = px(10)
		sb.content_margin_bottom = px(8)
	return sb


## A Theme carrying the whole look, assigned to each UI root so every stock
## control (buttons, line edits, scrollbars, tooltips) inherits it.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = fs(FS_BODY)
	t.set_color("font_color", "Label", INK)
	# Button
	for n: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var idx := ["normal", "hover", "pressed", "focus", "disabled"].find(n)
		t.set_stylebox(n, "Button", _btn_style(mini(idx, 2) if idx < 3 else (1 if idx == 3 else 0), false, ACCENT if n == "focus" else EDGE))
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", fs(FS_SMALL))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", FAINT)
	# LineEdit
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.03, 0.025, 0.02, 0.72)
	le.border_color = EDGE
	le.set_border_width_all(1)
	le.set_corner_radius_all(int(px(R_SM + 2)))
	le.content_margin_left = px(12)
	le.content_margin_right = px(12)
	le.content_margin_top = px(7)
	le.content_margin_bottom = px(7)
	le.anti_aliasing = true
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	lef.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	# Scrollbars: thin gold-ish grabbers.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	track.set_corner_radius_all(4)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.38)
	grab.set_corner_radius_all(4)
	var grab_h := grab.duplicate() as StyleBoxFlat
	grab_h.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.65)
	for cls: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, track)
		t.set_stylebox("grabber", cls, grab)
		t.set_stylebox("grabber_highlight", cls, grab_h)
		t.set_stylebox("grabber_pressed", cls, grab_h)
	t.set_stylebox("panel", "PanelContainer", panel())
	_theme = t
	return t


## Gives a UI root the shared theme.
static func apply(root: Node) -> void:
	if root is Control:
		(root as Control).theme = theme()
	elif root is Window:
		(root as Window).theme = theme()


## Font for _draw() code, at a weight.
static func draw_font(weight: int = 600) -> Font:
	return font(weight)


## A drop-shadowed string for _draw() code.
static func draw_text(ci: CanvasItem, at: Vector2, s: String, size: int, colour: Color,
		weight: int = 600, shadow: bool = true, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0) -> void:
	var f := font(weight)
	if shadow:
		ci.draw_string(f, at + Vector2(0, 1), s, align, width, size, Color(0, 0, 0, 0.55))
	ci.draw_string(f, at, s, align, width, size, colour)


