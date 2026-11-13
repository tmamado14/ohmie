class_name QuantityText
extends RefCounted
## Exact text for a value with a unit, and the parser for prefixed part values.
## Never rounds and never uses floating point.
##
## Styles:
##   FRACTION     World 1: the plain exact fraction in base units, "3/2 A",
##                "-6 V", "0 Ω". This is Rational.to_text() plus the unit.
##   ENGINEERING  World 2: the SI prefix (µ, m, none, k, M) that puts the
##                magnitude in [1, 1000), then the scaled value as an exact
##                decimal when its denominator has only the factors 2 and 5
##                ("4.3 mA", "0.7 V" is "700 mV", "2.2 kΩ", "-6 V"), otherwise
##                as a fraction ("10/3 mA"). Zero is "0" with the base unit.
##                A magnitude below 1 µ keeps µ (e.g. "0.5 µA"); one of 1000 M
##                or more keeps M ("2000 MΩ").
##
## parse() reads part values: a number Rational.parse accepts ("220", "0.7",
## "1/2", "-6") optionally followed directly by one prefix letter: "u" or "µ"
## (micro), "m", "k", "M" ("1k" = 1000, "4.7k" = 4700, "2.2M" = 2200000).

@warning_ignore_start("integer_division")

enum Style { FRACTION, ENGINEERING }

const MICRO: String = "µ"
const _PREFIX_EXPONENTS: Array[int] = [6, 3, 0, -3, -6]
const _PREFIX_TEXTS: Array[String] = ["M", "k", "", "m", MICRO]
## Accepted by parse(): letter -> power of ten.
const _PARSE_PREFIXES: Dictionary = {"M": 6, "k": 3, "m": -3, "u": -6, MICRO: -6, "μ": -6}
const _DIGITS: String = "0123456789"


## "<number> <unit>" in `style` (see the class description). "ERROR" for a
## null or invalid value.
static func format(value: Rational, unit: String, style: Style = Style.FRACTION) -> String:
	var parts: PackedStringArray = split(value, style)
	if parts.is_empty():
		return "ERROR"
	return "%s %s%s" % [parts[0], parts[1], unit]


## [number text, prefix] as format() would print them ("4.3", "m"). The
## prefix is "" in FRACTION style and for zero. Empty for a null or invalid
## value.
static func split(value: Rational, style: Style = Style.FRACTION) -> PackedStringArray:
	if value == null or not value.is_valid():
		return PackedStringArray()
	if style == Style.FRACTION or value.is_zero():
		return PackedStringArray([value.to_text(), ""])
	var magnitude: Rational = Rational.new(absi(value.numerator), value.denominator)
	var chosen: int = _PREFIX_EXPONENTS.size() - 1
	for i: int in _PREFIX_EXPONENTS.size():
		if magnitude.compare(_power_of_ten(_PREFIX_EXPONENTS[i])) >= 0:
			chosen = i
			break
	var scaled: Rational = _scale(value, -_PREFIX_EXPONENTS[chosen])
	if scaled == null:
		# Not representable after scaling: the exact base-unit fraction.
		return PackedStringArray([value.to_text(), ""])
	return PackedStringArray([decimal_text(scaled), _PREFIX_TEXTS[chosen]])


## A range "low–high unit" with the dash given. In ENGINEERING style both ends
## share the prefix when they would print with the same one ("5–20 mA"),
## otherwise each end has its own ("500 µA–2 mA"). "ERROR" if either end is
## null or invalid.
static func format_range(low: Rational, high: Rational, unit: String, style: Style = Style.FRACTION,
		dash: String = "–") -> String:
	var low_parts: PackedStringArray = split(low, style)
	var high_parts: PackedStringArray = split(high, style)
	if low_parts.is_empty() or high_parts.is_empty():
		return "ERROR"
	if low_parts[1] == high_parts[1] or low.is_zero():
		return "%s%s%s %s%s" % [low_parts[0], dash, high_parts[0], high_parts[1], unit]
	return "%s %s%s%s%s %s%s" % [low_parts[0], low_parts[1], unit, dash, high_parts[0],
			high_parts[1], unit]


