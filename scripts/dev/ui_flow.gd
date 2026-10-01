extends Node
class_name UiFlow
## The game played through its interface, not through the dispatcher.
##
## Every step goes in the way a player's does: the player is turned to face
## somebody, the talk action is pressed, a sentence is typed into the bar and
## submitted (or a phrase button is tapped), and the map, stores, chat and
## pause screens are opened and closed with their own actions. What is checked
## is what the player would see: the bar opening for the right person, a line
## coming back in the subtitles, a panel opening and closing.
##
##   godot4 --headless --path . -- --uiflow --nosave --noquick \
##     --proxy=http://127.0.0.1:8787/v1/chat/completions
##   ... add --uiflowshots=/abs/dir under a display for a picture per step.

var hud: Hud
var crew: Crew
var player: Player
var map: MapScreen
var inventory: InventoryScreen
var pause: PauseMenu

const REPLY_WAIT := 25.0

var _steps: Array[Dictionary] = []
var _i := -1
var _t := 0.0
var _armed := false
var _wait := 0.0
var _phase := 0
var _results: Array[Dictionary] = []
var _heard: Array[String] = []
var _shots := ""
var _frozen: Worker = null


func begin() -> void:
	# The pause menu pauses the tree; this has to keep running to close it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--uiflowshots="):
			_shots = a.substr(14)
			DirAccess.make_dir_recursive_absolute(_shots)
	crew.worker_spoke.connect(func(w: Worker, line: String, _k: String) -> void:
		_heard.append("%s: %s" % [w.display_name(), line]))
	_steps = [
		{"name": "talk to Mira opens the bar", "who": "mira", "do": "open"},
		{"name": "typed greeting gets a reply", "who": "mira", "do": "type", "say": "hello Mira"},
		{"name": "typed question gets an answer", "who": "mira", "do": "type",
			"say": "what are you doing?"},
		{"name": "phrase button orders a build", "who": "tobias", "do": "phrase",
			"phrase": "build a hut"},
		{"name": "the assumptions panel shows the plan", "do": "assumptions"},
		{"name": "a stranger can be hired from the bar", "who": "citizen", "do": "type",
			"say": "hire you as a shepherd", "expect": "hired"},
		{"name": "the new shepherd takes an order", "who": "citizen", "do": "type",
			"say": "bring 4 sheep"},
		{"name": "chat panel opens", "do": "action", "action": "chat", "check": "chat_open"},
		{"name": "chat panel closes", "do": "action", "action": "menu", "check": "chat_closed"},
		{"name": "map opens", "do": "action", "action": "map", "check": "map_open"},
		{"name": "map closes", "do": "action", "action": "map", "check": "map_closed"},
		{"name": "stores open", "do": "action", "action": "inventory", "check": "inv_open"},
		{"name": "stores close", "do": "action", "action": "inventory", "check": "inv_closed"},
		{"name": "pause opens", "do": "action", "action": "menu", "check": "pause_open"},
		{"name": "pause closes", "do": "action", "action": "menu", "check": "pause_closed"},
		{"name": "Esc closes the bar without sending", "who": "ren", "do": "cancel"},
	]
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if _wait > 8.0:
			_armed = true
			_citizen = crew.citizens()[0] if not crew.citizens().is_empty() else null
			_next()
		return
	_t += delta
	_tick()


var _citizen: Worker = null


func _who(s: Dictionary) -> Worker:
	var w := str(s.get("who", ""))
	if w == "citizen":
		return _citizen
	return crew.get_worker(w)


func _next() -> void:
	if _frozen != null and is_instance_valid(_frozen):
		_frozen.set_physics_process(true)
		_frozen = null
	_i += 1
	_t = 0.0
	_phase = 0
	_heard.clear()
	if _i >= _steps.size():
		_finish()


func _tick() -> void:
	if _i >= _steps.size():
		return
	var s: Dictionary = _steps[_i]
	match str(s["do"]):
		"open", "type", "phrase", "cancel":
			_tick_talk(s)
		"assumptions":
			_pass_if(hud._assume.visible, s, "panel %s" % (
				"up" if hud._assume.visible else "never shown"), 6.0)
		"action":
			if _phase == 0:
				_press(str(s["action"]))
				_phase = 1
			elif _t > 0.6:
				var ok := _check(str(s["check"]))
				_done(s, ok, str(s["check"]))


