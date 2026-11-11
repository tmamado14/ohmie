extends TestCase
## Tests for LevelCircuit: validation of a level's "circuit" object and the
## conversion to CircuitGraph.


## A valid board: two sockets in parallel between A and B, through junctions.
func _parallel_board() -> Dictionary:
	return {
		"nodes": {
			"A": [0, 100], "j1": [64, 100], "t1": [64, 0], "b1": [64, 200],
			"t2": [320, 0], "b2": [320, 200], "j2": [320, 100], "B": [384, 100],
		},
		"terminals": ["A", "B"],
		"edges": [
			{"id": "w1", "type": "wire", "from": "A", "to": "j1"},
			{"id": "w2", "type": "wire", "from": "j1", "to": "t1"},
			{"id": "w3", "type": "wire", "from": "j1", "to": "b1"},
			{"id": "s1", "type": "socket", "from": "t1", "to": "t2"},
			{"id": "s2", "type": "socket", "from": "b1", "to": "b2"},
			{"id": "w4", "type": "wire", "from": "t2", "to": "j2"},
			{"id": "w5", "type": "wire", "from": "b2", "to": "j2"},
			{"id": "w6", "type": "wire", "from": "j2", "to": "B"},
		],
	}


## A socket in series with a fixed 1/2 ohm resistor.
func _series_fixed_board() -> Dictionary:
	return {
		"nodes": {"A": [0, 0], "n1": [200, 0], "B": [400, 0]},
		"terminals": ["A", "B"],
		"edges": [
			{"id": "s1", "type": "socket", "from": "A", "to": "n1"},
			{"id": "f1", "type": "fixed", "from": "n1", "to": "B", "ohms": "1/2"},
		],
	}


## Parses `data` and checks it is rejected with an error containing `fragment`.
func _assert_rejected(data: Variant, fragment: String, message: String) -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(data, "test")
	assert_null(circuit, message)
	assert_error_pushed(fragment, message)


func test_valid_board_parses_nodes_terminals_and_edges() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	assert_not_null(circuit)
	assert_eq(circuit.terminal_a, "A")
	assert_eq(circuit.terminal_b, "B")
	assert_eq(circuit.get_node_names().size(), 8)
	assert_eq(circuit.get_node_position("t2"), Vector2(320, 0))
	var edges: Array[LevelCircuit.Edge] = circuit.get_edges()
	assert_eq(edges.size(), 8)
	assert_eq(edges[3].id, "s1")
	assert_eq(edges[3].type, LevelCircuit.TYPE_SOCKET)
	assert_eq(edges[3].from_node, "t1")
	assert_eq(edges[3].to_node, "t2")
	assert_eq(circuit.get_node_degree("j1"), 3)
	assert_true(circuit.is_terminal("B"))
	assert_false(circuit.is_terminal("j1"))


func test_socket_descriptors_match_puzzle_solver_format() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	var sockets: Array[Dictionary] = circuit.get_socket_descriptors()
	assert_eq(sockets.size(), 2)
	assert_eq(sockets[0], {"id": "s1", "from": "t1", "to": "t2"})
	assert_eq(sockets[1], {"id": "s2", "from": "b1", "to": "b2"})


func test_base_graph_has_wires_fixed_and_terminals_but_no_sockets() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_series_fixed_board(), "test")
	var graph: CircuitGraph = circuit.build_base_graph()
	assert_eq(graph.get_terminal_a(), "A")
	assert_eq(graph.get_terminal_b(), "B")
	assert_true(graph.has_edge("f1"))
	assert_false(graph.has_edge("s1"))
	assert_rational_eq(graph.get_edge_ohms("f1"), "1/2")


func test_two_parallel_sockets_filled_with_two_and_two_give_one() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	var graph: CircuitGraph = circuit.build_graph({"s1": Rational.new(2), "s2": Rational.new(2)})
	var result: CircuitResult = CircuitSolver.solve(graph)
	assert_eq(result.status, CircuitResult.Status.OK)
	assert_rational_eq(result.value, "1")
	assert_true(result.matches(Rational.new(1)))


func test_two_parallel_sockets_with_one_filled_give_its_value() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	var result: CircuitResult = CircuitSolver.solve(circuit.build_graph({"s2": Rational.new(2)}))
	assert_eq(result.status, CircuitResult.Status.OK)
	assert_rational_eq(result.value, "2")


