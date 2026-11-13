extends TestCase
## Tests for PwlSolver (through DcSolver.solve) with diodes, LEDs and Zeners.
## Every expected value is exact and derived by hand in the comments.
## v = V(anode) - V(cathode); i = current from anode to cathode.

const OK: DcSolution.Status = DcSolution.Status.OK
const SHORT: DcSolution.Status = DcSolution.Status.SHORT
const INDETERMINATE: DcSolution.Status = DcSolution.Status.INDETERMINATE
const ERROR: DcSolution.Status = DcSolution.Status.ERROR
const VALUE: DcSolution.MeterState = DcSolution.MeterState.VALUE
const OPEN: DcSolution.MeterState = DcSolution.MeterState.OPEN
const INVALID: DcSolution.MeterState = DcSolution.MeterState.INVALID
const D_OFF: int = DiodeModel.State.OFF
const D_ON: int = DiodeModel.State.ON
const D_BREAKDOWN: int = DiodeModel.State.BREAKDOWN
const INT_MAX: int = 9223372036854775807


func _q(text: String) -> Rational:
	return Rational.parse(text)


## Rows as in test_dc_solver.gd, plus ["d", id, anode, cathode, drop] and
## ["z", id, anode, cathode, drop, zener voltage].
func _net(rows: Array) -> DcNetwork:
	var net: DcNetwork = DcNetwork.new()
	for row: Array in rows:
		var kind: String = row[0]
		match kind:
			"wire":
				net.add_wire(row[1], row[2], row[3])
			"r":
				net.add_resistor(row[1], row[2], row[3], _q(row[4]))
			"v":
				net.add_voltage_source(row[1], row[2], row[3], _q(row[4]))
			"am":
				net.add_ammeter(row[1], row[2], row[3])
			"vm":
				net.add_voltmeter(row[1], row[2], row[3])
			"om":
				net.add_ohmmeter(row[1], row[2], row[3])
			"d":
				net.add_diode(row[1], row[2], row[3], _q(row[4]))
			"z":
				net.add_zener(row[1], row[2], row[3], _q(row[4]), _q(row[5]))
	return net


func _solve(rows: Array) -> DcSolution:
	return DcSolver.solve(_net(rows))


## Every value of a solution as text, for comparing two solves.
func _dump(net: DcNetwork, sol: DcSolution) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("status %s %s" % [sol.status_text(), sol.error_message])
	for node: String in net.get_nodes():
		lines.append("node %s %s" % [node, _text(sol.node_voltage(node))])
	for id: String in net.get_element_ids():
		lines.append("%s k=%d v=%s i=%s p=%s m=%d r=%s s=%d %s" % [id, sol.element_kind(id),
				_text(sol.voltage_across(id)), _text(sol.current_through(id)), _text(sol.power_of(id)),
				sol.meter_state(id), _text(sol.meter_reading(id)), sol.device_state(id),
				sol.device_state_name(id)])
	lines.append("energized %s" % sol.is_energized())
	return "\n".join(lines)


func _text(value: Rational) -> String:
	return "null" if value == null else value.to_text()


## Removes every recorded engine error containing `fragment`; returns how many.
func _claim_errors(fragment: String) -> int:
	var count: int = 0
	var i: int = 0
	while i < _engine_errors.size():
		if _engine_errors[i].contains(fragment):
			_engine_errors.remove_at(i)
			count += 1
		else:
			i += 1
	return count


# --- single diodes --------------------------------------------------------------------

func test_silicon_diode_forward_in_series() -> void:
	# 5 V (+ p, - g), 1 kOhm p -> x, diode x -> g (0.7 V).
	# ON: V(x) = 0.7, i = (5 - 0.7) / 1000 = 4.3 mA = 43/10000 A.
	# Resistor: 4.3 V. Diode power 0.7 * 43/10000 = 301/100000 W.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_ON)
	assert_eq(sol.device_state_name("D1"), "on")
	assert_rational_eq(sol.current_through("D1"), "43/10000")
	assert_rational_eq(sol.voltage_across("D1"), "7/10")
	assert_rational_eq(sol.power_of("D1"), "301/100000")
	assert_rational_eq(sol.current_through("R1"), "43/10000")
	assert_rational_eq(sol.voltage_across("R1"), "43/10")
	assert_rational_eq(sol.current_through("B1"), "43/10000", "the battery delivers the same current")
	assert_rational_eq(sol.node_voltage("g"), "0", "g is the ground (smallest name)")
	assert_rational_eq(sol.node_voltage("x"), "7/10")
	assert_rational_eq(sol.node_voltage("p"), "5")
	assert_true(sol.is_energized())
	assert_true(sol.is_device("D1"))
	assert_false(sol.is_device("R1"))
	assert_eq(sol.element_kind("D1"), DcNetwork.Kind.DIODE)
	assert_eq(sol.meter_state("D1"), DcSolution.MeterState.NOT_A_METER, "a diode is not a meter")


func test_silicon_diode_reversed_in_series() -> void:
	# Same loop with the anode at g: OFF, no current, so V(x) = V(p) = 5 and
	# v = V(g) - V(x) = -5: the full 5 V sits across the diode, in reverse.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "g", "x", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_eq(sol.device_state_name("D1"), "off")
	assert_rational_eq(sol.current_through("D1"), "0")
	assert_rational_eq(sol.voltage_across("D1"), "-5")
	assert_rational_eq(sol.power_of("D1"), "0")
	assert_rational_eq(sol.current_through("R1"), "0")
	assert_rational_eq(sol.voltage_across("R1"), "0")
	assert_rational_eq(sol.current_through("B1"), "0")
	assert_false(sol.is_energized())


