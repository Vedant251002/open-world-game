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
## A plain-language reply to a question, as opposed to a plan.
signal answered(worker_id: String, text: String)
## A role composed from a name and a description. `role` is the raw dictionary
## the composer produced, validated for shape only; the dispatcher runs it
## through Validator.check_role and either keeps it or says why not. `source`
## is "model" or "fallback", so the roster can say which it got.
signal role_ready(key: String, role: Dictionary, source: String)
## A morning's round toward a goal: {"done", "orders": [{who, order}], "note"}.
signal round_ready(worker_id: String, round: Dictionary, source: String)
## Something a person said in their own words: a reply in a conversation, or
## what they came out with when something happened to them. `tag` is the
## caller's, handed back so it knows which moment this was for.
signal line_ready(worker_id: String, text: String, tag: String)

## OpenCode Zen, which speaks the OpenAI chat-completions shape.
##
## The model is not a constant: it is read from .env at boot so it can be
## changed without a rebuild. That matters here more than usual, because the
## gateway carries seventy models, most of them billed, and which of the free
## ones is answering today is an operational question rather than a design one.
##
## The account has no credits, so the model has to be one of the free ids.
## Measured on the same workshop prompt:
##
##   nemotron-3-ultra-free        44 s, complete JSON, every attempt
##   ling-3.0-flash-fin-free     2.7 s, but capped near 250 output tokens on the
##                               free tier, so a full spec is always truncated
##   nemotron-3.5-lightning-free  59 s, spends its whole budget reasoning
##   mimo-v2.5-free               a daily quota, then 429 for the rest of the day
##   muse-spark-*-contributor-free, deepseek-v4-flash-free   down upstream
##
## So the choice is the slow one that finishes its sentences. Forty seconds
## would be intolerable if the player watched it — which is why the worker now
## sets off for the plot the moment the order is given, and the call lands while
## they are walking. That was always the design (§5.2); it just was not built.
const ENDPOINT := "https://opencode.ai/zen/v1/chat/completions"

## The browser build cannot call ENDPOINT. OpenCode Zen sends no CORS headers,
## so the request is refused before it leaves the page — that is a rule of the
## browser, not a missing setting, and no key in the build would change it.
##
## So a browser build goes through proxy/worker.js instead, which holds the key
## on Cloudflare and adds the headers a browser insists on. This URL is not a
## secret: it is useless without the key, and the Worker only answers the
## game's own origin.
##
## Deployed from proxy/, and committed here on purpose. Native builds do not
## need it — they can call the API directly with a key from the environment —
## but the browser build has no other way to reach a model at all.
const PROXY_URL := "https://delegate-ai.delegate-ai-proxy.workers.dev"
const DEFAULT_MODEL := "nemotron-3-ultra-free"
## Which gateway is answering. Chosen at boot by which key is present, Groq
## first — see AIProvider.PREFERENCE and _pick_provider.
var provider := "opencode"
## Generous. A full spec with five modules and three assumptions runs past
## sixteen hundred tokens, and a truncated reply is not a poor plan, it is no
## plan at all: the JSON never closes, so nothing can parse it.
const MAX_TOKENS := 3200
## Long, because the free models on the gateway are slow: thirty seconds was
## timing out on a reply that was on its way. The wait is not free — the
## worker stands there saying they are thinking about it — but a timeout
## costs the same wait and then throws the answer away.
const TIMEOUT := 90.0
## How long to wait before retrying a rate limit. Long enough for a per-minute
## token bucket to have refilled a little, short enough that it is over before
## the worker has reached the plot.
const RATE_LIMIT_WAIT := 6.0
## Ceiling on a gateway-supplied retry hint. A body saying "try again in
## 86400s" must not leave a worker thinking for a day, and a player who is
## already waiting 90s for a reply is not going to be saved by 120s.
const MAX_RATE_LIMIT_WAIT := 45.0
const LOG_DIR := "user://ai_log"

var api_key := ""
var proxy_url := ""
var model := DEFAULT_MODEL
var last_error := ""
var offline := false          ## forced by --offline, or by having no key

var calls_made := 0
var cache_hits := 0
var retries := 0

