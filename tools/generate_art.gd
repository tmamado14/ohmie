extends SceneTree
## Generates the processed art for the new (2x, hand-inked) pack into res://assets/processed/.
##
## Run from the project root, then re-import:
##   godot --headless --path . --script res://tools/generate_art.gd
##   godot --headless --path . --import
##
## Everything is authored at 2x and is meant to be drawn at scale 0.5 with Linear filtering.
## Edges are anti-aliased (1 px coverage ramp), which suits this style. Colours are sampled
## from the pack: ink from the door outline, brass from the slot rim, copper from the door
## pipes, porcelain from the door insulators, parchment from the slot, teal from the doors.
## Source PNGs in res://assets/ are only read, never written.

const OUTPUT_DIR: String = "res://assets/processed/"
const SLOT_PATH: String = "res://assets/ui/decor/blank_resistor_slot.png"
const DOOR_CLOSED_PATH: String = "res://assets/props/exit_door_closed.png"
const DOOR_OPEN_PATH: String = "res://assets/props/exit_door_open.png"

const INK: Color = Color8(36, 24, 15)
const BRASS: Color = Color8(199, 144, 66)
const BRASS_LIGHT: Color = Color8(252, 207, 119)
const BRASS_DARK: Color = Color8(138, 90, 36)
const COPPER: Color = Color8(170, 83, 44)
const COPPER_LIGHT: Color = Color8(239, 162, 107)
const COPPER_DARK: Color = Color8(110, 52, 24)
const PORCELAIN: Color = Color8(238, 214, 178)
const PORCELAIN_LIGHT: Color = Color8(252, 238, 214)
const PORCELAIN_SHADE: Color = Color8(196, 160, 120)
const OXBLOOD: Color = Color8(150, 62, 48)
const GLOW: Color = Color8(255, 222, 120)
const GLOW_CORE: Color = Color8(255, 240, 190)
const IRON: Color = Color8(92, 100, 94)
const IRON_LIGHT: Color = Color8(150, 158, 148)
const IRON_DARK: Color = Color8(48, 52, 50)
const WALNUT: Color = Color8(92, 56, 34)
const WALNUT_DARK: Color = Color8(58, 34, 20)
const SOLDER: Color = Color8(178, 184, 186)
const SOLDER_LIGHT: Color = Color8(236, 240, 240)
const CLEAR: Color = Color(0, 0, 0, 0)

## Socket canvas (2x): 208x144, shown as 104x72.
const SOCKET_SIZE: Vector2i = Vector2i(208, 144)
## Nine-slice boundaries. The source slot is 160x160: outer ink x 7-152 / y 8-151, inner
## ink x 18-19 and 140-141 / y 18-19 and 139-140, corner screw plates inside a 40 px corner,
## lead notches on rows 69-93 (ink lines at 69-70 and 92-93). Corner cells and the notch band
## are copied 1:1; only the plain edge runs and the parchment between them are resampled.
const SLICE_SRC_X: Array[int] = [0, 40, 120, 160]
const SLICE_DST_X: Array[int] = [0, 40, 168, 208]
const SLICE_SRC_Y: Array[int] = [0, 40, 66, 96, 120, 160]
const SLICE_DST_Y: Array[int] = [0, 40, 57, 87, 104, 144]
## Result: notch rows 60-84 (centre 72.5), window x 20-187 / y 20-122, outer ink x 7-200 / y 8-135.
## Inner parchment window of the reshaped frame (inside the inner ink line), in canvas px.
const WINDOW_RECT: Rect2 = Rect2(20, 20, 168, 103)
## Outer edge of the frame (outer ink line) in canvas px; the 7-8 px around it is margin.
const FRAME_OUTER_RECT: Rect2 = Rect2(7, 8, 194, 128)
const FRAME_CORNER_RADIUS: float = 15.0
## Copper lead stubs: rows 65-78 (continuous y 65..79), centred on y = 72 = canvas mid-height.
const STUB_CENTRE_Y: float = 72.0
const STUB_HALF_THICKNESS: float = 7.0
const STUB_INNER_X: float = 26.0
## Screw centres of the reshaped frame (corners are copied 1:1 from the source).
const SCREWS: Array[Vector2] = [Vector2(25, 25), Vector2(183, 25), Vector2(25, 118), Vector2(183, 118)]

