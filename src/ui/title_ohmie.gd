class_name TitleOhmie
extends Node2D
## Ohmie on the title screen: stands on the floor and keeps busy in a loop of
## idle, a hop in place, idle, a short run to the other mark, and now and then
## a victory pose. Position is the feet; the sprite faces right unless flipped.

const FRAMES: SpriteFrames = preload("res://resources/themes/player_frames.tres")
const SPRITE_SCALE: float = 0.5
## Offset that puts the feet of the 2x frames at the node's origin (as in player.tscn).
const SPRITE_OFFSET: Vector2 = Vector2(0, -122)

## The two marks Ohmie runs between, as x positions relative to the start.
@export var run_distance: float = 300.0
@export var run_speed: float = 230.0
@export var idle_seconds: float = 2.2
@export var hop_height: float = 64.0
@export var hop_seconds: float = 0.3

var _sprite: AnimatedSprite2D = null
var _home_x: float = 0.0
var _at_home: bool = true


func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	_sprite.offset = SPRITE_OFFSET
	add_child(_sprite)
	_home_x = position.x
	_sprite.play(&"idle")
	_loop()


func _loop() -> void:
	var step: int = 0
	while is_inside_tree():
		await _wait(idle_seconds)
		if not is_inside_tree():
			return
		match step % 4:
			0:
				await _hop()
			1:
				await _run()
			2:
				await _pose()
			3:
				await _run()
		step += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _hop() -> void:
	_sprite.play(&"jump")
	var ground_y: float = _sprite.position.y
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "position:y", ground_y - hop_height, hop_seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position:y", ground_y, hop_seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_sprite.play(&"idle")
	_squash()


func _run() -> void:
	var target_x: float = _home_x + run_distance if _at_home else _home_x
	_at_home = not _at_home
	_sprite.flip_h = target_x < position.x
	_sprite.play(&"run")
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", target_x, absf(target_x - position.x) / run_speed)
	await tween.finished
	_sprite.play(&"idle")
	_sprite.flip_h = false if _at_home else true


func _pose() -> void:
	_sprite.flip_h = false
	_sprite.play(&"victory")
	await _wait(1.4)
	_sprite.play(&"idle")


## A quick squash on landing.
func _squash() -> void:
	var base: Vector2 = Vector2.ONE * SPRITE_SCALE
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "scale", Vector2(base.x * 1.08, base.y * 0.92), 0.06)
	tween.tween_property(_sprite, "scale", base, 0.12)
