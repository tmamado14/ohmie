extends SceneTree
## Generates the circuit-part art (battery, blank resistor, meters, lamps, polarity badges)
## into res://assets/processed/.
##
## Run from the project root, then re-import:
##   godot --headless --path . --script res://tools/generate_parts_art.gd
##   godot --headless --path . --import
##
## Everything is authored at 2x and is meant to be drawn at scale 0.5 with Linear filtering,
## like tools/generate_art.gd (whose palette, lead stubs and shaded discs this reuses).
## Shapes are signed-distance fields with a 1 px anti-aliased edge, ink outlined, with a faint
## watercolour wash (low-frequency value noise plus paper speckle) on the larger fills.
## Source PNGs in res://assets/ are only read, never written.

const OUTPUT_DIR: String = "res://assets/processed/"
const RESISTOR_PATH: String = "res://assets/interactive/resistors/resistor_2ohm.png"

# --- Palette (shared with tools/generate_art.gd) --------------------------------------------
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
const WALNUT_LIGHT: Color = Color8(132, 84, 50)
const CLEAR: Color = Color(0, 0, 0, 0)

# --- Colours of the pack's resistor icons (sampled from resistor_*.png) ---------------------
const RES_INK: Color = Color8(51, 36, 29)
const RES_CREAM: Color = Color8(246, 227, 185)
const PLAQUE_CREAM: Color = Color8(248, 223, 177)
const LEAD_GREY: Color = Color8(170, 162, 154)
## Neutral band colour for the blank resistor (bands 1-3; band 4 keeps its gold).
const NEUTRAL_BAND: Color = Color8(150, 132, 110)

# --- Extra accents ---------------------------------------------------------------------------
const TEAL: Color = Color8(64, 122, 112)
const TEAL_LIGHT: Color = Color8(112, 166, 150)
const TEAL_DARK: Color = Color8(38, 78, 72)
const OXBLOOD_LIGHT: Color = Color8(196, 98, 76)
const OXBLOOD_DARK: Color = Color8(102, 38, 30)
const MUSTARD: Color = Color8(205, 165, 55)
const MUSTARD_LIGHT: Color = Color8(240, 204, 104)
const MUSTARD_DARK: Color = Color8(150, 110, 30)
const DISPLAY_CREAM: Color = Color8(250, 236, 206)
const GLASS_OFF: Color = Color8(158, 154, 140)
const GLASS_OFF_LIGHT: Color = Color8(206, 202, 186)
const GLASS_OFF_DARK: Color = Color8(100, 96, 86)
const GLASS_BLOWN: Color = Color8(84, 78, 70)
const GLASS_BLOWN_DARK: Color = Color8(46, 40, 34)
const SMOKE: Color = Color8(150, 144, 136)
const SMOKE_LIGHT: Color = Color8(200, 194, 184)

# --- Part (carried / plugged) geometry: matches the resistor icons ---------------------------
const PART_SIZE: Vector2i = Vector2i(192, 128)
## Lead rows 50-63: ink 50-52 and 61-63, grey core 53-60 (centre y = 57).
const LEAD_TOP: int = 50
const LEAD_BOTTOM: int = 63
const LEAD_LEFT_X: int = 7
const LEAD_RIGHT_X: int = 185
## Resistor body bands (columns, colour part only; each has a 1 px ink edge on its left).
const BAND_RUNS: Array[Vector2i] = [Vector2i(54, 64), Vector2i(80, 90), Vector2i(115, 125)]
## Body rows inside the outline (outline rows are 19-22 and 94-96).
const BAND_ROWS: Vector2i = Vector2i(23, 93)
## Plaque rows copied from the blank resistor onto the battery (below the body outline).
const PLAQUE_COPY: Rect2i = Rect2i(50, 97, 92, 30)
## Plaque text area that is blanked (holds every icon's baked value text, x 68-123 y 103-116).
const PLAQUE_BLANK: Rect2i = Rect2i(61, 98, 72, 23)

## Battery: positive end on the LEFT.
const BATT_BODY: Rect2 = Rect2(30, 19, 138, 78)
const BATT_BODY_RADIUS: float = 12.0
const BATT_OUTLINE: float = 4.0
const BATT_NUB: Rect2 = Rect2(12, 40, 24, 34)
const BATT_CAP_LEFT_END: float = 50.0
const BATT_CAP_RIGHT_START: float = 150.0
const BATT_PLUS_CENTRE: Vector2 = Vector2(75, 57)
const BATT_MINUS_CENTRE: Vector2 = Vector2(131, 57)
const BATT_INK_BAND: Vector2 = Vector2(97, 103)
const BATT_GOLD_BAND: Vector2 = Vector2(103, 111)

# --- Board fixture geometry: matches socket_empty.png (208x144, stubs at y = 72) -------------
const FIXTURE_SIZE: Vector2i = Vector2i(208, 144)
const STUB_CENTRE_Y: float = 72.0
const STUB_HALF_THICKNESS: float = 7.0
const STUB_INNER_X: float = 26.0

