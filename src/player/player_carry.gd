class_name PlayerCarry
extends Node2D
## Ohmie's hands: carries at most one resistor and handles `interact`
## (GDD section 2, "Interaction rules").
##
## A child of the player, at the player's origin (the feet). Interaction only
## works while Ohmie stands on a floor or platform: in the air nothing is
## highlighted and every `interact` press is invalid.
## On the ground, each physics frame it finds the nearest Interactable within
## `reach` of the body centre that can be used with the current hands (empty
## hands: loose resistors and filled sockets; carrying: sockets) and
## highlights it. On `interact`:
##   empty hands + loose resistor -> pick up
##   carrying + empty socket      -> plug in
##   empty hands + filled socket  -> pull out
##   carrying + filled socket     -> swap
##   carrying + nothing in range  -> put down at the feet (ResistorPlacement
##                                   picks the exact spot, or refuses)
##   anything else                -> invalid

signal picked_up(resistor: ResistorPickup)
signal placed(resistor: ResistorPickup, socket: CircuitSocket)
signal removed(resistor: ResistorPickup, socket: CircuitSocket)
signal swapped(placed_resistor: ResistorPickup, taken_resistor: ResistorPickup, socket: CircuitSocket)
signal dropped(resistor: ResistorPickup)
signal invalid_action

## The body whose floor state decides whether Ohmie can interact at all.
@export var body: CharacterBody2D
## Interaction range in pixels, measured from the body centre.
@export var reach: float = 56.0
## From the feet to the body centre (half the 88 px collider).
@export var body_centre_offset: Vector2 = Vector2(0, -44)
## How far a put-down may slide along the surface to find a valid spot.
@export var put_down_max_slide: float = 64.0
## Step between the spots tried when a returning resistor's home is taken.
@export var return_home_step: float = 64.0

var _carried: ResistorPickup = null
var _target: Interactable = null
var _enabled: bool = true

@onready var _carried_icon: ResistorIcon = $CarriedIcon


func _ready() -> void:
	_carried_icon.visible = false


func _physics_process(_delta: float) -> void:
	if not _enabled:
		return
	var grounded: bool = _is_grounded()
	_set_target(_find_target() if grounded else null)
	if Input.is_action_just_pressed("interact"):
		if grounded:
			_interact()
		else:
			invalid_action.emit()


## The resistor in Ohmie's hands, or null.
func get_carried() -> ResistorPickup:
	return _carried


func is_carrying() -> bool:
	return _carried != null


## The highlighted interactable, or null.
func get_target() -> Interactable:
	return _target


## Turns interaction on or off (off clears the highlight).
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_set_target(null)


## Sends a carried resistor back to where the level first put it (after a
## fall), or beside it if another loose resistor lies there.
func return_carried_home() -> void:
	if _carried == null:
		return
	var resistor: ResistorPickup = _carried
	_set_carried(null)
	resistor.place_loose(_placement().find_return_spot(resistor.home_position, return_home_step))


func _interact() -> void:
	var socket: CircuitSocket = _target as CircuitSocket
	var pickup: ResistorPickup = _target as ResistorPickup
	if _carried == null:
		if pickup != null:
			pickup.take()
			_set_carried(pickup)
			_set_target(null)
			picked_up.emit(pickup)
		elif socket != null and socket.is_filled():
			var taken: ResistorPickup = socket.take_out()
			_set_carried(taken)
			removed.emit(taken, socket)
		else:
			invalid_action.emit()
		return

	var held: ResistorPickup = _carried
	if socket != null:
		if socket.is_filled():
			var old: ResistorPickup = socket.swap(held)
			_set_carried(old)
			swapped.emit(held, old, socket)
		else:
			_set_carried(null)
			socket.insert(held)
			placed.emit(held, socket)
		return

	var spot: Vector2 = _placement().find_put_down(global_position, put_down_max_slide)
	if spot == ResistorPlacement.NO_SPOT:
		invalid_action.emit()
		return
	_set_carried(null)
	held.place_loose(spot)
	dropped.emit(held)


func _is_grounded() -> bool:
	return body != null and body.is_on_floor()


func _find_target() -> Interactable:
	var centre: Vector2 = global_position + body_centre_offset
	var carrying: bool = _carried != null
	var best: Interactable = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var candidate: Interactable = node as Interactable
		if candidate == null or not candidate.can_interact(carrying):
			continue
		var distance: float = centre.distance_to(candidate.get_interaction_point())
		if distance <= reach and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## A placement helper that knows every other loose resistor.
func _placement() -> ResistorPlacement:
	var others: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var pickup: ResistorPickup = node as ResistorPickup
		if pickup != null and pickup.is_loose() and pickup != _carried:
			others.append(pickup.global_position)
	return ResistorPlacement.new(get_world_2d().direct_space_state, others)


func _set_target(target: Interactable) -> void:
	if target == _target:
		return
	if _target != null and is_instance_valid(_target):
		_target.set_highlighted(false)
	_target = target
	if _target != null:
		_target.set_highlighted(true)


func _set_carried(resistor: ResistorPickup) -> void:
	_carried = resistor
	_carried_icon.set_value(resistor.value if resistor != null else null)
	_carried_icon.visible = resistor != null