## The exact decimal form when the denominator has only the factors 2 and 5
## ("43/10" -> "4.3", "-1/8" -> "-0.125", "7" -> "7"), otherwise to_text()
## ("10/3"). "ERROR" for a null or invalid value.
static func decimal_text(value: Rational) -> String:
	if value == null or not value.is_valid():
		return "ERROR"
	var den: int = value.denominator
	var twos: int = 0
	var fives: int = 0
	while den % 2 == 0:
		den /= 2
		twos += 1
	while den % 5 == 0:
		den /= 5
		fives += 1
	if den != 1:
		return value.to_text()
	var places: int = maxi(twos, fives)
	if places == 0:
		return value.to_text()
	# value = n / (2^twos 5^fives) = n * 2^(places - twos) * 5^(places - fives) / 10^places
	var factor: int = 1
	for i: int in places - twos:
		if not Rational._mul_fits(factor, 2):
			return value.to_text()
		factor *= 2
	for i: int in places - fives:
		if not Rational._mul_fits(factor, 5):
			return value.to_text()
		factor *= 5
	var magnitude: int = absi(value.numerator)
	if not Rational._mul_fits(magnitude, factor):
		return value.to_text()
	var digits: String = str(magnitude * factor)
	while digits.length() <= places:
		digits = "0" + digits
	var whole: String = digits.substr(0, digits.length() - places)
	var fraction: String = digits.substr(digits.length() - places)
	return "%s%s.%s" % ["-" if value.sign() < 0 else "", whole, fraction]


## Parses a part value such as "1k", "4.7k", "220", "0.7", "1/2", "2.2M",
## "100u", "-6". Surrounding whitespace is ignored; there is no space between
## the number and its prefix and no unit. Returns null (with a push_error that
## names the text) for anything else or a value that does not fit in 64 bits.
static func parse(text: String) -> Rational:
	var body: String = text.strip_edges()
	var exponent: int = 0
	if not body.is_empty():
		var last: String = body.substr(body.length() - 1)
		if _PARSE_PREFIXES.has(last):
			exponent = int(_PARSE_PREFIXES[last])
			body = body.substr(0, body.length() - 1)
	if not _is_number_text(body):
		push_error("QuantityText.parse: '%s' is not a value (expected e.g. 220, 0.7, 1/2, 4.7k, 2.2M)." % text)
		return null
	var number: Rational = Rational.parse(body)
	if number == null:
		push_error("QuantityText.parse: '%s' is not a valid value (see the error above)." % text)
		return null
	var value: Rational = _scale(number, exponent)
	if value == null:
		push_error("QuantityText.parse: '%s' does not fit in 64 bits." % text)
		return null
	return value


## value * 10^exponent exactly, or null when it does not fit. Never pushes an
## error.
static func _scale(value: Rational, exponent: int) -> Rational:
	if exponent == 0:
		return value
	var power: int = 1
	for i: int in absi(exponent):
		power *= 10
	var num: int = value.numerator
	var den: int = value.denominator
	if exponent > 0:
		var g: int = Rational._gcd(den, power)
		den /= g
		power /= g
		if not Rational._mul_fits(num, power):
			return null
		return Rational.new(num * power, den)
	var g2: int = Rational._gcd(absi(num), power)
	num /= g2
	power /= g2
	if not Rational._mul_fits(den, power):
		return null
	return Rational.new(num, den * power)


## 10^exponent as a Rational, for |exponent| <= 6.
static func _power_of_ten(exponent: int) -> Rational:
	var power: int = 1
	for i: int in absi(exponent):
		power *= 10
	return Rational.new(power) if exponent >= 0 else Rational.new(1, power)


## True for [-]digits, [-]digits.digits or [-]digits/digits.
static func _is_number_text(body: String) -> bool:
	var s: String = body.substr(1) if body.begins_with("-") else body
	var separator: String = ""
	var digits_before: int = 0
	var digits_after: int = 0
	for i: int in s.length():
		var c: String = s[i]
		if _DIGITS.contains(c):
			if separator.is_empty():
				digits_before += 1
			else:
				digits_after += 1
		elif (c == "." or c == "/") and separator.is_empty():
			separator = c
		else:
			return false
	if digits_before == 0:
		return false
	return separator.is_empty() or digits_after > 0