## Meter case, brass bezel, parchment face and display window (canvas px).
const METER_CASE: Rect2 = Rect2(12, 5, 184, 134)
const METER_BEZEL: Rect2 = Rect2(20, 12, 168, 120)
const METER_FACE: Rect2 = Rect2(26, 18, 156, 108)
## Display window, outline included; its cream interior is x 33-174, y 75-120 (142x46).
const METER_WINDOW: Rect2 = Rect2(30, 72, 148, 52)
const METER_WINDOW_OUTLINE: float = 2.5
const METER_BADGE: Rect2 = Rect2(31, 21, 62, 48)
const METER_PIVOT: Vector2 = Vector2(142, 62)
const METER_ARC_RADIUS: float = 28.0
const METER_POSTS: Array[Vector2] = [Vector2(19, 72), Vector2(189, 72)]

## Lamp: bulb, screw base, flange and walnut plinth (canvas px). Same in all three states.
const BULB_CENTRE: Vector2 = Vector2(104, 47)
const BULB_RADIUS: float = 29.0
const BULB_NECK: Rect2 = Rect2(91, 62, 26, 34)
const LAMP_SCREW: Rect2 = Rect2(88, 90, 32, 22)
const LAMP_FLANGE: Rect2 = Rect2(76, 108, 56, 11)
const LAMP_PLINTH: Rect2 = Rect2(52, 116, 104, 23)
const LAMP_POSTS: Array[Vector2] = [Vector2(30, 72), Vector2(178, 72)]

