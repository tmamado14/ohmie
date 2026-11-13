extends SceneTree
## Generates the World 2 (electronics) art that the user's set in
## res://assets/interactive/electronics/ does not provide, into res://assets/processed/.
##
## Run from the project root, then re-import:
##   godot --headless --path . --script res://tools/generate_electronics_art.gd
##   godot --headless --path . --import
##
## Currently: the two diode direction badges (diode_arrow_right.png, diode_arrow_left.png).
## Authored at 2x for scale 0.5 with Linear filtering, like tools/generate_parts_art.gd, whose
## brass disc (polarity_plus.png) the badges share exactly. Source PNGs are only read.

const OUTPUT_DIR: String = "res://assets/processed/"

# --- Palette (shared with tools/generate_parts_art.gd) --------------------------------------
const INK: Color = Color8(36, 24, 15)
const BRASS: Color = Color8(199, 144, 66)
const BRASS_LIGHT: Color = Color8(252, 207, 119)
const BRASS_DARK: Color = Color8(138, 90, 36)
const CLEAR: Color = Color(0, 0, 0, 0)

# --- Badge geometry (same disc as polarity_plus.png) ----------------------------------------
const BADGE_SIZE: Vector2i = Vector2i(32, 32)
const BADGE_CENTRE: Vector2 = Vector2(16, 16)
const BADGE_RADIUS: float = 14.0
## Diode mark for the right-pointing badge (anode on the left, cathode bar on the right).
## The left badge mirrors these about x = 16.
const MARK_TRIANGLE_BACK_X: float = 9.0
const MARK_TRIANGLE_TIP_X: float = 20.0
const MARK_HALF_HEIGHT: float = 7.0
const MARK_BAR_X: float = 21.5
const MARK_BAR_HALF_WIDTH: float = 1.8
const MARK_LEAD_HALF_WIDTH: float = 1.1
const MARK_LEAD_LEFT_X: float = 6.0
const MARK_LEAD_RIGHT_X: float = 26.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures: int = 0
	failures += _save(_diode_badge(true), "diode_arrow_right.png")
	failures += _save(_diode_badge(false), "diode_arrow_left.png")
	quit(1 if failures > 0 else 0)


# --- I/O -------------------------------------------------------------------------------------

func _save(img: Image, file_name: String) -> int:
	var path: String = OUTPUT_DIR + file_name
	var err: Error = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("generate_electronics_art: could not save %s (%s)" % [path, error_string(err)])
		return 1
	print("generate_electronics_art: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	return 0


func _blank(size: Vector2i) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


# --- Pixel and shape helpers (as in tools/generate_parts_art.gd) -----------------------------

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


func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _sd_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d: float = minf(_sd_segment(p, a, b), minf(_sd_segment(p, b, c), _sd_segment(p, c, a)))
	var s1: float = (b - a).cross(p - a)
	var s2: float = (c - b).cross(p - b)
	var s3: float = (a - c).cross(p - c)
	var inside: bool = (s1 >= 0.0 and s2 >= 0.0 and s3 >= 0.0) or (s1 <= 0.0 and s2 <= 0.0 and s3 <= 0.0)
	return -d if inside else d


## Ink-outlined brass disc lit from the upper left: the exact drawing of polarity_plus.png.
func _disc_shaded(img: Image, centre: Vector2, radius: float, base: Color, light: Color, dark: Color) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
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


# --- Diode direction badge -------------------------------------------------------------------

## Signed distance to the ink diode mark (lead, triangle, cathode bar, lead) pointing right,
## evaluated on the mirrored point for the left badge so the two marks are exact mirrors.
func _sd_diode_mark(p: Vector2, right: bool) -> float:
	var q: Vector2 = p if right else Vector2(BADGE_SIZE.x - p.x, p.y)
	var cy: float = BADGE_CENTRE.y
	var tri: float = _sd_triangle(q, Vector2(MARK_TRIANGLE_BACK_X, cy - MARK_HALF_HEIGHT),
			Vector2(MARK_TRIANGLE_BACK_X, cy + MARK_HALF_HEIGHT), Vector2(MARK_TRIANGLE_TIP_X, cy))
	var bar: float = _sd_segment(q, Vector2(MARK_BAR_X, cy - MARK_HALF_HEIGHT), Vector2(MARK_BAR_X, cy + MARK_HALF_HEIGHT)) - MARK_BAR_HALF_WIDTH
	var leads: float = _sd_segment(q, Vector2(MARK_LEAD_LEFT_X, cy), Vector2(MARK_LEAD_RIGHT_X, cy)) - MARK_LEAD_HALF_WIDTH
	return minf(tri, minf(bar, leads))


## Brass disc (identical to polarity_plus.png) with an ink diode mark showing the conduction
## direction, anode to cathode: the triangle points at the cathode bar.
func _diode_badge(right: bool) -> Image:
	var img: Image = _blank(BADGE_SIZE)
	_disc_shaded(img, BADGE_CENTRE, BADGE_RADIUS, BRASS, BRASS_LIGHT, BRASS_DARK)
	for y: int in img.get_height():
		for x: int in img.get_width():
			_over(img, x, y, INK, _coverage(_sd_diode_mark(Vector2(x + 0.5, y + 0.5), right)))
	return img
