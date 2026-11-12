class_name HitFlash
extends Node2D
## The burst shown where Ohmie is zapped: the child Sprite2D "Burst" grows,
## turns a little and fades out, the child Sprite2D "Puff" swells and fades a
## little later, then the node frees itself. Looks only.

## Scale of each sprite at the start and the end (the art is drawn at 2x).
@export var burst_start_scale: float = 0.2
@export var burst_end_scale: float = 0.7
@export var puff_start_scale: float = 0.3
@export var puff_end_scale: float = 0.6
## Seconds the whole effect lasts.
@export var duration: float = 0.45
## Turn of the burst over the effect, in degrees.
@export var burst_turn_degrees: float = 20.0

@onready var _burst: Sprite2D = $Burst
@onready var _puff: Sprite2D = $Puff


func _ready() -> void:
	_burst.scale = Vector2.ONE * burst_start_scale
	_puff.scale = Vector2.ONE * puff_start_scale
	_puff.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_burst, "scale", Vector2.ONE * burst_end_scale, duration * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_burst, "rotation", deg_to_rad(burst_turn_degrees), duration)
	tween.tween_property(_burst, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.tween_property(_puff, "modulate:a", 0.85, duration * 0.3).set_delay(duration * 0.2)
	tween.tween_property(_puff, "scale", Vector2.ONE * puff_end_scale, duration * 0.8).set_delay(duration * 0.2)
	tween.tween_property(_puff, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.chain().tween_callback(queue_free)
