class_name FixedResistor
extends Node2D
## A resistor soldered into the board by the level. Drawn centred on the
## midpoint of its edge on an iron backing so it reads as "cannot be moved".
## Not interactable.

const BACKING_TEXTURE: Texture2D = preload("res://assets/processed/fixed_backing.png")
## The processed art is drawn at 2x; this brings it to 104x72 on screen.
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## Icon centre relative to the backing centre, so the icon's leads meet the stubs.
const ICON_OFFSET: Vector2 = Vector2(0, 3.5)
const ICON_DIM: Color = Color(0.8, 0.8, 0.8)

var _icon: ResistorIcon = null


func _init() -> void:
	var backing: Sprite2D = Sprite2D.new()
	backing.name = "Backing"
	backing.texture = BACKING_TEXTURE
	backing.scale = ART_SCALE
	add_child(backing)
	_icon = ResistorIcon.new()
	_icon.name = "Icon"
	_icon.position = ICON_OFFSET
	_icon.modulate = ICON_DIM
	add_child(_icon)


func set_value(value: Rational) -> void:
	_icon.set_value(value)
