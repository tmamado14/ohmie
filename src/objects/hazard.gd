class_name Hazard
extends Node2D
## Base for everything that zaps Ohmie on contact: patrolling and floating
## enemies and static hazards. A child Hurtbox named "Hurtbox" decides the
## contact; this node re-announces it as `touched`. Hazards never touch the
## circuit or the parts; the room performs the zap.
##
## A hazard that stands on a surface (a patroller or a static hazard: see
## _hurts_only_at_its_level) ignores a body whose feet are more than
## BELOW_TOLERANCE px below its own floor point, so a jump from underneath a
## one-way platform cannot poke Ohmie's head into it. Floaters hurt from any side.

signal touched(body: Node2D)

## How far (px) a body's feet may be below a surface hazard's floor point and
## still be hurt by it.
const BELOW_TOLERANCE: float = 12.0

## The Sfx sound the room plays when this hazard zaps Ohmie.
@export var zap_sound: StringName = &"enemy_zap"
## The drawn body's size on screen: it stands on the origin (surface hazards)
## or is centred on it (floaters). Used for get_sweep_rect().
@export var body_size: Vector2 = Vector2(64, 64)

@onready var _hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_hurtbox.touched.connect(_on_hurtbox_touched)


## Places the hazard from its level entry. Call after adding it to the tree.
func setup(entry: LevelObject) -> void:
	position = entry.position


func get_hurtbox() -> Hurtbox:
	return _hurtbox


## Every area (global) the drawn body can ever cover: for a hazard that does
## not move, its body standing on its origin. Moving hazards override this.
func get_sweep_rect() -> Rect2:
	return Rect2(global_position - Vector2(body_size.x * 0.5, body_size.y), body_size)


## True for a hazard whose origin is the floor point it stands on and that
## only hurts bodies at or above that level. Overridden by surface hazards.
func _hurts_only_at_its_level() -> bool:
	return false


func _on_hurtbox_touched(body: Node2D) -> void:
	if _hurts_only_at_its_level() and body.global_position.y > global_position.y + BELOW_TOLERANCE:
		return
	touched.emit(body)
