extends RefCounted
class_name DetRng
## Deterministic draws for the generator.
##
## build-order.md is explicit: any global RNG anywhere in the generator is a
## bug. Every value here comes from hash(seed, plot_id, step_index, counter), so
## the same spec on the same plot produces byte-identical voxels forever, and a
## bug can be reproduced from a screenshot.
##
## All constants stay under 2^63 because GDScript integers are signed, and the
## state is masked to 63 bits after every step so results never depend on how
## the platform handles overflow.

const MASK := 0x7FFFFFFFFFFFFFFF
const MIX_A := 0x62A9D9ED799705F5
const MIX_B := 0x2545F4914F6CDD1D
const MIX_C := 0x1B03738712FAD5C9

var _state: int = 0


func _init(world_seed: int, plot_id: int, step_index: int) -> void:
	_state = mix(mix(mix(world_seed, 1), plot_id), step_index)


## SplitMix-style finaliser.
static func mix(a: int, b: int = 0) -> int:
	var x := ((a & MASK) + (b & MASK) * MIX_C) & MASK
	x = ((x ^ (x >> 30)) * MIX_A) & MASK
	x = ((x ^ (x >> 27)) * MIX_B) & MASK
	return (x ^ (x >> 31)) & MASK


## Stable hash of a string, used for spec cache keys.
static func hash_text(s: String) -> int:
	var h := 2166136261
	for c in s.to_utf8_buffer():
		h = ((h ^ c) * 16777619) & MASK
	return mix(h)


func next() -> int:
	_state = mix(_state, 1)
	return _state


func randf() -> float:
	return float(next() & 0xFFFFFF) / float(0x1000000)


func randi_range(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + (next() % (hi - lo + 1))


func chance(p: float) -> bool:
	return randf() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[next() % arr.size()]


## Fisher-Yates using only this generator, so shuffles stay reproducible.
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := next() % (i + 1)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
