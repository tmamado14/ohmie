class_name Interactable
extends Node2D
## Base for things Ohmie can use with `interact`: loose resistors and sockets.
##
## Every instance joins GROUP so the player's carry component can find the
## nearest one. Subclasses say where their centre is, whether they can be used
## right now, and how they look when highlighted.

const GROUP: StringName = &"interactable"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## Global point used for the reach check (the visual centre).
func get_interaction_point() -> Vector2:
	return global_position


## False while the object cannot be interacted with at all (for example a
## resistor that is being carried or sits in a socket).
func is_available() -> bool:
	return visible


## Shows or hides the "this is what interact will act on" highlight.
func set_highlighted(_highlighted: bool) -> void:
	pass
