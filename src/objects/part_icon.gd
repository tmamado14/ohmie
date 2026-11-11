class_name PartIcon
extends Node2D
## Draws one carried part, centred on this node's origin (96x64 px on screen:
## the 192x128 art drawn at ART_SCALE).
##
## Resistors with a value that has art use their icon. Any other resistor uses
## the blank resistor with its value written in the plaque; a battery uses the
## battery art with its voltage written in the plaque. The battery art's plus
## end is on its LEFT; set_flipped(true) mirrors the art (not the text).

const ICON_DIR: String = "res://assets/interactive/resistors/"
## Rational.to_text() of a resistance -> icon file name part.
const ICON_NAMES: Dictionary = {
	"1/2": "0p5ohm", "1": "1ohm", "2": "2ohm", "3": "3ohm",
	"4": "4ohm", "6": "6ohm", "10": "10ohm",
}
const BLANK_RESISTOR_TEXTURE: Texture2D = preload("res://assets/processed/part_resistor_blank.png")
const BATTERY_TEXTURE: Texture2D = preload("res://assets/processed/part_battery.png")
const SIZE: Vector2 = Vector2(96, 64)
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## The plaque's text rectangle relative to the icon centre: (30.5, 49, 36, 11.5)
## on screen from the icon's top-left (docs/ASSETS.md).
const LABEL_RECT: Rect2 = Rect2(-17.5, 17, 36, 11.5)
const LABEL_COLOR: Color = Color("33241d")
const LABEL_MAX_FONT_SIZE: int = 11
const LABEL_MIN_FONT_SIZE: int = 6

var _sprite: Sprite2D = null
var _label: Label = null
var _part: Part = null


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.scale = ART_SCALE
	add_child(_sprite)
	_label = Label.new()
	_label.name = "ValueLabel"
	_label.position = LABEL_RECT.position
	_label.size = LABEL_RECT.size
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", LABEL_MAX_FONT_SIZE)
	_label.add_theme_color_override(&"font_color", LABEL_COLOR)
	_label.visible = false
	add_child(_label)


## Shows `part`, or nothing when `part` is null.
func set_part(part: Part) -> void:
	_part = part
	if part == null:
		_sprite.texture = null
		_label.visible = false
		return
	var key: String = part.value.to_text()
	if not part.is_battery() and ICON_NAMES.has(key):
		_sprite.texture = load(ICON_DIR + "resistor_%s.png" % ICON_NAMES[key]) as Texture2D
		_label.visible = false
		return
	_sprite.texture = BATTERY_TEXTURE if part.is_battery() else BLANK_RESISTOR_TEXTURE
	_label.text = part.label()
	_label.visible = true
	TextFit.fit_centred(_label, LABEL_RECT, LABEL_MAX_FONT_SIZE, LABEL_MIN_FONT_SIZE)


## The part shown, or null.
func get_part() -> Part:
	return _part


## Mirrors the art horizontally (the value text stays readable).
func set_flipped(flipped: bool) -> void:
	_sprite.flip_h = flipped


func is_flipped() -> bool:
	return _sprite.flip_h


## The text drawn on the plaque ("" when the art carries its own value).
func get_label_text() -> String:
	return _label.text if _label.visible else ""
