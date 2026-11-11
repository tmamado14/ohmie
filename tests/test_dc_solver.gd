extends TestCase
## Tests for DcSolver and DcSolution. Every expected value is exact and derived
## by hand in the comments.

const ReferenceMna: GDScript = preload("res://tests/dc_reference_mna.gd")

const OK: DcSolution.Status = DcSolution.Status.OK
const SHORT: DcSolution.Status = DcSolution.Status.SHORT
const INDETERMINATE: DcSolution.Status = DcSolution.Status.INDETERMINATE
const ERROR: DcSolution.Status = DcSolution.Status.ERROR
const VALUE: DcSolution.MeterState = DcSolution.MeterState.VALUE
const OPEN: DcSolution.MeterState = DcSolution.MeterState.OPEN
const INVALID: DcSolution.MeterState = DcSolution.MeterState.INVALID
const NOT_A_METER: DcSolution.MeterState = DcSolution.MeterState.NOT_A_METER
const INT_MAX: int = 9223372036854775807


func _q(text: String) -> Rational:
	return Rational.parse(text)


## Builds a network from rows: ["wire", id, a, b], ["r", id, a, b, ohms],
## ["v", id, plus, minus, volts], ["am", id, a, b], ["vm", id, a, b],
## ["om", id, a, b].
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
	return net


## Every value of a solution as text, for comparing two solves.
func _dump(net: DcNetwork, sol: DcSolution) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("status %s %s" % [sol.status_text(), sol.error_message])
	for node: String in net.get_nodes():
		lines.append("node %s %s" % [node, _text(sol.node_voltage(node))])
	for id: String in net.get_element_ids():
		lines.append("%s v=%s i=%s p=%s m=%d r=%s" % [id, _text(sol.voltage_across(id)),
				_text(sol.current_through(id)), _text(sol.power_of(id)),
				sol.meter_state(id), _text(sol.meter_reading(id))])
	lines.append("energized %s" % sol.is_energized())
	return "\n".join(lines)


func _text(value: Rational) -> String:
	return "null" if value == null else value.to_text()


# --- basic circuits ----------------------------------------------------------------

## 6 V source (+ at p, - at g), ammeter p -> a, 3 ohm a -> g.
func _six_volts_three_ohms(ammeter_from: String, ammeter_to: String) -> DcNetwork:
	return _net([["v", "B1", "p", "g", "6"], ["am", "AM", ammeter_from, ammeter_to],
			["r", "R1", "a", "g", "3"]])


func test_six_volts_across_three_ohms() -> void:
	var sol: DcSolution = DcSolver.solve(_six_volts_three_ohms("p", "a"))
	assert_eq(sol.status, OK)
	assert_true(sol.is_ok())
	assert_eq(sol.status_text(), "OK")
	assert_eq(sol.error_message, "")
	assert_eq(sol.meter_state("AM"), VALUE)
	assert_rational_eq(sol.meter_reading("AM"), "2", "ammeter")
	assert_rational_eq(sol.current_through("AM"), "2", "ammeter current")
	assert_rational_eq(sol.voltage_across("AM"), "0", "ideal ammeter drops nothing")
	assert_rational_eq(sol.power_of("AM"), "0")
	assert_rational_eq(sol.current_through("R1"), "2", "resistor current")
	assert_rational_eq(sol.voltage_across("R1"), "6", "resistor voltage")
	assert_rational_eq(sol.power_of("R1"), "12", "resistor power")
	assert_rational_eq(sol.voltage_across("B1"), "6", "source voltage")
	assert_rational_eq(sol.current_through("B1"), "2", "source delivers 2 A")
	assert_rational_eq(sol.power_of("B1"), "12", "source delivers 12 W")
	assert_true(sol.is_energized())
	# Ground is the alphabetically smallest node, a (joined to p by the ammeter).
	assert_rational_eq(sol.node_voltage("a"), "0")
	assert_rational_eq(sol.node_voltage("p"), "0")
	assert_rational_eq(sol.node_voltage("g"), "-6")


func test_reversed_ammeter_reads_negative() -> void:
	var sol: DcSolution = DcSolver.solve(_six_volts_three_ohms("a", "p"))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("AM"), "-2")
	assert_rational_eq(sol.current_through("R1"), "2")