## How long an order actually takes, measured.
##
## The game used to log the request and the response and never the gap between
## them, which is why two separate bugs could take the whole AI feature
## offline and nothing in the project could see it: there was no number. It
## also meant the rate-limit wait was a guess (a flat RATE_LIMIT_WAIT) when the
## gateway was stating the exact retry time in the body of the 429.
##
## These are wall-clock milliseconds for the HTTP round trip only, not the
## walk to the plot or the build — those are the player's, and they are
## reported separately by the dispatcher. Percentiles rather than an average,
## because a tail is what a player actually feels: a median of 2 s with a 90th
## percentile of 70 s is a different product from a median of 20 s, and an
## average of 9 s describes neither.
var _latencies_ms: Array[float] = []
var _inflight_at := 0
## Which kind of call is in flight, so the latency can be attributed.
var _inflight_kind := ""
## How many times a 429 sent us back to wait, and how long in total. A player
## who is rate-limited on every order is the loudest possible signal that the
## token budget is the real constraint, and it was invisible before.
var rate_limit_waits := 0
var rate_limit_wait_total := 0.0
## Per-stage latency, so a slow order can be attributed rather than guessed at.
var _lat_by_kind: Dictionary = {}


## Starts timing one call. Cheap enough to call on every request.
func _begin_call(kind: String) -> void:
	_inflight_at = Time.get_ticks_msec()
	_inflight_kind = kind


## Ends timing and folds the result into the stats. `failed` is kept separate
## from the successes so a gateway that is refusing everything does not look
## like a gateway that is slow.
func _end_call(failed: bool) -> void:
	if _inflight_at == 0:
		return
	var ms := float(Time.get_ticks_msec() - _inflight_at)
	_inflight_at = 0
	if not failed:
		_latencies_ms.append(ms)
		var k := _inflight_kind
		if not _lat_by_kind.has(k):
			_lat_by_kind[k] = []
		(_lat_by_kind[k] as Array).append(ms)
	_inflight_kind = ""


static func _percentile(sorted_vals: Array[float], p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var i := int(round((sorted_vals.size() - 1) * clampf(p, 0.0, 1.0)))
	return sorted_vals[clampi(i, 0, sorted_vals.size() - 1)]


## Median / p90 / max, in seconds, over every call that succeeded.
func latency_report() -> Dictionary:
	if _latencies_ms.is_empty():
		return {"n": 0}
	var s := _latencies_ms.duplicate()
	s.sort()
	return {
		"n": s.size(),
		"median": _percentile(s, 0.5) / 1000.0,
		"p90": _percentile(s, 0.9) / 1000.0,
		"max": s[s.size() - 1] / 1000.0,
		"mean": (s.reduce(func(a, b): return a + b, 0.0) / s.size()) / 1000.0,
	}


## The same, per kind of call, so a slow planner is distinguishable from a slow
## chat reply. Kinds: plan, talk, role, round, answer.
func latency_by_kind() -> Dictionary:
	var out := {}
	for k: String in _lat_by_kind:
		var a: Array = _lat_by_kind[k]
		if a.is_empty():
			continue
		var s: Array[float] = []
		for v in a:
			s.append(v)
		s.sort()
		out[k] = {
			"n": s.size(),
			"median": _percentile(s, 0.5) / 1000.0,
			"p90": _percentile(s, 0.9) / 1000.0,
		}
	return out


## The wait the gateway asked for, in seconds, or 0 when it did not say.
##
## Groq's 429 body names the exact delay — "Please try again in 34.9275s" — and
## the game was ignoring it and waiting a flat RATE_LIMIT_WAIT instead. On a
## 35 s hint that is a guaranteed second failure, and on a 7 s hint it is four
## wasted seconds of the player's time. The number is already in the response;
## this is the only reason it is not used.
##
## Written to cope with the formats in the wild rather than one exact string:
##   "...try again in 34.9275s"
##   "retry after 12s"
##   {"retry_after": 12.5}
static func retry_hint_seconds(raw: String) -> float:
	# The structured form first, when the gateway offers it.
	var j := JSON.new()
	if j.parse(raw) == OK and j.data is Dictionary:
		var d: Dictionary = j.data
		var e: Variant = d.get("error", {})
		if e is Dictionary:
			var ed: Dictionary = e
			for key in ["retry_after", "retry_after_seconds", "retry_delay"]:
				if ed.has(key):
					var v := float(ed[key])
					if v > 0.0:
						return v
			# Some gateways put a nested object here.
			var meta: Variant = ed.get("metadata", {})
			if meta is Dictionary:
				for key in ["retry_after", "retry_after_seconds"]:
					var md: Dictionary = meta
					if md.has(key):
						var v2 := float(md[key])
						if v2 > 0.0:
							return v2
	# Then the prose form, which is what Groq actually sends.
	var re := RegEx.new()
	re.compile("try again in\\s*([0-9]+(?:\\.[0-9]+)?)\\s*s?i")
	var m := re.search(raw)
	if m != null:
		return maxf(0.0, float(m.get_string(1)))
	var re2 := RegEx.new()
	re2.compile("retry[- ]after\\s*([0-9]+(?:\\.[0-9]+)?)\\s*s?i")
	var m2 := re2.search(raw)
	if m2 != null:
		return maxf(0.0, float(m2.get_string(1)))
	return 0.0
var fallbacks := 0

var _busy := {}               ## worker_id -> true
var _composing := {}          ## role key -> true
var _log_index := 0


func _ready() -> void:
	_pick_provider()
	var key_env := str(AIProvider.of(provider)["key_env"])
	api_key = OS.get_environment(key_env)
	if api_key == "":
		api_key = _read_env("res://.env", key_env)

	# A local override beats the compiled-in one, so the Worker can be tested
	# against a dev deployment without editing and rebuilding the game.
	proxy_url = OS.get_environment("OPENCODE_PROXY_URL")
	if proxy_url == "":
		proxy_url = _read_env("res://.env", "OPENCODE_PROXY_URL")
	if proxy_url == "":
		proxy_url = PROXY_URL
	for arg2 in OS.get_cmdline_user_args():
		if arg2.begins_with("--proxy="):
			proxy_url = arg2.substr(8)

	var model_env := str(AIProvider.of(provider)["model_env"])
	model = OS.get_environment(model_env)
	if model == "":
		model = _read_env("res://.env", model_env)
	if model == "":
		model = str(AIProvider.of(provider)["default_model"])
	# A flag beats the file, so a single run can try another model without
	# anything being edited.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			model = arg.substr(8)
	if "--offline" in OS.get_cmdline_user_args():
		offline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))


