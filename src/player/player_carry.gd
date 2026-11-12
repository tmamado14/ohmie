class_name PlayerCarry
extends Node2D
## Ohmie's hands: carries at most one part and handles `interact`
## (GDD section 2, "Interaction rules", with "resistor" read as "part").
##
## A child of the player, at the player's origin (the feet). Interaction only
## works while Ohmie stands on a floor or platform: in the air nothing is
## highlighted and every `interact` press is invalid.
## On the ground, each physics frame it finds the nearest Interactable within
## `reach` of the body centre that can be used with the current hands (empty
## hands: loose parts and filled slots; carrying: slots) and that stands at
## Ohmie's level (his feet within `level_tolerance` of the object's standing
## surface, so a part or slot on a ledge needs the climb), and highlights it.
## `target_changed` announces the highlighted target and its name-tag text
## whenever either changes. On `interact`:
##   empty hands + loose part     -> pick up
##   carrying + empty slot        -> plug in
##   empty hands + filled slot    -> pull out
##   carrying + filled slot       -> swap
##   carrying + nothing in range  -> put down at the feet (PartPlacement
##                                   picks the exact spot, or refuses; never
##                                   on a PartBlocker's area: pads, hazards,
##                                   board components, the door)
##   anything else                -> invalid

signal picked_up(part: PartPickup)
signal placed(part: PartPickup, socket: CircuitSocket)
signal removed(part: PartPickup, socket: CircuitSocket)
signal swapped(placed_part: PartPickup, taken_part: PartPickup, socket: CircuitSocket)
signal dropped(part: PartPickup)
signal invalid_action
## The highlighted target (null for none) or its name-tag text changed.
## `carrying`: whether Ohmie holds a part now.
signal target_changed(target: Interactable, tag_text: String, carrying: bool)

## The body whose floor state decides whether Ohmie can interact at all.
@export var body: CharacterBody2D
## Interaction range in pixels, measured from the body centre.
@export var reach: float = 56.0
## Same-level rule: Ohmie's feet must be within this many pixels (vertically)
## of a target's standing surface.
@export var level_tolerance: float = 24.0
## From the feet to the body centre (half the 88 px collider).
@export var body_centre_offset: Vector2 = Vector2(0, -44)
## How far a put-down may slide along the surface to find a valid spot.
@export var put_down_max_slide: float = 64.0
## Step between the spots tried when a returning part's home is taken.
@export var return_home_step: float = 64.0

var _carried: PartPickup = null
var _target: Interactable = null
var _enabled: bool = true
## What target_changed last announced.
var _announced_target: Interactable = null
var _announced_text: String = ""
var _announced_carrying: bool = false

@onready var _carried_icon: PartIcon = $CarriedIcon


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
	_announce_target()


## The part in Ohmie's hands, or null.
func get_carried() -> PartPickup:
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
		_announce_target()


## Sends a carried part back to where the level first put it (after a
## fall), or beside it if another loose part lies there.
func return_carried_home() -> void:
	if _carried == null:
		return
	var part: PartPickup = _carried
	_set_carried(null)
	part.place_loose(_placement().find_return_spot(part.home_position, return_home_step))


func _interact() -> void:
	var socket: CircuitSocket = _target as CircuitSocket
	var pickup: PartPickup = _target as PartPickup
	if _carried == null:
		if pickup != null:
			pickup.take()
			_set_carried(pickup)
			_set_target(null)
			picked_up.emit(pickup)
		elif socket != null and socket.is_filled():
			var taken: PartPickup = socket.take_out()
			_set_carried(taken)
			removed.emit(taken, socket)
		else:
			invalid_action.emit()
		return

	var held: PartPickup = _carried
	if socket != null:
		if socket.is_filled():
			var old: PartPickup = socket.swap(held)
			_set_carried(old)
			swapped.emit(held, old, socket)
		else:
			_set_carried(null)
			socket.insert(held)
			placed.emit(held, socket)
		return

	var spot: Vector2 = _placement().find_put_down(global_position, put_down_max_slide)
	if spot == PartPlacement.NO_SPOT:
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
		if absf(global_position.y - candidate.get_standing_y()) > level_tolerance:
			continue
		var distance: float = centre.distance_to(candidate.get_interaction_point())
		if distance <= reach and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## A placement helper that knows every other loose part and every area where
## a part may not lie (PartBlockers: bounce pads, static hazards, slots,
## fixed board parts, lamps, meters and the door).
func _placement() -> PartPlacement:
	var others: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var pickup: PartPickup = node as PartPickup
		if pickup != null and pickup.is_loose() and pickup != _carried:
			others.append(pickup.global_position)
	var blocked: Array[Rect2] = []
	for node: Node in get_tree().get_nodes_in_group(PartBlocker.GROUP):
		var blocker: PartBlocker = node as PartBlocker
		if blocker != null:
			blocked.append(blocker.get_global_rect())
	return PartPlacement.new(get_world_2d().direct_space_state, others, blocked)


func _set_target(target: Interactable) -> void:
	if target == _target:
		return
	if _target != null and is_instance_valid(_target):
		_target.set_highlighted(false)
	_target = target
	if _target != null:
		_target.set_highlighted(true)


## Emits target_changed when the target, its tag text or the hands changed
## since the last announcement.
func _announce_target() -> void:
	var target: Interactable = _target if _target != null and is_instance_valid(_target) else null
	var text: String = target.get_tag_text() if target != null else ""
	var carrying: bool = _carried != null
	if target == _announced_target and text == _announced_text and carrying == _announced_carrying:
		return
	_announced_target = target
	_announced_text = text
	_announced_carrying = carrying
	target_changed.emit(target, text, carrying)


func _set_carried(part: PartPickup) -> void:
	_carried = part
	_carried_icon.set_part(part.part if part != null else null)
	_carried_icon.visible = part != null
