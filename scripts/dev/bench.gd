extends Node
class_name Bench
## Frame timing, in two phases that measure different things.
##
##   still     — camera parked, world fully streamed. The steady-state cost of
##               drawing the town, which is what the player sees most of the time.
##   streaming — walking a long line so columns load and unload continuously.
##               The worst case, and the one that decides whether the world can
##               be endless without hitching.
##
## Vsync is turned off here: with it on, a 17 ms frame and a 32 ms frame both
## report as the same number and the measurement says nothing.

var player: Player
var world: VoxelWorld
var sky: SkyEnv
var streamer: ChunkStreamer

var _phase := 0
var _warmup := 120
var _samples: Array[float] = []
var _centre := Vector3.ZERO
var _t := 0.0

const FRAMES := 420


func start(at: Vector3) -> void:
	_centre = at
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	set_process(true)


func _process(delta: float) -> void:
	if world != null and world.busy():
		return
	if _warmup > 0:
		_warmup -= 1
		if _warmup == 0 and streamer != null:
			streamer.stat_worst_frame_ms = 0.0
			streamer.stat_worst_collect_ms = 0.0
			streamer.stat_worst_ring_ms = 0.0
			streamer.stat_worst_evict_ms = 0.0
			world.stat_worst_frame_ms = 0.0
		world.stat_worst_dispatch_ms = 0.0
		world.stat_worst_upload_ms = 0.0
		return

	_t += delta
	match _phase:
		0:
			# Parked at the well, looking across the plaza.
			var pos := _centre + Vector3(0, 0, 16.0)
			pos.y = world.ground_m(pos.x, pos.z) + 0.2
			player.teleport(pos, 0.0)
			sky.hour = 11.0
		1:
			# A long straight walk, at a running pace, into unexplored ground.
			var p := _centre + Vector3(_t * 6.0, 0.0, 0.0)
			p.y = world.ground_m(p.x, p.z) + 1.7
			player.teleport(p, PI * 0.5)

	_samples.append(delta)
	if _samples.size() < FRAMES:
		return
	_report(["still", "streaming"][_phase])
	_samples.clear()
	if streamer != null:
		streamer.stat_worst_frame_ms = 0.0
		streamer.stat_worst_collect_ms = 0.0
		streamer.stat_worst_ring_ms = 0.0
		streamer.stat_worst_evict_ms = 0.0
		world.stat_worst_frame_ms = 0.0
		world.stat_worst_dispatch_ms = 0.0
		world.stat_worst_upload_ms = 0.0
	_phase += 1
	_warmup = 60
	_t = 0.0
	if _phase > 1:
		get_tree().quit()


func _report(label: String) -> void:
	var s := _samples.duplicate()
	s.sort()
	var median: float = s[s.size() / 2]
	var p95: float = s[int(s.size() * 0.95)]
	var worst: float = s[s.size() - 1]
	var extra := "   draws %d  cpu %.1f ms  gpu %.1f ms  max_fps %d  vsync %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Engine.max_fps, DisplayServer.window_get_vsync_mode()]
	if streamer != null:
		extra += "   " + streamer.status_text()
	if world != null:
		extra += "  rescues %d" % world.stat_rescues
	# A median and a p95 that agree to two decimals are not a workload, they are
	# a frame cap — usually the machine throttling to 30 fps on battery. Say so,
	# because otherwise the next person reads it as a performance regression.
	var capped := absf(median - p95) < 0.0002
	if capped:
		extra += "   [CAPPED — external frame limiter, timings meaningless]"
	print("[bench] %-10s median %5.2f ms (%3.0f fps)   p95 %5.2f ms (%3.0f fps)   worst %5.2f ms%s" % [
		label, median * 1000.0, 1.0 / median, p95 * 1000.0, 1.0 / p95,
		worst * 1000.0, extra])
