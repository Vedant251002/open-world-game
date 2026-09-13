extends RefCounted
class_name Goal
## A standing objective given to somebody who can give orders.
##
## "Get a farm going" is not a plan; it is a reason for several plans over
## several days, handed out to several people. A goal is the thing that
## holds that together: the words, what has been done toward it, how many
## mornings it has had, and whether it is met. The foreman who holds it
## plans one round a day — a few orders to named people, or a hire where the
## town lacks the trade — and the round is planned knowing what the last one
## did. That is the game's own premise made recursive: you delegate to a
## person who delegates.

const MAX_ROUNDS := 12
const MAX_ORDERS_PER_ROUND := 4

var text := ""
var given_day := 0
var rounds := 0
var done := false
## Everything issued so far, oldest first: {"day", "who", "order", "outcome"}.
## Outcome is "given", "refused", "done" as it becomes known.
var log: Array[Dictionary] = []
## The current round's orders still to go out, and who they went to.
var pending: Array[Dictionary] = []
var out: Array[String] = []            ## worker ids with an order of this round in hand


func summary() -> String:
	if done:
		return "%s — done" % text
	var given := 0
	var refused := 0
	for e: Dictionary in log:
		if str(e.get("outcome", "")) == "refused":
			refused += 1
		else:
			given += 1
	return "%s — day %d of it, %d orders given%s" % [text, rounds, given,
		(", %d refused" % refused) if refused > 0 else ""]


## The log as a few lines a prompt or a report can use.
func recent_lines(n: int = 8) -> Array[String]:
	var lines: Array[String] = []
	var start := maxi(log.size() - n, 0)
	for i in range(start, log.size()):
		var e: Dictionary = log[i]
		lines.append("day %d: told %s to %s (%s)" % [int(e["day"]), str(e["who"]),
			str(e["order"]), str(e.get("outcome", "given"))])
	return lines


func note(day: int, who: String, order: String, outcome: String = "given") -> void:
	log.append({"day": day, "who": who, "order": order, "outcome": outcome})


func mark(who: String, outcome: String) -> void:
	for i in range(log.size() - 1, -1, -1):
		if str(log[i]["who"]) == who and str(log[i].get("outcome", "")) == "given":
			log[i]["outcome"] = outcome
			return


func to_dict() -> Dictionary:
	return {"text": text, "given_day": given_day, "rounds": rounds, "done": done,
		"log": log.duplicate(true)}


static func from_dict(d: Dictionary) -> Goal:
	var g := Goal.new()
	g.text = str(d.get("text", ""))
	g.given_day = int(d.get("given_day", 0))
	g.rounds = int(d.get("rounds", 0))
	g.done = bool(d.get("done", false))
	for e: Variant in d.get("log", []):
		if e is Dictionary:
			g.log.append(e)
	return g
