class_name PwlCondition
extends RefCounted
## One linear condition that must hold while a piecewise-linear device is in
## a given state. Immutable after construction.
##
## A device (see PwlDevice) is a set of branches between its terminals. Every
## condition is stated on those branches only:
##   BRANCH_VOLTAGE   V(from) - V(to) of one branch  <relation>  bound
##   BRANCH_CURRENTS  sum over branches of coefficient * current  <relation>  bound
## where a branch current flows from its `from` terminal to its `to` terminal
## through the device. Examples:
##   diode OFF   voltage(0, AT_MOST, Vf)            v <= Vf
##   diode ON    current(0, ABOVE, 0)               i > 0
##   (later) transistor saturated  current_sum([-beta, 1], AT_MOST, 0)
##                                 Ic - beta * Ib <= 0
##
## Strict relations (BELOW, ABOVE) let neighbouring states share a boundary
## point without both claiming it: see DiodeModel for the boundary rule.

enum Quantity { BRANCH_VOLTAGE, BRANCH_CURRENTS }
## AT_MOST <=, AT_LEAST >=, BELOW <, ABOVE >.
enum Relation { AT_MOST, AT_LEAST, BELOW, ABOVE }

const _RELATION_TEXTS: Array[String] = ["<=", ">=", "<", ">"]

var quantity: Quantity:
	get:
		return _quantity
var relation: Relation:
	get:
		return _relation
## The right-hand side. Never null on a valid condition.
var bound: Rational:
	get:
		return _bound
## BRANCH_VOLTAGE only: the branch index; -1 otherwise.
var branch: int:
	get:
		return _branch

var _quantity: Quantity = Quantity.BRANCH_VOLTAGE
var _relation: Relation = Relation.AT_MOST
var _bound: Rational = null
var _branch: int = -1
var _coefficients: Array[Rational] = []


## V(from) - V(to) of `branch_index` <relation> `limit`. Returns null (with
## push_error) for a negative branch or a null/invalid limit.
static func voltage(branch_index: int, how: Relation, limit: Rational) -> PwlCondition:
	if branch_index < 0 or not _valid_number(limit):
		push_error("PwlCondition.voltage: needs a branch >= 0 and a valid bound.")
		return null
	var condition: PwlCondition = PwlCondition.new()
	condition._quantity = Quantity.BRANCH_VOLTAGE
	condition._branch = branch_index
	condition._relation = how
	condition._bound = limit
	return condition


## The current of `branch_index` <relation> `limit`. Returns null (with
## push_error) for a negative branch or a null/invalid limit.
static func current(branch_index: int, how: Relation, limit: Rational) -> PwlCondition:
	if branch_index < 0 or not _valid_number(limit):
		push_error("PwlCondition.current: needs a branch >= 0 and a valid bound.")
		return null
	var coefficients: Array[Rational] = []
	coefficients.resize(branch_index + 1)
	coefficients[branch_index] = Rational.new(1)
	return current_sum(coefficients, how, limit)


## sum of coefficients[b] * current of branch b <relation> `limit`. A null
## coefficient counts as zero. Returns null (with push_error) for an empty
## list, an invalid coefficient, all coefficients zero, or an invalid limit.
static func current_sum(coefficients: Array[Rational], how: Relation, limit: Rational) -> PwlCondition:
	if not _valid_number(limit):
		push_error("PwlCondition.current_sum: needs a valid bound.")
		return null
	var any_non_zero: bool = false
	for c: Rational in coefficients:
		if c == null:
			continue
		if not c.is_valid():
			push_error("PwlCondition.current_sum: a coefficient is an invalid Rational.")
			return null
		if not c.is_zero():
			any_non_zero = true
	if not any_non_zero:
		push_error("PwlCondition.current_sum: needs at least one non-zero coefficient.")
		return null
	var condition: PwlCondition = PwlCondition.new()
	condition._quantity = Quantity.BRANCH_CURRENTS
	condition._coefficients = coefficients.duplicate()
	condition._relation = how
	condition._bound = limit
	return condition


## BRANCH_CURRENTS only: the coefficient of `branch_index` (zero when not
## listed). Null for a BRANCH_VOLTAGE condition.
func coefficient(branch_index: int) -> Rational:
	if _quantity != Quantity.BRANCH_CURRENTS:
		return null
	if branch_index < 0 or branch_index >= _coefficients.size() or _coefficients[branch_index] == null:
		return Rational.new(0)
	return _coefficients[branch_index]


## The number of coefficient entries (the highest listed branch + 1). 0 for a
## BRANCH_VOLTAGE condition.
func coefficient_count() -> int:
	return _coefficients.size() if _quantity == Quantity.BRANCH_CURRENTS else 0


## True for BELOW and ABOVE.
func is_strict() -> bool:
	return _relation == Relation.BELOW or _relation == Relation.ABOVE


## True when `value` (the left-hand side) satisfies the relation exactly.
## False for a null or invalid value.
func holds(value: Rational) -> bool:
	if value == null or not value.is_valid():
		return false
	var c: int = value.compare(_bound)
	match _relation:
		Relation.AT_MOST:
			return c <= 0
		Relation.AT_LEAST:
			return c >= 0
		Relation.BELOW:
			return c < 0
		Relation.ABOVE:
			return c > 0
	return false


## "V0 <= 7/10", "I0 > 0", "-100 I0 + I1 <= 0".
func to_text() -> String:
	var left: String = ""
	if _quantity == Quantity.BRANCH_VOLTAGE:
		left = "V%d" % _branch
	else:
		var terms: PackedStringArray = PackedStringArray()
		for b: int in _coefficients.size():
			var c: Rational = _coefficients[b]
			if c == null or c.is_zero():
				continue
			if c.numerator == 1 and c.denominator == 1:
				terms.append("I%d" % b)
			elif c.numerator == -1 and c.denominator == 1:
				terms.append("-I%d" % b)
			else:
				terms.append("%s I%d" % [c.to_text(), b])
		left = " + ".join(terms)
	return "%s %s %s" % [left, _RELATION_TEXTS[_relation], _bound.to_text()]


static func _valid_number(value: Rational) -> bool:
	return value != null and value.is_valid()