## Meter kinds: letter and accent colours (fill, light, dark), needle angle in degrees.
const METERS: Dictionary = {
	"ammeter": {"letter": "A", "accent": [OXBLOOD, OXBLOOD_LIGHT, OXBLOOD_DARK], "letter_fill": PLAQUE_CREAM, "needle": -52.0},
	"voltmeter": {"letter": "V", "accent": [TEAL, TEAL_LIGHT, TEAL_DARK], "letter_fill": PLAQUE_CREAM, "needle": -118.0},
	"ohmmeter": {"letter": "O", "accent": [MUSTARD, MUSTARD_LIGHT, MUSTARD_DARK], "letter_fill": PLAQUE_CREAM, "needle": -86.0},
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures: int = 0
	var resistor: Image = _load(RESISTOR_PATH)
	if resistor == null:
		quit(1)
		return
	var blank_resistor: Image = _resistor_blank(resistor)
	failures += _save(blank_resistor, "part_resistor_blank.png")
	failures += _save(_battery(blank_resistor), "part_battery.png")
	for kind: String in METERS:
		failures += _save(_meter(METERS[kind]), "meter_%s.png" % kind)
	failures += _save(_lamp("off"), "lamp_off.png")
	failures += _save(_lamp("on"), "lamp_on.png")
	failures += _save(_lamp("blown"), "lamp_blown.png")
	failures += _save(_polarity(true), "polarity_plus.png")
	failures += _save(_polarity(false), "polarity_minus.png")
	quit(1 if failures > 0 else 0)


# --- I/O -------------------------------------------------------------------------------------

func _load(path: String) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("generate_parts_art: could not load %s" % path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file_name: String) -> int:
	var path: String = OUTPUT_DIR + file_name
	var err: Error = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("generate_parts_art: could not save %s (%s)" % [path, error_string(err)])
		return 1
	print("generate_parts_art: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	return 0


func _blank(size: Vector2i) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


# --- Pixel and shape helpers -----------------------------------------------------------------

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


func _sd_round_rect(p: Vector2, rect: Rect2, radius: float) -> float:
	var centre: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	var q: Vector2 = (p - centre).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Distance to the segment a-b (a capsule of radius 0).
func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Distance to a polyline.
func _sd_polyline(p: Vector2, points: PackedVector2Array) -> float:
	var d: float = INF
	for i: int in points.size() - 1:
		d = minf(d, _sd_segment(p, points[i], points[i + 1]))
	return d


## Distance to a circular arc (centre, radius) between angles a0 < a1 (radians, y down).
func _sd_arc(p: Vector2, centre: Vector2, radius: float, a0: float, a1: float) -> float:
	var v: Vector2 = p - centre
	var a: float = v.angle()
	# Bring the angle into [a0, a0 + TAU).
	while a < a0:
		a += TAU
	while a >= a0 + TAU:
		a -= TAU
	if a <= a1:
		return absf(v.length() - radius)
	var e0: Vector2 = centre + Vector2.from_angle(a0) * radius
	var e1: Vector2 = centre + Vector2.from_angle(a1) * radius
	return minf(p.distance_to(e0), p.distance_to(e1))


## Polynomial smooth minimum (rounds the joint between two shapes).
func _smin(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		var t: float = float(i) / steps
		out.append(p0.bezier_interpolate(p1, p2, p3, t))
	return out


## Cheap deterministic hash in 0..1.
func _hash(x: int, y: int) -> float:
	var n: int = (x * 374761393 + y * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## Smooth value noise in 0..1 with the given cell size.
func _vnoise(x: float, y: float, cell: float) -> float:
	var gx: float = x / cell
	var gy: float = y / cell
	var ix: int = floori(gx)
	var iy: int = floori(gy)
	var fx: float = smoothstep(0.0, 1.0, gx - ix)
	var fy: float = smoothstep(0.0, 1.0, gy - iy)
	var top: float = lerpf(_hash(ix, iy), _hash(ix + 1, iy), fx)
	var bottom: float = lerpf(_hash(ix, iy + 1), _hash(ix + 1, iy + 1), fx)
	return lerpf(top, bottom, fy)


## Watercolour wash: a soft low-frequency mottle plus fine paper speckle.
func _wash(c: Color, p: Vector2, amount: float) -> Color:
	var n: float = 0.65 * (_vnoise(p.x, p.y, 11.0) - 0.5) + 0.35 * (_hash(int(p.x), int(p.y)) - 0.5)
	var k: float = 1.0 + amount * n
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


## Draws a shape: an ink band `outline` px wide inside the shape's edge, then the fill.
## `sdf(p) -> float` is the shape's signed distance, `fill(p) -> Color` its colour.
func _paint(img: Image, sdf: Callable, fill: Callable, outline: float, ink: Color = INK, bounds: Rect2i = Rect2i()) -> void:
	var r: Rect2i = Rect2i(Vector2i.ZERO, img.get_size())
	if bounds.has_area():
		r = bounds.intersection(r)
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var sd: float = sdf.call(p)
			if sd > 1.0:
				continue
			if outline > 0.0:
				_over(img, x, y, ink, _coverage(sd))
			var cov: float = _coverage(sd + outline)
			if cov > 0.0:
				_over(img, x, y, fill.call(p), cov)


## Ink-outlined disc with a light upper-left and dark lower-right, for screws, rivets, nuts.
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
			_over(img, x, y, base.lerp(light, lit).lerp(dark, shade * 0.8), fill)
			_over(img, x, y, light, _coverage(_sd_circle(p, centre - Vector2(radius, radius) * 0.32, radius * 0.22)) * 0.9)


## Socket-style copper lead stubs on both side edges at y = 72, open at the canvas edge
## (same drawing as tools/generate_art.gd, so a wire meets a fixture exactly as it meets a socket).
func _lead_stubs(img: Image) -> void:
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
					var t: float = (p.y - inner.position.y) / inner.size.y
					var shade: Color = COPPER_LIGHT.lerp(COPPER, smoothstep(0.15, 0.45, t)).lerp(COPPER_DARK, smoothstep(0.65, 1.0, t))
					_over(img, x, y, shade, core)


## Round-wire colour across a tube: `t` is 0 at the top edge and 1 at the bottom edge.
func _tube(t: float, light: Color, base: Color, dark: Color) -> Color:
	return light.lerp(base, smoothstep(0.12, 0.42, t)).lerp(dark, smoothstep(0.62, 1.0, t))


# --- Glyphs ----------------------------------------------------------------------------------

## Stroke skeleton of a glyph as segments (pairs of points), centred on `c`, `h` px tall.
## "O" means the ohm sign; its ring is added as an arc by _sd_glyph.
func _glyph_segments(ch: String, c: Vector2, h: float) -> PackedVector2Array:
	var top: float = c.y - h * 0.5
	var base: float = c.y + h * 0.5
	var w: float = h * 0.42
	var s: PackedVector2Array = PackedVector2Array()
	match ch:
		"A":
			s.append_array([Vector2(c.x - w, base), Vector2(c.x, top)])
			s.append_array([Vector2(c.x, top), Vector2(c.x + w, base)])
			s.append_array([Vector2(c.x - w * 0.52, top + h * 0.64), Vector2(c.x + w * 0.52, top + h * 0.64)])
			s.append_array([Vector2(c.x - w - h * 0.13, base), Vector2(c.x - w + h * 0.13, base)])
			s.append_array([Vector2(c.x + w - h * 0.13, base), Vector2(c.x + w + h * 0.13, base)])
		"V":
			s.append_array([Vector2(c.x - w, top), Vector2(c.x, base)])
			s.append_array([Vector2(c.x + w, top), Vector2(c.x, base)])
			s.append_array([Vector2(c.x - w - h * 0.13, top), Vector2(c.x - w + h * 0.13, top)])
			s.append_array([Vector2(c.x + w - h * 0.13, top), Vector2(c.x + w + h * 0.13, top)])
		"O":
			var r: float = h * 0.38
			var ring_c: Vector2 = Vector2(c.x, top + r + h * 0.04)
			var gap: float = deg_to_rad(38.0)
			for sign: float in [-1.0, 1.0]:
				var end: Vector2 = ring_c + Vector2(sin(gap) * r * sign, cos(gap) * r)
				var foot: Vector2 = Vector2(c.x + sign * r * 0.62, base)
				s.append_array([end, foot])
				s.append_array([foot, Vector2(c.x + sign * (r + h * 0.16), base)])
		"+":
			s.append_array([Vector2(c.x - h * 0.5, c.y), Vector2(c.x + h * 0.5, c.y)])
			s.append_array([Vector2(c.x, c.y - h * 0.5), Vector2(c.x, c.y + h * 0.5)])
		"-":
			s.append_array([Vector2(c.x - h * 0.5, c.y), Vector2(c.x + h * 0.5, c.y)])
	return s


## Signed distance to a glyph drawn with strokes of half-width `hw`.
func _sd_glyph(p: Vector2, ch: String, c: Vector2, h: float, hw: float) -> float:
	var segs: PackedVector2Array = _glyph_segments(ch, c, h)
	var d: float = INF
	for i: int in range(0, segs.size(), 2):
		d = minf(d, _sd_segment(p, segs[i], segs[i + 1]))
	if ch == "O":
		var top: float = c.y - h * 0.5
		var r: float = h * 0.38
		var ring_c: Vector2 = Vector2(c.x, top + r + h * 0.04)
		var gap: float = deg_to_rad(38.0)
		# The ring runs over the top, from the lower-right gap edge round to the lower-left one.
		d = minf(d, _sd_arc(p, ring_c, r, PI * 0.5 + gap, PI * 2.5 - gap))
	return d - hw


## Draws a glyph with an ink outline.
func _draw_glyph(img: Image, ch: String, c: Vector2, h: float, hw: float, fill: Color, outline: float, ink: Color = INK) -> void:
	var bounds: Rect2i = Rect2i(Vector2i(int(c.x - h - 4), int(c.y - h - 4)), Vector2i(int(h * 2 + 8), int(h * 2 + 8)))
	_paint(img, func(p: Vector2) -> float: return _sd_glyph(p, ch, c, h, hw + outline), func(_p: Vector2) -> Color: return fill, outline, ink, bounds)


# --- Parts: blank resistor and battery -------------------------------------------------------

## The pack's 2-ohm icon with its three value bands turned a neutral taupe (the gold tolerance
## band stays) and the value text removed from the plaque.
func _resistor_blank(src: Image) -> Image:
	var img: Image = src.duplicate() as Image
	for run: Vector2i in BAND_RUNS:
		var band: Color = img.get_pixel(run.x + 4, 57)
		# Rows inside the body outline only; the band's own colour also fills its 1 px ink-edge
		# column at the end rows. The tight tolerance keeps the black band apart from the ink.
		for y: int in range(BAND_ROWS.x, BAND_ROWS.y + 1):
			for x: int in range(run.x - 1, run.y + 1):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0 and _dist(c, band) < 0.04:
					img.set_pixel(x, y, Color(NEUTRAL_BAND, c.a))
	for y: int in range(PLAQUE_BLANK.position.y, PLAQUE_BLANK.end.y):
		for x: int in range(PLAQUE_BLANK.position.x, PLAQUE_BLANK.end.x):
			img.set_pixel(x, y, PLAQUE_CREAM)
	return img


func _dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## Resistor-style lead wires: rows 50-63, ink edges and a grey core, hard edges like the icons.
func _part_leads(img: Image, left_to: int, right_from: int) -> void:
	for y: int in range(LEAD_TOP, LEAD_BOTTOM + 1):
		var edge: bool = y < LEAD_TOP + 3 or y > LEAD_BOTTOM - 3
		var c: Color = RES_INK if edge else LEAD_GREY
		for x: int in range(LEAD_LEFT_X, left_to):
			img.set_pixel(x, y, c)
		for x: int in range(right_from, LEAD_RIGHT_X + 1):
			img.set_pixel(x, y, c)


## Horizontal dry cell, positive end (brass nub and "+") on the LEFT, flat negative end and "-"
## on the right, copper end caps, a muted teal wrapper with an ink and a gold band (as on
## battery_pickup.png), and the blank resistor's value plaque underneath.
func _battery(blank_resistor: Image) -> Image:
	var img: Image = _blank(PART_SIZE)
	_part_leads(img, int(BATT_NUB.position.x) + 4, int(BATT_BODY.end.x) - 4)
	# Plaque first, then the body's bottom outline closes over its top edge as on the resistors.
	img.blit_rect(blank_resistor, PLAQUE_COPY, PLAQUE_COPY.position)
	var body_top: float = BATT_BODY.position.y + BATT_OUTLINE
	var body_h: float = BATT_BODY.size.y - BATT_OUTLINE * 2.0
	# Brass positive nub (behind the left cap).
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, BATT_NUB, 6.0),
		func(p: Vector2) -> Color:
			var t: float = (p.y - BATT_NUB.position.y) / BATT_NUB.size.y
			return _wash(_tube(t, BRASS_LIGHT, BRASS, BRASS_DARK), p, 0.10),
		3.0, RES_INK)
	# Body: copper caps either end, teal wrapper between.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, BATT_BODY, BATT_BODY_RADIUS),
		func(p: Vector2) -> Color:
			var t: float = clampf((p.y - body_top) / body_h, 0.0, 1.0)
			var c: Color
			if p.x < BATT_CAP_LEFT_END or p.x > BATT_CAP_RIGHT_START:
				c = _tube(t, COPPER_LIGHT, COPPER, COPPER_DARK)
			elif p.x >= BATT_GOLD_BAND.x and p.x < BATT_GOLD_BAND.y:
				c = _tube(t, MUSTARD_LIGHT, MUSTARD, MUSTARD_DARK)
			elif p.x >= BATT_INK_BAND.x and p.x < BATT_INK_BAND.y:
				c = _tube(t, Color8(84, 66, 52), RES_INK, INK)
			else:
				c = _tube(t, TEAL_LIGHT, TEAL, TEAL_DARK)
			return _wash(c, p, 0.12),
		BATT_OUTLINE, RES_INK)
	# Ink seams between caps and wrapper, and thin ink edges on the bands.
	for seam: float in [BATT_CAP_LEFT_END, BATT_CAP_RIGHT_START]:
		_paint(img, func(p: Vector2) -> float: return absf(p.x - seam) - 1.5,
			func(_p: Vector2) -> Color: return RES_INK, 0.0, RES_INK,
			Rect2i(int(seam) - 3, int(body_top), 6, int(body_h)))
	for edge: float in [BATT_GOLD_BAND.x, BATT_GOLD_BAND.y]:
		_paint(img, func(p: Vector2) -> float: return absf(p.x - edge) - 0.6,
			func(_p: Vector2) -> Color: return RES_INK, 0.0, RES_INK,
			Rect2i(int(edge) - 2, int(body_top), 4, int(body_h)))
	# Specular streak along the top of the cylinder.
	for y: int in range(int(body_top) + 3, int(body_top) + 8):
		for x: int in range(int(BATT_BODY.position.x) + 10, int(BATT_BODY.end.x) - 10):
			var edge_fade: float = 1.0 - smoothstep(0.0, 2.5, absf(y - (body_top + 5.0)))
			_over(img, x, y, PORCELAIN_LIGHT, 0.28 * edge_fade)
	# Polarity marks.
	_draw_glyph(img, "+", BATT_PLUS_CENTRE, 30.0, 4.2, PLAQUE_CREAM, 2.5, RES_INK)
	_draw_glyph(img, "-", BATT_MINUS_CENTRE, 20.0, 4.2, PLAQUE_CREAM, 2.5, RES_INK)
	return img


# --- Meters ----------------------------------------------------------------------------------

func _wood(p: Vector2) -> Color:
	var grain: float = 0.5 + 0.5 * sin(p.y * 0.5 + 2.4 * sin(p.x * 0.05 + p.y * 0.08))
	var c: Color = WALNUT_DARK.lerp(WALNUT, 0.3 + 0.45 * grain)
	return _wash(c, p, 0.25)


## Brass-and-walnut panel meter: walnut case, brass bezel, parchment face with an accent-coloured
## letter plate (top left) and a small arc scale with a needle (top right), and a wide recessed
## cream display window across the bottom for the live reading.
func _meter(spec: Dictionary) -> Image:
	var img: Image = _blank(FIXTURE_SIZE)
	var accent: Array = spec["accent"]
	var acc: Color = accent[0]
	var acc_light: Color = accent[1]
	var acc_dark: Color = accent[2]
	_lead_stubs(img)
	# Walnut case.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, METER_CASE, 14.0), _wood, 3.0)
	# Brass bezel.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, METER_BEZEL, 10.0),
		func(p: Vector2) -> Color:
			var t: float = (p.y - METER_BEZEL.position.y) / METER_BEZEL.size.y
			var s: float = (p.x - METER_BEZEL.position.x) / METER_BEZEL.size.x
			var lit: float = clampf(1.0 - (t + s) * 0.9, 0.0, 1.0)
			return _wash(BRASS.lerp(BRASS_LIGHT, lit * 0.8).lerp(BRASS_DARK, smoothstep(0.75, 1.0, t) * 0.7), p, 0.12),
		2.0)
	# Parchment face.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, METER_FACE, 7.0),
		func(p: Vector2) -> Color: return _wash(PORCELAIN, p, 0.10), 2.0)
	# Arc scale: an accent zone, the scale line, major and minor ticks.
	var a0: float = deg_to_rad(-160.0)
	var a1: float = deg_to_rad(-20.0)
	var zone0: float = deg_to_rad(-55.0)
	var arc_bounds: Rect2i = Rect2i(100, 18, 82, 52)
	_paint(img, func(p: Vector2) -> float: return _sd_arc(p, METER_PIVOT, METER_ARC_RADIUS - 4.0, zone0, a1) - 2.6,
		func(_p: Vector2) -> Color: return acc, 0.0, INK, arc_bounds)
	_paint(img, func(p: Vector2) -> float: return _sd_arc(p, METER_PIVOT, METER_ARC_RADIUS, a0, a1) - 1.1,
		func(_p: Vector2) -> Color: return INK, 0.0, INK, arc_bounds)
	for i: int in 11:
		var a: float = lerpf(a0, a1, i / 10.0)
		var major: bool = i % 5 == 0
		var dir: Vector2 = Vector2.from_angle(a)
		var from: Vector2 = METER_PIVOT + dir * METER_ARC_RADIUS
		var to: Vector2 = METER_PIVOT + dir * (METER_ARC_RADIUS + (8.0 if major else 5.0))
		_paint(img, func(p: Vector2) -> float: return _sd_segment(p, from, to) - (1.3 if major else 0.9),
			func(_p: Vector2) -> Color: return INK, 0.0, INK, arc_bounds)
	# Needle (accent, ink outline) and its brass pivot.
	var tip: Vector2 = METER_PIVOT + Vector2.from_angle(deg_to_rad(spec["needle"])) * (METER_ARC_RADIUS + 3.0)
	_paint(img, func(p: Vector2) -> float: return _sd_segment(p, METER_PIVOT, tip) - 2.6,
		func(_p: Vector2) -> Color: return acc, 1.4, INK, arc_bounds)
	_disc_shaded(img, METER_PIVOT, 5.5, BRASS, BRASS_LIGHT, BRASS_DARK)
	# Letter plate: accent enamel in a brass rim, big cream (or ink) letter.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, METER_BADGE, 9.0),
		func(p: Vector2) -> Color: return _wash(BRASS.lerp(BRASS_LIGHT, clampf(1.0 - (p.y - METER_BADGE.position.y) / METER_BADGE.size.y, 0.0, 1.0) * 0.6), p, 0.1),
		2.0)
	var enamel: Rect2 = METER_BADGE.grow(-4.0)
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, enamel, 6.0),
		func(p: Vector2) -> Color:
			var t: float = (p.y - enamel.position.y) / enamel.size.y
			return _wash(acc_light.lerp(acc, smoothstep(0.0, 0.45, t)).lerp(acc_dark, smoothstep(0.7, 1.0, t) * 0.6), p, 0.12),
		1.6)
	var letter: String = spec["letter"]
	var letter_h: float = 32.0
	var stroke: float = 2.6 if letter == "O" else 3.2
	_draw_glyph(img, letter, enamel.get_center() + Vector2(0, 0.5), letter_h, stroke, spec["letter_fill"], 2.0)
	# Display window: recessed cream panel with a shadow cast from its top and left edges.
	var win: Rect2 = METER_WINDOW
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, win, 5.0),
		func(p: Vector2) -> Color:
			var from_top: float = p.y - win.position.y - METER_WINDOW_OUTLINE
			var from_left: float = p.x - win.position.x - METER_WINDOW_OUTLINE
			var cast: float = 0.22 * (1.0 - smoothstep(0.0, 6.0, from_top)) + 0.12 * (1.0 - smoothstep(0.0, 5.0, from_left))
			return _wash(DISPLAY_CREAM, p, 0.05).lerp(PORCELAIN_SHADE, cast),
		METER_WINDOW_OUTLINE)
	# Binding posts where the stubs enter the case, and two face screws.
	for post: Vector2 in METER_POSTS:
		_disc_shaded(img, post, 7.5, BRASS, BRASS_LIGHT, BRASS_DARK)
		_paint(img, func(p: Vector2) -> float: return _sd_segment(p, post + Vector2(-3.5, 3.5), post + Vector2(3.5, -3.5)) - 0.8,
			func(_p: Vector2) -> Color: return INK, 0.0, INK, Rect2i(Vector2i(post) - Vector2i(6, 6), Vector2i(12, 12)))
	return img


