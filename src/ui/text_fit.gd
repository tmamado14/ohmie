class_name TextFit
extends RefCounted
## Shrinks a label's font until its text fits the label's width.


## The largest font size from max_size down to min_size at which `text` is no
## wider than `width` in `font`; min_size when even that is too wide.
static func fit_font_size(font: Font, text: String, max_size: int, min_size: int, width: float) -> int:
	if font == null:
		return max_size
	var size: int = max_size
	while size > min_size:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			break
		size -= 1
	return size


## Gives `label` the largest font size (max_size down to min_size) at which its
## text fits `rect`'s width, and places it so the text line is centred on
## `rect`'s centre. A label is never shorter than its font's line, so a rect
## lower than the line would otherwise push the text down.
static func fit_centred(label: Label, rect: Rect2, max_size: int, min_size: int) -> void:
	var font: Font = label.get_theme_font(&"font")
	var size: int = fit_font_size(font, label.text, max_size, min_size, rect.size.x)
	label.add_theme_font_size_override(&"font_size", size)
	var height: float = maxf(rect.size.y, font.get_height(size) if font != null else rect.size.y)
	label.position = Vector2(rect.position.x, rect.get_center().y - height * 0.5)
	label.size = Vector2(rect.size.x, height)


## Sets `label`'s font size so its current text fits its current width. Call
## after the label is in the tree, so it uses its inherited theme font.
static func apply(label: Label, max_size: int, min_size: int) -> void:
	var font: Font = label.get_theme_font(&"font")
	var size: int = fit_font_size(font, label.text, max_size, min_size, label.size.x)
	label.add_theme_font_size_override(&"font_size", size)
