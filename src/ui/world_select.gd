class_name WorldSelect
extends Control
## The world select: "Choose a World" over a row of five world cards from the
## campaign. Left/right or the mouse select; Enter or a click opens an
## unlocked world's level select; a locked world shakes and buzzes. Esc goes
## back to the title.

const HEADING: String = "Choose a World"
const HINT_ENTRIES: PackedStringArray = ["Arrows choose", "Enter open", "Esc back"]
## Background art per world id, used for the card thumbnails.
const THUMBNAILS: Dictionary = {
	"old_workshop": "res://assets/environment/old_workshop_background_1920x1080.png",
	"copper_foundry": "res://assets/worlds/level_02_copper_foundry/background_1920x1080.png",
	"substation_switchyard": "res://assets/worlds/level_03_substation_switchyard/background_1920x1080.png",
	"signal_clocktower": "res://assets/worlds/level_04_signal_clocktower/background_1920x1080.png",
	"high_voltage_transmitter": "res://assets/worlds/level_05_high_voltage_transmitter/background_1920x1080.png",
}
const FALLBACK_THUMBNAIL: String = "res://assets/environment/old_workshop_background_1920x1080.png"

const HEADING_RECT: Rect2 = Rect2(0, 64, 1280, 80)
const HEADING_FONT_SIZE: int = 58
const SUBHEADING_RECT: Rect2 = Rect2(0, 140, 1280, 34)
const SUBHEADING: String = "Five worlds of circuits. One small resistor."
const CARD_TOP: float = 228.0
const CARD_GAP: float = 22.0
const HINT_RECT: Rect2 = Rect2(0, 664, 1280, 34)

var _campaign: Campaign = null
var _cards: Array[WorldCard] = []
var _worlds: Array[CampaignWorld] = []
var _selected: int = 0
## Enter or Esc pressed while the screen is still fading in is acted on when it ends.
var _fade_buffer: FadeInputBuffer = FadeInputBuffer.new(["menu_accept", "menu_back"])


func _ready() -> void:
	_campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	_build_heading()
	if _campaign != null:
		_build_cards()
	var hint: Label = MenuStyle.hint_label(MenuStyle.hint_text(HINT_ENTRIES))
	hint.name = "Hint"
	MenuStyle.place(hint, HINT_RECT)
	add_child(hint)
	var start: int = 0
	for i: int in _worlds.size():
		if _worlds[i].id == GameSession.world_id:
			start = i
	_select(start, false)
	MenuSound.play_music(self)
	ScreenFade.connect_finished(get_tree(), _on_fade_finished)


func _unhandled_input(event: InputEvent) -> void:
	if ScreenFade.is_busy(get_tree()):
		if _fade_buffer.offer(get_tree(), event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_left"):
		get_viewport().set_input_as_handled()
		_select(_selected - 1, true)
	elif event.is_action_pressed("menu_right"):
		get_viewport().set_input_as_handled()
		_select(_selected + 1, true)
	elif event.is_action_pressed("menu_accept"):
		get_viewport().set_input_as_handled()
		_open_selected()
	elif event.is_action_pressed("menu_back"):
		get_viewport().set_input_as_handled()
		MenuSound.play(self, MenuSound.SELECT)
		ScreenFade.go_to(get_tree(), ScreenFade.TITLE)


func get_card_count() -> int:
	return _cards.size()


func get_selected_index() -> int:
	return _selected


## The id of the selected world ("" when there is none).
func get_selected_world_id() -> String:
	return _worlds[_selected].id if _selected < _worlds.size() else ""


## Selects card `index` (clamped), as the arrow keys would.
func select(index: int) -> void:
	_select(index, true)


func _build_heading() -> void:
	var heading: Label = MenuStyle.art_label(HEADING, HEADING_FONT_SIZE, 10, MenuStyle.bold_font())
	heading.name = "Heading"
	MenuStyle.place(heading, HEADING_RECT)
	add_child(heading)
	var sub: Label = MenuStyle.art_label(SUBHEADING, 22, 5, MenuStyle.italic_font())
	sub.name = "Subheading"
	MenuStyle.place(sub, SUBHEADING_RECT)
	add_child(sub)


func _build_cards() -> void:
	var progress: Progress = GameSession.progress()
	_worlds = _campaign.worlds.duplicate()
	var row_width: float = _worlds.size() * WorldCard.CARD_SIZE.x + maxf(_worlds.size() - 1, 0) * CARD_GAP
	var left: float = get_viewport_rect().size.x * 0.5 - row_width * 0.5
	for i: int in _worlds.size():
		var world: CampaignWorld = _worlds[i]
		var card: WorldCard = WorldCard.new()
		card.name = "Card_" + world.id
		add_child(card)
		card.position = Vector2(left + i * (WorldCard.CARD_SIZE.x + CARD_GAP), CARD_TOP)
		var path: String = THUMBNAILS.get(world.id, FALLBACK_THUMBNAIL)
		card.setup(world, load(path) as Texture2D, progress.completed_count(world), world.rooms.size(),
				not progress.is_world_open(world))
		card.hovered.connect(_on_card_hovered.bind(i))
		card.clicked.connect(_on_card_clicked.bind(i))
		_cards.append(card)


func _select(index: int, with_sound: bool) -> void:
	if _cards.is_empty():
		return
	index = clampi(index, 0, _cards.size() - 1)
	if with_sound and index != _selected:
		MenuSound.play(self, MenuSound.SELECT)
	_selected = index
	for i: int in _cards.size():
		_cards[i].set_selected(i == _selected)
	# Draw the selected card last so its glow sits over its neighbours.
	move_child(_cards[_selected], -1)


func _open_selected() -> void:
	if _cards.is_empty():
		return
	var card: WorldCard = _cards[_selected]
	if card.is_locked():
		card.shake()
		MenuSound.play(self, MenuSound.DENIED)
		return
	MenuSound.play(self, MenuSound.CONFIRM)
	GameSession.world_id = _worlds[_selected].id
	ScreenFade.go_to(get_tree(), ScreenFade.LEVEL_SELECT)


func _on_fade_finished() -> void:
	var event: InputEvent = _fade_buffer.take()
	if event != null:
		_unhandled_input(event)


func _on_card_hovered(index: int) -> void:
	if not ScreenFade.is_busy(get_tree()):
		_select(index, true)


func _on_card_clicked(index: int) -> void:
	if ScreenFade.is_busy(get_tree()):
		return
	_select(index, true)
	_open_selected()
