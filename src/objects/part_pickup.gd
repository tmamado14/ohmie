class_name PartPickup
extends Interactable
## One carried part (resistor, battery or diode) from the level. The node's origin is
## the floor point under it (bottom centre of the icon).
##
## The same node represents the part for the whole level: it is shown while it
## lies loose, and hidden while Ohmie carries it or it sits in a slot (those
## draw their own icon). It remembers where the level first put it.

## From the origin (feet) to the icon centre: the logical 96x64 icon box whose
## bottom is the floor point (reach, name tag and footprint use it).
const ICON_OFFSET: Vector2 = Vector2(0, -32)
## Where the icon is drawn: lowered by the transparent band under the art's ink
## (PartIcon.INK_BOTTOM_INSET), so the plaque's bottom edge touches the surface.
const ICON_DRAW_OFFSET: Vector2 = ICON_OFFSET + Vector2(0, PartIcon.INK_BOTTOM_INSET)
const ICON_SIZE: Vector2 = Vector2(96, 64)

## The level file's id for this part.
var part_id: String = ""
## The part's kind and exact value.
var part: Part = null
## Where the level originally put it (global floor point).
var home_position: Vector2 = Vector2.ZERO

var _loose: bool = true

@onready var _icon: PartIcon = $Icon
@onready var _highlight: Sprite2D = $Highlight


func _ready() -> void:
	_icon.position = ICON_DRAW_OFFSET
	_highlight.position = ICON_DRAW_OFFSET
	_highlight.visible = false
	_icon.set_part(part)


## Sets the part and home (global floor point) and puts it there. Call after
## adding the node to the tree.
func setup(id: String, level_part: Part, home: Vector2) -> void:
	part_id = id
	part = level_part
	home_position = home
	if _icon != null:
		_icon.set_part(part)
	place_loose(home)


## Lays the part loose with its bottom centre at `at` (global).
func place_loose(at: Vector2) -> void:
	global_position = at
	_loose = true
	visible = true


## Takes the part out of the world (carried or plugged in).
func take() -> void:
	_loose = false
	visible = false
	set_highlighted(false)


func is_loose() -> bool:
	return _loose


func is_available() -> bool:
	return _loose


## A loose part can only be picked up, so only with empty hands.
func can_interact(carrying: bool) -> bool:
	return _loose and not carrying


func get_interaction_point() -> Vector2:
	return global_position + ICON_OFFSET


## The floor point the part lies on.
func get_standing_y() -> float:
	return global_position.y


## The top centre of the 64 px tall icon.
func get_tag_anchor() -> Vector2:
	return global_position + ICON_OFFSET * 2.0


## The 96x64 icon box standing on the floor point.
func get_frame_rect() -> Rect2:
	return Rect2(global_position + ICON_OFFSET - ICON_SIZE * 0.5, ICON_SIZE)


## The drawn icon (for checks of how the part looks).
func get_icon() -> PartIcon:
	return _icon


## The part's name tag: "3 Ω", "1/2 Ω", "6 V", "diode 0.7 V".
func get_tag_text() -> String:
	return part.tag_text() if part != null else ""


func set_highlighted(highlighted: bool) -> void:
	if _highlight != null:
		_highlight.visible = highlighted
