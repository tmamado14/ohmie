extends SceneTree
## Generates placeholder pixel art into res://assets/processed/.
##
## Run from the project root, then re-import:
##   godot --headless --path . --script res://tools/generate_placeholders.gd
##   godot --headless --path . --import
##
## Every pixel is written with set_pixel (no blending, no anti-aliasing). Colours are
## taken from assets/environment/tileset_32px.png and assets/ui/resistor_slot_empty.png.

const OUTPUT_DIR: String = "res://assets/processed/"

const DARK: Color = Color("182e3a")        # outline / dark teal
const PANEL: Color = Color("102a36")       # slot inner panel
const PANEL_ALPHA: float = 200.0 / 255.0   # semi-opaque inner panel
const COPPER: Color = Color("b66b39")
const ORANGE: Color = Color("ecaa57")      # copper highlight
const GOLD: Color = Color("eab940")
const CREAM: Color = Color("ffe2a0")       # gold highlight
const CYAN: Color = Color("4bd3c2")
const CLEAR: Color = Color(0, 0, 0, 0)

## Socket / pickup frame: a 96x64 resistor icon sits at (4, 4) inside a 104x72 canvas.
const FRAME_SIZE: Vector2i = Vector2i(104, 72)
const LEAD_LENGTH: int = 10        # stub length from each side edge, in px
const LEAD_TOP_ROW: int = 34       # copper rows 34..37, centred on y = 36
const LEAD_THICKNESS: int = 4


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures: int = 0
	failures += _save(_socket(false), "socket_empty.png")
	failures += _save(_socket(true), "socket_highlight.png")
	failures += _save(_node_dot(), "node_dot.png")
	failures += _save(_terminal(), "terminal.png")
	failures += _save(_pickup_highlight(), "pickup_highlight.png")
	quit(1 if failures > 0 else 0)


func _save(img: Image, file_name: String) -> int:
	var path: String = OUTPUT_DIR + file_name
	var err: Error = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("generate_placeholders: could not save %s (%s)" % [path, error_string(err)])
		return 1
	print("generate_placeholders: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	return 0


func _blank(size: Vector2i) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


## Fills a rectangle inset by `inset` px from the canvas edge, with pixel-rounded corners.
func _fill_rounded(img: Image, inset: int, radius: int, color: Color) -> void:
	var x0: int = inset
	var y0: int = inset
	var x1: int = img.get_width() - 1 - inset
	var y1: int = img.get_height() - 1 - inset
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if _inside_rounded(x, y, x0, y0, x1, y1, radius):
				img.set_pixel(x, y, color)


func _inside_rounded(x: int, y: int, x0: int, y0: int, x1: int, y1: int, radius: int) -> bool:
	if radius <= 0:
		return true
	var cx: float = clampf(x + 0.5, x0 + radius, x1 + 1 - radius)
	var cy: float = clampf(y + 0.5, y0 + radius, y1 + 1 - radius)
	var dx: float = x + 0.5 - cx
	var dy: float = y + 0.5 - cy
	return dx * dx + dy * dy <= radius * radius


## Hard-edged disc centred on pixel-grid point (cx, cy).
func _disc(img: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	var r2: float = radius * radius
	for y: int in img.get_height():
		for x: int in img.get_width():
			var dx: float = x + 0.5 - cx
			var dy: float = y + 0.5 - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)


func _rect(img: Image, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	for y: int in range(y0, y0 + h):
		for x: int in range(x0, x0 + w):
			img.set_pixel(x, y, color)


## 5x5 dot with the four corner pixels cut, centred on (cx, cy).
func _corner_dot(img: Image, cx: int, cy: int, color: Color) -> void:
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if absi(dx) == 2 and absi(dy) == 2:
				continue
			img.set_pixel(cx + dx, cy + dy, color)


## Copper lead stubs on the left and right edges, centred at mid-height, dark outlined.
func _lead_stubs(img: Image) -> void:
	var w: int = img.get_width()
	var top: int = LEAD_TOP_ROW
	# Dark outline above, below and on the inner end; the outer end is open so a wire joins it.
	_rect(img, 0, top - 1, LEAD_LENGTH, LEAD_THICKNESS + 2, DARK)
	_rect(img, w - LEAD_LENGTH, top - 1, LEAD_LENGTH, LEAD_THICKNESS + 2, DARK)
	_rect(img, 0, top, LEAD_LENGTH - 1, LEAD_THICKNESS, COPPER)
	_rect(img, w - LEAD_LENGTH + 1, top, LEAD_LENGTH - 1, LEAD_THICKNESS, COPPER)
	_rect(img, 0, top + 1, LEAD_LENGTH - 1, 1, ORANGE)
	_rect(img, w - LEAD_LENGTH + 1, top + 1, LEAD_LENGTH - 1, 1, ORANGE)


func _socket(highlight: bool) -> Image:
	var img: Image = _blank(FRAME_SIZE)
	var panel: Color = Color(PANEL.r, PANEL.g, PANEL.b, PANEL_ALPHA)
	_fill_rounded(img, 0, 3, DARK)
	var w: int = FRAME_SIZE.x
	var h: int = FRAME_SIZE.y
	if highlight:
		# Thicker, brighter border: gold / cream / gold, 3 px.
		_fill_rounded(img, 1, 3, GOLD)
		_fill_rounded(img, 2, 2, CREAM)
		_fill_rounded(img, 3, 2, GOLD)
		_fill_rounded(img, 4, 1, panel)
		for p: Vector2i in [Vector2i(5, 5), Vector2i(w - 6, 5), Vector2i(5, h - 6), Vector2i(w - 6, h - 6)]:
			_corner_dot(img, p.x, p.y, CYAN)
	else:
		# Thin cyan border, 1 px, gold corner dots straddling it (as in resistor_slot_empty.png).
		_fill_rounded(img, 1, 2, CYAN)
		_fill_rounded(img, 2, 1, panel)
		for p: Vector2i in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, h - 4), Vector2i(w - 4, h - 4)]:
			_corner_dot(img, p.x, p.y, GOLD)
	_lead_stubs(img)
	return img