## Exit door: the open image is the closed one drawn about 8% smaller and offset.
## Scaling it by 1.09 and moving it by (-21, -14) lines its arch up with the closed door.
const DOOR_SIZE: Vector2i = Vector2i(216, 320)
const DOOR_OPEN_SCALE: float = 1.09
const DOOR_OPEN_OFFSET: Vector2i = Vector2i(-21, -14)
## A broken-off piece of the left base plinth sits at x 6-11, y 229-249 in the open image.
const DOOR_OPEN_STRAY: Rect2i = Rect2i(0, 222, 16, 34)
## Columns [x, y) between the two insulator stacks: arch, doorway and hinges come from the open door.
const DOOR_ARCH_BAND: Vector2i = Vector2i(44, 180)
## A point inside each swung-open leaf of the aligned open door.
const DOOR_LEAF_SEEDS: Array[Vector2i] = [Vector2i(57, 220), Vector2i(170, 220)]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures: int = 0
	var slot: Image = _load(SLOT_PATH)
	if slot == null:
		quit(1)
		return
	var frame: Image = _nine_slice(slot)
	failures += _save(_socket_empty(frame), "socket_empty.png")
	failures += _save(_socket_highlight(frame), "socket_highlight.png")
	failures += _save(_fixed_backing(frame), "fixed_backing.png")
	failures += _save(_pickup_highlight(), "pickup_highlight.png")
	failures += _save(_node_dot(), "node_dot.png")
	var door: Image = _door_open_aligned()
	if door == null:
		failures += 1
	else:
		failures += _save(door, "exit_door_open_aligned.png")
	quit(1 if failures > 0 else 0)


# --- I/O -------------------------------------------------------------------------------------

