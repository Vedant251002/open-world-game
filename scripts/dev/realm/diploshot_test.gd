extends Node
## Pictures of the Diplomacy screen, the map's neighbours and the village-code
## screen.  xvfb-run -a godot --path . --rendering-driver opengl3 -- --realmtest=diploshot --diploshotdir=/abs/dir

var world: VoxelWorld
var crew: Crew
var clock: GameClock
var town: Town
var village: Village
var realm: Realm
var player: Player
var map: MapScreen
var hud: Hud

var dir := "/tmp/diploshot"


func begin() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--diploshotdir="):
			dir = a.substr(15)
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[diploshot] %s %dx%d" % [name, img.get_width(), img.get_height()])


func _run() -> void:
	await get_tree().create_timer(6.0, true).timeout
	var main: Node = get_parent()
	var nb: Node = realm.system("Neighbours")
	var ts: Array = nb.list()
	ts[0]["disposition"] = 0.35
	ts[0]["treaty"] = "trade"
	ts[1]["disposition"] = -0.7
	ts[1]["treaty"] = "war"
	ts[2]["disposition"] = 0.05
	ts[2]["treaty"] = "none"
	if ts.size() > 3:
		ts[3]["disposition"] = 0.75
		ts[3]["treaty"] = "alliance"
	var screen: DiplomacyScreen = main.diplomacy_screen
	player.teleport(village.well_pos + Vector3(3.0, 1.5, 11.0), 0.15, -0.09)
	clock.hour = 10.0
	screen.open_screen()
	await _frames(4)
	screen._say("Good morning. We would like to open the roads and trade with you.")
	screen._say("Would you stand with us as allies?")
	screen._say("What do you want from us?")
	await _frames(8)
	await _shot("diplomacy_screen")
	screen._select(str(ts[1]["name"]))
	screen._say("I ask for peace. The quarrel has cost us both.")
	await _frames(6)
	await _shot("diplomacy_war")
	screen.close_screen()
	await _frames(3)

	map.set_open(true)
	await _frames(40)
	await _shot("map_neighbours")
	map.set_open(false)

	var vs: VisitScreen = main.visit_screen
	vs.owner_name = "Mara"
	vs.open_screen()
	await _frames(4)
	vs._make_code()
	vs._paste_box.text = vs._code_box.text
	vs._on_paste_changed()
	await _frames(6)
	await _shot("village_codes")
	vs.close_screen()
	get_tree().quit(0)
