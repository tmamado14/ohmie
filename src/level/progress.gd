class_name Progress
extends RefCounted
## Which rooms the player has completed, and the unlock rules that follow
## from it. Pure logic: the set of completed level files plus rules over a
## CampaignWorld. Saving is ProgressStore's job; when `save_path` is set,
## mark_completed() saves through it at once. With an empty `save_path` the
## progress lives in memory only (tests, tools, rooms loaded without the menus).
##
## Unlock rules (is_unlocked):
## - nothing in a world that is not open (is_world_open), and no room that is
##   not built, is unlocked;
## - a completed room stays unlocked;
## - the first built room of an unlocked world is always unlocked;
## - a regular room is unlocked when the previous built room in play order is
##   completed;
## - every Overtime room unlocks at once: when the world's last regular room
##   (room 10) is completed, or, while that room is not built, when every built
##   regular room is completed.

## The real save file. Only the menus use it (through GameSession).
const DEFAULT_PATH: String = "user://progress.json"

## Where mark_completed() saves; "" keeps the progress in memory only.
var save_path: String = ""

var _completed: Dictionary = {}  # String (level file) -> true


func is_completed(file: String) -> bool:
	return _completed.has(file)


## Records `file` as completed and, when `save_path` is set, saves at once.
func mark_completed(file: String) -> void:
	if file.is_empty():
		return
	_completed[file] = true
	if not save_path.is_empty():
		ProgressStore.save(self, save_path)


## Every completed level file, sorted.
func completed_files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for file: String in _completed.keys():
		files.append(file)
	files.sort()
	return files


## How many of `world`'s rooms are completed.
func completed_count(world: CampaignWorld) -> int:
	var count: int = 0
	for room: CampaignRoom in world.rooms:
		if is_completed(room.file):
			count += 1
	return count


## Whether `room` of `world` may be started (see the rules above).
func is_unlocked(world: CampaignWorld, room: CampaignRoom) -> bool:
	if world == null or room == null or not is_world_open(world) or not room.built:
		return false
	if is_completed(room.file):
		return true
	if room == world.first_built_room():
		return true
	if room.overtime:
		return is_overtime_open(world)
	var previous: CampaignRoom = world.previous_built_room(room)
	return previous != null and is_completed(previous.file)


## Whether `world` may be entered: not hard `locked`, and, when it names an
## `unlock_after` world, that world's Overtime is open (the same rule:
## its room 10 completed).
func is_world_open(world: CampaignWorld) -> bool:
	if world == null or world.locked:
		return false
	return world.unlock_after == null or is_overtime_open(world.unlock_after)


## Whether the Overtime rooms of `world` are open.
func is_overtime_open(world: CampaignWorld) -> bool:
	var last_regular: CampaignRoom = world.last_regular_room()
	if last_regular != null and last_regular.built:
		return is_completed(last_regular.file)
	for room: CampaignRoom in world.regular_rooms():
		if room.built and not is_completed(room.file):
			return false
	return true


## The save file's content: {"completed": [files...]}.
func to_dictionary() -> Dictionary:
	return {"completed": Array(completed_files())}


## Progress from a save file's content. Anything that is not a list of
## strings under "completed" is ignored, so a damaged file gives empty progress.
static func from_dictionary(data: Variant) -> Progress:
	var progress: Progress = Progress.new()
	if data is Dictionary and (data as Dictionary).get("completed") is Array:
		for entry: Variant in (data as Dictionary)["completed"]:
			if entry is String and not (entry as String).is_empty():
				progress._completed[entry as String] = true
	return progress
