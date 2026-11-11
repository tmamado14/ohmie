class_name ArcLabel
extends Control
## Draws one line of text bent along a gentle upward arc: a warm drop shadow,
## a thick ink outline, then the fill, letter by letter. Centred in the control.
## Used for the title logotype.

@export var text: String = "":
	set(value):
		text = value
		queue_redraw()
@export var font_size: int = 160:
	set(value):
		font_size = value
		queue_redraw()
## Radius of the arc the baseline follows; larger is flatter.
@export var radius: float = 900.0:
	set(value):
		radius = value
		queue_redraw()
@export var fill_color: Color = MenuStyle.CREAM
@export var outline_color: Color = MenuStyle.OUTLINE_INK
@export var outline_size: int = 22
@export var shadow_color: Color = MenuStyle.WARM_SHADOW
@export var shadow_offset: Vector2 = Vector2(6, 10)
## Extra space between letters, in pixels.
@export var letter_spacing: float = 2.0

var _font: Font = null


func _ready() -> void:
	_font = MenuStyle.bold_font()
	queue_redraw()


func _draw() -> void:
	if _font == null or text.is_empty():
		return
	var advances: Array[float] = []
	var total: float = 0.0
	for i: int in text.length():
		var advance: float = _font.get_char_size(text.unicode_at(i), font_size).x
		advances.append(advance)
		total += advance + (letter_spacing if i < text.length() - 1 else 0.0)
	var ascent: float = _font.get_ascent(font_size)
	var descent: float = _font.get_descent(font_size)
	# Baseline at the vertical centre of the text box, arc centre straight below.
	var baseline: Vector2 = Vector2(size.x * 0.5, size.y * 0.5 + (ascent - descent) * 0.5)
	var arc_center: Vector2 = baseline + Vector2(0, radius)
	for pass_index: int in 3:
		var x: float = -total * 0.5
		for i: int in text.length():
			var advance: float = advances[i]
			var angle: float = (x + advance * 0.5) / radius
			var origin: Vector2 = arc_center + Vector2(sin(angle), -cos(angle)) * radius
			draw_set_transform(origin, angle, Vector2.ONE)
			var at: Vector2 = Vector2(-advance * 0.5, 0)
			var code: int = text.unicode_at(i)
			match pass_index:
				0:
					draw_set_transform(origin + shadow_offset, angle, Vector2.ONE)
					_font.draw_char_outline(get_canvas_item(), at, code, font_size, outline_size, shadow_color)
					_font.draw_char(get_canvas_item(), at, code, font_size, shadow_color)
				1:
					_font.draw_char_outline(get_canvas_item(), at, code, font_size, outline_size, outline_color)
				2:
					_font.draw_char(get_canvas_item(), at, code, font_size, fill_color)
			x += advance + letter_spacing
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
