class_name ResistorIcon
extends Node2D
## Draws one resistor value, centred on this node's origin (96x64 px on
## screen: the 192x128 icon art drawn at ART_SCALE).
##
## The seven values with art use their icon. Any other value falls back to the
## 1 ohm icon tinted grey with the value written over its baked label.

const ICON_DIR: String = "res://assets/interactive/resistors/"
## Rational.to_text() of a value -> icon file name part.
const ICON_NAMES: Dictionary = {
	"1/2": "0p5ohm", "1": "1ohm", "2": "2ohm", "3": "3ohm",
	"4": "4ohm", "6": "6ohm", "10": "10ohm",
}
const FALLBACK_NAME: String = "1ohm"
const FALLBACK_TINT: Color = Color(0.55, 0.55, 0.55)
const SIZE: Vector2 = Vector2(96, 64)
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## Covers the baked value plaque at the bottom of the icon (art x 57-135, y 100-124).
const FALLBACK_LABEL_RECT: Rect2 = Rect2(-24, 17, 48, 15)
const FALLBACK_LABEL_BACKGROUND: Color = Color("eed6b2")
const FALLBACK_LABEL_COLOR: Color = Color("2e1f1a")
const FALLBACK_FONT_SIZE: int = 11

var _sprite: Sprite2D = null
var _label: Label = null


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.scale = ART_SCALE
	add_child(_sprite)
	_label = Label.new()
	_label.name = "FallbackLabel"
	_label.position = FALLBACK_LABEL_RECT.position
	_label.size = FALLBACK_LABEL_RECT.size
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", FALLBACK_FONT_SIZE)
	_label.add_theme_color_override(&"font_color", FALLBACK_LABEL_COLOR)
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = FALLBACK_LABEL_BACKGROUND
	_label.add_theme_stylebox_override(&"normal", background)
	_label.visible = false
	add_child(_label)


## Shows `value`, or nothing when `value` is null.
func set_value(value: Rational) -> void:
	if value == null:
		_sprite.texture = null
		_label.visible = false
		return
	var key: String = value.to_text()
	if ICON_NAMES.has(key):
		_sprite.texture = _load_icon(ICON_NAMES[key])
		_sprite.self_modulate = Color.WHITE
		_label.visible = false
	else:
		_sprite.texture = _load_icon(FALLBACK_NAME)
		_sprite.self_modulate = FALLBACK_TINT
		_label.text = key + " Ω"
		_label.visible = true


static func _load_icon(file_part: String) -> Texture2D:
	return load(ICON_DIR + "resistor_%s.png" % file_part) as Texture2D