func test_reversed_source_still_delivers_positive_current() -> void:
	# + at g, - at p: V(p) = -6, the resistor current p -> g is -2, and the
	# source still powers the load: it delivers +2 A and +12 W.
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "g", "p", "6"], ["r", "R1", "p", "g", "3"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.node_voltage("p"), "-6")
	assert_rational_eq(sol.current_through("R1"), "-2")
	assert_rational_eq(sol.power_of("R1"), "12", "resistor power is never negative")
	assert_rational_eq(sol.current_through("B1"), "2")
	assert_rational_eq(sol.power_of("B1"), "12")
	assert_rational_eq(sol.voltage_across("B1"), "6")


func test_series_with_voltmeter() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"],
			["r", "R1", "p", "m", "2"], ["r", "R2", "m", "g", "4"],
			["vm", "VM", "m", "g"], ["vm", "VMR", "g", "m"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("R1"), "1")
	assert_rational_eq(sol.current_through("R2"), "1")
	assert_eq(sol.meter_state("VM"), VALUE)
	assert_rational_eq(sol.meter_reading("VM"), "4")
	assert_rational_eq(sol.meter_reading("VMR"), "-4")
	assert_rational_eq(sol.voltage_across("VM"), "4")
	assert_rational_eq(sol.current_through("VM"), "0", "an ideal voltmeter draws nothing")
	assert_rational_eq(sol.power_of("VM"), "0")


func test_parallel_branches() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["am", "AM", "p", "t"],
			["r", "R1", "t", "g", "2"], ["r", "R2", "t", "g", "3"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("AM"), "5")
	assert_rational_eq(sol.current_through("R1"), "3")
	assert_rational_eq(sol.current_through("R2"), "2")
	assert_rational_eq(sol.current_through("B1"), "5")
	assert_rational_eq(sol.power_of("B1"), "30")


func test_voltage_divider() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"],
			["r", "TOP", "p", "m", "4"], ["r", "LOW", "m", "g", "2"]]))
	assert_rational_eq(sol.voltage_across("LOW"), "2")
	assert_rational_eq(sol.voltage_across("TOP"), "4")


func test_series_sources_add() -> void:
	# 3 V (g -> x) then 6 V (x -> p): V(p) = 9 across 3 ohm -> 3 A.
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "x", "g", "3"],
			["v", "B2", "p", "x", "6"], ["r", "R", "p", "g", "3"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.node_voltage("p"), "9")
	assert_rational_eq(sol.current_through("R"), "3")
	assert_rational_eq(sol.current_through("B1"), "3")
	assert_rational_eq(sol.current_through("B2"), "3")


func test_opposing_sources_subtract() -> void:
	# B1 reversed (+ at g): V(x) = -3, V(p) = 3 -> 1 A clockwise p -> g.
	# The loop current enters B1 at its plus terminal, so B1 is being charged:
	# it delivers -1 A and -3 W. B2 delivers 6 W; the resistor takes 3 W.
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "g", "x", "3"],
			["v", "B2", "p", "x", "6"], ["r", "R", "p", "g", "3"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("R"), "1")
	assert_rational_eq(sol.current_through("B2"), "1")
	assert_rational_eq(sol.current_through("B1"), "-1")
	assert_rational_eq(sol.power_of("B1"), "-3")
	assert_rational_eq(sol.power_of("B2"), "6")
	assert_rational_eq(sol.power_of("R"), "3")


func test_fractions_stay_exact() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "5"], ["r", "R1", "p", "g", "3"]]))
	assert_rational_eq(sol.current_through("R1"), "5/3")
	assert_rational_eq(sol.power_of("R1"), "25/3")
	# 1/3 + 2/3 in series on 1 V: exactly 1 A.
	var series: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "1"],
			["r", "R1", "p", "m", "1/3"], ["r", "R2", "m", "g", "2/3"]]))
	assert_rational_eq(series.current_through("R1"), "1")
	assert_rational_eq(series.voltage_across("R1"), "1/3")


# --- open, short, indeterminate -----------------------------------------------------

