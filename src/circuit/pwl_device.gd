class_name PwlDevice
extends RefCounted
## Base class of every piecewise-linear device model: diodes and Zeners now,
## transistors and op-amps later. A model is immutable shared data; the same
## instance may sit in many elements of many networks.
##
## The protocol, which PwlSolver drives without knowing the device type:
##   - The device has terminals (terminal_names) and branches. A branch runs
##     from one terminal to another (branch_terminals) and is the unit the
##     linear solver sees.
##   - The device is always in exactly one of state_count() states.
##   - In each state every branch is replaced by a linear stand-in:
##     branch_kind(state, branch) and branch_value(state, branch).
##       OPEN     no current; its voltage is still measured.
##       VOLTAGE  an ideal source: V(from) - V(to) = branch_value.
##     Later device types add kinds here (a current-controlled current source
##     for transistors, a nullator/norator pair for op-amps); the solver's
##     state search does not change, only the linear stand-ins it can build.
##   - conditions(state) lists the PwlConditions (on branch voltages and branch
##     currents) that must all hold for the state to be the right one.
##
## Subclasses override every method below. The base implementations push an
## error and return an empty or null value.

enum BranchKind { OPEN, VOLTAGE }


## Terminal names in order, e.g. ["anode", "cathode"].
func terminal_names() -> Array[String]:
	push_error("PwlDevice.terminal_names: not implemented by this device model.")
	var none: Array[String] = []
	return none


func terminal_count() -> int:
	return terminal_names().size()


func branch_count() -> int:
	push_error("PwlDevice.branch_count: not implemented by this device model.")
	return 0


## [from terminal index, to terminal index] of `branch`; empty when out of range.
func branch_terminals(_branch: int) -> Array[int]:
	push_error("PwlDevice.branch_terminals: not implemented by this device model.")
	var none: Array[int] = []
	return none


func state_count() -> int:
	push_error("PwlDevice.state_count: not implemented by this device model.")
	return 0


## A lower-case name for `state`, e.g. "off"; "" when out of range.
func state_name(_state: int) -> String:
	push_error("PwlDevice.state_name: not implemented by this device model.")
	return ""


## The linear stand-in of `branch` in `state`.
func branch_kind(_state: int, _branch: int) -> BranchKind:
	push_error("PwlDevice.branch_kind: not implemented by this device model.")
	return BranchKind.OPEN


## The stand-in's value (volts for VOLTAGE); null for OPEN or out of range.
func branch_value(_state: int, _branch: int) -> Rational:
	push_error("PwlDevice.branch_value: not implemented by this device model.")
	return null


## Every condition that must hold in `state`; empty when out of range.
func conditions(_state: int) -> Array[PwlCondition]:
	push_error("PwlDevice.conditions: not implemented by this device model.")
	var none: Array[PwlCondition] = []
	return none


## The DcNetwork.Kind of elements holding this model.
func network_kind() -> int:
	push_error("PwlDevice.network_kind: not implemented by this device model.")
	return -1


## The parameter values as text, e.g. "7/10" or "7/10 51/10".
func parameters_text() -> String:
	push_error("PwlDevice.parameters_text: not implemented by this device model.")
	return ""
