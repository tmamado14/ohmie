class_name Rational
extends RefCounted
## An immutable exact fraction of two 64-bit integers.
##
## Invariants of every valid instance: the fraction is fully reduced, the
## denominator is positive, and zero is stored as 0/1. Values are never
## approximated. Every operation returns a new instance.
##
## Overflow policy: no operation silently wraps. Products are cross-reduced by
## their greatest common divisors before multiplying, so many results with
## large intermediate values still fit. If a result (or an unavoidable
## intermediate value) does not fit in a signed 64-bit integer, the operation
## calls push_error and returns null. The value -2^63 is never used as a
## numerator or denominator, so negation is always safe.
##
## Invalid construction (zero denominator, or -2^63 as an input) calls
## push_error and produces an instance whose is_valid() is false. Every
## operation on an invalid instance calls push_error and returns null. Use
## Rational.parse() or Rational.create() to get null instead of an invalid
## instance.

@warning_ignore_start("integer_division")

## Largest magnitude allowed for a numerator or denominator.
const INT_MAX: int = 9223372036854775807
## The one 64-bit value whose negation overflows. Always rejected.
const INT_MIN: int = -9223372036854775807 - 1

const _DIGITS: String = "0123456789"

## Read-only numerator (carries the sign).
var numerator: int:
	get:
		return _num
	set(_value):
		push_error("Rational is immutable: numerator cannot be assigned.")

## Read-only denominator, always > 0.
var denominator: int:
	get:
		return _den
	set(_value):
		push_error("Rational is immutable: denominator cannot be assigned.")

var _num: int = 0
var _den: int = 1
var _valid: bool = true


func _init(num: int, den: int = 1) -> void:
	if den == 0:
		push_error("Rational: zero denominator in %d/0." % num)
		_valid = false
		return
	if num == INT_MIN or den == INT_MIN:
		push_error("Rational: -2^63 is outside the supported range.")
		_valid = false
		return
	if den < 0:
		num = -num
		den = -den
	var g: int = _gcd(absi(num), den)
	_num = num / g
	_den = den / g


## Returns n/1.
static func from_int(n: int) -> Rational:
	return Rational.new(n, 1)


## Returns num/den, or null (with push_error) if that is not a valid value.
static func create(num: int, den: int = 1) -> Rational:
	if den == 0:
		push_error("Rational.create: zero denominator in %d/0." % num)
		return null
	if num == INT_MIN or den == INT_MIN:
		push_error("Rational.create: -2^63 is outside the supported range.")
		return null
	return Rational.new(num, den)


## Parses "2", "-2", "1/2", "-3/4", "0.5", "-1.25" exactly.
## Surrounding whitespace is ignored. A sign is allowed only at the very start.
## Returns null (with push_error, unless `quiet`) for anything else, for a zero
## denominator, or for a value that does not fit in 64 bits.
static func parse(text: String, quiet: bool = false) -> Rational:
	var s: String = text.strip_edges()
	var negative: bool = false
	if s.begins_with("-"):
		negative = true
		s = s.substr(1)
	var result: Rational = null
	var slash: int = s.find("/")
	if slash >= 0:
		result = _parse_fraction_body(s.substr(0, slash), s.substr(slash + 1), text, quiet)
	elif s.find(".") >= 0:
		result = _parse_decimal_body(s, text, quiet)
	else:
		var n: Rational = _parse_digits(s, text, quiet)
		result = n
	if result == null:
		return null
	if negative:
		return Rational.new(-result._num, result._den)
	return result


## Returns true unless construction failed.
func is_valid() -> bool:
	return _valid


func add(other: Rational) -> Rational:
	if not _check_operands(other, "add"):
		return null
	var g: int = _gcd(_den, other._den)
	var scale_self: int = other._den / g
	var scale_other: int = _den / g
	if not (_mul_fits(_num, scale_self) and _mul_fits(other._num, scale_other)
			and _mul_fits(_den, scale_self)):
		return _overflow("add", other)
	var left: int = _num * scale_self
	var right: int = other._num * scale_other
	if not _add_fits(left, right):
		return _overflow("add", other)
	return Rational.new(left + right, _den * scale_self)


