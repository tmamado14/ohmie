class_name PolarityBadges
extends Node2D
## The + and − badges a slot or fixed part shows while a battery sits in it,
## centred on the 104x72 frame's top corner screws. Place this node at the
## frame's centre.

const PLUS_TEXTURE: Texture2D = preload("res://assets/processed/polarity_plus.png")
const MINUS_TEXTURE: Texture2D = preload("res://assets/processed/polarity_minus.png")
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## The corner screws relative to the frame centre: (12.5, 12.5) and
## (91.5, 12.5) on screen from the 104x72 frame's top-left (docs/ASSETS.md).
const LEFT_SCREW: Vector2 = Vector2(-39.5, -23.5)
const RIGHT_SCREW: Vector2 = Vector2(39.5, -23.5)

var _plus: Sprite2D = null
var _minus: Sprite2D = null


func _init() -> void:
	_plus = _make_badge("Plus", PLUS_TEXTURE)
	_minus = _make_badge("Minus", MINUS_TEXTURE)
	show_polarity(false, false)


## Shows the badges (plus on the right when `plus_on_right`, else on the left),
## or hides both.
func show_polarity(shown: bool, plus_on_right: bool) -> void:
	_plus.visible = shown
	_minus.visible = shown
	_plus.position = RIGHT_SCREW if plus_on_right else LEFT_SCREW
	_minus.position = LEFT_SCREW if plus_on_right else RIGHT_SCREW


func is_shown() -> bool:
	return _plus.visible


## True when the plus badge sits on the right-hand screw.
func is_plus_on_right() -> bool:
	return _plus.position == RIGHT_SCREW


func _make_badge(badge_name: String, texture: Texture2D) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = badge_name
	sprite.texture = texture
	sprite.scale = ART_SCALE
	add_child(sprite)
	return sprite
