class_name Sfx
## The one-line way to make a sound from anywhere in the game.
##
##     Sfx.click()          # a button
##     Sfx.chime()          # a toast / notification
##     Sfx.at("hammer_1", world_position)
##
## Everything here is a no-op until the AudioDirector exists and the browser
## has let audio start, so UI code can call it unconditionally.

static var host: AudioDirector = null
static var _last_hover_ms := 0


static func _ok() -> bool:
	return host != null and is_instance_valid(host)


## Gives a Button the soft click and hover. Safe to call twice on one button.
static func hook_button(b: BaseButton) -> void:
	if b.has_meta("_sfx"):
		return
	b.set_meta("_sfx", true)
	b.pressed.connect(click)
	b.mouse_entered.connect(hover)


static func click() -> void:
	if _ok():
		host.ui("ui_click", -6.0)


static func hover() -> void:
	# Sweeping the pointer across a menu must not machine-gun.
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < 90:
		return
	_last_hover_ms = now
	if _ok():
		host.ui("ui_hover", -14.0)


## A toast, a message, a small piece of news.
static func chime() -> void:
	if _ok():
		host.notify("ui_chime")


## A larger moment: a new tier, a battle won.
static func milestone() -> void:
	if _ok():
		host.notify("ui_milestone", true)


static func alert() -> void:
	if _ok():
		host.notify("ui_alert", true)


static func page() -> void:
	if _ok():
		host.ui("ui_page", -8.0)


## Positional one-shot in the world.
static func at(sound: String, pos: Vector3, db: float = -6.0, pitch: float = 1.0) -> void:
	if _ok():
		host.play3d(sound, pos, db, pitch)
