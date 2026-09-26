extends Node
## A screenshot of the chat panel with a conversation in it.
## Run with:  godot --path . -- --realmtest=chatshot --shot=<path>

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var realm: Realm
var hud: Node
var _t := 0.0
var _step := 0


func begin() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _step == 0 and _t > 6.0:
		_step = 1
		var w: Worker = crew.workers[0]
		hud._on_chat_sent(w, "how many people live here?")
		hud._on_chat_sent(w, "what is the weather like?")
		hud._on_chat_sent(w, "build a wall around the town")
		hud._on_chat_sent(crew.workers[1], "who are our neighbours?")
	elif _step == 1 and _t > 9.0:
		_step = 2
		hud.toggle_chat()
	elif _step == 2 and _t > 10.0:
		_step = 3
		var path := "user://chatshot.png"
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				path = a.substr(7)
		get_viewport().get_texture().get_image().save_png(path)
		var w: Worker = crew.workers[0]
		print("[chatshot] saved %s; %d lines with %s, open %s" % [path,
			(hud.chat.history.get(w.memory.worker_id, []) as Array).size(), w.display_name(), str(hud.chat.open)])
		get_tree().quit()
