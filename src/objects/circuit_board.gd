class_name CircuitBoard
extends Node2D
## The level's closed circuit drawn on the wall (GDD 12.2): wires, junction
## dots, slots, fixed resistors and batteries, lamps and meters, built from a
## LevelCircuit.
##
## Whenever a slot's contents change it builds the network with
## LevelCircuit.build_network, solves it once with DcSolver, updates every
## meter's reading, every lamp and the wire colour, and announces the solution
## with `circuit_changed`; `goal_met` is LevelGoal.is_met. It also announces
## once right after build(). `shorted` is emitted when a change puts the
## circuit into a SHORT (not for a board that starts shorted).
##
## `special_readings_changed` announces the special readings (MeterText:
## SHORT, ???, OL, ---) its meters show, whenever that set changes (and once
## after build()).
##
## Fixed components and meters are drawn at z 0 and slots at z 1 (their
## scene's z_index); enemies (z 2) and Ohmie (z 3) draw in front. Every slot,
## fixed part, lamp and meter carries a PartBlocker over its frame, so a loose
## part is never put down on it.

signal circuit_changed(solution: DcSolution, goal_met: bool)
signal shorted
## The special readings now on the board's meters, each once, in
## MeterText.SPECIAL_READINGS order (empty when none).
signal special_readings_changed(readings: PackedStringArray)

const NODE_DOT_TEXTURE: Texture2D = preload("res://assets/processed/node_dot.png")
## The processed art is drawn at 2x; this brings it to its on-screen size.
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## Nodes with at least this many edges get a junction dot.
const JUNCTION_DEGREE: int = 3
## Where a loose part may not be put down over a fixed part, lamp or meter: the
## 104x72 frame, 8 px wider on each side so a part's leads stay clear of it
## too (the same area as the PartBlocker in socket.tscn). Its bottom centre
## sits BLOCKER_OFFSET below the component's centre.
const BLOCKER_SIZE: Vector2 = Vector2(120, 72)
const BLOCKER_OFFSET: Vector2 = Vector2(0, 36)
## Every slot, fixed part, lamp and meter is drawn 104x72, centred on its edge's midpoint.
const COMPONENT_SIZE: Vector2 = Vector2(104, 72)

@export var socket_scene: PackedScene

var _circuit: LevelCircuit = null
var _goal: LevelGoal = null
var _sockets: Array[CircuitSocket] = []
var _meters: Dictionary = {}  # edge id -> BoardMeter
var _lamps: Dictionary = {}  # edge id -> BoardLamp
var _wires: CircuitWires = null
var _last_solution: DcSolution = null
var _goal_met: bool = false
var _was_short: bool = false
var _component_frames: Array[Rect2] = []
var _special_readings: PackedStringArray = PackedStringArray()
var _specials_announced: bool = false


## Builds every visual from `circuit` and announces the first solution.
## `goal` decides what counts as solved. `theme` colours the wires.
func build(circuit: LevelCircuit, goal: LevelGoal, theme: RoomTheme = null) -> void:
	_circuit = circuit
	_goal = goal
	_wires = CircuitWires.new()
	_wires.name = "Wires"
	add_child(_wires)
	_wires.build(circuit, theme)
	_add_junction_dots()
	_add_components()
	_refresh()


func get_sockets() -> Array[CircuitSocket]:
	return _sockets.duplicate()


## The meter drawn for edge `id`, or null.
func get_meter(id: String) -> BoardMeter:
	return _meters.get(id, null)


## The lamp drawn for edge `id`, or null.
func get_lamp(id: String) -> BoardLamp:
	return _lamps.get(id, null)


func get_wires() -> CircuitWires:
	return _wires


## The global frame of every slot, fixed part, lamp and meter, in edge order.
func get_component_frames() -> Array[Rect2]:
	return _component_frames.duplicate()


## The special readings the meters show now (see special_readings_changed).
func get_special_readings() -> PackedStringArray:
	return _special_readings.duplicate()


## The most recent solution (null before build()).
func get_last_solution() -> DcSolution:
	return _last_solution


## The goal's verdict on the most recent solution.
func is_goal_met() -> bool:
	return _goal_met


func _add_junction_dots() -> void:
	for node_name: String in _circuit.get_node_names():
		if _circuit.get_node_degree(node_name) >= JUNCTION_DEGREE:
			var dot: Sprite2D = Sprite2D.new()
			dot.name = "Dot_" + node_name
			dot.texture = NODE_DOT_TEXTURE
			dot.scale = ART_SCALE
			dot.position = _circuit.get_node_position(node_name)
			add_child(dot)


