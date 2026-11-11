extends TestCase
## Tests for Rational.

const MAX: int = Rational.INT_MAX
const TWO_62: int = 4611686018427387904
const TWO_61: int = 2305843009213693952


func _r(text: String) -> Rational:
	return Rational.parse(text)


# --- construction ----------------------------------------------------------------

func test_new_reduces() -> void:
	assert_rational_eq(Rational.new(6, 4), "3/2")
	assert_rational_eq(Rational.new(10, 5), "2")
	assert_rational_eq(Rational.new(7), "7")
	var r: Rational = Rational.new(6, 4)
	assert_eq(r.numerator, 3)
	assert_eq(r.denominator, 2)


func test_new_normalises_sign() -> void:
	assert_rational_eq(Rational.new(1, -2), "-1/2")
	assert_rational_eq(Rational.new(-1, -2), "1/2")
	assert_rational_eq(Rational.new(-6, 4), "-3/2")
	assert_eq(Rational.new(3, -9).denominator, 3)


func test_zero_is_stored_as_zero_over_one() -> void:
	var z: Rational = Rational.new(0, -5)
	assert_eq(z.numerator, 0)
	assert_eq(z.denominator, 1)
	assert_rational_eq(z, "0")
	assert_true(z.is_zero())
	assert_true(z.is_integer())


func test_new_zero_denominator_is_invalid() -> void:
	var r: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_false(r.is_valid())
	assert_eq(r.to_text(), "INVALID")
	assert_false(r.equals(Rational.new(0)))


func test_new_rejects_int64_min() -> void:
	var r: Rational = Rational.new(Rational.INT_MIN, 1)
	assert_error_pushed("outside the supported range")
	assert_false(r.is_valid())
	var r2: Rational = Rational.new(1, Rational.INT_MIN)
	assert_error_pushed("outside the supported range")
	assert_false(r2.is_valid())


func test_operations_on_invalid_return_null() -> void:
	var bad: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_null(bad.add(Rational.new(1)))
	assert_error_pushed("invalid Rational")
	assert_null(Rational.new(1).mul(bad))
	assert_error_pushed("invalid Rational")
	assert_null(Rational.new(1).add(null))
	assert_error_pushed("null")
	assert_eq(Rational.new(1).compare(null), 0)
	assert_error_pushed("null")


func test_create_returns_null_when_invalid() -> void:
	assert_rational_eq(Rational.create(4, 6), "2/3")
	assert_null(Rational.create(4, 0))
	assert_error_pushed("zero denominator")
	assert_null(Rational.create(Rational.INT_MIN, 3))
	assert_error_pushed("outside the supported range")


func test_from_int() -> void:
	assert_rational_eq(Rational.from_int(5), "5")
	assert_rational_eq(Rational.from_int(-3), "-3")
	assert_rational_eq(Rational.from_int(0), "0")


func test_is_immutable() -> void:
	var r: Rational = Rational.new(1, 2)
	r.numerator = 5
	assert_error_pushed("immutable")
	r.denominator = 7
	assert_error_pushed("immutable")
	assert_rational_eq(r, "1/2")
	var sum: Rational = r.add(Rational.new(1, 2))
	assert_rational_eq(sum, "1")
	assert_rational_eq(r, "1/2", "operands are not changed")


# --- parse ----------------------------------------------------------------

func test_parse_integers() -> void:
	assert_rational_eq(_r("2"), "2")
	assert_rational_eq(_r("0"), "0")
	assert_rational_eq(_r("-7"), "-7")
	assert_rational_eq(_r("007"), "7")
	assert_rational_eq(_r("  3 "), "3")
	assert_rational_eq(_r("9223372036854775807"), "9223372036854775807")


func test_parse_fractions() -> void:
	assert_rational_eq(_r("1/2"), "1/2")
	assert_rational_eq(_r("-3/4"), "-3/4")
	assert_rational_eq(_r("4/6"), "2/3")
	assert_rational_eq(_r("10/5"), "2")
	assert_rational_eq(_r("0/9"), "0")


func test_parse_decimals_exactly() -> void:
	assert_rational_eq(_r("0.5"), "1/2")
	assert_rational_eq(_r("1.25"), "5/4")
	assert_rational_eq(_r("-0.75"), "-3/4")
	assert_rational_eq(_r("2.0"), "2")
	assert_rational_eq(_r("0.1"), "1/10")
	assert_rational_eq(_r("1.50000000000000000000000000"), "3/2", "trailing zeros")
	assert_rational_eq(_r("0.333"), "333/1000")