func sub(other: Rational) -> Rational:
	if not _check_operands(other, "sub"):
		return null
	return add(other.negate())


func mul(other: Rational) -> Rational:
	if not _check_operands(other, "mul"):
		return null
	# Cross-reduce so the products are as small as possible.
	var g1: int = _gcd(absi(_num), other._den)
	var g2: int = _gcd(absi(other._num), _den)
	var n1: int = _num / g1
	var d2: int = other._den / g1
	var n2: int = other._num / g2
	var d1: int = _den / g2
	if not (_mul_fits(n1, n2) and _mul_fits(d1, d2)):
		return _overflow("mul", other)
	return Rational.new(n1 * n2, d1 * d2)


## Division by zero calls push_error and returns null.
func div(other: Rational) -> Rational:
	if not _check_operands(other, "div"):
		return null
	if other.is_zero():
		push_error("Rational.div: division by zero (%s / 0)." % to_text())
		return null
	return mul(other.reciprocal())


## The reciprocal of zero calls push_error and returns null.
func reciprocal() -> Rational:
	if not _check_self("reciprocal"):
		return null
	if _num == 0:
		push_error("Rational.reciprocal: zero has no reciprocal.")
		return null
	return Rational.new(_den, _num)


func negate() -> Rational:
	if not _check_self("negate"):
		return null
	return Rational.new(-_num, _den)


## Exact equality. False if either side is null or invalid.
func equals(other: Rational) -> bool:
	if other == null or not _valid or not other._valid:
		return false
	return _num == other._num and _den == other._den


## Returns -1, 0 or 1. Never overflows. An invalid operand calls push_error
## and returns 0.
func compare(other: Rational) -> int:
	if not _check_operands(other, "compare"):
		return 0
	var sign_self: int = signi(_num)
	var sign_other: int = signi(other._num)
	if sign_self != sign_other:
		return -1 if sign_self < sign_other else 1
	if sign_self == 0:
		return 0
	if sign_self > 0:
		return _compare_non_negative(_num, _den, other._num, other._den)
	# Both negative: x < y exactly when -y < -x.
	return _compare_non_negative(-other._num, other._den, -_num, _den)


## Returns -1, 0 or 1.
func sign() -> int:
	return signi(_num)


func is_zero() -> bool:
	return _valid and _num == 0


func is_integer() -> bool:
	return _valid and _den == 1


## "2", "3/2", "-3/4", "0". An invalid instance gives "INVALID".
func to_text() -> String:
	if not _valid:
		return "INVALID"
	if _den == 1:
		return str(_num)
	return "%d/%d" % [_num, _den]


func _to_string() -> String:
	return to_text()


# --- private helpers ---------------------------------------------------------

func _check_self(op: String) -> bool:
	if not _valid:
		push_error("Rational.%s: called on an invalid Rational." % op)
		return false
	return true


func _check_operands(other: Rational, op: String) -> bool:
	if not _check_self(op):
		return false
	if other == null:
		push_error("Rational.%s: the other operand is null." % op)
		return false
	if not other._valid:
		push_error("Rational.%s: the other operand is an invalid Rational." % op)
		return false
	return true


func _overflow(op: String, other: Rational) -> Rational:
	push_error("Rational.%s: result of %s and %s does not fit in 64 bits." % [
			op, to_text(), other.to_text()])
	return null


## Greatest common divisor of two non-negative integers. gcd(0, 0) is 1 so
## that dividing by it is always safe.
static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = a % b
		a = b
		b = t
	return a if a != 0 else 1


## True if a * b fits, given both operands are within +-INT_MAX.
static func _mul_fits(a: int, b: int) -> bool:
	if a == 0 or b == 0:
		return true
	return absi(a) <= INT_MAX / absi(b)


