extends SceneTree
## Exhaustive state check of World 1 rooms 1-10 (QA).
##
## For every room, every assignment of the room's parts to its slots (each
## slot empty or holding a distinct part) is generated.
##
## 1. Pure solver, every assignment: no assignment may be INDETERMINATE or
##    ERROR (GDD 3, "Rooms are designed so this cannot happen"). Assignments
##    that give SHORT are listed (allowed, but they must read SHORT and keep
##    the door shut, which part 2 checks).
## 2. In the running room, up to MAX_PER_ROOM assignments (sampled evenly when
##    there are more, always including every SHORT and every solving one) are
##    put into the slots through the board API (CircuitSocket.insert /
##    take_out). Every solving, INDETERMINATE and ERROR assignment is always
##    included; SHORT ones and the rest share the remaining places evenly. After each one, against an independent DcSolver.solve of the
##    same assignment:
##      - the door is open, the board reports goal met and the mission sign
##        shows done exactly when LevelGoal.is_met;
##      - the plaque rows show the captions, readings (GoalCondition.reading_text)
##        and targets the goal gives, each row green exactly when its condition
##        holds, and each row's text fits its column at the chosen font size;
##      - every meter shows MeterText.reading and its text fits the window;
##      - every lamp is ON / OFF / BLOWN by its rating, from |current|;
##      - a SHORT shows SHORT on every ammeter / voltmeter and on the plaque
##        (current and voltage rows) and the wires show the short state;
##      - nothing logs an ERROR or WARNING.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_world_states.gd


