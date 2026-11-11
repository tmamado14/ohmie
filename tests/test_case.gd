class_name TestCase
extends RefCounted
## Base class for headless tests. Methods named test_* are run by
## tests/run_tests.gd. Assertions record failures instead of stopping the test.
##
## Engine errors (push_error) raised during a test fail it, unless the test
## claims them with assert_error_pushed(). Script runtime errors always fail it.
## A test that makes no assertions fails.

var _failures: Array[String] = []
var _assertions: int = 0
var _engine_errors: Array[String] = []


# --- assertions ----------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	_assertions += 1
	if not condition:
		_fail_with("expected true", message)


func assert_false(condition: bool, message: String = "") -> void:
	_assertions += 1
	if condition:
		_fail_with("expected false", message)


## Equality for values of the same type (arrays and dictionaries compare by content).
func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail_with("expected <%s> but got <%s>" % [_describe(expected), _describe(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_assertions += 1
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		_fail_with("expected anything but <%s>" % _describe(unexpected), message)


func assert_null(value: Variant, message: String = "") -> void:
	_assertions += 1
	if value != null:
		_fail_with("expected null but got <%s>" % _describe(value), message)


func assert_not_null(value: Variant, message: String = "") -> void:
	_assertions += 1
	if value == null:
		_fail_with("expected a value but got null", message)


## Passes if actual is a valid Rational whose to_text() equals expected_text.
func assert_rational_eq(actual: Rational, expected_text: String, message: String = "") -> void:
	_assertions += 1
	if actual == null:
		_fail_with("expected Rational %s but got null" % expected_text, message)
	elif not actual.is_valid():
		_fail_with("expected Rational %s but got an invalid Rational" % expected_text, message)
	elif actual.to_text() != expected_text:
		_fail_with("expected Rational %s but got %s" % [expected_text, actual.to_text()], message)


## Passes if an engine error containing `fragment` was raised earlier in this
## test, and claims it so it does not fail the test.
func assert_error_pushed(fragment: String, message: String = "") -> void:
	_assertions += 1
	for i: int in _engine_errors.size():
		if _engine_errors[i].contains(fragment):
			_engine_errors.remove_at(i)
			return
	_fail_with("expected an engine error containing '%s'" % fragment, message)


func fail(message: String) -> void:
	_assertions += 1
	_fail_with("failed", message)


# --- used by the runner ----------------------------------------------------------

func _begin_test() -> void:
	_failures.clear()
	_engine_errors.clear()
	_assertions = 0


func _record_engine_error(text: String) -> void:
	_engine_errors.append(text)


func _record_script_error(text: String) -> void:
	_failures.append("script error: %s" % text)


## Returns every failure of the test that just ran.
func _end_test() -> Array[String]:
	var result: Array[String] = _failures.duplicate()
	for text: String in _engine_errors:
		result.append("unexpected engine error: %s" % text)
	if _assertions == 0 and result.is_empty():
		result.append("the test made no assertions")
	return result


func _fail_with(reason: String, message: String) -> void:
	if message.is_empty():
		_failures.append(reason)
	else:
		_failures.append("%s: %s" % [message, reason])


func _describe(value: Variant) -> String:
	if value is Rational:
		return "Rational %s" % (value as Rational).to_text()
	return var_to_str(value)
