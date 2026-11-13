extends SceneTree
## Generates the illustrated wooden-shelf platform tiles and writes one composite tile atlas per
## world theme to res://assets/processed/tileset_<theme>.png.
##
## Run from the project root, then re-import and rebuild the TileSets:
##   godot --headless --path . --script res://tools/generate_platform_art.gd
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/build_tilesets.gd
##
## Each composite is a pixel copy of that theme's pack atlas (256x256, 4x4 cells of 64 px) with
## the four one-way platform cells (tile IDs 4 left, 5 middle, 6 right, 7 single) replaced by a
## hand-inked shelf built from res://assets/platforms/narrow_shelf.png:
##   - the plank is the source plank scaled by PLANK_SCALE (26 rows thick), cut to an exact
##     rounded rectangle whose straight top edge is row PLANK_TOP_ROW (the one-way collision top),
##     outlined in the pack's ink, deepened in colour, shaded towards its bottom edge, with a
##     light band under the top ink;
##   - the middle tile's wood is a 64 px span of the source plank, made seamless by a cross-fade
##     and with knots softened, so it repeats without a visible seam or an obvious mark;
##   - the left and right tiles keep the source plank's rounded ends and one scaled scroll bracket;
##     the single tile has both ends and two brackets;
##   - the brackets get a 1 px ink rim, and a short, soft ink shadow falls under the plank and
##     the brackets.
## The shelf is tinted per theme by the ratio of that theme's pack platform colours to the Old
## Workshop's. Source PNGs in res://assets/ are only read, never written. Output is deterministic.

const BuildTilesets := preload("res://tools/build_tilesets.gd")

const SHELF_PATH: String = "res://assets/platforms/narrow_shelf.png"
const REFERENCE_THEME: String = "old_workshop"

const TILE_PX: int = 64
const ATLAS_COLUMNS: int = 4
const TILE_LEFT: int = 4
const TILE_MIDDLE: int = 5
const TILE_RIGHT: int = 6
const TILE_SINGLE: int = 7

const INK: Color = Color8(36, 24, 15)
const CLEAR: Color = Color(0, 0, 0, 0)

# --- Plank --------------------------------------------------------------------------------------
## The source shelf is scaled by this before its plank is cut out (32 source rows -> 26).
const PLANK_SCALE: float = 0.8125
## Top row of the plank in the 64 px cell: the one-way strip's top, so texture_origin is 0.
const PLANK_TOP_ROW: int = BuildTilesets.ONE_WAY_TOP_ROW
## Plank thickness in cell rows (rows 14-39, 13 px on screen).
const PLANK_ROWS: int = 26
## Transparent columns left outside a rounded plank end.
const PLANK_END_INSET: int = 2
const PLANK_CORNER_RADIUS: float = 5.0
## Width of the ink outline drawn inside the plank's edge (source px; 1.75 px on screen).
const OUTLINE_WIDTH: float = 3.5
## Scaled-shelf columns between the two ends, used to measure the plank's rows and mean colours.
const MEASURE_COLUMNS: Vector2i = Vector2i(40, 220)
## Scaled-shelf column where the middle tile's 64 px of wood start.
const MIDDLE_SPAN_START: int = 110
## Columns cross-faded across the middle tile's wrap so it tiles seamlessly.
const SEAM_FADE: int = 20
## Columns at each edge of the middle tile pulled to a shared colour, so edge columns match.
const EDGE_MATCH_COLUMNS: int = 4
## Plank-end columns copied from the source as they are, then cross-faded into the middle wood.
const END_KEEP: int = 18
const END_FADE: int = 12
## Soft limit on how far a pixel may stray from its row's mean colour (tames knots and marks).
const DETAIL_LIMIT: float = 0.09
## Light band under the top ink, so the walkable top reads clearly. Strength per row from
## HIGHLIGHT_FIRST_ROW (the row where the top ink fades into the wood).
const HIGHLIGHT: Color = Color8(255, 230, 178)
const HIGHLIGHT_STRENGTH: Array[float] = [0.50, 0.36, 0.14]
const HIGHLIGHT_FIRST_ROW: int = 17
## Deeper, richer wood than the pale source plank (multiplies the wood colour).
const WOOD_GAIN: Color = Color(0.90, 0.85, 0.80)
## The plank's lower rows darken towards its bottom ink, so it reads as a thick, solid board.
const SHADE_ROWS: int = 8
const SHADE_DEEPEST: float = 0.68

