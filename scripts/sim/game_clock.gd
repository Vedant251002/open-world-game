extends Node
class_name GameClock
## One real minute is one in-game hour, per build-order.md slice 3.
##
## The clock is the reason DISCOVER works. A job takes three to eight in-game
## hours, which is three to eight real minutes — long enough to wander off and
## forget, short enough that you have not lost interest by the time Mira comes
## back to tell you what she has done.

signal hour_passed(hour: float, day: int)
signal day_passed(day: int)

const HOURS_PER_REAL_MINUTE := 1.0
const DAY_START := 7.0

var hour: float = DAY_START
var day: int = 1
var paused := false
var speed := 1.0            ## 1 = normal, raised while the player waits

var _last_hour := -1


func _process(delta: float) -> void:
	if paused:
		return
	advance(delta / 60.0 * HOURS_PER_REAL_MINUTE * speed)


func advance(hours: float) -> void:
	hour += hours
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_passed.emit(day)
	var h := int(hour)
	if h != _last_hour:
		_last_hour = h
		hour_passed.emit(hour, day)


## Skips forward, used by the "wait until evening" verb. Returns hours skipped.
func skip_to(target_hour: float) -> float:
	var delta := target_hour - hour
	if delta <= 0.0:
		delta += 24.0
	advance(delta)
	return delta


func clock_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "Day %d   %02d:%02d" % [day, h, m]


## Rough time-of-day word, used in worker dialogue: "should be done by evening".
func part_of_day(at_hour: float) -> String:
	var h := fposmod(at_hour, 24.0)
	if h < 5.0:
		return "the small hours"
	if h < 9.0:
		return "morning"
	if h < 12.0:
		return "late morning"
	if h < 14.0:
		return "midday"
	if h < 17.0:
		return "the afternoon"
	if h < 20.0:
		return "evening"
	return "tonight"
