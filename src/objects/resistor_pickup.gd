class_name ResistorPickup
extends Interactable
## One resistor from the level. The node's origin is the floor point under it
## (bottom centre of the icon).
##
## The same node represents the resistor for the whole level: it is shown while
## it lies loose, and hidden while Ohmie carries it or it sits in a socket
## (those draw their own icon). It remembers where the level first put it.

## From the origin (feet) to the icon centre.
const ICON_OFFSET: Vector2 = Vector2(0, -32)

## The level file's id for this resistor.
var pickup_id: String = ""
## The resistor's exact value.
var value: Rational = null
## Where the level originally put it (global floor point).
var home_position: Vector2 = Vector2.ZERO

var _loose: bool = true

@onready var _icon: ResistorIcon = $Icon
@onready var _highlight: Sprite2D = $Highlight


func _ready() -> void:
	_icon.position = ICON_OFFSET
	_highlight.position = ICON_OFFSET
	_highlight.visible = false
	_icon.set_value(value)


## Sets the value and home (global floor point) and puts the resistor there.
## Call after adding the node to the tree.
func setup(id: String, ohms: Rational, home: Vector2) -> void:
	pickup_id = id
	value = ohms
	home_position = home
	if _icon != null:
		_icon.set_value(value)
	place_loose(home)


## Lays the resistor loose with its bottom centre at `at` (global).
func place_loose(at: Vector2) -> void:
	global_position = at
	_loose = true
	visible = true


## Takes the resistor out of the world (carried or plugged in).
func take() -> void:
	_loose = false
	visible = false
	set_highlighted(false)


func is_loose() -> bool:
	return _loose


func is_available() -> bool:
	return _loose


func get_interaction_point() -> Vector2:
	return global_position + ICON_OFFSET


func set_highlighted(highlighted: bool) -> void:
	if _highlight != null:
		_highlight.visible = highlighted
