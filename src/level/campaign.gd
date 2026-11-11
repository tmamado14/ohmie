class_name Campaign
extends RefCounted
## The worlds of the game and their rooms, read from a JSON file such as
##   { "worlds": [ { "id": "old_workshop", "number": 1, "name": "Old Workshop",
##       "topic": "DC basics", "locked": false,
##       "rooms": [ { "number": 1, "file": "res://levels/w1_01.json" }, ...,
##                  { "number": 11, "file": "res://levels/w1_11.json", "overtime": true } ] },
##     { "id": "copper_foundry", "number": 2, ..., "locked": true, "rooms": [] } ] }
##
## Rooms are kept in the order the file lists them (the play order). A room
## whose level file does not exist is "not built yet": it is listed, but
## first_built_room() and next_built_after() skip it. Whether a file exists is
## asked once, at load, through a Callable (FileAccess.file_exists by default)
## so tests can describe any mix of built and unbuilt rooms. Pure data: no nodes.

const DEFAULT_PATH: String = "res://levels/campaign.json"

var worlds: Array[CampaignWorld] = []


## Loads a campaign file. Returns null and pushes an error when it is missing or invalid.
static func load_from_file(path: String = DEFAULT_PATH) -> Campaign:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Campaign: could not read '%s'" % path)
		return null
	return from_dictionary(JSON.parse_string(text), path)


## Builds a campaign from parsed JSON. `file_exists` takes a path and returns
## whether that level file exists; when it is not valid, FileAccess.file_exists is used.
static func from_dictionary(data: Variant, source: String, file_exists: Callable = Callable()) -> Campaign:
	if not data is Dictionary or not (data as Dictionary).get("worlds") is Array:
		push_error("Campaign: '%s' needs a 'worlds' array" % source)
		return null
	var exists: Callable = file_exists
	if not exists.is_valid():
		exists = func(path: String) -> bool: return FileAccess.file_exists(path)
	var campaign: Campaign = Campaign.new()
	for world_data: Variant in (data as Dictionary)["worlds"]:
		var world: CampaignWorld = _parse_world(world_data, source, exists)
		if world == null:
			return null
		campaign.worlds.append(world)
	return campaign


## The world with id `world_id`, or null.
func get_world(world_id: String) -> CampaignWorld:
	for world: CampaignWorld in worlds:
		if world.id == world_id:
			return world
	return null


## The world that lists the level file `file`, or null.
func world_of(file: String) -> CampaignWorld:
	for world: CampaignWorld in worlds:
		if world.find_room(file) != null:
			return world
	return null


## The room entry of the level file `file` in any world, or null.
func find_room(file: String) -> CampaignRoom:
	var world: CampaignWorld = world_of(file)
	return world.find_room(file) if world != null else null


## True when `file` is listed in the campaign and exists.
func is_built(file: String) -> bool:
	var room: CampaignRoom = find_room(file)
	return room != null and room.built


## The first built room of the first unlocked world that has one, or "".
func first_built_room() -> String:
	for world: CampaignWorld in worlds:
		if world.locked:
			continue
		var room: CampaignRoom = world.first_built_room()
		if room != null:
			return room.file
	return ""


## The built room after `path` in the same world, or "" when `path` is the
## world's last built room or is not in the campaign.
func next_built_after(path: String) -> String:
	var world: CampaignWorld = world_of(path)
	if world == null:
		return ""
	var next: CampaignRoom = world.next_built_room(world.find_room(path))
	return next.file if next != null else ""


static func _parse_world(value: Variant, source: String, exists: Callable) -> CampaignWorld:
	if not value is Dictionary:
		push_error("Campaign: '%s': every world must be an object" % source)
		return null
	var data: Dictionary = value
	if not data.get("id") is String or not data.get("name") is String or not data.get("rooms") is Array:
		push_error("Campaign: '%s': a world needs 'id', 'name' and 'rooms'" % source)
		return null
	var world: CampaignWorld = CampaignWorld.new()
	world.id = data["id"]
	world.name = data["name"]
	world.number = int(data.get("number", 0))
	world.topic = str(data.get("topic", ""))
	world.locked = bool(data.get("locked", false))
	for room_value: Variant in data["rooms"]:
		if not room_value is Dictionary or not (room_value as Dictionary).get("file") is String:
			push_error("Campaign: '%s': every room of '%s' needs a 'file'" % [source, world.id])
			return null
		var room_data: Dictionary = room_value
		var file: String = room_data["file"]
		world.rooms.append(CampaignRoom.create(int(room_data.get("number", world.rooms.size() + 1)), file,
				bool(room_data.get("overtime", false)), bool(exists.call(file))))
	return world