func test_parse_decimal_equals_fraction() -> void:
	assert_true(_r("0.5").equals(_r("1/2")))
	assert_true(_r("1.25").equals(_r("5/4")))


func test_parse_invalid_forms_return_null() -> void:
	var bad: Array[String] = ["", "abc", "1/2/3", "1.2.3", "1/", "/2", ".5", "5.",
			"1/-2", "--1", "+1", "1e3", "1 / 2", "0x10", "-", "1/0.5"]
	for text: String in bad:
		assert_null(Rational.parse(text), "parse('%s')" % text)
		assert_error_pushed("Rational.parse", "parse('%s') explains the error" % text)


func test_parse_zero_denominator_returns_null() -> void:
	assert_null(_r("1/0"))
	assert_error_pushed("zero denominator")
	assert_null(_r("0/0"))
	assert_error_pushed("zero denominator")


func test_parse_overflow_returns_null() -> void:
	assert_null(_r("9223372036854775808"))
	assert_error_pushed("does not fit")
	assert_null(_r("1/99999999999999999999"))
	assert_error_pushed("does not fit")
	assert_null(_r("0.0000000000000000000001"))
	assert_error_pushed("too many decimal places")
	assert_null(_r("922337203685477580.8"))
	assert_error_pushed("does not fit")


# --- arithmetic ----------------------------------------------------------------

func test_one_third_plus_two_thirds_is_exactly_one() -> void:
	var sum: Rational = _r("1/3").add(_r("2/3"))
	assert_rational_eq(sum, "1")
	assert_true(sum.equals(Rational.from_int(1)))
	assert_true(sum.is_integer())


func test_add() -> void:
	assert_rational_eq(_r("1/2").add(_r("1/3")), "5/6")
	assert_rational_eq(_r("1/2").add(_r("-1/2")), "0")
	assert_rational_eq(_r("-3/4").add(_r("1/4")), "-1/2")
	assert_rational_eq(_r("2").add(_r("3")), "5")
	assert_rational_eq(_r("1/6").add(_r("1/10")), "4/15")


func test_sub() -> void:
	assert_rational_eq(_r("1/2").sub(_r("1/3")), "1/6")
	assert_rational_eq(_r("1/3").sub(_r("1/2")), "-1/6")
	assert_rational_eq(_r("5").sub(_r("5")), "0")
	assert_rational_eq(_r("-1/2").sub(_r("-1/2")), "0")


func test_mul() -> void:
	assert_rational_eq(_r("2/3").mul(_r("3/4")), "1/2")
	assert_rational_eq(_r("-2/3").mul(_r("3/4")), "-1/2")
	assert_rational_eq(_r("-2").mul(_r("-1/2")), "1")
	assert_rational_eq(_r("0").mul(_r("7/9")), "0")


func test_div() -> void:
	assert_rational_eq(_r("1/2").div(_r("1/4")), "2")
	assert_rational_eq(_r("3").div(_r("-6")), "-1/2")
	assert_rational_eq(_r("-2/3").div(_r("-4/9")), "3/2")
	assert_rational_eq(_r("0").div(_r("5")), "0")


func test_div_by_zero_returns_null() -> void:
	assert_null(_r("1").div(_r("0")))
	assert_error_pushed("division by zero")


func test_reciprocal() -> void:
	assert_rational_eq(_r("2/3").reciprocal(), "3/2")
	assert_rational_eq(_r("-1/4").reciprocal(), "-4")
	assert_rational_eq(_r("5").reciprocal(), "1/5")
	assert_null(_r("0").reciprocal())
	assert_error_pushed("zero has no reciprocal")


func test_negate_and_sign() -> void:
	assert_rational_eq(_r("1/2").negate(), "-1/2")
	assert_rational_eq(_r("-3").negate(), "3")
	assert_rational_eq(_r("0").negate(), "0")
	assert_eq(_r("2/7").sign(), 1)
	assert_eq(_r("-2/7").sign(), -1)
	assert_eq(_r("0").sign(), 0)


