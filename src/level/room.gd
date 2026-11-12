class_name Room
extends Node2D
## Builds one room from a level file (theme, tiles, parts, circuit board,
## door, HUD, player) and runs its flow: the board's solution, judged by the
## level's goal, drives the HUD and the door; the open door completes the
## level, `restart` reloads the scene, and falling out respawns Ohmie (a
## carried part goes back to its home). The level's bounce pads, enemies and
## hazards are built by RoomObjects: a pad's `bounced` launches Ohmie, a
## hazard's touch zaps him. A zap and a pit fall share one respawn path,
## PlayerRespawn (a zap first freezes Ohmie for a short hit beat). After the
## level is complete, `interact` loads the next built room of the Campaign, if any, and the room
## is recorded as completed in GameSession's Progress (saved to disk only when
## the game was started through the menus).
##
## When the game was started through the menus (GameSession.from_menus), Esc
## (`menu_back`) returns to the level select (an Esc pressed while the room is
## still fading in is remembered and acted on when the fade ends), the next
## room is loaded with a fade, and the victory line mentions the map.
## Otherwise Esc does nothing.
##
## The level file is, in order of precedence: `level_override` (set by scripted
## tests; it survives `restart` reloads), a user argument
## --level=res://levels/<file>.json on the command line (after `--`), the room
## chosen in the menus (GameSession.room_file), the campaign's first built room
## when `start_from_campaign` is set, or `level_path`.
## Also connects gameplay signals to the Sfx autoload.

## Emitted once when Ohmie walks into the open door.
signal level_completed
## Emitted once per accepted zap (an enemy or hazard touched Ohmie).
signal zapped

const LEVEL_ARG_PREFIX: String = "--level="
## The background is scaled to cover exactly this area (the 1280x720 room).
const ROOM_SIZE: Vector2 = Vector2(1280, 720)

## When not empty, every Room loads this level instead of `level_path` or the
## command line. A static, so it outlives scene reloads; for scripted tests.
static var level_override: String = ""

## The level to load when nothing else names one (and the fallback when the
## campaign cannot be read).
@export_file("*.json") var level_path: String = ""
## Load the campaign's first level instead of `level_path`.
@export var start_from_campaign: bool = false
@export var player_scene: PackedScene
@export var pickup_scene: PackedScene

## The parsed level, or null if loading failed.
var level_data: LevelData = null

var _theme: RoomTheme = null

var _circuit: LevelCircuit = null
var _goal: LevelGoal = null
var _player: Player = null
var _carry: PlayerCarry = null
var _parts: Array[PartPickup] = []
var _was_met: bool = false
var _complete: bool = false
var _sfx: SfxPlayer = null
## The campaign level after this one ("" if none), known once the level is complete.
var _next_level: String = ""
## Esc pressed while the room is still fading in is acted on when it ends.
var _fade_buffer: FadeInputBuffer = FadeInputBuffer.new(["menu_back"])

@onready var _background: Sprite2D = $Background
@onready var _tiles: RoomTiles = $Tiles
@onready var _board: CircuitBoard = $Board
@onready var _door: ExitDoor = $Door/ExitDoor
@onready var _part_container: Node2D = $Parts
@onready var _hud: Hud = $Hud/Hud
@onready var _objects: RoomObjects = $Objects
@onready var _respawn: PlayerRespawn = $Respawn
@onready var _target_tag: TargetTag = $TargetTag


func _ready() -> void:
	_sfx = get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	level_path = _choose_level_path()
	if not _load_level():
		return
	_apply_theme()
	_tiles.build(level_data.tile_rows)
	_hud.set_title(level_data.title)
	_hud.set_mission(_goal.mission)
	_hud.set_controls_hint(_has_one_way_platform(), GameSession.from_menus)
	var symbols: PackedStringArray = PackedStringArray()
	var targets: PackedStringArray = PackedStringArray()
	for i: int in _goal.condition_count():
		symbols.append(_row_caption(i))
		targets.append(_goal.target_text(i))
	_hud.set_goal_rows(symbols, targets)
	_door.position = level_data.door
	_door.entered.connect(_on_door_entered)
	_door.opened.connect(_play_sound.bind(&"door_open"))
	_build_parts()
	_objects.build(level_data.objects)
	_objects.touched.connect(_on_object_touched)
	_objects.bounced.connect(_on_object_bounced)
	_spawn_player()
	_board.circuit_changed.connect(_on_circuit_changed)
	_board.shorted.connect(_play_sound.bind(&"invalid"))
	_board.build(_circuit, _goal, _theme)
	ScreenFade.connect_finished(get_tree(), _on_fade_finished)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif event.is_action_pressed("menu_back") and GameSession.from_menus:
		get_viewport().set_input_as_handled()
		if ScreenFade.is_busy(get_tree()):
			_fade_buffer.offer(get_tree(), event)
		else:
			ScreenFade.go_to(get_tree(), ScreenFade.LEVEL_SELECT)
	elif event.is_action_pressed("interact") and _complete and not _next_level.is_empty():
		get_viewport().set_input_as_handled()
		if GameSession.from_menus:
			GameSession.room_file = _next_level
			ScreenFade.go_to(get_tree(), ScreenFade.GAME)
		else:
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


