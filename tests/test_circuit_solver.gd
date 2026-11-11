extends TestCase
## Tests for CircuitSolver, CircuitResult and ReductionStep.

const OK: CircuitResult.Status = CircuitResult.Status.OK
const OPEN: CircuitResult.Status = CircuitResult.Status.OPEN
const UNSUPPORTED: CircuitResult.Status = CircuitResult.Status.UNSUPPORTED
const ERROR: CircuitResult.Status = CircuitResult.Status.ERROR


## Builds a graph with terminals A and B. Each edge is
## [id, node_a, node_b] for a wire or [id, node_a, node_b, "value"] for a resistor.
func _graph(edges: Array) -> CircuitGraph:
	var g: CircuitGraph = CircuitGraph.new()
	g.set_terminals("A", "B")
	for edge: Array in edges:
		if edge.size() == 3:
			g.add_wire(edge[0], edge[1], edge[2])
		else:
			g.add_resistor(edge[0], edge[1], edge[2], Rational.parse(edge[3]))
	return g


func _kinds(result: CircuitResult) -> Array[String]:
	var kinds: Array[String] = []
	for step: ReductionStep in result.steps:
		kinds.append(ReductionStep.Kind.keys()[step.kind])
	return kinds


func _step_texts(result: CircuitResult) -> Array[String]:
	var texts: Array[String] = []
	for step: ReductionStep in result.steps:
		texts.append(step.to_text())
	return texts


func _assert_ok(result: CircuitResult, expected: String, message: String = "") -> void:
	assert_eq(result.status, OK, message + " status")
	assert_rational_eq(result.value, expected, message)


# --- basic networks ----------------------------------------------------------------

func test_single_resistor() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([["R1", "A", "B", "5/2"]]))
	_assert_ok(result, "5/2")
	assert_eq(result.steps.size(), 0)
	assert_eq(result.to_text(), "5/2")


func test_two_in_parallel() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "2"]]))
	_assert_ok(result, "1")
	assert_eq(result.steps.size(), 1)
	var step: ReductionStep = result.steps[0]
	assert_eq(step.kind, ReductionStep.Kind.PARALLEL)
	var expected_ids: Array[String] = ["R1", "R2"]
	assert_eq(step.input_ids, expected_ids)
	assert_rational_eq(step.input_values[0], "2")
	assert_rational_eq(step.input_values[1], "2")
	assert_eq(step.output_id, "m1")
	assert_rational_eq(step.output_value, "1")
	assert_eq(step.node_a, "A")
	assert_eq(step.node_b, "B")
	assert_eq(step.to_text(), "PARALLEL R1=2 R2=2 -> m1=1 (A-B)")


func test_two_in_series() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1/2"], ["R2", "C", "B", "1/2"]]))
	_assert_ok(result, "1")
	assert_eq(result.steps.size(), 1)
	var step: ReductionStep = result.steps[0]
	assert_eq(step.kind, ReductionStep.Kind.SERIES)
	var expected_ids: Array[String] = ["R1", "R2"]
	assert_eq(step.input_ids, expected_ids)
	assert_eq(step.output_id, "m1")
	assert_rational_eq(step.output_value, "1")
	assert_eq(step.node_a, "A")
	assert_eq(step.node_b, "B")


func test_three_threes_in_parallel() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "3"], ["R2", "A", "B", "3"], ["R3", "A", "B", "3"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = [
			"PARALLEL R1=3 R2=3 -> m1=3/2 (A-B)",
			"PARALLEL R3=3 m1=3/2 -> m2=1 (A-B)"]
	assert_eq(_step_texts(result), expected)


func test_two_three_six_in_parallel() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "3"], ["R3", "A", "B", "6"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = ["PARALLEL", "PARALLEL"]
	assert_eq(_kinds(result), expected)


func test_half_plus_parallel_pair_through_wires() -> void:
	# A -w1- C -R1(1/2)- D -w2- E, then E -R2(1)- F -w3- B and E -R3(1)- G -w4- B.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["w1", "A", "C"], ["R1", "C", "D", "1/2"], ["w2", "D", "E"],
			["R2", "E", "F", "1"], ["w3", "F", "B"],
			["R3", "E", "G", "1"], ["w4", "G", "B"]]))
	_assert_ok(result, "1")
	# Wire-merged groups are named by their smallest member: {A,C}=A, {D,E}=D, {B,F,G}=B.
	var expected: Array[String] = [
			"PARALLEL R2=1 R3=1 -> m1=1/2 (D-B)",
			"SERIES R1=1/2 m1=1/2 -> m2=1 (A-B)"]
	assert_eq(_step_texts(result), expected)


