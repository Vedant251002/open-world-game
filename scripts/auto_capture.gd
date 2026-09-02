extends Node
## Automated verification: teleports the player camera through a tour of the
## city, saves screenshots, prints their paths, then quits.
## Run: godot --path . -- --autocap

var player: CharacterBody3D
var gen: Node3D
var main: Node3D


func _ready() -> void:
	await _wait(1.6)
	if player == null:
		get_tree().quit()
		return
	player.autopilot = true
	var dir := ProjectSettings.globalize_path("user://").path_join("autocap")
	DirAccess.make_dir_recursive_absolute(dir)

	var shots: Array = [
		{"n": "01_spawn_avenue", "p": Vector3(7.5, 0.15, -30), "yaw": 180.0, "pitch": 4.0},
		{"n": "02_intersection", "p": Vector3(0, 0.05, 0), "yaw": 135.0, "pitch": 5.0},
		{"n": "03_downtown", "p": Vector3(-20, 0.15, 60), "yaw": 200.0, "pitch": 8.0},
		{"n": "04_traffic", "p": Vector3(55.5, 0.15, -70), "yaw": 180.0, "pitch": 4.0},
		{"n": "05_park", "p": Vector3(120, 0.15, -72), "yaw": 30.0, "pitch": 6.0},
		{"n": "06_beach_ocean", "p": Vector3(200, 0.1, 0), "yaw": -90.0, "pitch": 6.0},
		{"n": "07_neon_street", "p": Vector3(7.5, 0.7, 30), "yaw": 195.0, "pitch": 12.0},
	]

	if gen and gen.get("shop_entries") and not gen.shop_entries.is_empty():
		var e: Dictionary = gen.shop_entries[0]
		shots.append({"n": "08_interior_shop", "p": e["outside"], "yaw": float(e["yaw"]), "pitch": 2.0})
		shots.append({"n": "09_interior_inside", "p": e["inside"], "yaw": float(e["yaw"]), "pitch": 2.0})

	# aerial overview
	player.frozen = false
	player.set_state(Vector3(30, 52, -80), 145.0, -33.0)
	player.frozen = true
	await _wait(0.5)
	await _shot(dir, "10_aerial_city")

	player.frozen = false
	for s in shots:
		player.set_state(s["p"], s["yaw"], s["pitch"])
		await _wait(0.45)
		await _shot(dir, s["n"])

	# ---- AI ORDER E2E TEST: real LLM call -> worker builds -> screenshot ----
	var cmd_ui: CanvasLayer = null
	for c in main.get_children():
		if c is CanvasLayer and c.get_script() and c.get_script().resource_path == "res://scripts/command_ui.gd":
			cmd_ui = c
			break
	if cmd_ui:
		# site is 12m ahead of the player at spawn, facing +Z (yaw 180 => fwd = +Z)
		player.set_state(Vector3(7.5, 0.15, -30), 180.0, 4.0)
		cmd_ui._on_submit("build a cafeteria here")
		await _wait(5.0)
		await _shot(dir, "11_ai_order_received")
		# let the worker finish (build time 9s + margin)
		await _wait(12.0)
		await _shot(dir, "12_ai_order_built")
		var built := false
		for c in main.get_children():
			if c.get_script() and c.get_script().resource_path == "res://scripts/worker_agent.gd":
				built = true
		print("AI_ORDER_TEST worker_spawned=%s" % built)
	# --------------------------------------------------------------------------

	print("AUTOCAP_DONE " + dir)
	get_tree().quit()


func _wait(t: float):
	return get_tree().create_timer(t).timeout


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("AUTOCAP_SAVED " + ProjectSettings.globalize_path(path))
