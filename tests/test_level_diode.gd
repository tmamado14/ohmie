extends TestCase
## Tests for diodes as carried parts (Part, LevelPart, LevelCircuit), the
## "numbers" flag of a level, prefixed values ("1k") in level files, and
## World 2's unlock rule (Progress.is_world_open).

const DEV_DIODE: String = "res://levels/dev_diode.json"


func _parse_parts(raw: Array, numbers: QuantityText.Style = QuantityText.Style.FRACTION) -> Array[LevelPart]:
	var parts: Array[LevelPart] = []
	LevelPart.parse_all(raw, "test", parts, numbers)
	return parts


## One loop: slot s1 from n1 to n2, then a fixed resistor back.
func _loop_circuit(resistor_value: String) -> LevelCircuit:
	return LevelCircuit.from_dictionary({
		"nodes": {"n1": [0, 0], "n2": [224, 0], "n3": [224, 100], "n4": [0, 100]},
		"edges": [
			{"id": "s1", "type": "slot", "from": "n1", "to": "n2"},
			{"id": "w1", "type": "wire", "from": "n2", "to": "n3"},
			{"id": "r1", "type": "resistor", "from": "n3", "to": "n4", "value": resistor_value},
			{"id": "w2", "type": "wire", "from": "n4", "to": "n1"},
		],
	}, "test")


# --- parts ----------------------------------------------------------------------------

func test_diode_part_parses() -> void:
	var parts: Array[LevelPart] = _parse_parts([
		{"id": "d1", "kind": "diode", "value": "0.7", "pos": [10, 20]},
		{"id": "d2", "kind": "diode", "value": "0.3", "style": "schottky", "pos": [30, 20]},
		{"id": "d3", "kind": "diode", "value": "0", "style": "signal", "pos": [50, 20]},
	])
	assert_eq(parts.size(), 3)
	if parts.size() != 3:
		return
	var d1: Part = parts[0].part
	assert_eq(d1.kind, Part.Kind.DIODE)
	assert_true(d1.is_diode() and d1.is_polarized() and not d1.is_battery())
	assert_rational_eq(d1.value, "7/10")
	assert_eq(d1.diode_style, "rectifier", "the default style")
	assert_eq(parts[1].part.diode_style, "schottky")
	assert_eq(parts[2].part.diode_style, "signal")
	assert_rational_eq(parts[2].part.value, "0", "a diode's drop may be 0")
	assert_false(d1.flipped, "a diode starts not flipped")
	var search: Dictionary = d1.to_search_dictionary()
	assert_eq(search["kind"], "diode")
	assert_rational_eq(search["value"], "7/10")
	assert_eq(search.get("reversible"), true, "a diode is reversible for the puzzle search")
	assert_eq(d1.label(), DcPuzzleSearch.part_text(search), "label() is the validator's solution text")
	assert_eq(d1.label(), "diode 7/10 V")


func test_diode_texts_follow_the_number_style() -> void:
	var fraction: Array[LevelPart] = _parse_parts([{"id": "d1", "kind": "diode", "value": "0.7", "pos": [1, 2]}])
	var engineering: Array[LevelPart] = _parse_parts([
		{"id": "d1", "kind": "diode", "value": "0.7", "pos": [1, 2]},
		{"id": "r1", "kind": "resistor", "value": "1k", "pos": [3, 4]},
	], QuantityText.Style.ENGINEERING)
	assert_eq(fraction[0].part.value_text(), "7/10 V")
	assert_eq(fraction[0].part.tag_text(), "diode 7/10 V →")
	assert_eq(engineering[0].part.value_text(), "0.7 V")
	assert_eq(engineering[0].part.tag_text(), "diode 0.7 V →")
	assert_eq(engineering[1].part.tag_text(), "1 kΩ")
	assert_eq(engineering[1].part.label(), "1000 Ω", "the solution text stays exact")


func test_diode_with_bad_value_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "-0.7", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'value' '-0.7' (must be >= 0)")
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "drop", "pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'value' 'drop'")
	assert_error_pushed("Rational.parse", "the parser's own error")
	assert_eq(parts.size(), 0)