func test_threshold_source_is_one_state_not_ambiguous() -> void:
	# 0.7 V through 1 kOhm and a 0.7 V diode. OFF: no current, v = 0.7 <= 0.7,
	# valid. ON: i = (0.7 - 0.7) / 1000 = 0, not > 0, invalid. One state: OFF.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "7/10"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"]])
	assert_eq(sol.status, OK, "the boundary is not INDETERMINATE")
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.current_through("D1"), "0")
	assert_rational_eq(sol.voltage_across("D1"), "7/10")
	assert_rational_eq(sol.current_through("R1"), "0")


func test_threshold_source_directly_across_diode() -> void:
	# 0.7 V straight across a 0.7 V diode: OFF holds (v = 0.7 <= 0.7). ON makes
	# two equal sources in parallel (linear INDETERMINATE), which is ignored
	# because a valid combination exists.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "7/10"], ["d", "D1", "p", "g", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.current_through("B1"), "0")


func test_battery_directly_across_forward_diode_is_short() -> void:
	# OFF: v = 5 > 0.7, invalid. ON: two contradicting sources: SHORT.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["d", "D1", "p", "g", "7/10"],
			["am", "AM", "p", "q"], ["vm", "VM", "p", "g"], ["om", "OM", "p", "g"]])
	assert_eq(sol.status, SHORT)
	assert_null(sol.current_through("D1"))
	assert_null(sol.voltage_across("D1"))
	assert_eq(sol.device_state("D1"), -1, "no state when the status is not OK")
	assert_eq(sol.device_state_name("D1"), "")
	assert_true(sol.is_device("D1"), "still known as a device")
	assert_eq(sol.meter_state("AM"), INVALID)
	assert_eq(sol.meter_state("VM"), INVALID)
	assert_eq(sol.meter_state("OM"), VALUE, "the battery is a wire for the ohmmeter")
	assert_rational_eq(sol.meter_reading("OM"), "0")
	assert_false(sol.is_energized())


func test_battery_directly_across_reversed_diode() -> void:
	# OFF: v = V(g) - V(p) = -5 <= 0.7, valid, no current.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["d", "D1", "g", "p", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.current_through("D1"), "0")
	assert_rational_eq(sol.voltage_across("D1"), "-5")
	assert_rational_eq(sol.current_through("B1"), "0")


func test_battery_below_the_drop_across_diode() -> void:
	# 1/2 V across a 0.7 V diode: OFF holds; the ON combination is a SHORT
	# (0.7 against 0.5), a wrong guess that is ignored.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "1/2"], ["d", "D1", "p", "g", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.voltage_across("D1"), "1/2")


func test_red_led_with_series_resistor() -> void:
	# 9 V, 350 Ohm, red LED (2 V): i = (9 - 2) / 350 = 1/50 A = 20 mA.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "9"], ["r", "R1", "p", "x", "350"],
			["d", "LED", "x", "g", "2"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("LED"), D_ON)
	assert_rational_eq(sol.current_through("LED"), "1/50")
	assert_rational_eq(sol.voltage_across("LED"), "2")
	assert_rational_eq(sol.power_of("LED"), "1/25")
	assert_rational_eq(sol.voltage_across("R1"), "7")


func test_zero_drop_ideal_diode() -> void:
	# Drop 0: an ideal switch. 6 V across 3 Ohm through it: 2 A.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "6"], ["d", "D1", "p", "x", "0"],
			["r", "R1", "x", "g", "3"]])
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("D1"), "2")
	assert_rational_eq(sol.voltage_across("D1"), "0")
	assert_rational_eq(sol.power_of("D1"), "0")


# --- pairs ----------------------------------------------------------------------------

func test_two_diodes_in_series() -> void:
	# 5 V, 1 kOhm, two 0.7 V diodes: i = (5 - 1.4) / 1000 = 9/2500 A.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "y", "7/10"], ["d", "D2", "y", "g", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_ON)
	assert_eq(sol.device_state("D2"), D_ON)
	assert_rational_eq(sol.current_through("D1"), "9/2500")
	assert_rational_eq(sol.current_through("D2"), "9/2500")
	assert_rational_eq(sol.node_voltage("y"), "7/10")
	assert_rational_eq(sol.node_voltage("x"), "7/5")


func test_two_diodes_anti_parallel() -> void:
	# D1 x -> g conducts 4.3 mA; D2 g -> x sees v = -0.7 and is OFF.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["d", "D2", "g", "x", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_ON)
	assert_eq(sol.device_state("D2"), D_OFF)
	assert_rational_eq(sol.current_through("D1"), "43/10000")
	assert_rational_eq(sol.current_through("D2"), "0")
	assert_rational_eq(sol.voltage_across("D2"), "-7/10")


