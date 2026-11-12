class_name MenuStyle
extends RefCounted
## The look shared by every menu screen: colours, the game's serif font (the
## bundled Libre Baskerville, whose numerals are full-height lining figures),
## the control-hint style, and small factories for labels in the two text
## styles (cream with an ink outline over art; dark ink on parchment).

const CREAM: Color = Color("f6e7c8")
const OUTLINE_INK: Color = Color("24180f")
const INK: Color = Color("2e1f1a")
const GOLD: Color = Color("f2c25a")
const GREEN: Color = Color("2f6b3a")
const WARM_SHADOW: Color = Color(0.45, 0.2, 0.07, 0.75)
const DIM_INK: Color = Color(0.18, 0.12, 0.1, 0.55)

## Libre Baskerville regular, bold and italic. Each falls back to a system serif
## for the few glyphs it lacks (Ω, arrows, ≥, ≤). Regular is also the
## project's default font (gui/theme/custom_font).
const REGULAR_FONT: Font = preload("res://resources/fonts/serif_regular.tres")
const BOLD_FONT: Font = preload("res://resources/fonts/serif_bold.tres")
const ITALIC_FONT: Font = preload("res://resources/fonts/serif_italic.tres")

## Control hints, on every screen and in the rooms: "Key action · Key action".
const HINT_SEPARATOR: String = " · "
const HINT_FONT_SIZE: int = 18
const HINT_OUTLINE: int = 6

## Brightness of an item that is not selected, and of the selected one.
const UNSELECTED_MODULATE: Color = Color(0.86, 0.84, 0.82)
const SELECTED_MODULATE: Color = Color(1.12, 1.1, 1.06)
const LOCKED_MODULATE: Color = Color(0.62, 0.6, 0.6)


static func font() -> Font:
	return REGULAR_FONT


static func bold_font() -> Font:
	return BOLD_FONT


static func italic_font() -> Font:
	return ITALIC_FONT


## One hint line from "Key action" entries, joined with HINT_SEPARATOR.
static func hint_text(entries: PackedStringArray) -> String:
	return HINT_SEPARATOR.join(entries)


## A control hint in the shared style (cream with an ink outline, HINT_FONT_SIZE).
static func hint_label(text: String) -> Label:
	return art_label(text, HINT_FONT_SIZE, HINT_OUTLINE)


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
