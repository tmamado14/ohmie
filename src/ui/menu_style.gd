class_name MenuStyle
extends RefCounted
## The look shared by every menu screen: colours, the serif font the HUD uses,
## and small factories for labels in the two text styles (cream with an ink
## outline over art; dark ink on parchment).

const CREAM: Color = Color("f6e7c8")
const OUTLINE_INK: Color = Color("24180f")
const INK: Color = Color("2e1f1a")
const GOLD: Color = Color("f2c25a")
const GREEN: Color = Color("2f6b3a")
const WARM_SHADOW: Color = Color(0.45, 0.2, 0.07, 0.75)
const DIM_INK: Color = Color(0.18, 0.12, 0.1, 0.55)
const FONT_NAMES: PackedStringArray = ["Georgia", "Times New Roman", "serif"]

## Brightness of an item that is not selected, and of the selected one.
const UNSELECTED_MODULATE: Color = Color(0.86, 0.84, 0.82)
const SELECTED_MODULATE: Color = Color(1.12, 1.1, 1.06)
const LOCKED_MODULATE: Color = Color(0.62, 0.6, 0.6)

static var _font: SystemFont = null
static var _bold_font: SystemFont = null
static var _italic_font: SystemFont = null


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = FONT_NAMES
	return _font


static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = SystemFont.new()
		_bold_font.font_names = FONT_NAMES
		_bold_font.font_weight = 700
	return _bold_font


static func italic_font() -> Font:
	if _italic_font == null:
		_italic_font = SystemFont.new()
		_italic_font.font_names = FONT_NAMES
		_italic_font.font_italic = true
	return _italic_font


## Cream text with a dark ink outline and a soft shadow, for text over art.
static func art_label(text: String, size: int, outline: int = 6, label_font: Font = null) -> Label:
	var label: Label = _label(text, size, label_font)
	label.add_theme_color_override(&"font_color", CREAM)
	label.add_theme_color_override(&"font_outline_color", OUTLINE_INK)
	label.add_theme_constant_override(&"outline_size", outline)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override(&"shadow_offset_x", 0)
	label.add_theme_constant_override(&"shadow_offset_y", 3)
	label.add_theme_constant_override(&"shadow_outline_size", outline)
	return label


## Dark ink text, for parchment and wood.
static func ink_label(text: String, size: int, label_font: Font = null) -> Label:
	var label: Label = _label(text, size, label_font)
	label.add_theme_color_override(&"font_color", INK)
	return label


static func _label(text: String, size: int, label_font: Font) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", label_font if label_font != null else font())
	label.add_theme_font_size_override(&"font_size", size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Places `control` at `rect` (position and size) with no anchoring.
static func place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