# --- Lamps -----------------------------------------------------------------------------------

func _sd_bulb(p: Vector2) -> float:
	return _smin(_sd_circle(p, BULB_CENTRE, BULB_RADIUS), _sd_round_rect(p, BULB_NECK, 6.0), 9.0)


## The parts every lamp state shares: stubs, binding posts, copper wires, walnut plinth, brass
## flange and screw base. The glass is drawn on top by _lamp.
func _lamp_base(img: Image) -> void:
	_lead_stubs(img)
	# Copper wires from each post, curving down into the flange (like the HUD plaque's bulb).
	var wires: Array[PackedVector2Array] = [
		_cubic(LAMP_POSTS[0], LAMP_POSTS[0] + Vector2(30, 0), Vector2(56, 113), Vector2(80, 113), 24),
		_cubic(LAMP_POSTS[1], LAMP_POSTS[1] + Vector2(-30, 0), Vector2(152, 113), Vector2(128, 113), 24),
	]
	for wire: PackedVector2Array in wires:
		_paint(img, func(p: Vector2) -> float: return _sd_polyline(p, wire) - 5.5,
			func(p: Vector2) -> Color:
				# Lit along the core, darker towards the ink edge.
				var d: float = _sd_polyline(p, wire)
				return _tube(clampf(0.2 + d / 3.5 * 0.8, 0.0, 1.0), COPPER_LIGHT, COPPER, COPPER_DARK),
			2.0)
	# Walnut plinth.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, LAMP_PLINTH, 8.0),
		func(p: Vector2) -> Color:
			var t: float = (p.y - LAMP_PLINTH.position.y) / LAMP_PLINTH.size.y
			return _wood(p).lerp(WALNUT_LIGHT, (1.0 - smoothstep(0.0, 0.3, t)) * 0.5),
		3.0)
	# Brass flange and screw base with thread ridges.
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, LAMP_FLANGE, 4.0),
		func(p: Vector2) -> Color: return _wash(_tube((p.y - LAMP_FLANGE.position.y) / LAMP_FLANGE.size.y, BRASS_LIGHT, BRASS, BRASS_DARK), p, 0.1),
		2.5)
	_paint(img, func(p: Vector2) -> float: return _sd_round_rect(p, LAMP_SCREW, 3.0),
		func(p: Vector2) -> Color:
			var s: float = (p.x - LAMP_SCREW.position.x) / LAMP_SCREW.size.x
			return _wash(_tube(s, BRASS_LIGHT, BRASS, BRASS_DARK), p, 0.1),
		2.5)
	for ridge_y: float in [96.5, 102.5]:
		_paint(img, func(p: Vector2) -> float: return absf(p.y - ridge_y) - 1.1,
			func(_p: Vector2) -> Color: return INK, 0.0, INK,
			Rect2i(int(LAMP_SCREW.position.x) + 2, int(ridge_y) - 3, int(LAMP_SCREW.size.x) - 4, 6))
	for post: Vector2 in LAMP_POSTS:
		_disc_shaded(img, post, 8.0, BRASS, BRASS_LIGHT, BRASS_DARK)


