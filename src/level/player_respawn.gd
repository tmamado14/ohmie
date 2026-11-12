class_name PlayerRespawn
extends Node2D
## Ohmie's single way back to the room's spawn, used by a fall into a pit and
## by a zap from an enemy or hazard.
##
## respawn_now() (a pit fall) at once returns a carried part to its home, puts
## Ohmie at the spawn and starts `grace_time` seconds of invulnerability, shown
## by a blink. zap() first freezes Ohmie for `hit_freeze_time` seconds with a
## hit flash at his body centre, ignoring input, then does the same respawn.
## While frozen or invulnerable further zaps are ignored. The circuit is never
## touched.
##
## The room owns this node and hands it the player and the carry component.

## Emitted when a zap is accepted (once per zap, at the start of the freeze).
signal zapped
## Emitted every time Ohmie is put back at the spawn.
signal respawned

## Seconds Ohmie stays frozen after a zap before respawning.
@export var hit_freeze_time: float = 0.45
## Seconds of invulnerability after every respawn.
@export var grace_time: float = 0.6
## Shown at Ohmie's body centre when he is zapped.
@export var hit_flash_scene: PackedScene
## From the feet to the body centre (half the 88 px collider).
@export var body_centre_offset: Vector2 = Vector2(0, -44)

var _player: Player = null
var _carry: PlayerCarry = null
var _spawn: Vector2 = Vector2.ZERO
var _zapping: bool = false
var _freeze_left: float = 0.0
var _grace_left: float = 0.0


## `carry` may be null. `spawn` is the floor point Ohmie returns to.
func setup(player: Player, carry: PlayerCarry, spawn: Vector2) -> void:
	_player = player
	_carry = carry
	_spawn = spawn


## True during the freeze after a zap.
func is_zapping() -> bool:
	return _zapping


## True during the grace period after a respawn.
func is_invulnerable() -> bool:
	return _grace_left > 0.0


## True when a zap would be accepted now.
func can_be_zapped() -> bool:
	return _player != null and not _zapping and _grace_left <= 0.0


## Starts the hit beat; Ohmie respawns when it ends. Returns false (and does
## nothing) while he is already frozen or invulnerable.
func zap() -> bool:
	if not can_be_zapped():
		return false
	_zapping = true
	_freeze_left = hit_freeze_time
	_player.set_frozen(true)
	if _carry != null:
		_carry.set_enabled(false)
	_show_hit_flash()
	zapped.emit()
	return true


## Sends a carried part home, puts Ohmie at the spawn and starts the grace
## period. Ends a running freeze.
func respawn_now() -> void:
	if _player == null:
		return
	var was_zapping: bool = _zapping
	_zapping = false
	_freeze_left = 0.0
	if _carry != null:
		_carry.return_carried_home()
	_player.respawn(_spawn)
	if was_zapping:
		_player.set_frozen(false)
		if _carry != null:
			_carry.set_enabled(true)
	_grace_left = grace_time
	_player.set_blinking(_grace_left > 0.0)
	respawned.emit()


func _physics_process(delta: float) -> void:
	if _zapping:
		_freeze_left -= delta
		if _freeze_left <= 0.0:
			respawn_now()
	elif _grace_left > 0.0:
		_grace_left -= delta
		if _grace_left <= 0.0:
			_grace_left = 0.0
			_player.set_blinking(false)


func _show_hit_flash() -> void:
	if hit_flash_scene == null:
		return
	var flash: Node2D = hit_flash_scene.instantiate() as Node2D
	if flash == null:
		return
	add_child(flash)
	flash.global_position = _player.global_position + body_centre_offset
