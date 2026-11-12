class_name PartBlocker
extends Node2D
## A floor area where a loose part may not lie (a bounce pad or a static
## hazard). Its origin is the bottom centre of the area. PlayerCarry collects
## every blocker in GROUP and hands their rectangles to PartPlacement.

const GROUP: StringName = &"part_blockers"

## Width and height of the blocked area in pixels, standing on the origin.
@export var size: Vector2 = Vector2(64, 48)


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## The blocked area in global coordinates.
func get_global_rect() -> Rect2:
	return Rect2(global_position - Vector2(size.x * 0.5, size.y), size)