## True if a + b stays within +-INT_MAX, given both operands do.
static func _add_fits(a: int, b: int) -> bool:
	if b > 0:
		return a <= INT_MAX - b
	return a >= -INT_MAX - b


## Compares a/b with c/d for a, c >= 0 and b, d > 0, by comparing continued
## fraction expansions. Uses only division and remainder, so it cannot overflow.
static func _compare_non_negative(a: int, b: int, c: int, d: int) -> int:
	while true:
		var q1: int = a / b
		var r1: int = a % b
		var q2: int = c / d
		var r2: int = c % d
		if q1 != q2:
			return -1 if q1 < q2 else 1
		if r1 == 0 and r2 == 0:
			return 0
		if r1 == 0:
			return -1
		if r2 == 0:
			return 1
		# r1/b < r2/d exactly when d/r2 < b/r1.
		var next_a: int = d
		var next_b: int = r2
		var next_c: int = b
		var next_d: int = r1
		a = next_a
		b = next_b
		c = next_c
		d = next_d
	return 0


## Parses a non-empty run of decimal digits. Returns null on bad text or overflow.
static func _parse_digits(digits: String, original: String, quiet: bool) -> Rational:
	var value: int = _digits_to_int(digits, original, quiet)
	if value < 0:
		return null
	return Rational.new(value, 1)


## Returns the value of a non-empty run of digits, or -1 (with push_error
## unless `quiet`).
static func _digits_to_int(digits: String, original: String, quiet: bool) -> int:
	if digits.is_empty():
		_parse_error("Rational.parse: '%s' is not a number (expected 2, -3/4 or 0.5)." % original, quiet)
		return -1
	var value: int = 0
	for i: int in digits.length():
		var digit: int = _DIGITS.find(digits[i])
		if digit < 0:
			_parse_error("Rational.parse: '%s' is not a number (expected 2, -3/4 or 0.5)." % original, quiet)
			return -1
		if value > (INT_MAX - digit) / 10:
			_parse_error("Rational.parse: '%s' does not fit in 64 bits." % original, quiet)
			return -1
		value = value * 10 + digit
	return value


static func _parse_fraction_body(num_text: String, den_text: String, original: String,
		quiet: bool) -> Rational:
	var n: int = _digits_to_int(num_text, original, quiet)
	if n < 0:
		return null
	var d: int = _digits_to_int(den_text, original, quiet)
	if d < 0:
		return null
	if d == 0:
		_parse_error("Rational.parse: '%s' has a zero denominator." % original, quiet)
		return null
	return Rational.new(n, d)


static func _parse_decimal_body(text: String, original: String, quiet: bool) -> Rational:
	var dot: int = text.find(".")
	var int_text: String = text.substr(0, dot)
	var frac_text: String = text.substr(dot + 1)
	if int_text.is_empty() or frac_text.is_empty():
		_parse_error("Rational.parse: '%s' needs digits on both sides of the point." % original, quiet)
		return null
	# Trailing zeros after the point do not change the value.
	while frac_text.length() > 1 and frac_text.ends_with("0"):
		frac_text = frac_text.substr(0, frac_text.length() - 1)
	var whole: int = _digits_to_int(int_text, original, quiet)
	if whole < 0:
		return null
	var frac: int = _digits_to_int(frac_text, original, quiet)
	if frac < 0:
		return null
	var scale: int = 1
	for i: int in frac_text.length():
		if not _mul_fits(scale, 10):
			_parse_error("Rational.parse: '%s' has too many decimal places." % original, quiet)
			return null
		scale *= 10
	if not _mul_fits(whole, scale) or not _add_fits(whole * scale, frac):
		_parse_error("Rational.parse: '%s' does not fit in 64 bits." % original, quiet)
		return null
	return Rational.new(whole * scale + frac, scale)


static func _parse_error(message: String, quiet: bool) -> void:
	if not quiet:
		push_error(message)
