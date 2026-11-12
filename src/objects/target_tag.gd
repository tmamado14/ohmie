class_name TargetTag
extends Node2D
## The small name tag over the highlighted target: a parchment-coloured
## rounded label with dark ink text ("3 Ω", "6 V", "empty"). Ohmie draws in
## front of slots and loose parts, so the tag names what he is standing at.
##
## It floats above the target and clear of Ohmie's head (and of the part he
## carries), and stays on screen. Exists only while there is a target: the
## room connects PlayerCarry.target_changed to show_target(). Looks only.

const FONT: Font = preload("res://resources/fonts/serif_bold.tres")
const FONT_SIZE: int = 16
const PADDING: Vector2 = Vector2(9, 3)
const CORNER_RADIUS: int = 7
const BORDER_WIDTH: int = 2
const FILL_COLOR: Color = Color("f6e7c8")
const BORDER_COLOR: Color = Color("6b4a32")
const TEXT_COLOR: Color = Color("2e1f1a")
## Space between the tag and what it must clear.
const GAP: float = 6.0
## Above the standing surface: the top of Ohmie's antennae, and the top of the
## carried part icon (drawn at 0.75 scale, centre 128 px above the feet).
const HEAD_CLEARANCE: float = 128.0
const CARRY_CLEARANCE: float = 154.0
## The tag stays this far inside the 1280x720 screen.
const SCREEN_RECT: Rect2 = Rect2(4, 4, 1272, 712)

var _text: String = ""
var _box: StyleBoxFlat = null


func _init() -> void:
	visible = false
	_box = StyleBoxFlat.new()
	_box.bg_color = FILL_COLOR
	_box.border_color = BORDER_COLOR
	_box.set_border_width_all(BORDER_WIDTH)
	_box.set_corner_radius_all(CORNER_RADIUS)
	_box.shadow_color = Color(0, 0, 0, 0.3)
	_box.shadow_size = 2
	_box.shadow_offset = Vector2(0, 2)


## Shows the tag for `target` with `text`, or hides it when `target` is null
## or `text` is empty. `carrying`: Ohmie holds a part (the tag then also clears it).
func show_target(target: Interactable, text: String, carrying: bool) -> void:
	if target == null or text.is_empty():
		visible = false
		_text = ""
		return
	_text = text
	var size: Vector2 = tag_size(text)
	var anchor: Vector2 = target.get_tag_anchor()
	var clearance: float = CARRY_CLEARANCE if carrying else HEAD_CLEARANCE
	var bottom: float = minf(anchor.y, target.get_standing_y() - clearance) - GAP
	var top_left: Vector2 = Vector2(anchor.x - size.x * 0.5, bottom - size.y)
	top_left.x = clampf(top_left.x, SCREEN_RECT.position.x, SCREEN_RECT.end.x - size.x)
	top_left.y = clampf(top_left.y, SCREEN_RECT.position.y, SCREEN_RECT.end.y - size.y)
	global_position = top_left.round()
	visible = true
	queue_redraw()


func get_text() -> String:
	return _text if visible else ""


## The tag's rectangle in global coordinates (for checks).
func get_global_rect() -> Rect2:
	return Rect2(global_position, tag_size(_text))


static func tag_size(text: String) -> Vector2:
	var text_size: Vector2 = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return Vector2(ceilf(text_size.x), FONT.get_height(FONT_SIZE)) + PADDING * 2.0


func _draw() -> void:
	if _text.is_empty():
		return
	var size: Vector2 = tag_size(_text)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var baseline: Vector2 = Vector2(PADDING.x, PADDING.y + FONT.get_ascent(FONT_SIZE))
	draw_string(FONT, baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
