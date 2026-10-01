extends Node
## Pictures for review: a fire with the bucket line and the crisis banner, the
## aftermath banner, a hunger banner, and the village in winter and in autumn.
## Run (software renderer, slow):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     -- --realmtest=crisisshot --nosave --noquick --shotdir=/abs/dir

var world: VoxelWorld
var clock: GameClock
var realm: Realm
var player: Player
var crew: Crew
var town: Town
var farm: Farm
var hud: Node
var sky: Node

var _t := 0.0
var _started := false
var _dir := "/tmp/crisisshot"


func begin() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			_dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(_dir)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t < 7.0 or _started:
		return
	_started = true
	_run()


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, name])
	print("[crisisshot] %s %dx%d" % [name, img.get_width(), img.get_height()])


func _set_hour(h: float) -> void:
	clock.hour = h
	if sky != null:
		sky.hour = h


## Stands the player `back` metres from a point, looking at it.
func _look_at(target: Vector3, back: float, height: float, from_deg: float) -> void:
	var a := deg_to_rad(from_deg)
	var at := target + Vector3(sin(a), 0.0, cos(a)) * back
	at.y = world.ground_m(at.x, at.z) + 0.1
	var d := target - at
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(height - 1.7, Vector2(d.x, d.z).length())
	player.teleport(at, yaw, pitch)


func _run() -> void:
	var cr: Node = realm.system("Crisis")
	var wx: Node = realm.system("Weather")
	var se: Node = realm.system("Seasons")
	var w: Worker = crew.workers[0]
	_set_hour(18.7)
	var rec := realm.building("bakery")
	if rec.is_empty():
		rec = town.buildings[0]
	var name := str(rec["archetype"]).replace("_", " ")
	var door := realm.door_of(rec)
	var patch: VoxelPatch = rec["patch"]
	var centre := Vector3((patch.footprint.position.x + patch.footprint.size.x * 0.5) * 0.25, 0.0,
		(patch.footprint.position.y + patch.footprint.size.y * 0.5) * 0.25)
	centre.y = world.ground_m(centre.x, centre.z) + 3.0

	var fd := door - centre
	var front_deg := rad_to_deg(atan2(fd.x, fd.z))

	# ---- the alarm: flames, smoke, the banner, nobody fighting it yet
	wx.force("clear")
	wx.ignite(rec, "a stray spark")
	clock.advance(1.0)
	cr.scan()
	_look_at(centre, 17.0, 5.0, front_deg)
	await _secs(4.0)
	await _shot("fire_banner")

	# ---- the bucket line
	realm.handle(w, "everyone to the %s with buckets" % name)
	var i := 0
	for hand: Worker in crew.workers:
		var extra: Dictionary = hand.job_errand.get("extra", {})
		if int(extra.get("fire_id", -1)) >= 0:
			var ang := float(i) * 0.9
			hand.global_position = door + Vector3(cos(ang) * 3.0, 0.2, sin(ang) * 3.0)
			i += 1
	cr.scan()
	_look_at(centre, 14.0, 4.0, front_deg)
	await _secs(3.5)
	await _shot("fire_bucket_line")

	# ---- it is out: the aftermath
	var hours := 0
	while not wx.fires().is_empty() and hours < 20:
		clock.advance(1.0)
		hours += 1
		for f: Dictionary in wx.fires():
			if wx.fighters_of(f).is_empty():
				realm.handle(w, "everyone to the %s with buckets" % str(f["rec"]["archetype"]).replace("_", " "))
	cr.scan()
	await _secs(1.0)
	await _shot("fire_aftermath")

	# ---- hunger
	clock.day = maxi(clock.day, 8)
	cr.trigger("famine")
	await _secs(1.0)
	await _shot("famine_banner")
	town.coins = 5000
	realm.handle(w, "buy 200 food")
	cr.scan()

	# ---- winter and autumn
	var wp := realm.village.well_pos
	var wday := 1
	for d in range(1, 49):
		if str(wx.season_of(d)) == "winter" and int(wx.day_of_season(d)) == 6:
			wday = d
	clock.day = wday
	se.on_day(wday)
	wx.force("snow")
	wx.on_hour(clock.hour, clock.day)
	_set_hour(11.5)
	_look_at(wp, 22.0, 7.0, 20.0)
	await _secs(4.0)
	await _shot("winter")

	var aday := 1
	for d2 in range(1, 49):
		if str(wx.season_of(d2)) == "autumn" and int(wx.day_of_season(d2)) == 9:
			aday = d2
	clock.day = aday
	se.on_day(aday)
	wx.force("clear")
	_set_hour(16.5)
	_look_at(wp, 22.0, 7.0, 20.0)
	await _secs(4.0)
	await _shot("autumn")
	get_tree().quit()