## Filament: two support wires up from the neck and a looped coil between them.
func _filament(img: Image, colour: Color, width: float, broken: bool) -> void:
	var left: PackedVector2Array = PackedVector2Array([Vector2(98, 92), Vector2(97, 70), Vector2(95, 50)])
	var right: PackedVector2Array = PackedVector2Array([Vector2(110, 92), Vector2(111, 70), Vector2(113, 50)])
	var coil: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		var t: float = i / 24.0
		var x: float = lerpf(95.0, 113.0, t)
		coil.append(Vector2(x, 50.0 - sin(t * PI) * 9.0 + sin(t * TAU * 3.0) * 2.2))
	if broken:
		# Snapped in the middle: each half droops.
		var half_l: PackedVector2Array = PackedVector2Array()
		var half_r: PackedVector2Array = PackedVector2Array()
		for i: int in 11:
			var p: Vector2 = coil[i]
			half_l.append(p + Vector2(0, (i / 10.0) * (i / 10.0) * 9.0))
			var q: Vector2 = coil[14 + i]
			half_r.append(q + Vector2(0, (1.0 - i / 10.0) * (1.0 - i / 10.0) * 11.0))
		coil = half_l
		_stroke(img, half_r, colour, width)
	for line: PackedVector2Array in [left, right, coil]:
		_stroke(img, line, colour, width)


