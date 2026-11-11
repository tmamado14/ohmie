class_name Room
extends Node2D
## Builds one room from a level file (theme, tiles, pickups, circuit board,
## door, HUD, player) and runs its flow: the board's reading, judged by the
## level's goal, drives the HUD and the door,
## the open door completes the level, `restart` reloads the scene, and falling
## out respawns Ohmie (a carried resistor goes back to its home). After the
## level is complete, `interact` loads the next level of the Campaign, if any.
##
## The level file is, in order of precedence: `level_override` (set by scripted
## tests; it survives `restart` reloads), a user argument
## --level=res://levels/<file>.json on the command line (after `--`), or
## `level_path`.
## Also connects gameplay signals to the Sfx autoload.

## Emitted once when Ohmie walks into the open door.
signal level_completed

const LEVEL_ARG_PREFIX: String = "--level="
## The background is scaled to cover exactly this area (the 1280x720 room).
const ROOM_SIZE: Vector2 = Vector2(1280, 720)

## When not empty, every Room loads this level instead of `level_path` or the
## command line. A static, so it outlives scene reloads; for scripted tests.
static var level_override: String = ""

@export_file("*.json") var level_path: String = ""
@export var player_scene: PackedScene
@export var pickup_scene: PackedScene

## The parsed level, or null if loading failed.
var level_data: LevelData = null

var _theme: RoomTheme = null

var _circuit: LevelCircuit = null
var _goal: LevelGoal = null
var _player: Player = null
var _carry: PlayerCarry = null
var _pickups: Array[ResistorPickup] = []
var _was_match: bool = false
var _complete: bool = false
var _sfx: SfxPlayer = null
## The campaign level after this one ("" if none), known once the level is complete.
var _next_level: String = ""

@onready var _background: Sprite2D = $Background
@onready var _tiles: RoomTiles = $Tiles
@onready var _board: CircuitBoard = $Board
@onready var _door: ExitDoor = $Door/ExitDoor
@onready var _pickup_container: Node2D = $Pickups
@onready var _hud: Hud = $Hud/Hud


func _ready() -> void:
	_sfx = get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	var override: String = level_override
	if override.is_empty():
		override = level_path_from_command_line()
	if not override.is_empty():
		level_path = override
	if not _load_level():
		return
	_apply_theme()
	_tiles.build(level_data.tile_rows)
	_hud.set_title(level_data.title)
	_hud.set_goal(_goal.goal_label(), _goal.mission, _goal.reading_caption())
	_door.position = level_data.door
	_door.entered.connect(_on_door_entered)
	_door.opened.connect(_play_sound.bind(&"door_open"))
	_build_pickups()
	_spawn_player()
	_board.resistance_changed.connect(_on_resistance_changed)
	_board.build(_circuit, _goal, _theme)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif event.is_action_pressed("interact") and _complete and not _next_level.is_empty():
		get_viewport().set_input_as_handled()
		level_override = _next_level
		get_tree().reload_current_scene()


## The value of a --level=<path> user argument, or "" if there is none.
static func level_path_from_command_line() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(LEVEL_ARG_PREFIX):
			return arg.substr(LEVEL_ARG_PREFIX.length())
	return ""


## The theme in use (tiles, background, music, wire colours), or null.
func get_room_theme() -> RoomTheme:
	return _theme


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


## The level's goal (what solves it and the mission text), or null.
func get_goal() -> LevelGoal:
	return _goal


## The goal's target resistance, or null when the goal is not a resistance goal.
func get_target() -> Rational:
	return _goal.target if _goal != null else null


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
	_goal = level_data.goal
	return true


func _apply_theme() -> void:
	_theme = RoomTheme.load_for_world(level_data.world)
	if _theme == null:
		return
	_tiles.tile_set = _theme.tileset
	_background.texture = _theme.background
	if _theme.background != null:
		_background.scale = ROOM_SIZE / _theme.background.get_size()
	_background.modulate = _theme.background_modulate
	if _sfx != null:
		_sfx.play_music(_theme.music)


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
	_hud.show_reading(_goal.reading_label(result), is_match)
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
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	_next_level = campaign.next_after(level_path) if campaign != null else ""
	_hud.show_level_complete(not _next_level.is_empty())
	_play_sound(&"win")
	level_completed.emit()


func _play_sound(sound: StringName) -> void:
	if _sfx != null:
		_sfx.play(sound)


func _on_player_fell_out() -> void:
	if _carry != null:
		_carry.return_carried_home()
	_player.respawn(level_data.spawn)
