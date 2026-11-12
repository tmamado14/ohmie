class_name LevelSelect
extends Control
## The level select of the chosen world (GameSession.world_id): a grid of
## room tiles (rooms 1-10 in two rows of five, the Overtime rooms in a row of
## their own) and a parchment panel showing the selected room's number, title
## and mission. Tile states come from the campaign (built or not) and the
## session's Progress (completed, unlocked). Arrows/WASD or the mouse select;
## Enter or a click starts a room that is completed or unlocked; a locked or
## unbuilt room shakes and buzzes. Esc goes back to the world select.

const PANEL: Texture2D = preload("res://assets/ui/decor/blank_puzzle_panel.png")
const CHECK: Texture2D = preload("res://assets/processed/ui_check.png")
const LOCK: Texture2D = preload("res://assets/processed/ui_lock.png")

const HINT_ENTRIES: PackedStringArray = ["Arrows choose", "Enter play", "Esc worlds"]
const OVERTIME_HEADING: String = "Overtime"
const OVERTIME_NOTE: String = "bonus rooms"
const LOCKED_TITLE: String = "???"
const UNBUILT_TITLE: String = "Coming soon"
const STATUS_COMPLETED: String = "Completed"
const STATUS_READY: String = "Press Enter to play"
const MISSION_CAPTION: String = "MISSION"
const STATUS_UNBUILT: String = "This room is still being built."
const COLOR_LOCKED: Color = Color("7a2e22")

# Layout (1280x720).
const HEADING_RECT: Rect2 = Rect2(0, 34, 1280, 72)
const SUBHEADING_RECT: Rect2 = Rect2(0, 100, 1280, 30)
const GRID_LEFT: float = 74.0
const GRID_TOP: float = 176.0
const COLUMNS: int = 5
const TILE_GAP: Vector2 = Vector2(22, 22)
const OVERTIME_LABEL_TOP: float = 438.0
const OVERTIME_TOP: float = 482.0
const OVERTIME_HEADING_FONT_SIZE: int = 30
## Space between "Overtime" and the "bonus rooms" note after it.
const OVERTIME_NOTE_GAP: float = 10.0
const PANEL_RECT: Rect2 = Rect2(718, 166, 520, 325)
## Text area inside the panel (panel-local, inside the parchment).
const INFO_RECT: Rect2 = Rect2(80, 46, 360, 232)
const OHMIE_START: Vector2 = Vector2(560, 656)
const HINT_RECT: Rect2 = Rect2(0, 664, 1280, 34)

var _campaign: Campaign = null
var _world: CampaignWorld = null
var _progress: Progress = null
var _tiles: Array[RoomTile] = []
var _rooms: Array[CampaignRoom] = []
## Tile indices per grid row, for arrow navigation.
var _rows: Array[PackedInt32Array] = []
var _titles: Dictionary = {}  # level file -> title
var _missions: Dictionary = {}  # level file -> mission
var _selected: int = 0
## Enter or Esc pressed while the screen is still fading in is acted on when it ends.
var _fade_buffer: FadeInputBuffer = FadeInputBuffer.new(["menu_accept", "menu_back"])

var _info_caption: Label = null
var _info_title: Label = null
var _info_mission: Label = null
var _status_icon: TextureRect = null
var _status_text: Label = null


func _ready() -> void:
	_campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	_progress = GameSession.progress()
	if _campaign != null:
		_world = _campaign.get_world(GameSession.world_id)
		if _world == null and not _campaign.worlds.is_empty():
			_world = _campaign.worlds[0]
	_build_heading()
	_build_panel()
	if _world != null:
		_read_levels()
		_build_tiles()
	var ohmie: TitleOhmie = TitleOhmie.new()
	ohmie.name = "Ohmie"
	ohmie.position = OHMIE_START
	ohmie.run_distance = 190.0
	add_child(ohmie)
	var hint: Label = MenuStyle.hint_label(MenuStyle.hint_text(HINT_ENTRIES))
	hint.name = "Hint"
	MenuStyle.place(hint, HINT_RECT)
	add_child(hint)
	_select(_initial_selection(), false)
	MenuSound.play_music(self)
	ScreenFade.connect_finished(get_tree(), _on_fade_finished)


func _unhandled_input(event: InputEvent) -> void:
	if _tiles.is_empty():
		return
	if ScreenFade.is_busy(get_tree()):
		if _fade_buffer.offer(get_tree(), event):
			get_viewport().set_input_as_handled()
		return
	var handled: bool = true
	if event.is_action_pressed("menu_left"):
		_move(-1, 0)
	elif event.is_action_pressed("menu_right"):
		_move(1, 0)
	elif event.is_action_pressed("menu_up"):
		_move(0, -1)
	elif event.is_action_pressed("menu_down"):
		_move(0, 1)
	elif event.is_action_pressed("menu_accept"):
		_start_selected()
	elif event.is_action_pressed("menu_back"):
		MenuSound.play(self, MenuSound.SELECT)
		ScreenFade.go_to(get_tree(), ScreenFade.WORLD_SELECT)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## The level file of the selected tile ("" when there is none).