func _stroke(img: Image, line: PackedVector2Array, colour: Color, width: float) -> void:
	var bounds: Rect2i = Rect2i(70, 10, 70, 90)
	_paint(img, func(p: Vector2) -> float: return _sd_polyline(p, line) - width * 0.5,
		func(_p: Vector2) -> Color: return colour, 0.0, colour, bounds)


## lamp_off: dim grey glass. lamp_on: warm yellow glass, bright filament, soft halo and
## pack-style shine ticks. lamp_blown: smoky dark glass, cracks, snapped filament, smoke puff.
func _lamp(state: String) -> Image:
	var img: Image = _blank(FIXTURE_SIZE)
	if state == "on":
		# Halo first, under everything.
		for y: int in img.get_height():
			for x: int in img.get_width():
				var d: float = Vector2(x + 0.5, y + 0.5).distance_to(BULB_CENTRE)
				var a: float = 1.0 - smoothstep(BULB_RADIUS - 2.0, BULB_RADIUS + 15.0, d)
				_over(img, x, y, GLOW, a * a * 0.85)
	_lamp_base(img)
	var glass_bounds: Rect2i = Rect2i(70, 14, 68, 84)
	match state:
		"off":
			_paint(img, _sd_bulb,
				func(p: Vector2) -> Color:
					var d: Vector2 = (p - BULB_CENTRE) / BULB_RADIUS
					var lit: float = clampf(-(d.x * 0.6 + d.y) * 0.8, 0.0, 1.0)
					var shade: float = clampf((d.x * 0.6 + d.y) * 0.7, 0.0, 1.0)
					return _wash(GLASS_OFF.lerp(GLASS_OFF_LIGHT, lit).lerp(GLASS_OFF_DARK, shade), p, 0.08),
				3.0, INK, glass_bounds)
			_filament(img, Color8(70, 56, 44), 2.2, false)
			_glint(img, 0.75)
		"on":
			_paint(img, _sd_bulb,
				func(p: Vector2) -> Color:
					var d: float = p.distance_to(BULB_CENTRE + Vector2(0, 2)) / BULB_RADIUS
					return GLOW_CORE.lerp(GLOW, smoothstep(0.25, 0.85, d)).lerp(BRASS, smoothstep(0.85, 1.3, d) * 0.6),
				3.0, INK, glass_bounds)
			# Bright bloom round the coil, then a white-hot filament.
			for y: int in range(20, 80):
				for x: int in range(76, 132):
					var p: Vector2 = Vector2(x + 0.5, y + 0.5)
					if _sd_bulb(p) > -3.0:
						continue
					var d: float = p.distance_to(Vector2(104, 46))
					_over(img, x, y, Color(1, 1, 0.92), (1.0 - smoothstep(4.0, 16.0, d)) * 0.8)
			_filament(img, Color8(186, 104, 40), 2.2, false)
			_filament(img, Color(1, 0.98, 0.86), 1.0, false)
			_glint(img, 0.9)
			_shine_ticks(img)
		"blown":
			_paint(img, _sd_bulb,
				func(p: Vector2) -> Color:
					var d: Vector2 = (p - BULB_CENTRE) / BULB_RADIUS
					var shade: float = clampf((d.x * 0.5 + d.y) * 0.6 + 0.3, 0.0, 1.0)
					var scorch: float = 1.0 - smoothstep(4.0, 22.0, p.distance_to(Vector2(104, 44)))
					var c: Color = GLASS_BLOWN.lerp(GLASS_BLOWN_DARK, shade * 0.7).lerp(INK, scorch * 0.7)
					return _wash(c, p, 0.2),
				3.0, INK, glass_bounds)
			_filament(img, Color8(26, 18, 12), 2.2, true)
			_glint(img, 0.35)
			_cracks(img)
			_smoke(img)
	return img


