class_name TitleOhmie
extends Node2D
## Ohmie as a menu mascot: stands on the floor on a soft contact shadow,
## breathes while idle, and keeps busy in a loop of a hop in place, a short
## run to the other mark, a victory pose, and the run back. Position is the
## feet; the sprite faces right unless flipped. Size, hop and run are set by
## the screen that places him (the title shows him large, the level select small).

const FRAMES: SpriteFrames = preload("res://resources/themes/player_frames.tres")
## Offset that puts the feet of the 2x frames at the node's origin (as in player.tscn), in frame pixels.
const SPRITE_OFFSET: Vector2 = Vector2(0, -122)
## Contact shadow: width and height at sprite_scale 1.0, colour, and how small and faint it gets at the top of a hop.
const SHADOW_SIZE: Vector2 = Vector2(190, 38)
const SHADOW_COLOR: Color = Color(0.04, 0.02, 0.01, 0.85)
const SHADOW_MIN_FACTOR: float = 0.45
const SHADOW_TEXTURE_SIZE: int = 64
## Idle breathing: vertical stretch and period in seconds.
const BREATH_STRETCH: float = 0.015
const BREATH_SECONDS: float = 2.6
const POSE_SECONDS: float = 1.6
const LANDING_SQUASH: Vector2 = Vector2(1.08, 0.92)

## Drawn size of the 256x256 frames (0.5 matches the in-game player).
@export var sprite_scale: float = 0.5
## Distance between the two marks Ohmie runs between, rightwards from where he starts.
@export var run_distance: float = 300.0
@export var run_speed: float = 230.0
@export var idle_seconds: float = 2.2
@export var hop_height: float = 64.0
@export var hop_seconds: float = 0.3

var _body: Node2D = null
var _sprite: AnimatedSprite2D = null
var _shadow: Sprite2D = null
var _home_x: float = 0.0
var _at_home: bool = true
var _time: float = 0.0


func _ready() -> void:
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	_shadow.texture = _shadow_texture()
	add_child(_shadow)
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = FRAMES
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.scale = Vector2.ONE * sprite_scale
	_sprite.offset = SPRITE_OFFSET
	_body.add_child(_sprite)
	_home_x = position.x
	_sprite.play(&"idle")
	_update_shadow()
	_loop()


func _process(delta: float) -> void:
	_time += delta
	var breathing: bool = _sprite.animation == &"idle" and is_zero_approx(_sprite.position.y)
	var stretch: float = BREATH_STRETCH * sin(_time * TAU / BREATH_SECONDS) if breathing else 0.0
	_body.scale = Vector2(1.0 - stretch * 0.5, 1.0 + stretch)
	_update_shadow()


## The shadow shrinks and fades as Ohmie rises off the floor.
func _update_shadow() -> void:
	var rise: float = maxf(-_sprite.position.y, 0.0)
	var factor: float = clampf(1.0 - rise / maxf(hop_height * 2.0, 1.0), SHADOW_MIN_FACTOR, 1.0)
	_shadow.scale = SHADOW_SIZE * sprite_scale * factor / float(SHADOW_TEXTURE_SIZE)
	_shadow.modulate.a = factor


func _shadow_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, SHADOW_COLOR)
	gradient.set_color(1, Color(SHADOW_COLOR, 0.0))
	gradient.add_point(0.6, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.75))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = SHADOW_TEXTURE_SIZE
	texture.height = SHADOW_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


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
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "position:y", -hop_height, hop_seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position:y", 0.0, hop_seconds) \
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
	_squash()
	_sprite.flip_h = not _at_home


func _pose() -> void:
	_sprite.flip_h = false
	_sprite.play(&"victory")
	await _wait(POSE_SECONDS)
	_sprite.play(&"idle")


## A quick squash on landing or stopping.
func _squash() -> void:
	var base: Vector2 = Vector2.ONE * sprite_scale
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "scale", base * LANDING_SQUASH, 0.06)
	tween.tween_property(_sprite, "scale", base, 0.12)
