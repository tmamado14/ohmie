class_name TitleScreen
extends Control
## The title screen: the bobbing "Ohmie" logotype (it scales in on arrival)
## with its glowing bolt, the "Circuit Adventure" ribbon, a full-size Ohmie
## busy on the workshop floor left of the menu, and the menu
## (Play, Quit). Up/down or the mouse select, Enter/Space/E or a click confirm.
## Play goes to the world select; Quit closes the game. Starts the menu music.

const RIBBON: Texture2D = preload("res://assets/ui/decor/blank_victory_ribbon.png")
const BOLT: Texture2D = preload("res://assets/ui/decor/energy_bolt.png")
const BOLT_REGION: Rect2 = Rect2(4, 10, 70, 112)

const GAME_NAME: String = "Ohmie"
const SUBTITLE: String = "Circuit Adventure"
const VERSION_LINE: String = "v0.2 · World 1 preview"
const HINT_ENTRIES: PackedStringArray = ["Arrows choose", "Enter select"]
const PLAY: String = "Play"
const QUIT: String = "Quit"

# Layout (1280x720).
const LOGO_RECT: Rect2 = Rect2(240, 28, 800, 220)
const LOGO_FONT_SIZE: int = 176
const LOGO_TILT_DEGREES: float = -3.0
## Right of the "e" with a clear gap, low enough to keep off the top edge at the top of the bob.
const BOLT_RECT: Rect2 = Rect2(990, 36, 76, 122)
const BOLT_TILT_DEGREES: float = 16.0
## Warm additive glow behind the bolt, centred on it, pulsing slowly.
const BOLT_GLOW_SIZE: Vector2 = Vector2(210, 210)
const BOLT_GLOW_COLOR: Color = Color(1.0, 0.78, 0.3, 0.85)
const BOLT_GLOW_MIN_ALPHA: float = 0.45
## A soft dark pool behind the logo and ribbon so the cream letters stand off the posters.
const HALO_RECT: Rect2 = Rect2(180, -40, 920, 470)
const HALO_ALPHA: float = 0.5
const RIBBON_RECT: Rect2 = Rect2(400, 214, 480, 156)
## Text band of the ribbon art (source pixels), scaled with the ribbon: the
## flat front panel (about x 120-480) less a margin on both sides, so the
## words never run into the folds.
const RIBBON_TEXT_SOURCE: Rect2 = Rect2(146, 44, 308, 74)
const SUBTITLE_FONT_SIZE: int = 34
const SUBTITLE_MIN_FONT_SIZE: int = 20
const BUTTON_CENTER_X: float = 640.0
const FIRST_BUTTON_Y: float = 392.0
const BUTTON_SPACING: float = 112.0
## Ohmie on the floor strip left of the menu. At scale 1.0 the character is
## about 192 px tall in its 256 px frames; 1.1 makes him about 211 px.
const OHMIE_START: Vector2 = Vector2(268, 664)
const OHMIE_SCALE: float = 1.1
## Short enough that his victory stars and jump arms stay left of the selection bolt beside the buttons.
const OHMIE_RUN_DISTANCE: float = 80.0
const OHMIE_RUN_SPEED: float = 220.0
const OHMIE_HOP_HEIGHT: float = 96.0
const OHMIE_HOP_SECONDS: float = 0.34
const OHMIE_IDLE_SECONDS: float = 2.4
const HINT_RECT: Rect2 = Rect2(0, 664, 1280, 34)
const VERSION_RECT: Rect2 = Rect2(900, 680, 360, 30)

## Logo bob: amplitude in pixels and period in seconds.
const BOB_PIXELS: float = 6.0
const BOB_SECONDS: float = 3.2
const BOLT_PULSE_SECONDS: float = 2.4
## Logo entrance: starts this small and transparent, then eases out (back) to full size.
const LOGO_INTRO_SCALE: float = 0.7
const LOGO_INTRO_DELAY: float = 0.15
const LOGO_INTRO_SECONDS: float = 0.75
const LOGO_INTRO_FADE_SECONDS: float = 0.3
const QUIT_AUDIO_FRAMES: int = 10

var _buttons: Array[TealButton] = []
var _selected: int = 0
var _logo: Control = null
var _bolt: TextureRect = null
var _bolt_glow: TextureRect = null
var _time: float = 0.0


