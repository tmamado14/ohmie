extends TestCase
## Tests for LevelData (level file parsing, GDD 12.4), LevelPart (the "parts"
## list) and Part.

const DEV_ROOM: String = "res://levels/dev_room.json"
const LEVEL_FILES: Array[String] = [
	"res://levels/dev_room.json", "res://levels/w1_02.json", "res://levels/w1_07.json",
]


## A minimal valid level: a slot and an ammeter in one loop, goal 2 A.
func _valid_level() -> Dictionary:
	var rows: Array[String] = []
	for y: int in LevelData.ROW_COUNT:
		rows.append("#".repeat(LevelData.COLUMN_COUNT) if y >= 20 else ".".repeat(LevelData.COLUMN_COUNT))
	return {
		"id": "t", "title": "T", "mission": "Draw 2 A.",
		"goal": [{"of": "am1", "quantity": "current", "equals": "2"}],
		"tiles": rows, "spawn": [96, 640], "door": [1180, 640],
		"parts": [
			{"id": "b1", "kind": "battery", "value": "6", "pos": [200, 640]},
			{"id": "r1", "kind": "resistor", "value": "3", "pos": [300, 640]},
		],
		"circuit": {
			"nodes": {"n1": [0, 0], "n2": [224, 0], "n3": [448, 0], "n4": [448, 100], "n5": [0, 100]},
			"edges": [
				{"id": "s1", "type": "slot", "from": "n1", "to": "n2"},
				{"id": "s2", "type": "slot", "from": "n2", "to": "n3"},
				{"id": "w1", "type": "wire", "from": "n3", "to": "n4"},
				{"id": "am1", "type": "ammeter", "from": "n4", "to": "n5"},
				{"id": "w2", "type": "wire", "from": "n5", "to": "n1"},
			],
		},
	}


func _assert_rejected(data: Dictionary, fragment: String, message: String) -> void:
	assert_null(LevelData.from_dictionary(data, "test"), message)
	assert_error_pushed(fragment, message)


func test_every_level_file_loads() -> void:
	for path: String in LEVEL_FILES:
		var level: LevelData = LevelData.load_from_file(path)
		assert_not_null(level, path)


func test_dev_room_loads() -> void:
	var level: LevelData = LevelData.load_from_file(DEV_ROOM)
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.id, "dev_room")
	assert_eq(level.mission, "Make 1 Ω.")
	assert_eq(level.goal.size(), 1)
	assert_eq(level.goal[0].element_id, "om1")
	assert_eq(level.goal[0].quantity, GoalCondition.Quantity.RESISTANCE)
	assert_rational_eq(level.goal[0].equals, "1")
	assert_eq(level.tile_rows.size(), LevelData.ROW_COUNT)
	assert_eq(level.spawn, Vector2(96, 640))
	assert_eq(level.door, Vector2(1180, 640))
	assert_eq(level.parts.size(), 3)
	assert_eq(level.world, LevelData.DEFAULT_WORLD, "world defaults to old_workshop")
	assert_not_null(level.circuit)
	assert_eq(level.make_goal().mission, "Make 1 Ω.")


func test_constructed_level_parses() -> void:
	var level: LevelData = LevelData.from_dictionary(_valid_level(), "test")
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.parts[0].id, "b1")
	assert_true(level.parts[0].part.is_battery())
	assert_rational_eq(level.parts[1].part.value, "3")
	assert_eq(level.parts[1].position, Vector2(300, 640))
	assert_eq(level.teaches, "", "teaches is optional")
	assert_eq(level.circuit.get_slot_descriptors().size(), 2)


func test_optional_fields_parse() -> void:
	var data: Dictionary = _valid_level()
	data["teaches"] = "I = V / R"
	data["world"] = "copper_foundry"
	var level: LevelData = LevelData.from_dictionary(data, "test")
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.teaches, "I = V / R")
	assert_eq(level.world, "copper_foundry")


func test_missing_file_is_rejected() -> void:
	assert_null(LevelData.load_from_file("res://levels/does_not_exist.json"))
	assert_error_pushed("file not found")


func test_missing_field_is_rejected() -> void:
	for field: String in LevelData.REQUIRED_FIELDS:
		var data: Dictionary = _valid_level()
		data.erase(field)
		_assert_rejected(data, "missing field '%s'" % field, "without " + field)


func test_old_format_fields_are_rejected() -> void:
	for field: String in ["pickups", "target", "terminals"]:
		var data: Dictionary = _valid_level()
		data[field] = []
		_assert_rejected(data, "unknown field '%s'" % field, "old field " + field)


func test_empty_mission_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["mission"] = "  "
	_assert_rejected(data, "'mission' must be a non-empty string", "blank mission")
	data["mission"] = 3
	_assert_rejected(data, "'mission' must be a non-empty string", "number mission")


func test_goal_must_be_a_non_empty_array() -> void:
	var data: Dictionary = _valid_level()
	data["goal"] = []
	_assert_rejected(data, "'goal' must be a non-empty array", "empty goal")
	data["goal"] = {"of": "am1", "quantity": "current", "equals": "2"}
	_assert_rejected(data, "'goal' must be a non-empty array", "goal object")
	data["goal"] = ["am1"]
	_assert_rejected(data, "goal[0] must be an object", "goal of strings")


func test_invalid_goal_condition_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["goal"] = [{"of": "am1", "quantity": "speed", "equals": "2"}]
	_assert_rejected(data, "goal[0] is invalid", "unknown quantity")
	assert_error_pushed("unknown quantity 'speed'")