## The level's goal (mission and conditions), or null.
func get_goal() -> LevelGoal:
	return _goal


## The level's bounce pads, enemies and hazards.
func get_objects() -> RoomObjects:
	return _objects


## The name tag over the highlighted target.
func get_target_tag() -> TargetTag:
	return _target_tag


## Ohmie's respawn path (pit falls and zaps).
func get_respawn() -> PlayerRespawn:
	return _respawn


## Every carried part of the level, in file order.
func get_parts() -> Array[PartPickup]:
	return _parts.duplicate()


func is_complete() -> bool:
	return _complete


func _choose_level_path() -> String:
	if not level_override.is_empty():
		return level_override
	var from_command_line: String = level_path_from_command_line()
	if not from_command_line.is_empty():
		return from_command_line
	if GameSession.from_menus and not GameSession.room_file.is_empty():
		return GameSession.room_file
	if start_from_campaign:
		var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
		if campaign != null and not campaign.first_built_room().is_empty():
			return campaign.first_built_room()
	return level_path


func _load_level() -> bool:
	level_data = LevelData.load_from_file(level_path)
	if level_data == null:
		push_error("Room: could not load level '%s'" % level_path)
		return false
	_circuit = level_data.circuit
	_goal = level_data.make_goal()
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


func _build_parts() -> void:
	if pickup_scene == null:
		push_error("Room: pickup_scene is not set")
		return
	for entry: LevelPart in level_data.parts:
		var pickup: PartPickup = pickup_scene.instantiate() as PartPickup
		if pickup == null:
			push_error("Room: pickup_scene does not have a PartPickup root")
			return
		pickup.name = "Part_" + entry.id
		_part_container.add_child(pickup)
		pickup.setup(entry.id, entry.part, entry.position)
		_parts.append(pickup)


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
	_respawn.zapped.connect(zapped.emit)
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
	_carry.target_changed.connect(_target_tag.show_target)
	_respawn.setup(_player, _carry, level_data.spawn)


func _on_circuit_changed(solution: DcSolution, goal_met: bool) -> void:
	var readings: PackedStringArray = PackedStringArray()
	var met: Array[bool] = []
	for i: int in _goal.condition_count():
		readings.append(_goal.reading_text(i, solution))
		met.append(_goal.is_condition_met(i, solution))
	_hud.show_readings(readings, met, goal_met)
	if goal_met and not _was_met:
		_play_sound(&"connect")
	_was_met = goal_met
	_door.set_open(goal_met)


func _on_fade_finished() -> void:
	var event: InputEvent = _fade_buffer.take()
	if event != null:
		_unhandled_input(event)


func _on_door_entered() -> void:
	if _complete:
		return
	_complete = true
	if _player != null:
		_player.set_input_enabled(false)
		_player.play_victory()
	if _carry != null:
		_carry.set_enabled(false)
	var progress: Progress = GameSession.progress()
	progress.mark_completed(level_path)
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	_next_level = campaign.next_built_after(level_path) if campaign != null else ""
	if GameSession.from_menus and not _next_level.is_empty():
		var world: CampaignWorld = campaign.world_of(_next_level)
		if not progress.is_unlocked(world, world.find_room(_next_level)):
			_next_level = ""
	_hud.show_level_complete(not _next_level.is_empty(), GameSession.from_menus)
	_play_sound(&"win")
	level_completed.emit()


func _play_sound(sound: StringName) -> void:
	if _sfx != null:
		_sfx.play(sound)


## The plaque caption of condition `index`: its quantity symbol, followed by
## the element's label when the circuit gives it one ("I top").
func _row_caption(index: int) -> String:
	var symbol: String = _goal.symbol(index)
	var edge: LevelCircuit.Edge = _circuit.get_edge(_goal.conditions[index].element_id)
	if edge == null or edge.label.is_empty():
		return symbol
	return "%s %s" % [symbol, edge.label]


## True when the level's tiles contain at least one one-way platform.
func _has_one_way_platform() -> bool:
	for row: String in level_data.tile_rows:
		if row.contains(RoomTiles.CHAR_PLATFORM):
			return true
	return false


func _on_player_fell_out() -> void:
	_respawn.respawn_now()


func _on_object_touched(body: Node2D, sound: StringName) -> void:
	if body != _player or _complete:
		return
	if _respawn.zap():
		_play_sound(sound)


func _on_object_bounced(body: Node2D, surface_y: float, launch_speed: float) -> void:
	if body != _player or _complete or _player.is_frozen():
		return
	_player.bounce(surface_y, launch_speed)
	_play_sound(&"bounce")