func _add_components() -> void:
	for edge: LevelCircuit.Edge in _circuit.get_edges():
		var a: Vector2 = _circuit.get_node_position(edge.from_node)
		var b: Vector2 = _circuit.get_node_position(edge.to_node)
		var middle: Vector2 = (a + b) * 0.5
		var from_is_right: bool = a.x > b.x
		if edge.type != LevelCircuit.TYPE_WIRE:
			_component_frames.append(Rect2(to_global(middle) - COMPONENT_SIZE * 0.5, COMPONENT_SIZE))
		match edge.type:
			LevelCircuit.TYPE_SLOT:
				_add_socket(edge.id, middle, from_is_right)
			LevelCircuit.TYPE_RESISTOR, LevelCircuit.TYPE_BATTERY:
				var fixed: FixedPart = FixedPart.new()
				fixed.name = "Fixed_" + edge.id
				fixed.position = middle
				add_child(fixed)
				var kind: Part.Kind = Part.Kind.BATTERY if edge.type == LevelCircuit.TYPE_BATTERY else Part.Kind.RESISTOR
				fixed.setup(Part.create(kind, edge.value), from_is_right)
				_add_blocker(fixed)
			LevelCircuit.TYPE_LAMP:
				var lamp: BoardLamp = BoardLamp.new()
				lamp.name = "Lamp_" + edge.id
				lamp.lamp_id = edge.id
				lamp.position = middle
				add_child(lamp)
				_lamps[edge.id] = lamp
				_add_blocker(lamp)
			LevelCircuit.TYPE_AMMETER, LevelCircuit.TYPE_VOLTMETER, LevelCircuit.TYPE_OHMMETER:
				var meter: BoardMeter = BoardMeter.new()
				meter.name = "Meter_" + edge.id
				meter.position = middle
				add_child(meter)
				meter.setup(edge.id, edge.type)
				_meters[edge.id] = meter
				_add_blocker(meter)


func _add_blocker(component: Node2D) -> void:
	var blocker: PartBlocker = PartBlocker.new()
	blocker.name = "PartBlocker"
	blocker.size = BLOCKER_SIZE
	blocker.position = BLOCKER_OFFSET
	component.add_child(blocker)


func _add_socket(id: String, at: Vector2, from_is_right: bool) -> void:
	if socket_scene == null:
		push_error("CircuitBoard: socket_scene is not set")
		return
	var socket: CircuitSocket = socket_scene.instantiate() as CircuitSocket
	if socket == null:
		push_error("CircuitBoard: socket_scene does not have a CircuitSocket root")
		return
	socket.name = "Socket_" + id
	socket.socket_id = id
	socket.position = at
	add_child(socket)
	socket.set_from_is_right(from_is_right)
	socket.contents_changed.connect(_refresh)
	_sockets.append(socket)


func _refresh() -> void:
	var filled: Dictionary = {}
	for socket: CircuitSocket in _sockets:
		if socket.is_filled():
			filled[socket.socket_id] = socket.get_part()
	var solution: DcSolution = DcSolver.solve(_circuit.build_network(filled))
	var goal_met: bool = _goal != null and _goal.is_met(solution)
	var first: bool = _last_solution == null
	_last_solution = solution
	_goal_met = goal_met
	var shown: PackedStringArray = PackedStringArray()
	for id: String in _meters:
		var reading: String = MeterText.reading(solution, id)
		(_meters[id] as BoardMeter).set_reading(reading)
		shown.append(reading)
	for id: String in _lamps:
		var edge: LevelCircuit.Edge = _circuit.get_edge(id)
		(_lamps[id] as BoardLamp).set_state(BoardLamp.state_for(
				solution.current_through(id), edge.rated_min, edge.rated_max))
	var is_short: bool = solution.status == DcSolution.Status.SHORT
	_wires.set_state(_wire_state(solution, goal_met))
	circuit_changed.emit(solution, goal_met)
	if is_short and not _was_short and not first:
		shorted.emit()
	_was_short = is_short
	_announce_special_readings(MeterText.special_readings_in(shown))


func _announce_special_readings(specials: PackedStringArray) -> void:
	if _specials_announced and specials == _special_readings:
		return
	_specials_announced = true
	_special_readings = specials
	special_readings_changed.emit(specials.duplicate())


static func _wire_state(solution: DcSolution, goal_met: bool) -> CircuitWires.State:
	if solution.status == DcSolution.Status.SHORT:
		return CircuitWires.State.SHORT
	if goal_met:
		return CircuitWires.State.MATCH
	if solution.is_energized():
		return CircuitWires.State.ENERGIZED
	return CircuitWires.State.PLAIN
