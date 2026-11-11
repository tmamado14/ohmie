extends TestCase
## Tests for LevelGoal: a mission plus a list of GoalConditions, met when the
## solve is OK and every condition holds; display helpers delegate to
## GoalCondition.


## A loop of a battery `volts` and resistor `ohms` with an ammeter am1 and a
## voltmeter vm1 across the resistor.
func _loop(volts: int, ohms: int) -> DcSolution:
	var network: DcNetwork = DcNetwork.new()
	network.add_voltage_source("b1", "p", "n", Rational.new(volts))
	network.add_ammeter("am1", "p", "x")
	network.add_resistor("r1", "x", "n", Rational.new(ohms))
	network.add_voltmeter("vm1", "x", "n")
	return DcSolver.solve(network)


func _short() -> DcSolution:
	var network: DcNetwork = DcNetwork.new()
	network.add_voltage_source("b1", "p", "n", Rational.new(6))
	network.add_ammeter("am1", "p", "n")
	network.add_voltmeter("vm1", "p", "n")
	return DcSolver.solve(network)


func _goal(conditions: Array[Dictionary]) -> LevelGoal:
	var parsed: Array[GoalCondition] = []
	for data: Dictionary in conditions:
		parsed.append(GoalCondition.from_dictionary(data))
	return LevelGoal.create("Draw 2 A.", parsed)


func test_create_keeps_mission_and_conditions() -> void:
	var goal: LevelGoal = _goal([{"of": "am1", "quantity": "current", "equals": "2"}])
	assert_eq(goal.mission, "Draw 2 A.")
	assert_eq(goal.condition_count(), 1)
	assert_eq(goal.conditions[0].element_id, "am1")


func test_single_condition_is_met_exactly() -> void:
	var goal: LevelGoal = _goal([{"of": "am1", "quantity": "current", "equals": "2"}])
	assert_true(goal.is_met(_loop(6, 3)), "6 V / 3 ohm = 2 A")
	assert_false(goal.is_met(_loop(6, 2)), "3 A is not 2 A")
	assert_false(goal.is_met(null), "no solution")


func test_all_conditions_must_hold() -> void:
	var goal: LevelGoal = _goal([
		{"of": "am1", "quantity": "current", "equals": "2"},
		{"of": "vm1", "quantity": "voltage", "min": "5", "max": "6"},
	])
	assert_true(goal.is_met(_loop(6, 3)), "2 A and 6 V")
	assert_false(goal.is_met(_loop(4, 2)), "2 A but only 4 V")
	assert_true(goal.is_condition_met(0, _loop(4, 2)), "the current condition alone holds")
	assert_false(goal.is_condition_met(1, _loop(4, 2)), "the voltage condition alone fails")


func test_short_never_meets_the_goal() -> void:
	var short: DcSolution = _short()
	assert_eq(short.status, DcSolution.Status.SHORT)
	var goal: LevelGoal = _goal([{"of": "am1", "quantity": "current", "min": "0"}])
	assert_false(goal.is_met(short))


func test_ohmmeter_match_during_a_short_does_not_meet_the_goal() -> void:
	var network: DcNetwork = DcNetwork.new()
	network.add_voltage_source("b1", "p", "n", Rational.new(6))
	network.add_wire("w1", "p", "n")
	network.add_resistor("r1", "x", "y", Rational.new(1))
	network.add_ohmmeter("om1", "x", "y")
	var solution: DcSolution = DcSolver.solve(network)
	assert_eq(solution.status, DcSolution.Status.SHORT)
	var goal: LevelGoal = _goal([{"of": "om1", "quantity": "resistance", "equals": "1"}])
	assert_true(goal.is_condition_met(0, solution), "the ohmmeter alone reads 1")
	assert_false(goal.is_met(solution), "but a short keeps the door shut")


func test_empty_goal_is_never_met() -> void:
	var empty: Array[GoalCondition] = []
	assert_false(LevelGoal.create("Nothing.", empty).is_met(_loop(6, 3)))


func test_display_helpers_delegate_to_the_condition() -> void:
	var goal: LevelGoal = _goal([
		{"of": "am1", "quantity": "current", "equals": "2"},
		{"of": "vm1", "quantity": "voltage", "min": "1", "max": "3/2"},
	])
	var solution: DcSolution = _loop(6, 4)
	assert_eq(goal.target_text(0), "2 A")
	assert_eq(goal.target_text(1), "1–3/2 V")
	assert_eq(goal.reading_text(0, solution), "3/2 A")
	assert_eq(goal.reading_text(1, solution), "6 V")
	assert_eq(goal.reading_text(0, _short()), "SHORT")
	assert_eq(goal.reading_text(0, solution), goal.conditions[0].reading_text(solution))


func test_quantity_symbols() -> void:
	assert_eq(LevelGoal.quantity_symbol(GoalCondition.Quantity.CURRENT), "I")
	assert_eq(LevelGoal.quantity_symbol(GoalCondition.Quantity.VOLTAGE), "V")
	assert_eq(LevelGoal.quantity_symbol(GoalCondition.Quantity.RESISTANCE), "R")
	assert_eq(LevelGoal.quantity_symbol(GoalCondition.Quantity.POWER), "P")
	var goal: LevelGoal = _goal([{"of": "om1", "quantity": "resistance", "equals": "1"}])
	assert_eq(goal.symbol(0), "R")