func test_diode_with_bad_style_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "0.7", "style": "zener",
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'style'")
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "0.7", "style": 3,
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("invalid 'style'")
	assert_false(LevelPart.parse_all([{"id": "r", "kind": "resistor", "value": "3", "style": "signal",
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("only a diode may have")


func test_diode_flipped_parses() -> void:
	var parts: Array[LevelPart] = _parse_parts([
		{"id": "d1", "kind": "diode", "value": "0.7", "flipped": true, "pos": [10, 20]},
		{"id": "d2", "kind": "diode", "value": "0.7", "flipped": false, "pos": [30, 20]},
		{"id": "d3", "kind": "diode", "value": "0.3", "style": "schottky", "pos": [50, 20]},
	], QuantityText.Style.ENGINEERING)
	assert_eq(parts.size(), 3)
	if parts.size() != 3:
		return
	assert_true(parts[0].part.flipped, "\"flipped\": true")
	assert_false(parts[1].part.flipped, "\"flipped\": false")
	assert_false(parts[2].part.flipped, "no \"flipped\": not flipped")
	assert_eq(parts[0].part.tag_text(), "diode 0.7 V ←", "a flipped diode's tag points left")
	assert_eq(parts[1].part.tag_text(), "diode 0.7 V →")


func test_diode_flipped_bad_type_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "0.7", "flipped": "yes",
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("needs 'flipped' as true or false")
	assert_false(LevelPart.parse_all([{"id": "d", "kind": "diode", "value": "0.7", "flipped": 1,
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("needs 'flipped' as true or false")
	assert_eq(parts.size(), 0)


func test_flipped_on_a_non_diode_is_rejected() -> void:
	var parts: Array[LevelPart] = []
	assert_false(LevelPart.parse_all([{"id": "r", "kind": "resistor", "value": "3", "flipped": true,
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("has 'flipped', which only a diode may have")
	assert_false(LevelPart.parse_all([{"id": "b", "kind": "battery", "value": "6", "flipped": false,
			"pos": [1, 2]}], "test", parts))
	assert_error_pushed("has 'flipped', which only a diode may have")


func test_only_a_diode_can_be_flipped() -> void:
	var diode: Part = Part.create(Part.Kind.DIODE, Rational.create(7, 10))
	var battery: Part = Part.create(Part.Kind.BATTERY, Rational.new(6))
	var resistor: Part = Part.create(Part.Kind.RESISTOR, Rational.new(3))
	assert_true(diode.is_flippable() and diode.set_flipped(true) and diode.flipped)
	assert_false(battery.is_flippable() or battery.set_flipped(true) or battery.flipped, "a battery cannot flip")
	assert_false(resistor.is_flippable() or resistor.set_flipped(true) or resistor.flipped, "a resistor cannot flip")
	var twin: Part = diode.copy()
	assert_true(twin != diode and twin.flipped and twin.is_diode(), "copy() keeps the direction")
	assert_rational_eq(twin.value, "7/10")
	assert_eq(twin.diode_style, diode.diode_style)
	twin.set_flipped(false)
	assert_true(diode.flipped, "turning the copy leaves the original alone")


func test_only_a_diode_is_reversible_for_the_search() -> void:
	assert_eq(Part.create(Part.Kind.DIODE, Rational.create(7, 10)).to_search_dictionary().get("reversible"), true)
	assert_false(Part.create(Part.Kind.BATTERY, Rational.new(6)).to_search_dictionary().has("reversible"))
	assert_false(Part.create(Part.Kind.RESISTOR, Rational.new(3)).to_search_dictionary().has("reversible"))


func test_prefixed_part_values() -> void:
	var parts: Array[LevelPart] = _parse_parts([
		{"id": "a", "kind": "resistor", "value": "1k", "pos": [1, 2]},
		{"id": "b", "kind": "resistor", "value": "4.7k", "pos": [1, 2]},
		{"id": "c", "kind": "resistor", "value": "3/2", "pos": [1, 2]},
		{"id": "d", "kind": "battery", "value": "0.5", "pos": [1, 2]},
	])
	assert_eq(parts.size(), 4)
	if parts.size() != 4:
		return
	assert_rational_eq(parts[0].part.value, "1000")
	assert_rational_eq(parts[1].part.value, "4700")
	assert_rational_eq(parts[2].part.value, "3/2", "plain strings give the same value as before")
	assert_rational_eq(parts[3].part.value, "1/2")


# --- circuit --------------------------------------------------------------------------

## Two slots in parallel between nL (screen-left, x 0) and nR (screen-right,
## x 224): s_lr runs from nL to nR, s_rl from nR to nL.
func _two_way_circuit() -> LevelCircuit:
	return LevelCircuit.from_dictionary({
		"nodes": {"nL": [0, 0], "nR": [224, 0], "mL": [0, 100], "mR": [224, 100]},
		"edges": [
			{"id": "s_lr", "type": "slot", "from": "nL", "to": "nR"},
			{"id": "w1", "type": "wire", "from": "nR", "to": "mR"},
			{"id": "s_rl", "type": "slot", "from": "mR", "to": "mL"},
			{"id": "w2", "type": "wire", "from": "mL", "to": "nL"},
		],
	}, "test")


func test_build_network_puts_the_diode_anode_where_the_picture_shows_it() -> void:
	var circuit: LevelCircuit = _two_way_circuit()
	assert_not_null(circuit)
	if circuit == null:
		return
	# slot id -> [anode when not flipped, anode when flipped]
	var expected: Dictionary = {"s_lr": ["nL", "nR"], "s_rl": ["mL", "mR"]}
	for slot: String in expected:
		for flip_index: int in 2:
			var diode: Part = Part.create(Part.Kind.DIODE, Rational.create(7, 10))
			diode.set_flipped(flip_index == 1)
			var network: DcNetwork = circuit.build_network({slot: diode})
			var anode: String = (expected[slot] as Array)[flip_index]
			var cathode: String = (expected[slot] as Array)[1 - flip_index]
			var what: String = "%s %s" % [slot, "flipped" if diode.flipped else "not flipped"]
			assert_eq(network.get_kind(slot), DcNetwork.Kind.DIODE, what)
			assert_eq(network.get_node_a(slot), anode, what + ": the anode")
			assert_eq(network.get_node_b(slot), cathode, what + ": the cathode")
			assert_eq(circuit.diode_anode_node(circuit.get_edge(slot), diode.flipped), anode, what)


func test_build_network_keeps_a_battery_plus_at_from() -> void:
	var circuit: LevelCircuit = _two_way_circuit()
	assert_not_null(circuit)
	if circuit == null:
		return
	var battery: Part = Part.create(Part.Kind.BATTERY, Rational.new(6))
	var network: DcNetwork = circuit.build_network({"s_rl": battery})
	assert_eq(network.get_kind("s_rl"), DcNetwork.Kind.VOLTAGE_SOURCE)
	assert_eq(network.get_node_a("s_rl"), "mR", "a battery's plus stays at the slot's from node")
	assert_eq(network.get_node_b("s_rl"), "mL")


func test_prefixed_element_values() -> void:
	var circuit: LevelCircuit = _loop_circuit("2.2k")
	assert_not_null(circuit)
	if circuit == null:
		return
	assert_rational_eq(circuit.get_edge("r1").value, "2200")
	var level: LevelData = LevelData.load_from_file(DEV_DIODE)
	assert_not_null(level)
	if level == null:
		return
	var lamp: LevelCircuit.Edge = level.circuit.get_edge("lamp1")
	assert_rational_eq(lamp.value, "1000")
	assert_rational_eq(lamp.rated_min, "3/1000")
	assert_rational_eq(lamp.rated_max, "3/500")


# --- the numbers flag -----------------------------------------------------------------

func test_engineering_flag_reaches_every_condition() -> void:
	var level: LevelData = LevelData.load_from_file(DEV_DIODE)
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.number_style, QuantityText.Style.ENGINEERING)
	var goal: LevelGoal = level.make_goal()
	assert_eq(goal.number_style, QuantityText.Style.ENGINEERING)
	for condition: GoalCondition in goal.conditions:
		assert_eq(condition.style, QuantityText.Style.ENGINEERING)
	assert_eq(goal.target_text(0), "5–6 mA")
	for entry: LevelPart in level.parts:
		assert_eq(entry.part.number_style, QuantityText.Style.ENGINEERING, entry.id)


func test_rooms_without_the_flag_keep_fractions() -> void:
	var level: LevelData = LevelData.load_from_file("res://levels/w1_05.json")
	assert_not_null(level)
	if level == null:
		return
	assert_eq(level.number_style, QuantityText.Style.FRACTION)
	for condition: GoalCondition in level.make_goal().conditions:
		assert_eq(condition.style, QuantityText.Style.FRACTION)


func test_bad_numbers_flag_is_rejected() -> void:
	var text: String = FileAccess.get_file_as_string(DEV_DIODE)
	var data: Dictionary = JSON.parse_string(text)
	data["numbers"] = "scientific"
	assert_null(LevelData.from_dictionary(data, "test"))
	assert_error_pushed("field 'numbers' must be one of")


# --- World 2 unlock -------------------------------------------------------------------

func test_world_two_opens_with_world_one_room_ten() -> void:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	assert_not_null(campaign)
	if campaign == null:
		return
	var one: CampaignWorld = campaign.get_world("old_workshop")
	var two: CampaignWorld = campaign.get_world("copper_foundry")
	var progress: Progress = Progress.new()
	assert_true(progress.is_world_open(one))
	assert_false(progress.is_world_open(two), "fresh progress: World 2 is closed")
	for i: int in 9:
		progress.mark_completed(one.rooms[i].file)
	assert_false(progress.is_world_open(two), "rooms 1 to 9 are not enough")
	progress.mark_completed(one.last_regular_room().file)
	assert_true(progress.is_world_open(two), "room 10 completed: World 2 opens")
	assert_false(progress.is_world_open(campaign.get_world("substation_switchyard")), "World 3 stays locked")


func test_unlock_after_must_name_another_world() -> void:
	var data: Dictionary = {"worlds": [
		{"id": "a", "name": "A", "rooms": []},
		{"id": "b", "name": "B", "unlock_after": "nowhere", "rooms": []},
	]}
	assert_null(Campaign.from_dictionary(data, "test"))
	assert_error_pushed("naming no other world")
