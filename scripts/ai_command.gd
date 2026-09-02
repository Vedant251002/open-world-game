extends Node
## AI COMMAND LAYER — multi-provider, all FREE:
## 1) OpenRouter free models (user directive)  2) OpenCode Zen gateway fallback
## 3) built-in offline keyword parser as last resort.
signal order_ready(order: Dictionary)
signal status(msg: String)

const SYSTEM_PROMPT := """You are the command parser for a 3D city-building game (player is the king).
Convert the player's natural-language order into ONE compact JSON object. Output ONLY the JSON.
Schema:
{"action":"build|demolish|query|move","object":"<thing to build, lowercase, singular>","location_relation":"near|on|in|at","location":"<one of: beach|park|downtown|market|here|main street|ocean>"}
Rules: object is the building type only (e.g. cafeteria, house, hotel, shop, statue, tower, garage, office). If the player asks something unrelated, use {"action":"query","object":"<topic>","location_relation":"at","location":"here"}."""

const OPENROUTER_MODELS := [
	"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
	"nvidia/nemotron-3.5-lightning:free",
	"nvidia/nemotron-3-super-120b-a12b:free",
]

var _endpoints: Array = []
var _busy := false
var last_provider := ""


func _ready() -> void:
	_load_endpoints()


func _read_env(path: String, varname: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var val := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with(varname + "="):
			val = line.substr(varname.length() + 1).strip_edges().trim_prefix('"').trim_suffix('"')
			break
	f.close()
	return val


func _load_endpoints() -> void:
	# --- 1) OpenRouter free models (key from .env) ---
	var orkey := OS.get_environment("OPENROUTER_API_KEY")
	if orkey == "":
		orkey = _read_env("res://.env", "OPENROUTER_API_KEY")
	if orkey != "":
		for m in OPENROUTER_MODELS:
			_endpoints.append({
				"label": "OpenRouter/" + m,
				"url": "https://openrouter.ai/api/v1",
				"key": orkey,
				"model": m,
				"extra": ["HTTP-Referer: neon-bay-city", "X-Title: Neon Bay City"],
			})
	# --- 2) OpenCode Zen gateway (key from .env) ---
	var okey := OS.get_environment("OPENCODE_API_KEY")
	var ourl := OS.get_environment("OPENCODE_BASE_URL")
	if okey == "" or ourl == "":
		okey = _read_env("res://.env", "OPENCODE_API_KEY")
		ourl = _read_env("res://.env", "OPENCODE_BASE_URL")
	if okey != "" and ourl != "":
		_endpoints.append({
			"label": "OpenCode/glm-5.3-flash",
			"url": ourl,
			"key": okey,
			"model": "glm-5.3-flash",
			"extra": [],
		})


func available() -> bool:
	return not _endpoints.is_empty()


func submit(text: String) -> void:
	if _busy:
		emit_status("The advisor is still thinking, my liege...")
		return
	if _endpoints.is_empty():
		emit_status("No AI reachable — using the royal clerk (offline parser)")
		_fallback_parse(text)
		return
	_busy = true
	emit_status("Consulting the royal advisor...")
	_try(0, text)


func _try(idx: int, text: String) -> void:
	if idx >= _endpoints.size():
		_busy = false
		emit_status("All advisors unreachable — using the royal clerk")
		_fallback_parse(text)
		return
	var ep: Dictionary = _endpoints[idx]
	var http := HTTPRequest.new()
	http.timeout = 25.0
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(
		func(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray):
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				_try(idx + 1, text)
				return
			var parsed := _extract_json(body.get_string_from_utf8())
			if parsed.is_empty():
				_try(idx + 1, text)
				return
			_busy = false
			last_provider = ep["label"]
			print("AI_USED ", ep["label"])
			emit_status("Advisor (%s) understood you." % ep["label"])
			order_ready.emit(parsed),
		CONNECT_ONE_SHOT
	)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + ep["key"]])
	for h in ep["extra"]:
		headers.append(h)
	var body := JSON.stringify({
		"model": ep["model"],
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": text},
		],
		"temperature": 0.1,
	})
	var err := http.request(ep["url"] + "/chat/completions", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		_try(idx + 1, text)


func _extract_json(txt: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(txt) != OK:
		return {}
	var payload = json.data
	if not (payload is Dictionary) or not payload.has("choices"):
		return {}
	var content: String = payload["choices"][0]["message"]["content"]
	content = content.strip_edges().trim_prefix("```json").trim_prefix("```").trim_suffix("```").strip_edges()
	var j2 := JSON.new()
	if j2.parse(content) == OK and j2.data is Dictionary:
		return j2.data
	return {}


func _fallback_parse(text: String) -> void:
	var t := text.to_lower()
	var order := {"action": "build", "object": "house", "location_relation": "at", "location": "here"}
	var verbs := ["build", "make", "construct", "create"]
	for v in verbs:
		if v in t:
			order["action"] = "build"
			break
	if "demolish" in t or "remove" in t or "destroy" in t:
		order["action"] = "demolish"
	var buildings := ["cafeteria", "house", "hotel", "shop", "cafe", "statue", "tower", "garage", "office", "restaurant", "bar", "apartment", "market", "gym", "library", "museum", "bank", "hospital", "school", "park"]
	for b in buildings:
		if b in t:
			order["object"] = b
			break
	if "beach" in t:
		order["location"] = "beach"
	elif "park" in t:
		order["location"] = "park"
	elif "downtown" in t:
		order["location"] = "downtown"
	_busy = false
	last_provider = "offline-clerk"
	order_ready.emit(order)


func emit_status(msg: String) -> void:
	status.emit(msg)
