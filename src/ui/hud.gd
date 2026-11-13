class_name Hud
extends Control
## On-screen information: the goal readout on the plaque (top left), the
## mission sign (top right), the level title, a control hint, and the
## level-complete banner over a full-screen dim. The dim sits above the title
## and hint and below the readout, the mission sign and the banner.
##
## The plaque has two text rows. With one goal condition they read
## "GOAL  2 A" and "I  3/2 A" (the reading turns green while the condition is
## met). With two conditions each row reads "I  3/2 A  →  2 A", green while that
## condition is met. A caption may carry the meter's label ("I top").
## On every row the caption (left) and its value (right) share one font size,
## so they share a baseline; all rows use the largest size at which every
## row's caption, a gap of at least CAPTION_GAP and its value fit the
## parchment, so a long caption shrinks together with its value.
##
## The control hint reads "A/D move · Space jump (hold for higher) · E use ·
## R restart", with "S drop down" when the room has a one-way platform, "F flip"
## after "E use" when the room has a part that can be flipped, and "Esc map"
## when Esc opens the map (MenuStyle hint style).
##
## The line under the victory banner sits on a dark rounded strip sized to its
## text, so it stays readable over anything behind it.
##
## While a special reading (SHORT, ???, OL, ---) is on a board meter
## (set_board_special_readings) or a plaque row, one quiet caption directly
## above the control hint explains the most important one (ReadingLegend), in
## the hint style, shrinking to fit the screen width. It shows and hides with
## the reading.
##
## Only shows what it is given through its methods (plain strings and flags);
## it never looks at the board, the circuit or the level.

## Dark ink on the parchment; met rows and the mission heading turn green.
const COLOR_INK: Color = Color("2e1f1a")
const COLOR_MATCH: Color = Color("2f6b3a")
const MISSION_HEADING: String = "MISSION"
const MISSION_DONE_HEADING: String = "MISSION COMPLETE"
## The line under the victory banner.
const VICTORY_NEXT_ROOM: String = "Press E for the next room"
const VICTORY_PLAY_AGAIN: String = "Press R to play again"
## The same lines when the game was started through the menus (Esc opens the map).
const VICTORY_NEXT_ROOM_MAP: String = "E next room · R replay · Esc map"
const VICTORY_MAP_PLAY_AGAIN: String = "R replay · Esc map"
## The control hint's entries, in order. DROP_HINT is added when the room has a
## one-way platform, FLIP_HINT when it has a flippable part; the hint ends with
## MAP_HINT when Esc opens the map.
const MOVE_HINTS: PackedStringArray = ["A/D move", "Space jump (hold for higher)"]
const DROP_HINT: String = "S drop down"
const USE_HINT: String = "E use"
const FLIP_HINT: String = "F flip"
const RESTART_HINT: String = "R restart"
const MAP_HINT: String = " · Esc map"
## Caption of the target row when the goal has one condition.
const GOAL_CAPTION: String = "GOAL"
## Between the reading and the target on a two-condition row.
const ARROW: String = "  →  "
## Shown until the first reading arrives.
const NO_READING: String = "?"
const MAX_ROWS: int = 2

## Plaque row geometry (pixels inside the plaque texture rect).
const ROW_TOPS: Array[float] = [78.0, 103.0]
const ROW_HEIGHT: float = 25.0
const CAPTION_LEFT: float = 131.0
const VALUE_RIGHT: float = 296.0
## Least space between a caption and its value.
const CAPTION_GAP: float = 10.0
## Font size of every plaque row (caption and value alike), shrunk to fit.
const ROW_MAX_FONT_SIZE: int = 19
const ROW_MIN_FONT_SIZE: int = 10
## The mission line keeps MISSION_FONT_SIZE, shrinking to no less than
## MISSION_ONE_LINE_MIN_FONT_SIZE when that keeps it on one line; a longer
## mission wraps at MISSION_FONT_SIZE.
const MISSION_FONT_SIZE: int = 16
const MISSION_ONE_LINE_MIN_FONT_SIZE: int = 14
## The banner's "Circuit complete!" shrinks to fit the ribbon's flat panel.
const BANNER_MAX_FONT_SIZE: int = 28
const BANNER_MIN_FONT_SIZE: int = 18
## Width of the ribbon's flat panel available to the message (Victory/Banner/Message).
const BANNER_TEXT_WIDTH: float = 220.0
## The reading caption's line: offsets from the bottom of the screen (the hint
## line sits at -34..-8, so the caption ends where the hint begins, well below
## the floor at y 640), its side margin and the smallest font it may shrink to.
const LEGEND_OFFSET_TOP: float = -60.0
const LEGEND_OFFSET_BOTTOM: float = -34.0
const LEGEND_SIDE_MARGIN: float = 16.0
const LEGEND_MIN_FONT_SIZE: int = 12