# --- Shadow -------------------------------------------------------------------------------------
## Ink shadow alpha on the rows right under the plank.
const SHADOW_ALPHAS: Array[float] = [0.30, 0.17, 0.07]
## Bracket shadow: the bracket's own shape, offset and faded.
const BRACKET_SHADOW_OFFSET: Vector2i = Vector2i(2, 1)
const BRACKET_SHADOW_ALPHA: float = 0.22

# --- Brackets -----------------------------------------------------------------------------------
## Source rectangles of the two scroll brackets (cleat with bolt, leg, fillet; rail cut off).
const LEFT_BRACKET_SOURCE: Rect2i = Rect2i(31, 53, 74, 68)
const RIGHT_BRACKET_SOURCE: Rect2i = Rect2i(220, 53, 75, 68)
## Source columns at the bracket's inner side over which the cut rail stub fades out.
const BRACKET_RAIL_FADE: int = 12
## Source rows of the rail band (under the plank) that the fade applies to.
const BRACKET_RAIL_ROWS: Vector2i = Vector2i(53, 64)
const BRACKET_SCALE: float = 0.38
## Cell row of the bracket's top edge (tucked behind the plank's bottom edge).
const BRACKET_TOP_ROW: int = 36
## Cell column of the bracket's left edge in the left and right tiles.
const LEFT_BRACKET_X: int = 8
const RIGHT_BRACKET_X: int = 26
## Single tile: two brackets, left edges at these columns.
const SINGLE_LEFT_BRACKET_X: int = 3
const SINGLE_RIGHT_BRACKET_X: int = 31

var _shelf: Image
var _plank_top: int = 0
var _plank_left: int = 0
var _plank_right: int = 0
var _middle_wood: Image
var _left_bracket: Image
var _right_bracket: Image


func _init() -> void:
	quit(_run())


func _run() -> int:
	var source: Image = _load(SHELF_PATH)
	if source == null:
		return 1
	_shelf = _scaled_unpremultiplied(source, Rect2i(Vector2i.ZERO, source.get_size()), PLANK_SCALE, Vector2i.ZERO)
	if not _measure_plank():
		return 1
	_soften_detail()
	_middle_wood = _make_middle_wood()
	_left_bracket = _scaled_unpremultiplied(source, LEFT_BRACKET_SOURCE, BRACKET_SCALE, Vector2i(1, 0))
	_right_bracket = _scaled_unpremultiplied(source, RIGHT_BRACKET_SOURCE, BRACKET_SCALE, Vector2i(-1, 0))
	print("generate_platform_art: scaled shelf %dx%d, plank rows %d.., ends at columns %d and %d, brackets %s and %s" % [
			_shelf.get_width(), _shelf.get_height(), _plank_top, _plank_left, _plank_right,
			_left_bracket.get_size(), _right_bracket.get_size()])

	var cells: Dictionary = {
		TILE_LEFT: _build_cell(true, false, [LEFT_BRACKET_X], [_left_bracket]),
		TILE_MIDDLE: _build_cell(false, false, [], []),
		TILE_RIGHT: _build_cell(false, true, [RIGHT_BRACKET_X], [_right_bracket]),
		TILE_SINGLE: _build_cell(true, true, [SINGLE_LEFT_BRACKET_X, SINGLE_RIGHT_BRACKET_X], [_left_bracket, _right_bracket]),
	}
	for tile_id: int in cells:
		if cells[tile_id] == null:
			return 1

	var reference: Image = _load(BuildTilesets.THEMES[REFERENCE_THEME])
	if reference == null:
		return 1
	var reference_mean: Color = _platform_mean(reference)
	var failures: int = 0
	for theme: String in BuildTilesets.THEMES:
		var atlas: Image = _load(BuildTilesets.THEMES[theme])
		if atlas == null:
			failures += 1
			continue
		var mean: Color = _platform_mean(atlas)
		var tint: Color = Color(mean.r / reference_mean.r, mean.g / reference_mean.g, mean.b / reference_mean.b)
		for tile_id: int in cells:
			var origin: Vector2i = Vector2i(tile_id % ATLAS_COLUMNS, tile_id / ATLAS_COLUMNS) * TILE_PX
			atlas.fill_rect(Rect2i(origin, Vector2i(TILE_PX, TILE_PX)), CLEAR)
			atlas.blit_rect(_tinted(cells[tile_id], tint), Rect2i(0, 0, TILE_PX, TILE_PX), origin)
		var path: String = BuildTilesets.COMPOSITE_PATH_FORMAT % theme
		var err: Error = atlas.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("generate_platform_art: could not save %s (%s)" % [path, error_string(err)])
			failures += 1
			continue
		print("generate_platform_art: wrote %s (tint %.3f, %.3f, %.3f)" % [path, tint.r, tint.g, tint.b])
	return 1 if failures > 0 else 0


