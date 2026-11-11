class_name Player
extends CharacterBody2D
## Ohmie's movement: run, jump (with coyote time, jump buffer and variable
## height), drop through one-way platforms, and animation. Numbers from GDD
## section 5. The origin is the bottom centre of the collider (the feet).
##
## Movement only. Carrying and interaction belong in separate scripts.

signal jumped
signal landed
## Emitted once when the feet pass `fall_out_y`. Cleared by respawn().
signal fell_out

const ONE_WAY_LAYER: int = 2
const ANIM_IDLE: StringName = &"idle"
const ANIM_RUN: StringName = &"run"
const ANIM_JUMP: StringName = &"jump"

@export var run_speed: float = 240.0
@export var gravity: float = 1800.0
@export var jump_velocity: float = 660.0
## Upward speed is multiplied by this when jump is released while rising.
@export var jump_release_factor: float = 0.5
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.10
## How long the one-way collision stays off after a drop-through starts.
@export var drop_through_time: float = 0.25
@export var fall_out_y: float = 800.0
## Horizontal range the collider is kept inside.
@export var screen_left: float = 0.0
@export var screen_right: float = 1280.0

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _drop_timer: float = 0.0
var _was_on_floor: bool = false
var _has_fallen_out: bool = false
var _half_width: float = 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var rect: RectangleShape2D = _collision.shape as RectangleShape2D
	_half_width = rect.size.x * 0.5 if rect != null else 0.0
	_sprite.play(ANIM_IDLE)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_apply_gravity(delta)
	_handle_drop_through()
	_handle_jump()
	_handle_run()
	move_and_slide()
	_clamp_to_screen()
	_update_floor_state()
	_update_animation()
	_check_fell_out()


## Puts Ohmie's feet at `at` with no velocity and clears all timers.
func respawn(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_end_drop_through()
	_was_on_floor = false
	_has_fallen_out = false


func _update_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			_end_drop_through()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


func _handle_drop_through() -> void:
	if Input.is_action_pressed("move_down") and is_on_floor():
		_drop_timer = drop_through_time
		set_collision_mask_value(ONE_WAY_LAYER, false)


func _end_drop_through() -> void:
	_drop_timer = 0.0
	set_collision_mask_value(ONE_WAY_LAYER, true)


func _handle_jump() -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = -jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		jumped.emit()
	elif Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_release_factor


func _handle_run() -> void:
	var direction: float = Input.get_axis("move_left", "move_right")
	velocity.x = direction * run_speed
	if direction != 0.0:
		_sprite.flip_h = direction < 0.0


func _clamp_to_screen() -> void:
	var clamped_x: float = clampf(position.x, screen_left + _half_width, screen_right - _half_width)
	if clamped_x != position.x:
		position.x = clamped_x
		velocity.x = 0.0


func _update_floor_state() -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor


func _update_animation() -> void:
	var anim: StringName = ANIM_JUMP
	if is_on_floor():
		anim = ANIM_RUN if absf(velocity.x) > 0.0 else ANIM_IDLE
	if _sprite.animation != anim:
		_sprite.play(anim)


func _check_fell_out() -> void:
	if not _has_fallen_out and position.y > fall_out_y:
		_has_fallen_out = true
		fell_out.emit()
