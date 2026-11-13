class_name TargetTag
extends Node2D
## The small name tag of the highlighted target: a parchment-coloured rounded
## label with dark ink text ("3 Ω", "6 V", "empty") and a small tail pointing
## at the target when it sits right beside it.
##
## The tag stays visually attached to its own target. It tries a few places in
## order and takes the first that is fully on screen, clear of Ohmie's drawn
## body and of the part he carries, clear of the plaque and the mission sign,
## and nearer to its own target's frame than to any other board component:
##   a slot: beside its frame on the side away from Ohmie, then the other
##     side, then just above the frame, then above Ohmie's head, then below;
##   a loose part: above Ohmie's head (and the part he carries), then beside
##     the part, then just above it.
## While Ohmie moves the tag keeps its place as long as it stays valid. If no
## place passes every rule, it takes the first on-screen place clear of Ohmie.
##
## The room hands it the board's component frames and the HUD panels once
## (set_layout), Ohmie's feet every physics frame (set_viewer), and connects
## PlayerCarry.target_changed to show_target(). Looks only.

const FONT: Font = preload("res://resources/fonts/serif_bold.tres")
const FONT_SIZE: int = 16
const PADDING: Vector2 = Vector2(9, 3)
const CORNER_RADIUS: int = 7
const BORDER_WIDTH: int = 2
const FILL_COLOR: Color = Color("f6e7c8")
const BORDER_COLOR: Color = Color("6b4a32")
const TEXT_COLOR: Color = Color("2e1f1a")
## Space between the tag and what it must clear.
const GAP: float = 6.0
## Above the standing surface: the top of Ohmie's antennae, and the top of the
## carried part icon (drawn at 0.75 scale, centre 128 px above the feet).
const HEAD_CLEARANCE: float = 128.0
const CARRY_CLEARANCE: float = 154.0
## Ohmie's drawn body, standing on his feet (his idle art is about 60 px wide,
## antennae up to HEAD_CLEARANCE).
const VIEWER_HALF_WIDTH: float = 32.0
## The carried part's icon (PlayerCarry's CarriedIcon: 96x64 at 0.75 scale,
## centred CARRIED_ICON_HEIGHT above the feet).
const CARRIED_ICON_SIZE: Vector2 = Vector2(72, 48)
const CARRIED_ICON_HEIGHT: float = 128.0
## The tail: its width where it meets the tag; it reaches GAP - TAIL_MARGIN out.
const TAIL_WIDTH: float = 10.0
const TAIL_MARGIN: float = 1.0
## Two rects closer than this count as the same component frame.
const SAME_FRAME_TOLERANCE: float = 0.5
## The tag stays this far inside the 1280x720 screen.
const SCREEN_RECT: Rect2 = Rect2(4, 4, 1272, 712)

enum Place { LEFT, RIGHT, ABOVE, ABOVE_HEAD, BELOW }

var _text: String = ""
var _box: StyleBoxFlat = null
var _target: Interactable = null
var _carrying: bool = false
var _viewer: Vector2 = Vector2(-INF, -INF)
var _frames: Array[Rect2] = []
var _keep_clear: Array[Rect2] = []
var _place: Place = Place.ABOVE_HEAD


func _init() -> void:
	visible = false
	_box = StyleBoxFlat.new()
	_box.bg_color = FILL_COLOR
	_box.border_color = BORDER_COLOR
	_box.set_border_width_all(BORDER_WIDTH)
	_box.set_corner_radius_all(CORNER_RADIUS)
	_box.shadow_color = Color(0, 0, 0, 0.3)
	_box.shadow_size = 2
	_box.shadow_offset = Vector2(0, 2)


## `frames`: the global frame of every board component (slots, fixed parts,
## lamps, meters). `keep_clear`: screen areas the tag must not cover (the plaque
## and the mission sign).
func set_layout(frames: Array[Rect2], keep_clear: Array[Rect2]) -> void:
	_frames = frames.duplicate()
	_keep_clear = keep_clear.duplicate()


## Ohmie's feet (global). Moves the tag only when he now covers it.
func set_viewer(feet: Vector2) -> void:
	_viewer = feet
	if visible and _target != null and is_instance_valid(_target) \
			and not _is_valid(get_global_rect(), _target.get_frame_rect()):
		_choose_place()


## Shows the tag for `target` with `text`, or hides it when `target` is null
## or `text` is empty. `carrying`: Ohmie holds a part (the tag then also clears it).
func show_target(target: Interactable, text: String, carrying: bool) -> void:
	if target == null or text.is_empty():
		visible = false
		_text = ""
		_target = null
		return
	_text = text
	_target = target
	_carrying = carrying
	visible = true
	_choose_place()


func get_text() -> String:
	return _text if visible else ""


## The tag's rectangle in global coordinates (for checks).
func get_global_rect() -> Rect2:
	return Rect2(global_position, tag_size(_text))


static func tag_size(text: String) -> Vector2:
	var text_size: Vector2 = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return Vector2(ceilf(text_size.x), FONT.get_height(FONT_SIZE)) + PADDING * 2.0


