extends Node
class_name ChatProbe
## One live question to the model, to see what a worker says when the town's
## records cannot answer for them.
##
## The deterministic layer is tested by AskTest with no network at all. This is
## the other half: a question with no pattern — an opinion, a why — goes to the
## model with the same facts the records hold, and this prints what comes back.
## It costs one call. Run with:  godot --path . -- --chatprobe --say="..."

var dispatch: Dispatcher
var crew: Crew
var world: VoxelWorld

var _question := "what do you make of this town so far?"
var _t := 0.0
var _wait := 0.0
var _armed := false
var _heard: Array[String] = []


func begin(say: String) -> void:
	if say != "":
		_question = say
	crew.worker_spoke.connect(func(w: Worker, line: String, kind: String) -> void:
		print("[chat]   %s (%s): %s" % [w.display_name(), kind, line])
		_heard.append(line))
	set_process(true)


func _process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if world.busy() and _wait < 15.0:
			return
		_armed = true
		print("[chat] provider: %s" % dispatch.describe_ai())
		if not dispatch.ai_online():
			print("[chat] === SKIP (no model configured) ===")
			get_tree().quit(0)
			return
		print("[chat] Mira <- \"%s\"" % _question)
		dispatch.instruct(crew.get_worker("mira"), _question)
		return
	_t += delta
	# "Let me think." is the acknowledgement; the answer is whatever follows.
	if _heard.size() >= 2:
		print("[chat] === PASS ===")
		get_tree().quit(0)
	elif _t > 60.0:
		print("[chat] === FAIL: no reply in 60 s ===")
		get_tree().quit(1)