func test_series_pair_parallel_with_two() -> void:
	# (1 + 1) || 2
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "C", "B", "1"], ["R3", "A", "B", "2"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = ["SERIES", "PARALLEL"]
	assert_eq(_kinds(result), expected)


func test_nested_parallel_series_parallel() -> void:
	# ((2 || 2) + (2 || 2)) || 2
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "2"], ["R2", "A", "C", "2"],
			["R3", "C", "B", "2"], ["R4", "C", "B", "2"],
			["R5", "A", "B", "2"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = [
			"PARALLEL R1=2 R2=2 -> m1=1 (A-C)",
			"PARALLEL R3=2 R4=2 -> m2=1 (C-B)",
			"SERIES m1=1 m2=1 -> m3=2 (A-B)",
			"PARALLEL R5=2 m3=2 -> m4=1 (A-B)"]
	assert_eq(_step_texts(result), expected)


func test_non_target_values_are_exact() -> void:
	_assert_ok(CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "C", "B", "2"]])), "3", "1 + 2")
	_assert_ok(CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "3"]])), "6/5", "2 || 3")
	_assert_ok(CircuitSolver.solve(_graph([
			["R1", "A", "B", "1/3"], ["R2", "A", "B", "1/7"]])), "1/10", "1/3 || 1/7")


func test_long_chains_stay_exact() -> void:
	var series_edges: Array = []
	for i: int in 10:
		var from_node: String = "A" if i == 0 else "N%d" % i
		var to_node: String = "B" if i == 9 else "N%d" % (i + 1)
		series_edges.append(["R%02d" % i, from_node, to_node, "1/10"])
	_assert_ok(CircuitSolver.solve(_graph(series_edges)), "1", "ten 1/10 in series")
	var parallel_edges: Array = []
	for i: int in 10:
		parallel_edges.append(["R%02d" % i, "A", "B", "10"])
	_assert_ok(CircuitSolver.solve(_graph(parallel_edges)), "1", "ten 10 in parallel")


# --- open, short and missing parts ----------------------------------------------------

func test_series_chain_with_empty_socket_is_open() -> void:
	# The socket between C and D is empty, so it is not in the graph.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "D", "B", "1"]]))
	assert_eq(result.status, OPEN)
	assert_null(result.value)
	assert_eq(result.to_text(), "OPEN")


func test_parallel_with_missing_branch_uses_remaining_branches() -> void:
	# Branch 1: R1. Branch 2: R2, empty socket C-D, R3 (dead). Branch 3: R4.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"],
			["R2", "A", "C", "5"], ["R3", "D", "B", "7"],
			["R4", "A", "B", "2"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = ["PRUNE", "PRUNE", "PARALLEL"]
	assert_eq(_kinds(result), expected)
	assert_eq(result.steps[0].input_ids[0], "R2")
	assert_eq(result.steps[1].input_ids[0], "R3")


func test_dangling_branch_is_pruned() -> void:
	var without: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "2"]]))
	var with_branch: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "2"],
			["R3", "A", "X", "4"], ["R4", "X", "Y", "4"]]))
	_assert_ok(with_branch, "1")
	assert_true(with_branch.value.equals(without.value))
	var expected: Array[String] = [
			"PRUNE R4=4 (X-Y)",
			"PRUNE R3=4 (A-X)",
			"PARALLEL R1=2 R2=2 -> m1=1 (A-B)"]
	assert_eq(_step_texts(with_branch), expected)
	var prune: ReductionStep = with_branch.steps[0]
	assert_eq(prune.output_id, "")
	assert_null(prune.output_value)


