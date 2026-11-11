extends SceneTree
## Headless test runner.
##
## Runs every method named test_* in every res://tests/test_*.gd (except
## test_case.gd), prints one PASS/FAIL line per test and a summary, then exits
## with 0 if everything passed and 1 otherwise. A test script that fails to
## load or does not extend TestCase counts as a failure.
##
## Usage: godot --headless --path . --script res://tests/run_tests.gd

const TESTS_DIR: String = "res://tests/"
const SOURCE_DIR: String = "res://src"
const BASE_SCRIPT_FILE: String = "test_case.gd"
const EXIT_PASS: int = 0
const EXIT_FAIL: int = 1


## Forwards engine errors raised during a test to that test.
class _CaptureLogger:
	extends Logger
	var target: TestCase = null
	var load_errors: Array[String] = []
	var capture_load_errors: bool = false
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text: String = rationale if not rationale.is_empty() else code
		if not rationale.is_empty() and not code.is_empty() and code != rationale:
			text = "%s (%s)" % [rationale, code]
		var location: String = "%s:%d %s" % [file, line, function]
		_mutex.lock()
		if capture_load_errors:
			load_errors.append("%s [%s]" % [text, location])
		elif target != null:
			if error_type == ERROR_TYPE_SCRIPT:
				target._record_script_error("%s [%s]" % [text, location])
			else:
				target._record_engine_error(text)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var logger: _CaptureLogger = _CaptureLogger.new()
	OS.add_logger(logger)
	var exit_code: int = _run_all(logger)
	OS.remove_logger(logger)
	quit(exit_code)


func _run_all(logger: _CaptureLogger) -> int:
	var passed: int = 0
	var failed: int = 0

	# A broken source script makes every test that uses it meaningless (calls
	# on it fail and can loop), so stop before running anything.
	var broken: Array[String] = _find_broken_scripts(SOURCE_DIR, logger)
	if not broken.is_empty():
		for line: String in broken:
			print("FAIL  %s" % line)
		print("")
		print("Summary: %d source script(s) failed to compile; no tests were run" % broken.size())
		print("TESTS FAILED")
		return EXIT_FAIL

	var files: Array[String] = _find_test_files()
	if files.is_empty():
		print("FAIL  no test files found in %s" % TESTS_DIR)
		return EXIT_FAIL

	for file: String in files:
		var path: String = TESTS_DIR + file
		logger.load_errors.clear()
		logger.capture_load_errors = true
		var script: GDScript = load(path) as GDScript
		var instance: Object = null
		if script != null and script.can_instantiate():
			instance = script.new()
		logger.capture_load_errors = false

		var case: TestCase = instance as TestCase
		if case == null or not logger.load_errors.is_empty():
			var reason: String = "could not load or does not extend TestCase"
			if not logger.load_errors.is_empty():
				reason += ": " + "; ".join(logger.load_errors)
			print("FAIL  %s : %s" % [file, reason])
			failed += 1
			continue

		var methods: Array[String] = []
		for info: Dictionary in case.get_method_list():
			var method_name: String = info["name"]
			if method_name.begins_with("test_") and not methods.has(method_name):
				methods.append(method_name)
		methods.sort()
		if methods.is_empty():
			print("FAIL  %s : contains no test_* methods" % file)
			failed += 1
			continue

		for method_name: String in methods:
			case._begin_test()
			logger.target = case
			case.call(method_name)
			logger.target = null
			var failures: Array[String] = case._end_test()
			if failures.is_empty():
				print("PASS  %s :: %s" % [file, method_name])
				passed += 1
			else:
				print("FAIL  %s :: %s" % [file, method_name])
				for failure: String in failures:
					print("        %s" % failure)
				failed += 1

	print("")
	print("Summary: %d passed, %d failed, %d total" % [passed, failed, passed + failed])
	if failed == 0:
		print("ALL TESTS PASSED")
		return EXIT_PASS
	print("TESTS FAILED")
	return EXIT_FAIL


## Loads every .gd file under `dir` (recursively) and returns one line for each
## that does not compile.
func _find_broken_scripts(dir: String, logger: _CaptureLogger) -> Array[String]:
	var broken: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir):
		broken.append_array(_find_broken_scripts(dir.path_join(sub), logger))
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		var path: String = dir.path_join(file)
		logger.load_errors.clear()
		logger.capture_load_errors = true
		var script: GDScript = load(path) as GDScript
		# can_instantiate() is not used here: a valid @abstract class reports false.
		var compiles: bool = script != null
		logger.capture_load_errors = false
		if not compiles or not logger.load_errors.is_empty():
			broken.append("%s : does not compile: %s" % [path, "; ".join(logger.load_errors)])
	return broken


func _find_test_files() -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(TESTS_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != BASE_SCRIPT_FILE:
			files.append(file)
	files.sort()
	return files