func test_open_loop_is_ok_with_no_current() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["am", "AM", "p", "a"],
			["r", "R1", "a", "m", "3"], ["vm", "VM", "m", "g"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("AM"), "0")
	assert_rational_eq(sol.current_through("R1"), "0")
	assert_rational_eq(sol.current_through("B1"), "0")
	assert_rational_eq(sol.meter_reading("VM"), "6", "a dead end sits at the source voltage")
	assert_rational_eq(sol.node_voltage("m"), "0", "a is the ground; m is joined to it through R1")
	assert_false(sol.is_energized())


func test_zero_volt_source_is_ok_but_not_energized() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "0"], ["r", "R1", "p", "g", "3"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("R1"), "0")
	assert_false(sol.is_energized())


func test_battery_shorted_by_wire() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["wire", "W", "p", "g"],
			["r", "R1", "p", "g", "3"], ["am", "AM", "p", "a"], ["vm", "VM", "p", "g"]]))
	assert_eq(sol.status, SHORT)
	assert_eq(sol.status_text(), "SHORT")
	assert_false(sol.is_ok())
	assert_false(sol.is_energized())
	assert_null(sol.current_through("R1"))
	assert_null(sol.voltage_across("R1"))
	assert_null(sol.power_of("B1"))
	assert_null(sol.node_voltage("p"))
	assert_eq(sol.meter_state("AM"), INVALID)
	assert_eq(sol.meter_state("VM"), INVALID)
	assert_null(sol.meter_reading("AM"))
	assert_null(sol.meter_reading("VM"))


func test_battery_shorted_by_ammeter() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["am", "AM", "p", "g"]]))
	assert_eq(sol.status, SHORT)
	assert_eq(sol.meter_state("AM"), INVALID)


func test_battery_with_both_ends_on_one_node() -> void:
	assert_eq(DcSolver.solve(_net([["v", "B1", "p", "p", "5"]])).status, SHORT)
	assert_eq(DcSolver.solve(_net([["v", "B1", "p", "p", "0"]])).status, INDETERMINATE)


func test_zero_volt_battery_shorted_is_indeterminate() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "0"], ["wire", "W", "p", "g"]]))
	assert_eq(sol.status, INDETERMINATE)


func test_different_batteries_in_parallel_short() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["v", "B2", "p", "g", "3"],
			["r", "R1", "p", "g", "3"]]))
	assert_eq(sol.status, SHORT)


func test_equal_batteries_in_parallel_are_indeterminate() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["v", "B2", "p", "g", "6"],
			["r", "R1", "p", "g", "3"]]))
	assert_eq(sol.status, INDETERMINATE)
	assert_eq(sol.status_text(), "INDETERMINATE")
	assert_null(sol.current_through("R1"))
	assert_null(sol.current_through("B1"))


func test_two_ammeters_in_parallel_are_indeterminate() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["am", "AM1", "p", "a"],
			["am", "AM2", "p", "a"], ["r", "R1", "a", "g", "3"]]))
	assert_eq(sol.status, INDETERMINATE)
	assert_eq(sol.meter_state("AM1"), INVALID)
	assert_null(sol.meter_reading("AM2"))


func test_short_wins_over_indeterminate() -> void:
	# A consistent loop (two equal sources) and an inconsistent one (shorted 3 V).
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["v", "B2", "p", "g", "6"],
			["v", "B3", "x", "y", "3"], ["wire", "W", "x", "y"]]))
	assert_eq(sol.status, SHORT)


# --- components ----------------------------------------------------------------------

func test_floating_component_without_source() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["r", "R1", "p", "g", "3"],
			["r", "R2", "x", "y", "5"], ["vm", "VM", "p", "x"], ["vm", "VMX", "x", "y"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("R1"), "2")
	assert_rational_eq(sol.current_through("R2"), "0")
	assert_rational_eq(sol.node_voltage("x"), "0")
	assert_rational_eq(sol.node_voltage("y"), "0")
	assert_eq(sol.meter_state("VM"), OPEN, "voltmeter between two unconnected parts")
	assert_null(sol.meter_reading("VM"))
	assert_null(sol.voltage_across("VM"))
	assert_rational_eq(sol.current_through("VM"), "0")
	assert_eq(sol.meter_state("VMX"), VALUE)
	assert_rational_eq(sol.meter_reading("VMX"), "0")