func test_parallel_diodes_with_different_drops() -> void:
	# Silicon (0.7) and Schottky (0.3) in parallel: the Schottky clamps x at
	# 0.3 V and carries (5 - 0.3) / 1000 = 47/10000 A; the silicon diode sees
	# 0.3 <= 0.7 and is OFF. (Silicon alone ON would put 0.7 across the
	# Schottky: invalid. Both ON: SHORT.)
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "SI", "x", "g", "7/10"], ["d", "SCH", "x", "g", "3/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("SCH"), D_ON)
	assert_eq(sol.device_state("SI"), D_OFF)
	assert_rational_eq(sol.current_through("SCH"), "47/10000")
	assert_rational_eq(sol.current_through("SI"), "0")
	assert_rational_eq(sol.voltage_across("SI"), "3/10")


func test_identical_parallel_diodes_are_indeterminate() -> void:
	# Two equal ideal diodes in parallel: either one may carry the 4.3 mA (and
	# both together any split). The valid combinations disagree.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["d", "D2", "x", "g", "7/10"], ["am", "AM", "g", "h"]])
	assert_eq(sol.status, INDETERMINATE)
	assert_null(sol.current_through("R1"))
	assert_eq(sol.device_state("D1"), -1)
	assert_eq(sol.meter_state("AM"), INVALID)


# --- Zener ----------------------------------------------------------------------------

## 12 V (+ p, - g), 1 kOhm p -> n, Zener (0.7 V, 5.1 V) and a load n -> g.
func _regulator(load: String, zener_anode: String, zener_cathode: String) -> DcSolution:
	return _solve([["v", "B1", "p", "g", "12"], ["r", "RS", "p", "n", "1000"],
			["z", "Z1", zener_anode, zener_cathode, "7/10", "51/10"], ["r", "RL", "n", "g", load],
			["vm", "VM", "n", "g"]])


func test_zener_regulates_with_light_load() -> void:
	# Reverse (anode g, cathode n), load 10 kOhm: breakdown holds V(n) = 5.1.
	# Series current (12 - 5.1) / 1000 = 69/10000; load 5.1 / 10000 =
	# 51/100000; the Zener takes 69/10000 - 51/100000 = 639/100000 from
	# cathode to anode, so i = -639/100000 (< 0, breakdown is valid).
	# Power v * i = (-51/10) * (-639/100000) = 32589/1000000.
	var sol: DcSolution = _regulator("10000", "g", "n")
	assert_eq(sol.status, OK)
	assert_eq(sol.element_kind("Z1"), DcNetwork.Kind.ZENER)
	assert_eq(sol.device_state("Z1"), D_BREAKDOWN)
	assert_eq(sol.device_state_name("Z1"), "breakdown")
	assert_rational_eq(sol.meter_reading("VM"), "51/10")
	assert_rational_eq(sol.voltage_across("Z1"), "-51/10")
	assert_rational_eq(sol.current_through("Z1"), "-639/100000")
	assert_rational_eq(sol.power_of("Z1"), "32589/1000000")
	assert_rational_eq(sol.current_through("RS"), "69/10000")
	assert_rational_eq(sol.current_through("RL"), "51/100000")


func test_zener_drops_out_with_heavy_load() -> void:
	# Load 500 Ohm: the divider gives 12 * 500 / 1500 = 4 V < 5.1, so the
	# Zener is OFF (v = -4 is within [-5.1, 0.7]). Breakdown would need it to
	# push current the wrong way: (6.9 - 10.2) mA, i = +3.3 mA, invalid.
	var sol: DcSolution = _regulator("500", "g", "n")
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("Z1"), D_OFF)
	assert_eq(sol.device_state_name("Z1"), "off")
	assert_rational_eq(sol.meter_reading("VM"), "4")
	assert_rational_eq(sol.voltage_across("Z1"), "-4")
	assert_rational_eq(sol.current_through("Z1"), "0")
	assert_rational_eq(sol.current_through("RL"), "1/125")


func test_zener_forwards_is_a_diode() -> void:
	# Anode n, cathode g: forward at 0.7 V. Series (12 - 0.7) / 1000 =
	# 113/10000, load 0.7 / 10000 = 7/100000, Zener 1130/100000 - 7/100000 =
	# 1123/100000.
	var sol: DcSolution = _regulator("10000", "n", "g")
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("Z1"), D_ON)
	assert_eq(sol.device_state_name("Z1"), "forward")
	assert_rational_eq(sol.meter_reading("VM"), "7/10")
	assert_rational_eq(sol.current_through("Z1"), "1123/100000")


func test_zener_directly_across_battery_is_short() -> void:
	# 12 V straight across a reversed 5.1 V Zener: OFF needs v >= -5.1 (it is
	# -12), breakdown and forward contradict the battery: SHORT.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "12"], ["z", "Z1", "g", "p", "7/10", "51/10"]])
	assert_eq(sol.status, SHORT)


func test_zener_off_between_its_two_voltages() -> void:
	# 3 V reversed across a 5.1 V Zener: v = -3 in [-5.1, 0.7]: OFF.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "3"], ["z", "Z1", "g", "p", "7/10", "51/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("Z1"), D_OFF)
	assert_rational_eq(sol.voltage_across("Z1"), "-3")


