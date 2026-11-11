class_name ExitDoor
extends Node2D
## The level's exit. The origin is the floor point under the door (bottom
## centre). A closed door does nothing and does not block movement. While open,
## a body (the player) overlapping the doorway centre triggers `entered` once.

signal opened
signal closed
## The player walked into the open door. Emitted at most once.
signal entered

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

var _open: bool = false
var _entered: bool = false

@onready var _sprite: Sprite2D = $Sprite
@onready var _doorway: Area2D = $Doorway


func _ready() -> void:
	_sprite.texture = closed_texture


func _physics_process(_delta: float) -> void:
	if _open and not _entered and _doorway.has_overlapping_bodies():
		_entered = true
		entered.emit()


func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	_sprite.texture = open_texture if open else closed_texture
	if open:
		opened.emit()
	else:
		closed.emit()


func is_open() -> bool:
	return _open
