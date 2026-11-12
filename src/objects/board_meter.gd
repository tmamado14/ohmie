class_name BoardMeter
extends Node2D
## A fixed ammeter, voltmeter or ohmmeter on the board, centred on the midpoint
## of its edge (104x72 on screen), with its live reading written in the display
## window. The text shrinks until it fits the window. Not interactable.

const TEXTURES: Dictionary = {
	"ammeter": preload("res://assets/processed/meter_ammeter.png"),
	"voltmeter": preload("res://assets/processed/meter_voltmeter.png"),
	"ohmmeter": preload("res://assets/processed/meter_ohmmeter.png"),
}
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## The display window's text rectangle relative to the meter centre: (18, 39,
## 68, 20) on screen from the 104x72 meter's top-left (docs/ASSETS.md).
const TEXT_RECT: Rect2 = Rect2(-34, 3, 68, 20)
const TEXT_COLOR: Color = Color("24180f")
const TEXT_FONT: Font = preload("res://resources/fonts/serif_bold.tres")
const MAX_FONT_SIZE: int = 18
const MIN_FONT_SIZE: int = 8

var meter_id: String = ""

var _sprite: Sprite2D = null
var _label: Label = null


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.scale = ART_SCALE
	add_child(_sprite)
	_label = Label.new()
	_label.name = "Reading"
	_label.position = TEXT_RECT.position
	_label.size = TEXT_RECT.size
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", TEXT_COLOR)
	_label.add_theme_font_override(&"font", TEXT_FONT)
	_label.add_theme_font_size_override(&"font_size", MAX_FONT_SIZE)
	add_child(_label)


## `type`: "ammeter", "voltmeter" or "ohmmeter" (LevelCircuit.TYPE_*).
func setup(id: String, type: String) -> void:
	meter_id = id
	_sprite.texture = TEXTURES.get(type, null)
	if _sprite.texture == null:
		push_error("BoardMeter: unknown meter type '%s'" % type)


## Shows `text` in the window, shrinking the font until it fits.
func set_reading(text: String) -> void:
	_label.text = text
	TextFit.fit_centred(_label, TEXT_RECT, MAX_FONT_SIZE, MIN_FONT_SIZE)


func get_reading() -> String:
	return _label.text