func test_zener_exactly_at_breakdown_is_off() -> void:
	# 5.1 V reversed through 1 kOhm: breakdown would carry 0 A (not < 0), OFF
	# holds at v = -5.1 exactly: one state.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "51/10"], ["r", "R1", "p", "n", "1000"],
			["z", "Z1", "g", "n", "7/10", "51/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("Z1"), D_OFF)
	assert_rational_eq(sol.voltage_across("Z1"), "-51/10")


# --- bridge rectifier -----------------------------------------------------------------

## Battery between ac nodes "a1" and "a2"; D1 a1 -> P, D2 a2 -> P, D3 N -> a1,
## D4 N -> a2; load 100 Ohm P -> N; voltmeter P -> N.
func _bridge(plus: String, minus: String) -> DcSolution:
	return _solve([["v", "B1", plus, minus, "5"], ["d", "D1", "a1", "P", "7/10"],
			["d", "D2", "a2", "P", "7/10"], ["d", "D3", "N", "a1", "7/10"],
			["d", "D4", "N", "a2", "7/10"], ["r", "RL", "P", "N", "100"], ["vm", "VM", "P", "N"]])


func test_bridge_rectifier_either_battery_direction() -> void:
	# + at a1: D1 and D4 conduct; load V = 5 - 1.4 = 18/5, I = 18/500 = 9/250.
	# D2 sees V(a2) - V(P) = (V(a1) - 5) - (V(a1) - 0.7) = -4.3: OFF; D3 too.
	var forward: DcSolution = _bridge("a1", "a2")
	assert_eq(forward.status, OK)
	assert_rational_eq(forward.meter_reading("VM"), "18/5")
	assert_rational_eq(forward.current_through("RL"), "9/250")
	assert_eq(forward.device_state("D1"), D_ON)
	assert_eq(forward.device_state("D4"), D_ON)
	assert_eq(forward.device_state("D2"), D_OFF)
	assert_eq(forward.device_state("D3"), D_OFF)
	assert_rational_eq(forward.voltage_across("D2"), "-43/10")
	# + at a2: D2 and D3 conduct; the load sees the same polarity and value.
	var reverse: DcSolution = _bridge("a2", "a1")
	assert_eq(reverse.status, OK)
	assert_rational_eq(reverse.meter_reading("VM"), "18/5")
	assert_rational_eq(reverse.current_through("RL"), "9/250")
	assert_eq(reverse.device_state("D2"), D_ON)
	assert_eq(reverse.device_state("D3"), D_ON)
	assert_eq(reverse.device_state("D1"), D_OFF)
	assert_eq(reverse.device_state("D4"), D_OFF)


func test_bridge_with_too_small_a_battery_is_off() -> void:
	# 1 V < 1.4 V: no pair can conduct; all OFF and the load is dead.
	var sol: DcSolution = _solve([["v", "B1", "a1", "a2", "1"], ["d", "D1", "a1", "P", "7/10"],
			["d", "D2", "a2", "P", "7/10"], ["d", "D3", "N", "a1", "7/10"],
			["d", "D4", "N", "a2", "7/10"], ["r", "RL", "P", "N", "100"]])
	assert_eq(sol.status, OK)
	for id: String in ["D1", "D2", "D3", "D4"]:
		assert_eq(sol.device_state(id), D_OFF, id)
	assert_rational_eq(sol.current_through("RL"), "0")


# --- open sections, floating parts ----------------------------------------------------------

func test_off_diode_leaves_a_dead_branch() -> void:
	# 5 V, 1 kOhm p -> m, forward diode m -> x, ammeter x -> y, and y goes
	# nowhere (an empty slot). The diode cannot conduct (no return path), so
	# it is OFF: the ammeter in the dead branch reads 0, x and y float.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "m", "1000"],
			["d", "D1", "m", "x", "7/10"], ["am", "AM", "x", "y"], ["vm", "VMX", "x", "g"],
			["vm", "VMM", "m", "g"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.current_through("D1"), "0")
	assert_null(sol.voltage_across("D1"), "its ends are in unconnected parts")
	assert_rational_eq(sol.power_of("D1"), "0")
	assert_eq(sol.meter_state("AM"), VALUE)
	assert_rational_eq(sol.meter_reading("AM"), "0")
	assert_eq(sol.meter_state("VMX"), OPEN, "voltmeter across unconnected parts")
	assert_rational_eq(sol.meter_reading("VMM"), "5", "no current: the resistor drops nothing")
	assert_rational_eq(sol.node_voltage("x"), "0", "x grounds its own floating part")
	assert_false(sol.is_energized())


func test_dangling_diode() -> void:
	# A diode hanging from p to a node nothing else touches.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "6"], ["r", "R1", "p", "g", "3"],
			["d", "D1", "p", "z", "7/10"], ["d", "D2", "z", "z", "7/10"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_null(sol.voltage_across("D1"))
	assert_eq(sol.device_state("D2"), D_OFF, "both ends on one node: v = 0")
	assert_rational_eq(sol.voltage_across("D2"), "0")
	assert_rational_eq(sol.current_through("R1"), "2")
	assert_true(sol.is_energized())


func test_diode_shorted_by_a_wire_is_off() -> void:
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "6"], ["r", "R1", "p", "x", "3"],
			["d", "D1", "x", "g", "7/10"], ["wire", "W", "x", "g"]])
	assert_eq(sol.status, OK)
	assert_eq(sol.device_state("D1"), D_OFF)
	assert_rational_eq(sol.current_through("R1"), "2")


func test_floating_battery_closed_through_off_diodes() -> void:
	# Battery (+ p, - n) whose loop is closed only by D1 p -> q and D2 q -> n.
	# With both OFF, q floats: the battery and q are separate parts, and the
	# two OFF conditions V(p) - V(q) <= 0.7 and V(q) - V(n) <= 0.7 must hold
	# together for some potential of q: possible iff V(p) - V(n) <= 1.4.
	var low: DcSolution = _solve([["v", "B1", "p", "n", "1"], ["d", "D1", "p", "q", "7/10"],
			["d", "D2", "q", "n", "7/10"]])
	assert_eq(low.status, OK, "1 V <= 1.4 V: both OFF")
	assert_eq(low.device_state("D1"), D_OFF)
	assert_eq(low.device_state("D2"), D_OFF)
	assert_null(low.voltage_across("D1"))
	var edge: DcSolution = _solve([["v", "B1", "p", "n", "7/5"], ["d", "D1", "p", "q", "7/10"],
			["d", "D2", "q", "n", "7/10"]])
	assert_eq(edge.status, OK, "exactly 1.4 V: both OFF (boundary)")
	assert_eq(edge.device_state("D1"), D_OFF)
	# 5 V: both OFF is impossible (5 > 1.4), one ON leaves the other with
	# 4.3 V, both ON contradict the battery. A real short.
	var high: DcSolution = _solve([["v", "B1", "p", "n", "5"], ["d", "D1", "p", "q", "7/10"],
			["d", "D2", "q", "n", "7/10"]])
	assert_eq(high.status, SHORT)


