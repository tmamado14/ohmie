extends SceneTree
## Generates the menu badges into res://assets/processed/:
##   ui_lock.png   64x64  brass padlock (iron shackle), dark ink outline, soft shading
##   ui_check.png  64x64  green check badge in a brass ring
##
## Run from the project root, then re-import:
##   godot --headless --path . --script res://tools/generate_ui_art.gd
##   godot --headless --path . --import
##
## Authored at 2x like the rest of the pack (drawn at scale 0.5, Linear filtering).
## Every shape is a signed-distance field evaluated on a 4x supersampled canvas
## and box-filtered down, so edges are anti-aliased. Transparent background.

const OUTPUT_DIR: String = "res://assets/processed/"
const SIZE: int = 64
## Supersampling factor: shapes are described on a SIZE * SUPER canvas.
const SUPER: int = 4
const CANVAS: float = 256.0

# Palette (shared with tools/generate_parts_art.gd).
const INK: Color = Color8(36, 24, 15)
const BRASS: Color = Color8(199, 144, 66)
const BRASS_LIGHT: Color = Color8(252, 207, 119)
const BRASS_DARK: Color = Color8(138, 90, 36)
const IRON: Color = Color8(118, 124, 118)
const IRON_LIGHT: Color = Color8(186, 190, 180)
const IRON_DARK: Color = Color8(64, 68, 66)
const GREEN: Color = Color8(76, 150, 84)
const GREEN_LIGHT: Color = Color8(128, 196, 116)
const GREEN_DARK: Color = Color8(40, 94, 52)
const CREAM: Color = Color8(250, 238, 214)
const CLEAR: Color = Color(0, 0, 0, 0)

## Ink outline width on the canvas (about 3 px in the 64 px image).
const OUTLINE: float = 12.0


func _initialize() -> void:
	var ok: bool = _save(_render(_lock_pixel), "ui_lock.png")
	ok = _save(_render(_check_pixel), "ui_check.png") and ok
	quit(0 if ok else 1)


func _save(image: Image, file_name: String) -> bool:
	var path: String = ProjectSettings.globalize_path(OUTPUT_DIR + file_name)
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("generate_ui_art: could not save %s (%s)" % [path, error_string(err)])
		return false
	print("generate_ui_art: saved %s" % path)
	return true


## Renders `shader` (canvas point -> premultiplied colour) with SUPER x SUPER samples per pixel.
func _render(shader: Callable) -> Image:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var step: float = CANVAS / float(SIZE * SUPER)
	for y: int in SIZE:
		for x: int in SIZE:
			var sum: Color = Color(0, 0, 0, 0)
			for sy: int in SUPER:
				for sx: int in SUPER:
					var p: Vector2 = Vector2((x * SUPER + sx + 0.5) * step, (y * SUPER + sy + 0.5) * step)
					var c: Color = shader.call(p)
					sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
			var n: float = float(SUPER * SUPER)
			var a: float = sum.a / n
			if a <= 0.0:
				image.set_pixel(x, y, CLEAR)
			else:
				image.set_pixel(x, y, Color(sum.r / n / a, sum.g / n / a, sum.b / n / a, a))
	return image


# --- padlock -------------------------------------------------------------------------------

