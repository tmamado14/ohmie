class_name RoomTile
extends Control
## One room on the level select: the brass slot frame with the room number on
## its parchment, in one of four states:
## - COMPLETED: the number and a green check badge on the top-right corner;
## - UNLOCKED: the number;
## - LOCKED: dimmed, a padlock in the middle, the number small underneath;
## - UNBUILT: the locked look, with "soon" in place of the number.
## Selected: scaled up and brighter with a warm glow. It only reports the
## mouse (hovered, clicked); the screen owns selection.

signal hovered
signal clicked

enum State { COMPLETED, UNLOCKED, LOCKED, UNBUILT }

const FRAME: Texture2D = preload("res://assets/ui/decor/blank_resistor_slot.png")
const LOCK: Texture2D = preload("res://assets/processed/ui_lock.png")
const CHECK: Texture2D = preload("res://assets/processed/ui_check.png")

const TILE_SIZE: Vector2 = Vector2(112, 112)
const NUMBER_FONT_SIZE: int = 46
const SMALL_NUMBER_RECT: Rect2 = Rect2(0, 72, 112, 24)
const LOCK_RECT: Rect2 = Rect2(34, 24, 44, 44)
const CHECK_RECT: Rect2 = Rect2(72, -10, 48, 48)
const SELECTED_SCALE: float = 1.12
## Not built yet: darker and slightly see-through, a step below locked.
const UNBUILT_MODULATE: Color = Color(0.5, 0.48, 0.47, 0.85)
const TWEEN_SECONDS: float = 0.12
const SHAKE_PIXELS: float = 7.0
const SHAKE_STEP_SECONDS: float = 0.04

var _state: State = State.UNLOCKED
var _selected: bool = false
var _body: Control = null
var _glow: Panel = null
var _shake: Tween = null


func _ready() -> void:
	custom_minimum_size = TILE_SIZE
	size = TILE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit())


func setup(number: int, state: State) -> void:
	_state = state
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_start() else Control.CURSOR_ARROW
	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_body, Rect2(Vector2.ZERO, TILE_SIZE))
	_body.pivot_offset = TILE_SIZE * 0.5
	add_child(_body)
	_glow = Panel.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.82, 0.42, 0.2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(1.0, 0.76, 0.3, 0.6)
	style.shadow_size = 16
	_glow.add_theme_stylebox_override(&"panel", style)
	MenuStyle.place(_glow, Rect2(Vector2(4, 4), TILE_SIZE - Vector2(8, 8)))
	_body.add_child(_glow)
	_body.add_child(_texture_rect(FRAME, Rect2(Vector2.ZERO, TILE_SIZE)))
	match state:
		State.COMPLETED, State.UNLOCKED:
			var label: Label = MenuStyle.ink_label(str(number), NUMBER_FONT_SIZE, MenuStyle.bold_font())
			label.name = "Number"
			MenuStyle.place(label, Rect2(Vector2(0, -2), TILE_SIZE))
			_body.add_child(label)
		State.LOCKED, State.UNBUILT:
			_body.add_child(_texture_rect(LOCK, LOCK_RECT))
			var caption: String = str(number) if state == State.LOCKED else "soon"
			var small: Label = MenuStyle.ink_label(caption, 19 if state == State.LOCKED else 16,
					MenuStyle.bold_font() if state == State.LOCKED else MenuStyle.italic_font())
			small.name = "Number"
			MenuStyle.place(small, SMALL_NUMBER_RECT)
			_body.add_child(small)
	if state == State.COMPLETED:
		var check: TextureRect = _texture_rect(CHECK, CHECK_RECT)
		check.name = "Check"
		_body.add_child(check)
	_apply(false)


func get_state() -> State:
	return _state


## True when the room can be started (completed or unlocked).
func can_start() -> bool:
	return _state == State.COMPLETED or _state == State.UNLOCKED


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	_apply(true)


## A short side-to-side shake (a room that cannot be started was chosen).
func shake() -> void:
	if _body == null:
		return
	if _shake != null and _shake.is_valid():
		_shake.kill()
	_shake = create_tween()
	for offset: float in [SHAKE_PIXELS, -SHAKE_PIXELS, SHAKE_PIXELS * 0.6, -SHAKE_PIXELS * 0.6, 0.0]:
		_shake.tween_property(_body, "position:x", offset, SHAKE_STEP_SECONDS)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()


func _texture_rect(texture: Texture2D, rect: Rect2) -> TextureRect:
	var texture_rect: TextureRect = TextureRect.new()
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(texture_rect, rect)
	return texture_rect


func _apply(animate: bool) -> void:
	if _body == null:
		return
	_glow.visible = _selected
	var target_scale: Vector2 = Vector2.ONE * (SELECTED_SCALE if _selected else 1.0)
	var target_modulate: Color = MenuStyle.SELECTED_MODULATE if _selected else MenuStyle.UNSELECTED_MODULATE
	if _state == State.LOCKED:
		target_modulate = Color(0.85, 0.83, 0.8) if _selected else MenuStyle.LOCKED_MODULATE
	elif _state == State.UNBUILT:
		target_modulate = Color(0.7, 0.68, 0.66, 0.95) if _selected else UNBUILT_MODULATE
	if not animate or not is_inside_tree():
		_body.scale = target_scale
		_body.modulate = target_modulate
		return
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "scale", target_scale, TWEEN_SECONDS)
	tween.tween_property(_body, "modulate", target_modulate, TWEEN_SECONDS)