## A test model: a diode whose OFF state is strict (v < drop), to exercise the
## strict edges of the floating-part check.
class _StrictDiode:
	extends PwlDevice
	var _drop: Rational = Rational.new(7, 10)

	func terminal_names() -> Array[String]:
		var names: Array[String] = ["anode", "cathode"]
		return names

	func branch_count() -> int:
		return 1

	func branch_terminals(_branch: int) -> Array[int]:
		var terminals: Array[int] = [0, 1]
		return terminals

	func state_count() -> int:
		return 2

	func state_name(state: int) -> String:
		return "on" if state == 1 else "off"

	func branch_kind(state: int, _branch: int) -> PwlDevice.BranchKind:
		return PwlDevice.BranchKind.VOLTAGE if state == 1 else PwlDevice.BranchKind.OPEN

	func branch_value(state: int, _branch: int) -> Rational:
		return _drop if state == 1 else null

	func conditions(state: int) -> Array[PwlCondition]:
		var list: Array[PwlCondition] = []
		if state == 1:
			list.append(PwlCondition.current(0, PwlCondition.Relation.ABOVE, Rational.new(0)))
		else:
			list.append(PwlCondition.voltage(0, PwlCondition.Relation.BELOW, _drop))
		return list

	func network_kind() -> int:
		return DcNetwork.Kind.DIODE

	func parameters_text() -> String:
		return "strict"


func _strict_pair(volts: String) -> DcSolution:
	# Battery (+ p, - n), strict diodes p -> q -> n, compiled by hand so the
	# test model can be attached.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "n", _q(volts))
	net.add_diode("D1", "p", "q", _q("7/10"))
	net.add_diode("D2", "q", "n", _q("7/10"))
	var no_extra: Array[String] = []
	var circuit: DcSolver._Circuit = DcSolver._compile(net, no_extra)
	var model: _StrictDiode = _StrictDiode.new()
	for id: String in ["D1", "D2"]:
		var e: int = circuit.element_index[id]
		circuit.set_element(e, DcNetwork.Kind.DIODE, null, null, model)
	return PwlSolver._solve_compiled(circuit, {}, true)


func test_strict_conditions_across_floating_parts() -> void:
	# Below 1.4 V both strict OFF conditions can hold together.
	assert_eq(_strict_pair("1").status, OK)
	# At exactly 1.4 V, v1 + v2 = 1.4 with v1 < 0.7 and v2 < 0.7 is impossible.
	# One ON carries 0 A (not > 0). Both ON: 0.7 + 0.7 = 1.4, a consistent
	# source loop: INDETERMINATE, the only status left.
	assert_eq(_strict_pair("7/5").status, INDETERMINATE)


# --- the network as a whole -----------------------------------------------------------

func test_unrelated_short_wins() -> void:
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["v", "B2", "s", "t", "3"], ["wire", "W", "s", "t"]])
	assert_eq(sol.status, SHORT)


func test_unrelated_indeterminate() -> void:
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["v", "B2", "s", "t", "3"], ["am", "A1", "s", "u"],
			["am", "A2", "s", "u"], ["r", "R2", "u", "t", "1"]])
	assert_eq(sol.status, INDETERMINATE)


func test_power_balance_with_devices() -> void:
	# 10 V, 100 Ohm, red LED (2 V) || (Schottky 0.3 in series with 50 Ohm).
	# Node x: LED clamps x at 2 V if it conducts; then the Schottky branch
	# carries (2 - 0.3) / 50 = 17/500 and the series resistor (10 - 2) / 100
	# = 2/25 = 40/500, so the LED takes 23/500 > 0: consistent.
	var sol: DcSolution = _solve([["v", "B1", "p", "g", "10"], ["r", "R1", "p", "x", "100"],
			["d", "LED", "x", "g", "2"], ["d", "SCH", "x", "y", "3/10"], ["r", "R2", "y", "g", "50"]])
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("LED"), "23/500")
	assert_rational_eq(sol.current_through("SCH"), "17/500")
	var delivered: Rational = sol.power_of("B1")
	var used: Rational = sol.power_of("R1").add(sol.power_of("R2")).add(sol.power_of("LED")).add(sol.power_of("SCH"))
	assert_true(delivered.equals(used), "power balance %s vs %s" % [delivered.to_text(), used.to_text()])


func test_ohmmeter_reads_devices_as_open() -> void:
	# Ohmmeter across R1 (2) in series with a diode: OL. Across R1 || diode: 2.
	var series: DcSolution = _solve([["r", "R1", "a", "m", "2"], ["d", "D1", "m", "b", "7/10"],
			["om", "OM", "a", "b"], ["om", "OMR", "a", "m"]])
	assert_eq(series.status, OK)
	assert_eq(series.meter_state("OM"), OPEN, "OL: the only path is through the diode")
	assert_eq(series.meter_state("OMR"), VALUE)
	assert_rational_eq(series.meter_reading("OMR"), "2")
	var parallel: DcSolution = _solve([["r", "R1", "a", "b", "2"], ["d", "D1", "a", "b", "7/10"],
			["d", "D2", "b", "a", "7/10"], ["om", "OM", "a", "b"]])
	assert_rational_eq(parallel.meter_reading("OM"), "2", "both directions: still open")
	# A conducting diode in the live circuit does not change the reading: across
	# the diode the ohmmeter sees only R1 through the dead battery (1000), not
	# the diode (which would read 0 if it counted as a wire or a source).
	var live: DcSolution = _solve([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["om", "OM", "x", "g"], ["om", "OMP", "p", "x"]])
	assert_eq(live.device_state("D1"), D_ON)
	assert_rational_eq(live.meter_reading("OM"), "1000")
	assert_rational_eq(live.meter_reading("OMP"), "1000")


