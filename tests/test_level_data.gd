extends TestCase
## Tests for LevelData (level file parsing) and LevelPickup (pickup parsing).

const DEV_ROOM: String = "res://levels/dev_room.json"


func _valid_level() -> Dictionary:
	var rows: Array[String] = []
	for y: int in LevelData.ROW_COUNT:
		rows.append("#".repeat(LevelData.COLUMN_COUNT) if y >= 20 else ".".repeat(LevelData.COLUMN_COUNT))
	return {
		"id": "t", "title": "T", "teaches": "testing", "target": "1",
		"tiles": rows, "spawn": [96, 640], "door": [1180, 640],
		"pickups": [{"id": "r1", "ohms": "2", "pos": [200, 640]}],
		"circuit": {"nodes": {}, "terminals": [], "edges": []},
	}


func test_dev_room_loads() -> void:
	var level: LevelData = LevelData.load_from_file(DEV_ROOM)
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.id, "dev_room")
	assert_eq(level.target_text, "1")
	assert_eq(level.tile_rows.size(), LevelData.ROW_COUNT)
	assert_eq(level.spawn, Vector2(96, 640))
	assert_eq(level.door, Vector2(1180, 640))
	assert_eq(level.pickups.size(), 3)
	assert_true(level.circuit.has("edges"))
	assert_not_null(LevelCircuit.from_dictionary(level.circuit, DEV_ROOM), "dev room circuit is valid")


func test_constructed_level_parses() -> void:
	var level: LevelData = LevelData.from_dictionary(_valid_level(), "test")
	assert_not_null(level)


func test_missing_file_is_rejected() -> void:
	assert_null(LevelData.load_from_file("res://levels/does_not_exist.json"))
	assert_error_pushed("file not found")


func test_missing_field_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data.erase("door")
	assert_null(LevelData.from_dictionary(data, "test"))
	assert_error_pushed("missing field 'door'")


func test_wrong_row_count_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	(data["tiles"] as Array).pop_back()
	assert_null(LevelData.from_dictionary(data, "test"))
	assert_error_pushed("expected 23")


func test_unknown_tile_character_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["tiles"][3] = "X" + ".".repeat(LevelData.COLUMN_COUNT - 1)
	assert_null(LevelData.from_dictionary(data, "test"))
	assert_error_pushed("unknown tile character 'X'")


func test_bad_spawn_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["spawn"] = [96]
	assert_null(LevelData.from_dictionary(data, "test"))
	assert_error_pushed("'spawn' must be two numbers")


func test_pickups_parse_to_rationals() -> void:
	var raw: Array[Dictionary] = [
		{"id": "a", "ohms": "0.5", "pos": [10, 20]},
		{"id": "b", "ohms": "3/2", "pos": [30, 40]},
	]
	var pickups: Array[LevelPickup] = []
	assert_true(LevelPickup.parse_all(raw, "test", pickups))
	assert_eq(pickups.size(), 2)
	assert_rational_eq(pickups[0].ohms, "1/2")
	assert_rational_eq(pickups[1].ohms, "3/2")
	assert_eq(pickups[1].position, Vector2(30, 40))


func test_pickup_with_bad_ohms_is_rejected() -> void:
	var raw: Array[Dictionary] = [{"id": "a", "ohms": "0", "pos": [10, 20]}]
	var pickups: Array[LevelPickup] = []
	assert_false(LevelPickup.parse_all(raw, "test", pickups))
	assert_eq(pickups.size(), 0)
	assert_error_pushed("invalid 'ohms' value '0'")


func test_duplicate_pickup_id_is_rejected() -> void:
	var raw: Array[Dictionary] = [
		{"id": "a", "ohms": "1", "pos": [10, 20]},
		{"id": "a", "ohms": "2", "pos": [30, 40]},
	]
	var pickups: Array[LevelPickup] = []
	assert_false(LevelPickup.parse_all(raw, "test", pickups))
	assert_error_pushed("pickup id 'a' is used more than once")
