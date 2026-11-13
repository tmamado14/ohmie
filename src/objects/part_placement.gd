class_name PartPlacement
extends RefCounted
## Finds where a loose part may lie: a floor point whose 80 px footprint is
## fully on screen, fully supported by solid ground or a platform (physics
## layers 1 and 2) at one surface height, not crowding another loose part
## (closer than MIN_SPACING horizontally while their icons share height), and
## not overlapping a blocked area (a PartBlocker: a bounce pad, a static
## hazard, a slot's frame, a fixed board part, lamp or meter, or the door; the
## footprint is HALF_FOOTPRINT * 2 wide and FOOTPRINT_HEIGHT tall). Used for
## putting down and for sending a part home.
##
## Sending a part home (find_return_spot) also knows the room's standing
## surfaces and the areas its enemies and hazards sweep ("danger"):
##   1. the home itself, unless another loose part crowds it or it lies on a
##      blocked area;
##   2. the nearest valid spot on the home's own surface (the continuous run of
##      floor or platform at the home's height), tried outward both ways in
##      RETURN_STEP steps, outside every danger area;
##   3. the nearest valid spot on the home surface inside a danger area;
##   4. only when the home surface holds no valid spot at all, the valid spot
##      on any other surface nearest the home in a straight line, outside
##      danger first.
## Every spot from steps 2-4 also leaves Ohmie room to stand on it (so the part
## can be picked up again from its own level). Only when nothing on the screen
## qualifies is the spacing between loose parts relaxed, step by step, down to
## RELAXED_MIN_SPACING (icons just not overlapping), with a warning. If even
## that finds nothing the result is NO_SPOT; a part is never stacked.
##
## Geometry only: it asks the physics space, it does not move anything.

## Returned when no valid spot exists.
const NO_SPOT: Vector2 = Vector2(INF, INF)
## Half the part's footprint width.
const HALF_FOOTPRINT: float = 40.0
## Height of the part's footprint above its floor point (the 64 px icon).
const FOOTPRINT_HEIGHT: float = 64.0
## Floor-point x range that keeps the 96 px icon fully on the 1280 px screen.
const SCREEN_MIN_X: float = 48.0
const SCREEN_MAX_X: float = 1232.0
## Two loose parts at the same level lie at least this far apart (floor point
## x), so their 96 px icons never overlap. Parts whose floor points differ by
## FOOTPRINT_HEIGHT or more (one on a ledge above the other) do not crowd.
const MIN_SPACING: float = 100.0
## The last-resort spacing for a returning part: the 96 px icons just do not
## overlap. Reached in SPACING_RELAX_STEP steps from MIN_SPACING.
const RELAXED_MIN_SPACING: float = 96.0
const SPACING_RELAX_STEP: float = 1.0
## Physics layers 1 (world) and 2 (one-way platforms).
const SUPPORT_MASK: int = 0b11
## Physics layer 1 alone: solid ground, which Ohmie cannot stand inside.
const SOLID_MASK: int = 0b01
## Each support probe is a vertical ray from this far above the surface to
## this far below it.
const PROBE_DEPTH: float = 8.0
## A probe's hit must lie this close to the surface height.
const SURFACE_TOLERANCE: float = 2.0
## The end probes sit this far inside the footprint's ends, so a footprint that
## ends exactly at a tile edge counts as supported.
const EDGE_INSET: float = 0.5
## Step of the search when sliding a put-down along the surface.
const SLIDE_STEP: float = 1.0
## Step of the search for a returning part's spot along a surface.
const RETURN_STEP: float = 8.0
## Ohmie's standing body (the 36 x 88 collider, 1 px smaller each way) must fit
## on a returned part's spot without touching solid ground.
const STANDING_BODY_SIZE: Vector2 = Vector2(34, 86)

var _space: PhysicsDirectSpaceState2D = null
var _others: Array[Vector2] = []
var _blocked: Array[Rect2] = []
var _surfaces: Array[Rect2] = []
var _danger: Array[Rect2] = []
var _spacing: float = MIN_SPACING
var _standing_body: RectangleShape2D = null