func test_two_powered_components_each_have_their_own_ground() -> void:
	# Second circuit: 4 V with + at x; its ground is x (smaller than y), so
	# V(y) = -4 and the 2 ohm resistor x -> y carries 2 A.
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["r", "R1", "p", "g", "3"],
			["v", "B2", "x", "y", "4"], ["r", "R2", "x", "y", "2"], ["vm", "VM", "g", "y"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.node_voltage("x"), "0")
	assert_rational_eq(sol.node_voltage("y"), "-4")
	assert_rational_eq(sol.current_through("R2"), "2")
	assert_rational_eq(sol.current_through("R1"), "2")
	assert_eq(sol.meter_state("VM"), OPEN)


func test_voltmeter_on_unused_nodes() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["r", "R1", "p", "g", "3"],
			["vm", "VZ", "p", "z"], ["vm", "VZZ", "z", "z"]]))
	assert_eq(sol.meter_state("VZ"), OPEN)
	assert_eq(sol.meter_state("VZZ"), VALUE)
	assert_rational_eq(sol.meter_reading("VZZ"), "0")
	assert_rational_eq(sol.node_voltage("z"), "0")


func test_wire_merged_nodes_share_a_voltage() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "p", "g", "6"], ["wire", "W", "p", "q"],
			["r", "R1", "q", "g", "3"]]))
	assert_rational_eq(sol.node_voltage("q"), "6")
	assert_rational_eq(sol.voltage_across("W"), "0")
	assert_null(sol.current_through("W"), "wire currents are not tracked")
	assert_null(sol.power_of("W"))
	assert_rational_eq(sol.current_through("R1"), "2")


func test_empty_network() -> void:
	var sol: DcSolution = DcSolver.solve(DcNetwork.new())
	assert_eq(sol.status, OK)
	assert_false(sol.is_energized())


func test_null_network_is_an_error() -> void:
	var sol: DcSolution = DcSolver.solve(null)
	assert_error_pushed("network is null")
	assert_eq(sol.status, ERROR)
	assert_true(sol.error_message.contains("network is null"))


# --- bridges and multi-loop circuits --------------------------------------------------

## Supply s (+) to b (-), supply ammeter s -> t, arms t-l, t-r, l-b, r-b, and
## a bridge ammeter l -> r.
func _bridge(r1: String, r2: String, r3: String, r4: String) -> DcNetwork:
	return _net([["v", "B1", "s", "b", "6"], ["am", "AMS", "s", "t"],
			["r", "R1", "t", "l", r1], ["r", "R2", "t", "r", r2],
			["r", "R3", "l", "b", r3], ["r", "R4", "r", "b", r4], ["am", "AMB", "l", "r"]])


func test_balanced_wheatstone_bridge() -> void:
	# 1/2 = 2/4: no bridge current. Branches 1+2 = 3 and 2+4 = 6 in parallel
	# give 2 ohm, so 6 V drives 3 A.
	var sol: DcSolution = DcSolver.solve(_bridge("1", "2", "2", "4"))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("AMB"), "0")
	assert_rational_eq(sol.meter_reading("AMS"), "3")
	assert_rational_eq(sol.current_through("R1"), "2")
	assert_rational_eq(sol.current_through("R2"), "1")


func test_unbalanced_wheatstone_bridge() -> void:
	# The ideal bridge ammeter joins l and r into one node M.
	# t-M: 1 || 2 = 2/3. M-b: 3 || 4 = 12/7. Total 2/3 + 12/7 = 50/21.
	# Supply: 6 / (50/21) = 63/25 A. V(t) - V(M) = 63/25 * 2/3 = 42/25, so
	# R1 carries 42/25 and R2 21/25. V(M) - V(b) = 63/25 * 12/7 = 108/25, so
	# R3 carries 36/25 and R4 27/25. KCL at l: 42/25 in, 36/25 out through R3,
	# so 6/25 flows l -> r through the bridge.
	var sol: DcSolution = DcSolver.solve(_bridge("1", "2", "3", "4"))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("AMS"), "63/25")
	assert_rational_eq(sol.meter_reading("AMB"), "6/25")
	assert_rational_eq(sol.current_through("R1"), "42/25")
	assert_rational_eq(sol.current_through("R2"), "21/25")
	assert_rational_eq(sol.current_through("R3"), "36/25")
	assert_rational_eq(sol.current_through("R4"), "27/25")
	assert_rational_eq(sol.current_through("B1"), "63/25")


