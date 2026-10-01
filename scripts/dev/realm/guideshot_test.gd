extends Node
## Screenshots of the first-day card, the milestone banner and the milestones
## panel, over the live village.
## Run with:
##   godot --path . --rendering-driver opengl3 -- --realmtest=guideshot --nosave --shotdir=/abs/dir

var world: VoxelWorld
var village: Village
var town: Town
var clock: GameClock
var player: Player
var crew: Crew
var hud: Hud
var dispatch: Dispatcher
var map: MapScreen
var inventory: InventoryScreen

var _dir := "user://guideshots"


func begin() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			_dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	await _frames(40)
	var main := get_parent()
	var prog: Progression = main.get("progression")
	var ui: MilestonesUi = main.get("milestones_ui")
	player.teleport(village.well_pos + Vector3(3.0, 1.5, 11.0), 0.15, -0.09)
	clock.hour = 10.0
	var mira := crew.get_worker("mira")
	var tobias := crew.get_worker("tobias")

	var tut := Tutorial.new()
	add_child(tut)
	tut.setup(hud, crew, dispatch, town, map, player, clock, ui)
	tut.village_name = str(main.get("identity").village_name)
	tut.start()
	await _frames(30)
	await _save("10_tutorial_talk")

	hud.talk_opened.emit(mira)
	await _frames(20)
	await _save("11_tutorial_order")

	dispatch.plan_accepted.emit(tobias, ["a small hut, three metres by four",
		"timber walls, thatch roof", "on the nearest free plot"])
	hud.show_assumptions(tobias, ["a small hut, three metres by four",
		"timber walls, thatch roof", "on the nearest free plot"])
	await _frames(20)
	await _save("12_tutorial_assumptions")

	tut.notify("gotit")
	await _frames(20)
	await _save("13_tutorial_build")

	crew.job_done.emit(tobias, VoxelPatch.new(Vector3i.ZERO, Vector3i.ONE))
	await _frames(40)
	await _save("14_milestone_banner")

	prog.grant("build_5")
	tut.skip()

	ui.set_open(true)
	await _frames(20)
	await _save("16_milestones_panel")
	ui.set_open(false)
	print("[guideshot] done -> %s" % ProjectSettings.globalize_path(_dir))
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("%s/%s.png" % [_dir, name]))
	print("[guideshot] %s" % name)
