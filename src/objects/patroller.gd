class_name Patroller
extends Hazard
## An enemy that walks back and forth on its surface between x = `left` and
## x = `right` at `speed` px/s, turning at the ends and facing its direction of
## travel. It never falls, jumps or chases. The origin is the floor point
## under it; it starts walking right.
##
## Movement happens in _physics_process (deterministic at a fixed frame rate);
## the squash-and-stretch wobble, bob and tilt are only looks.

## The art faces right; the body is mirrored while walking left.
@export var art_faces_right: bool = true
## Squash and stretch: fraction of the size gained and lost each cycle.
@export var wobble_amount: float = 0.0
## Cycle speed of the wobble, bob and tilt, in radians per second.
@export var wobble_speed: float = 6.0
## Height of a small hop (wheels on a bumpy floor), in pixels.
@export var bob_height: float = 0.0
## Rocking angle either side, in degrees.
@export var tilt_degrees: float = 0.0

var left: float = 0.0
var right: float = 0.0
var speed: float = LevelObject.DEFAULT_PATROLLER_SPEED

var _direction: float = 1.0
var _time: float = 0.0
var _hurtbox_base_x: float = 0.0

@onready var _body: Node2D = $Body


func _ready() -> void:
	super._ready()
	_hurtbox_base_x = _hurtbox.position.x
	_apply_looks()


func setup(entry: LevelObject) -> void:
	super.setup(entry)
	left = entry.left
	right = entry.right
	speed = entry.speed
	_direction = 1.0
	_apply_looks()


## +1 while walking right, -1 while walking left.
func get_direction() -> float:
	return _direction


## True while the drawn body faces right.
func is_facing_right() -> bool:
	var mirrored: bool = _body.scale.x < 0.0
	return mirrored != art_faces_right


func _physics_process(delta: float) -> void:
	if right <= left:
		return
	var x: float = position.x + _direction * speed * delta
	if x >= right:
		x = right
		_direction = -1.0
	elif x <= left:
		x = left
		_direction = 1.0
	position.x = x
	_hurtbox.position.x = _hurtbox_base_x * _facing_sign()
	_apply_looks()


func _process(delta: float) -> void:
	_time += delta
	_apply_looks()


func _apply_looks() -> void:
	var wave: float = sin(_time * wobble_speed)
	_body.scale = Vector2(_facing_sign() * (1.0 + wobble_amount * wave), 1.0 - wobble_amount * wave)
	_body.position.y = -absf(sin(_time * wobble_speed)) * bob_height
	_body.rotation = deg_to_rad(tilt_degrees) * sin(_time * wobble_speed * 0.5)


## +1 when the art must be drawn as authored, -1 when mirrored.
func _facing_sign() -> float:
	var moving_right: bool = _direction > 0.0
	return 1.0 if moving_right == art_faces_right else -1.0
