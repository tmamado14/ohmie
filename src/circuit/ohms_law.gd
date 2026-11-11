class_name OhmsLaw
extends RefCounted
## Ohm's law on exact values: I = V / R and R = V / I.
##
## Pure and exact (Rational only). Both functions return null, without pushing
## an error, when an argument is null or invalid or the divisor is zero.


## The current in amperes that `voltage` drives through `resistance` (V / R).
static func current(voltage: Rational, resistance: Rational) -> Rational:
	if not _usable(voltage) or not _usable(resistance) or resistance.is_zero():
		return null
	return voltage.div(resistance)


## The resistance in ohms that draws `current` from `voltage` (V / I).
static func resistance_for(voltage: Rational, current: Rational) -> Rational:
	if not _usable(voltage) or not _usable(current) or current.is_zero():
		return null
	return voltage.div(current)


static func _usable(value: Rational) -> bool:
	return value != null and value.is_valid()