func test_two_parallel_sockets_empty_are_open() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	assert_eq(CircuitSolver.solve(circuit.build_graph({})).status, CircuitResult.Status.OPEN)
	assert_eq(CircuitSolver.solve(circuit.build_base_graph()).status, CircuitResult.Status.OPEN)


func test_fixed_resistor_counts_in_series() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_series_fixed_board(), "test")
	var result: CircuitResult = CircuitSolver.solve(circuit.build_graph({"s1": Rational.create(1, 2)}))
	assert_eq(result.status, CircuitResult.Status.OK)
	assert_rational_eq(result.value, "1")


func test_build_graph_rejects_unknown_socket_id() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	var graph: CircuitGraph = circuit.build_graph({"nope": Rational.new(2)})
	assert_false(graph.has_edge("nope"))
	assert_error_pushed("'nope' is not a socket")


func test_build_graph_rejects_non_rational_value() -> void:
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(_parallel_board(), "test")
	var graph: CircuitGraph = circuit.build_graph({"s1": "2"})
	assert_false(graph.has_edge("s1"))
	assert_error_pushed("socket 's1' is not a Rational")


func test_rejects_non_object() -> void:
	_assert_rejected([1, 2], "must be an object", "array instead of object")


func test_rejects_missing_section() -> void:
	var data: Dictionary = _parallel_board()
	data.erase("edges")
	_assert_rejected(data, "missing 'edges'", "no edges")


func test_rejects_node_that_is_not_a_point() -> void:
	var data: Dictionary = _parallel_board()
	data["nodes"]["j1"] = [64]
	_assert_rejected(data, "node 'j1' must be two numbers", "one coordinate")
	data["nodes"]["j1"] = ["64", 100]
	_assert_rejected(data, "node 'j1' must be two numbers", "string coordinate")
	data["nodes"] = [[0, 0]]
	_assert_rejected(data, "'nodes' must be an object", "nodes as array")


func test_rejects_wrong_terminal_count() -> void:
	var data: Dictionary = _parallel_board()
	data["terminals"] = ["A"]
	_assert_rejected(data, "array of two node names", "one terminal")


func test_rejects_same_terminal_twice() -> void:
	var data: Dictionary = _parallel_board()
	data["terminals"] = ["A", "A"]
	_assert_rejected(data, "must be different nodes", "A and A")


func test_rejects_terminal_that_is_not_a_node() -> void:
	var data: Dictionary = _parallel_board()
	data["terminals"] = ["A", "Z"]
	_assert_rejected(data, "terminal 'Z' is not a node", "missing terminal node")


func test_rejects_duplicate_edge_id() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][1]["id"] = "w1"
	_assert_rejected(data, "edge id 'w1' is used more than once", "duplicate id")


func test_rejects_edge_without_id() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][0].erase("id")
	_assert_rejected(data, "needs a non-empty string 'id'", "missing id")


func test_rejects_unknown_edge_type() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][0]["type"] = "diode"
	_assert_rejected(data, "unknown type 'diode'", "unknown type")


func test_rejects_unknown_from_node() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][0]["from"] = "nowhere"
	_assert_rejected(data, "unknown node 'nowhere'", "unknown from")


func test_rejects_unknown_to_node() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][0]["to"] = "elsewhere"
	_assert_rejected(data, "unknown node 'elsewhere'", "unknown to")


func test_rejects_edge_from_a_node_to_itself() -> void:
	var data: Dictionary = _parallel_board()
	data["edges"][0]["to"] = "A"
	_assert_rejected(data, "starts and ends at the same node", "self loop")


func test_rejects_fixed_without_ohms() -> void:
	var data: Dictionary = _series_fixed_board()
	data["edges"][1].erase("ohms")
	_assert_rejected(data, "needs 'ohms' as a string", "fixed without ohms")


func test_rejects_fixed_with_unparseable_ohms() -> void:
	var data: Dictionary = _series_fixed_board()
	data["edges"][1]["ohms"] = "two"
	_assert_rejected(data, "invalid 'ohms' value 'two'", "fixed with text ohms")
	assert_error_pushed("Rational.parse", "the parser's own error")


func test_rejects_fixed_with_zero_or_negative_ohms() -> void:
	var data: Dictionary = _series_fixed_board()
	data["edges"][1]["ohms"] = "0"
	_assert_rejected(data, "must have 'ohms' > 0", "zero ohms")
	data["edges"][1]["ohms"] = "-1/2"
	_assert_rejected(data, "must have 'ohms' > 0", "negative ohms")
