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
		"schema": "strict",
		"max_tokens_field": "max_completion_tokens",
		"reasoning": true,
		"label": "Groq",
	},
	# The original. Kept because it works, costs nothing, and is what the
	# deployed proxy already holds a key for — but it is slow (the better part
	# of a minute), it has no structured output, and its free models truncate.
	"opencode": {
		"endpoint": "https://opencode.ai/zen/v1/chat/completions",
		"key_env": "OPENCODE_API_KEY",
		"model_env": "OPENCODE_MODEL",
		"default_model": "nemotron-3-ultra-free",
		"schema": "none",
		"max_tokens_field": "max_tokens",
		"reasoning": true,
		"label": "OpenCode Zen",
	},
}

## Tried in this order when nothing has been named. Groq first: it is the one
## that can promise the JSON parses.
const PREFERENCE := ["groq", "opencode"]


static func known(name: String) -> bool:
	return PROVIDERS.has(name)


static func of(name: String) -> Dictionary:
	return PROVIDERS.get(name, PROVIDERS["opencode"])


static func endpoint(name: String) -> String:
	return str(of(name)["endpoint"])


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
