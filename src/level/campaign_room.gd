class_name CampaignRoom
extends RefCounted
## One room entry of a campaign world: its number in the world, its level
## file, whether it belongs to the Overtime group, and whether its file exists
## ("built"). A room that is not built yet is skipped by every next-room rule
## and can never be started. Pure data.

var number: int = 0
var file: String = ""
var overtime: bool = false
var built: bool = false


static func create(room_number: int, room_file: String, is_overtime: bool, is_built: bool) -> CampaignRoom:
	var room: CampaignRoom = CampaignRoom.new()
	room.number = room_number
	room.file = room_file
	room.overtime = is_overtime
	room.built = is_built
	return room
