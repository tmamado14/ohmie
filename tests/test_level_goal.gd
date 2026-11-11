extends TestCase
## Tests for LevelGoal: parsing from the "goal" object or the legacy "target"
## field, matching a CircuitResult, and the readout labels.

const MISSION: String = "Make exactly 1 Ω between A and B to unlock the door."


func _resistance_goal(value: String, mission: String = "") -> Dictionary:
	var goal: Dictionary = {"type": "resistance", "value": value}
	if not mission.is_empty():
		goal["mission"] = mission
	return {"goal": goal}


## The equivalent resistance between A and B of the given resistors in series.
func _series(values: Array[Rational]) -> CircuitResult:
	var graph: CircuitGraph = CircuitGraph.new()
	for i: int in values.size():
		var from_node: String = "A" if i == 0 else "n%d" % i
		var to_node: String = "B" if i == values.size() - 1 else "n%d" % (i + 1)
		graph.add_resistor("r%d" % i, from_node, to_node, values[i])
	graph.set_terminals("A", "B")
	return CircuitSolver.solve(graph)


func _open_result() -> CircuitResult:
	var graph: CircuitGraph = CircuitGraph.new()
	graph.add_resistor("r1", "A", "x", Rational.new(1))
	graph.set_terminals("A", "B")
	return CircuitSolver.solve(graph)


func test_goal_object_parses() -> void:
	var goal: LevelGoal = LevelGoal.from_level(_resistance_goal("1", MISSION), "test")
	assert_not_null(goal)
	if goal == null:
		return
	assert_eq(goal.type, LevelGoal.TYPE_RESISTANCE)
	assert_rational_eq(goal.target, "1")
	assert_eq(goal.mission, MISSION)


func test_legacy_target_parses() -> void:
	var goal: LevelGoal = LevelGoal.from_level({"target": "3/2"}, "test")
	assert_not_null(goal)
	if goal == null:
		return
	assert_eq(goal.type, LevelGoal.TYPE_RESISTANCE)
	assert_rational_eq(goal.target, "3/2")
	assert_eq(goal.mission, "Make exactly 3/2 Ω between A and B.")


func test_goal_wins_over_target() -> void:
	var data: Dictionary = _resistance_goal("2")
	data["target"] = "1"
	var goal: LevelGoal = LevelGoal.from_level(data, "test")
	assert_not_null(goal)
	if goal == null:
		return
	assert_rational_eq(goal.target, "2")


func test_neither_goal_nor_target_is_rejected() -> void:
	assert_null(LevelGoal.from_level({}, "test"))
	assert_error_pushed("needs a 'goal' object or a 'target' field")


func test_unsupported_type_is_rejected() -> void:
	var data: Dictionary = {"goal": {"type": "led_current", "value": "1"}}
	assert_null(LevelGoal.from_level(data, "test"))
	assert_error_pushed("goal type 'led_current' is not supported yet")


func test_zero_value_is_rejected() -> void:
	assert_null(LevelGoal.from_level(_resistance_goal("0"), "test"))
	assert_error_pushed("resistance value '0' must be an exact number > 0")


func test_negative_value_is_rejected() -> void:
	assert_null(LevelGoal.from_level(_resistance_goal("-1/2"), "test"))
	assert_error_pushed("resistance value '-1/2' must be an exact number > 0")


func test_unparseable_value_is_rejected() -> void:
	assert_null(LevelGoal.from_level(_resistance_goal("one"), "test"))
	assert_error_pushed("'one' is not a number")
	assert_error_pushed("resistance value 'one' must be an exact number > 0")


func test_missing_value_is_rejected() -> void:
	assert_null(LevelGoal.from_level({"goal": {"type": "resistance"}}, "test"))
	assert_error_pushed("resistance goal needs a string 'value'")


func test_unparseable_legacy_target_is_rejected() -> void:
	assert_null(LevelGoal.from_level({"target": "0"}, "test"))
	assert_error_pushed("resistance value '0' must be an exact number > 0")


func test_default_mission_text() -> void:
	var goal: LevelGoal = LevelGoal.from_level(_resistance_goal("1"), "test")
	assert_not_null(goal)
	if goal == null:
		return
	assert_eq(goal.mission, "Make exactly 1 Ω between A and B.")


func test_is_met_only_for_exact_match() -> void:
	var goal: LevelGoal = LevelGoal.from_level(_resistance_goal("1"), "test")
	assert_not_null(goal)
	if goal == null:
		return
	var one: CircuitResult = _series([Rational.new(1)])
	var three_halves: CircuitResult = _series([Rational.new(1, 2), Rational.new(1)])
	var open: CircuitResult = _open_result()
	assert_eq(open.status, CircuitResult.Status.OPEN)
	assert_true(goal.is_met(one), "1 meets a 1 Ω goal")
	assert_false(goal.is_met(three_halves), "3/2 does not meet a 1 Ω goal")
	assert_false(goal.is_met(open), "OPEN does not meet a 1 Ω goal")
	assert_false(goal.is_met(null), "no result does not meet the goal")


func test_non_one_goal_met_by_series() -> void:
	var goal: LevelGoal = LevelGoal.from_level(_resistance_goal("3/2"), "test")
	assert_not_null(goal)
	if goal == null:
		return
	var result: CircuitResult = _series([Rational.new(1, 2), Rational.new(1)])
	assert_eq(result.status, CircuitResult.Status.OK)
	assert_true(goal.is_met(result), "1/2 + 1 meets a 3/2 Ω goal")
	assert_false(goal.is_met(_series([Rational.new(1)])), "1 does not meet a 3/2 Ω goal")


func test_goal_label() -> void:
	assert_eq(LevelGoal.from_level(_resistance_goal("1"), "test").goal_label(), "1 Ω")
	assert_eq(LevelGoal.from_level(_resistance_goal("1.5"), "test").goal_label(), "3/2 Ω")


func test_reading_label() -> void:
	var goal: LevelGoal = LevelGoal.from_level(_resistance_goal("1"), "test")
	assert_eq(goal.reading_label(_series([Rational.new(1, 2), Rational.new(1)])), "3/2 Ω")
	assert_eq(goal.reading_label(_series([Rational.new(1)])), "1 Ω")
	assert_eq(goal.reading_label(_open_result()), "OPEN")
	var unsupported: CircuitResult = CircuitResult.new()
	unsupported.status = CircuitResult.Status.UNSUPPORTED
	assert_eq(goal.reading_label(unsupported), "???")
	var error: CircuitResult = CircuitResult.new()
	error.status = CircuitResult.Status.ERROR
	assert_eq(goal.reading_label(error), "ERROR")
	assert_eq(goal.reading_label(null), "?")


func test_level_data_exposes_goal() -> void:
	var level: LevelData = LevelData.load_from_file("res://levels/slice_01.json")
	assert_not_null(level)
	if level == null:
		return
	assert_not_null(level.goal)
	assert_eq(level.goal.mission, MISSION)
	assert_rational_eq(level.goal.target, "1")
	assert_eq(level.target_text, "1", "target_text still reports the goal value")
