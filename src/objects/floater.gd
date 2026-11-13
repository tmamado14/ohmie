class_name Floater
extends Hazard
## An enemy that floats in a straight line from `from` to `to` (centre points)
## and back, forever, easing in and out at both ends. `speed` is its average
## speed in px/s, so one leg takes distance / speed seconds. The origin is its
## centre. It faces right unless its current leg moves left.
##
## Movement happens in _physics_process; the pulse, the glow and the sway are
## only looks.

## The art faces right; the body is mirrored while moving left.
@export var art_faces_right: bool = true
## Scale pulse: fraction gained and lost each cycle.
@export var pulse_amount: float = 0.07
## Pulse speed in radians per second.
@export var pulse_speed: float = 7.0
## Glow opacity range (the additive halo behind the body).
@export var glow_min_alpha: float = 0.15
@export var glow_max_alpha: float = 0.55
## Gentle rocking angle either side, in degrees.
@export var sway_degrees: float = 6.0
## Sway speed in radians per second.
@export var sway_speed: float = 2.5

var speed: float = LevelObject.DEFAULT_FLOATER_SPEED

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _leg_time: float = 0.0
## 0..2: 0..1 is the leg from `from` to `to`, 1..2 the way back.
var _phase: float = 0.0
var _time: float = 0.0
var _hurtbox_base_x: float = 0.0

@onready var _body: Node2D = $Body
@onready var _glow: CanvasItem = $Body/Glow


func _ready() -> void:
	super._ready()
	_hurtbox_base_x = _hurtbox.position.x
	_apply_looks()


func setup(entry: LevelObject) -> void:
	_from = entry.from_point
	_to = entry.to_point
	speed = entry.speed
	_phase = 0.0
	_leg_time = _from.distance_to(_to) / speed if speed > 0.0 else 0.0
	position = _from
	_apply_looks()


## The two centre points it moves between.
func get_from() -> Vector2:
	return _from


func get_to() -> Vector2:
	return _to


## The whole flight: the line from `from` to `to` (in the parent's
## coordinates) widened by half the body size on every side.
func get_sweep_rect() -> Rect2:
	var parent_offset: Vector2 = global_position - position
	return Rect2(_from + parent_offset, Vector2.ZERO).expand(_to + parent_offset).grow_individual(
			body_size.x * 0.5, body_size.y * 0.5, body_size.x * 0.5, body_size.y * 0.5)


func _physics_process(delta: float) -> void:
	if _leg_time <= 0.0:
		return
	_phase = fmod(_phase + delta / _leg_time, 2.0)
	var along: float = _phase if _phase < 1.0 else 2.0 - _phase
	position = _from.lerp(_to, 0.5 - 0.5 * cos(PI * along))
	_hurtbox.position.x = _hurtbox_base_x * _facing_sign()


func _process(delta: float) -> void:
	_time += delta
	_apply_looks()


func _apply_looks() -> void:
	var pulse: float = sin(_time * pulse_speed)
	var size: float = 1.0 + pulse_amount * pulse
	_body.scale = Vector2(_facing_sign() * size, size)
	_body.rotation = deg_to_rad(sway_degrees) * sin(_time * sway_speed)
	_glow.modulate.a = lerpf(glow_min_alpha, glow_max_alpha, 0.5 + 0.5 * pulse)


## +1 when the art must be drawn as authored, -1 when mirrored.
func _facing_sign() -> float:
	var dx: float = _to.x - _from.x
	if _phase >= 1.0:
		dx = -dx
	if dx == 0.0:
		return 1.0
	return 1.0 if (dx > 0.0) == art_faces_right else -1.0
