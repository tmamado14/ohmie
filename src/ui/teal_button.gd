class_name TealButton
extends Control
## A menu button drawn from the pack's blank teal button with a cream label.
## Selected: scaled up, brighter, with an energy bolt marker at its left.
## It only reports the mouse (hovered, clicked); the screen owns selection and
## keyboard input and calls set_selected().

signal hovered
signal clicked

const TEXTURE: Texture2D = preload("res://assets/ui/decor/blank_teal_button.png")
const BOLT: Texture2D = preload("res://assets/ui/decor/energy_bolt.png")
## The bolt itself inside energy_bolt.png (the file has a stray mark at its right edge).
const BOLT_REGION: Rect2 = Rect2(4, 10, 70, 112)
## Text area inside the button art (docs/ASSETS.md).
const TEXT_RECT: Rect2 = Rect2(46, 16, 148, 56)
const FONT_SIZE: int = 32
const SELECTED_SCALE: float = 1.08
const MARKER_SIZE: Vector2 = Vector2(30, 48)
const MARKER_GAP: float = 6.0
const TWEEN_SECONDS: float = 0.12

@export var text: String = ""

var _label: Label = null
var _marker: TextureRect = null
var _selected: bool = false


func _ready() -> void:
	custom_minimum_size = TEXTURE.get_size()
	size = TEXTURE.get_size()
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art: TextureRect = TextureRect.new()
	art.texture = TEXTURE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	_label = MenuStyle.art_label(text, FONT_SIZE, 7, MenuStyle.bold_font())
	MenuStyle.place(_label, TEXT_RECT)
	add_child(_label)
	var bolt: AtlasTexture = AtlasTexture.new()
	bolt.atlas = BOLT
	bolt.region = BOLT_REGION
	_marker = TextureRect.new()
	_marker.texture = bolt
	_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_marker, Rect2(Vector2(-MARKER_SIZE.x - MARKER_GAP, (size.y - MARKER_SIZE.y) * 0.5), MARKER_SIZE))
	_marker.rotation_degrees = -8.0
	add_child(_marker)
	mouse_entered.connect(func() -> void: hovered.emit())
	_apply(false)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	_apply(true)


func is_selected() -> bool:
	return _selected


func get_text() -> String:
	return text


func _apply(animate: bool) -> void:
	if _marker == null:
		return
	_marker.visible = _selected
	var target_scale: Vector2 = Vector2.ONE * (SELECTED_SCALE if _selected else 1.0)
	var target_modulate: Color = MenuStyle.SELECTED_MODULATE if _selected else MenuStyle.UNSELECTED_MODULATE
	if not animate or not is_inside_tree():
		scale = target_scale
		modulate = target_modulate
		return
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target_scale, TWEEN_SECONDS)
	tween.tween_property(self, "modulate", target_modulate, TWEEN_SECONDS)
