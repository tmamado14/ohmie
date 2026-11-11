extends SceneTree
## Checks that a level file is valid and solvable, and reports its solutions.
##
## Loads the level, its circuit and its pickups, runs PuzzleSolver over every
## way of filling the sockets, and prints each solution, which resistor values
## are never used (decoys), and layout warnings (edges that are not horizontal
## or vertical, socket or fixed edges shorter than MIN_COMPONENT_LENGTH).
##
## Usage (exit code 0 = valid and at least one solution):
##   godot --headless --path . --script res://tools/validate_level.gd -- res://levels/<file>.json

const MIN_COMPONENT_LENGTH: float = 128.0
const EXIT_OK: int = 0
const EXIT_FAIL: int = 1


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("validate_level: give the level path after --, e.g. -- res://levels/slice_01.json")
		return EXIT_FAIL
	var path: String = args[0]

	var level: LevelData = LevelData.load_from_file(path)
	if level == null:
		print("INVALID  %s: level data could not be loaded (see error above)" % path)
		return EXIT_FAIL
	var circuit: LevelCircuit = LevelCircuit.from_dictionary(level.circuit, path)
	if circuit == null:
		print("INVALID  %s: circuit is invalid (see error above)" % path)
		return EXIT_FAIL
	var pickups: Array[LevelPickup] = []
	if not LevelPickup.parse_all(level.pickups, path, pickups):
		print("INVALID  %s: pickups are invalid (see error above)" % path)
		return EXIT_FAIL
	var goal: LevelGoal = level.goal
	var target: Rational = goal.equivalent_resistance_target()
	if target == null:
		print("INVALID  %s: goal type '%s' has no equivalent resistance to validate" % [path, goal.type])
		return EXIT_FAIL

	var sockets: Array[Dictionary] = circuit.get_socket_descriptors()
	var values: Array[Rational] = []
	var value_texts: Array[String] = []
	for pickup: LevelPickup in pickups:
		values.append(pickup.ohms)
		value_texts.append(pickup.ohms.to_text())

	print("Level:      %s \"%s\"" % [level.id, level.title])
	if goal.type == LevelGoal.TYPE_CURRENT:
		print("Goal:       %s, voltage %s V, value %s A (equivalent resistance %s ohm)" % [
				goal.type, goal.voltage.to_text(), goal.current.to_text(), target.to_text()])
	else:
		print("Goal:       %s, value %s ohm" % [goal.type, target.to_text()])
	print("Mission:    %s" % goal.mission)
	var socket_ids: Array[String] = []
	for socket: Dictionary in sockets:
		socket_ids.append("%s (%s-%s)" % [socket["id"], socket["from"], socket["to"]])
	print("Sockets:    %d: %s" % [sockets.size(), ", ".join(socket_ids)])
	print("Resistors:  %d: %s" % [values.size(), ", ".join(value_texts)])

	var warnings: int = _print_layout_warnings(circuit)

	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(
			circuit.build_base_graph(), sockets, values, target)
	print("Solutions:  %d" % solutions.size())
	for i: int in solutions.size():
		print("  %d. %s" % [i + 1, _describe_solution(solutions[i], sockets)])

	_print_value_usage(value_texts, solutions)

	if solutions.is_empty():
		print("UNSOLVABLE  %s" % path)
		return EXIT_FAIL
	print("OK  %s: %d solution(s), %d warning(s)" % [path, solutions.size(), warnings])
	return EXIT_OK


## Prints one WARNING line per layout problem and returns how many there were.
func _print_layout_warnings(circuit: LevelCircuit) -> int:
	var count: int = 0
	for edge: LevelCircuit.Edge in circuit.get_edges():
		var a: Vector2 = circuit.get_node_position(edge.from_node)
		var b: Vector2 = circuit.get_node_position(edge.to_node)
		if a.x != b.x and a.y != b.y:
			print("WARNING: edge '%s' (%s %s to %s %s) is neither horizontal nor vertical" % [
					edge.id, edge.from_node, a, edge.to_node, b])
			count += 1
		if edge.type != LevelCircuit.TYPE_WIRE and a.distance_to(b) < MIN_COMPONENT_LENGTH:
			print("WARNING: %s edge '%s' is %.0f px long; its nodes must be at least %.0f px apart" % [
					edge.type, edge.id, a.distance_to(b), MIN_COMPONENT_LENGTH])
			count += 1
	return count


func _describe_solution(solution: Dictionary, sockets: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for socket: Dictionary in sockets:
		var id: String = socket["id"]
		parts.append("%s=%s" % [id, solution[id] if solution.has(id) else "empty"])
	return ", ".join(parts)


func _print_value_usage(value_texts: Array[String], solutions: Array[Dictionary]) -> void:
	var used: Dictionary = {}
	for solution: Dictionary in solutions:
		for value: Variant in solution.values():
			used[str(value)] = true
	var listed: Dictionary = {}
	print("Resistor values:")
	for text: String in value_texts:
		if listed.has(text):
			continue
		listed[text] = true
		var count: int = value_texts.count(text)
		if used.has(text):
			print("  %s ohm (x%d): used in a solution" % [text, count])
		else:
			print("  %s ohm (x%d): UNUSED in every solution (decoy)" % [text, count])