func _tick_talk(s: Dictionary) -> void:
	var w := _who(s)
	if w == null:
		_done(s, false, "nobody to talk to")
		return
	if _phase == 0:
		_face(w)
		_phase = 1
		return
	if _phase == 1:
		if hud._target != w:
			if _t > 4.0:
				_done(s, false, "could not get %s in the crosshair" % w.display_name())
			return
		_press("talk")
		_phase = 2
		_t = 0.0
		return
	if _phase == 2:
		if hud._typing_for != w:
			if _t > 2.0:
				_done(s, false, "talk did not open the bar for %s" % w.display_name())
			return
		_shot("bar")
		match str(s["do"]):
			"open":
				_press("menu")
				_done(s, true, "bar opened: \"%s\"" % hud._barlabel.text)
				return
			"cancel":
				hud._entry.text = "this must not be sent"
				_press("menu")
				_phase = 4
				_t = 0.0
				return
			"phrase":
				var b := _phrase_button(str(s["phrase"]))
				if b == null:
					_done(s, false, "no phrase button \"%s\"" % s["phrase"])
					return
				_heard.clear()
				b.pressed.emit()
			_:
				hud._entry.text = str(s["say"])
				_heard.clear()
				hud._entry.text_submitted.emit(hud._entry.text)
		_phase = 3
		_t = 0.0
		return
	if _phase == 3:
		var mine := _heard.filter(func(l: String) -> bool:
			return l.begins_with(w.display_name() + ":"))
		if str(s.get("expect", "")) == "hired":
			if w.hired and not mine.is_empty():
				_shot("reply")
				_done(s, true, "hired as %s; %s" % [w.role.name if w.role else "?", mine[-1]])
			elif _t > REPLY_WAIT:
				_done(s, false, "not hired after %.0fs (%s)" % [_t, " | ".join(_heard)])
			return
		if not mine.is_empty() and _t > 1.5:
			_shot("reply")
			_done(s, true, mine[-1])
		elif _t > REPLY_WAIT:
			_done(s, false, "no reply in %.0fs (%s)" % [REPLY_WAIT,
				" | ".join(_heard) if not _heard.is_empty() else "silence"])
		return
	if _phase == 4:
		if _t > 1.5:
			var sent := _heard.any(func(l: String) -> bool: return l.begins_with(w.display_name()))
			_done(s, hud._typing_for == null and not sent,
				"bar closed=%s, %s" % [hud._typing_for == null, "a reply came" if sent else "nothing sent"])


func _pass_if(cond: bool, s: Dictionary, why: String, limit: float) -> void:
	if cond:
		_shot("panel")
		_done(s, true, why)
	elif _t > limit:
		_done(s, false, why)


func _check(what: String) -> bool:
	match what:
		"chat_open": return hud.chat != null and hud.chat.open
		"chat_closed": return hud.chat != null and not hud.chat.open
		"map_open": return map != null and map.open
		"map_closed": return map != null and not map.open
		"inv_open": return inventory != null and inventory.open
		"inv_closed": return inventory != null and not inventory.open
		"pause_open": return pause != null and pause.open
		"pause_closed": return pause != null and not pause.open
	return false


func _press(action: String) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)


## Stand two and a half metres in front of somebody and look at their chest.
func _face(w: Worker) -> void:
	w.set_physics_process(false)
	_frozen = w
	var front := w.global_position + Vector3(0.0, 0.0, 2.5)
	var to := w.global_position + Vector3(0, 1.1, 0) - (front + Vector3(0, 1.6, 0))
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	player.teleport(front, yaw, pitch)


func _phrase_button(text: String) -> Button:
	for b: Node in hud.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


func _shot(tag: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_shots, _i, tag])


func _done(s: Dictionary, ok: bool, why: String) -> void:
	_results.append({"step": s["name"], "ok": ok, "why": why, "seconds": snappedf(_t, 0.1)})
	print("[uiflow] %2d %s %-40s %s" % [_i, "[ok]  " if ok else "[FAIL]", s["name"], why.substr(0, 140)])
	_next()


func _finish() -> void:
	var fails := _results.filter(func(r: Dictionary) -> bool: return not r["ok"])
	print("[uiflow] %d/%d steps ok" % [_results.size() - fails.size(), _results.size()])
	var f := FileAccess.open("user://ui_flow.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_results, "  "))
	f.close()
	print("[uiflow] %s" % ("=== PASS ===" if fails.is_empty() else "=== FAIL ==="))
	get_tree().quit(0 if fails.is_empty() else 1)