## Pale highlight crescent on the upper-left of the glass.
func _glint(img: Image, strength: float) -> void:
	var arc_c: Vector2 = BULB_CENTRE
	_paint(img, func(p: Vector2) -> float: return _sd_arc(p, arc_c, BULB_RADIUS - 8.0, deg_to_rad(-170.0), deg_to_rad(-115.0)) - 2.4,
		func(_p: Vector2) -> Color: return Color(PORCELAIN_LIGHT, strength), 0.0, INK, Rect2i(70, 14, 40, 40))
	_paint(img, func(p: Vector2) -> float: return _sd_circle(p, arc_c + Vector2.from_angle(deg_to_rad(-100.0)) * (BULB_RADIUS - 8.0), 2.0),
		func(_p: Vector2) -> Color: return Color(PORCELAIN_LIGHT, strength), 0.0, INK, Rect2i(90, 14, 30, 30))


## Small inked brass wedges radiating from the bulb, like the shine marks on battery_pickup.png.
func _shine_ticks(img: Image) -> void:
	for deg: float in [-162.0, -128.0, -52.0, -18.0]:
		var dir: Vector2 = Vector2.from_angle(deg_to_rad(deg))
		var n: Vector2 = dir.orthogonal()
		var base_c: Vector2 = BULB_CENTRE + dir * (BULB_RADIUS + 7.0)
		var tip: Vector2 = BULB_CENTRE + dir * (BULB_RADIUS + 20.0)
		var a: Vector2 = tip
		var b: Vector2 = base_c + n * 4.5
		var c: Vector2 = base_c - n * 4.5
		_paint(img, func(p: Vector2) -> float: return _sd_triangle(p, a, b, c) - 1.5,
			func(q: Vector2) -> Color: return BRASS_LIGHT.lerp(MUSTARD, clampf(q.distance_to(tip) / 14.0, 0.0, 1.0)),
			2.0, INK)


