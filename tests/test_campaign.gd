extends TestCase
## Tests for Campaign: worlds and rooms, built and unbuilt rooms, the next
## built room, the first built room, the Overtime flag and locked worlds.
## Synthetic campaigns decide which files "exist" through a Callable, so the
## results do not depend on which level files are present; the real
## res://levels/campaign.json is checked for its shape only.

const A: String = "res://levels/test_a.json"
const B: String = "res://levels/test_b.json"
const C: String = "res://levels/test_c.json"
const D: String = "res://levels/test_d.json"
const E: String = "res://levels/test_e.json"
const OT1: String = "res://levels/test_ot1.json"
const OT2: String = "res://levels/test_ot2.json"
const LOCKED_ROOM: String = "res://levels/test_locked.json"


## World "one": rooms 1-5 (A..E) plus Overtime 6, 7; world "two" is locked.
func _data() -> Dictionary:
	return {"worlds": [
		{"id": "one", "number": 1, "name": "One", "topic": "DC basics", "locked": false, "rooms": [
			{"number": 1, "file": A}, {"number": 2, "file": B}, {"number": 3, "file": C},
			{"number": 4, "file": D}, {"number": 5, "file": E},
			{"number": 6, "file": OT1, "overtime": true}, {"number": 7, "file": OT2, "overtime": true}]},
		{"id": "two", "number": 2, "name": "Two", "topic": "Coming soon", "locked": true, "rooms": [
			{"number": 1, "file": LOCKED_ROOM}]},
	]}


func _campaign(built: Array[String]) -> Campaign:
	return Campaign.from_dictionary(_data(), "test", func(path: String) -> bool: return built.has(path))


func test_worlds_and_rooms_are_read_in_order() -> void:
	var campaign: Campaign = _campaign([A, B])
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.worlds.size(), 2)
	var one: CampaignWorld = campaign.worlds[0]
	assert_eq(one.id, "one")
	assert_eq(one.number, 1)
	assert_eq(one.name, "One")
	assert_eq(one.topic, "DC basics")
	assert_false(one.locked)
	assert_eq(one.rooms.size(), 7)
	assert_eq(one.rooms[2].number, 3)
	assert_eq(one.rooms[2].file, C)
	assert_true(campaign.worlds[1].locked, "world two is locked")


func test_overtime_flag() -> void:
	var one: CampaignWorld = _campaign([]).worlds[0]
	assert_false(one.rooms[4].overtime)
	assert_true(one.rooms[5].overtime)
	assert_true(one.rooms[6].overtime)
	assert_eq(one.regular_rooms().size(), 5)
	assert_eq(one.overtime_rooms().size(), 2)
	assert_eq(one.last_regular_room().file, E)


func test_built_flag_follows_file_existence() -> void:
	var campaign: Campaign = _campaign([B, D])
	assert_false(campaign.is_built(A))
	assert_true(campaign.is_built(B))
	assert_false(campaign.is_built(C))
	assert_true(campaign.is_built(D))
	assert_false(campaign.is_built("res://levels/not_listed.json"))
	assert_eq(campaign.worlds[0].built_rooms().size(), 2)


func test_first_built_room_skips_unbuilt_rooms() -> void:
	assert_eq(_campaign([B, D]).first_built_room(), B)
	assert_eq(_campaign([A, B]).first_built_room(), A)
	assert_eq(_campaign([OT2]).first_built_room(), OT2)


func test_first_built_room_skips_locked_worlds() -> void:
	assert_eq(_campaign([LOCKED_ROOM]).first_built_room(), "")
	assert_eq(_campaign([LOCKED_ROOM, C]).first_built_room(), C)


func test_next_built_after_skips_unbuilt_rooms() -> void:
	var campaign: Campaign = _campaign([B, D, OT1])
	assert_eq(campaign.next_built_after(B), D)
	assert_eq(campaign.next_built_after(D), OT1, "after the last built regular room comes Overtime")
	assert_eq(campaign.next_built_after(OT1), "", "the last built room has no next")


