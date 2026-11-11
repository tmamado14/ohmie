class_name BoardLamp
extends Node2D
## A fixed lamp on the board, centred on the midpoint of its edge (104x72 on
## screen): dark, lit or blown. Not interactable.

enum State { OFF, ON, BLOWN }

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/processed/lamp_off.png"),
	preload("res://assets/processed/lamp_on.png"),
	preload("res://assets/processed/lamp_blown.png"),
]
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)

var lamp_id: String = ""

var _sprite: Sprite2D = null
var _state: State = State.OFF


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.scale = ART_SCALE
	add_child(_sprite)
	set_state(State.OFF)


## The state for a lamp carrying `current` amperes (null when the circuit has
## no valid solution): OFF below rated_min or without a solution, ON within
## rated_min..rated_max, BLOWN above rated_max. The direction of the current
## does not matter.
static func state_for(current: Rational, rated_min: Rational, rated_max: Rational) -> State:
	if current == null:
		return State.OFF
	var magnitude: Rational = current.negate() if current.sign() < 0 else current
	if magnitude.compare(rated_max) > 0:
		return State.BLOWN
	if magnitude.compare(rated_min) < 0:
		return State.OFF
	return State.ON


func set_state(state: State) -> void:
	_state = state
	_sprite.texture = TEXTURES[state]


func get_state() -> State:
	return _state
