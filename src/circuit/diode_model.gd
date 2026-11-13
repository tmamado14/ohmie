class_name DiodeModel
extends PwlDevice
## The piecewise-linear model of a two-terminal diode-like part: a rectifier
## or signal diode, a Schottky diode, an LED (all "diode": only the forward
## drop differs) or a Zener diode. Immutable.
##
## Terminals: 0 anode (a), 1 cathode (k). One branch, 0, from a to k.
## v = V(a) - V(k); i = the current from a to k through the device.
##
## States and their stand-ins and conditions:
##   OFF        open              Vf >= v       (Zener: -Vz <= v <= Vf)
##   ON         source v = Vf     i > 0          (a Zener's "forward" state)
##   BREAKDOWN  source v = -Vz    i < 0          (Zener only)
##
## Boundary rule: the corner points of the characteristic (v = Vf with i = 0,
## and for a Zener v = -Vz with i = 0) belong to OFF only. OFF's conditions are
## closed and the conducting states' conditions are strict, so every point of
## the characteristic belongs to exactly one state. A circuit sitting exactly
## on the threshold therefore has one valid state combination, not two, and is
## never reported as ambiguous.
##
## Typical forward drops: silicon 7/10, Schottky 3/10, red LED 2, green LED 3.
## They are parameters of each part, never fixed inside the solver.

enum State { OFF, ON, BREAKDOWN }

const _TERMINALS: Array[String] = ["anode", "cathode"]
const _DIODE_STATE_NAMES: Array[String] = ["off", "on"]
const _ZENER_STATE_NAMES: Array[String] = ["off", "forward", "breakdown"]

## Read-only forward drop in volts, >= 0.
var forward_drop: Rational:
	get:
		return _forward_drop
## Read-only Zener (breakdown) voltage in volts, > 0; null for a plain diode.
var zener_voltage: Rational:
	get:
		return _zener_voltage

var _forward_drop: Rational = null
var _zener_voltage: Rational = null
var _conditions: Array = []  # state -> Array[PwlCondition]


## A plain diode with forward drop `drop` (>= 0). Returns null (with
## push_error) for a null, invalid or negative drop.
static func diode(drop: Rational) -> DiodeModel:
	if not _check_drop(drop, "DiodeModel.diode"):
		return null
	var model: DiodeModel = DiodeModel.new()
	model._forward_drop = drop
	model._build_conditions()
	return model


## A Zener diode with forward drop `drop` (>= 0) and breakdown voltage
## `breakdown` (> 0). Returns null (with push_error) on bad input.
static func zener(drop: Rational, breakdown: Rational) -> DiodeModel:
	if not _check_drop(drop, "DiodeModel.zener"):
		return null
	if breakdown == null or not breakdown.is_valid() or breakdown.sign() <= 0:
		push_error("DiodeModel.zener: the Zener voltage must be a valid value > 0, got %s." % [
				"null" if breakdown == null else breakdown.to_text()])
		return null
	var model: DiodeModel = DiodeModel.new()
	model._forward_drop = drop
	model._zener_voltage = breakdown
	model._build_conditions()
	return model


func is_zener() -> bool:
	return _zener_voltage != null


func terminal_names() -> Array[String]:
	return _TERMINALS.duplicate()


func branch_count() -> int:
	return 1


func branch_terminals(branch: int) -> Array[int]:
	var terminals: Array[int] = []
	if branch == 0:
		terminals.append(0)
		terminals.append(1)
	return terminals


## 2 for a diode (OFF, ON), 3 for a Zener (OFF, ON, BREAKDOWN).
func state_count() -> int:
	return 3 if is_zener() else 2


## "off", "on" for a diode; "off", "forward", "breakdown" for a Zener.
func state_name(state: int) -> String:
	var names: Array[String] = _ZENER_STATE_NAMES if is_zener() else _DIODE_STATE_NAMES
	if state < 0 or state >= names.size():
		return ""
	return names[state]


func branch_kind(state: int, _branch: int) -> PwlDevice.BranchKind:
	if state == State.ON or (state == State.BREAKDOWN and is_zener()):
		return PwlDevice.BranchKind.VOLTAGE
	return PwlDevice.BranchKind.OPEN


func branch_value(state: int, branch: int) -> Rational:
	if branch != 0:
		return null
	if state == State.ON:
		return _forward_drop
	if state == State.BREAKDOWN and is_zener():
		return _zener_voltage.negate()
	return null


func conditions(state: int) -> Array[PwlCondition]:
	var list: Array[PwlCondition] = []
	if state < 0 or state >= _conditions.size():
		return list
	for condition: PwlCondition in _conditions[state]:
		list.append(condition)
	return list


## DcNetwork.Kind.DIODE or DcNetwork.Kind.ZENER.
func network_kind() -> int:
	return DcNetwork.Kind.ZENER if is_zener() else DcNetwork.Kind.DIODE


## "7/10" for a diode; "7/10 51/10" (forward drop, Zener voltage) for a Zener.
func parameters_text() -> String:
	if is_zener():
		return "%s %s" % [_forward_drop.to_text(), _zener_voltage.to_text()]
	return _forward_drop.to_text()


## Exact equality of kind and parameters.
func same_as(other: DiodeModel) -> bool:
	if other == null or not _forward_drop.equals(other._forward_drop):
		return false
	if is_zener() != other.is_zener():
		return false
	return not is_zener() or _zener_voltage.equals(other._zener_voltage)


func _build_conditions() -> void:
	var zero: Rational = Rational.new(0)
	var off: Array[PwlCondition] = [PwlCondition.voltage(0, PwlCondition.Relation.AT_MOST, _forward_drop)]
	if is_zener():
		off.append(PwlCondition.voltage(0, PwlCondition.Relation.AT_LEAST, _zener_voltage.negate()))
	var on: Array[PwlCondition] = [PwlCondition.current(0, PwlCondition.Relation.ABOVE, zero)]
	_conditions = [off, on]
	if is_zener():
		var breakdown: Array[PwlCondition] = [PwlCondition.current(0, PwlCondition.Relation.BELOW, zero)]
		_conditions.append(breakdown)


static func _check_drop(drop: Rational, op: String) -> bool:
	if drop == null or not drop.is_valid() or drop.sign() < 0:
		push_error("%s: the forward drop must be a valid value >= 0, got %s." % [
				op, "null" if drop == null else drop.to_text()])
		return false
	return true
