class_name DcSolution
extends RefCounted
## The outcome of DcSolver.solve(): every exact voltage, current, power and
## meter reading of one DC network.
##
## Status:
##   OK             the circuit has exactly one solution.
##   SHORT          the equations contradict each other: an ideal source (or
##                  ammeter) loop whose voltages do not sum to zero, e.g. a
##                  battery shorted by a wire or by an ammeter, or directly
##                  across a forward diode.
##   INDETERMINATE  consistent, but some current is not determined, e.g. two
##                  ammeters in parallel or two equal batteries in parallel.
##   ERROR          a value overflowed 64 bits or the network was invalid;
##                  error_message says why. Never shown as a number.
## With devices, PwlSolver documents how the statuses of its state
## combinations combine into one.
##
## Sign conventions (one place, used everywhere):
##   Every element has a first node a and a second node b (plus and minus for a
##   voltage source).
##   voltage_across(id) = V(a) - V(b).
##   current_through(id) = the current flowing through the element from a to b,
##     EXCEPT for a voltage source, where it is the current the source delivers:
##     the current leaving its plus terminal into the rest of the circuit
##     (positive when the source powers a load).
##   power_of(id): a resistor's dissipated power V * I (never negative); a
##     voltage source's delivered power volts * delivered current (positive
##     when it powers a load); 0 for meters; null for wires.
##   An ammeter reads current_through (a to b); a voltmeter reads V(a) - V(b).
##   Devices (DIODE, ZENER; a is the anode, b the cathode):
##     voltage_across = V(anode) - V(cathode), null when an OFF device's ends
##     lie in different connected parts (as for a voltmeter);
##     current_through = the current from anode to cathode through it (a
##     Zener in breakdown carries a negative current);
##     power_of = voltage * current (0 for an OFF device);
##     device_state / device_state_name give the state PwlSolver chose.
##   Node voltages are relative to the ground of their connected component,
##   which is the component's alphabetically smallest node name. An OFF device
##   does not connect its ends.
##
## Every getter returns null (and never calls push_error) when the id or node
## is unknown, or when the value is not available: the status is not OK, or the
## quantity has no meaning (current through a wire, a voltage between two
## unconnected parts). Ohmmeter readings are the exception: they do not depend
## on the status, see meter_reading().
##
## Instances are filled in by DcSolver. Treat them as read-only.

enum Status { OK, SHORT, INDETERMINATE, ERROR }

## VALUE: meter_reading() holds a number. OPEN: no defined reading (an
## ohmmeter shows OL, a voltmeter between unconnected parts shows nothing).
## INVALID: the circuit has no valid solution (or the ohmmeter's own solve
## overflowed). NOT_A_METER: the id is unknown or not a meter.
enum MeterState { VALUE, OPEN, INVALID, NOT_A_METER }

var status: Status = Status.ERROR
var error_message: String = ""

# Written by DcSolver.
var _kinds: Dictionary = {}  # element id -> DcNetwork.Kind
var _node_voltages: Dictionary = {}  # node name -> Rational (only when OK)
var _voltages: Dictionary = {}  # element id -> Rational (only when OK)
var _currents: Dictionary = {}  # element id -> Rational (only when OK)
var _powers: Dictionary = {}  # element id -> Rational (only when OK)
var _meter_states: Dictionary = {}  # meter id -> MeterState
var _meter_readings: Dictionary = {}  # meter id -> Rational (only when VALUE)
var _energized: bool = false
var _device_states: Dictionary = {}  # device id -> int state (only when OK)
var _device_state_names: Dictionary = {}  # device id -> String (only when OK)


## The DcNetwork.Kind of an element, or -1 for an unknown id.
func element_kind(id: String) -> int:
	if not _kinds.has(id):
		return -1
	return int(_kinds[id])


func has_element(id: String) -> bool:
	return _kinds.has(id)


## The voltage of a node relative to its component's ground. Null for an
## unknown node or when the status is not OK.
func node_voltage(node: String) -> Rational:
	return _node_voltages.get(node, null)


## V(first node) - V(second node). For a voltage source: plus - minus.
## Null for an unknown id, when the status is not OK, or for a voltmeter or
## ohmmeter whose nodes lie in different connected parts.
func voltage_across(id: String) -> Rational:
	return _voltages.get(id, null)


## Current from the first node to the second node through the element; for a
## voltage source, the current it delivers from its plus terminal. 0 for
## voltmeters and ohmmeters. Null for wires, unknown ids, or when the status is
## not OK.
func current_through(id: String) -> Rational:
	return _currents.get(id, null)


## Resistor: dissipated power. Voltage source: delivered power. Meters: 0.
## Null for wires, unknown ids, or when the status is not OK.
func power_of(id: String) -> Rational:
	return _powers.get(id, null)


## The reading of an ammeter (current a to b), voltmeter (V(a) - V(b)) or
## ohmmeter (resistance between a and b with all sources switched off).
## Null unless meter_state(id) is VALUE.
##
## Ohmmeter readings come from their own solve of the dead network (voltage
## sources and ammeters become wires; voltmeters and other ohmmeters are open),
## so they are valid even when the live circuit is SHORT or INDETERMINATE.
## Every device (diode, LED, Zener) is open for an ohmmeter: with all sources
## off nothing forward-biases it, so a path only through a device reads OL.
func meter_reading(id: String) -> Rational:
	return _meter_readings.get(id, null)


## See MeterState.
func meter_state(id: String) -> MeterState:
	if not _meter_states.has(id):
		return MeterState.NOT_A_METER
	return _meter_states[id]


## True when the status is OK and at least one resistor or device carries a
## non-zero current.
func is_energized() -> bool:
	return status == Status.OK and _energized


## True when `id` is a device element (DIODE or ZENER) of the solved network,
## whatever the status.
func is_device(id: String) -> bool:
	return DcNetwork.is_device_kind(element_kind(id))


## The device's state (DiodeModel.State for diodes and Zeners). -1 for an
## unknown id, an element that is not a device, or when the status is not OK.
func device_state(id: String) -> int:
	return int(_device_states.get(id, -1))


## The device model's name for its state: "off" or "on" for a diode; "off",
## "forward" or "breakdown" for a Zener. "" whenever device_state is -1.
func device_state_name(id: String) -> String:
	return String(_device_state_names.get(id, ""))


func is_ok() -> bool:
	return status == Status.OK


## "OK", "SHORT", "INDETERMINATE" or "ERROR".
func status_text() -> String:
	return Status.keys()[status]
