extends Node
class_name LLM
## One API call per instruction, per game-design-doc.md §5.2.
##
## Not per tick, not per worker per frame. Roughly 1500 tokens in and 500 out,
## a handful of calls a session. Latency is hidden behind in-game time: the
## worker is already walking to the plot while the call is in flight.
##
## Every request and response is written to disk. That log is the prompt-tuning
## dataset and the only real QA instrument against a non-deterministic
## component, which is why slice 4 onward is emphatic about keeping it.

signal plan_ready(worker_id: String, plan: Dictionary)
signal question_ready(worker_id: String, question: String, line: String)
signal failed(worker_id: String, reason: String)
signal status(text: String)

const MODEL := "claude-haiku-4-5"
const ENDPOINT := "https://api.anthropic.com/v1/messages"
const MAX_TOKENS := 1600
const TIMEOUT := 30.0
const LOG_DIR := "user://ai_log"

var api_key := ""
var workspace := ""
var offline := false          ## forced by --offline, or by having no key

var calls_made := 0
var cache_hits := 0
var retries := 0
var fallbacks := 0

var _busy := {}               ## worker_id -> true
var _log_index := 0


func _ready() -> void:
	api_key = OS.get_environment("ANTHROPIC_API_KEY")
	if api_key == "":
		api_key = _read_env("res://.env", "ANTHROPIC_API_KEY")
	workspace = OS.get_environment("ANTHROPIC_WORKSPACE_ID")
	if workspace == "":
		workspace = _read_env("res://.env", "ANTHROPIC_WORKSPACE_ID")
	if "--offline" in OS.get_cmdline_user_args():
		offline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))


func available() -> bool:
	return api_key != "" and not offline


func _read_env(path: String, key_name: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var val := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with(key_name + "="):
			val = line.substr(key_name.length() + 1).strip_edges() \
				.trim_prefix("\"").trim_suffix("\"")
			break
	f.close()
	return val


func busy_for(worker_id: String) -> bool:
	return _busy.get(worker_id, false)


# ---------------------------------------------------------------- submission

func submit(instruction: String, mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town) -> void:
	if busy_for(mem.worker_id):
		status.emit("%s is still thinking." % mem.display_name)
		return

	# Cache before anything else. A popular building on a familiar plot for a
	# worker whose preferences have not changed is the same plan every time.
	var arch := ArchetypeLibrary.guess_archetype(instruction)
	var key := ArchetypeLibrary.cache_key(arch, int(ctx.get("tier", 1)), plot, mem)
	var hit := ArchetypeLibrary.cached(key)
	if not hit.is_empty() and _instruction_is_plain(instruction):
		cache_hits += 1
		_log("cache", mem.worker_id, instruction, JSON.stringify(hit))
		plan_ready.emit(mem.worker_id, hit)
		return

	if not available():
		_offline_answer(instruction, mem, plot, ctx)
		return

	_busy[mem.worker_id] = true
	status.emit("%s is working it out..." % mem.display_name)
	_request(instruction, mem, plot, ctx, clock, town, key, 0, "")


## Only cache-serve an instruction that is a plain request for a building type.
## Anything with extra clauses in it deserves a real call, because the clauses
## are where the misinterpretation lives.
func _instruction_is_plain(instruction: String) -> bool:
	var w := instruction.strip_edges().split(" ", false)
	return w.size() <= 5


func _request(instruction: String, mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town, key: String, attempt: int, repair: String) -> void:
	var sys := Prompt.system(mem, ctx)
	var usr := Prompt.user(instruction, mem, plot, ctx, clock, town)
	if repair != "":
		usr += "\n\nYour previous reply could not be used: %s\nReturn corrected JSON only." % repair

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_on_reply(result, code, body, instruction, mem, plot, ctx, clock, town,
				key, attempt),
		CONNECT_ONE_SHOT)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: 2023-06-01",
	])
	if workspace != "":
		headers.append("anthropic-workspace-id: " + workspace)

	var payload := JSON.stringify({
		"model": MODEL,
		"max_tokens": MAX_TOKENS,
		"system": sys,
		"messages": [{"role": "user", "content": usr}],
	})
	_log("request", mem.worker_id, instruction, sys + "\n\n---\n\n" + usr)
	calls_made += 1

	if http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, payload) != OK:
		http.queue_free()
		_busy.erase(mem.worker_id)
		_offline_answer(instruction, mem, plot, ctx)


