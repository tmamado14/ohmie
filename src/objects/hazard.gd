class_name Hazard
extends Node2D
## Base for everything that zaps Ohmie on contact: patrolling and floating
## enemies and static hazards. A child Hurtbox named "Hurtbox" decides the
## contact; this node re-announces it as `touched`. Hazards never touch the
## circuit or the parts; the room performs the zap.

signal touched(body: Node2D)

## The Sfx sound the room plays when this hazard zaps Ohmie.
@export var zap_sound: StringName = &"enemy_zap"

@onready var _hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_hurtbox.touched.connect(touched.emit)


## Places the hazard from its level entry. Call after adding it to the tree.
func setup(entry: LevelObject) -> void:
	position = entry.position


func get_hurtbox() -> Hurtbox:
	return _hurtbox
