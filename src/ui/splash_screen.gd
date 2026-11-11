class_name SplashScreen
extends Control
## The splash sequence on a near-black warm background: two cards, each
## fading in, holding, and fading out: "Made with Godot Engine" with the
## Godot icon, then "<producer> presents" (the producer is the project setting
## application/config/producer). Then the title. Any key or click skips to the title.

const PRODUCER_SETTING: String = "application/config/producer"
const PRODUCER_FALLBACK: String = "An Ohmie Workshop production"
const ICON: Texture2D = preload("res://icon.svg")

const BACKGROUND: Color = Color("120d0a")
const GLOW: Color = Color(0.3, 0.19, 0.11, 0.55)
const FADE_IN_SECONDS: float = 0.5
const HOLD_SECONDS: float = 1.6
const FADE_OUT_SECONDS: float = 0.5
const GAP_SECONDS: float = 0.2
## The title fades in from black more slowly than an ordinary screen change.
const TITLE_REVEAL_SECONDS: float = 0.7

const ICON_SIZE: Vector2 = Vector2(144, 144)

var _cards: Array[Control] = []
var _card_index: int = -1
var _done: bool = false


func _ready() -> void:
	_build_background()
	_cards.append(_build_engine_card())
	_cards.append(_build_producer_card())
	for card: Control in _cards:
		card.modulate.a = 0.0
		add_child(card)
	_play()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	var button: InputEventMouseButton = event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo) or (button != null and button.pressed):
		get_viewport().set_input_as_handled()
		_finish()


## The card being shown: 0 the engine card, 1 the producer card, 2 when finished.
func get_card_index() -> int:
	return _card_index


## The producer name as shown on the second card.
static func producer() -> String:
	var value: String = str(ProjectSettings.get_setting(PRODUCER_SETTING, "")).strip_edges()
	return value if not value.is_empty() else PRODUCER_FALLBACK


func _play() -> void:
	for i: int in _cards.size():
		if _done:
			return
		_card_index = i
		var tween: Tween = create_tween()
		tween.tween_property(_cards[i], "modulate:a", 1.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE)
		tween.tween_interval(HOLD_SECONDS)
		tween.tween_property(_cards[i], "modulate:a", 0.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
		tween.tween_interval(GAP_SECONDS)
		await tween.finished
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_card_index = _cards.size()
	ScreenFade.go_to(get_tree(), ScreenFade.TITLE, TITLE_REVEAL_SECONDS)


func _build_background() -> void:
	var fill: ColorRect = ColorRect.new()
	fill.color = BACKGROUND
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, GLOW)
	gradient.set_color(1, Color(GLOW, 0.0))
	var glow_texture: GradientTexture2D = GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 1.0)
	var glow: TextureRect = TextureRect.new()
	glow.texture = glow_texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(glow)


func _build_engine_card() -> Control:
	var card: VBoxContainer = _card("EngineCard")
	var icon: TextureRect = TextureRect.new()
	icon.texture = ICON
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	card.add_child(_spacer(18))
	card.add_child(MenuStyle.art_label("Made with", 24, 4, MenuStyle.italic_font()))
	card.add_child(MenuStyle.art_label("Godot Engine", 46, 6, MenuStyle.bold_font()))
	return card


func _build_producer_card() -> Control:
	var card: VBoxContainer = _card("ProducerCard")
	var name_label: Label = MenuStyle.art_label(producer(), 64, 7, MenuStyle.bold_font())
	name_label.name = "Producer"
	card.add_child(name_label)
	card.add_child(_rule())
	card.add_child(MenuStyle.art_label("presents", 30, 4, MenuStyle.italic_font()))
	return card


func _card(card_name: String) -> VBoxContainer:
	var card: VBoxContainer = VBoxContainer.new()
	card.name = card_name
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_constant_override(&"separation", 4)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	return card


## A short brass rule between the producer and "presents".
func _rule() -> Control:
	var holder: CenterContainer = CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, 26)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line: ColorRect = ColorRect.new()
	line.color = MenuStyle.GOLD
	line.custom_minimum_size = Vector2(180, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)
	return holder


func _spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