func get_selected_file() -> String:
	return _rooms[_selected].file if _selected < _rooms.size() else ""


## The state of the tile of level file `file`, or -1 when it has no tile.
func get_tile_state(file: String) -> int:
	for i: int in _rooms.size():
		if _rooms[i].file == file:
			return _tiles[i].get_state()
	return -1


## Selects the tile of level file `file`. Returns false when it has no tile.
func select_room(file: String) -> bool:
	for i: int in _rooms.size():
		if _rooms[i].file == file:
			_select(i, true)
			return true
	return false


## The panel's title line ("7  Half and Half") and mission line as shown.
func get_info_title() -> String:
	return _info_title.text


func get_info_mission() -> String:
	return _info_mission.text


func _build_heading() -> void:
	var heading_text: String = _world.name if _world != null else ""
	var heading: Label = MenuStyle.art_label(heading_text, 56, 10, MenuStyle.bold_font())
	heading.name = "Heading"
	MenuStyle.place(heading, HEADING_RECT)
	add_child(heading)
	if _world == null:
		return
	var sub: Label = MenuStyle.art_label("World %d  ·  %s" % [_world.number, _world.topic], 22, 5,
			MenuStyle.italic_font())
	sub.name = "Subheading"
	MenuStyle.place(sub, SUBHEADING_RECT)
	add_child(sub)


func _build_panel() -> void:
	var panel: TextureRect = TextureRect.new()
	panel.name = "InfoPanel"
	panel.texture = PANEL
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(panel, PANEL_RECT)
	add_child(panel)
	var info: VBoxContainer = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override(&"separation", 6)
	MenuStyle.place(info, INFO_RECT)
	panel.add_child(info)
	_info_title = MenuStyle.ink_label("", 31, MenuStyle.bold_font())
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_title.add_theme_constant_override(&"line_spacing", -4)
	info.add_child(_info_title)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(MenuStyle.INK, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rule)
	_info_caption = MenuStyle.ink_label("", 15, MenuStyle.bold_font())
	_info_caption.add_theme_color_override(&"font_color", Color(MenuStyle.INK, 0.65))
	info.add_child(_info_caption)
	_info_mission = MenuStyle.ink_label("", 24, MenuStyle.italic_font())
	_info_mission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_mission)
	var status: HBoxContainer = HBoxContainer.new()
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override(&"separation", 8)
	info.add_child(status)
	_status_icon = TextureRect.new()
	_status_icon.custom_minimum_size = Vector2(28, 28)
	_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(_status_icon)
	_status_text = MenuStyle.ink_label("", 20, MenuStyle.bold_font())
	status.add_child(_status_text)


## Reads the title and mission of every built room from its level file.
func _read_levels() -> void:
	for room: CampaignRoom in _world.rooms:
		if not room.built:
			continue
		var data: LevelData = LevelData.load_from_file(room.file)
		if data != null:
			_titles[room.file] = data.title
			_missions[room.file] = data.mission


func _build_tiles() -> void:
	var regular: Array[CampaignRoom] = _world.regular_rooms()
	var overtime: Array[CampaignRoom] = _world.overtime_rooms()
	for i: int in regular.size():
		var row_index: int = floori(float(i) / COLUMNS)
		var at: Vector2 = Vector2(GRID_LEFT + (i % COLUMNS) * (RoomTile.TILE_SIZE.x + TILE_GAP.x),
				GRID_TOP + row_index * (RoomTile.TILE_SIZE.y + TILE_GAP.y))
		_add_tile(regular[i], at, row_index)
	if overtime.is_empty():
		return
	var heading: Label = MenuStyle.art_label(OVERTIME_HEADING, OVERTIME_HEADING_FONT_SIZE, 7, MenuStyle.bold_font())
	heading.name = "OvertimeHeading"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var heading_width: float = ceilf(MenuStyle.bold_font().get_string_size(OVERTIME_HEADING,
			HORIZONTAL_ALIGNMENT_LEFT, -1, OVERTIME_HEADING_FONT_SIZE).x)
	MenuStyle.place(heading, Rect2(GRID_LEFT, OVERTIME_LABEL_TOP, heading_width, 36))
	add_child(heading)
	var note: Label = MenuStyle.art_label(OVERTIME_NOTE, 19, 5, MenuStyle.italic_font())
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuStyle.place(note, Rect2(GRID_LEFT + heading_width + OVERTIME_NOTE_GAP, OVERTIME_LABEL_TOP + 6, 200, 30))
	add_child(note)
	var row: int = ceili(regular.size() / float(COLUMNS))
	for i: int in overtime.size():
		var at: Vector2 = Vector2(GRID_LEFT + i * (RoomTile.TILE_SIZE.x + TILE_GAP.x), OVERTIME_TOP)
		_add_tile(overtime[i], at, row)