func test_next_built_after_unknown_or_unbuilt_room() -> void:
	var campaign: Campaign = _campaign([B, D])
	assert_eq(campaign.next_built_after("res://levels/dev_room.json"), "")
	assert_eq(campaign.next_built_after(""), "")
	assert_eq(campaign.next_built_after(C), D, "from an unbuilt room the next built room still follows")


func test_next_built_stays_in_its_world() -> void:
	var campaign: Campaign = _campaign([E, LOCKED_ROOM])
	assert_eq(campaign.next_built_after(E), "")


func test_world_lookup() -> void:
	var campaign: Campaign = _campaign([])
	assert_eq(campaign.get_world("two").name, "Two")
	assert_null(campaign.get_world("nope"))
	assert_eq(campaign.world_of(C).id, "one")
	assert_eq(campaign.world_of(LOCKED_ROOM).id, "two")
	assert_null(campaign.world_of("res://levels/nowhere.json"))
	assert_eq(campaign.find_room(OT1).number, 6)


func test_previous_built_room() -> void:
	var one: CampaignWorld = _campaign([A, C, OT1]).worlds[0]
	assert_eq(one.previous_built_room(one.find_room(C)).file, A)
	assert_eq(one.previous_built_room(one.find_room(B)).file, A)
	assert_null(one.previous_built_room(one.find_room(A)))
	assert_eq(one.previous_built_room(one.find_room(OT1)).file, C)


func test_invalid_campaign_is_rejected() -> void:
	assert_null(Campaign.from_dictionary({"levels": [A]}, "old format"))
	assert_error_pushed("needs a 'worlds' array")
	assert_null(Campaign.from_dictionary({"worlds": [{"id": "x", "name": "X", "rooms": [{"number": 1}]}]}, "no file"))
	assert_error_pushed("needs a 'file'")


func test_empty_campaign_has_no_first() -> void:
	assert_eq(Campaign.new().first_built_room(), "")
	assert_eq(Campaign.new().next_built_after(A), "")


# --- the real campaign file -----------------------------------------------------------

func test_real_campaign_lists_five_worlds() -> void:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.worlds.size(), 5)
	var names: Array[String] = []
	for world: CampaignWorld in campaign.worlds:
		names.append(world.name)
	assert_eq(names, ["Old Workshop", "Copper Foundry", "Substation Switchyard", "Signal Clocktower",
			"High-Voltage Transmitter"] as Array[String])
	assert_false(campaign.worlds[0].locked, "World 1 is open")
	var two: CampaignWorld = campaign.worlds[1]
	assert_false(two.locked, "World 2 is not hard-locked")
	assert_true(two.unlock_after == campaign.worlds[0], "World 2 opens after World 1")
	assert_eq(two.topic, "Basic electronics")
	assert_eq(two.rooms.size(), 1)
	assert_eq(two.rooms[0].file, "res://levels/w2_01.json")
	for i: int in range(2, 5):
		assert_true(campaign.worlds[i].locked, "world %d is locked" % (i + 1))
		assert_eq(campaign.worlds[i].topic, "Coming soon")


func test_real_campaign_world_one_has_thirteen_rooms() -> void:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	if campaign == null:
		fail("campaign loads")
		return
	var one: CampaignWorld = campaign.get_world("old_workshop")
	assert_not_null(one)
	if one == null:
		return
	assert_eq(one.rooms.size(), 13)
	for i: int in one.rooms.size():
		var room: CampaignRoom = one.rooms[i]
		assert_eq(room.number, i + 1)
		assert_eq(room.file, "res://levels/w1_%02d.json" % (i + 1))
		assert_eq(room.overtime, i >= 10, "room %d overtime flag" % room.number)


func test_real_campaign_built_rooms_load() -> void:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	if campaign == null:
		fail("campaign loads")
		return
	var first: String = campaign.first_built_room()
	assert_ne(first, "", "at least one room is built")
	for room: CampaignRoom in campaign.get_world("old_workshop").built_rooms():
		assert_not_null(LevelData.load_from_file(room.file), room.file)
