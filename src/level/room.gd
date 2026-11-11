class_name Room
extends Node2D
## Builds one room from a level file (tiles, pickups, circuit board, door, HUD,
## player) and runs its flow: the board's reading drives the HUD and the door,
## the open door completes the level, `restart` reloads the scene, and falling
## out respawns Ohmie (a carried resistor goes back to its home).
##
## The level file is `level_path`, unless the command line has a user argument
## --level=res://levels/<file>.json (after `--`), which wins.
## Also connects gameplay signals to the Sfx autoload.

## Emitted once when Ohmie walks into the open door.
signal level_completed

const LEVEL_ARG_PREFIX: String = "--level="

@export_file("*.json") var level_path: String = ""
@export var player_scene: PackedScene
@export var pickup_scene: PackedScene

## The parsed level, or null if loading failed.
var level_data: LevelData = null

var _circuit: LevelCircuit = null
var _target: Rational = null
var _player: Player = null
var _carry: PlayerCarry = null
var _pickups: Array[ResistorPickup] = []
var _was_match: bool = false
var _complete: bool = false
var _sfx: SfxPlayer = null

@onready var _tiles: RoomTiles = $Tiles
@onready var _board: CircuitBoard = $Board
@onready var _door: ExitDoor = $Door/ExitDoor
@onready var _pickup_container: Node2D = $Pickups
@onready var _hud: Hud = $Hud/Hud


func _ready() -> void:
	_sfx = get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	var override: String = level_path_from_command_line()
	if not override.is_empty():
		level_path = override
	if not _load_level():
		return
	_tiles.build(level_data.tile_rows)
	_hud.set_title(level_data.title)
	_hud.set_target(_target)
	_door.position = level_data.door
	_door.entered.connect(_on_door_entered)
	_door.opened.connect(_play_sound.bind(&"door_open"))
	_build_pickups()
	_spawn_player()
	_board.resistance_changed.connect(_on_resistance_changed)
	_board.build(_circuit, _target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


## The value of a --level=<path> user argument, or "" if there is none.
static func level_path_from_command_line() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(LEVEL_ARG_PREFIX):
			return arg.substr(LEVEL_ARG_PREFIX.length())
	return ""


func get_player() -> Player:
	return _player


func get_carry() -> PlayerCarry:
	return _carry


func get_board() -> CircuitBoard:
	return _board


func get_door() -> ExitDoor:
	return _door


func get_hud() -> Hud:
	return _hud


func get_circuit() -> LevelCircuit:
	return _circuit


func get_target() -> Rational:
	return _target


func get_pickups() -> Array[ResistorPickup]:
	return _pickups.duplicate()


func is_complete() -> bool:
	return _complete


func _load_level() -> bool:
	level_data = LevelData.load_from_file(level_path)
	if level_data == null:
		push_error("Room: could not load level '%s'" % level_path)
		return false
	_circuit = LevelCircuit.from_dictionary(level_data.circuit, level_path)
	if _circuit == null:
		push_error("Room: level '%s' has an invalid circuit" % level_path)
		level_data = null
		return false
	_target = Rational.parse(level_data.target_text)
	if _target == null or not _target.is_valid() or _target.sign() <= 0:
		push_error("Room: level '%s' has an invalid target '%s'" % [level_path, level_data.target_text])
		level_data = null
		return false
	return true


func _build_pickups() -> void:
	var entries: Array[LevelPickup] = []
	if not LevelPickup.parse_all(level_data.pickups, level_path, entries):
		return
	if pickup_scene == null:
		push_error("Room: pickup_scene is not set")
		return
	for entry: LevelPickup in entries:
		var pickup: ResistorPickup = pickup_scene.instantiate() as ResistorPickup
		if pickup == null:
			push_error("Room: pickup_scene does not have a ResistorPickup root")
			return
		pickup.name = "Pickup_" + entry.id
		_pickup_container.add_child(pickup)
		pickup.setup(entry.id, entry.ohms, entry.position)
		_pickups.append(pickup)


func _spawn_player() -> void:
	if player_scene == null:
		push_error("Room: player_scene is not set")
		return
	_player = player_scene.instantiate() as Player
	if _player == null:
		push_error("Room: player_scene does not have a Player root")
		return
	_player.name = "Player"
	add_child(_player)
	_player.respawn(level_data.spawn)
	_player.fell_out.connect(_on_player_fell_out)
	_player.jumped.connect(_play_sound.bind(&"jump"))
	_player.landed.connect(_play_sound.bind(&"land"))
	_carry = _player.get_node_or_null(^"Carry") as PlayerCarry
	if _carry == null:
		push_error("Room: the player has no PlayerCarry child named 'Carry'")
		return
	_carry.picked_up.connect(_play_sound.bind(&"pickup").unbind(1))
	_carry.removed.connect(_play_sound.bind(&"pickup").unbind(2))
	_carry.placed.connect(_play_sound.bind(&"place_resistor").unbind(2))
	_carry.swapped.connect(_play_sound.bind(&"place_resistor").unbind(3))
	_carry.dropped.connect(_play_sound.bind(&"place_resistor").unbind(1))
	_carry.invalid_action.connect(_play_sound.bind(&"invalid"))


func _on_resistance_changed(result: CircuitResult, is_match: bool) -> void:
	_hud.show_reading(result, is_match)
	if is_match and not _was_match:
		_play_sound(&"connect")
	_was_match = is_match
	_door.set_open(is_match)


func _on_door_entered() -> void:
	if _complete:
		return
	_complete = true
	if _player != null:
		_player.set_input_enabled(false)
		_player.play_victory()
	if _carry != null:
		_carry.set_enabled(false)
	_hud.show_level_complete()
	_play_sound(&"win")
	level_completed.emit()


func _play_sound(sound: StringName) -> void:
	if _sfx != null:
		_sfx.play(sound)


func _on_player_fell_out() -> void:
	if _carry != null:
		_carry.return_carried_home()
	_player.respawn(level_data.spawn)
