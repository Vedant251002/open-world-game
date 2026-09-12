extends RefCounted
class_name SaveGame
## The town, written down.
##
## Until this existed every session started from nothing: the roles you had
## defined, what the crew had learned about you, the pen behind the tavern —
## all of it went with the window. For a game whose whole idea is people who
## remember what you told them, that was the one thing it could not afford.
##
## What is saved is small, because the world is not: the world comes from a
## seed, and only what was changed on top of it is kept — the same stash of
## modified chunks that lets a building survive being walked away from. Every
## building's record, every person's memory and role, the fields, the animals,
## the clock and where you were standing. Not the plans in flight: a worker
## who was halfway through an order comes back idle, holding the memory of
## being given it, which is what a person would do after a night's sleep.
##
## One slot. store_var into a zstd stream: it takes Vector3i, Rect2i and
## PackedByteArray as they are, so nothing here converts anything by hand,
## and a save with five buildings is a few hundred kilobytes.

const VERSION := 1
## A var, not a const, so a test can point it at a scratch file and never
## read or overwrite the player's town.
static var path := "user://save/town.save"

## Off for every test and bench run, so a harness never reads a real save or
## leaves one behind.
static var enabled := true


static func exists() -> bool:
	return enabled and FileAccess.file_exists(path)


static func write(state: Dictionary) -> bool:
	if not enabled:
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://save"))
	state["version"] = VERSION
	state["written"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[save] could not open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_var(state)
	f.close()
	return true


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v: Variant = f.get_var()
	f.close()
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	if int(d.get("version", 0)) != VERSION:
		push_warning("[save] version %s is not %d; starting fresh" % [str(d.get("version")), VERSION])
		return {}
	return d


static func erase() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Everything about a finished building the register needs, without its
## voxels — those are in the world's own stash. Enough to stand the record up
## again, put the furniture back, and let "go to the bakery" find the door.
static func patch_to_dict(p: VoxelPatch) -> Dictionary:
	return {
		"origin": p.origin, "size": p.size, "footprint": p.footprint,
		"front": p.front, "doors": p.doors.duplicate(), "plot_id": p.plot_id,
		"archetype": p.archetype, "cost": p.cost.duplicate(),
		"sign_text": p.sign_text, "props": p.props.duplicate(true),
		"modules": p.modules.duplicate(true),
		"interior_cells": p.interior_cells.duplicate(),
		"entrance_cell": p.entrance_cell, "touched": p.touched,
	}


## A patch shell: the record of a building, not a thing that can be laid. Its
## data is one byte, deliberately; nothing downstream of the register reads
## voxels from a patch, and a full box per building would be megabytes.
static func patch_from_dict(d: Dictionary) -> VoxelPatch:
	var p := VoxelPatch.new(d.get("origin", Vector3i.ZERO), Vector3i.ONE)
	p.size = d.get("size", Vector3i.ONE)
	p.footprint = d.get("footprint", Rect2i())
	p.front = d.get("front", Vector3i(0, 0, -1))
	for door: Variant in d.get("doors", []):
		p.doors.append(door)
	p.plot_id = int(d.get("plot_id", -1))
	p.archetype = str(d.get("archetype", ""))
	p.cost = d.get("cost", {})
	p.sign_text = str(d.get("sign_text", ""))
	for pr: Variant in d.get("props", []):
		p.props.append(pr)
	for m: Variant in d.get("modules", []):
		p.modules.append(m)
	for c: Variant in d.get("interior_cells", []):
		p.interior_cells.append(c)
	p.entrance_cell = d.get("entrance_cell", Rect2i())
	p.touched = int(d.get("touched", 0))
	return p
