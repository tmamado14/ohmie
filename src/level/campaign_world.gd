class_name CampaignWorld
extends RefCounted
## One world of the campaign: its id (the theme name, e.g. "old_workshop"),
## number, display name, topic line, whether it is locked, and its rooms in
## play order (the order the campaign file lists them: regular rooms, then the
## Overtime rooms). A world opens either always, never (`locked`) or once
## another world's Overtime is open (`unlock_after`). Pure data.

var id: String = ""
var number: int = 0
var name: String = ""
var topic: String = ""
## A hard lock: nothing in the world can be played (the planned worlds).
var locked: bool = false
## The world whose Overtime must be open (its room 10 completed) before this
## one opens, or null ("unlock_after" in the campaign file). See
## Progress.is_world_open().
var unlock_after: CampaignWorld = null
var rooms: Array[CampaignRoom] = []


## The room whose level file is `file`, or null.
func find_room(file: String) -> CampaignRoom:
	for room: CampaignRoom in rooms:
		if room.file == file:
			return room
	return null


## The rooms whose files exist, in play order.
func built_rooms() -> Array[CampaignRoom]:
	var result: Array[CampaignRoom] = []
	for room: CampaignRoom in rooms:
		if room.built:
			result.append(room)
	return result


## The regular (non-Overtime) rooms, built or not, in play order.
func regular_rooms() -> Array[CampaignRoom]:
	var result: Array[CampaignRoom] = []
	for room: CampaignRoom in rooms:
		if not room.overtime:
			result.append(room)
	return result


## The Overtime rooms, built or not, in play order.
func overtime_rooms() -> Array[CampaignRoom]:
	var result: Array[CampaignRoom] = []
	for room: CampaignRoom in rooms:
		if room.overtime:
			result.append(room)
	return result


## The last regular room in the list (room 10 in World 1), built or not, or null.
func last_regular_room() -> CampaignRoom:
	var regular: Array[CampaignRoom] = regular_rooms()
	return regular[regular.size() - 1] if not regular.is_empty() else null


## The first built room in play order, or null when none is built.
func first_built_room() -> CampaignRoom:
	for room: CampaignRoom in rooms:
		if room.built:
			return room
	return null


## The built room that comes before `room` in play order, or null.
func previous_built_room(room: CampaignRoom) -> CampaignRoom:
	var index: int = rooms.find(room)
	for i: int in range(index - 1, -1, -1):
		if rooms[i].built:
			return rooms[i]
	return null


## The built room that comes after `room` in play order, or null.
func next_built_room(room: CampaignRoom) -> CampaignRoom:
	var index: int = rooms.find(room)
	if index < 0:
		return null
	for i: int in range(index + 1, rooms.size()):
		if rooms[i].built:
			return rooms[i]
	return null
