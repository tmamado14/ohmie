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
## condition is met. Values shrink to fit the parchment.
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
const SINGLE_CAPTION_WIDTH: float = 59.0
const MULTI_CAPTION_WIDTH: float = 22.0
const VALUE_MAX_FONT_SIZE: int = 21
const VALUE_MIN_FONT_SIZE: int = 10

var _mission_done: bool = false
var _symbols: PackedStringArray = PackedStringArray()
var _targets: PackedStringArray = PackedStringArray()
var _readings: PackedStringArray = PackedStringArray()
var _met: Array[bool] = []

@onready var _captions: Array[Label] = [$Readout/Row0Caption, $Readout/Row1Caption]
@onready var _values: Array[Label] = [$Readout/Row0Value, $Readout/Row1Value]
@onready var _mission_heading: Label = $MissionSign/Text/Heading
@onready var _mission_text: Label = $MissionSign/Text/Mission
@onready var _title: Label = $Title
@onready var _victory: Control = $Victory
@onready var _victory_dim: ColorRect = $VictoryDim
@onready var _victory_line: Label = $Victory/PlayAgain


func _ready() -> void:
	_mission_text.add_theme_color_override(&"font_color", COLOR_INK)
	_set_mission_done(false)
	_victory.visible = false
	_victory_dim.visible = false
	_render_rows()


func set_title(text: String) -> void:
	_title.text = text


## The one-line mission on the sign.
func set_mission(text: String) -> void:
	_mission_text.text = text


## One entry per goal condition (at most MAX_ROWS are shown): its quantity
## symbol ("I", "V", "R", "P") and its target ("2 A", "1–3/2 V").
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


## Shows the victory banner; the line under it invites to the next room when
## there is one, otherwise to play again.
func show_level_complete(has_next_room: bool = false) -> void:
	_victory_line.text = VICTORY_NEXT_ROOM if has_next_room else VICTORY_PLAY_AGAIN
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
	for row: int in MAX_ROWS:
		_set_row(row, "", "", false, MULTI_CAPTION_WIDTH)
	if _symbols.size() == 1:
		_set_row(0, GOAL_CAPTION, _targets[0], false, SINGLE_CAPTION_WIDTH)
		_set_row(1, _symbols[0], _readings[0], _met[0], SINGLE_CAPTION_WIDTH)
		return
	for i: int in mini(_symbols.size(), MAX_ROWS):
		_set_row(i, _symbols[i], _readings[i] + ARROW + _targets[i], _met[i], MULTI_CAPTION_WIDTH)


func _set_row(row: int, caption: String, value: String, met: bool, caption_width: float) -> void:
	var caption_label: Label = _captions[row]
	var value_label: Label = _values[row]
	caption_label.text = caption
	caption_label.position = Vector2(CAPTION_LEFT, ROW_TOPS[row])
	caption_label.size = Vector2(caption_width, ROW_HEIGHT)
	value_label.text = value
	value_label.position = Vector2(CAPTION_LEFT + caption_width, ROW_TOPS[row])
	value_label.size = Vector2(VALUE_RIGHT - CAPTION_LEFT - caption_width, ROW_HEIGHT)
	value_label.add_theme_color_override(&"font_color", COLOR_MATCH if met else COLOR_INK)
	TextFit.apply(value_label, VALUE_MAX_FONT_SIZE, VALUE_MIN_FONT_SIZE)


func _set_mission_done(done: bool) -> void:
	_mission_done = done
	_mission_heading.text = MISSION_DONE_HEADING if done else MISSION_HEADING
	_mission_heading.add_theme_color_override(&"font_color", COLOR_MATCH if done else COLOR_INK)
