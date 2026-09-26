extends RefCounted
class_name AIProvider
## Which gateway answers, and what it can be asked for.
##
## There used to be one endpoint and one model id, and every fact about them
## was a constant in LLM. That was fine while the answer was "OpenCode Zen",
## and stopped being fine the moment a second gateway was worth having: the
## interesting differences between them are not the URL but what they can be
## asked to guarantee.
##
## The one that matters here is constrained decoding. A gateway that accepts a
## response_format of json_schema will not return malformed JSON, because the
## decoder cannot emit a token that breaks the schema. That removes the single
## worst failure this game has — a reply that is cut off mid-string is not a
## worse plan, it is no plan at all, and the recovery is a wasted forty seconds
## followed by the offline library.

const PROVIDERS := {
	# Free, no card, and fast enough that the worker does not have to be sent
	# walking to hide the wait. gpt-oss-120b is on the free plan at 30 requests
	# a minute and supports strict structured outputs.
	#
	# The ceiling to watch is tokens per minute, not requests: 8K TPM against a
	# prompt that runs to three thousand tokens is roughly one order a minute
	# sustained. The archetype cache already absorbs most of that, and a plan
	# the town has seen before never leaves the machine.
	"groq": {
		"endpoint": "https://api.groq.com/openai/v1/chat/completions",
		"key_env": "GROQ_API_KEY",
		"model_env": "GROQ_MODEL",
		"default_model": "openai/gpt-oss-120b",
		# The router's model: the one that hears every sentence and decides
		# which verb it is. Small and quick — a seven-hundred-token prompt
		# and a one-line answer — and on the free plan it has its own rate
		# limit, so the designer's budget is not spent on "go to the well".
		"fast_model_env": "GROQ_FAST_MODEL",
		"default_fast_model": "openai/gpt-oss-20b",
		"reasoning_effort": "low",
		"schema": "strict",
		"max_tokens_field": "max_completion_tokens",
		# How this gateway is told not to think out loud. Groq's own switch
		# is a pair of plain fields; OrcaRouter's is a nested object, and
		# sending the wrong one is a 400 rather than something ignored —
		# which is why this is a table entry and not a constant in the body.
		"quiet": {"reasoning_format": "hidden"},
		"effort_field": "reasoning_effort",
		"label": "Groq",
	},
	# Free behind a linked GitHub account, no card. Replaces OpenCode Zen, whose
	# free tier stopped answering anything but its own editor in September 2026.
	#
	# Measured on the game's own bakery prompt (2,700 tokens in): every reply
	# under response_format json_schema finished with stop and parsed, in twenty
	# to thirty seconds; a chat answer takes five. The prompt is under the free
	# tier's per-request cap, and the gateway caches the system prompt between
	# calls.
	#
	# The catch is that GLM thinks before it answers and cannot be told not to:
	# every known switch is ignored, and Z.ai's own one is refused upstream. The
	# thinking runs to fifteen hundred tokens and comes out of the same budget
	# as the plan, so without the headroom below a plain 3,200-token request is
	# cut off mid-string — the exact failure the old gateway had.
	"orcarouter": {
		"endpoint": "https://api.orcarouter.ai/v1/chat/completions",
		"key_env": "ORCAROUTER_API_KEY",
		"model_env": "ORCAROUTER_MODEL",
		"default_model": "z-ai/glm-5.3-flash-free",
		"fast_model_env": "ORCAROUTER_FAST_MODEL",
		"default_fast_model": "z-ai/glm-5.3-flash-free",
		"schema": "strict",
		"max_tokens_field": "max_completion_tokens",
		"quiet": {"reasoning": {"exclude": true}},
		"token_headroom": 2.0,
		"label": "OrcaRouter",
	},
}

## Tried in this order when nothing has been named. Groq first: it is the one
## that can promise the JSON parses without spending half its budget thinking.
const PREFERENCE := ["groq", "orcarouter"]


static func known(name: String) -> bool:
	return PROVIDERS.has(name)


static func of(name: String) -> Dictionary:
	return PROVIDERS.get(name, PROVIDERS["orcarouter"])


static func endpoint(name: String) -> String:
	return str(of(name)["endpoint"])


## Everything this gateway needs told about thinking out loud, merged into
## the request body. `effort` is "low", "medium" or "" — the router asks for
## low, because its question is which of forty verbs a sentence is, and
## thinking about that for a thousand tokens makes the answer slower rather
## than better. A gateway with no such switch gets nothing, rather than a
## field it will refuse the whole request over.
static func quiet_body(name: String, effort: String = "") -> Dictionary:
	var out: Dictionary = (of(name).get("quiet", {}) as Dictionary).duplicate(true)
	var field := str(of(name).get("effort_field", ""))
	if field != "" and effort != "":
		out[field] = effort
	return out


static func label(name: String) -> String:
	return str(of(name)["label"])


## Whether this gateway will hold the reply to a schema, and how hard.
##   "strict" — constrained decoding; the JSON cannot come back broken
##   "none"   — hope, a prompt, and a parser that tolerates prose
static func schema_mode(name: String) -> String:
	return str(of(name)["schema"])


## Older gateways call it max_tokens; newer ones renamed it when reasoning
## models made the old name ambiguous. One line here beats a wrong field name
## that silently caps the reply at the default.
static func token_field(name: String) -> String:
	return str(of(name)["max_tokens_field"])


## The token budget to actually send, given what the caller wants back.
##
## A model that reasons out loud pays for the reasoning from the same budget
## as the answer, and on a gateway where that cannot be switched off the
## honest fix is to ask for more. Nothing is spent by asking: the reply stops
## when the answer does, and the extra is only the room for it to get there.
static func budget(name: String, asked: int) -> int:
	return int(ceil(asked * float(of(name).get("token_headroom", 1.0))))
