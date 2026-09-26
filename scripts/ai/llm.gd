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
## The router has decided what a sentence is. `reply` is the model's object
## — kind plan / chat / question — or {"kind": "offline"} when there is no
## model, or {"kind": "failed", "reason": ...} when there was one and it did
## not answer. The dispatcher owns what happens next in every case.
signal routed(worker_id: String, reply: Dictionary)

## The browser build cannot call a gateway directly. None of them send CORS
## headers, so the request is refused before it leaves the page — that is a rule of the
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
## Which gateway is answering. Chosen at boot by which key is present, Groq
## first — see AIProvider.PREFERENCE and _pick_provider.
var provider := "orcarouter"
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
## And the longest. A gateway that asks for a minute is asking for longer than
## anybody will stand in a field waiting; past this the offline library is the
## better answer.
const RATE_LIMIT_WAIT_MAX := 30.0
const LOG_DIR := "user://ai_log"

var api_key := ""
var proxy_url := ""
var model := ""
## The router's model. See AIProvider: the small one, for every sentence.
var fast_model := ""
var last_error := ""
var offline := false          ## forced by --offline, or by having no key

var calls_made := 0
var cache_hits := 0
var retries := 0
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
	proxy_url = OS.get_environment("AI_PROXY_URL")
	if proxy_url == "":
		proxy_url = _read_env("res://.env", "AI_PROXY_URL")
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
	var fast_env := str(AIProvider.of(provider).get("fast_model_env", ""))
	fast_model = OS.get_environment(fast_env) if fast_env != "" else ""
	if fast_model == "" and fast_env != "":
		fast_model = _read_env("res://.env", fast_env)
	if fast_model == "":
		fast_model = str(AIProvider.of(provider).get("default_fast_model", model))
	for arg3 in OS.get_cmdline_user_args():
		if arg3.begins_with("--fast-model="):
			fast_model = arg3.substr(13)
	if "--offline" in OS.get_cmdline_user_args():
		offline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))


## Which gateway to talk to.
##
## Named outright with --provider= or AI_PROVIDER, and otherwise decided by
## which key is actually present — Groq first, because it answers without
## thinking for a thousand tokens first. Falling through to the next gateway
## rather than going offline matters: a missing Groq key should cost some
## speed, not the AI.
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
	provider = "orcarouter"


func available() -> bool:
	return (api_key != "" or proxy_url != "") and not offline


## Where a request goes, and with what on it.
##
## A key in hand wins, and the proxy is the fallback. This is the reverse of
## what it used to be, and the reason is that the proxy holds one key for one
## gateway: routing a Groq request through a Worker whose secret is an
## OrcaRouter key sends it to the wrong place with the wrong credentials. Trying the key
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


# -------------------------------------------------------------------- routing

## Sentences the router is still deciding about.
var _routing: Dictionary = {}
## A route reply is a verb and a few fields, or a line. Four hundred and
## fifty covers a four-step plan with a building brief in it, and the ceiling
## is charged against the free tier's per-minute budget whether the reply
## uses it or not.
const ROUTE_TOKENS := 450


## Every sentence said to a worker starts here. The small model reads it
## against the catalogue and says what it is; nothing in the engine matches a
## word of it. See Prompt.router_system for what it is shown.
func route(instruction: String, mem: WorkerMemory, ctx: Dictionary,
		clock: GameClock, town: Town, crew: Crew) -> void:
	if _routing.get(mem.worker_id, false):
		status.emit("%s is still thinking." % mem.display_name)
		return
	if not available():
		routed.emit(mem.worker_id, {"kind": "offline"})
		return
	_routing[mem.worker_id] = true
	_route_request(instruction, mem, ctx, clock, town, crew, 0, "", fast_model)


