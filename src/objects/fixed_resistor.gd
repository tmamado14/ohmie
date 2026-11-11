class_name FixedResistor
extends Node2D
## A resistor soldered into the board by the level. Drawn centred on the
## midpoint of its edge inside a dark, steel-framed backing so it reads as
## "cannot be moved". Not interactable.

const FRAME_SIZE: Vector2 = Vector2(104, 72)
const BACKING_COLOR: Color = Color(0.04, 0.09, 0.12, 0.9)
const BORDER_COLOR: Color = Color("6b7a85")
const OUTLINE_COLOR: Color = Color("182e3a")
const BORDER_WIDTH: float = 3.0
const ICON_DIM: Color = Color(0.8, 0.8, 0.8)

var _icon: ResistorIcon = null


func _init() -> void:
	_icon = ResistorIcon.new()
	_icon.name = "Icon"
	_icon.modulate = ICON_DIM
	add_child(_icon)


func set_value(value: Rational) -> void:
	_icon.set_value(value)


func _draw() -> void:
	var rect: Rect2 = Rect2(-FRAME_SIZE * 0.5, FRAME_SIZE)
	draw_rect(rect, BACKING_COLOR, true)
	draw_rect(rect.grow(-1.0), OUTLINE_COLOR, false, 2.0)
	draw_rect(rect.grow(-1.0 - BORDER_WIDTH * 0.5 - 1.0), BORDER_COLOR, false, BORDER_WIDTH)