func test_self_loop_is_pruned() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "1"], ["R2", "A", "A", "9"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = ["PRUNE R2=9 (A-A)"]
	assert_eq(_step_texts(result), expected)


func test_resistor_shorted_by_wire_is_pruned() -> void:
	# R3 sits across C-D, but a wire also joins C and D, so R3 carries no current.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "D", "B", "1"],
			["R3", "C", "D", "7"], ["w1", "C", "D"]]))
	_assert_ok(result, "2")
	var expected: Array[String] = ["PRUNE", "SERIES"]
	assert_eq(_kinds(result), expected)


func test_terminals_joined_by_wire_is_zero() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([["w1", "A", "B"]]))
	_assert_ok(result, "0")
	assert_eq(result.steps.size(), 0)
	assert_eq(result.to_text(), "0")


func test_wire_across_terminals_with_resistors_elsewhere_is_zero() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "C", "B", "1"], ["R3", "A", "B", "5"],
			["w1", "A", "B"]]))
	_assert_ok(result, "0")


func test_short_through_chain_of_wires_is_zero() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "3"], ["w1", "A", "X"], ["w2", "X", "Y"], ["w3", "Y", "B"]]))
	_assert_ok(result, "0")


func test_no_edges_is_open() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([]))
	assert_eq(result.status, OPEN)
	assert_eq(result.steps.size(), 0)


func test_terminals_unset_is_open() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	g.add_resistor("R1", "A", "B", Rational.new(1))
	var result: CircuitResult = CircuitSolver.solve(g)
	assert_eq(result.status, OPEN)
	assert_eq(result.to_text(), "OPEN")


func test_terminal_without_edges_is_open() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([["R1", "A", "C", "1"]]))
	assert_eq(result.status, OPEN)


func test_terminals_in_separate_parts_is_open() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "C", "A", "1"], ["R3", "B", "D", "1"]]))
	assert_eq(result.status, OPEN)


func test_disconnected_part_is_ignored() -> void:
	# A Wheatstone bridge between P, Q, S, T is not connected to A or B at all.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "1"],
			["X1", "P", "Q", "1"], ["X2", "P", "S", "2"], ["X3", "Q", "T", "3"],
			["X4", "S", "T", "4"], ["X5", "Q", "S", "5"]]))
	_assert_ok(result, "1")
	var expected: Array[String] = ["PRUNE", "PRUNE", "PRUNE", "PRUNE", "PRUNE"]
	assert_eq(_kinds(result), expected)


# --- unsupported and errors ----------------------------------------------------------

func test_wheatstone_bridge_is_unsupported() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "1"], ["R2", "A", "D", "1"],
			["R3", "C", "B", "1"], ["R4", "D", "B", "1"],
			["R5", "C", "D", "1"]]))
	assert_eq(result.status, UNSUPPORTED)
	assert_null(result.value)
	assert_eq(result.to_text(), "???")


func test_known_limitation_k4_hanging_off_one_node_is_unsupported() -> void:
	# A complete graph on A, Q, S, T touches the main circuit only at A, so it
	# carries no current and the true answer is 1. Every node in it has degree
	# 3, so series-parallel reduction cannot remove it.
	# Documented limitation until the Milestone 3 nodal solver.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "1"],
			["X1", "A", "Q", "1"], ["X2", "A", "S", "1"], ["X3", "A", "T", "1"],
			["X4", "Q", "S", "1"], ["X5", "Q", "T", "1"], ["X6", "S", "T", "1"]]))
	assert_eq(result.status, UNSUPPORTED)