func test_two_loops_with_shared_resistor() -> void:
	# B1 10 V (a+, g-) through R1 2 ohm a -> j; B2 5 V (b+, g-) through R2 1 ohm
	# b -> j; R3 4 ohm j -> g shared.
	# KCL at j: (10 - V)/2 + (5 - V)/1 = V/4  =>  40 = 7V  =>  V(j) = 40/7.
	# I1 = (10 - 40/7)/2 = 15/7, I2 = 5 - 40/7 = -5/7, I3 = 10/7.
	var sol: DcSolution = DcSolver.solve(_net([["v", "B1", "a", "g", "10"], ["v", "B2", "b", "g", "5"],
			["r", "R1", "a", "j", "2"], ["r", "R2", "b", "j", "1"], ["r", "R3", "j", "g", "4"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.voltage_across("R3"), "40/7", "V(j) - V(g)")
	assert_rational_eq(sol.node_voltage("j"), "-30/7", "relative to the ground a, which is at +10 V over g")
	assert_rational_eq(sol.current_through("R1"), "15/7")
	assert_rational_eq(sol.current_through("R2"), "-5/7")
	assert_rational_eq(sol.current_through("R3"), "10/7")
	assert_rational_eq(sol.current_through("B1"), "15/7")
	assert_rational_eq(sol.current_through("B2"), "-5/7", "B2 is being charged")
	# Kirchhoff's current law at j: in through R1 and R2 equals out through R3.
	var into_j: Rational = sol.current_through("R1").add(sol.current_through("R2"))
	assert_true(into_j.equals(sol.current_through("R3")), "KCL at j")
	# Power balance: sources deliver what the resistors dissipate.
	var delivered: Rational = sol.power_of("B1").add(sol.power_of("B2"))
	var dissipated: Rational = sol.power_of("R1").add(sol.power_of("R2")).add(sol.power_of("R3"))
	assert_true(delivered.equals(dissipated), "power balance")


# --- ohmmeters ---------------------------------------------------------------------------

func test_ohmmeter_two_in_parallel() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "b", "2"], ["r", "R2", "a", "b", "2"],
			["om", "OM", "a", "b"]]))
	assert_eq(sol.meter_state("OM"), VALUE)
	assert_rational_eq(sol.meter_reading("OM"), "1")
	assert_rational_eq(sol.current_through("OM"), "0")
	assert_rational_eq(sol.power_of("OM"), "0")


func test_ohmmeter_half_plus_parallel_pair() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "m", "1/2"], ["r", "R2", "m", "b", "1"],
			["r", "R3", "m", "b", "1"], ["om", "OM", "a", "b"]]))
	assert_rational_eq(sol.meter_reading("OM"), "1")


func test_ohmmeter_open() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "m", "2"], ["r", "R2", "b", "n", "2"],
			["om", "OM", "a", "b"], ["om", "OMZ", "a", "z"]]))
	assert_eq(sol.meter_state("OM"), OPEN)
	assert_null(sol.meter_reading("OM"))
	assert_eq(sol.meter_state("OMZ"), OPEN, "a node nothing else touches")


func test_ohmmeter_across_wire_and_same_node() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["wire", "W", "a", "b"], ["r", "R1", "a", "b", "5"],
			["om", "OM", "a", "b"], ["om", "OMS", "c", "c"]]))
	assert_eq(sol.meter_state("OM"), VALUE)
	assert_rational_eq(sol.meter_reading("OM"), "0")
	assert_eq(sol.meter_state("OMS"), VALUE)
	assert_rational_eq(sol.meter_reading("OMS"), "0")


func test_ohmmeter_treats_sources_and_ammeters_as_wires() -> void:
	# Dead network: B1 joins m and b, AM joins b and c. So R1 (a-m) and R2 (a-c)
	# are in parallel between a and b: 2 || 2 = 1.
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "m", "2"], ["v", "B1", "m", "b", "9"],
			["am", "AM", "b", "c"], ["r", "R2", "a", "c", "2"], ["om", "OM", "a", "b"]]))
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.meter_reading("OM"), "1")


