class_name BouncePad
extends Node2D
## A spring pad on the floor. Landing on its cushion from above launches
## whoever landed straight up at `launch_speed`, whether or not jump is held;
## standing on it keeps bouncing. It is not solid: walking into it from the
## side does nothing. The origin is the floor point under it.
##
## The pad only detects the landing and announces it with `bounced`; the room
## launches Ohmie. The child Area2D "Trigger" (physics layer 6 `utility`,
## watching the player layer) reaches well above the cushion, so a falling
## body is seen for a few frames before it lands. The pad remembers each seen
## body's feet height from the previous frame; a landing is a body that is
## falling, whose feet were at or above the cushion's top last frame and are
## now at most `catch_depth` below it, within `catch_half_width` of the
## pad's centre. A body first seen below the top (walking in from the side)
## never bounces.

## Emitted once per landing, with the cushion's top (global y) and the speed
## to launch at.
signal bounced(body: Node2D, surface_y: float, launch_speed: float)

## Upward launch speed in px/s. With gravity 1800 px/s² at 60 physics frames a
## second, 913 px/s peaks about 224 px (7 tiles) above the cushion.
@export var launch_speed: float = 913.0
## Height of the cushion's top above the floor point, in pixels.
@export var surface_height: float = 50.0
## Horizontal distance from the centre within which feet count as on the pad.
@export var catch_half_width: float = 30.0
## How far below the cushion's top feet may already be when the landing is
## seen: more than the largest fall in one frame (about 25 px from the top of
## the screen), less than the cushion's height above the floor.
@export var catch_depth: float = 40.0
## Feet within this many pixels of the top count as having come from above.
@export var crossing_tolerance: float = 1.0
## The squash pose (scale of the art) right after a bounce.
@export var squash_scale: Vector2 = Vector2(1.18, 0.68)
## Seconds the squash pose is held before springing back.
@export var squash_hold_time: float = 0.07
## Seconds the cushion takes to spring back.
@export var spring_back_time: float = 0.4

var _tween: Tween = null
## Instance id -> feet y last physics frame, for bodies inside the trigger.
var _last_feet_y: Dictionary = {}

@onready var _body: Node2D = $Body
@onready var _trigger: Area2D = $Trigger


## Places the pad from its level entry. Call after adding it to the tree.
func setup(entry: LevelObject) -> void:
	position = entry.position


## Global y of the cushion's top.
func get_surface_y() -> float:
	return global_position.y - surface_height


func _physics_process(_delta: float) -> void:
	var seen: Dictionary = {}
	for body: Node2D in _trigger.get_overlapping_bodies():
		var character: CharacterBody2D = body as CharacterBody2D
		if character == null:
			continue
		var id: int = character.get_instance_id()
		var previous_feet_y: float = _last_feet_y.get(id, INF)
		seen[id] = character.global_position.y
		if _is_landing(character, previous_feet_y):
			_squash()
			bounced.emit(character, get_surface_y(), launch_speed)
	_last_feet_y = seen


func _is_landing(character: CharacterBody2D, previous_feet_y: float) -> bool:
	if character.velocity.y <= 0.0 or previous_feet_y > get_surface_y() + crossing_tolerance:
		return false
	var feet: Vector2 = character.global_position
	if absf(feet.x - global_position.x) > catch_half_width:
		return false
	var surface: float = get_surface_y()
	return feet.y >= surface and feet.y <= surface + catch_depth


func _squash() -> void:
	if _tween != null:
		_tween.kill()
	_body.scale = squash_scale
	_tween = create_tween()
	_tween.tween_interval(squash_hold_time)
	_tween.tween_property(_body, "scale", Vector2.ONE, spring_back_time) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
