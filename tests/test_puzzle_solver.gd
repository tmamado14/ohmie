extends TestCase
## Tests for PuzzleSolver.


func _values(texts: Array[String]) -> Array[Rational]:
	var values: Array[Rational] = []
	for text: String in texts:
		values.append(Rational.parse(text))
	return values


func _socket(id: String, from_node: String, to_node: String) -> Dictionary:
	return {"id": id, "from": from_node, "to": to_node}


func _base() -> CircuitGraph:
	var g: CircuitGraph = CircuitGraph.new()
	g.set_terminals("A", "B")
	return g


## Board: S1 from A to C, then S2 and S3 in parallel from C to B.
func _series_then_parallel_sockets() -> Array[Dictionary]:
	var sockets: Array[Dictionary] = [
			_socket("S1", "A", "C"), _socket("S2", "C", "B"), _socket("S3", "C", "B")]
	return sockets


func _three_parallel_sockets() -> Array[Dictionary]:
	var sockets: Array[Dictionary] = [
			_socket("S1", "A", "B"), _socket("S2", "A", "B"), _socket("S3", "A", "B")]
	return sockets


func _contains(solutions: Array[Dictionary], expected: Dictionary) -> bool:
	for solution: Dictionary in solutions:
		if solution == expected:
			return true
	return false


func test_series_then_parallel_has_exactly_one_solution() -> void:
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			_series_then_parallel_sockets(), _values(["1/2", "1", "1", "2"]), Rational.new(1))
	assert_eq(solutions.size(), 1)
	assert_eq(solutions[0], {"S1": "1/2", "S2": "1", "S3": "1"})


func test_three_parallel_sockets_families() -> void:
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			_three_parallel_sockets(), _values(["2", "2", "3", "6"]), Rational.new(1))
	# Solutions are told apart by which value sits in which socket; which of the
	# two equal 2-ohm resistors is used does not matter.
	# Family {2, 2, one socket empty}: the empty socket can be S1, S2 or S3 -> 3.
	# Family {2, 3, 6}: every arrangement of three distinct values in three
	# sockets -> 3! = 6.
	# No other subset of [2, 2, 3, 6] in parallel gives 1, so 3 + 6 = 9.
	assert_eq(solutions.size(), 9)
	assert_true(_contains(solutions, {"S1": "2", "S2": "2"}))
	assert_true(_contains(solutions, {"S1": "2", "S3": "2"}))
	assert_true(_contains(solutions, {"S2": "2", "S3": "2"}))
	assert_true(_contains(solutions, {"S1": "2", "S2": "3", "S3": "6"}))
	assert_true(_contains(solutions, {"S1": "6", "S2": "3", "S3": "2"}))
	assert_true(_contains(solutions, {"S1": "3", "S2": "6", "S3": "2"}))
	# No duplicates.
	for i: int in solutions.size():
		for j: int in range(i + 1, solutions.size()):
			assert_ne(solutions[i], solutions[j], "solutions %d and %d differ" % [i, j])


func test_no_solution_returns_empty() -> void:
	var sockets: Array[Dictionary] = [_socket("S1", "A", "C"), _socket("S2", "C", "B")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			sockets, _values(["5", "7"]), Rational.new(1))
	assert_eq(solutions.size(), 0)


func test_equal_resistors_give_one_solution() -> void:
	var sockets: Array[Dictionary] = [_socket("S1", "A", "B")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			sockets, _values(["1", "1", "1"]), Rational.new(1))
	assert_eq(solutions.size(), 1)
	assert_eq(solutions[0], {"S1": "1"})


func test_fixed_resistors_and_wires_in_base() -> void:
	# Fixed 1/2 from A to C, a wire from C to D, then one socket from D to B.
	var base: CircuitGraph = _base()
	base.add_resistor("F1", "A", "C", Rational.parse("1/2"))
	base.add_wire("w1", "C", "D")
	var sockets: Array[Dictionary] = [_socket("S1", "D", "B")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(base,
			sockets, _values(["1", "0.5", "2"]), Rational.new(1))
	assert_eq(solutions.size(), 1)
	assert_eq(solutions[0], {"S1": "1/2"}, "decimal input is reported as an exact fraction")


func test_base_already_at_target_gives_all_empty_solution() -> void:
	var base: CircuitGraph = _base()
	base.add_resistor("F1", "A", "B", Rational.new(1))
	var sockets: Array[Dictionary] = [_socket("S1", "A", "C")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(base,
			sockets, _values(["3"]), Rational.new(1))
	# Empty, and S1 = 3 (a dead-end branch that changes nothing).
	assert_eq(solutions.size(), 2)
	assert_eq(solutions[0], {})
	assert_eq(solutions[1], {"S1": "3"})


func test_no_resistors_and_no_sockets() -> void:
	var no_sockets: Array[Dictionary] = []
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			no_sockets, _values([]), Rational.new(1))
	assert_eq(solutions.size(), 0, "an empty board is OPEN, never 1")
	var short_base: CircuitGraph = _base()
	short_base.add_wire("w1", "A", "B")
	var zero_solutions: Array[Dictionary] = PuzzleSolver.find_solutions(short_base,
			no_sockets, _values([]), Rational.new(0))
	assert_eq(zero_solutions.size(), 1, "a shorted board hits a 0 target")


func test_solutions_are_in_a_fixed_order() -> void:
	var first: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			_three_parallel_sockets(), _values(["2", "2", "3", "6"]), Rational.new(1))
	var second: Array[Dictionary] = PuzzleSolver.find_solutions(_base(),
			_three_parallel_sockets(), _values(["2", "2", "3", "6"]), Rational.new(1))
	assert_eq(first, second)
	assert_eq(first[0], {"S2": "2", "S3": "2"}, "S1 empty is tried first")