func test_ohmmeter_treats_voltmeters_and_other_ohmmeters_as_open() -> void:
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "m", "2"], ["vm", "VM", "m", "b"],
			["om", "OM2", "m", "b"], ["om", "OM", "a", "b"]]))
	assert_eq(sol.meter_state("OM"), OPEN)


func test_ohmmeter_works_while_live_circuit_is_short() -> void:
	# The wire shorts the battery (SHORT), but the dead network is the same as
	# above: 2 || 2 = 1.
	var sol: DcSolution = DcSolver.solve(_net([["r", "R1", "a", "m", "2"], ["v", "B1", "m", "b", "9"],
			["wire", "W", "m", "b"], ["r", "R2", "a", "b", "2"], ["om", "OM", "a", "b"],
			["am", "AM", "a", "x"]]))
	assert_eq(sol.status, SHORT)
	assert_eq(sol.meter_state("OM"), VALUE)
	assert_rational_eq(sol.meter_reading("OM"), "1")
	assert_eq(sol.meter_state("AM"), INVALID)


func test_ohmmeter_on_unbalanced_bridge() -> void:
	# Arms t-l 1, t-r 2, l-b 3, r-b 4, bridge l-r 5. Ground b, inject 1 A at t:
	#   l: 23 Vl - 15 Vt - 3 Vr = 0,  r: 19 Vr - 10 Vt - 4 Vl = 0
	#   => Vr = 58/85 Vt, Vl = 63/85 Vt
	#   t: (Vt - Vl) + (Vt - Vr)/2 = 1 => 71/170 Vt = 1 => R = 170/71.
	var rows: Array = [["r", "R1", "t", "l", "1"], ["r", "R2", "t", "r", "2"],
			["r", "R3", "l", "b", "3"], ["r", "R4", "r", "b", "4"], ["r", "R5", "l", "r", "5"],
			["om", "OM", "t", "b"]]
	var sol: DcSolution = DcSolver.solve(_net(rows))
	assert_rational_eq(sol.meter_reading("OM"), "170/71")
	# Cross-check through the live solver: 1 V across the bridge draws 71/170 A.
	rows.append(["v", "B1", "s", "b", "1"])
	rows.append(["am", "AM", "s", "t"])
	var live: DcSolution = DcSolver.solve(_net(rows))
	assert_rational_eq(live.meter_reading("AM"), "71/170")


## [id, a, b] is a wire, [id, a, b, ohms] a resistor. Terminals A and B.
func _series_parallel_cases() -> Array:
	return [
		[["R1", "A", "B", "5/2"]],
		[["R1", "A", "C", "1"], ["R2", "C", "B", "2"]],
		[["R1", "A", "B", "3"], ["R2", "A", "B", "6"]],
		[["R1", "A", "C", "1"], ["R2", "C", "B", "2"], ["R3", "C", "B", "2"], ["R4", "A", "B", "3"]],
		[["R1", "A", "C", "1/2"], ["W", "C", "D"], ["R2", "D", "B", "1/2"], ["R3", "D", "B", "1/3"]],
		[["R1", "A", "B", "2"], ["R2", "B", "E", "7"]],
		[["R1", "A", "C", "1"], ["R2", "B", "D", "3"]],
		[["W", "A", "B"], ["R1", "A", "B", "4"]],
		# A-C 1, then (C-D 2 + (3 || 6)) || C-B 4 = 2, so A-C-B = 3; || A-B 5/2 = 15/11.
		[["R1", "A", "C", "1"], ["R2", "C", "D", "2"], ["R3", "D", "B", "3"], ["R4", "D", "B", "6"],
				["R5", "C", "B", "4"], ["R6", "D", "D", "9"], ["R7", "A", "B", "5/2"]],
	]