## Counts engine errors and warnings (push_error, push_warning, script errors).
class ErrorCounter extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _lines: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		_lines.append("type %d: %s %s (%s:%d %s)" % [error_type, code, rationale, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n: int = _lines.size()
		_mutex.unlock()
		return n

	func lines_since(start: int) -> PackedStringArray:
		_mutex.lock()
		var out: PackedStringArray = _lines.slice(start)
		_mutex.unlock()
		return out


const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROOM_PATH: NodePath = ^"Room"
const ROOMS: PackedStringArray = [
	"res://levels/w1_01.json", "res://levels/w1_02.json", "res://levels/w1_03.json",
	"res://levels/w1_04.json", "res://levels/w1_05.json", "res://levels/w1_06.json",
	"res://levels/w1_07.json", "res://levels/w1_08.json", "res://levels/w1_09.json",
	"res://levels/w1_10.json",
]
const MAX_PER_ROOM: int = 400
const SETTLE_FRAMES: int = 10
const EMPTY: int = -1
## Plaque geometry from Hud (value column right edge and caption columns).
const METER_TEXT_WIDTH: float = 68.0
const MAX_FAILURE_LINES_PER_ROOM: int = 12

var _passed: int = 0
var _failed: int = 0
var _logger: ErrorCounter = null
var _short_report: PackedStringArray = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check(false, "main scene loads")
	else:
		for path: String in ROOMS:
			await _check_room(packed, path)
	Room.level_override = ""
	print("")
	print("== Rooms that can reach SHORT")
	if _short_report.is_empty():
		print("  none")
	for line: String in _short_report:
		print("  " + line)
	var errors: PackedStringArray = _logger.lines_since(0)
	_check(errors.is_empty(), "no ERROR or WARNING was logged during the whole run (%d logged)" % errors.size())
	for i: int in mini(errors.size(), 10):
		print("      " + errors[i])
	OS.remove_logger(_logger)
	print("")
	print("play_world_states: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check_room(packed: PackedScene, path: String) -> void:
	print("")
	print("== %s" % path)
	var errors_before: int = _logger.count()
	Room.level_override = path
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_physics(SETTLE_FRAMES)
	var room: Room = main.get_node_or_null(ROOM_PATH) as Room
	if room == null or room.level_data == null:
		_check(false, "%s loads" % path)
		main.queue_free()
		await _wait_physics(2)
		return
	var board: CircuitBoard = room.get_board()
	var sockets: Array[CircuitSocket] = board.get_sockets()
	var pickups: Array[PartPickup] = room.get_parts()
	var circuit: LevelCircuit = room.get_circuit()
	var goal: LevelGoal = room.get_goal()
	# Keep Ohmie out of the way (no input is pressed in this test).
	room.get_carry().set_enabled(false)

	var assignments: Array[PackedInt32Array] = []
	_enumerate(sockets.size(), pickups.size(), PackedInt32Array(), assignments)
	print("  %d slots, %d parts, %d assignments" % [sockets.size(), pickups.size(), assignments.size()])

	# 1. Pure solver over every assignment.
	var indeterminate: PackedStringArray = []
	var errored: PackedStringArray = []
	var shorts: PackedStringArray = []
	var must_include: Dictionary = {}
	var short_indices: Array[int] = []
	var solving: int = 0
	for i: int in assignments.size():
		var solution: DcSolution = DcSolver.solve(circuit.build_network(_fill(assignments[i], sockets, pickups)))
		match solution.status:
			DcSolution.Status.INDETERMINATE:
				indeterminate.append(_describe(assignments[i], sockets, pickups))
				must_include[i] = true
			DcSolution.Status.ERROR:
				errored.append(_describe(assignments[i], sockets, pickups))
				must_include[i] = true
			DcSolution.Status.SHORT:
				shorts.append(_describe(assignments[i], sockets, pickups))
				short_indices.append(i)
		if goal.is_met(solution):
			solving += 1
			must_include[i] = true
	_check(indeterminate.is_empty(), "%s: no assignment is INDETERMINATE (%d are: %s)" % [
			room.level_data.id, indeterminate.size(), _first(indeterminate)])
	_check(errored.is_empty(), "%s: no assignment gives ERROR (%d do: %s)" % [
			room.level_data.id, errored.size(), _first(errored)])
	print("  INFO  %d assignment(s) meet the goal, %d give SHORT" % [solving, shorts.size()])
	if not shorts.is_empty():
		_short_report.append("%s: %d assignment(s), e.g. %s" % [room.level_data.id, shorts.size(), _first(shorts)])

	# 2. In-game check on a sample.
	var chosen: Array[int] = _sample(assignments.size(), must_include, short_indices)
	var bad_lines: PackedStringArray = []
	var room_failures: int = 0
	for index: int in chosen:
		var problems: PackedStringArray = _apply_and_compare(assignments[index], room, sockets, pickups)
		if not problems.is_empty():
			room_failures += 1
			if bad_lines.size() < MAX_FAILURE_LINES_PER_ROOM:
				bad_lines.append("[%s] %s" % [_describe(assignments[index], sockets, pickups), "; ".join(problems)])
	_check(room_failures == 0, "%s: door, plaque, meters, lamps and wires match an independent solve for all %d sampled assignments (%d mismatched)" % [
			room.level_data.id, chosen.size(), room_failures])
	for line: String in bad_lines:
		print("      " + line)
	var new_errors: PackedStringArray = _logger.lines_since(errors_before)
	_check(new_errors.is_empty(), "%s: no ERROR or WARNING logged (%d)" % [room.level_data.id, new_errors.size()])
	for i: int in mini(new_errors.size(), 5):
		print("      " + new_errors[i])

	main.queue_free()
	current_scene = null
	await _wait_physics(3)


## Every assignment of `part_count` distinct parts (or EMPTY) to `slot_count` slots.
func _enumerate(slot_count: int, part_count: int, prefix: PackedInt32Array, out: Array[PackedInt32Array]) -> void:
	if prefix.size() == slot_count:
		out.append(prefix.duplicate())
		return
	for choice: int in range(EMPTY, part_count):
		if choice != EMPTY and prefix.has(choice):
			continue
		var next: PackedInt32Array = prefix.duplicate()
		next.append(choice)
		_enumerate(slot_count, part_count, next, out)


## At most MAX_PER_ROOM indices (more only if `must` alone is larger): every
## index in `must`, then about half the remaining places for evenly spaced
## SHORT indices, then evenly spaced others.
func _sample(total: int, must: Dictionary, shorts: Array[int]) -> Array[int]:
	var picked: Dictionary = {}
	for key: Variant in must.keys():
		picked[int(key)] = true
	if total <= MAX_PER_ROOM:
		for i: int in total:
			picked[i] = true
	else:
		var places: int = maxi(MAX_PER_ROOM - picked.size(), 0)
		var short_places: int = mini(shorts.size(), floori(places * 0.5))
		for k: int in short_places:
			picked[shorts[int(floor(float(k) * float(shorts.size()) / float(short_places)))]] = true
		var step: float = float(total) / float(maxi(MAX_PER_ROOM - picked.size(), 1))
		var x: float = 0.0
		while picked.size() < MAX_PER_ROOM and x < float(total):
			picked[int(x)] = true
			x += step
	var out: Array[int] = []
	for key: Variant in picked.keys():
		out.append(int(key))
	out.sort()
	return out


func _fill(assignment: PackedInt32Array, sockets: Array[CircuitSocket], pickups: Array[PartPickup]) -> Dictionary:
	var filled: Dictionary = {}
	for s: int in assignment.size():
		if assignment[s] != EMPTY:
			filled[sockets[s].socket_id] = pickups[assignment[s]].part
	return filled


func _describe(assignment: PackedInt32Array, sockets: Array[CircuitSocket], pickups: Array[PartPickup]) -> String:
	var parts: PackedStringArray = []
	for s: int in assignment.size():
		var what: String = "-" if assignment[s] == EMPTY else pickups[assignment[s]].part.label()
		parts.append("%s=%s" % [sockets[s].socket_id, what])
	return ", ".join(parts)


func _first(items: PackedStringArray) -> String:
	if items.is_empty():
		return "none"
	var shown: PackedStringArray = items.slice(0, 3)
	return " | ".join(shown) + (" | ..." if items.size() > 3 else "")


## Puts `assignment` into the slots and returns every mismatch found.
func _apply_and_compare(assignment: PackedInt32Array, room: Room, sockets: Array[CircuitSocket],
		pickups: Array[PartPickup]) -> PackedStringArray:
	for socket: CircuitSocket in sockets:
		socket.take_out()
	for s: int in assignment.size():
		if assignment[s] != EMPTY:
			var pickup: PartPickup = pickups[assignment[s]]
			pickup.take()
			sockets[s].insert(pickup)
	var problems: PackedStringArray = []
	var board: CircuitBoard = room.get_board()
	var goal: LevelGoal = room.get_goal()
	var circuit: LevelCircuit = room.get_circuit()
	var hud: Hud = room.get_hud()
	var door: ExitDoor = room.get_door()
	var expected: DcSolution = DcSolver.solve(circuit.build_network(_fill(assignment, sockets, pickups)))
	var met: bool = goal.is_met(expected)
	var is_short: bool = expected.status == DcSolution.Status.SHORT

	if door.is_open() != met:
		problems.append("door %s, goal %s" % ["open" if door.is_open() else "shut", "met" if met else "not met"])
	if board.is_goal_met() != met:
		problems.append("board goal_met %s" % board.is_goal_met())
	if hud.is_mission_complete_shown() != met:
		problems.append("mission sign done %s" % hud.is_mission_complete_shown())
	if is_short and door.is_open():
		problems.append("SHORT with the door open")

	# Plaque rows.
	var count: int = goal.condition_count()
	if count == 1:
		var caption: String = _caption(goal, circuit, 0)
		_expect_text(problems, "plaque row 0 caption", hud.get_row_caption(0), "GOAL")
		_expect_text(problems, "plaque row 0 value", hud.get_row_value(0), goal.target_text(0))
		_expect_text(problems, "plaque row 1 caption", hud.get_row_caption(1), caption)
		_expect_text(problems, "plaque row 1 value", hud.get_row_value(1), goal.reading_text(0, expected))
	else:
		for i: int in mini(count, 2):
			_expect_text(problems, "plaque row %d caption" % i, hud.get_row_caption(i), _caption(goal, circuit, i))
			_expect_text(problems, "plaque row %d value" % i, hud.get_row_value(i),
					goal.reading_text(i, expected) + "  →  " + goal.target_text(i))
	for i: int in count:
		if hud.is_condition_met_shown(i) != goal.is_condition_met(i, expected):
			problems.append("plaque row for condition %d green=%s, condition met=%s" % [
					i, hud.is_condition_met_shown(i), goal.is_condition_met(i, expected)])
		if is_short and goal.conditions[i].quantity != GoalCondition.Quantity.RESISTANCE \
				and hud.get_reading_text(i) != "SHORT":
			problems.append("SHORT but plaque reading %d is '%s'" % [i, hud.get_reading_text(i)])
	_check_plaque_fit(problems, hud)

	# Meters.
	for edge: LevelCircuit.Edge in circuit.get_edges():
		if not edge.is_meter():
			continue
		var meter: BoardMeter = board.get_meter(edge.id)
		if meter == null:
			problems.append("meter %s missing" % edge.id)
			continue
		var want: String = MeterText.reading(expected, edge.id)
		_expect_text(problems, "meter %s" % edge.id, meter.get_reading(), want)
		if is_short and edge.type != LevelCircuit.TYPE_OHMMETER and meter.get_reading() != "SHORT":
			problems.append("SHORT but meter %s reads '%s'" % [edge.id, meter.get_reading()])
		var label: Label = meter.get_node_or_null(^"Reading") as Label
		if label != null:
			var font: Font = label.get_theme_font(&"font")
			var size: int = label.get_theme_font_size(&"font_size")
			var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if width > METER_TEXT_WIDTH + 0.5:
				problems.append("meter %s text '%s' is %.0f px wide in a %.0f px window (font %d)" % [
						edge.id, label.text, width, METER_TEXT_WIDTH, size])

	# Lamps.
	for edge: LevelCircuit.Edge in circuit.get_edges():
		if edge.type != LevelCircuit.TYPE_LAMP:
			continue
		var lamp: BoardLamp = board.get_lamp(edge.id)
		if lamp == null:
			problems.append("lamp %s missing" % edge.id)
			continue
		var want_state: BoardLamp.State = _lamp_state(expected.current_through(edge.id), edge.rated_min, edge.rated_max)
		if lamp.get_state() != want_state:
			problems.append("lamp %s is %s, expected %s" % [edge.id, BoardLamp.State.keys()[lamp.get_state()],
					BoardLamp.State.keys()[want_state]])

	# Wires.
	var wire_state: CircuitWires.State = board.get_wires().get_state()
	var want_wires: CircuitWires.State = CircuitWires.State.PLAIN
	if is_short:
		want_wires = CircuitWires.State.SHORT
	elif met:
		want_wires = CircuitWires.State.MATCH
	elif expected.is_energized():
		want_wires = CircuitWires.State.ENERGIZED
	if wire_state != want_wires:
		problems.append("wires %s, expected %s" % [CircuitWires.State.keys()[wire_state], CircuitWires.State.keys()[want_wires]])
	return problems


## Independent of BoardLamp.state_for: compares |current| with the rating.
func _lamp_state(current: Rational, rated_min: Rational, rated_max: Rational) -> BoardLamp.State:
	if current == null:
		return BoardLamp.State.OFF
	var magnitude: Rational = current
	if current.sign() < 0:
		magnitude = current.negate()
	if magnitude.compare(rated_max) > 0:
		return BoardLamp.State.BLOWN
	if magnitude.compare(rated_min) >= 0:
		return BoardLamp.State.ON
	return BoardLamp.State.OFF


func _caption(goal: LevelGoal, circuit: LevelCircuit, index: int) -> String:
	var symbol: String = goal.symbol(index)
	var edge: LevelCircuit.Edge = circuit.get_edge(goal.conditions[index].element_id)
	if edge == null or edge.label.is_empty():
		return symbol
	return "%s %s" % [symbol, edge.label]


## Every plaque label's text fits inside the label at its font size, and the
## value labels end at or left of the plaque's value column edge.
func _check_plaque_fit(problems: PackedStringArray, hud: Hud) -> void:
	for path: NodePath in [^"Readout/Row0Caption", ^"Readout/Row1Caption", ^"Readout/Row0Value", ^"Readout/Row1Value"]:
		var label: Label = hud.get_node_or_null(path) as Label
		if label == null or label.text.is_empty():
			continue
		var font: Font = label.get_theme_font(&"font")
		var size: int = label.get_theme_font_size(&"font_size")
		var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var right: float = label.position.x + label.size.x
		if width > label.size.x + 0.5:
			problems.append("plaque %s '%s' is %.0f px wide in %.0f px (font %d)" % [path, label.text, width, label.size.x, size])
		if right > Hud.VALUE_RIGHT + 0.5:
			problems.append("plaque %s ends at x %.0f, past %.0f" % [path, right, Hud.VALUE_RIGHT])


func _expect_text(problems: PackedStringArray, what: String, got: String, want: String) -> void:
	if got != want:
		problems.append("%s '%s' (expected '%s')" % [what, got, want])


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS  " + description)
	else:
		_failed += 1
		print("FAIL  " + description)