func _pickup_highlight() -> Image:
	var img: Image = _blank(FRAME_SIZE)
	_fill_rounded(img, 0, 3, DARK)
	_fill_rounded(img, 1, 3, GOLD)
	_fill_rounded(img, 2, 2, CREAM)
	_fill_rounded(img, 3, 2, GOLD)
	_fill_rounded(img, 4, 1, CLEAR)
	return img


func _node_dot() -> Image:
	var img: Image = _blank(Vector2i(16, 16))
	_disc(img, 8.0, 8.0, 7.0, DARK)
	_disc(img, 8.0, 8.0, 5.5, COPPER)
	_disc(img, 7.0, 7.0, 3.0, ORANGE)
	img.set_pixel(5, 5, CREAM)
	img.set_pixel(6, 5, CREAM)
	img.set_pixel(5, 6, CREAM)
	return img


func _terminal() -> Image:
	var img: Image = _blank(Vector2i(32, 32))
	var c: float = 16.0
	_disc(img, c, c, 15.0, DARK)
	_disc(img, c, c, 13.0, GOLD)
	# Light upper-left rim, shaded lower-right rim.
	for y: int in 32:
		for x: int in 32:
			if img.get_pixel(x, y) != GOLD:
				continue
			var dx: float = x + 0.5 - c
			var dy: float = y + 0.5 - c
			if dx * dx + dy * dy < 9.5 * 9.5:
				continue
			if dx + dy < -8.0:
				img.set_pixel(x, y, CREAM)
			elif dx + dy > 8.0:
				img.set_pixel(x, y, ORANGE)
	# Post cap: dark ring, gold cap with a light spot, dark centre hole. No slot or cross,
	# so it does not read as a minus or plus polarity sign.
	_disc(img, c, c, 8.0, DARK)
	_disc(img, c, c, 6.5, GOLD)
	_disc(img, c - 2.0, c - 2.0, 2.5, CREAM)
	_disc(img, c, c, 2.0, DARK)
	return img
