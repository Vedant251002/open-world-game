extends CanvasLayer
## Command console: press T (or Enter), type an order in plain English,
## the free internet LLM parses it, a worker builds it.

const AICommand := preload("res://scripts/ai_command.gd")
const WorkerAgent := preload("res://scripts/worker_agent.gd")

var ai: Node
var input: LineEdit
var log_label: RichTextLabel
var open := false
var gen: Node3D
var main: Node
var workers: Array = []


func _ready() -> void:
	layer = 10

	ai = AICommand.new()
	add_child(ai)
	ai.order_ready.connect(_on_order)
	ai.status.connect(_on_status)

	# chat log (top-left, below title)
	log_label = RichTextLabel.new()
	log_label.position = Vector2(16, 44)
	log_label.size = Vector2(640, 170)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_label)

	# input row
	input = LineEdit.new()
	input.placeholder_text = "Press T and command your workers... e.g. 'build a cafeteria near the beach'"
	input.position = Vector2(16, 640)
	input.size = Vector2(640, 34)
	input.visible = false
	add_child(input)
	input.text_submitted.connect(_on_submit)


func bind(g: Node3D, m: Node) -> void:
	gen = g
	main = m


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T and not open:
			_open()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and open:
			_close()
			get_viewport().set_input_as_handled()


func _open() -> void:
	open = true
	input.visible = true
	input.grab_focus()
	if main and main.get("player"):
		main.player.ui_block = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	open = false
	input.visible = false
	input.release_focus()
	if main and main.get("player"):
		main.player.ui_block = false


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	input.clear()
	_close()
	if t == "":
		return
	_log("[color=#ff9ad5]You:[/color] " + t)
	if ai.available():
		ai.submit(t)
	else:
		ai._fallback_parse(t)


func _on_status(msg: String) -> void:
	_log("[color=#9ad5ff]Advisor:[/color] " + msg)


func _log(line: String) -> void:
	log_label.append_text(line + "\n")


# ------------------------------------------------ order handling
func _on_order(order: Dictionary) -> void:
	var action: String = order.get("action", "query")
	var obj: String = order.get("object", "")
	var loc: String = order.get("location", "here")

	if action == "build" and obj != "":
		var pos := _pick_site(loc)
		var bldg := _building_for(obj)
		var display := obj if obj != "" else "building"
		_log("[color=#9ad5ff]Advisor:[/color] Order received: %s %s at the %s. Dispatching a worker." % [action, display, loc])
		var w := WorkerAgent.new()
		main.add_child(w)
		w.global_position = _worker_spawn(pos)
		w.gen_ref = gen
		w.assign(order, pos, bldg, display)
		workers.append(w)
	elif action == "demolish":
		_log("[color=#9ad5ff]Advisor:[/color] Demolition orders come in the next phase, my liege.")
	else:
		_log("[color=#9ad5ff]Advisor:[/color] I can order the building of: cafeteria, hotel, house, shop, tower, office, garage... Try 'build a hotel near the beach'.")


func _worker_spawn(site: Vector3) -> Vector3:
	var p: Vector3 = main.player.global_position if main and main.get("player") else site + Vector3(6, 0, 6)
	p = p + Vector3(2, 0, 2)
	p.y = 0.15
	if p.distance_to(site) > 60.0:
		p = site + Vector3(10, 0.15, 10)
	return p


func _pick_site(loc: String) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())
	match loc:
		"beach":
			return Vector3(rng.randf_range(160.0, 230.0), 0.0, rng.randf_range(-120.0, 120.0))
		"park":
			return Vector3(120 + rng.randf_range(-8, 8), 0.0, -72 + rng.randf_range(-8, 8))
		"downtown":
			return Vector3(rng.randf_range(-30.0, 30.0), 0.0, rng.randf_range(-30.0, 30.0))
		"market":
			return Vector3(rng.randf_range(20.0, 60.0), 0.0, rng.randf_range(20.0, 60.0))
		"ocean":
			return Vector3(rng.randf_range(160.0, 230.0), 0.0, rng.randf_range(-120.0, 120.0))
		_:
			# "here": 12m in front of the player
			var p: Vector3 = main.player.global_position if main and main.get("player") else Vector3(10, 0, 10)
			var fwd := -Vector3(sin(main.player.rotation.y), 0, cos(main.player.rotation.y))
			var site := p + fwd * 12.0
			site.y = 0.0
			return site


func _building_for(obj: String) -> String:
	var big := ["hotel", "tower", "office", "apartment", "hospital", "school", "museum", "library", "bank"]
	var small := ["house", "shop", "cafe", "cafeteria", "restaurant", "bar", "garage", "gym", "market", "statue"]
	obj = obj.to_lower()
	for b in big:
		if b in obj:
			return "res://assets/buildings/sky_%d.glb" % ((obj.length() % 3) + 1)
	for s in small:
		if s in obj:
			return "res://assets/buildings/bldg_%d.glb" % ((obj.length() % 14) + 1)
	return "res://assets/buildings/bldg_%d.glb" % ((obj.length() % 14) + 1)
