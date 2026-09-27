"""Test the player-run classifier against the logs it actually produced.

The whole point of run_player.py's scoring is that a case is only "answered"
when the thing that came back was an answer. Three separate mistakes got past
it in one session -- a citizen's background line, a cough from an ill worker,
and a gateway that was simply full -- and each produced a confident wrong
number. So the classifier is checked against the real log lines, not against
what it was written for.

    python _tools/test_player_classifier.py
"""
import re
import sys

# Verbatim from runs on 2026-09-27.
LOGS = {
    # a real reply, in the worker's own voice
    "good": [
        "Ha! A flibbertigibbet wombat, you say — I'll keep an eye out for it.",
        "Good morning! I didn't quite catch that — was it a word?",
        "I cannot think that through just now, and I will not guess at a job.",
    ],
    # background: a citizen or an ill worker, said unprompted
    "chatter": [
        "I am grey and weak.",
        "I am burning up.",
        "I am coughing fit to split.",
    ],
    # the gateway, not the town
    "gateway": [
        "WARNING: [llm] z-ai/glm-5.3-flash-free failed http=429 result=0: "
        "Free model capacity is limited right now. Retry shortly, or add "
        "credits for higher, more stable limits",
        "WARNING: [llm] openai/gpt-oss-120b failed http=429 result=0: Rate "
        "limit reached for model `openai/gpt-oss-120b` in organization `org_x` "
        "service tier `on_demand` on tokens per day (TPD): Limit 200000, Used "
        "199451, Requested 2883. Please try again in 16m48s.",
        "WARNING: [llm] m failed http=429 result=0: Rate limit reached ... on "
        "tokens per minute (TPM): Limit 8000, Used 6273. Please try again in "
        "34.9275s.",
        "WARNING: [llm] m failed http=400 result=0: Tool call validation "
        "failed: parameters for tool harvest did not match schema: errors: "
        "[`/in`: expected string, but got null]",
    ],
}

IDLE = ("i am grey and weak", "i am burning up", "i am coughing fit to split",
        "i am not well")

# The same patterns run_player.py uses, kept in step deliberately: this file
# failing to match something the runner also fails to match is the signal.
GATEWAY = [
    (r"tokens per day", "daily token budget spent"),
    (r"tokens per minute", "per-minute token budget spent"),
    (r"capacity is limited", "free tier at capacity (gateway)"),
    (r"rate limit", "rate limited"),
    (r"http=(429)", "rate limited"),
    (r"http=(400)[^\n]*(expected string|not in request\.tools)", "schema rejected"),
    (r"http=(\d{3})", "gateway error"),
]

fails = 0

print("a reply is an answer")
for line in LOGS["good"]:
    chatter = any(s in line.lower() for s in IDLE)
    gw = any(re.search(p, line, re.I) for p, _ in GATEWAY)
    ok = (not chatter) and (not gw)
    if not ok:
        fails += 1
    print(f"  [{'OK ' if ok else 'FAIL'}] {line[:58]}")

print("\nbackground chatter is NOT an answer")
for line in LOGS["chatter"]:
    chatter = any(s in line.lower() for s in IDLE)
    if not chatter:
        fails += 1
    print(f"  [{'OK ' if chatter else 'FAIL'}] {line[:58]}")

print("\na gateway refusal is NOT the town's failure")
for line in LOGS["gateway"]:
    tag = ""
    for p, t in GATEWAY:
        if re.search(p, line, re.I):
            tag = t
            break
    if not tag:
        fails += 1
    print(f"  [{'OK ' if tag else 'FAIL'}] {tag:28s} {line[:44]}")

print("\nthe two are told apart: a gateway line beats a chatter line")
# The measured case: an ill worker's line AND a full gateway in the same log.
combined = LOGS["chatter"][0] + "\n" + LOGS["gateway"][0]
tag = ""
for p, t in GATEWAY:
    if re.search(p, combined, re.I):
        tag = t
        break
want = "free tier at capacity (gateway)"
if tag != want:
    fails += 1
print(f"  [{'OK ' if tag == want else 'FAIL'}] got {tag!r}, want {want!r}")

print()
print("ALL PASS" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