func test_input_network_is_not_modified_and_results_repeat() -> void:
	var net: DcNetwork = _net([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "x", "1000"],
			["d", "D1", "x", "g", "7/10"], ["z", "Z1", "g", "x", "7/10", "3"], ["om", "OM", "p", "g"]])
	var before: String = net.to_text()
	var first: String = _dump(net, DcSolver.solve(net))
	var second: String = _dump(net, DcSolver.solve(net))
	assert_eq(net.to_text(), before)
	assert_eq(first, second)
	assert_true(first.contains("D1 k=%d" % DcNetwork.Kind.DIODE), first)


func test_large_values_that_fit_stay_exact() -> void:
	# 2^61 V through an ideal (0 V) diode across 2^60 Ohm: exactly 2 A.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", Rational.new(2305843009213693952))
	net.add_diode("D1", "p", "x", Rational.new(0))
	net.add_resistor("R1", "x", "g", Rational.new(1152921504606846976))
	var sol: DcSolution = DcSolver.solve(net)
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("D1"), "2")
	assert_rational_eq(sol.power_of("R1"), "4611686018427387904")


func test_overflow_is_an_error_not_a_guess() -> void:
	# (2^63 - 1) V across 1/2 Ohm and a diode: the ON combination's current
	# does not fit in 64 bits, so the answer is ERROR.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", Rational.new(INT_MAX))
	net.add_resistor("R1", "p", "x", Rational.new(1, 2))
	net.add_diode("D1", "x", "g", Rational.new(0))
	net.add_ammeter("AM", "g", "h")
	var sol: DcSolution = DcSolver.solve(net)
	assert_true(_claim_errors("Rational.") > 0, "a Rational overflow was reported")
	assert_true(_claim_errors("DcSolver.solve") > 0, "the solver reported it")
	assert_eq(sol.status, ERROR)
	assert_true(sol.error_message.contains("does not fit in 64 bits"), sol.error_message)
	assert_null(sol.current_through("D1"))
	assert_eq(sol.device_state("D1"), -1)
	assert_eq(sol.meter_state("AM"), INVALID)


func test_too_many_combinations_is_an_error() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "n0", "g", Rational.new(1))
	for k: int in 17:
		net.add_diode("D%02d" % k, "n%d" % k, "n%d" % (k + 1), Rational.new(7, 10))
	assert_eq(PwlSolver.combination_count(net), PwlSolver.MAX_COMBINATIONS + 1)
	var sol: DcSolution = DcSolver.solve(net)
	assert_error_pushed("more than 65536 combinations")
	assert_eq(sol.status, ERROR)
	assert_eq(sol.element_kind("D00"), DcNetwork.Kind.DIODE)


func test_combination_count() -> void:
	assert_eq(PwlSolver.combination_count(null), 0)
	assert_eq(PwlSolver.combination_count(DcNetwork.new()), 1)
	var net: DcNetwork = _net([["r", "R1", "a", "b", "1"], ["d", "D1", "a", "b", "7/10"],
			["d", "D2", "b", "a", "3/10"], ["z", "Z1", "a", "b", "7/10", "51/10"]])
	assert_eq(PwlSolver.combination_count(net), 12, "2 * 2 * 3")


# --- no devices: the search path equals the linear solver -------------------------------------

func _search_path(net: DcNetwork) -> DcSolution:
	var no_extra: Array[String] = []
	return PwlSolver._solve_compiled(DcSolver._compile(net, no_extra), {}, true)


func test_no_devices_search_path_matches_fixtures() -> void:
	var fixtures: Array = [
		# series with an ammeter
		[["v", "B1", "p", "g", "6"], ["am", "AM", "p", "a"], ["r", "R1", "a", "g", "3"]],
		# unbalanced bridge with an ohmmeter
		[["v", "B1", "s", "b", "6"], ["am", "AMS", "s", "t"], ["r", "R1", "t", "l", "1"],
				["r", "R2", "t", "r", "2"], ["r", "R3", "l", "b", "3"], ["r", "R4", "r", "b", "4"],
				["am", "AMB", "l", "r"], ["om", "OM", "t", "b"]],
		# shorted battery, ohmmeter still reads
		[["r", "R1", "a", "m", "2"], ["v", "B1", "m", "b", "9"], ["wire", "W", "m", "b"],
				["r", "R2", "a", "b", "2"], ["om", "OM", "a", "b"], ["am", "AM", "a", "x"]],
		# two ammeters in parallel
		[["v", "B1", "p", "g", "6"], ["am", "AM1", "p", "a"], ["am", "AM2", "p", "a"],
				["r", "R1", "a", "g", "3"]],
		# floating component and open voltmeter
		[["v", "B1", "p", "g", "6"], ["r", "R1", "p", "g", "3"], ["r", "R2", "x", "y", "5"],
				["vm", "VM", "p", "x"], ["vm", "VMX", "x", "y"]],
		# two loops with a shared resistor
		[["v", "B1", "a", "g", "10"], ["v", "B2", "b", "g", "5"], ["r", "R1", "a", "j", "2"],
				["r", "R2", "b", "j", "1"], ["r", "R3", "j", "g", "4"]],
		# empty network
		[],
	]
	for rows: Array in fixtures:
		var net: DcNetwork = _net(rows)
		assert_eq(_dump(net, _search_path(net)), _dump(net, DcSolver.solve(net)), net.to_text())