func test_ohmmeter_matches_series_parallel_solver() -> void:
	var checked: int = 0
	for edges: Array in _series_parallel_cases():
		var graph: CircuitGraph = CircuitGraph.new()
		graph.set_terminals("A", "B")
		var net: DcNetwork = DcNetwork.new()
		net.add_ohmmeter("OM", "A", "B")
		for edge: Array in edges:
			if edge.size() == 3:
				graph.add_wire(edge[0], edge[1], edge[2])
				net.add_wire(edge[0], edge[1], edge[2])
			else:
				graph.add_resistor(edge[0], edge[1], edge[2], _q(edge[3]))
				net.add_resistor(edge[0], edge[1], edge[2], _q(edge[3]))
		var expected: CircuitResult = CircuitSolver.solve(graph)
		var sol: DcSolution = DcSolver.solve(net)
		var label: String = str(edges)
		if expected.status == CircuitResult.Status.OPEN:
			assert_eq(sol.meter_state("OM"), OPEN, label)
		else:
			assert_eq(expected.status, CircuitResult.Status.OK, label)
			assert_eq(sol.meter_state("OM"), VALUE, label)
			assert_rational_eq(sol.meter_reading("OM"), expected.value.to_text(), label)
		checked += 1
	assert_eq(checked, 9)


# --- getters and contract ------------------------------------------------------------------

func test_unknown_ids_and_non_meters() -> void:
	var sol: DcSolution = DcSolver.solve(_six_volts_three_ohms("p", "a"))
	assert_null(sol.voltage_across("nope"))
	assert_null(sol.current_through("nope"))
	assert_null(sol.power_of("nope"))
	assert_null(sol.meter_reading("nope"))
	assert_null(sol.node_voltage("nope"))
	assert_eq(sol.meter_state("nope"), NOT_A_METER)
	assert_eq(sol.meter_state("R1"), NOT_A_METER)
	assert_null(sol.meter_reading("R1"))
	assert_eq(sol.element_kind("R1"), DcNetwork.Kind.RESISTOR)
	assert_eq(sol.element_kind("AM"), DcNetwork.Kind.AMMETER)
	assert_eq(sol.element_kind("nope"), -1)
	assert_true(sol.has_element("B1"))
	assert_false(sol.has_element("nope"))


func test_input_network_is_not_modified() -> void:
	var net: DcNetwork = _bridge("1", "2", "3", "4")
	net.add_ohmmeter("OM", "t", "b")
	net.add_wire("W", "b", "z")
	var before: String = net.to_text()
	DcSolver.solve(net)
	assert_eq(net.to_text(), before)


func test_same_network_twice_gives_identical_results() -> void:
	var net: DcNetwork = _bridge("1", "2", "3", "4")
	net.add_ohmmeter("OM", "t", "b")
	net.add_voltmeter("VM", "l", "b")
	var first: String = _dump(net, DcSolver.solve(net))
	var second: String = _dump(net, DcSolver.solve(net))
	assert_eq(first, second)
	assert_true(first.contains("AMB v=0 i=6/25"), first)


# --- overflow -----------------------------------------------------------------------------

func test_overflow_in_a_current_is_an_error() -> void:
	# V = 2^63 - 1 across 1/2 ohm: the current does not fit in 64 bits.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", Rational.new(INT_MAX))
	net.add_resistor("R1", "p", "g", Rational.new(1, 2))
	net.add_ammeter("AM", "p", "q")
	var sol: DcSolution = DcSolver.solve(net)
	assert_error_pushed("Rational.mul")
	assert_error_pushed("DcSolver.solve")
	assert_eq(sol.status, ERROR)
	assert_eq(sol.status_text(), "ERROR")
	assert_true(sol.error_message.contains("does not fit in 64 bits"), sol.error_message)
	assert_null(sol.current_through("R1"))
	assert_null(sol.node_voltage("p"))
	assert_eq(sol.meter_state("AM"), INVALID)
	assert_false(sol.is_energized())


func test_overflow_in_series_sources_is_an_error() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "x", "g", Rational.new(INT_MAX))
	net.add_voltage_source("B2", "p", "x", Rational.new(INT_MAX))
	net.add_resistor("R1", "p", "g", Rational.new(1))
	var sol: DcSolution = DcSolver.solve(net)
	assert_error_pushed("Rational.add")
	assert_error_pushed("source voltage sum")
	assert_eq(sol.status, ERROR)


