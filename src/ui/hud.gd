class_name Hud
extends Control
## On-screen information: the TARGET / EQUIVALENT readout, the level title, a
## control hint, and the level-complete banner over a full-screen dim. The
## dim sits above the title and hint and below the readout and the banner.
##
## Only shows what it is given through its methods; it never looks at the board.

const COLOR_TARGET: Color = Color("e8b339")
const COLOR_EQUIVALENT: Color = Color("47d1c0")
const COLOR_MATCH: Color = Color("6be36b")
const OHM_SUFFIX: String = " Ω"

@onready var _target_value: Label = $Readout/TargetValue
@onready var _equivalent_value: Label = $Readout/EquivalentValue
@onready var _title: Label = $Title
@onready var _victory: Control = $Victory
@onready var _victory_dim: ColorRect = $VictoryDim


func _ready() -> void:
	_target_value.add_theme_color_override(&"font_color", COLOR_TARGET)
	_equivalent_value.add_theme_color_override(&"font_color", COLOR_EQUIVALENT)
	_victory.visible = false
	_victory_dim.visible = false


func set_title(text: String) -> void:
	_title.text = text


func set_target(target: Rational) -> void:
	_target_value.text = target.to_text() + OHM_SUFFIX if target != null else "?"


## Shows a new reading; green when it matches the target.
func show_reading(result: CircuitResult, is_match: bool) -> void:
	_equivalent_value.text = format_reading(result)
	_equivalent_value.add_theme_color_override(&"font_color", COLOR_MATCH if is_match else COLOR_EQUIVALENT)


func show_level_complete() -> void:
	_victory_dim.visible = true
	_victory.visible = true


## The equivalent value as currently shown, for example "3/2 Ω" or "OPEN".
func get_equivalent_text() -> String:
	return _equivalent_value.text


func is_level_complete_shown() -> bool:
	return _victory.visible


## "1 Ω", "3/2 Ω" for OK; "OPEN", "???" or "ERROR" otherwise.
static func format_reading(result: CircuitResult) -> String:
	if result == null:
		return "?"
	if result.status == CircuitResult.Status.OK:
		return result.to_text() + OHM_SUFFIX
	return result.to_text()
