class_name FixedPart
extends Node2D
## A resistor or battery soldered into the board by the level. Drawn centred on
## the midpoint of its edge on an iron backing so it reads as "cannot be
## moved". A battery's art is mirrored when needed so its plus end faces the
## edge's `from` node, which also gets the + badge. Not interactable.

const BACKING_TEXTURE: Texture2D = preload("res://assets/processed/fixed_backing.png")
## The processed art is drawn at 2x; this brings it to 104x72 on screen.
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## Icon centre relative to the backing centre, so the icon's leads meet the stubs.
const ICON_OFFSET: Vector2 = Vector2(0, 3.5)
const ICON_DIM: Color = Color(0.8, 0.8, 0.8)

var _icon: PartIcon = null
var _badges: PolarityBadges = null


func _init() -> void:
	var backing: Sprite2D = Sprite2D.new()
	backing.name = "Backing"
	backing.texture = BACKING_TEXTURE
	backing.scale = ART_SCALE
	add_child(backing)
	_icon = PartIcon.new()
	_icon.name = "Icon"
	_icon.position = ICON_OFFSET
	_icon.modulate = ICON_DIM
	add_child(_icon)
	_badges = PolarityBadges.new()
	_badges.name = "Polarity"
	add_child(_badges)


## Shows `part`. `from_is_right`: the edge's `from` node lies right of its `to`
## node on screen (only matters for a battery).
func setup(part: Part, from_is_right: bool) -> void:
	_icon.set_part(part)
	var battery: bool = part != null and part.is_battery()
	_icon.set_flipped(battery and from_is_right)
	_badges.show_polarity(battery, from_is_right)


func get_icon() -> PartIcon:
	return _icon