func _ready() -> void:
	_build_logo()
	_build_ribbon()
	_build_buttons()
	_build_footer()
	var ohmie: TitleOhmie = TitleOhmie.new()
	ohmie.name = "Ohmie"
	ohmie.position = OHMIE_START
	ohmie.sprite_scale = OHMIE_SCALE
	ohmie.run_distance = OHMIE_RUN_DISTANCE
	ohmie.run_speed = OHMIE_RUN_SPEED
	ohmie.hop_height = OHMIE_HOP_HEIGHT
	ohmie.hop_seconds = OHMIE_HOP_SECONDS
	ohmie.idle_seconds = OHMIE_IDLE_SECONDS
	add_child(ohmie)
	_select(0, false)
	_play_logo_intro()
	MenuSound.play_music(self)


func _process(delta: float) -> void:
	_time += delta
	if _logo != null:
		_logo.position.y = LOGO_RECT.position.y + sin(_time * TAU / BOB_SECONDS) * BOB_PIXELS
	if _bolt != null:
		var pulse: float = 0.5 + 0.5 * sin(_time * TAU / BOLT_PULSE_SECONDS)
		_bolt.scale = Vector2.ONE * (1.0 + 0.05 * pulse)
		_bolt.modulate = Color(1.0 + 0.25 * pulse, 1.0 + 0.2 * pulse, 1.0)
		_bolt_glow.modulate.a = lerpf(BOLT_GLOW_MIN_ALPHA, 1.0, pulse)
		_bolt_glow.scale = Vector2.ONE * (0.9 + 0.15 * pulse)


func _unhandled_input(event: InputEvent) -> void:
	# No key is remembered while the title fades in: it follows the splash, and
	# a key that skipped the splash must not also choose Play.
	if ScreenFade.is_busy(get_tree()):
		return
	if event.is_action_pressed("menu_up"):
		get_viewport().set_input_as_handled()
		_select(posmod(_selected - 1, _buttons.size()), true)
	elif event.is_action_pressed("menu_down"):
		get_viewport().set_input_as_handled()
		_select(posmod(_selected + 1, _buttons.size()), true)
	elif event.is_action_pressed("menu_accept"):
		get_viewport().set_input_as_handled()
		_activate()


## The label of the selected button ("Play" or "Quit").
func get_selected_text() -> String:
	return _buttons[_selected].get_text()


func _build_logo() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.06, 0.035, 0.02, HALO_ALPHA))
	gradient.set_color(1, Color(0.06, 0.035, 0.02, 0.0))
	var halo_texture: GradientTexture2D = GradientTexture2D.new()
	halo_texture.gradient = gradient
	halo_texture.fill = GradientTexture2D.FILL_RADIAL
	halo_texture.fill_from = Vector2(0.5, 0.5)
	halo_texture.fill_to = Vector2(0.5, 1.0)
	var halo: TextureRect = TextureRect.new()
	halo.name = "Halo"
	halo.texture = halo_texture
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(halo, HALO_RECT)
	add_child(halo)
	_logo = Control.new()
	_logo.name = "Logo"
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_logo, LOGO_RECT)
	_logo.pivot_offset = LOGO_RECT.size * 0.5
	_logo.rotation_degrees = LOGO_TILT_DEGREES
	add_child(_logo)
	var word: ArcLabel = ArcLabel.new()
	word.name = "Word"
	word.text = GAME_NAME
	word.font_size = LOGO_FONT_SIZE
	word.radius = 1500.0
	word.letter_spacing = 4.0
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(word, Rect2(Vector2.ZERO, LOGO_RECT.size))
	_logo.add_child(word)
	_bolt_glow = _build_bolt_glow()
	_logo.add_child(_bolt_glow)
	_logo.move_child(_bolt_glow, 0)  # behind the letters
	var bolt_texture: AtlasTexture = AtlasTexture.new()
	bolt_texture.atlas = BOLT
	bolt_texture.region = BOLT_REGION
	_bolt = TextureRect.new()
	_bolt.name = "Bolt"
	_bolt.texture = bolt_texture
	_bolt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(_bolt, Rect2(BOLT_RECT.position - LOGO_RECT.position, BOLT_RECT.size))
	_bolt.pivot_offset = BOLT_RECT.size * 0.5
	_bolt.rotation_degrees = BOLT_TILT_DEGREES
	_logo.add_child(_bolt)