func _sd_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d: float = minf(_sd_segment(p, a, b), minf(_sd_segment(p, b, c), _sd_segment(p, c, a)))
	var s1: float = (b - a).cross(p - a)
	var s2: float = (c - b).cross(p - b)
	var s3: float = (a - c).cross(p - c)
	var inside: bool = (s1 >= 0.0 and s2 >= 0.0 and s3 >= 0.0) or (s1 <= 0.0 and s2 <= 0.0 and s3 <= 0.0)
	return -d if inside else d


## Jagged ink cracks with a pale edge on the glass.
func _cracks(img: Image) -> void:
	var cracks: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(122, 24), Vector2(117, 33), Vector2(121, 39), Vector2(113, 48), Vector2(116, 55)]),
		PackedVector2Array([Vector2(117, 33), Vector2(127, 38), Vector2(130, 46)]),
		PackedVector2Array([Vector2(84, 34), Vector2(90, 40), Vector2(87, 47)]),
	]
	for crack: PackedVector2Array in cracks:
		var lit: PackedVector2Array = PackedVector2Array()
		for q: Vector2 in crack:
			lit.append(q + Vector2(1.2, 1.0))
		_paint(img, func(p: Vector2) -> float: return maxf(_sd_polyline(p, lit) - 0.9, _sd_bulb(p) + 3.0),
			func(_p: Vector2) -> Color: return Color(SMOKE_LIGHT, 0.85), 0.0, INK, Rect2i(70, 14, 68, 60))
		_paint(img, func(p: Vector2) -> float: return maxf(_sd_polyline(p, crack) - 1.1, _sd_bulb(p) + 3.0),
			func(_p: Vector2) -> Color: return INK, 0.0, INK, Rect2i(70, 14, 68, 60))


## A small puff of grey smoke at the top right of the bulb.
func _smoke(img: Image) -> void:
	var puffs: Array[Vector3] = [Vector3(126, 24, 6.5), Vector3(136, 15, 8.0), Vector3(149, 11, 7.5), Vector3(152, 22, 6.5), Vector3(141, 24, 6.5)]
	var sd_cloud: Callable = func(p: Vector2) -> float:
		var d: float = INF
		for c: Vector3 in puffs:
			d = minf(d, _sd_circle(p, Vector2(c.x, c.y), c.z))
		return d
	_paint(img, sd_cloud,
		func(p: Vector2) -> Color:
			var t: float = clampf((p.y - 6.0) / 26.0, 0.0, 1.0)
			return _wash(SMOKE_LIGHT.lerp(SMOKE, t), p, 0.12),
		2.0, INK, Rect2i(118, 0, 50, 40))


# --- Polarity badges -------------------------------------------------------------------------

func _polarity(plus: bool) -> Image:
	var img: Image = _blank(Vector2i(32, 32))
	_disc_shaded(img, Vector2(16, 16), 14.0, BRASS, BRASS_LIGHT, BRASS_DARK)
	_draw_glyph(img, "+" if plus else "-", Vector2(16, 16), 15.0, 2.2, INK, 0.0)
	return img