var _mission_done: bool = false
var _board_specials: PackedStringArray = PackedStringArray()
var _legend: Label = null
var _symbols: PackedStringArray = PackedStringArray()
var _targets: PackedStringArray = PackedStringArray()
var _readings: PackedStringArray = PackedStringArray()
var _met: Array[bool] = []

@onready var _captions: Array[Label] = [$Readout/Row0Caption, $Readout/Row1Caption]
@onready var _values: Array[Label] = [$Readout/Row0Value, $Readout/Row1Value]
@onready var _mission_heading: Label = $MissionSign/Text/Heading
@onready var _mission_text: Label = $MissionSign/Text/Mission
@onready var _title: Label = $Title
@onready var _hint: Label = $Hint
@onready var _victory: Control = $Victory
@onready var _victory_dim: ColorRect = $VictoryDim
@onready var _victory_line: Label = $Victory/PlayAgain
@onready var _victory_message: Label = $Victory/Banner/Message


func _ready() -> void:
	_mission_text.add_theme_color_override(&"font_color", COLOR_INK)
	_set_mission_done(false)
	_victory.visible = false
	_victory_dim.visible = false
	_victory_message.add_theme_font_size_override(&"font_size", TextFit.fit_font_size(
			_victory_message.get_theme_font(&"font"), _victory_message.text, BANNER_MAX_FONT_SIZE,
			BANNER_MIN_FONT_SIZE, BANNER_TEXT_WIDTH))
	_add_legend()
	_render_rows()


func set_title(text: String) -> void:
	_title.text = text


## The one-line mission on the sign.
func set_mission(text: String) -> void:
	_mission_text.text = text
	var font: Font = _mission_text.get_theme_font(&"font")
	var width: float = _mission_text.get_parent_control().size.x
	var size: int = TextFit.fit_font_size(font, text, MISSION_FONT_SIZE, MISSION_ONE_LINE_MIN_FONT_SIZE, width)
	if _text_width(font, text, size) > width:
		size = MISSION_FONT_SIZE
	_mission_text.add_theme_font_size_override(&"font_size", size)


## Sets the control hint: "S drop down" only when `has_one_way_platform`,
## "F flip" only when `has_flippable_part`, and "Esc map" at the end only when
## `map_shown`.
func set_controls_hint(has_one_way_platform: bool, map_shown: bool, has_flippable_part: bool = false) -> void:
	var entries: PackedStringArray = MOVE_HINTS.duplicate()
	if has_one_way_platform:
		entries.append(DROP_HINT)
	entries.append(USE_HINT)
	if has_flippable_part:
		entries.append(FLIP_HINT)
	entries.append(RESTART_HINT)
	var text: String = MenuStyle.hint_text(entries)
	_hint.text = text + MAP_HINT if map_shown else text


func get_hint_text() -> String:
	return _hint.text


## The hint line's rectangle on screen.
func get_hint_rect() -> Rect2:
	return _hint.get_global_rect()


## The special readings the board's meters show now (CircuitBoard.special_readings_changed).
func set_board_special_readings(readings: PackedStringArray) -> void:
	_board_specials = readings.duplicate()
	_update_legend()


## The reading caption as shown ("" while hidden).
func get_legend_text() -> String:
	return _legend.text if _legend != null and _legend.visible else ""