## A soft warm radial glow, added onto the wall behind the bolt (logo-local).
func _build_bolt_glow() -> TextureRect:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, BOLT_GLOW_COLOR)
	gradient.set_color(1, Color(BOLT_GLOW_COLOR, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow: TextureRect = TextureRect.new()
	glow.name = "BoltGlow"
	glow.texture = texture
	glow.material = additive
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center: Vector2 = BOLT_RECT.get_center() - LOGO_RECT.position
	MenuStyle.place(glow, Rect2(center - BOLT_GLOW_SIZE * 0.5, BOLT_GLOW_SIZE))
	glow.pivot_offset = BOLT_GLOW_SIZE * 0.5
	return glow


## The logotype scales in from LOGO_INTRO_SCALE with an ease-out-back overshoot while it fades in.
func _play_logo_intro() -> void:
	_logo.scale = Vector2.ONE * LOGO_INTRO_SCALE
	_logo.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(_logo, "scale", Vector2.ONE, LOGO_INTRO_SECONDS).set_delay(LOGO_INTRO_DELAY) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_logo, "modulate:a", 1.0, LOGO_INTRO_FADE_SECONDS).set_delay(LOGO_INTRO_DELAY)


func _build_ribbon() -> void:
	var ribbon: TextureRect = TextureRect.new()
	ribbon.name = "Ribbon"
	ribbon.texture = RIBBON
	ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.place(ribbon, RIBBON_RECT)
	add_child(ribbon)
	var ratio: float = RIBBON_RECT.size.x / RIBBON.get_size().x
	var subtitle: Label = MenuStyle.ink_label(SUBTITLE, SUBTITLE_FONT_SIZE, MenuStyle.italic_font())
	subtitle.name = "Subtitle"
	var band: Rect2 = Rect2(RIBBON_TEXT_SOURCE.position * ratio, RIBBON_TEXT_SOURCE.size * ratio)
	subtitle.add_theme_font_size_override(&"font_size", TextFit.fit_font_size(MenuStyle.italic_font(),
			SUBTITLE, SUBTITLE_FONT_SIZE, SUBTITLE_MIN_FONT_SIZE, band.size.x))
	MenuStyle.place(subtitle, band)
	ribbon.add_child(subtitle)


func _build_buttons() -> void:
	var labels: PackedStringArray = [PLAY, QUIT]
	for i: int in labels.size():
		var button: TealButton = TealButton.new()
		button.name = labels[i] + "Button"
		button.text = labels[i]
		add_child(button)
		button.position = Vector2(BUTTON_CENTER_X - button.size.x * 0.5, FIRST_BUTTON_Y + BUTTON_SPACING * i)
		button.hovered.connect(_on_button_hovered.bind(i))
		button.clicked.connect(_on_button_clicked.bind(i))
		_buttons.append(button)


func _build_footer() -> void:
	var hint: Label = MenuStyle.hint_label(MenuStyle.hint_text(HINT_ENTRIES))
	hint.name = "Hint"
	MenuStyle.place(hint, HINT_RECT)
	add_child(hint)
	var version: Label = MenuStyle.art_label(VERSION_LINE, 16, 5)
	version.name = "Version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MenuStyle.place(version, VERSION_RECT)
	add_child(version)


func _select(index: int, with_sound: bool) -> void:
	if with_sound and index != _selected:
		MenuSound.play(self, MenuSound.SELECT)
	_selected = index
	for i: int in _buttons.size():
		_buttons[i].set_selected(i == _selected)


func _activate() -> void:
	MenuSound.play(self, MenuSound.CONFIRM)
	match _buttons[_selected].get_text():
		PLAY:
			ScreenFade.go_to(get_tree(), ScreenFade.WORLD_SELECT)
		QUIT:
			_quit()


## Stops the audio and gives its thread a few frames to let go before quitting.
func _quit() -> void:
	set_process_unhandled_input(false)
	MenuSound.stop_all(self)
	for i: int in QUIT_AUDIO_FRAMES:
		await get_tree().process_frame
	get_tree().quit()


func _on_button_hovered(index: int) -> void:
	if not ScreenFade.is_busy(get_tree()):
		_select(index, true)


func _on_button_clicked(index: int) -> void:
	if ScreenFade.is_busy(get_tree()):
		return
	_select(index, index != _selected)
	_activate()
