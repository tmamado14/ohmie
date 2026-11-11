extends TestCase
## Tests for OhmsLaw: exact I = V / R and R = V / I.


func test_six_volts_across_three_ohms_is_two_amps() -> void:
	assert_rational_eq(OhmsLaw.current(Rational.new(6), Rational.new(3)), "2")


func test_six_volts_across_three_halves_ohm_is_four_amps() -> void:
	assert_rational_eq(OhmsLaw.current(Rational.new(6), Rational.new(3, 2)), "4")


func test_five_volts_across_three_ohms_is_exact_fraction() -> void:
	assert_rational_eq(OhmsLaw.current(Rational.new(5), Rational.new(3)), "5/3")


func test_zero_resistance_gives_null() -> void:
	assert_null(OhmsLaw.current(Rational.new(6), Rational.new(0)))


func test_null_arguments_give_null() -> void:
	assert_null(OhmsLaw.current(null, Rational.new(3)))
	assert_null(OhmsLaw.current(Rational.new(6), null))
	assert_null(OhmsLaw.resistance_for(null, Rational.new(2)))


func test_resistance_for_six_volts_two_amps_is_three_ohms() -> void:
	assert_rational_eq(OhmsLaw.resistance_for(Rational.new(6), Rational.new(2)), "3")


func test_resistance_for_zero_current_gives_null() -> void:
	assert_null(OhmsLaw.resistance_for(Rational.new(6), Rational.new(0)))