func test_no_devices_search_path_matches_overflow_error() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", Rational.new(INT_MAX))
	net.add_resistor("R1", "p", "g", Rational.new(1, 2))
	net.add_ammeter("AM", "p", "q")
	var expected: String = _dump(net, DcSolver.solve(net))
	var actual: String = _dump(net, _search_path(net))
	assert_eq(_claim_errors("Rational.mul"), 2)
	assert_eq(_claim_errors("DcSolver.solve"), 2)
	assert_eq(actual, expected)
	assert_true(actual.contains("status ERROR"), actual)


const _RESISTANCES: Array[String] = ["1/2", "1", "2", "3", "4", "6"]
const _VOLTAGES: Array[String] = ["-2", "0", "1", "3", "5/2"]
const _DROPS: Array[String] = ["0", "3/10", "7/10", "2"]
const _ZENER_VOLTAGES: Array[String] = ["1", "3", "51/10"]


## Random network as in test_dc_solver.gd, plus `devices` diodes or Zeners.
func _random_network(rng: RandomNumberGenerator, devices: int) -> DcNetwork:
	var net: DcNetwork = DcNetwork.new()
	var node_count: int = rng.randi_range(2, 5)
	var element_count: int = rng.randi_range(2, 7)
	for k: int in element_count:
		var id: String = "e%d" % k
		var a: String = "n%d" % rng.randi_range(0, node_count - 1)
		var b: String = "n%d" % rng.randi_range(0, node_count - 1)
		var roll: int = rng.randi_range(0, 11)
		if roll <= 4:
			net.add_resistor(id, a, b, _q(_RESISTANCES[rng.randi_range(0, _RESISTANCES.size() - 1)]))
		elif roll <= 6:
			net.add_voltage_source(id, a, b, _q(_VOLTAGES[rng.randi_range(0, _VOLTAGES.size() - 1)]))
		elif roll == 7:
			net.add_ammeter(id, a, b)
		elif roll == 8:
			net.add_wire(id, a, b)
		elif roll == 9:
			net.add_voltmeter(id, a, b)
		else:
			net.add_ohmmeter(id, a, b)
	for k: int in devices:
		var id: String = "d%d" % k
		var a: String = "n%d" % rng.randi_range(0, node_count - 1)
		var b: String = "n%d" % rng.randi_range(0, node_count - 1)
		var drop: Rational = _q(_DROPS[rng.randi_range(0, _DROPS.size() - 1)])
		if rng.randi_range(0, 3) == 0:
			net.add_zener(id, a, b, _q("7/10"), _q(_ZENER_VOLTAGES[rng.randi_range(0, _ZENER_VOLTAGES.size() - 1)]))
		else:
			net.add_diode(id, a, b, drop)
	return net


func test_no_devices_search_path_matches_random_networks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261113
	for trial: int in 300:
		var net: DcNetwork = _random_network(rng, 0)
		assert_eq(_dump(net, _search_path(net)), _dump(net, DcSolver.solve(net)), "trial %d\n%s" % [trial, net.to_text()])


## Problems with an OK solution: Kirchhoff's current law at every wire-merged
## node, Ohm's law, source voltages, and every device's state conditions.
func _problems(net: DcNetwork, sol: DcSolution) -> Array[String]:
	var problems: Array[String] = []
	var nodes: Array[String] = net.get_nodes()
	var group: Dictionary = {}
	for node: String in nodes:
		group[node] = node
	for id: String in net.get_element_ids():
		if net.get_kind(id) == DcNetwork.Kind.WIRE:
			var ra: String = _find(group, net.get_node_a(id))
			var rb: String = _find(group, net.get_node_b(id))
			if ra != rb:
				group[ra] = rb
	var leaving: Dictionary = {}
	var zero: Rational = Rational.new(0)
	for id: String in net.get_element_ids():
		var kind: int = net.get_kind(id)
		if kind == DcNetwork.Kind.WIRE:
			continue
		var i: Rational = sol.current_through(id)
		var v: Rational = sol.voltage_across(id)
		if i == null:
			problems.append("%s has no current" % id)
			continue
		# Current leaving node a through the element (a source reports the
		# current it pushes out of its plus terminal).
		var out_of_a: Rational = i.negate() if kind == DcNetwork.Kind.VOLTAGE_SOURCE else i
		var ga: String = _find(group, net.get_node_a(id))
		var gb: String = _find(group, net.get_node_b(id))
		leaving[ga] = (leaving.get(ga, zero) as Rational).add(out_of_a)
		leaving[gb] = (leaving.get(gb, zero) as Rational).sub(out_of_a)
		match kind:
			DcNetwork.Kind.RESISTOR:
				if v == null or not v.equals(i.mul(net.get_value(id))):
					problems.append("%s breaks Ohm's law" % id)
			DcNetwork.Kind.VOLTAGE_SOURCE:
				if v == null or not v.equals(net.get_value(id)):
					problems.append("%s does not hold its voltage" % id)
			DcNetwork.Kind.DIODE, DcNetwork.Kind.ZENER:
				var model: DiodeModel = net.get_device(id)
				var state: int = sol.device_state(id)
				match state:
					D_OFF:
						if not i.is_zero():
							problems.append("%s is OFF with current %s" % [id, i.to_text()])
						if v != null and (v.compare(model.forward_drop) > 0
								or (model.is_zener() and v.compare(model.zener_voltage.negate()) < 0)):
							problems.append("%s is OFF with v = %s" % [id, v.to_text()])
					D_ON:
						if v == null or not v.equals(model.forward_drop) or i.sign() <= 0:
							problems.append("%s is ON with v = %s, i = %s" % [id, _text(v), i.to_text()])
					D_BREAKDOWN:
						if (not model.is_zener() or v == null or not v.equals(model.zener_voltage.negate())
								or i.sign() >= 0):
							problems.append("%s is in breakdown with v = %s, i = %s" % [id, _text(v), i.to_text()])
					_:
						problems.append("%s has no state" % id)
	for key: Variant in leaving.keys():
		if not (leaving[key] as Rational).is_zero():
			problems.append("KCL fails at %s: %s leaves" % [str(key), (leaving[key] as Rational).to_text()])
	return problems


