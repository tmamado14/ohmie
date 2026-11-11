class_name WorldCard
extends Control
## One world on the world select: a cropped thumbnail of the world's
## background pinned in the wooden puzzle frame, then "WORLD n", the name, the
## topic line and (for an open world) the room progress. A locked world shows
## a desaturated, dimmed thumbnail under a padlock.
## Selected: lifted, scaled up, brighter, with a warm glow behind the frame.
## It only reports the mouse (hovered, clicked); the screen owns selection.

signal hovered
signal clicked

const FRAME: Texture2D = preload("res://assets/ui/decor/blank_puzzle_panel.png")
const LOCK: Texture2D = preload("res://assets/processed/ui_lock.png")
const CHECK: Texture2D = preload("res://assets/processed/ui_check.png")

const CARD_SIZE: Vector2 = Vector2(224, 312)
const BACKING_RECT: Rect2 = Rect2(-4, -4, 232, 320)
const FRAME_RECT: Rect2 = Rect2(6, 8, 212, 132)
## The picture inside the frame's parchment.
const THUMB_RECT: Rect2 = Rect2(40, 29, 144, 92)
const LOCK_SIZE: Vector2 = Vector2(64, 64)
const NUMBER_RECT: Rect2 = Rect2(0, 148, 224, 24)
const NAME_RECT: Rect2 = Rect2(4, 172, 216, 62)
const TOPIC_RECT: Rect2 = Rect2(0, 240, 224, 26)
const PROGRESS_RECT: Rect2 = Rect2(0, 270, 224, 30)
const PROGRESS_ICON_SIZE: Vector2 = Vector2(26, 26)

const SELECTED_SCALE: float = 1.07
const SELECTED_LIFT: float = 12.0
const TWEEN_SECONDS: float = 0.14
const SHAKE_PIXELS: float = 9.0
const SHAKE_STEP_SECONDS: float = 0.045

const DESATURATE_SHADER: String = """
shader_type canvas_item;
uniform float amount = 0.85;
uniform float darken = 0.55;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(grey), amount) * darken;
	COLOR = c * COLOR;
}
"""

var _locked: bool = false
var _selected: bool = false
var _body: Control = null
var _backing: Panel = null
var _shake: Tween = null


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit())


## Builds the card for `world`. `thumbnail` is the world's background;
## `completed` and `total` are its room progress (shown for open worlds).
func setup(world: CampaignWorld, thumbnail: Texture2D, completed: int, total: int) -> void:
	_locked = world.locked
	mouse_default_cursor_shape = Control.CURSOR_ARROW if _locked else Control.CURSOR_POINTING_HAND
	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_body, Rect2(Vector2.ZERO, CARD_SIZE))
	_body.pivot_offset = CARD_SIZE * 0.5
	add_child(_body)
	_backing = Panel.new()
	_backing.name = "Backing"
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_backing, BACKING_RECT)
	_body.add_child(_backing)
	var frame: TextureRect = _texture_rect(FRAME, FRAME_RECT)
	_body.add_child(frame)
	var thumb: TextureRect = _texture_rect(thumbnail, THUMB_RECT)
	thumb.name = "Thumbnail"
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if _locked:
		var material: ShaderMaterial = ShaderMaterial.new()
		var shader: Shader = Shader.new()
		shader.code = DESATURATE_SHADER
		material.shader = shader
		thumb.material = material
	_body.add_child(thumb)
	if _locked:
		var lock_at: Vector2 = THUMB_RECT.get_center() - LOCK_SIZE * 0.5
		var lock: TextureRect = _texture_rect(LOCK, Rect2(lock_at, LOCK_SIZE))
		lock.name = "Lock"
		_body.add_child(lock)

	var number: Label = MenuStyle.art_label("WORLD %d" % world.number, 17, 5, MenuStyle.bold_font())
	number.add_theme_color_override(&"font_color", MenuStyle.GOLD)
	MenuStyle.place(number, NUMBER_RECT)
	_body.add_child(number)
	var title: Label = MenuStyle.art_label(world.name, 24, 7, MenuStyle.bold_font())
	title.name = "Name"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override(&"line_spacing", -6)
	MenuStyle.place(title, NAME_RECT)
	_body.add_child(title)
	var topic: Label = MenuStyle.art_label(world.topic, 19, 5, MenuStyle.italic_font())
	MenuStyle.place(topic, TOPIC_RECT)
	_body.add_child(topic)
	if not _locked:
		_body.add_child(_progress_line(completed, total))
	_apply(false)


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	_apply(true)


func is_locked() -> bool:
	return _locked


## A short side-to-side shake (a locked world was chosen).
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


func _progress_line(completed: int, total: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	MenuStyle.place(row, PROGRESS_RECT)
	var icon: TextureRect = TextureRect.new()
	icon.texture = CHECK
	icon.custom_minimum_size = PROGRESS_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text: Label = MenuStyle.art_label("%d / %d rooms" % [completed, total], 19, 5)
	text.name = "Progress"
	text.add_theme_color_override(&"font_color", MenuStyle.GOLD)
	row.add_child(text)
	return row


## The dark card behind the frame and text; brass-edged, gold and glowing when selected.
static func _backing_style(selected: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.065, 0.045, 0.72 if selected else 0.5)
	style.set_corner_radius_all(16)
	style.set_border_width_all(3 if selected else 2)
	style.border_color = MenuStyle.GOLD if selected else Color(0.42, 0.28, 0.16, 0.8)
	if selected:
		style.shadow_color = Color(1.0, 0.74, 0.3, 0.45)
		style.shadow_size = 14
	return style


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
	_backing.add_theme_stylebox_override(&"panel", _backing_style(_selected))
	var target_scale: Vector2 = Vector2.ONE * (SELECTED_SCALE if _selected else 1.0)
	var target_y: float = -SELECTED_LIFT if _selected else 0.0
	var target_modulate: Color = MenuStyle.SELECTED_MODULATE if _selected else MenuStyle.UNSELECTED_MODULATE
	if _locked:
		target_modulate = Color(0.95, 0.93, 0.9) if _selected else MenuStyle.LOCKED_MODULATE
	if not animate or not is_inside_tree():
		_body.scale = target_scale
		_body.position.y = target_y
		_body.modulate = target_modulate
		return
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "scale", target_scale, TWEEN_SECONDS)
	tween.tween_property(_body, "position:y", target_y, TWEEN_SECONDS)
	tween.tween_property(_body, "modulate", target_modulate, TWEEN_SECONDS)
