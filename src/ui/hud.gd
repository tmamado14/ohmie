class_name Hud
extends Control
## On-screen information: the GOAL / reading readout on the plaque (top left), the
## mission sign (top right), the level title, a control hint, and the
## level-complete banner over a full-screen dim. The dim sits above the title
## and hint and below the readout, the mission sign and the banner.
##
## Only shows what it is given through its methods; it never looks at the
## board or the level.

## Dark ink on the parchment; the equivalent value and the mission heading
## turn green when the goal is met.
const COLOR_INK: Color = Color("2e1f1a")
const COLOR_MATCH: Color = Color("2f6b3a")
const MISSION_HEADING: String = "MISSION"
const MISSION_DONE_HEADING: String = "MISSION COMPLETE"
## The line under the victory banner.
const VICTORY_NEXT_ROOM: String = "Press E for the next room"
const VICTORY_PLAY_AGAIN: String = "Press R to play again"

var _mission_done: bool = false

@onready var _goal_value: Label = $Readout/TargetValue
@onready var _equivalent_value: Label = $Readout/EquivalentValue
@onready var _equivalent_caption: Label = $Readout/EquivalentCaption
@onready var _mission_heading: Label = $MissionSign/Text/Heading
@onready var _mission_text: Label = $MissionSign/Text/Mission
@onready var _title: Label = $Title
@onready var _victory: Control = $Victory
@onready var _victory_dim: ColorRect = $VictoryDim
@onready var _victory_line: Label = $Victory/PlayAgain


func _ready() -> void:
	_goal_value.add_theme_color_override(&"font_color", COLOR_INK)
	_equivalent_value.add_theme_color_override(&"font_color", COLOR_INK)
	_mission_text.add_theme_color_override(&"font_color", COLOR_INK)
	_set_mission_done(false)
	_victory.visible = false
	_victory_dim.visible = false


func set_title(text: String) -> void:
	_title.text = text


## Shows the goal in short on the plaque (e.g. "1 Ω"), the caption of the
## reading row (e.g. "R EQ" or "I") and the mission sentence on the sign.
func set_goal(goal_label: String, mission: String, reading_caption: String) -> void:
	_goal_value.text = goal_label
	_mission_text.text = mission
	_equivalent_caption.text = reading_caption


## Shows a new reading (e.g. "3/2 Ω" or "OPEN"); green, with the mission sign
## marked complete, while the goal is met.
func show_reading(reading_text: String, goal_met: bool) -> void:
	_equivalent_value.text = reading_text
	_equivalent_value.add_theme_color_override(&"font_color", COLOR_MATCH if goal_met else COLOR_INK)
	_set_mission_done(goal_met)


## Shows the victory banner; the line under it invites to the next room when
## there is one, otherwise to play again.
func show_level_complete(has_next_room: bool = false) -> void:
	_victory_line.text = VICTORY_NEXT_ROOM if has_next_room else VICTORY_PLAY_AGAIN
	_victory_dim.visible = true
	_victory.visible = true


## The equivalent value as currently shown, for example "3/2 Ω" or "OPEN".
func get_equivalent_text() -> String:
	return _equivalent_value.text


## The line under the victory banner as currently shown.
func get_victory_line() -> String:
	return _victory_line.text


## The caption of the reading row as currently shown, for example "R EQ" or "I".
func get_reading_caption() -> String:
	return _equivalent_caption.text


## The goal as currently shown on the plaque, for example "1 Ω".
func get_goal_text() -> String:
	return _goal_value.text


## The mission sentence as currently shown on the sign.
func get_mission_text() -> String:
	return _mission_text.text


## True while the mission sign shows its "done" state.
func is_mission_complete_shown() -> bool:
	return _mission_done


func is_level_complete_shown() -> bool:
	return _victory.visible


func _set_mission_done(done: bool) -> void:
	_mission_done = done
	_mission_heading.text = MISSION_DONE_HEADING if done else MISSION_HEADING
	_mission_heading.add_theme_color_override(&"font_color", COLOR_MATCH if done else COLOR_INK)