func _find(group: Dictionary, node: String) -> String:
	while group[node] != node:
		node = group[node]
	return node


## A circuit-like random network: one battery, mostly resistors, a few
## sources, wires and meters, and `devices` diodes or Zeners.
func _device_network(rng: RandomNumberGenerator, devices: int) -> DcNetwork:
	var net: DcNetwork = DcNetwork.new()
	var node_count: int = rng.randi_range(3, 5)
	net.add_voltage_source("B", "n0", "n1", _q(["3", "5", "9", "12"][rng.randi_range(0, 3)]))
	var element_count: int = rng.randi_range(2, 6)
	for k: int in element_count:
		var id: String = "e%d" % k
		var a: String = "n%d" % rng.randi_range(0, node_count - 1)
		var b: String = "n%d" % rng.randi_range(0, node_count - 1)
		var roll: int = rng.randi_range(0, 19)
		if roll <= 11:
			net.add_resistor(id, a, b, _q(_RESISTANCES[rng.randi_range(0, _RESISTANCES.size() - 1)]))
		elif roll <= 13:
			net.add_voltage_source(id, a, b, _q(_VOLTAGES[rng.randi_range(0, _VOLTAGES.size() - 1)]))
		elif roll == 14:
			net.add_wire(id, a, b)
		elif roll <= 16:
			net.add_ammeter(id, a, b)
		else:
			net.add_voltmeter(id, a, b)
	for k: int in devices:
		var id: String = "d%d" % k
		var a: String = "n%d" % rng.randi_range(0, node_count - 1)
		var b: String = "n%d" % rng.randi_range(0, node_count - 1)
		if rng.randi_range(0, 2) > 0:
			# Mostly in series with a resistor, so the current is limited.
			var middle: String = "m%d" % k
			net.add_resistor("rs%d" % k, middle, b, _q(_RESISTANCES[rng.randi_range(0, _RESISTANCES.size() - 1)]))
			b = middle
		if rng.randi_range(0, 3) == 0:
			net.add_zener(id, a, b, _q("7/10"), _q(_ZENER_VOLTAGES[rng.randi_range(0, _ZENER_VOLTAGES.size() - 1)]))
		else:
			net.add_diode(id, a, b, _q(_DROPS[rng.randi_range(0, _DROPS.size() - 1)]))
	return net


func test_random_networks_with_devices_satisfy_every_law() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	var counts: Dictionary = {"OK": 0, "SHORT": 0, "INDETERMINATE": 0, "ERROR": 0}
	var states_seen: Dictionary = {}
	var conducting: int = 0
	for trial: int in 800:
		var net: DcNetwork = _random_network(rng, rng.randi_range(1, 3)) if trial % 2 == 0 \
				else _device_network(rng, rng.randi_range(1, 3))
		var sol: DcSolution = DcSolver.solve(net)
		var label: String = "trial %d:\n%s" % [trial, net.to_text()]
		counts[sol.status_text()] = int(counts[sol.status_text()]) + 1
		assert_ne(sol.status, ERROR, label + "\n" + sol.error_message)
		if sol.status != OK:
			continue
		var problems: Array[String] = _problems(net, sol)
		assert_true(problems.is_empty(), label + "\n" + "\n".join(problems))
		for id: String in net.get_element_ids():
			if net.get_device(id) != null:
				states_seen[sol.device_state(id)] = true
				if not sol.current_through(id).is_zero():
					conducting += 1
	assert_true(int(counts["OK"]) > 350, str(counts))
	assert_true(int(counts["SHORT"]) > 10, str(counts))
	assert_true(int(counts["INDETERMINATE"]) > 10, str(counts))
	assert_true(states_seen.has(D_OFF) and states_seen.has(D_ON) and states_seen.has(D_BREAKDOWN), str(states_seen))
	assert_true(conducting > 80, "conducting devices: %d %s" % [conducting, str(counts)])


func test_partial_solve_matches_full_solve_with_devices() -> void:
	# The puzzle search solves only for the elements its conditions name.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var compared: int = 0
	for trial: int in 120:
		var net: DcNetwork = _random_network(rng, rng.randi_range(1, 2))
		var full: DcSolution = DcSolver.solve(net)
		var no_extra: Array[String] = []
		var circuit: DcSolver._Circuit = DcSolver._compile(net, no_extra)
		for id: String in net.get_element_ids():
			var part: DcSolution = PwlSolver._solve_compiled(circuit, {id: true}, false)
			var label: String = "trial %d element %s:\n%s" % [trial, id, net.to_text()]
			assert_eq(part.status, full.status, label)
			assert_eq(_text(part.voltage_across(id)), _text(full.voltage_across(id)), label)
			assert_eq(_text(part.current_through(id)), _text(full.current_through(id)), label)
			assert_eq(_text(part.power_of(id)), _text(full.power_of(id)), label)
			assert_eq(part.meter_state(id), full.meter_state(id), label)
			assert_eq(_text(part.meter_reading(id)), _text(full.meter_reading(id)), label)
			assert_eq(part.device_state(id), full.device_state(id), label)
			compared += 1
		assert_eq(net.to_text(), net.duplicate_network().to_text())
	assert_true(compared > 400, "compared %d" % compared)