## `with_model` is which of the two answers this attempt. It is the small one
## every time but the one after a rate limit — see _on_route_reply.
func _route_request(instruction: String, mem: WorkerMemory, ctx: Dictionary,
		clock: GameClock, town: Town, crew: Crew, attempt: int, repair: String,
		with_model: String) -> void:
	var sys := Prompt.router_system(mem, ctx)
	var usr := Prompt.router_user(instruction, mem, ctx, clock, town, crew)
	if repair != "":
		usr += "\n\nYour previous reply could not be used: %s\nReturn corrected JSON only." % repair

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_on_route_reply(result, code, h, body, instruction, mem, ctx, clock, town,
				crew, attempt, with_model),
		CONNECT_ONE_SHOT)

	var route_to := _route()
	var body := {
		"model": with_model,
		"temperature": 0.3,
		"messages": [
			{"role": "system", "content": sys},
			{"role": "user", "content": usr},
		],
	}
	body.merge(AIProvider.quiet_body(provider, "low"))
	body[AIProvider.token_field(provider)] = AIProvider.budget(provider, ROUTE_TOKENS)
	if AIProvider.schema_mode(provider) != "none":
		var allowed: Array = []
		var role: Role = ctx.get("role", null)
		if role != null and role.id != "builder":
			for c: String in role.ready_capabilities():
				allowed.append(c)
		body["response_format"] = {
			"type": "json_schema",
			"json_schema": PlanSchema.router_schema(int(ctx.get("tier", 1)), allowed),
		}
	var fmt := JSON.stringify(body.get("response_format", {}))
	_log("route", mem.worker_id, instruction, "%s\n\n---\n\n%s\n\n--- schema (%d chars)\n%s"
		% [sys, usr, fmt.length(), fmt])
	calls_made += 1
	if http.request(str(route_to["url"]), route_to["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_routing.erase(mem.worker_id)
		routed.emit(mem.worker_id, {"kind": "failed", "reason": "could not send"})


func _on_route_reply(result: int, code: int, headers: PackedStringArray, body: PackedByteArray,
		instruction: String, mem: WorkerMemory, ctx: Dictionary, clock: GameClock,
		town: Town, crew: Crew, attempt: int, with_model: String) -> void:
	var raw := body.get_string_from_utf8()
	_log("routed", mem.worker_id, instruction, "http=%d result=%d\n%s" % [code, result, raw])

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_error = ("timed out after %.0f s" % TIMEOUT) if result == HTTPRequest.RESULT_TIMEOUT \
			else _gateway_message(raw)
		push_warning("[llm] router %s failed http=%d result=%d: %s" % [with_model, code, result, last_error])
		if attempt == 0 and _worth_retrying(result, code, raw):
			retries += 1
			# A per-minute token budget is counted per model, so the one the
			# router has just exhausted is not the one the designer uses. The
			# big model can answer a routing question perfectly well — it is
			# only slower and dearer, which is the right thing to be when the
			# alternative is telling the player to say it again. Waiting out
			# the bucket comes first; this is what happens when that is not
			# enough.
			var next_model := with_model
			if code == 429 or code == 413:
				await get_tree().create_timer(_retry_after(headers)).timeout
				if with_model != model:
					next_model = model
					status.emit("%s is busy; asking %s." % [fast_model, model])
			_route_request(instruction, mem, ctx, clock, town, crew, 1, "", next_model)
			return
		_routing.erase(mem.worker_id)
		status.emit("%s: %s" % [with_model, last_error])
		routed.emit(mem.worker_id, {"kind": "failed", "reason": last_error})
		return

	var parsed := _extract(raw)
	var problem := _route_problem(parsed)
	if problem != "":
		if attempt == 0:
			retries += 1
			_route_request(instruction, mem, ctx, clock, town, crew, 1, problem, with_model)
			return
		_routing.erase(mem.worker_id)
		push_warning("[llm] router rejected twice: %s" % problem)
		routed.emit(mem.worker_id, {"kind": "failed", "reason": problem})
		return

	_routing.erase(mem.worker_id)
	routed.emit(mem.worker_id, parsed)


## Shape only. Whether the town can do it is the validator's, and whether
## the building fits is the designer's.
func _route_problem(d: Dictionary) -> String:
	if d.is_empty():
		return "the reply was not JSON"
	var kind := str(d.get("kind", ""))
	if kind == "chat":
		return ""
	if kind == "question":
		if str(d.get("question", "")).strip_edges() == "":
			return "kind was question but no question was given"
		return ""
	# A small model's favourite near miss is to answer with the verb as the
	# kind — {"kind": "standing", "steps": [{"do": "standing", ...}]} — which
	# is a correct plan with a wrong label on it. Refusing that costs a round
	# trip to be told something the reply already said, so it is read as what
	# it plainly is. Anything with no steps in it is still refused.
	if kind != "plan":
		if not (d.get("steps", null) is Array) or (d["steps"] as Array).is_empty():
			return "kind must be exactly \"plan\", \"chat\" or \"question\""
		d["kind"] = "plan"
	var steps: Array = d.get("steps", []) if d.get("steps", null) is Array else []
	if steps.is_empty():
		return "a plan needs at least one step"
	if steps.size() > Steps.MAX_STEPS:
		return "at most %d steps — this is one order, not a project" % Steps.MAX_STEPS
	for s: Variant in steps:
		if not (s is Dictionary):
			return "every step must be an object"
		var verb := str((s as Dictionary).get("do", ""))
		if verb == "":
			return "every step needs a \"do\""
		if not Steps.known(verb):
			return "\"%s\" is not a verb — use only the ones listed" % verb
		if verb == "build" and str((s as Dictionary).get("brief", "")).strip_edges() == "" \
				and not ((s as Dictionary).get("spec", null) is Dictionary):
			return "a build step needs a brief in words"
	return ""


# ---------------------------------------------------------------- submission

## The designer. Only a building brief comes here now: the router has
## already decided the sentence is a build, and this is the model that can
## hold a floor plan in its head.
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
	# ...unless it is not a building at all. The cache is keyed by archetype and
	# guess_archetype answers "hut" for anything it does not recognise, so "bring
	# six hens" is a three-word plain instruction that hashes to whatever hut was
	# last built on this plot. The old livestock branch in Dispatcher hid this by
	# never letting such an order reach here; now that orders compose, it has to
	# be said properly.
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
		"model": fast_model,
		"temperature": 0.6,
		"messages": [
			{"role": "system", "content": Prompt.chat_system(mem, ctx)},
			{"role": "user", "content": Prompt.chat_user(question, mem, ctx, clock, town)},
		],
	}
	body.merge(AIProvider.quiet_body(provider, "low"))
	body[AIProvider.token_field(provider)] = AIProvider.budget(provider, ANSWER_TOKENS)
	calls_made += 1
	if http.request(str(route["url"]), route["headers"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		http.queue_free()
		_chatting.erase(mem.worker_id)
		answered.emit(mem.worker_id, "I could not tell you just now.")


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
	body.merge(AIProvider.quiet_body(provider, "medium"))
	body[AIProvider.token_field(provider)] = AIProvider.budget(provider, ROLE_TOKENS)
	if AIProvider.schema_mode(provider) != "none":
		body["response_format"] = {
			"type": "json_schema", "json_schema": PlanSchema.role_schema(),
		}
	_log("role_request", key, name, Prompt.role_system() + "

---

"
		+ Prompt.role_user(name, description, ctx))
	calls_made += 1
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
		"model": fast_model,
		"temperature": 0.6,
		"messages": [
			{"role": "system", "content": Prompt.round_system(worker.memory, worker.role)},
			{"role": "user", "content": Prompt.round_user(goal, crew, town, clock, farm, livestock)},
		],
	}
	body.merge(AIProvider.quiet_body(provider, "low"))
	body[AIProvider.token_field(provider)] = AIProvider.budget(provider, ROLE_TOKENS)
	if AIProvider.schema_mode(provider) != "none":
		body["response_format"] = {"type": "json_schema", "json_schema": PlanSchema.round_schema()}
	_log("round_request", wid, goal.text, Prompt.round_system(worker.memory, worker.role)
		+ "\n\n---\n\n" + Prompt.round_user(goal, crew, town, clock, farm, livestock))
	calls_made += 1
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
	var sys := Prompt.system(mem, ctx)
	var usr := Prompt.user(instruction, mem, plot, ctx, clock, town)
	if repair != "":
		usr += "\n\nYour previous reply could not be used: %s\nReturn corrected JSON only." % repair

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_on_reply(result, code, h, body, instruction, mem, plot, ctx, clock, town,
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
	# Several of these models think out loud into a separate field that shares
	# the token budget with the answer. Left on, the reasoning eats three
	# thousand tokens and the JSON is cut off mid-string, which is not a worse
	# plan but no plan at all. How a gateway is told to stop is its own
	# business — see AIProvider — and telling the wrong one is a 400.
	body.merge(AIProvider.quiet_body(provider, "medium"))
	# Newer gateways renamed max_tokens when reasoning models made the old name
	# ambiguous, and quietly ignore the old one — which caps the reply at their
	# default and truncates exactly the plans this was raised to fit.
	body[AIProvider.token_field(provider)] = AIProvider.budget(provider, MAX_TOKENS)

	# And the point of the whole exercise: on a gateway that constrains its
	# decoding, ask it to. The reply then cannot come back as unparseable JSON,
	# which is the failure that costs a full round trip and yields nothing.
	if AIProvider.schema_mode(provider) != "none":
		var allowed: Array = []
		var role: Role = ctx.get("role", null)
		if role != null and role.id != "builder":
			for c: String in role.ready_capabilities():
				allowed.append(c)
		body["response_format"] = {
			"type": "json_schema",
			"json_schema": PlanSchema.for_tier(int(ctx.get("tier", 1)), allowed, "design"),
		}
	var payload := JSON.stringify(body)
	_log("request", mem.worker_id, instruction, sys + "\n\n---\n\n" + usr)
	calls_made += 1

	if http.request(str(route["url"]), headers, HTTPClient.METHOD_POST, payload) != OK:
		http.queue_free()
		_busy.erase(mem.worker_id)
		_offline_answer(instruction, mem, plot, ctx)


func _on_reply(result: int, code: int, headers: PackedStringArray, body: PackedByteArray,
		instruction: String, mem: WorkerMemory, plot: Plot, ctx: Dictionary,
		clock: GameClock, town: Town, key: String, attempt: int) -> void:
	var raw := body.get_string_from_utf8()
	_log("response", mem.worker_id, instruction, "http=%d result=%d\n%s" % [code, result, raw])

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
		if attempt == 0 and _worth_retrying(result, code, raw):
			retries += 1
			status.emit("%s: %s — trying once more." % [model, last_error])
			# A rate limit is the one failure where retrying at once is worse
			# than useless. Groq's free tier caps tokens per minute, not just
			# requests, and this prompt is a few thousand of them — so an
			# immediate second try is refused for the same reason as the first,
			# burns the one retry, and drops the player to the offline library.
			# The wait is free: the worker is walking to the plot regardless.
			if code == 429:
				await get_tree().create_timer(_retry_after(headers)).timeout
			_request(instruction, mem, plot, ctx, clock, town, key, 1, "")
			return

		_busy.erase(mem.worker_id)
		status.emit("%s: %s" % [model, last_error])
		failed.emit(mem.worker_id, last_error)
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
static func _worth_retrying(result: int, code: int, raw: String = "") -> bool:
	if result != HTTPRequest.RESULT_SUCCESS:
		return result != HTTPRequest.RESULT_TIMEOUT
	if code >= 500 or code == 429:
		return true
	# A per-minute token budget is refused as 413 rather than 429 on some
	# gateways, and 413 otherwise means "this will never fit" — so the body
	# has to be read to tell a wait from a dead end.
	if code == 413:
		var m := _gateway_message(raw).to_lower()
		return m.find("per minute") >= 0 or m.find("rate limit") >= 0 \
			or m.find("tpm") >= 0
	return false


## How long the gateway says to wait, within reason. Asking is much better
## than guessing: a token bucket that refills in four seconds should not cost
## thirty, and one that needs twenty should not be poked at six.
static func _retry_after(headers: PackedStringArray) -> float:
	var wait := RATE_LIMIT_WAIT
	for h: String in headers:
		var low := h.to_lower()
		if not (low.begins_with("retry-after") or low.find("ratelimit-reset") >= 0):
			continue
		var value := low.substr(low.find(":") + 1).strip_edges()
		var secs := 0.0
		if value.ends_with("ms"):
			secs = float(value.trim_suffix("ms")) / 1000.0
		else:
			secs = float(value.trim_suffix("s"))
		if secs > 0.0:
			wait = maxf(wait, secs + 0.5)
	return clampf(wait, RATE_LIMIT_WAIT, RATE_LIMIT_WAIT_MAX)


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
	if fast_model != model:
		return "%s, %s routing, %s designing%s" % [name, fast_model, model, held]
	return "%s, model %s%s" % [name, model, held]


func stats_text() -> String:
	return "calls %d  cache %d  retry %d  fallback %d  specs %d" % [
		calls_made, cache_hits, retries, fallbacks, ArchetypeLibrary.cache_size()]
