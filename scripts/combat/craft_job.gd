extends RefCounted
class_name CraftJob
## A batch of something being made at the armoury.
##
## The same shape as a quarry or a field: hours of work that a worker
## advances on the game clock, and a result that lands in the stores when the
## hours are done. The materials were taken when the job started, so a
## half-finished batch of shot has already eaten its steel — which is also
## why nothing here can be cancelled for a refund.

var item := "shot"
var batches := 1
var total_hours := 1.0
var hours_left := 1.0
var finished := false
var town: Town


func advance(hours: float) -> void:
	if finished:
		return
	hours_left -= hours
	if hours_left <= 0.0:
		hours_left = 0.0
		finished = true
		var made := batches * int(Arsenal.item(item).get("batch", 1))
		if town != null:
			town.stock[item] = town.units_of(item) + made


func made() -> int:
	return batches * int(Arsenal.item(item).get("batch", 1))


func progress() -> float:
	if total_hours <= 0.0:
		return 1.0
	return clampf(1.0 - hours_left / total_hours, 0.0, 1.0)


func summary() -> String:
	return "%d %s" % [made(), Arsenal.label(item)]