## `space`: the world to probe. `others`: floor points of the other loose
## parts (not the one being placed). `blocked`: global areas a footprint may
## not overlap (touching edges is allowed). `surfaces`: the room's standing
## surfaces as zero-height rects (RoomTiles.standing_surfaces). `danger`: areas
## a returning part keeps out of when it can (enemy and hazard sweeps).
func _init(space: PhysicsDirectSpaceState2D, others: Array[Vector2],
		blocked: Array[Rect2] = [], surfaces: Array[Rect2] = [], danger: Array[Rect2] = []) -> void:
	_space = space
	_others = others
	_blocked = blocked
	_surfaces = surfaces
	_danger = danger


## Spot for putting a part down at `feet` (Ohmie's feet on a surface):
## `feet.x` if valid, otherwise the nearest valid x within `max_slide` px on the
## same surface, sliding away from a too-close loose part first on a tie.
## NO_SPOT if there is none.
func find_put_down(feet: Vector2, max_slide: float) -> Vector2:
	var away: float = _away_direction(feet)
	var offset: float = 0.0
	while offset <= max_slide:
		for direction: float in [away, -away]:
			var spot: Vector2 = valid_spot_at(Vector2(feet.x + direction * offset, feet.y))
			if spot != NO_SPOT:
				return spot
			if offset == 0.0:
				break
		offset += SLIDE_STEP
	return NO_SPOT


## Spot for a part returning to `home` (see the class description for the
## order). NO_SPOT only when nothing on the screen qualifies even with the
## spacing relaxed to RELAXED_MIN_SPACING.
func find_return_spot(home: Vector2) -> Vector2:
	_spacing = MIN_SPACING
	while _spacing >= RELAXED_MIN_SPACING:
		var spot: Vector2 = _return_spot(home)
		if spot != NO_SPOT:
			if _spacing < MIN_SPACING:
				push_warning("PartPlacement: no spot for a part returning to %s with %.0f px between loose parts; used %.0f px at %s"
						% [home, MIN_SPACING, _spacing, spot])
			_spacing = MIN_SPACING
			return spot
		_spacing -= SPACING_RELAX_STEP
	_spacing = MIN_SPACING
	return NO_SPOT


## The resting floor point for a part at `at` (x, and the surface height
## to check), or NO_SPOT if it would be off screen, unsupported or too close to
## another loose part, or overlapping a blocked area. The returned y is the
## probed surface height.
func valid_spot_at(at: Vector2) -> Vector2:
	if at.x < SCREEN_MIN_X or at.x > SCREEN_MAX_X:
		return NO_SPOT
	var surface_y: float = _surface_y(at.x, at.y)
	if is_inf(surface_y):
		return NO_SPOT
	var reach: float = HALF_FOOTPRINT - EDGE_INSET
	if absf(_surface_y(at.x - reach, at.y) - surface_y) > SURFACE_TOLERANCE \
			or absf(_surface_y(at.x + reach, at.y) - surface_y) > SURFACE_TOLERANCE:
		return NO_SPOT
	var spot: Vector2 = Vector2(at.x, surface_y)
	if _crowded(spot) or _on_blocked_area(spot):
		return NO_SPOT
	return spot


## True when a part lying at `spot` overlaps an enemy's or hazard's sweep.
func is_in_danger(spot: Vector2) -> bool:
	var footprint: Rect2 = _footprint(spot)
	for area: Rect2 in _danger:
		if footprint.intersects(area):
			return true
	return false