func _load(path: String) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("generate_platform_art: could not load %s" % path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Cuts `region` out of `source`, scales it with alpha premultiplied (so transparent pixels do not
## bleed dark fringes) and returns it un-premultiplied. `rail_fade_side` (x = +1 fades the right
## edge, -1 the left) fades out the cut rail stub of a bracket before scaling.
func _scaled_unpremultiplied(source: Image, region: Rect2i, factor: float, rail_fade_side: Vector2i) -> Image:
	var img: Image = source.get_region(region)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var a: float = c.a * _rail_fade(region, x, y, rail_fade_side.x)
			img.set_pixel(x, y, Color(c.r * a, c.g * a, c.b * a, a))
	var w: int = roundi(region.size.x * factor)
	var h: int = roundi(region.size.y * factor)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	for y: int in h:
		for x: int in w:
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				img.set_pixel(x, y, CLEAR)
			else:
				img.set_pixel(x, y, Color(clampf(c.r / c.a, 0.0, 1.0), clampf(c.g / c.a, 0.0, 1.0), clampf(c.b / c.a, 0.0, 1.0), clampf(c.a, 0.0, 1.0)))
	return img


func _rail_fade(region: Rect2i, x: int, y: int, side: int) -> float:
	if side == 0:
		return 1.0
	var source_y: int = region.position.y + y
	if source_y < BRACKET_RAIL_ROWS.x or source_y > BRACKET_RAIL_ROWS.y:
		return 1.0
	var from_edge: int = region.size.x - 1 - x if side > 0 else x
	return clampf(float(from_edge) / BRACKET_RAIL_FADE, 0.0, 1.0)


## Finds the scaled plank's top row (median alpha >= 0.5 across the measured columns) and the
## columns of its two ends (on the plank's middle row).
func _measure_plank() -> bool:
	_plank_top = -1
	for y: int in _shelf.get_height():
		var alphas: Array[float] = []
		for x: int in range(MEASURE_COLUMNS.x, MEASURE_COLUMNS.y):
			alphas.append(_shelf.get_pixel(x, y).a)
		alphas.sort()
		if alphas[alphas.size() / 2] >= 0.5:
			_plank_top = y
			break
	if _plank_top < 0:
		push_error("generate_platform_art: no plank found in %s" % SHELF_PATH)
		return false
	var mid_row: int = _plank_top + PLANK_ROWS / 2
	_plank_left = -1
	_plank_right = -1
	for x: int in _shelf.get_width():
		if _shelf.get_pixel(x, mid_row).a >= 0.5:
			if _plank_left < 0:
				_plank_left = x
			_plank_right = x
	return _plank_left >= 0


## Shelf row that cell row `y` takes its wood from.
func _shelf_row(y: int) -> int:
	return clampi(y - PLANK_TOP_ROW + _plank_top, 0, _shelf.get_height() - 1)


## Pulls every plank pixel towards its row's mean colour by a soft limit, keeping the grain's
## streaks but flattening knots and dark marks that would repeat every tile.
func _soften_detail() -> void:
	for row: int in PLANK_ROWS:
		var y: int = _plank_top + row
		var sum: Color = Color(0, 0, 0, 0)
		var count: int = 0
		for x: int in range(MEASURE_COLUMNS.x, MEASURE_COLUMNS.y):
			var c: Color = _shelf.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				count += 1
		if count == 0:
			continue
		var mean: Color = sum / count
		for x: int in _shelf.get_width():
			var c: Color = _shelf.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			_shelf.set_pixel(x, y, Color(_soft(c.r, mean.r), _soft(c.g, mean.g), _soft(c.b, mean.b), c.a))


func _soft(value: float, mean: float) -> float:
	return mean + DETAIL_LIMIT * tanh((value - mean) / DETAIL_LIMIT)


## The middle tile's wood (64 columns, shelf rows): a span of the plank whose wrap is cross-faded
## so column 63 runs into column 0, then both edge columns pulled to the same colour.
func _make_middle_wood() -> Image:
	var wood: Image = Image.create(TILE_PX, _shelf.get_height(), false, Image.FORMAT_RGBA8)
	wood.fill(CLEAR)
	for y: int in _shelf.get_height():
		for x: int in TILE_PX:
			var c: Color = _shelf.get_pixel(MIDDLE_SPAN_START + x, y)
			if x < SEAM_FADE:
				var wrapped: Color = _shelf.get_pixel(MIDDLE_SPAN_START + x + TILE_PX, y)
				c = wrapped.lerp(c, float(x) / SEAM_FADE)
			wood.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		var first: Color = wood.get_pixel(0, y)
		var last: Color = wood.get_pixel(TILE_PX - 1, y)
		var shared: Color = first.lerp(last, 0.5)
		for i: int in EDGE_MATCH_COLUMNS:
			var weight: float = 1.0 - float(i) / EDGE_MATCH_COLUMNS
			wood.set_pixel(i, y, wood.get_pixel(i, y).lerp(shared, weight))
			wood.set_pixel(TILE_PX - 1 - i, y, wood.get_pixel(TILE_PX - 1 - i, y).lerp(shared, weight))
	return wood


## One 64x64 platform cell. A closed side gets a rounded inked end; an open side runs to the
## cell edge in the middle wood. Brackets are drawn behind the plank.
func _build_cell(closed_left: bool, closed_right: bool, bracket_x: Array[int], brackets: Array[Image]) -> Image:
	var cell: Image = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	cell.fill(CLEAR)
	var left_edge: float = float(PLANK_END_INSET) if closed_left else -1000.0
	var right_edge: float = float(TILE_PX - PLANK_END_INSET) if closed_right else 1000.0
	var top_edge: float = float(PLANK_TOP_ROW)
	var bottom_edge: float = float(PLANK_TOP_ROW + PLANK_ROWS)

	# Shadows first (plank, then brackets), so the wood covers them.
	for x: int in TILE_PX:
		var coverage: float = _plank_coverage(Vector2(x + 0.5, bottom_edge - 0.5), left_edge, right_edge, top_edge, bottom_edge)
		for i: int in SHADOW_ALPHAS.size():
			_over(cell, x, int(bottom_edge) + i, INK, SHADOW_ALPHAS[i] * coverage)
	# Each bracket gets a 1 px ink rim (its silhouette grown by one pixel), so it stays inked
	# after scaling; its shadow is that rim's shape, offset and faded.
	var cell_rect: Rect2i = Rect2i(Vector2i.ZERO, Vector2i(TILE_PX, TILE_PX))
	var rims: Array[Image] = []
	for b: int in brackets.size():
		var rim: Image = _grown_alpha(brackets[b])
		rims.append(rim)
		var rim_at: Vector2i = Vector2i(bracket_x[b], BRACKET_TOP_ROW) - Vector2i.ONE
		if not cell_rect.encloses(Rect2i(rim_at + BRACKET_SHADOW_OFFSET, rim.get_size())) or not cell_rect.encloses(Rect2i(rim_at, rim.get_size())):
			push_error("generate_platform_art: bracket at %s does not fit in the cell" % rim_at)
			return null
		for y: int in rim.get_height():
			for x: int in rim.get_width():
				var p: Vector2i = rim_at + BRACKET_SHADOW_OFFSET + Vector2i(x, y)
				_over(cell, p.x, p.y, INK, rim.get_pixel(x, y).a * BRACKET_SHADOW_ALPHA)
	for b: int in brackets.size():
		var bracket: Image = brackets[b]
		var at: Vector2i = Vector2i(bracket_x[b], BRACKET_TOP_ROW)
		for y: int in rims[b].get_height():
			for x: int in rims[b].get_width():
				_over(cell, at.x - 1 + x, at.y - 1 + y, INK, rims[b].get_pixel(x, y).a)
		for y: int in bracket.get_height():
			for x: int in bracket.get_width():
				var c: Color = bracket.get_pixel(x, y)
				_over(cell, at.x + x, at.y + y, Color(c.r, c.g, c.b), c.a)

	# The plank: an exact rounded rectangle, ink outline inside its edge, wood within.
	for y: int in range(PLANK_TOP_ROW, PLANK_TOP_ROW + PLANK_ROWS):
		var shade_t: float = clampf(float(y - (PLANK_TOP_ROW + PLANK_ROWS - SHADE_ROWS)) / SHADE_ROWS, 0.0, 1.0)
		var shade: float = lerpf(1.0, SHADE_DEEPEST, shade_t)
		for x: int in TILE_PX:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var sd: float = _plank_sd(p, left_edge, right_edge, top_edge, bottom_edge)
			var coverage: float = clampf(0.5 - sd, 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var wood: Color = _wood(x, y, closed_left, closed_right)
			wood = Color(wood.r * WOOD_GAIN.r * shade, wood.g * WOOD_GAIN.g * shade, wood.b * WOOD_GAIN.b * shade)
			var highlight_index: int = y - HIGHLIGHT_FIRST_ROW
			if highlight_index >= 0 and highlight_index < HIGHLIGHT_STRENGTH.size():
				wood = wood.lerp(HIGHLIGHT, HIGHLIGHT_STRENGTH[highlight_index])
			var inner: float = clampf(-sd - OUTLINE_WIDTH + 0.5, 0.0, 1.0)
			_over(cell, x, y, INK.lerp(wood, inner), coverage)
	return cell


## Wood colour for a plank pixel: the seamless middle wood, with the source plank's own ends
## laid over it near a closed side (weighted by the source's alpha, so its silhouette edge never
## shows through).
func _wood(x: int, y: int, closed_left: bool, closed_right: bool) -> Color:
	var row: int = _shelf_row(y)
	var c: Color = _middle_wood.get_pixel(x, row)
	if closed_left:
		var weight: float = 1.0 - clampf(float(x - PLANK_END_INSET - END_KEEP) / END_FADE, 0.0, 1.0)
		var sx: int = _plank_left + x - PLANK_END_INSET
		if weight > 0.0 and sx >= 0 and sx < _shelf.get_width():
			var s: Color = _shelf.get_pixel(sx, row)
			c = c.lerp(Color(s.r, s.g, s.b), weight * s.a)
	if closed_right:
		var from_right: int = TILE_PX - PLANK_END_INSET - 1 - x
		var weight: float = 1.0 - clampf(float(from_right - END_KEEP) / END_FADE, 0.0, 1.0)
		var sx: int = _plank_right - from_right
		if weight > 0.0 and sx >= 0 and sx < _shelf.get_width():
			var s: Color = _shelf.get_pixel(sx, row)
			c = c.lerp(Color(s.r, s.g, s.b), weight * s.a)
	return Color(c.r, c.g, c.b, 1.0)


## Signed distance to the plank's rounded rectangle (negative inside). Corners are rounded only
## on closed sides; an open side's edge is placed far outside the cell.
func _plank_sd(p: Vector2, left: float, right: float, top: float, bottom: float) -> float:
	var centre: Vector2 = Vector2((left + right) * 0.5, (top + bottom) * 0.5)
	var half: Vector2 = Vector2((right - left) * 0.5, (bottom - top) * 0.5)
	var r: float = PLANK_CORNER_RADIUS
	var q: Vector2 = (p - centre).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## Alpha of `img` grown by one pixel in every direction (3x3 maximum), on a canvas 2 px larger.
func _grown_alpha(img: Image) -> Image:
	var w: int = img.get_width() + 2
	var h: int = img.get_height() + 2
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(CLEAR)
	for y: int in h:
		for x: int in w:
			var a: float = 0.0
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var sx: int = x - 1 + dx
					var sy: int = y - 1 + dy
					if sx >= 0 and sy >= 0 and sx < img.get_width() and sy < img.get_height():
						a = maxf(a, img.get_pixel(sx, sy).a)
			out.set_pixel(x, y, Color(INK.r, INK.g, INK.b, a))
	return out


func _plank_coverage(p: Vector2, left: float, right: float, top: float, bottom: float) -> float:
	return clampf(0.5 - _plank_sd(p, left, right, top, bottom), 0.0, 1.0)


func _over(img: Image, x: int, y: int, color: Color, amount: float) -> void:
	if amount <= 0.0 or x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var src: Color = Color(color.r, color.g, color.b, clampf(amount, 0.0, 1.0))
	img.set_pixel(x, y, img.get_pixel(x, y).blend(src))


## Mean RGB of the pack's platform cells (tiles 4-7, alpha > 0) in an atlas.
func _platform_mean(atlas: Image) -> Color:
	var sum: Color = Color(0, 0, 0, 0)
	var count: int = 0
	for tile_id: int in BuildTilesets.ONE_WAY_TILE_IDS:
		var origin: Vector2i = Vector2i(tile_id % ATLAS_COLUMNS, tile_id / ATLAS_COLUMNS) * TILE_PX
		for y: int in TILE_PX:
			for x: int in TILE_PX:
				var c: Color = atlas.get_pixel(origin.x + x, origin.y + y)
				if c.a > 0.0:
					sum += Color(c.r, c.g, c.b, 0.0)
					count += 1
	return sum / maxi(count, 1)


func _tinted(cell: Image, tint: Color) -> Image:
	var out: Image = cell.duplicate() as Image
	for y: int in out.get_height():
		for x: int in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(clampf(c.r * tint.r, 0.0, 1.0), clampf(c.g * tint.g, 0.0, 1.0), clampf(c.b * tint.b, 0.0, 1.0), c.a))
	return out
