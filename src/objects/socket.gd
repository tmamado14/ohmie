class_name CircuitSocket
extends Interactable
## A socket on the circuit board that holds at most one resistor. The node's
## origin is the midpoint of its edge; the 104x72 frame is centred on it.
##
## Announces every change of contents with `contents_changed`; the board
## listens and re-solves the circuit.

signal contents_changed

@export var empty_texture: Texture2D
@export var highlight_texture: Texture2D

## The level file's edge id of this socket.
var socket_id: String = ""

var _resistor: ResistorPickup = null

@onready var _frame: Sprite2D = $Frame
@onready var _icon: ResistorIcon = $Icon


func _ready() -> void:
	_frame.texture = empty_texture
	_icon.set_value(null)


func is_filled() -> bool:
	return _resistor != null


## The value in the socket, or null when empty.
func get_value() -> Rational:
	return _resistor.value if _resistor != null else null


## The resistor in the socket, or null when empty.
func get_resistor() -> ResistorPickup:
	return _resistor


## Plugs `resistor` into this empty socket. Returns false if already filled.
func insert(resistor: ResistorPickup) -> bool:
	if _resistor != null or resistor == null:
		return false
	_set_resistor(resistor)
	return true


## Pulls the resistor out and returns it (null if the socket was empty).
func take_out() -> ResistorPickup:
	var old: ResistorPickup = _resistor
	if old != null:
		_set_resistor(null)
	return old


## Puts `resistor` in and returns the one that was there (one change event).
func swap(resistor: ResistorPickup) -> ResistorPickup:
	var old: ResistorPickup = _resistor
	_set_resistor(resistor)
	return old


func set_highlighted(highlighted: bool) -> void:
	if _frame != null:
		_frame.texture = highlight_texture if highlighted else empty_texture


func _set_resistor(resistor: ResistorPickup) -> void:
	_resistor = resistor
	_icon.set_value(get_value())
	contents_changed.emit()