func test_equals() -> void:
	assert_true(_r("2/4").equals(_r("1/2")))
	assert_false(_r("1/2").equals(_r("-1/2")))
	assert_false(_r("1/2").equals(null))


func test_compare() -> void:
	assert_eq(_r("1/2").compare(_r("1/3")), 1)
	assert_eq(_r("1/3").compare(_r("1/2")), -1)
	assert_eq(_r("2/4").compare(_r("1/2")), 0)
	assert_eq(_r("-1/2").compare(_r("1/3")), -1)
	assert_eq(_r("-1/2").compare(_r("-1/3")), -1)
	assert_eq(_r("-1/3").compare(_r("-1/2")), 1)
	assert_eq(_r("0").compare(_r("-1/9")), 1)
	assert_eq(_r("0").compare(_r("0")), 0)
	assert_eq(_r("3").compare(_r("3/1")), 0)
	assert_eq(_r("7/2").compare(_r("3")), 1)


func test_compare_large_values_without_overflow() -> void:
	# Cross-multiplying these would overflow; compare must still be exact.
	var a: Rational = Rational.new(MAX - 1, MAX)
	var b: Rational = Rational.new(MAX - 2, MAX - 1)
	assert_eq(a.compare(b), 1)
	assert_eq(b.compare(a), -1)
	assert_eq(a.negate().compare(b.negate()), -1)
	assert_eq(Rational.new(MAX).compare(Rational.new(MAX - 1)), 1)


func test_is_zero_and_is_integer() -> void:
	assert_true(_r("0").is_zero())
	assert_false(_r("1/2").is_zero())
	assert_true(_r("4/2").is_integer())
	assert_false(_r("3/2").is_integer())
	assert_true(_r("-5").is_integer())


func test_to_text() -> void:
	assert_eq(_r("2").to_text(), "2")
	assert_eq(_r("3/2").to_text(), "3/2")
	assert_eq(_r("0").to_text(), "0")
	assert_eq(_r("-3/2").to_text(), "-3/2")
	assert_eq(str(_r("3/2")), "3/2")


# --- overflow --------------------------------------------------------------------

func test_add_overflow_returns_null() -> void:
	assert_null(Rational.new(MAX).add(Rational.new(1)))
	assert_error_pushed("does not fit in 64 bits")
	assert_null(Rational.new(-MAX).sub(Rational.new(1)))
	assert_error_pushed("does not fit in 64 bits")
	# Denominators with no common factor whose product is too large.
	assert_null(Rational.new(1, MAX).add(Rational.new(1, MAX - 1)))
	assert_error_pushed("does not fit in 64 bits")


func test_mul_overflow_returns_null() -> void:
	assert_null(Rational.new(TWO_62).mul(Rational.new(2)))
	assert_error_pushed("does not fit in 64 bits")
	assert_null(Rational.new(1, TWO_62).mul(Rational.new(1, 3)))
	assert_error_pushed("does not fit in 64 bits")
	assert_null(Rational.new(1, 3).div(Rational.new(TWO_62)))
	assert_error_pushed("does not fit in 64 bits")


func test_largest_values_still_work() -> void:
	assert_rational_eq(Rational.new(MAX).sub(Rational.new(MAX)), "0")
	assert_rational_eq(Rational.new(-MAX).add(Rational.new(MAX)), "0")
	assert_rational_eq(Rational.new(MAX).negate(), "-9223372036854775807")
	assert_rational_eq(Rational.new(1, MAX).reciprocal(), "9223372036854775807")


func test_mul_fits_only_because_of_cross_reduction() -> void:
	# Naively 2^62 * 3 and 3 * 2^61 both overflow; cross-reducing gives 2/1 * 1/1.
	var a: Rational = Rational.new(TWO_62, 3)
	var b: Rational = Rational.new(3, TWO_61)
	assert_rational_eq(a.mul(b), "2")
	# The same through div.
	assert_rational_eq(a.div(Rational.new(TWO_61, 3)), "2")


func test_add_fits_only_because_of_common_denominator() -> void:
	# Naively the denominator 2^62 * 2^62 overflows; using the lcm it does not.
	var tiny: Rational = Rational.new(1, TWO_62)
	assert_rational_eq(tiny.add(tiny), "1/%d" % TWO_61)
	var a: Rational = Rational.new(1, TWO_61)
	assert_rational_eq(a.sub(tiny), "1/%d" % TWO_62)