func _add_tile(room: CampaignRoom, at: Vector2, row: int) -> void:
	var tile: RoomTile = RoomTile.new()
	tile.name = "Room%d" % room.number
	add_child(tile)
	tile.position = at
	tile.setup(room.number, _state_of(room))
	var index: int = _tiles.size()
	tile.hovered.connect(_on_tile_hovered.bind(index))
	tile.clicked.connect(_on_tile_clicked.bind(index))
	_tiles.append(tile)
	_rooms.append(room)
	while _rows.size() <= row:
		_rows.append(PackedInt32Array())
	_rows[row].append(index)


func _state_of(room: CampaignRoom) -> RoomTile.State:
	if not room.built:
		return RoomTile.State.UNBUILT
	if _progress.is_completed(room.file):
		return RoomTile.State.COMPLETED
	if _progress.is_unlocked(_world, room):
		return RoomTile.State.UNLOCKED
	return RoomTile.State.LOCKED


## The room the player came back from, else the first unlocked room not yet
## completed, else the first room that can be started, else the first tile.
func _initial_selection() -> int:
	for i: int in _rooms.size():
		if _rooms[i].file == GameSession.room_file:
			return i
	for i: int in _tiles.size():
		if _tiles[i].get_state() == RoomTile.State.UNLOCKED:
			return i
	for i: int in _tiles.size():
		if _tiles[i].can_start():
			return i
	return 0


func _move(dx: int, dy: int) -> void:
	var row: int = 0
	var column: int = 0
	for r: int in _rows.size():
		var found: int = _rows[r].find(_selected)
		if found >= 0:
			row = r
			column = found
	if dy != 0:
		row = clampi(row + dy, 0, _rows.size() - 1)
		column = mini(column, _rows[row].size() - 1)
	else:
		column = clampi(column + dx, 0, _rows[row].size() - 1)
	_select(_rows[row][column], true)


func _select(index: int, with_sound: bool) -> void:
	if _tiles.is_empty():
		return
	index = clampi(index, 0, _tiles.size() - 1)
	if with_sound and index != _selected:
		MenuSound.play(self, MenuSound.SELECT)
	_selected = index
	for i: int in _tiles.size():
		_tiles[i].set_selected(i == _selected)
	move_child(_tiles[_selected], -1)
	_show_info(_rooms[_selected], _tiles[_selected].get_state())


func _show_info(room: CampaignRoom, state: RoomTile.State) -> void:
	var can_start: bool = state == RoomTile.State.COMPLETED or state == RoomTile.State.UNLOCKED
	var group: String = (OVERTIME_HEADING + " room").to_upper() if room.overtime else ""
	_info_caption.text = MISSION_CAPTION if can_start else group
	_info_caption.visible = not _info_caption.text.is_empty()
	var title: String = _titles.get(room.file, LOCKED_TITLE)
	var mission: String = _missions.get(room.file, "")
	match state:
		RoomTile.State.COMPLETED:
			_set_info(room, title, mission, CHECK, STATUS_COMPLETED, MenuStyle.GREEN)
		RoomTile.State.UNLOCKED:
			_set_info(room, title, mission, null, STATUS_READY, MenuStyle.INK)
		RoomTile.State.LOCKED:
			_set_info(room, LOCKED_TITLE, _locked_reason(room), LOCK, "Locked", COLOR_LOCKED)
		RoomTile.State.UNBUILT:
			_set_info(room, UNBUILT_TITLE, STATUS_UNBUILT, LOCK, "Not open yet", COLOR_LOCKED)


func _set_info(room: CampaignRoom, title: String, mission: String, icon: Texture2D, status: String,
		status_color: Color) -> void:
	_info_title.text = "%d  %s" % [room.number, title]
	_info_mission.text = mission
	_status_icon.texture = icon
	_status_icon.visible = icon != null
	_status_text.text = status
	_status_text.add_theme_color_override(&"font_color", status_color)


func _locked_reason(room: CampaignRoom) -> String:
	if room.overtime:
		var last: CampaignRoom = _world.last_regular_room()
		if last != null and last.built:
			return "Finish room %d to unlock Overtime." % last.number
		return "Finish every room to unlock Overtime."
	var previous: CampaignRoom = _world.previous_built_room(room)
	if previous != null:
		return "Finish room %d to unlock." % previous.number
	return "Locked."


func _start_selected() -> void:
	var tile: RoomTile = _tiles[_selected]
	if not tile.can_start():
		tile.shake()
		MenuSound.play(self, MenuSound.DENIED)
		return
	MenuSound.play(self, MenuSound.CONFIRM)
	GameSession.world_id = _world.id
	GameSession.room_file = _rooms[_selected].file
	ScreenFade.go_to(get_tree(), ScreenFade.GAME)


func _on_fade_finished() -> void:
	var event: InputEvent = _fade_buffer.take()
	if event != null:
		_unhandled_input(event)


func _on_tile_hovered(index: int) -> void:
	if not ScreenFade.is_busy(get_tree()):
		_select(index, true)


func _on_tile_clicked(index: int) -> void:
	if ScreenFade.is_busy(get_tree()):
		return
	_select(index, true)
	_start_selected()