## Which gateway to talk to.
##
## Named outright with --provider= or AI_PROVIDER, and otherwise decided by
## which key is actually present. The chat API wins when CHAT_API_KEY is set.
## A missing key falls through rather than going offline.
func _pick_provider() -> void:
	var named := OS.get_environment("AI_PROVIDER")
	if named == "":
		named = _read_env("res://.env", "AI_PROVIDER")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--provider="):
			named = arg.substr(11)
	if named != "" and AIProvider.known(named):
		provider = named
		return

	for name: String in AIProvider.PREFERENCE:
		var env_name := str(AIProvider.of(name)["key_env"])
		if OS.get_environment(env_name) != "" \
				or _read_env("res://.env", env_name) != "":
			provider = name
			return
	provider = "opencode"


func available() -> bool:
	return (api_key != "" or proxy_url != "") and not offline


## Token budget, and the reasoning flag only for gateways that understand it.
## A plain OpenAI-compatible server rejects a body that contains "reasoning".
func _finish_body(body: Dictionary, tokens: int) -> void:
	body[AIProvider.token_field(provider)] = tokens
	if AIProvider.wants_reasoning(provider):
		body["reasoning"] = {"exclude": true}


## Where a request goes, and with what on it.
##
## A key in hand wins, and the proxy is the fallback. This is the reverse of
## what it used to be, and the reason is that the proxy holds one key for one
## gateway: routing a Groq request through a Worker whose secret is an OpenCode
## key sends it to the wrong place with the wrong credentials. Trying the key
## you actually have is the only rule that stays true as gateways are added.
##
## The browser still has no key and still goes through the proxy, which is the
## case the proxy was built for.
func _route() -> Dictionary:
	if api_key != "":
		return {"url": AIProvider.endpoint(provider), "headers": PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + api_key])}
	return {"url": proxy_url, "headers": PackedStringArray([
		"Content-Type: application/json",
		# The Worker forces its own model, but it cannot guess which gateway a
		# build meant. Saying so costs nothing and is not a secret.
		"X-Provider: " + provider])}


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


## Workers with a question in flight. Separate from _busy, which is plans.
var _chatting: Dictionary = {}
## An answer is a sentence or two. Plans get thousands of tokens because a
## building has a lot of parts; a reply to "where is the store" does not.
const ANSWER_TOKENS := 220
## A role is a short list and a paragraph. Six hundred is generous.
const ROLE_TOKENS := 600
## A line of speech. Short on purpose: people in the street say a sentence or
## two, not a paragraph.
const TALK_TOKENS := 260
## Workers with a line in flight, and the newest thing waiting behind it.
var _talking: Dictionary = {}
var _talk_next: Dictionary = {}


# ---------------------------------------------------------------- submission

