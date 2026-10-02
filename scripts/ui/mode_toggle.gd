extends HBoxContainer
class_name ModeToggle
## Command or Chat: which of the two things the talk field is for.
##
## A command is an order — it goes to the classifier and the planner and
## somebody does something. Chat is talk — the model answers in the person's
## voice and nothing in the town changes. The same words mean different things
## in the two ("can you build a hut?" is an order in one and a question in the
## other), so the player says which, rather than the game guessing.

signal changed(mode: String)

const COMMAND := "command"
const CHAT := "chat"

var mode := COMMAND
var _buttons := {}
var _size := 14


func setup(font_size: int, height: float) -> void:
	_size = font_size
	add_theme_constant_override("separation", 4)
	for m: String in [COMMAND, CHAT]:
		var b := Button.new()
		b.text = "Command" if m == COMMAND else "Chat"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, height)
		b.tooltip_text = "Give an order: they will do it." if m == COMMAND \
			else "Just talk: they answer, nothing gets done."
		b.pressed.connect(func() -> void:
			if mode != m:
				set_mode(m)
				changed.emit(m))
		add_child(b)
		_buttons[m] = b
	_restyle()


## Shows a mode without announcing it — for keeping two toggles in step.
func set_mode(m: String) -> void:
	mode = CHAT if m == CHAT else COMMAND
	_restyle()


func _restyle() -> void:
	for m: String in _buttons:
		var b: Button = _buttons[m]
		UiTheme.style_button(b, _size, m == mode)
		b.add_theme_color_override("font_color",
			Color.WHITE if m == mode else UiTheme.DIM)
