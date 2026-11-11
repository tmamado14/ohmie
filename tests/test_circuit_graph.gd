extends TestCase
## Tests for CircuitGraph.


func test_add_wire_and_resistor() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_true(g.add_wire("w1", "A", "C"))
	assert_true(g.add_resistor("R1", "C", "B", Rational.parse("1/2")))
	assert_eq(g.edge_count(), 2)
	assert_true(g.has_edge("w1"))
	assert_true(g.is_wire("w1"))
	assert_false(g.is_wire("R1"))
	assert_eq(g.get_edge_node_a("R1"), "C")
	assert_eq(g.get_edge_node_b("R1"), "B")
	assert_rational_eq(g.get_edge_ohms("R1"), "1/2")
	assert_null(g.get_edge_ohms("w1"), "wires have no resistance value")


func test_edge_ids_and_nodes_are_sorted() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	g.add_resistor("b", "Z", "Y", Rational.new(1))
	g.add_wire("a", "X", "Y")
	g.add_resistor("c", "W", "X", Rational.new(2))
	var expected_ids: Array[String] = ["a", "b", "c"]
	assert_eq(g.get_edge_ids(), expected_ids)
	var expected_nodes: Array[String] = ["W", "X", "Y", "Z"]
	assert_eq(g.get_nodes(), expected_nodes)


func test_terminals() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.has_terminals())
	assert_eq(g.get_terminal_a(), "")
	assert_true(g.set_terminals("A", "B"))
	assert_true(g.has_terminals())
	assert_eq(g.get_terminal_a(), "A")
	assert_eq(g.get_terminal_b(), "B")


func test_set_terminals_rejects_empty_names() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.set_terminals("", "B"))
	assert_error_pushed("terminal names must not be empty")
	assert_false(g.set_terminals("A", ""))
	assert_error_pushed("terminal names must not be empty")
	assert_false(g.has_terminals())


func test_rejects_non_positive_resistance() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.add_resistor("R0", "A", "B", Rational.new(0)))
	assert_error_pushed("must be > 0")
	assert_false(g.add_resistor("R1", "A", "B", Rational.new(-1, 2)))
	assert_error_pushed("must be > 0")
	assert_eq(g.edge_count(), 0)


func test_rejects_missing_or_invalid_resistance() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.add_resistor("R1", "A", "B", null))
	assert_error_pushed("no valid value")
	var bad: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_false(g.add_resistor("R2", "A", "B", bad))
	assert_error_pushed("no valid value")
	assert_eq(g.edge_count(), 0)


func test_rejects_duplicate_ids() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_true(g.add_wire("e1", "A", "B"))
	assert_false(g.add_wire("e1", "C", "D"))
	assert_error_pushed("duplicate edge id 'e1'")
	assert_false(g.add_resistor("e1", "C", "D", Rational.new(1)))
	assert_error_pushed("duplicate edge id 'e1'")
	assert_eq(g.edge_count(), 1)
	assert_eq(g.get_edge_node_a("e1"), "A", "the original edge is kept")


func test_rejects_empty_names() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.add_wire("", "A", "B"))
	assert_error_pushed("edge id must not be empty")
	assert_false(g.add_wire("w", "", "B"))
	assert_error_pushed("empty node name")
	assert_false(g.add_resistor("R", "A", "", Rational.new(1)))
	assert_error_pushed("empty node name")
	assert_eq(g.edge_count(), 0)


func test_unknown_edge_accessors_report_errors() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	assert_false(g.has_edge("nope"))
	assert_false(g.is_wire("nope"))
	assert_error_pushed("unknown edge id 'nope'")
	assert_eq(g.get_edge_node_a("nope"), "")
	assert_error_pushed("unknown edge id 'nope'")
	assert_eq(g.get_edge_node_b("nope"), "")
	assert_error_pushed("unknown edge id 'nope'")
	assert_null(g.get_edge_ohms("nope"))
	assert_error_pushed("unknown edge id 'nope'")


func test_duplicate_graph_is_independent() -> void:
	var g: CircuitGraph = CircuitGraph.new()
	g.add_resistor("R1", "A", "B", Rational.new(2))
	g.set_terminals("A", "B")
	var copy: CircuitGraph = g.duplicate_graph()
	assert_eq(copy.to_text(), g.to_text())
	copy.add_resistor("R2", "A", "B", Rational.new(2))
	copy.set_terminals("X", "Y")
	assert_eq(g.edge_count(), 1, "adding to the copy does not change the original")
	assert_eq(g.get_terminal_a(), "A")
	assert_eq(copy.edge_count(), 2)


func test_to_text_is_deterministic() -> void:
	var g1: CircuitGraph = CircuitGraph.new()
	g1.add_resistor("R2", "C", "B", Rational.new(3, 2))
	g1.add_wire("w1", "A", "C")
	g1.set_terminals("A", "B")
	var g2: CircuitGraph = CircuitGraph.new()
	g2.set_terminals("A", "B")
	g2.add_wire("w1", "A", "C")
	g2.add_resistor("R2", "C", "B", Rational.new(3, 2))
	assert_eq(g1.to_text(), g2.to_text())
	assert_eq(g1.to_text(), "terminals A B\nresistor R2 C B 3/2\nwire w1 A C")