func test_goal_naming_unknown_element_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["goal"] = [{"of": "vm9", "quantity": "voltage", "equals": "2"}]
	_assert_rejected(data, "'vm9', which is not an edge", "unknown element")


func test_goal_quantity_must_fit_the_element() -> void:
	var data: Dictionary = _valid_level()
	data["goal"] = [{"of": "am1", "quantity": "resistance", "equals": "2"}]
	_assert_rejected(data, "a resistance goal cannot be measured on ammeter 'am1'", "resistance on an ammeter")


func test_wrong_row_count_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	(data["tiles"] as Array).pop_back()
	_assert_rejected(data, "expected 23", "22 rows")


func test_unknown_tile_character_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["tiles"][3] = "X" + ".".repeat(LevelData.COLUMN_COUNT - 1)
	_assert_rejected(data, "unknown tile character 'X'", "X tile")


func test_bad_spawn_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["spawn"] = [96]
	_assert_rejected(data, "'spawn' must be two numbers", "one coordinate")


func test_invalid_circuit_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["circuit"]["edges"][0]["type"] = "socket"
	_assert_rejected(data, "unknown type 'socket'", "old socket type")


func test_invalid_part_is_rejected() -> void:
	var data: Dictionary = _valid_level()
	data["parts"][0]["kind"] = "capacitor"
	_assert_rejected(data, "needs 'kind' \"resistor\" or \"battery\"", "unknown kind")


# --- LevelPart ------------------------------------------------------------------------

func test_parts_parse_to_parts() -> void:
	var raw: Array = [
		{"id": "a", "kind": "resistor", "value": "0.5", "pos": [10, 20]},
		{"id": "b", "kind": "battery", "value": "9", "pos": [30, 40]},
	]
	var parts: Array[LevelPart] = []
	assert_true(LevelPart.parse_all(raw, "test", parts))
	assert_eq(parts.size(), 2)
	if parts.size() != 2:
		return
	assert_eq(parts[0].part.kind, Part.Kind.RESISTOR)
	assert_rational_eq(parts[0].part.value, "1/2")
	assert_eq(parts[0].part.label(), "1/2 Ω")
	assert_eq(parts[1].part.kind, Part.Kind.BATTERY)
	assert_eq(parts[1].part.label(), "9 V")
	assert_eq(parts[1].position, Vector2(30, 40))


func test_part_with_bad_value_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "a", "kind": "resistor", "value": "0", "pos": [1, 2]}], "test", parts))
	assert_eq(parts.size(), 0)
	assert_error_pushed("invalid 'value' '0'")
	assert_false(LevelPart.parse_all([{"id": "a", "kind": "battery", "value": "-6", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'value' '-6'")
	assert_false(LevelPart.parse_all([{"id": "a", "kind": "battery", "value": 6, "pos": [1, 2]}], "test", parts))
	assert_error_pushed("needs 'value' as a string")
	assert_false(LevelPart.parse_all([{"id": "a", "kind": "battery", "value": "six", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'value' 'six'")
	assert_error_pushed("Rational.parse", "the parser's own error")


func test_part_with_bad_kind_or_pos_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "a", "value": "2", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("part 'a' needs 'kind'")
	assert_false(LevelPart.parse_all([{"id": "a", "kind": "resistor", "value": "2", "pos": [1]}], "test", parts))
	assert_error_pushed("part 'a' needs 'pos' as two numbers")
	assert_false(LevelPart.parse_all([{"kind": "resistor", "value": "2", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("parts[0] needs a non-empty string 'id'")
	assert_false(LevelPart.parse_all([{"id": "a", "ohms": "2", "kind": "resistor", "value": "2", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("unknown field 'ohms'")
	assert_false(LevelPart.parse_all({"a": 1}, "test", parts))
	assert_error_pushed("'parts' must be an array")


func test_duplicate_part_id_is_rejected() -> void:
	var raw: Array = [
		{"id": "a", "kind": "resistor", "value": "1", "pos": [10, 20]},
		{"id": "a", "kind": "resistor", "value": "2", "pos": [30, 40]},
	]
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all(raw, "test", parts))
	assert_error_pushed("part id 'a' is used more than once")


# --- Part -----------------------------------------------------------------------------

func test_part_labels_and_search_form() -> void:
	var resistor: Part = Part.create(Part.Kind.RESISTOR, Rational.new(3))
	var battery: Part = Part.create(Part.Kind.BATTERY, Rational.new(6))
	assert_eq(resistor.label(), "3 Ω")
	assert_eq(battery.label(), "6 V")
	assert_false(resistor.is_battery())
	assert_true(battery.is_battery())
	var search: Dictionary = battery.to_search_dictionary()
	assert_eq(search["kind"], "battery")
	assert_rational_eq(search["value"] as Rational, "6")
	assert_eq(resistor.to_search_dictionary()["kind"], "resistor")
	assert_eq(Part.kind_from_name("battery"), Part.Kind.BATTERY)
	assert_eq(Part.kind_from_name("socket"), -1)


func test_part_needs_a_positive_value() -> void:
	assert_null(Part.create(Part.Kind.RESISTOR, Rational.new(0)))
	assert_error_pushed("needs a value > 0")
	assert_null(Part.create(Part.Kind.BATTERY, null))
	assert_error_pushed("needs a value > 0")