## Distance between two rectangles (0 when they touch or overlap).
static func rect_distance(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()


func _choose_place() -> void:
	var frame: Rect2 = _target.get_frame_rect()
	var size: Vector2 = tag_size(_text)
	var order: Array[Place] = _place_order(frame)
	var fallback: Rect2 = Rect2()
	var have_fallback: bool = false
	for place: Place in order:
		var rect: Rect2 = Rect2(_top_left(place, frame, size), size)
		if _is_valid(rect, frame):
			_apply(place, rect)
			return
		if not have_fallback and SCREEN_RECT.encloses(rect) and not _covered_by_viewer(rect):
			fallback = rect
			_place = place
			have_fallback = true
	if not have_fallback:
		_place = order[0]
		fallback = Rect2(_top_left(_place, frame, size), size)
		fallback.position = fallback.position.clamp(SCREEN_RECT.position, SCREEN_RECT.end - size)
	_apply(_place, fallback)


func _apply(place: Place, rect: Rect2) -> void:
	_place = place
	global_position = rect.position.round()
	queue_redraw()


func _place_order(frame: Rect2) -> Array[Place]:
	var away: Place = Place.LEFT if _viewer.x >= frame.get_center().x else Place.RIGHT
	var toward: Place = Place.RIGHT if away == Place.LEFT else Place.LEFT
	if _target is PartPickup:
		return [Place.ABOVE_HEAD, away, toward, Place.ABOVE]
	return [away, toward, Place.ABOVE, Place.ABOVE_HEAD, Place.BELOW]


func _top_left(place: Place, frame: Rect2, size: Vector2) -> Vector2:
	var centre: Vector2 = frame.get_center()
	match place:
		Place.LEFT:
			return Vector2(frame.position.x - GAP - size.x, centre.y - size.y * 0.5)
		Place.RIGHT:
			return Vector2(frame.end.x + GAP, centre.y - size.y * 0.5)
		Place.ABOVE:
			return Vector2(centre.x - size.x * 0.5, frame.position.y - GAP - size.y)
		Place.BELOW:
			return Vector2(centre.x - size.x * 0.5, frame.end.y + GAP)
	var anchor: Vector2 = _target.get_tag_anchor()
	var clearance: float = CARRY_CLEARANCE if _carrying else HEAD_CLEARANCE
	var bottom: float = minf(anchor.y, _target.get_standing_y() - clearance) - GAP
	return Vector2(anchor.x - size.x * 0.5, bottom - size.y)


## On screen, clear of Ohmie, his carried part and the HUD panels, and nearer
## to `frame` than to any other board component.
func _is_valid(rect: Rect2, frame: Rect2) -> bool:
	if not SCREEN_RECT.encloses(rect) or _covered_by_viewer(rect):
		return false
	for area: Rect2 in _keep_clear:
		if rect.intersects(area):
			return false
	var own: float = rect_distance(rect, frame)
	for other: Rect2 in _frames:
		if _same_frame(other, frame):
			continue
		if rect_distance(rect, other) <= own:
			return false
	return true


func _covered_by_viewer(rect: Rect2) -> bool:
	if not is_finite(_viewer.x):
		return false
	var body: Rect2 = Rect2(_viewer.x - VIEWER_HALF_WIDTH, _viewer.y - HEAD_CLEARANCE,
			VIEWER_HALF_WIDTH * 2.0, HEAD_CLEARANCE)
	if rect.intersects(body):
		return true
	if _carrying:
		var icon: Rect2 = Rect2(_viewer - Vector2(CARRIED_ICON_SIZE.x * 0.5,
				CARRIED_ICON_HEIGHT + CARRIED_ICON_SIZE.y * 0.5), CARRIED_ICON_SIZE)
		if rect.intersects(icon):
			return true
	return false


static func _same_frame(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= SAME_FRAME_TOLERANCE \
			and a.size.distance_to(b.size) <= SAME_FRAME_TOLERANCE


func _draw() -> void:
	if _text.is_empty():
		return
	var size: Vector2 = tag_size(_text)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	_draw_tail(size)
	var baseline: Vector2 = Vector2(PADDING.x, PADDING.y + FONT.get_ascent(FONT_SIZE))
	draw_string(FONT, baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)


## A small triangle from the tag's edge toward the target, for the places
## right beside the target's frame.
func _draw_tail(size: Vector2) -> void:
	var reach: float = GAP - TAIL_MARGIN
	var half: float = TAIL_WIDTH * 0.5
	var base_a: Vector2
	var base_b: Vector2
	var tip: Vector2
	var inward: Vector2
	match _place:
		Place.LEFT:
			base_a = Vector2(size.x, size.y * 0.5 - half)
			base_b = Vector2(size.x, size.y * 0.5 + half)
			tip = Vector2(size.x + reach, size.y * 0.5)
			inward = Vector2(-BORDER_WIDTH, 0)
		Place.RIGHT:
			base_a = Vector2(0, size.y * 0.5 - half)
			base_b = Vector2(0, size.y * 0.5 + half)
			tip = Vector2(-reach, size.y * 0.5)
			inward = Vector2(BORDER_WIDTH, 0)
		Place.ABOVE:
			base_a = Vector2(size.x * 0.5 - half, size.y)
			base_b = Vector2(size.x * 0.5 + half, size.y)
			tip = Vector2(size.x * 0.5, size.y + reach)
			inward = Vector2(0, -BORDER_WIDTH)
		Place.BELOW:
			base_a = Vector2(size.x * 0.5 - half, 0)
			base_b = Vector2(size.x * 0.5 + half, 0)
			tip = Vector2(size.x * 0.5, -reach)
			inward = Vector2(0, BORDER_WIDTH)
		_:
			return
	draw_colored_polygon(PackedVector2Array([base_a + inward, tip, base_b + inward]), FILL_COLOR)
	draw_polyline(PackedVector2Array([base_a, tip, base_b]), BORDER_COLOR, BORDER_WIDTH, true)
