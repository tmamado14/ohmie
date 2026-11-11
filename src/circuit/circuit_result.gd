class_name CircuitResult
extends RefCounted
## The outcome of CircuitSolver.solve().
##
## OK: value holds the exact equivalent resistance.
## OPEN: no current can flow between the terminals.
## UNSUPPORTED: the network is not series-parallel (for example a bridge).
## ERROR: the input was invalid or a value overflowed 64 bits; error_message
## says why. Never shown as a number, so it can never be mistaken for a solution.

enum Status { OK, OPEN, UNSUPPORTED, ERROR }

var status: Status = Status.OPEN
var value: Rational = null  # set only when status is OK
var steps: Array[ReductionStep] = []
var error_message: String = ""


## Readout text without the unit: "1", "3/2", "0", "OPEN", "???" or "ERROR".
func to_text() -> String:
	match status:
		Status.OK:
			return value.to_text()
		Status.OPEN:
			return "OPEN"
		Status.UNSUPPORTED:
			return "???"
	return "ERROR"


## True exactly when status is OK and value equals target.
func matches(target: Rational) -> bool:
	return status == Status.OK and value != null and value.equals(target)
