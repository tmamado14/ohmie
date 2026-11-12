class_name StaticHazard
extends Hazard
## A hazard that never moves (spike strip, live wire). The origin is the floor
## point under it. Optionally flickers (a live wire's sparks) as a look.

## Flicker the brightness and jitter the art a little (sparks).
@export var flicker: bool = false
## Seconds between flicker changes.
@export var flicker_interval: float = 0.08
## Brightest flicker (modulate multiplier).
@export var flicker_max_brightness: float = 1.45
## Largest jitter offset in pixels.
@export var flicker_jitter: float = 0.75

var _flicker_left: float = 0.0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _body: Node2D = $Body


## A static hazard sits on a surface: it does not hurt from below it.
func _hurts_only_at_its_level() -> bool:
	return true


func _process(delta: float) -> void:
	if not flicker:
		return
	_flicker_left -= delta
	if _flicker_left > 0.0:
		return
	_flicker_left = flicker_interval
	var brightness: float = _random.randf_range(1.0, flicker_max_brightness)
	_body.modulate = Color(brightness, brightness, brightness, 1.0)
	_body.position = Vector2(_random.randf_range(-flicker_jitter, flicker_jitter),
			_random.randf_range(-flicker_jitter, flicker_jitter))