## The caption's text on screen: its line, narrowed to the text's width.
func get_legend_rect() -> Rect2:
	if _legend == null:
		return Rect2()
	var rect: Rect2 = _legend.get_global_rect()
	var font: Font = _legend.get_theme_font(&"font")
	var width: float = _text_width(font, _legend.text, _legend.get_theme_font_size(&"font_size"))
	return Rect2(rect.get_center().x - width * 0.5, rect.position.y, width, rect.size.y)


## The plaque and the mission sign on screen (things a tag must not cover).
func get_panel_rects() -> Array[Rect2]:
	return [$Readout.get_global_rect(), $MissionSign.get_global_rect()]


## One entry per goal condition (at most MAX_ROWS are shown): its caption (the
## quantity symbol "I", "V", "R", "P", optionally followed by the element's
## label: "I top") and its target ("2 A", "1–3/2 V").
func set_goal_rows(symbols: PackedStringArray, targets: PackedStringArray) -> void:
	_symbols = symbols.duplicate()
	_targets = targets.duplicate()
	_readings = PackedStringArray()
	_met.clear()
	for i: int in _symbols.size():
		_readings.append(NO_READING)
		_met.append(false)
	_render_rows()


## The live reading of each condition ("3/2 A", "OL", "SHORT"), whether each
## is met, and whether the whole goal is met (mission sign done state).
func show_readings(readings: PackedStringArray, met: Array[bool], goal_met: bool) -> void:
	for i: int in mini(readings.size(), _readings.size()):
		_readings[i] = readings[i]
		_met[i] = i < met.size() and met[i]
	_render_rows()
	_set_mission_done(goal_met)
	_update_legend()


## Shows the victory banner; the line under it invites to the next room when
## there is one, otherwise to play again. With `map_lines` (the game was
## started through the menus) the line also offers Esc for the map.
func show_level_complete(has_next_room: bool = false, map_lines: bool = false) -> void:
	if map_lines:
		_victory_line.text = VICTORY_NEXT_ROOM_MAP if has_next_room else VICTORY_MAP_PLAY_AGAIN
	else:
		_victory_line.text = VICTORY_NEXT_ROOM if has_next_room else VICTORY_PLAY_AGAIN
	_fit_victory_line()
	_victory_dim.visible = true
	_victory.visible = true


func get_condition_count() -> int:
	return _symbols.size()


## The live reading of condition `index` as last shown, e.g. "3/2 A" or "OL".
func get_reading_text(index: int) -> String:
	return _readings[index] if index < _readings.size() else ""


## The target of condition `index`, e.g. "2 A".
func get_target_text(index: int) -> String:
	return _targets[index] if index < _targets.size() else ""


## True while condition `index` is shown as met (green).
func is_condition_met_shown(index: int) -> bool:
	return index < _met.size() and _met[index]


## Plaque row `row` as shown: its caption and its value text.
func get_row_caption(row: int) -> String:
	return _captions[row].text


func get_row_value(row: int) -> String:
	return _values[row].text


## The font colour of plaque row `row`'s value.
func get_row_value_color(row: int) -> Color:
	return _values[row].get_theme_color(&"font_color")


func get_victory_line() -> String:
	return _victory_line.text


## The mission sentence as currently shown on the sign.
func get_mission_text() -> String:
	return _mission_text.text


## True while the mission sign shows its "done" state.
func is_mission_complete_shown() -> bool:
	return _mission_done


func is_level_complete_shown() -> bool:
	return _victory.visible


func _render_rows() -> void:
	if _captions.is_empty():
		return
	var captions: PackedStringArray = ["", ""]
	var values: PackedStringArray = ["", ""]
	var met: Array[bool] = [false, false]
	if _symbols.size() == 1:
		captions = [GOAL_CAPTION, _symbols[0]]
		values = [_targets[0], _readings[0]]
		met = [false, _met[0]]
	else:
		for i: int in mini(_symbols.size(), MAX_ROWS):
			captions[i] = _symbols[i]
			values[i] = _readings[i] + ARROW + _targets[i]
			met[i] = _met[i]
	var font: Font = _values[0].get_theme_font(&"font")
	var font_size: int = _row_font_size(font, captions, values)
	for row: int in MAX_ROWS:
		_set_row(row, captions[row], values[row], met[row], font, font_size)


