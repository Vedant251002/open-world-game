extends Node
class_name SiteFxShot
## Captures a building going up (outline, scaffold, flag, dust, material pile,
## the finished celebration) or, with --evening, the dusk ambience.
## Driven by `-- --sitefx [--evening] --shotdir=/abs/dir`.

var world: VoxelWorld
var player: Player
var crew: Crew
var dispatch: Dispatcher
var clock: GameClock
var town: Town
var sky: SkyEnv
var village: Village

var out_dir := "/tmp/sitefx"
var _t := 0.0
var _armed := false
var _phase := 0
var _mira: Worker
var _site := Vector3.ZERO
var _patch: VoxelPatch = null
var _hold := 0
var _eve := false
var _busy := false


func begin() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			out_dir = a.substr(10)
	_eve = "--evening" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	crew.get_worker("mira").role = crew.roles.get_role("builder")
	for mat: String in Resources.SOURCE:
		town.stock[mat] = 9000
	dispatch.llm.offline = true
	player.set_input_enabled(false)
	set_process(true)


func _look(from: Vector3, at: Vector3) -> void:
	var d := at - from
	player.teleport(from, atan2(-d.x, -d.z))
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _snap(shot_name: String, settle: int = 6) -> void:
	_busy = true
	for i in settle:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, shot_name])
	print("[sitefx] %s fps=%d" % [shot_name, Engine.get_frames_per_second()])
	_busy = false


func _process(delta: float) -> void:
	_t += delta
	if _busy:
		return
	if not _armed:
		if world.busy() and _t < 20.0:
			return
		_armed = true
		sky.hour = 20.8 if _eve else 11.0
		clock.hour = sky.hour
		clock.speed = 1.0 if _eve else 25.0
		_mira = crew.get_worker("mira")
		if not _eve:
			dispatch.take_plan_for_test(_mira, "build a small house near the well",
				[{"do": "build", "brief": "a small house near the well"}])
		return
	if _eve:
		_evening()
		return
	if _hold > 0:
		_hold -= 1
		return
	var c := _mira.job_construction
	if _phase == 0 and _mira.state == Worker.State.WALKING and _mira.job_patch != null \
			and _mira.body.has_meta("carried_kind") and str(_mira.body.get_meta("carried_kind")) != "":
		_phase = 10
		var m := _mira.global_position
		var fwd := Vector3(sin(_mira.rotation.y), 0.0, cos(_mira.rotation.y))
		_look(m + fwd * 2.6 + Vector3(0.8, 1.2, 0), m + Vector3(0, 0.9, 0))
		await _snap("00_carry", 1)
		if "--carryonly" in OS.get_cmdline_user_args():
			get_tree().quit()
		return
	if _phase == 10:
		_phase = 0
	if c != null:
		_patch = c.patch
		var fc := c.patch.footprint.get_center()
		_site = Vector3(fc.x * 0.25, world.ground_m(fc.x * 0.25, fc.y * 0.25), fc.y * 0.25)
		var p := c.progress()
		if c.fx != null and _phase == 0:
			_phase = 1
			_hold = 30
			_look(_site + Vector3(9.0, 4.0, 13.0), _site + Vector3(0, 1.0, 0))
			_snap("01_outline")
		elif p > 0.4 and _phase == 1:
			_phase = 2
			_look(_site + Vector3(9.0, 5.0, 13.0), _site + Vector3(0, 2.0, 0))
			_snap("02_mid")
		elif p > 0.5 and _phase == 2:
			_phase = 3
			_look(_site + Vector3(45.0, 12.0, 75.0), _site + Vector3(0, 4.0, 0))
			_snap("03_far_flag")
		elif p > 0.93 and _phase == 3:
			_phase = 4
			clock.speed = 1.0
	elif _phase == 4:
		_phase = 5
		_hold = 3
		_look(_site + Vector3(9.0, 6.0, 15.0), _site + Vector3(0, 4.0, 0))
	elif _phase == 5:
		_phase = 6
		_snap("04_done")
	elif _phase == 6:
		get_tree().quit()


func _grass_spot() -> Vector3:
	var c := village.well_pos
	for r in range(44, 100, 4):
		for k in 16:
			var a := float(k) / 16.0 * TAU
			var x := c.x + cos(a) * r
			var z := c.z + sin(a) * r
			var vx := floori(x / 0.25)
			var vz := floori(z / 0.25)
			var h := world.height_at(vx, vz)
			if h >= 0 and world.get_voxel(Vector3i(vx, h, vz)) == VoxelTypes.GRASS:
				return Vector3(x, float(h + 1) * 0.25, z)
	return c


func _evening() -> void:
	if _phase == 0:
		_phase = 1
		var g := _grass_spot()
		var out := (g - village.well_pos).normalized()
		_look(g + Vector3(0, 1.7, 0), g + out * 9.0 + Vector3(0, 1.0, 0))
		_hold = 420
		return
	if _hold > 0:
		_hold -= 1
		return
	if _phase == 1:
		_phase = 2
		_snap("05_fireflies")
	elif _phase == 2:
		get_tree().quit()
