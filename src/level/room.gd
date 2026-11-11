class_name Room
extends Node2D
## Builds one room from a level file: tiles and the player at the spawn point.
## Respawns the player when they fall out, and reloads the scene on `restart`.
##
## Board, Pickups, Door and Hud are empty containers for later features.

@export_file("*.json") var level_path: String = ""
@export var player_scene: PackedScene

## The parsed level, or null if loading failed.
var level_data: LevelData = null

var _player: Player = null

@onready var _tiles: RoomTiles = $Tiles


func _ready() -> void:
	level_data = LevelData.load_from_file(level_path)
	if level_data == null:
		push_error("Room: could not load level '%s'" % level_path)
		return
	_tiles.build(level_data.tile_rows)
	_spawn_player()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


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


func _on_player_fell_out() -> void:
	_player.respawn(level_data.spawn)