func test_overflow_in_an_ohmmeter_is_invalid() -> void:
	# Two (2^63 - 1) ohm resistors in series: 2^64 - 2 ohm does not fit.
	var net: DcNetwork = DcNetwork.new()
	net.add_resistor("R1", "a", "m", Rational.new(INT_MAX))
	net.add_resistor("R2", "m", "b", Rational.new(INT_MAX))
	net.add_ohmmeter("OM", "a", "b")
	var sol: DcSolution = DcSolver.solve(net)
	assert_error_pushed("Rational.add")
	assert_error_pushed("ohmmeter 'OM'")
	assert_eq(sol.status, OK, "the live circuit itself is fine")
	assert_eq(sol.meter_state("OM"), INVALID)
	assert_null(sol.meter_reading("OM"))


func test_large_values_that_fit_stay_exact() -> void:
	# 2^61 V across 2^60 ohm: exactly 2 A and 2^62 W.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", Rational.new(2305843009213693952))
	net.add_resistor("R1", "p", "g", Rational.new(1152921504606846976))
	var sol: DcSolution = DcSolver.solve(net)
	assert_eq(sol.status, OK)
	assert_rational_eq(sol.current_through("R1"), "2")
	assert_rational_eq(sol.power_of("R1"), "4611686018427387904")
	assert_rational_eq(sol.power_of("B1"), "4611686018427387904")


# --- cross-checks against plain MNA ---------------------------------------------------------

const _RESISTANCES: Array[String] = ["1/2", "1", "2", "3", "4", "6"]
const _VOLTAGES: Array[String] = ["-2", "0", "1", "3", "5/2"]


func _random_network(rng: RandomNumberGenerator) -> DcNetwork:
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
	return net


func test_matches_plain_mna_on_random_networks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261112
	var counts: Dictionary = {"OK": 0, "SHORT": 0, "INDETERMINATE": 0}
	var energized: int = 0
	for trial: int in 400:
		var net: DcNetwork = _random_network(rng)
		var expected: Dictionary = ReferenceMna.solve(net)
		var sol: DcSolution = DcSolver.solve(net)
		var label: String = "trial %d:\n%s" % [trial, net.to_text()]
		assert_eq(sol.status_text(), String(expected["status"]), label)
		counts[sol.status_text()] = int(counts.get(sol.status_text(), 0)) + 1
		if sol.status != OK or expected["status"] != "OK":
			continue
		if sol.is_energized():
			energized += 1
		var voltages: Dictionary = expected["voltages"]
		for node: String in voltages.keys():
			assert_rational_eq(sol.node_voltage(node), (voltages[node] as Rational).to_text(), label + "\nnode " + node)
		var currents: Dictionary = expected["currents"]
		for id: String in currents.keys():
			assert_rational_eq(sol.current_through(id), (currents[id] as Rational).to_text(), label + "\nelement " + id)
	# Make sure the random sample exercised every outcome.
	assert_true(int(counts["OK"]) > 100, str(counts))
	assert_true(int(counts["SHORT"]) > 10, str(counts))
	assert_true(int(counts["INDETERMINATE"]) > 10, str(counts))
	assert_true(energized > 20, "energized: %d" % energized)


func test_partial_solve_matches_full_solve() -> void:
	# The puzzle search solves only for the elements its conditions name. That
	# must give exactly the same values as the full solve.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 777
	var compared: int = 0
	for trial: int in 150:
		var net: DcNetwork = _random_network(rng)
		var full: DcSolution = DcSolver.solve(net)
		var no_extra: Array[String] = []
		var circuit: DcSolver._Circuit = DcSolver._compile(net, no_extra)
		for id: String in net.get_element_ids():
			var part: DcSolution = DcSolver._solve_circuit(circuit, {id: true}, false)
			var label: String = "trial %d element %s:\n%s" % [trial, id, net.to_text()]
			assert_eq(part.status, full.status, label)
			assert_eq(_text(part.voltage_across(id)), _text(full.voltage_across(id)), label)
			assert_eq(_text(part.current_through(id)), _text(full.current_through(id)), label)
			assert_eq(_text(part.power_of(id)), _text(full.power_of(id)), label)
			assert_eq(part.meter_state(id), full.meter_state(id), label)
			assert_eq(_text(part.meter_reading(id)), _text(full.meter_reading(id)), label)
			compared += 1
	assert_true(compared > 500, "compared %d" % compared)