func _lock_pixel(p: Vector2) -> Color:
	var color: Color = CLEAR
	# Shackle: a U of iron behind the body.
	var shackle_center: Vector2 = Vector2(128, 104)
	var shackle_radius: float = 50.0
	var shackle_half_width: float = 13.0
	var path_distance: float = _segment_distance(p, Vector2(78, 104), Vector2(78, 150))
	path_distance = minf(path_distance, _segment_distance(p, Vector2(178, 104), Vector2(178, 150)))
	if p.y <= shackle_center.y:
		path_distance = minf(path_distance, absf(p.distance_to(shackle_center) - shackle_radius))
	var shackle: float = path_distance - shackle_half_width
	if shackle < OUTLINE:
		color = INK
	if shackle < 0.0:
		# Rounded-bar shading: light along the bar's centre line, dark at its edges.
		var t: float = clampf(-shackle / shackle_half_width, 0.0, 1.0)
		color = IRON_DARK.lerp(IRON, smoothstep(0.0, 0.5, t))
		if t > 0.55 and p.x < 140.0:
			color = color.lerp(IRON_LIGHT, smoothstep(0.55, 0.95, t) * 0.8)
	# Body: rounded brass block.
	var body: float = _round_rect_distance(p, Vector2(128, 182), Vector2(82, 58), 22.0)
	if body < OUTLINE:
		color = INK
	if body < 0.0:
		var v: float = clampf((p.y - 124.0) / 116.0, 0.0, 1.0)
		color = BRASS_LIGHT.lerp(BRASS, smoothstep(0.0, 0.45, v)).lerp(BRASS_DARK, smoothstep(0.55, 1.0, v))
		# Inner rim shadow along the lower and right edges, highlight top left.
		var edge: float = clampf(-body / 12.0, 0.0, 1.0)
		if p.y > 196.0 or p.x > 186.0:
			color = color.lerp(BRASS_DARK, (1.0 - edge) * 0.55)
		var shine: float = 1.0 - clampf(p.distance_to(Vector2(84, 146)) / 46.0, 0.0, 1.0)
		color = color.lerp(Color8(255, 236, 180), shine * 0.6)
		# Rivets in the four corners.
		for rivet: Vector2 in [Vector2(66, 142), Vector2(190, 142), Vector2(66, 222), Vector2(190, 222)]:
			var d: float = p.distance_to(rivet)
			if d < 9.0:
				color = INK
			if d < 6.0:
				color = BRASS_LIGHT if p.y < rivet.y else BRASS
		# Keyhole: a disc over a tapered slot, in ink.
		var hole: float = p.distance_to(Vector2(128, 172)) - 15.0
		var slot_half: float = lerpf(7.0, 12.0, clampf((p.y - 172.0) / 36.0, 0.0, 1.0))
		if p.y > 172.0 and p.y < 210.0 and absf(p.x - 128.0) < slot_half:
			hole = minf(hole, -1.0)
		if hole < 0.0:
			color = INK
	return color


# --- check badge ---------------------------------------------------------------------------

func _check_pixel(p: Vector2) -> Color:
	var center: Vector2 = Vector2(128, 128)
	var d: float = p.distance_to(center)
	var color: Color = CLEAR
	var outer: float = 118.0
	var ring_inner: float = 92.0
	if d < outer:
		color = INK
	if d < outer - OUTLINE * 0.75:
		# Brass ring, lit from the top left.
		var lit: float = clampf(((center - p).normalized().dot(Vector2(0.6, 0.8).normalized()) + 1.0) * 0.5, 0.0, 1.0)
		color = BRASS_DARK.lerp(BRASS, smoothstep(0.1, 0.5, lit)).lerp(BRASS_LIGHT, smoothstep(0.6, 1.0, lit))
	if d < ring_inner + 5.0:
		color = INK
	if d < ring_inner:
		var v: float = clampf((p.y - 40.0) / 176.0, 0.0, 1.0)
		color = GREEN_LIGHT.lerp(GREEN, smoothstep(0.0, 0.5, v)).lerp(GREEN_DARK, smoothstep(0.5, 1.0, v))
		var shine: float = 1.0 - clampf(p.distance_to(Vector2(98, 84)) / 50.0, 0.0, 1.0)
		color = color.lerp(Color8(196, 236, 170), shine * 0.45)
	# The check mark: two thick strokes, cream with an ink outline.
	var stroke: float = minf(_segment_distance(p, Vector2(78, 132), Vector2(112, 166)),
			_segment_distance(p, Vector2(112, 166), Vector2(180, 92))) - 13.0
	if stroke < OUTLINE * 0.8:
		color = INK
	if stroke < 0.0:
		color = CREAM.lerp(Color8(226, 208, 170), clampf((p.y - 92.0) / 74.0, 0.0, 1.0) * 0.6)
	return color


# --- distance helpers ----------------------------------------------------------------------

func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _round_rect_distance(p: Vector2, center: Vector2, half_size: Vector2, radius: float) -> float:
	var q: Vector2 = (p - center).abs() - half_size + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
