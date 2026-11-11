extends SceneTree
## Checks that a level file is valid and solvable, and reports its solutions.
##
## Loads the level (LevelData validates the tiles, parts, circuit and goal),
## runs DcPuzzleSearch over every way of filling the slots with the room's
## parts, and prints each solution (at most MAX_PRINTED), which parts are never
## used (decoys), and layout warnings (edges that are not horizontal or
## vertical, component edges shorter than MIN_COMPONENT_LENGTH).
##
## Usage (exit code 0 = valid and at least one solution):
##   godot --headless --path . --script res://tools/validate_level.gd -- res://levels/<file>.json

const MIN_COMPONENT_LENGTH: float = 128.0
const MAX_PRINTED: int = 40
## Upper bound for the search, far above any World 1 room.
const MAX_SOLUTIONS: int = 100000
const EXIT_OK: int = 0
const EXIT_FAIL: int = 1


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("validate_level: give the level path after --, e.g. -- res://levels/w1_02.json")
		return EXIT_FAIL
	var path: String = args[0]

	var level: LevelData = LevelData.load_from_file(path)
	if level == null:
		print("INVALID  %s: the level could not be loaded (see the error above)" % path)
		return EXIT_FAIL
	var circuit: LevelCircuit = level.circuit
	var goal: LevelGoal = level.make_goal()

	print("Level:      %s \"%s\"" % [level.id, level.title])
	print("Mission:    %s" % level.mission)
	for i: int in goal.condition_count():
		var condition: GoalCondition = goal.conditions[i]
		print("Goal %d:     %s of %s is %s" % [i + 1, condition.quantity_name(), condition.element_id,
				goal.target_text(i)])
	var slots: Array[Dictionary] = circuit.get_slot_descriptors()
	var slot_texts: Array[String] = []
	for slot: Dictionary in slots:
		slot_texts.append("%s (%s -> %s)" % [slot["id"], slot["from"], slot["to"]])
	print("Slots:      %d: %s" % [slots.size(), ", ".join(slot_texts)])
	var search_parts: Array[Dictionary] = []
	var part_texts: Array[String] = []
	for entry: LevelPart in level.parts:
		search_parts.append(entry.part.to_search_dictionary())
		part_texts.append("%s %s %s" % [entry.id, entry.part.kind_name(), entry.part.label()])
	print("Parts:      %d: %s" % [level.parts.size(), ", ".join(part_texts)])

	var warnings: int = _print_layout_warnings(circuit)

	var solutions: Array[Dictionary] = DcPuzzleSearch.find_solutions(
			circuit.build_base_network(), slots, search_parts, goal.conditions, MAX_SOLUTIONS)
	print("Solutions:  %d" % solutions.size())
	for i: int in mini(solutions.size(), MAX_PRINTED):
		print("  %d. %s" % [i + 1, _describe_solution(solutions[i], slots)])
	if solutions.size() > MAX_PRINTED:
		print("  ... and %d more" % (solutions.size() - MAX_PRINTED))

	_print_part_usage(level.parts, solutions)

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


func _describe_solution(solution: Dictionary, slots: Array[Dictionary]) -> String:
	var texts: Array[String] = []
	for slot: Dictionary in slots:
		var id: String = slot["id"]
		texts.append("%s=%s" % [id, solution[id] if solution.has(id) else "empty"])
	return ", ".join(texts)


## One line per distinct part (kind and value): used in some solution, or a decoy.
func _print_part_usage(parts: Array[LevelPart], solutions: Array[Dictionary]) -> void:
	var used: Dictionary = {}
	for solution: Dictionary in solutions:
		for text: Variant in solution.values():
			used[str(text)] = true
	var counts: Dictionary = {}  # label -> count
	var order: Array[String] = []
	var kinds: Dictionary = {}  # label -> kind name
	for entry: LevelPart in parts:
		var text: String = entry.part.label()
		if not counts.has(text):
			order.append(text)
			counts[text] = 0
			kinds[text] = entry.part.kind_name()
		counts[text] = int(counts[text]) + 1
	print("Parts used:")
	for text: String in order:
		var verdict: String = "used in a solution" if used.has(text) else "UNUSED in every solution (decoy)"
		print("  %s %s (x%d): %s" % [kinds[text], text, counts[text], verdict])