## The largest row font size at which every row's caption, CAPTION_GAP and
## value fit between CAPTION_LEFT and VALUE_RIGHT (ROW_MIN_FONT_SIZE at least).
func _row_font_size(font: Font, captions: PackedStringArray, values: PackedStringArray) -> int:
	var size: int = ROW_MAX_FONT_SIZE
	while size > ROW_MIN_FONT_SIZE:
		var fits: bool = true
		for row: int in captions.size():
			if _text_width(font, captions[row], size) + CAPTION_GAP + _text_width(font, values[row], size) \
					> VALUE_RIGHT - CAPTION_LEFT:
				fits = false
		if fits:
			break
		size -= 1
	return size


## Caption left-aligned at CAPTION_LEFT, value right-aligned at VALUE_RIGHT, both
## at `font_size` in labels of the same top and height (so one baseline).
func _set_row(row: int, caption: String, value: String, met: bool, font: Font, font_size: int) -> void:
	var caption_label: Label = _captions[row]
	var value_label: Label = _values[row]
	var caption_width: float = ceilf(_text_width(font, caption, font_size))
	caption_label.text = caption
	caption_label.add_theme_font_size_override(&"font_size", font_size)
	caption_label.position = Vector2(CAPTION_LEFT, ROW_TOPS[row])
	caption_label.size = Vector2(caption_width, ROW_HEIGHT)
	var value_left: float = CAPTION_LEFT + caption_width + CAPTION_GAP
	value_label.text = value
	value_label.add_theme_font_size_override(&"font_size", font_size)
	value_label.position = Vector2(value_left, ROW_TOPS[row])
	value_label.size = Vector2(VALUE_RIGHT - value_left, ROW_HEIGHT)
	value_label.add_theme_color_override(&"font_color", COLOR_MATCH if met else COLOR_INK)


static func _text_width(font: Font, text: String, font_size: int) -> float:
	if font == null or text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## The caption line in the hint style, directly above the hint and drawn
## just after it (so the victory dim covers both).
func _add_legend() -> void:
	_legend = MenuStyle.hint_label("")
	_legend.name = "ReadingLegend"
	_legend.anchor_left = 0.0
	_legend.anchor_right = 1.0
	_legend.anchor_top = 1.0
	_legend.anchor_bottom = 1.0
	_legend.offset_left = LEGEND_SIDE_MARGIN
	_legend.offset_right = -LEGEND_SIDE_MARGIN
	_legend.offset_top = LEGEND_OFFSET_TOP
	_legend.offset_bottom = LEGEND_OFFSET_BOTTOM
	_legend.visible = false
	add_child(_legend)
	move_child(_legend, _hint.get_index() + 1)


## Shows the caption for the most important special reading on the board or
## the plaque, or hides it when there is none.
func _update_legend() -> void:
	if _legend == null:
		return
	var on_screen: PackedStringArray = _board_specials.duplicate()
	on_screen.append_array(_readings)
	var caption: String = ReadingLegend.caption_for(on_screen)
	_legend.text = caption
	_legend.visible = not caption.is_empty()
	if caption.is_empty():
		return
	var width: float = get_viewport_rect().size.x - LEGEND_SIDE_MARGIN * 2.0
	_legend.add_theme_font_size_override(&"font_size", TextFit.fit_font_size(
			_legend.get_theme_font(&"font"), caption, MenuStyle.HINT_FONT_SIZE, LEGEND_MIN_FONT_SIZE, width))


## Sizes the victory line (and so its backing strip) to its text, centred.
func _fit_victory_line() -> void:
	_victory_line.reset_size()
	var width: float = _victory_line.get_combined_minimum_size().x
	_victory_line.offset_left = -width * 0.5
	_victory_line.offset_right = width * 0.5


func _set_mission_done(done: bool) -> void:
	_mission_done = done
	_mission_heading.text = MISSION_DONE_HEADING if done else MISSION_HEADING
	_mission_heading.add_theme_color_override(&"font_color", COLOR_MATCH if done else COLOR_INK)