## One pass of the return search at the current spacing.
func _return_spot(home: Vector2) -> Vector2:
	if not _crowded(home) and not _on_blocked_area(home):
		return home
	var home_surface: Rect2 = _surface_under(home)
	var safe: Vector2 = NO_SPOT
	var risky: Vector2 = NO_SPOT
	var offset: float = RETURN_STEP
	while home.x - offset >= home_surface.position.x or home.x + offset <= home_surface.end.x:
		for direction: float in [-1.0, 1.0]:
			var x: float = home.x + direction * offset
			if x < home_surface.position.x or x > home_surface.end.x:
				continue
			var spot: Vector2 = _return_candidate(Vector2(x, home.y))
			if spot == NO_SPOT:
				continue
			if not is_in_danger(spot):
				return spot
			if risky == NO_SPOT:
				risky = spot
		offset += RETURN_STEP
	if risky != NO_SPOT:
		return risky
	var safe_distance: float = INF
	var risky_distance: float = INF
	for surface: Rect2 in _surfaces:
		if surface == home_surface:
			continue
		var x: float = maxf(surface.position.x + HALF_FOOTPRINT, SCREEN_MIN_X)
		var last: float = minf(surface.end.x - HALF_FOOTPRINT, SCREEN_MAX_X)
		while x <= last:
			var spot: Vector2 = _return_candidate(Vector2(x, surface.position.y))
			x += RETURN_STEP
			if spot == NO_SPOT:
				continue
			var distance: float = spot.distance_to(home)
			if not is_in_danger(spot):
				if distance < safe_distance:
					safe = spot
					safe_distance = distance
			elif distance < risky_distance:
				risky = spot
				risky_distance = distance
	return safe if safe != NO_SPOT else risky


## valid_spot_at(`at`), also requiring room for Ohmie to stand on the spot.
func _return_candidate(at: Vector2) -> Vector2:
	var spot: Vector2 = valid_spot_at(at)
	if spot == NO_SPOT or not _has_standing_room(spot):
		return NO_SPOT
	return spot


## The standing surface (from the room's list) that `point` lies on. Without a
## list, or when none matches, the whole screen width at the point's height.
func _surface_under(point: Vector2) -> Rect2:
	for surface: Rect2 in _surfaces:
		if absf(surface.position.y - point.y) <= SURFACE_TOLERANCE \
				and point.x >= surface.position.x and point.x <= surface.end.x:
			return surface
	return Rect2(0.0, point.y, SCREEN_MIN_X + SCREEN_MAX_X, 0.0)


## True when Ohmie's standing body at `feet` touches no solid ground.
func _has_standing_room(feet: Vector2) -> bool:
	if _standing_body == null:
		_standing_body = RectangleShape2D.new()
		_standing_body.size = STANDING_BODY_SIZE
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _standing_body
	query.transform = Transform2D(0.0, feet - Vector2(0.0, STANDING_BODY_SIZE.y * 0.5 + 1.0))
	query.collision_mask = SOLID_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return _space.intersect_shape(query, 1).is_empty()


## Height of the support surface under x near `near_y`, or INF if none.
func _surface_y(x: float, near_y: float) -> float:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			Vector2(x, near_y - PROBE_DEPTH), Vector2(x, near_y + PROBE_DEPTH), SUPPORT_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = _space.intersect_ray(query)
	if hit.is_empty():
		return INF
	var hit_y: float = (hit["position"] as Vector2).y
	if absf(hit_y - near_y) > SURFACE_TOLERANCE:
		return INF
	return hit_y


static func _footprint(spot: Vector2) -> Rect2:
	return Rect2(spot.x - HALF_FOOTPRINT, spot.y - FOOTPRINT_HEIGHT, HALF_FOOTPRINT * 2.0, FOOTPRINT_HEIGHT)


## True when the footprint standing on `spot` overlaps a blocked area.
func _on_blocked_area(spot: Vector2) -> bool:
	var footprint: Rect2 = _footprint(spot)
	for area: Rect2 in _blocked:
		if footprint.intersects(area):
			return true
	return false


func _crowded(spot: Vector2) -> bool:
	for other: Vector2 in _others:
		if _too_close(other, spot):
			return true
	return false


## True when parts at floor points `a` and `b` would overlap or nearly touch.
func _too_close(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) < _spacing and absf(a.y - b.y) < FOOTPRINT_HEIGHT


## +1 or -1: away from the nearest loose part crowding `spot` (to the right
## when none does or it lies exactly above).
func _away_direction(spot: Vector2) -> float:
	var nearest: Vector2 = NO_SPOT
	var nearest_distance: float = INF
	for other: Vector2 in _others:
		var distance: float = other.distance_to(spot)
		if _too_close(other, spot) and distance < nearest_distance:
			nearest = other
			nearest_distance = distance
	if nearest == NO_SPOT or nearest.x <= spot.x:
		return 1.0
	return -1.0
