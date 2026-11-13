class_name CircuitSocket
extends Interactable
## A slot on the circuit board that holds at most one part of any kind. The
## node's origin is the midpoint of its edge; the 104x72 frame is centred on it.
##
## A battery's plus end faces the slot's `from` node: its art (plus on the
## left) is mirrored when `from` lies right of `to`, and the + / − badges sit
## on the matching corner screws while a battery is in.
##
## Announces every change of contents with `contents_changed`; the board
## listens and re-solves the circuit.

signal contents_changed

## A slot sits at standing height: its centre this far above the surface it is
## used from (GDD 6).
const STANDING_HEIGHT: float = 44.0
## The frame's size on screen.
const FRAME_SIZE: Vector2 = Vector2(104, 72)
## Half the height of the 104x72 frame.
const FRAME_HALF_HEIGHT: float = FRAME_SIZE.y * 0.5
## The name tag of an empty slot.
const EMPTY_TAG: String = "empty"

@export var empty_texture: Texture2D
@export var highlight_texture: Texture2D

## The level file's edge id of this slot.
var socket_id: String = ""

var _pickup: PartPickup = null
## The slot's `from` node lies right of its `to` node on screen.
var _from_is_right: bool = false

@onready var _frame: Sprite2D = $Frame
@onready var _icon: PartIcon = $Icon
@onready var _badges: PolarityBadges = $Polarity


func _ready() -> void:
	_frame.texture = empty_texture
	_show_contents()


func is_filled() -> bool:
	return _pickup != null


## Carrying: plug in or swap. Empty hands: only a filled slot (pull out).
func can_interact(carrying: bool) -> bool:
	return carrying or is_filled()


func get_standing_y() -> float:
	return global_position.y + STANDING_HEIGHT


## The top centre of the frame.
func get_tag_anchor() -> Vector2:
	return global_position - Vector2(0, FRAME_HALF_HEIGHT)


## The 104x72 frame, centred on the slot's origin.
func get_frame_rect() -> Rect2:
	return Rect2(global_position - FRAME_SIZE * 0.5, FRAME_SIZE)


## The label of the part in the slot, or "empty".
func get_tag_text() -> String:
	var part: Part = get_part()
	return part.label() if part != null else EMPTY_TAG


## Tells the slot where its `from` node is, so a battery faces the right way.
func set_from_is_right(from_is_right: bool) -> void:
	_from_is_right = from_is_right
	if is_node_ready():
		_show_contents()


## The part in the slot, or null when empty.
func get_part() -> Part:
	return _pickup.part if _pickup != null else null


## The pickup in the slot, or null when empty.
func get_pickup() -> PartPickup:
	return _pickup


## Plugs `pickup` into this empty slot. Returns false if already filled.
func insert(pickup: PartPickup) -> bool:
	if _pickup != null or pickup == null:
		return false
	_set_pickup(pickup)
	return true


## Pulls the part out and returns it (null if the slot was empty).
func take_out() -> PartPickup:
	var old: PartPickup = _pickup
	if old != null:
		_set_pickup(null)
	return old


## Puts `pickup` in and returns the one that was there (one change event).
func swap(pickup: PartPickup) -> PartPickup:
	var old: PartPickup = _pickup
	_set_pickup(pickup)
	return old


func set_highlighted(highlighted: bool) -> void:
	if _frame != null:
		_frame.texture = highlight_texture if highlighted else empty_texture


## The drawn part icon (for checks of how the slot looks).
func get_icon() -> PartIcon:
	return _icon


## The + / − badges (for checks of how the slot looks).
func get_polarity_badges() -> PolarityBadges:
	return _badges


func _set_pickup(pickup: PartPickup) -> void:
	_pickup = pickup
	_show_contents()
	contents_changed.emit()


func _show_contents() -> void:
	var part: Part = get_part()
	var battery: bool = part != null and part.is_battery()
	_icon.set_part(part)
	_icon.set_flipped(battery and _from_is_right)
	_badges.show_polarity(battery, _from_is_right)
