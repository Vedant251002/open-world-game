class_name Platform
## Where the game is actually running.
##
## The web build is the only way DELEGATE reaches a phone, so the question that
## matters is not "is this Android" but "does this thing have fingers instead of
## a mouse". A touchscreen laptop answers yes to both; we let it, because the
## touch HUD costs nothing there and the keyboard keeps working alongside it.


## Whether to put the thumb HUD on screen at all.
static func has_touch() -> bool:
	return DisplayServer.is_touchscreen_available()


static func is_web() -> bool:
	return OS.has_feature("web")


## True where the GPU is a phone GPU: fewer samples, no screen-space effects,
## a shorter draw distance. Deliberately includes desktop-shaped web builds
## running on a tablet, and deliberately excludes a touchscreen desktop, which
## has the silicon to render the full thing.
static func is_handheld() -> bool:
	if OS.has_feature("mobile"):
		return true
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return is_web() and has_touch()