func test_bridge_hanging_off_one_node_reduces_away() -> void:
	# A bridge whose far corner T has only two edges is still reducible, so it
	# is removed completely and does not change the answer.
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "1"],
			["X1", "A", "Q", "1"], ["X2", "A", "S", "1"], ["X3", "Q", "T", "1"],
			["X4", "S", "T", "1"], ["X5", "Q", "S", "1"]]))
	_assert_ok(result, "1")


func test_overflow_gives_error_status_not_a_wrong_value() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "C", "9223372036854775807"], ["R2", "C", "B", "1"]]))
	assert_error_pushed("does not fit in 64 bits")
	assert_error_pushed("series merge of 'R1' and 'R2' overflowed")
	assert_eq(result.status, ERROR)
	assert_null(result.value)
	assert_eq(result.to_text(), "ERROR")
	assert_true(result.error_message.contains("overflowed"))
	assert_false(result.matches(Rational.new(1)))


func test_parallel_overflow_gives_error_status() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "1/9223372036854775807"], ["R2", "A", "B", "1/9223372036854775806"]]))
	assert_error_pushed("does not fit in 64 bits")
	assert_error_pushed("parallel merge of 'R1' and 'R2' overflowed")
	assert_eq(result.status, ERROR)


func test_null_graph_is_error() -> void:
	var result: CircuitResult = CircuitSolver.solve(null)
	assert_error_pushed("graph is null")
	assert_eq(result.status, ERROR)


# --- determinism and purity --------------------------------------------------------

func test_same_graph_gives_identical_steps() -> void:
	var g: CircuitGraph = _graph([
			["R1", "A", "C", "2"], ["R2", "A", "C", "2"],
			["R3", "C", "B", "2"], ["R4", "C", "B", "2"],
			["R5", "A", "B", "2"], ["R6", "B", "Z", "3"]])
	var first: CircuitResult = CircuitSolver.solve(g)
	var second: CircuitResult = CircuitSolver.solve(g)
	assert_eq(_step_texts(first), _step_texts(second))
	assert_true(first.steps.size() > 0)


func test_insertion_order_does_not_matter() -> void:
	var edges: Array = [
			["w1", "A", "E"], ["R1", "E", "C", "2"], ["R2", "A", "C", "2"],
			["R3", "C", "B", "2"], ["R4", "C", "B", "2"],
			["R5", "A", "B", "2"], ["R6", "B", "Z", "3"]]
	var forward: CircuitResult = CircuitSolver.solve(_graph(edges))
	var reversed_edges: Array = edges.duplicate()
	reversed_edges.reverse()
	var backward: CircuitResult = CircuitSolver.solve(_graph(reversed_edges))
	_assert_ok(forward, "1")
	_assert_ok(backward, "1")
	assert_eq(_step_texts(forward), _step_texts(backward))


func test_solve_does_not_modify_graph() -> void:
	var g: CircuitGraph = _graph([
			["w1", "A", "C"], ["R1", "C", "D", "1/2"], ["R2", "D", "B", "1"],
			["R3", "D", "B", "1"], ["R4", "D", "X", "1"]])
	var before: String = g.to_text()
	var result: CircuitResult = CircuitSolver.solve(g)
	_assert_ok(result, "1")
	assert_eq(g.to_text(), before)
	assert_eq(g.edge_count(), 5)


func test_generated_ids_skip_existing_ids() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["m1", "A", "B", "2"], ["m2", "A", "B", "2"]]))
	_assert_ok(result, "1")
	assert_eq(result.steps[0].output_id, "m3")


# --- CircuitResult --------------------------------------------------------------------

func test_result_matches_target() -> void:
	var result: CircuitResult = CircuitSolver.solve(_graph([
			["R1", "A", "B", "2"], ["R2", "A", "B", "2"]]))
	assert_true(result.matches(Rational.new(1)))
	assert_true(result.matches(Rational.parse("2/2")))
	assert_false(result.matches(Rational.new(2)))
	assert_false(result.matches(null))
	var open: CircuitResult = CircuitSolver.solve(_graph([]))
	assert_false(open.matches(Rational.new(0)))