func _load(path: String) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("generate_art: could not load %s" % path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file_name: String) -> int:
	var path: String = OUTPUT_DIR + file_name
	var err: Error = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("generate_art: could not save %s (%s)" % [path, error_string(err)])
		return 1
	print("generate_art: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	return 0


func _blank(size: Vector2i) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


# --- Pixel helpers ---------------------------------------------------------------------------

## Composites `color` over the pixel with extra opacity `amount` (0..1).
func _over(img: Image, x: int, y: int, color: Color, amount: float) -> void:
	if amount <= 0.0:
		return
	var src: Color = Color(color.r, color.g, color.b, color.a * clampf(amount, 0.0, 1.0))
	img.set_pixel(x, y, img.get_pixel(x, y).blend(src))


## Coverage of a shape for a pixel whose centre is at signed distance `sd` (negative = inside).
func _coverage(sd: float) -> float:
	return clampf(0.5 - sd, 0.0, 1.0)


func _sd_circle(p: Vector2, centre: Vector2, radius: float) -> float:
	return p.distance_to(centre) - radius


## Signed distance to a rounded rectangle.
func _sd_round_rect(p: Vector2, rect: Rect2, radius: float) -> float:
	var centre: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	var q: Vector2 = (p - centre).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Resizes with premultiplied alpha so transparent (black) pixels do not darken the edges.
func _resize_premultiplied(img: Image, size: Vector2i) -> Image:
	var copy: Image = img.duplicate() as Image
	for y: int in copy.get_height():
		for x: int in copy.get_width():
			var c: Color = copy.get_pixel(x, y)
			copy.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	copy.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	for y: int in copy.get_height():
		for x: int in copy.get_width():
			var c: Color = copy.get_pixel(x, y)
			if c.a <= 0.0:
				copy.set_pixel(x, y, CLEAR)
			else:
				copy.set_pixel(x, y, Color(clampf(c.r / c.a, 0.0, 1.0), clampf(c.g / c.a, 0.0, 1.0), clampf(c.b / c.a, 0.0, 1.0), clampf(c.a, 0.0, 1.0)))
	return copy


func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func _saturation(c: Color) -> float:
	var hi: float = maxf(c.r, maxf(c.g, c.b))
	var lo: float = minf(c.r, minf(c.g, c.b))
	return 0.0 if hi <= 0.0 else (hi - lo) / hi


## 0..1: how much a pixel inside the window is parchment (pale, unsaturated) rather than
## brass plate or ink. Smooth, so recolouring never leaves a hard seam.
func _parchment_weight(img: Image, x: int, y: int) -> float:
	if not WINDOW_RECT.has_point(Vector2(x + 0.5, y + 0.5)):
		return 0.0
	var c: Color = img.get_pixel(x, y)
	var pale: float = smoothstep(0.55, 0.75, _luma(c))
	var unsaturated: float = 1.0 - smoothstep(0.42, 0.55, _saturation(c))
	return pale * unsaturated


## Cheap deterministic value noise in 0..1 for wood grain.
func _hash(x: int, y: int) -> float:
	var n: int = (x * 374761393 + y * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


# --- Socket frame ----------------------------------------------------------------------------

## Reshapes the 160x160 slot into a 208x144 frame. Each source cell is resampled into the
## matching destination cell; corner and notch cells keep their size, so screws and notches
## are not distorted.
func _nine_slice(src: Image) -> Image:
	var dst: Image = _blank(SOCKET_SIZE)
	for j: int in SLICE_SRC_Y.size() - 1:
		for i: int in SLICE_SRC_X.size() - 1:
			var src_rect: Rect2i = Rect2i(SLICE_SRC_X[i], SLICE_SRC_Y[j], SLICE_SRC_X[i + 1] - SLICE_SRC_X[i], SLICE_SRC_Y[j + 1] - SLICE_SRC_Y[j])
			var dst_size: Vector2i = Vector2i(SLICE_DST_X[i + 1] - SLICE_DST_X[i], SLICE_DST_Y[j + 1] - SLICE_DST_Y[j])
			var cell: Image = src.get_region(src_rect)
			if dst_size != src_rect.size:
				cell = _resize_premultiplied(cell, dst_size)
			dst.blit_rect(cell, Rect2i(Vector2i.ZERO, dst_size), Vector2i(SLICE_DST_X[i], SLICE_DST_Y[j]))
	return dst


## Darkens the parchment window into a shaded recess so a cream resistor reads against it:
## a uniform tone-down plus a soft shadow cast by the top and left frame edges.
func _recess_window(img: Image, tone: float, shadow: float) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var w: float = _parchment_weight(img, x, y)
			if w <= 0.0:
				continue
			var c: Color = img.get_pixel(x, y)
			var from_top: float = (y + 0.5) - WINDOW_RECT.position.y
			var from_left: float = (x + 0.5) - WINDOW_RECT.position.x
			var cast: float = shadow * (maxf(0.0, 1.0 - from_top / 14.0) + 0.6 * maxf(0.0, 1.0 - from_left / 12.0))
			var k: float = clampf(tone - cast, 0.0, 1.0)
			var shaded: Color = Color(c.r * k, c.g * k * 0.95, c.b * k * 0.86, c.a)
			img.set_pixel(x, y, c.lerp(shaded, w))


## Copper lead stubs on both side edges at mid-height, open at the canvas edge so a wire that
## ends at the socket edge (x = 0 or x = 208 at 2x) runs straight into them.
func _lead_stubs(img: Image, solder: bool) -> void:
	var w: int = img.get_width()
	var top: float = STUB_CENTRE_Y - STUB_HALF_THICKNESS
	var bottom: float = STUB_CENTRE_Y + STUB_HALF_THICKNESS
	for side: int in 2:
		var x_from: float = -8.0 if side == 0 else w - STUB_INNER_X
		var x_to: float = STUB_INNER_X if side == 0 else w + 8.0
		var outer: Rect2 = Rect2(x_from, top, x_to - x_from, bottom - top)
		var inner: Rect2 = outer.grow(-2.0)
		for y: int in range(int(top) - 2, int(bottom) + 2):
			for x: int in range(maxi(0, int(x_from) - 2), mini(w, int(x_to) + 2)):
				var p: Vector2 = Vector2(x + 0.5, y + 0.5)
				_over(img, x, y, INK, _coverage(_sd_round_rect(p, outer, 3.0)))
				var core: float = _coverage(_sd_round_rect(p, inner, 2.0))
				if core > 0.0:
					# Round-wire shading: light band just above centre, dark underside.
					var t: float = (p.y - inner.position.y) / inner.size.y
					var shade: Color = COPPER_LIGHT.lerp(COPPER, smoothstep(0.15, 0.45, t)).lerp(COPPER_DARK, smoothstep(0.65, 1.0, t))
					_over(img, x, y, shade, core)
		if solder:
			var blob_centre: Vector2 = Vector2(STUB_INNER_X - 4.0 if side == 0 else w - STUB_INNER_X + 4.0, STUB_CENTRE_Y)
			_disc_shaded(img, blob_centre, 9.0, SOLDER, SOLDER_LIGHT, IRON_DARK)


## Ink-outlined disc with a light upper-left and dark lower-right, for screws, rivets, blobs.
func _disc_shaded(img: Image, centre: Vector2, radius: float, base: Color, light: Color, dark: Color) -> void:
	var x0: int = maxi(0, int(centre.x - radius - 2.0))
	var x1: int = mini(img.get_width(), int(centre.x + radius + 2.0))
	var y0: int = maxi(0, int(centre.y - radius - 2.0))
	var y1: int = mini(img.get_height(), int(centre.y + radius + 2.0))
	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			_over(img, x, y, INK, _coverage(_sd_circle(p, centre, radius)))
			var fill: float = _coverage(_sd_circle(p, centre, radius - 1.8))
			if fill <= 0.0:
				continue
			var d: Vector2 = (p - centre) / maxf(radius - 1.8, 0.001)
			var lit: float = clampf(-(d.x + d.y) * 0.7, 0.0, 1.0)
			var shade: float = clampf((d.x + d.y) * 0.7, 0.0, 1.0)
			var c: Color = base.lerp(light, lit).lerp(dark, shade * 0.8)
			_over(img, x, y, c, fill)
			# Small specular dot up and to the left.
			_over(img, x, y, light, _coverage(_sd_circle(p, centre - Vector2(radius, radius) * 0.32, radius * 0.22)) * 0.9)


func _socket_empty(frame: Image) -> Image:
	var img: Image = frame.duplicate() as Image
	_recess_window(img, 0.86, 0.25)
	_lead_stubs(img, false)
	return img


func _socket_highlight(frame: Image) -> Image:
	var img: Image = _blank(SOCKET_SIZE)
	# Glow filling the 7-8 px margin around the frame (under the frame): a solid pale-gold
	# band hugging the ink outline, fading out towards the canvas edge.
	for y: int in img.get_height():
		for x: int in img.get_width():
			var sd: float = _sd_round_rect(Vector2(x + 0.5, y + 0.5), FRAME_OUTER_RECT, FRAME_CORNER_RADIUS)
			if sd < 8.0:
				var a: float = 1.0 - smoothstep(2.0, 8.0, maxf(sd, 0.0))
				_over(img, x, y, GLOW, a)
				_over(img, x, y, GLOW_CORE, _coverage(sd - 3.0))
	img.blend_rect(frame, Rect2i(Vector2i.ZERO, SOCKET_SIZE), Vector2i.ZERO)
	# Brighter, warmer brass; then a lit (not recessed) window with light pooling at the rim.
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var w: float = _parchment_weight(img, x, y)
			if w < 1.0 and _luma(c) > 0.25:
				var lifted: Color = Color(minf(c.r * 1.12 + 0.04, 1.0), minf(c.g * 1.12 + 0.03, 1.0), minf(c.b * 1.05, 1.0), c.a)
				img.set_pixel(x, y, c.lerp(lifted, 1.0 - w))
	_recess_window(img, 0.93, 0.10)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var inside: float = -_sd_round_rect(p, WINDOW_RECT, 6.0)
			if inside > 0.0 and inside < 12.0:
				_over(img, x, y, GLOW_CORE, 0.45 * (1.0 - inside / 12.0) * _parchment_weight(img, x, y))
	_lead_stubs(img, false)
	return img


## Same shape as the socket but iron and dark walnut with rivets: "soldered in, fixed".
func _fixed_backing(frame: Image) -> Image:
	var img: Image = frame.duplicate() as Image
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l: float = _luma(c)
			var wood_w: float = _parchment_weight(img, x, y)
			# Frame: brass -> gunmetal iron, keeping the art's own light and shade. Ink stays.
			var ink_keep: float = 1.0 - smoothstep(0.18, 0.32, l)
			var iron: Color = IRON_DARK.lerp(IRON, smoothstep(0.25, 0.55, l)).lerp(IRON_LIGHT, smoothstep(0.7, 0.95, l))
			var frame_c: Color = iron.lerp(Color(c.r, c.g, c.b), ink_keep)
			# Window: dark walnut planks with grain.
			var grain: float = 0.5 + 0.5 * sin(y * 0.55 + 2.2 * sin(x * 0.045 + y * 0.09))
			var speck: float = _hash(x, y)
			var plank_seam: float = 1.0 if (y - 20) % 26 == 0 else 0.0
			var wood: Color = WALNUT_DARK.lerp(WALNUT, 0.35 + 0.45 * grain + 0.2 * speck)
			wood = wood.lerp(INK, plank_seam * 0.8)
			var out: Color = frame_c.lerp(wood, wood_w)
			out.a = c.a
			img.set_pixel(x, y, out)
	# Recessed shadow inside the window, a little heavier than the empty socket.
	for y: int in img.get_height():
		for x: int in img.get_width():
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var inside: float = -_sd_round_rect(p, WINDOW_RECT, 6.0)
			if inside > 0.0 and inside < 10.0:
				_over(img, x, y, INK, 0.35 * (1.0 - inside / 10.0))
	# Rivets over the corner screws and along the top and bottom bars.
	for s: Vector2 in SCREWS:
		_disc_shaded(img, s, 8.0, IRON, IRON_LIGHT, IRON_DARK)
	for rx: float in [64.0, 104.0, 144.0]:
		_disc_shaded(img, Vector2(rx, 13.5), 4.5, IRON, IRON_LIGHT, IRON_DARK)
		_disc_shaded(img, Vector2(rx, 129.5), 4.5, IRON, IRON_LIGHT, IRON_DARK)
	_lead_stubs(img, true)
	return img


# --- Pickup highlight ------------------------------------------------------------------------

## Glowing brass outline ring with a fully transparent centre, for a loose 192x128 resistor
## drawn centred on the same 208x144 canvas.
func _pickup_highlight() -> Image:
	var img: Image = _blank(SOCKET_SIZE)
	# Ring centre line inset 5.5 px; the whole band (glow included) stays within 0..11 px of
	# the edge. A resistor drawn at (8, 8) has opaque pixels from x 15 / y 27 to x 193 / y 132,
	# so its tightest clearance is the label at the bottom (11 px from the edge).
	var ring: Rect2 = Rect2(Vector2(5.5, 5.5), Vector2(SOCKET_SIZE) - Vector2(11, 11))
	var radius: float = 18.0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d: float = absf(_sd_round_rect(p, ring, radius))
			if d >= 5.5:
				continue
			# Soft glow either side of the ring.
			var g: float = 1.0 - smoothstep(2.5, 5.5, d)
			_over(img, x, y, GLOW, g * 0.85)
			# Ink band 8 px wide, brass 5.6 px, pale-gold core 2.8 px: an inked brass hoop.
			_over(img, x, y, INK, _coverage(d - 4.0))
			_over(img, x, y, BRASS, _coverage(d - 2.8))
			_over(img, x, y, BRASS_LIGHT, _coverage(d - 1.4))
			_over(img, x, y, GLOW_CORE, _coverage(d - 0.5) * 0.8)
	return img


# --- Node dot ----------------------------------------------------------------------------------

func _node_dot() -> Image:
	var img: Image = _blank(Vector2i(32, 32))
	_disc_shaded(img, Vector2(16, 16), 13.0, COPPER, COPPER_LIGHT, COPPER_DARK)
	# Brass rim ring for a soldered-joint look.
	for y: int in 32:
		for x: int in 32:
			var d: float = absf(_sd_circle(Vector2(x + 0.5, y + 0.5), Vector2(16, 16), 9.0))
			_over(img, x, y, BRASS_DARK, _coverage(d - 0.6) * 0.6)
	_over(img, 11, 10, PORCELAIN_LIGHT, 0.8)
	return img


# --- Exit door -------------------------------------------------------------------------------

## The pack's open door is drawn about 8% smaller and further right than the closed door, its
## right insulator is cut by the canvas edge and its left base plinth is broken. This starts
## from the closed door (complete insulators, pipes and plinths), rescales and moves the open
## door onto the same footprint, then draws the open door over it between the insulators
## (arch, doorway, leaves) and, outside that band, only the two swung-open leaves.
func _door_open_aligned() -> Image:
	var closed: Image = _load(DOOR_CLOSED_PATH)
	var open: Image = _load(DOOR_OPEN_PATH)
	if closed == null or open == null:
		return null
	for y: int in range(DOOR_OPEN_STRAY.position.y, DOOR_OPEN_STRAY.end.y):
		for x: int in range(DOOR_OPEN_STRAY.position.x, DOOR_OPEN_STRAY.end.x):
			open.set_pixel(x, y, CLEAR)
	var scaled_size: Vector2i = Vector2i(roundi(DOOR_SIZE.x * DOOR_OPEN_SCALE), roundi(DOOR_SIZE.y * DOOR_OPEN_SCALE))
	var scaled: Image = _resize_premultiplied(open, scaled_size)
	var aligned: Image = _blank(DOOR_SIZE)
	var src_origin: Vector2i = -DOOR_OPEN_OFFSET
	var src_rect: Rect2i = Rect2i(src_origin, DOOR_SIZE).intersection(Rect2i(Vector2i.ZERO, scaled_size))
	aligned.blit_rect(scaled, src_rect, src_rect.position - src_origin)

	var leaves: PackedByteArray = _door_leaf_mask(aligned)
	var out: Image = closed.duplicate() as Image
	for y: int in DOOR_SIZE.y:
		for x: int in DOOR_SIZE.x:
			var in_band: bool = x >= DOOR_ARCH_BAND.x and x < DOOR_ARCH_BAND.y
			if in_band or leaves[y * DOOR_SIZE.x + x] == 1:
				var c: Color = aligned.get_pixel(x, y)
				if c.a > 0.0:
					out.set_pixel(x, y, out.get_pixel(x, y).blend(c))
	return out


## 1 where a pixel belongs to one of the two open door leaves (plus a 3 px rim for their ink
## outline), found by flood-filling the non-ink pixels around a seed inside each leaf.
func _door_leaf_mask(img: Image) -> PackedByteArray:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var fill: PackedByteArray = PackedByteArray()
	fill.resize(w * h)
	for seed: Vector2i in DOOR_LEAF_SEEDS:
		var queue: Array[Vector2i] = [seed]
		fill[seed.y * w + seed.x] = 1
		while not queue.is_empty():
			var p: Vector2i = queue.pop_back()
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = p + step
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or fill[q.y * w + q.x] == 1:
					continue
				var c: Color = img.get_pixel(q.x, q.y)
				if c.a > 0.5 and _luma(c) > 0.2:
					fill[q.y * w + q.x] = 1
					queue.append(q)
	var grown: PackedByteArray = PackedByteArray()
	grown.resize(w * h)
	var r: int = 3
	for y: int in h:
		for x: int in w:
			if fill[y * w + x] != 1:
				continue
			for dy: int in range(-r, r + 1):
				for dx: int in range(-r, r + 1):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and dx * dx + dy * dy <= r * r:
						grown[ny * w + nx] = 1
	return grown