func test_does_not_modify_base() -> void:
	var base: CircuitGraph = _base()
	base.add_resistor("F1", "A", "C", Rational.parse("1/2"))
	var before: String = base.to_text()
	var sockets: Array[Dictionary] = [_socket("S1", "C", "B")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(base, sockets,
			_values(["1/2"]), Rational.new(1))
	assert_eq(solutions.size(), 1)
	assert_eq(base.to_text(), before)


func test_unsupported_assignments_are_not_solutions() -> void:
	# A bridge board: whatever goes in S5 makes the network non series-parallel.
	var base: CircuitGraph = _base()
	base.add_resistor("F1", "A", "C", Rational.new(1))
	base.add_resistor("F2", "A", "D", Rational.new(1))
	base.add_resistor("F3", "C", "B", Rational.new(1))
	base.add_resistor("F4", "D", "B", Rational.new(1))
	var sockets: Array[Dictionary] = [_socket("S5", "C", "D")]
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(base,
			sockets, _values(["5"]), Rational.new(1))
	# Empty S5 gives (1+1) || (1+1) = 1. Filled S5 is a balanced bridge: also 1
	# physically, but UNSUPPORTED in Milestone 1, so it is not listed.
	assert_eq(solutions.size(), 1)
	assert_eq(solutions[0], {})


# --- invalid input ---------------------------------------------------------------------

func test_null_base_or_target_is_rejected() -> void:
	var sockets: Array[Dictionary] = [_socket("S1", "A", "B")]
	assert_eq(PuzzleSolver.find_solutions(null, sockets, _values(["1"]), Rational.new(1)).size(), 0)
	assert_error_pushed("base graph is null")
	assert_eq(PuzzleSolver.find_solutions(_base(), sockets, _values(["1"]), null).size(), 0)
	assert_error_pushed("target is null")


func test_bad_socket_is_rejected() -> void:
	var missing_key: Array[Dictionary] = [{"id": "S1", "from": "A"}]
	assert_eq(PuzzleSolver.find_solutions(_base(), missing_key, _values(["1"]), Rational.new(1)).size(), 0)
	assert_error_pushed("needs a non-empty String 'to'")
	var wrong_type: Array[Dictionary] = [{"id": 5, "from": "A", "to": "B"}]
	assert_eq(PuzzleSolver.find_solutions(_base(), wrong_type, _values(["1"]), Rational.new(1)).size(), 0)
	assert_error_pushed("needs a non-empty String 'id'")
	var duplicate: Array[Dictionary] = [_socket("S1", "A", "B"), _socket("S1", "A", "B")]
	assert_eq(PuzzleSolver.find_solutions(_base(), duplicate, _values(["1"]), Rational.new(1)).size(), 0)
	assert_error_pushed("socket id 'S1' is not unique")


func test_socket_id_clashing_with_base_edge_is_rejected() -> void:
	var base: CircuitGraph = _base()
	base.add_resistor("S1", "A", "B", Rational.new(1))
	var sockets: Array[Dictionary] = [_socket("S1", "A", "B")]
	assert_eq(PuzzleSolver.find_solutions(base, sockets, _values(["1"]), Rational.new(1)).size(), 0)
	assert_error_pushed("socket id 'S1' is not unique")


func test_bad_resistor_is_rejected() -> void:
	var sockets: Array[Dictionary] = [_socket("S1", "A", "B")]
	assert_eq(PuzzleSolver.find_solutions(_base(), sockets, _values(["1", "0"]), Rational.new(1)).size(), 0)
	assert_error_pushed("resistor 1 must be a valid value > 0")
	var with_null: Array[Rational] = [Rational.new(1), null]
	assert_eq(PuzzleSolver.find_solutions(_base(), sockets, with_null, Rational.new(1)).size(), 0)
	assert_error_pushed("resistor 1 must be a valid value > 0")
