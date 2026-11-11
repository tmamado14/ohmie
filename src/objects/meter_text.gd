class_name MeterText
extends RefCounted
## What a meter on the board displays for a solved circuit. Wording only: the
## values come from DcSolution.
##
##   ammeter, voltmeter: "2 A", "-3/2 V"; "SHORT", "???" (indeterminate) or
##     "ERR" when the circuit has no valid solution; "---" for an OPEN
##     voltmeter (its two ends are not connected).
##   ohmmeter: "1 Ω"; "OL" when open; "ERR" when it could not be measured.

const SHORT_TEXT: String = "SHORT"
const INDETERMINATE_TEXT: String = "???"
const ERROR_TEXT: String = "ERR"
const NO_READING_TEXT: String = "---"
const OVER_LIMIT_TEXT: String = "OL"
const UNIT_AMPERE: String = "A"
const UNIT_VOLT: String = "V"
const UNIT_OHM: String = "Ω"


## The display text of meter `meter_id` in `solution`.
static func reading(solution: DcSolution, meter_id: String) -> String:
	if solution == null:
		return ERROR_TEXT
	var kind: int = solution.element_kind(meter_id)
	var state: DcSolution.MeterState = solution.meter_state(meter_id)
	if kind == DcNetwork.Kind.OHMMETER:
		match state:
			DcSolution.MeterState.VALUE:
				return _with_unit(solution.meter_reading(meter_id), UNIT_OHM)
			DcSolution.MeterState.OPEN:
				return OVER_LIMIT_TEXT
		return ERROR_TEXT
	if kind != DcNetwork.Kind.AMMETER and kind != DcNetwork.Kind.VOLTMETER:
		return ERROR_TEXT
	match solution.status:
		DcSolution.Status.SHORT:
			return SHORT_TEXT
		DcSolution.Status.INDETERMINATE:
			return INDETERMINATE_TEXT
		DcSolution.Status.ERROR:
			return ERROR_TEXT
	match state:
		DcSolution.MeterState.VALUE:
			return _with_unit(solution.meter_reading(meter_id),
					UNIT_AMPERE if kind == DcNetwork.Kind.AMMETER else UNIT_VOLT)
		DcSolution.MeterState.OPEN:
			return NO_READING_TEXT
	return ERROR_TEXT


static func _with_unit(value: Rational, unit: String) -> String:
	if value == null:
		return ERROR_TEXT
	return "%s %s" % [value.to_text(), unit]