func _on_reply(result: int, code: int, body: PackedByteArray, instruction: String,
		mem: WorkerMemory, plot: Plot, ctx: Dictionary, clock: GameClock, town: Town,
		key: String, attempt: int) -> void:
	var raw := body.get_string_from_utf8()
	_log("response", mem.worker_id, instruction, "http=%d result=%d\n%s" % [code, result, raw])

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_busy.erase(mem.worker_id)
		push_warning("[llm] call failed http=%d result=%d" % [code, result])
		status.emit("No reply. %s is using a standard plan." % mem.display_name)
		_offline_answer(instruction, mem, plot, ctx)
		return

	var parsed := _extract(raw)
	var problem := _schema_problem(parsed, ctx)
	if problem != "":
		# One retry with the error appended, then the cached archetype. This is
		# the recovery ladder from §5.4; the run never breaks on bad output.
		if attempt == 0:
			retries += 1
			_request(instruction, mem, plot, ctx, clock, town, key, 1, problem)
			return
		_busy.erase(mem.worker_id)
		push_warning("[llm] rejected twice: %s" % problem)
		_log("rejected", mem.worker_id, instruction, problem)
		_offline_answer(instruction, mem, plot, ctx)
		return

	_busy.erase(mem.worker_id)

	if str(parsed.get("kind", "")) == "question":
		question_ready.emit(mem.worker_id, str(parsed.get("question", "")),
			str(parsed.get("worker_line", parsed.get("question", ""))))
		return

	parsed["source"] = "model"
	ArchetypeLibrary.store(key, parsed)
	plan_ready.emit(mem.worker_id, parsed)


func _offline_answer(instruction: String, mem: WorkerMemory, plot: Plot,
		ctx: Dictionary) -> void:
	fallbacks += 1
	_busy.erase(mem.worker_id)
	var plan := ArchetypeLibrary.fallback(instruction, mem, plot, int(ctx.get("tier", 1)))
	plan_ready.emit(mem.worker_id, plan)


# -------------------------------------------------------------------- parsing

func _extract(raw: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return {}
	var payload: Dictionary = json.data
	var content: Variant = payload.get("content", [])
	if not (content is Array) or (content as Array).is_empty():
		return {}
	var text := str((content as Array)[0].get("text", ""))
	text = text.strip_edges()
	# Models sometimes fence JSON despite being told not to.
	if text.begins_with("```"):
		var nl := text.find("\n")
		text = text.substr(nl + 1) if nl >= 0 else text
		text = text.trim_suffix("```").strip_edges()
	# Or wrap it in a sentence.
	var first := text.find("{")
	var last := text.rfind("}")
	if first >= 0 and last > first:
		text = text.substr(first, last - first + 1)

	var j2 := JSON.new()
	if j2.parse(text) != OK or not (j2.data is Dictionary):
		return {}
	return j2.data


## Shape check only. The real vocabulary check is the validator, which runs on
## the spec proper and produces a question the worker can say out loud.
func _schema_problem(d: Dictionary, _ctx: Dictionary) -> String:
	if d.is_empty():
		return "the reply was not JSON"
	var kind := str(d.get("kind", ""))
	if kind == "question":
		if str(d.get("question", "")).strip_edges() == "":
			return "kind was question but no question was given"
		return ""
	if kind != "plan":
		return "kind must be exactly \"plan\" or \"question\""
	if not (d.get("spec", null) is Dictionary):
		return "spec is missing or is not an object"
	var spec: Dictionary = d["spec"]
	if not (spec.get("footprint", null) is Array):
		return "spec.footprint must be an array of two numbers"
	if not (spec.get("modules", null) is Array):
		return "spec.modules must be an array"
	if not (d.get("assumptions", null) is Array):
		return "assumptions must be an array of plain sentences"
	if (d["assumptions"] as Array).is_empty():
		return "assumptions must not be empty — state what you filled in and why"
	return ""


# -------------------------------------------------------------------- logging

func _log(kind: String, worker_id: String, instruction: String, payload: String) -> void:
	_log_index += 1
	var path := "%s/%04d_%s_%s.txt" % [LOG_DIR, _log_index, worker_id, kind]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# %s\n# worker: %s\n# instruction: %s\n\n%s\n" % [
		Time.get_datetime_string_from_system(), worker_id, instruction, payload])
	f.close()


func stats_text() -> String:
	return "calls %d  cache %d  retry %d  fallback %d  specs %d" % [
		calls_made, cache_hits, retries, fallbacks, ArchetypeLibrary.cache_size()]