func submit(instruction: String, mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town) -> void:
	if busy_for(mem.worker_id):
		status.emit("%s is still thinking." % mem.display_name)
		return

	# Only a building they actually named can come out of the cache. The key is
	# the archetype, and an unnamed sentence used to hash to whatever hut was
	# last built on this plot.
	var arch := ArchetypeLibrary.named_archetype(instruction)
	var key := ""
	if arch != "" and _instruction_is_plain(instruction) \
			and ArchetypeLibrary.land_plan(instruction, int(ctx.get("tier", 1))).is_empty() \
			and ArchetypeLibrary.errand_plan(instruction).is_empty():
		key = ArchetypeLibrary.cache_key(arch, int(ctx.get("tier", 1)), plot, mem)
		var hit := ArchetypeLibrary.cached(key)
		if not hit.is_empty():
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


## A question rather than an order: no plot, no schema, a short prose reply.
##
## Separate from submit() because the two share almost nothing but the route.
## A plan is constrained to a JSON schema and retried until it parses; an
## answer is one or two sentences and either arrives or it does not. Keeping
## them apart also keeps them from blocking each other — a worker can be asked
## what they are doing while the model is still writing their plan.
func ask(question: String, mem: WorkerMemory, ctx: Dictionary, clock: GameClock,
		town: Town) -> void:
	if not available():
		answered.emit(mem.worker_id, "I could not tell you, sorry.")
		return
	if _chatting.get(mem.worker_id, false):
		return
	_chatting[mem.worker_id] = true

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_chatting.erase(mem.worker_id)
			var raw := body.get_string_from_utf8()
			_log("answer", mem.worker_id, question, "http=%d result=%d\n%s" % [code, result, raw])
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				answered.emit(mem.worker_id, "I could not tell you just now.")
				return
			var text := _plain_text(raw)
			if text == "":
				text = "I am not sure how to answer that."
			answered.emit(mem.worker_id, text),
		CONNECT_ONE_SHOT)

	var route := _route()
	var body := {
		"model": model,
		"temperature": 0.6,
		"messages": [
			{"role": "system", "content": Prompt.chat_system(mem, ctx)},
			{"role": "user", "content": Prompt.chat_user(question, mem, ctx, clock, town)},
		],
	}
	_finish_body(body, ANSWER_TOKENS)
	calls_made += 1
	_begin_call("answer")
	if http.request(str(route["url"]), route["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_chatting.erase(mem.worker_id)
		answered.emit(mem.worker_id, "I could not tell you just now.")


## Somebody speaking as themselves. The caller writes the whole conversation
## — who they are, what they know, what was said — and gets back one line.
##
## One in flight per person. Anything said while they are still answering is
## kept, newest only, and sent the moment the first reply lands, so a player
## who types three things quickly gets an answer to the last rather than
## three answers to stale ones. Offline, or on any failure, `fallback` is
## said instead, so nobody ever stands there mute.
func talk(worker_id: String, system: String, messages: Array, tag: String,
		fallback: String) -> void:
	if not available():
		line_ready.emit(worker_id, fallback, tag)
		return
	if _talking.get(worker_id, false):
		_talk_next[worker_id] = [system, messages, tag, fallback]
		return
	_talking[worker_id] = true

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_talking.erase(worker_id)
			var raw := body.get_string_from_utf8()
			_log("talk", worker_id, tag, "http=%d result=%d\n%s" % [code, result, raw])
			var text := ""
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				text = _plain_text(raw)
			else:
				last_error = _gateway_message(raw)
			line_ready.emit(worker_id, text if text != "" else fallback, tag)
			if _talk_next.has(worker_id):
				var n: Array = _talk_next[worker_id]
				_talk_next.erase(worker_id)
				talk(worker_id, n[0], n[1], n[2], n[3]),
		CONNECT_ONE_SHOT)

	var route := _route()
	var msgs: Array = [{"role": "system", "content": system}]
	msgs.append_array(messages)
	var body := {"model": model, "temperature": 0.9, "messages": msgs}
	_finish_body(body, TALK_TOKENS)
	calls_made += 1
	_begin_call("talk")
	if http.request(str(route["url"]), route["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_talking.erase(worker_id)
		line_ready.emit(worker_id, fallback, tag)


## Composing a role. One call, once per role name the town has never heard of;
## after that it is in the RoleBook and never asked for again.
##
## The offline composer answers when there is no gateway, and when the gateway
## fails, and it is a keyword matcher over the capability tags — cruder than
## a model, but "shepherd" still comes out as stock, enclose and collect, and
## that is what an exported build with no key has to be able to do.
func compose_role(key: String, name: String, description: String,
		ctx: Dictionary) -> void:
	if not available():
		role_ready.emit(key, ArchetypeLibrary.role_fallback(name, description), "fallback")
		return
	if _composing.get(key, false):
		return
	_composing[key] = true

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_composing.erase(key)
			var raw := body.get_string_from_utf8()
			_log("role", key, name + " — " + description, "http=%d result=%d
%s" % [code, result, raw])
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				last_error = _gateway_message(raw)
				status.emit("%s: %s — writing the job up myself." % [model, last_error])
				role_ready.emit(key, ArchetypeLibrary.role_fallback(name, description), "fallback")
				return
			var parsed := _extract(raw)
			if str(parsed.get("kind", "")) != "role" 					or not (parsed.get("capabilities", null) is Array):
				_log("role_rejected", key, name, "not a role object")
				role_ready.emit(key, ArchetypeLibrary.role_fallback(name, description), "fallback")
				return
			role_ready.emit(key, parsed, "model"),
		CONNECT_ONE_SHOT)

	var route := _route()
	var body := {
		"model": model,
		"temperature": 0.5,
		"messages": [
			{"role": "system", "content": Prompt.role_system()},
			{"role": "user", "content": Prompt.role_user(name, description, ctx)},
		],
	}
	_finish_body(body, ROLE_TOKENS)
	if AIProvider.schema_mode(provider) != "none":
		body["response_format"] = {
			"type": "json_schema", "json_schema": PlanSchema.role_schema(),
		}
	_log("role_request", key, name, Prompt.role_system() + "\n\n---\n\n"
		+ Prompt.role_user(name, description, ctx))
	calls_made += 1
	_begin_call("role")
	if http.request(str(route["url"]), route["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_composing.erase(key)
		role_ready.emit(key, ArchetypeLibrary.role_fallback(name, description), "fallback")


## A round of a goal. One call a morning per foreman; offline, the campaign
## library answers, which is what a keyless build has to do.
func plan_round(worker: Worker, goal: Goal, crew: Crew, town: Town,
		clock: GameClock, farm: Farm, livestock: Livestock) -> void:
	var wid := worker.memory.worker_id
	if not available():
		round_ready.emit(wid, ArchetypeLibrary.goal_round(goal.text, goal.rounds), "fallback")
		return
	if _composing.get("round:" + wid, false):
		return
	_composing["round:" + wid] = true

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_composing.erase("round:" + wid)
			var raw := body.get_string_from_utf8()
			_log("round", wid, goal.text, "http=%d result=%d\n%s" % [code, result, raw])
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				last_error = _gateway_message(raw)
				status.emit("%s: %s — planning the day myself." % [model, last_error])
				round_ready.emit(wid, ArchetypeLibrary.goal_round(goal.text, goal.rounds), "fallback")
				return
			var parsed := _extract(raw)
			if str(parsed.get("kind", "")) != "round" or not (parsed.get("orders", null) is Array):
				_log("round_rejected", wid, goal.text, "not a round object")
				round_ready.emit(wid, ArchetypeLibrary.goal_round(goal.text, goal.rounds), "fallback")
				return
			round_ready.emit(wid, parsed, "model"),
		CONNECT_ONE_SHOT)

	var route := _route()
	var body := {
		"model": model,
		"temperature": 0.6,
		"messages": [
			{"role": "system", "content": Prompt.round_system(worker.memory, worker.role)},
			{"role": "user", "content": Prompt.round_user(goal, crew, town, clock, farm, livestock)},
		],
	}
	_finish_body(body, ROLE_TOKENS)
	if AIProvider.schema_mode(provider) != "none":
		body["response_format"] = {"type": "json_schema", "json_schema": PlanSchema.round_schema()}
	_log("round_request", wid, goal.text, Prompt.round_system(worker.memory, worker.role)
		+ "\n\n---\n\n" + Prompt.round_user(goal, crew, town, clock, farm, livestock))
	calls_made += 1
	_begin_call("round")
	if http.request(str(route["url"]), route["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_composing.erase("round:" + wid)
		round_ready.emit(wid, ArchetypeLibrary.goal_round(goal.text, goal.rounds), "fallback")


## The reply's text, with any fence or stray quoting stripped. Kept to a
## couple of sentences: a speech bubble is not a place for an essay, and the
## prompt asked for two anyway.
func _plain_text(raw: String) -> String:
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return ""
	var choices: Variant = (json.data as Dictionary).get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		return ""
	var msg: Variant = ((choices as Array)[0] as Dictionary).get("message", {})
	var text := str((msg as Dictionary).get("content", "")).strip_edges()
	# Reasoning models on some gateways put their thinking in the content.
	# Nobody says that out loud.
	var think_end := text.rfind("</think>")
	if think_end >= 0:
		text = text.substr(think_end + 8).strip_edges()
	if text.begins_with("```"):
		var nl := text.find("\n")
		text = text.substr(nl + 1) if nl >= 0 else text
		text = text.trim_suffix("```").strip_edges()
	text = text.trim_prefix("\"").trim_suffix("\"").strip_edges()
	if text.length() > 320:
		var cut := text.rfind(". ", 300)
		text = text.substr(0, cut + 1) if cut > 80 else text.substr(0, 300) + "…"
	return text


## Only cache-serve an instruction that is a plain request for a building type.
## Anything with extra clauses in it deserves a real call, because the clauses
## are where the misinterpretation lives.
func _instruction_is_plain(instruction: String) -> bool:
	var w := instruction.strip_edges().split(" ", false)
	return w.size() <= 5


func _request(instruction: String, mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town, key: String, attempt: int, repair: String) -> void:
	var sys := Prompt.system(mem, ctx, true)
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

	var route := _route()
	var headers: PackedStringArray = route["headers"]

	# The system prompt is a message with role "system" here rather than a
	# field of its own, which is the one shape difference that matters.
	var body := {
		"model": model,
		"temperature": 0.7,
		"messages": [
			{"role": "system", "content": sys},
			{"role": "user", "content": usr},
		],
	}
	# Newer gateways renamed max_tokens when reasoning models made the old name
	# ambiguous, and quietly ignore the old one — which caps the reply at their
	# default and truncates exactly the plans this was raised to fit. A plain
	# OpenAI-compatible server does not have a reasoning field at all, and
	# rejects the body if one is sent.
	_finish_body(body, MAX_TOKENS)

	# The actions are tools. The model calls one; it does not write the plan
	# into the message. A gateway that also locks the whole reply to a JSON
	# schema will refuse the tool call, so the schema is not sent alongside.
	var allowed: Array = []
	var role: Role = ctx.get("role", null)
	if role != null and role.id != "builder":
		for c: String in role.ready_capabilities():
			allowed.append(c)
	body["tools"] = PlanSchema.tools_for(int(ctx.get("tier", 1)), allowed)
	body["tool_choice"] = "required"
	var payload := JSON.stringify(body)
	_log("request", mem.worker_id, instruction, sys + "\n\n---\n\n" + usr)
	calls_made += 1
	_begin_call("plan")

	if http.request(str(route["url"]), headers, HTTPClient.METHOD_POST, payload) != OK:
		http.queue_free()
		_busy.erase(mem.worker_id)
		_offline_answer(instruction, mem, plot, ctx)


func _on_reply(result: int, code: int, body: PackedByteArray, instruction: String,
		mem: WorkerMemory, plot: Plot, ctx: Dictionary, clock: GameClock, town: Town,
		key: String, attempt: int) -> void:
	var raw := body.get_string_from_utf8()
	_log("response", mem.worker_id, instruction, "http=%d result=%d\n%s" % [code, result, raw])
	_end_call(result != HTTPRequest.RESULT_SUCCESS or code != 200)

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# Say what the gateway actually said. "No reply" sends whoever is
		# debugging into their own code, when the answer is almost always a
		# model id or an account balance.
		if result == HTTPRequest.RESULT_TIMEOUT:
			last_error = "timed out after %.0f s" % TIMEOUT
		else:
			last_error = _gateway_message(raw)
		push_warning("[llm] %s failed http=%d result=%d: %s" % [
			model, code, result, last_error])

		# One more go, if the failure is the kind that comes and goes. The free
		# endpoints on this gateway drop a request now and then, and the cost of
		# not retrying is that the player gets the stock building instead of the
		# one they asked for. A retry of the SAME model is not a fallback chain:
		# it never quietly substitutes a different one.
		if attempt == 0 and _worth_retrying(result, code):
			retries += 1
			status.emit("%s: %s — trying once more." % [model, last_error])
			# A rate limit is the one failure where retrying at once is worse
			# than useless. Groq's free tier caps tokens per minute, not just
			# requests, and this prompt is a few thousand of them — so an
			# immediate second try is refused for the same reason as the first,
			# burns the one retry, and drops the player to the offline library.
			# The wait is free: the worker is walking to the plot regardless.
			#
			# The gateway says how long to wait, in the body of the 429, to two
			# decimal places: "Please try again in 34.9275s". Waiting a flat
			# RATE_LIMIT_WAIT was therefore wrong in both directions — a 35s hint
			# got 6s and failed again, and a 7s hint cost four wasted seconds of
			# the player's time. Now the hint is used when there is one.
			if code == 429:
				var hint := retry_hint_seconds(raw)
				var wait_s := hint if hint > 0.0 else RATE_LIMIT_WAIT
				# Capped, because a hostile or mistaken body could otherwise say
				# "try again in 86400s" and leave a worker thinking for a day.
				wait_s = minf(wait_s, MAX_RATE_LIMIT_WAIT)
				# Never shorter than the flat wait: a hint of 0.2s is a gateway
				# counting down its own window, and retrying into it burns the
				# one retry the player has.
				wait_s = maxf(wait_s, minf(RATE_LIMIT_WAIT, 2.0))
				rate_limit_waits += 1
				rate_limit_wait_total += wait_s
				# A short wait is worth saying out loud, because the worker is
				# visibly idle and the player is watching them. A long one is
				# not: at 30s+ the player has decided the game is broken and a
				# number only makes it worse.
				if wait_s >= 10.0:
					status.emit("%s is waiting %d s — the gateway is busy." % [
						mem.display_name, int(round(wait_s))])
				await get_tree().create_timer(wait_s).timeout
			_request(instruction, mem, plot, ctx, clock, town, key, 1, "")
			return

		_busy.erase(mem.worker_id)
		status.emit("%s: %s" % [model, last_error])
		failed.emit(mem.worker_id, last_error)
		_offline_answer(instruction, mem, plot, ctx)
		return

	var calls := _tool_calls(raw)
	var parsed := PlanSchema.from_tool_calls(calls) if not calls.is_empty() else _extract(raw)
	if str(parsed.get("kind", "")) == "talk":
		_busy.erase(mem.worker_id)
		plan_ready.emit(mem.worker_id, parsed)
		return

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
	if key != "":
		ArchetypeLibrary.store(key, parsed)
	plan_ready.emit(mem.worker_id, parsed)


func _offline_answer(instruction: String, mem: WorkerMemory, plot: Plot,
		ctx: Dictionary) -> void:
	fallbacks += 1
	_busy.erase(mem.worker_id)
	var plan := ArchetypeLibrary.fallback(instruction, mem, plot, int(ctx.get("tier", 1)))
	# No recognised job. Saying so is the whole answer — a hut was the old
	# guess, and it is what walked them off when the words were not an order.
	if plan.is_empty():
		plan = {
			"kind": "talk",
			"worker_line": "I cannot think that through just now, and I will not guess at a job.",
			"source": "fallback",
		}
	plan_ready.emit(mem.worker_id, plan)


## Tool calls on the first choice, in the OpenAI shape every gateway here uses.
func _tool_calls(raw: String) -> Array:
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return []
	var choices: Variant = (json.data as Dictionary).get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		return []
	var msg: Variant = ((choices as Array)[0] as Dictionary).get("message", {})
	if not (msg is Dictionary):
		return []
	var calls: Variant = (msg as Dictionary).get("tool_calls", [])
	if not (calls is Array):
		return []
	var out: Array = []
	for c: Variant in calls:
		if not (c is Dictionary):
			continue
		var fn: Variant = (c as Dictionary).get("function", {})
		if not (fn is Dictionary):
			continue
		out.append({
			"name": str((fn as Dictionary).get("name", "")),
			"arguments": (fn as Dictionary).get("arguments", {}),
		})
	return out


# -------------------------------------------------------------------- parsing

func _extract(raw: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return {}
	var payload: Dictionary = json.data
	var choices: Variant = payload.get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		return {}
	var first: Variant = (choices as Array)[0]
	if not (first is Dictionary):
		return {}
	var msg: Variant = (first as Dictionary).get("message", {})
	if not (msg is Dictionary):
		return {}
	var text := str((msg as Dictionary).get("content", "")).strip_edges()

	# Models sometimes fence JSON despite being told not to.
	if text.begins_with("```"):
		var nl := text.find("\n")
		text = text.substr(nl + 1) if nl >= 0 else text
		text = text.trim_suffix("```").strip_edges()
	return _first_object(text)


## The first balanced {...} in the text that parses and looks like our reply.
##
## Cheaper models think out loud before answering, and that thinking is full of
## braces: quoted schema fragments, worked examples, half-written objects. So
## take the first candidate that both parses AND carries a "kind" field, rather
## than trusting the outermost pair of braces in the whole string — which is
## what the previous version did, and which swallows the reasoning along with
## the answer.
static func _first_object(text: String) -> Dictionary:
	var start := 0
	while true:
		var open := text.find("{", start)
		if open < 0:
			return {}
		var depth := 0
		var in_string := false
		var escaped := false
		var i := open
		while i < text.length():
			var ch := text[i]
			if in_string:
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == "\"":
					in_string = false
			elif ch == "\"":
				in_string = true
			elif ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					var j := JSON.new()
					if j.parse(text.substr(open, i - open + 1)) == OK \
							and j.data is Dictionary \
							and (j.data as Dictionary).has("kind"):
						return j.data
					break
			i += 1
		start = open + 1
	return {}


## Whether a failure is worth a second attempt.
##
## Server faults, rate limits and dropped connections come and go. A 400 or
## a 401 will say the same thing every time — a bad model id, or an empty
## account — and retrying only doubles the wait before the player finds out.
## A timeout is excluded too: it has already cost ninety seconds.
static func _worth_retrying(result: int, code: int) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS:
		return result != HTTPRequest.RESULT_TIMEOUT
	return code >= 500 or code == 429


## A human-readable reason out of a gateway error body.
static func _gateway_message(raw: String) -> String:
	var j := JSON.new()
	if j.parse(raw) == OK and j.data is Dictionary:
		var err: Variant = (j.data as Dictionary).get("error", {})
		if err is Dictionary:
			var m := str((err as Dictionary).get("message", ""))
			if m != "":
				return m
	return raw.substr(0, 120) if raw != "" else "no response"


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

	# A bare "spec" is still accepted and still correct: it is what the offline
	# library emits, what every cached plan on disk holds, and what a model that
	# has ignored the steps section will produce anyway. Steps.normalise() turns
	# it into a one-step plan downstream, so there is exactly one shape past
	# this point and only one of them has to be described here.
	var steps: Array = d.get("steps", []) if d.get("steps", null) is Array else []
	if steps.is_empty():
		if not (d.get("spec", null) is Dictionary):
			return "steps must be a non-empty array, or give a single spec object"
		steps = [{"do": "build", "spec": d["spec"]}]
	if steps.size() > Steps.MAX_STEPS:
		return "at most %d steps — this is one order, not a project" % Steps.MAX_STEPS

	for s: Variant in steps:
		if not (s is Dictionary):
			return "every step must be an object"
		var step: Dictionary = s
		var verb := str(step.get("do", ""))
		if verb == "":
			return "every step needs a \"do\""
		if not Steps.known(verb):
			return "\"%s\" is not a step — use only the ones listed" % verb
		if verb == "build":
			if not (step.get("spec", null) is Dictionary):
				return "a build step needs a spec object"
			var spec: Dictionary = step["spec"]
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


## What the AI layer is doing, in one line, for the boot log and the HUD.
func describe() -> String:
	var name := AIProvider.label(provider)
	if api_key == "" and proxy_url == "":
		return "offline (no %s) - using the plan library" \
			% str(AIProvider.of(provider)["key_env"])
	if offline:
		return "offline (--offline) - using the plan library"
	# Whether the JSON is guaranteed to parse is the most useful thing about a
	# run, and the hardest to work out afterwards from a log of bad replies.
	var held := "" if AIProvider.schema_mode(provider) == "none" \
		else ", schema-locked"
	if api_key == "":
		return "%s via the proxy, model %s%s" % [name, model, held]
	return "%s, model %s%s" % [name, model, held]


func stats_text() -> String:
	var s := "calls %d  cache %d  retry %d  fallback %d  specs %d" % [
		calls_made, cache_hits, retries, fallbacks, ArchetypeLibrary.cache_size()]
	# Latency only once there is something to report: an average over one call
	# is noise, and printing "median 0.0s" next to a real wait is worse than
	# printing nothing.
	var lat := latency_report()
	if int(lat.get("n", 0)) > 0:
		s += "  |  %d calls  median %.1fs  p90 %.1fs  max %.1fs" % [
			int(lat["n"]), float(lat["median"]), float(lat["p90"]),
			float(lat["max"])]
	if rate_limit_waits > 0:
		s += "  |  rate limited %dx, waited %.0fs total" % [
			rate_limit_waits, rate_limit_wait_total]
	return s
