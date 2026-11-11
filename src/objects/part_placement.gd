class_name PartPlacement
extends RefCounted
## Finds where a loose part may lie: a floor point whose 80 px footprint is
## fully on screen, fully supported by solid ground or a platform (physics
## layers 1 and 2) at one surface height, and not within MIN_SPACING of another
## loose part. Used for putting down and for sending a part home.
##
## Geometry only: it asks the physics space, it does not move anything.

## Returned when no valid spot exists.
const NO_SPOT: Vector2 = Vector2(INF, INF)
## Half the part's footprint width.
const HALF_FOOTPRINT: float = 40.0
## Floor-point x range that keeps the 96 px icon fully on the 1280 px screen.
const SCREEN_MIN_X: float = 48.0
const SCREEN_MAX_X: float = 1232.0
## Two loose parts' floor points never lie closer than this.
const MIN_SPACING: float = 60.0
## Physics layers 1 (world) and 2 (one-way platforms).
const SUPPORT_MASK: int = 0b11
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

var _space: PhysicsDirectSpaceState2D = null
var _others: Array[Vector2] = []


## `space`: the world to probe. `others`: floor points of the other loose
## parts (not the one being placed).
func _init(space: PhysicsDirectSpaceState2D, others: Array[Vector2]) -> void:
	_space = space
	_others = others


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


## Spot for a part returning to `home`: `home` itself unless another loose
## part lies within MIN_SPACING of it; then the nearest valid spot at
## offsets of ±step, ±2·step, ... along the same surface. Falls back to `home`
## if nothing on the screen is valid.
func find_return_spot(home: Vector2, step: float) -> Vector2:
	if not _crowded(home):
		return home
	var away: float = _away_direction(home)
	var offset: float = step
	while home.x - offset >= SCREEN_MIN_X or home.x + offset <= SCREEN_MAX_X:
		for direction: float in [away, -away]:
			var spot: Vector2 = valid_spot_at(Vector2(home.x + direction * offset, home.y))
			if spot != NO_SPOT:
				return spot
		offset += step
	return home


## The resting floor point for a part at `at` (x, and the surface height
## to check), or NO_SPOT if it would be off screen, unsupported or too close to
## another loose part. The returned y is the probed surface height.
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
	if _crowded(spot):
		return NO_SPOT
	return spot


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


func _crowded(spot: Vector2) -> bool:
	for other: Vector2 in _others:
		if other.distance_to(spot) < MIN_SPACING:
			return true
	return false


## +1 or -1: away from the nearest loose part closer than MIN_SPACING to
## `spot` (to the right when none is that close or it lies exactly above).
func _away_direction(spot: Vector2) -> float:
	var nearest: Vector2 = NO_SPOT
	var nearest_distance: float = INF
	for other: Vector2 in _others:
		var distance: float = other.distance_to(spot)
		if distance < MIN_SPACING and distance < nearest_distance:
			nearest = other
			nearest_distance = distance
	if nearest == NO_SPOT or nearest.x <= spot.x:
		return 1.0
	return -1.0
