class_name LevelGoal
extends RefCounted
## What a level asks the player to achieve, and how its readout is worded.
##
## Built from the level dictionary by `from_level`: the optional "goal" object
## wins; without it the legacy "target" field defines a resistance goal.
## Pure data: no nodes. The circuit math itself stays in src/circuit/ (this
## only compares a CircuitResult with the goal through CircuitResult's and
## OhmsLaw's API).
##
## Each goal type is one branch in `_parse_for_type`, `is_met`, `goal_label`,
## `reading_label`, `reading_caption` and `equivalent_resistance_target`. A new
## type adds a branch here; the board, HUD and door only use this API.
##
## Types:
##   resistance  {"value"}: the equivalent resistance between A and B is exactly value.
##   current     {"voltage", "value"}: a battery of `voltage` volts across A and B
##               draws exactly `value` amperes (I = V / R).

const TYPE_RESISTANCE: StringName = &"resistance"
const TYPE_CURRENT: StringName = &"current"
const OHM_SUFFIX: String = " Ω"
const AMP_SUFFIX: String = " A"
## Default mission for a resistance goal; %s is the value, e.g. "3/2".
const DEFAULT_RESISTANCE_MISSION: String = "Make exactly %s Ω between A and B."
## Default mission for a current goal; the current, then the voltage.
const DEFAULT_CURRENT_MISSION: String = "Draw exactly %s A from the %s V battery."
## Readout captions for the plaque's second row.
const CAPTION_RESISTANCE: String = "R EQ"
const CAPTION_CURRENT: String = "I"
## Current goal readouts that are not a number.
const READING_NO_CURRENT: String = "0 A"
const READING_SHORT: String = "SHORT"
## Shown by reading_label when there is no reading yet.
const NO_READING: String = "?"

var type: StringName = &""
## The player-facing sentence shown on the mission sign.
var mission: String = ""
## The exact equivalent resistance that solves a resistance goal (null otherwise).
var target: Rational = null
## The battery voltage across A and B of a current goal (null otherwise).
var voltage: Rational = null
## The exact current in amperes that solves a current goal (null otherwise).
var current: Rational = null


## Builds the goal of a level dictionary. Returns null and pushes an error when
## neither "goal" nor "target" is present or the goal is invalid.
## `source` names the origin in error messages.
static func from_level(data: Dictionary, source: String) -> LevelGoal:
	if data.has("goal"):
		return from_goal_object(data["goal"], source)
	if data.has("target"):
		if not data["target"] is String:
			push_error("LevelGoal: %s: field 'target' must be a string" % source)
			return null
		return _make_resistance(data["target"], "", source)
	push_error("LevelGoal: %s: the level needs a 'goal' object or a 'target' field" % source)
	return null


## Builds a goal from a "goal" object such as
## {"type": "resistance", "value": "1", "mission": "..."}.
static func from_goal_object(value: Variant, source: String) -> LevelGoal:
	if not value is Dictionary:
		push_error("LevelGoal: %s: field 'goal' must be an object" % source)
		return null
	var goal_dict: Dictionary = value
	if not goal_dict.get("type") is String:
		push_error("LevelGoal: %s: goal needs a string 'type'" % source)
		return null
	var mission_text: String = ""
	if goal_dict.has("mission"):
		if not goal_dict["mission"] is String:
			push_error("LevelGoal: %s: goal 'mission' must be a string" % source)
			return null
		mission_text = (goal_dict["mission"] as String).strip_edges()
	return _parse_for_type(StringName(goal_dict["type"] as String), goal_dict, mission_text, source)


## True when `result` solves the goal. Resistance: status OK and exactly the
## target. Current: status OK, resistance > 0 and V / R exactly the current.
func is_met(result: CircuitResult) -> bool:
	if result == null:
		return false
	match type:
		TYPE_RESISTANCE:
			return result.matches(target)
		TYPE_CURRENT:
			var drawn: Rational = _current_of(result)
			return drawn != null and drawn.equals(current)
	return false


## The goal in a few characters for the readout plaque, for example "1 Ω" or "2 A".
func goal_label() -> String:
	match type:
		TYPE_RESISTANCE:
			return target.to_text() + OHM_SUFFIX
		TYPE_CURRENT:
			return current.to_text() + AMP_SUFFIX
	return NO_READING


## The readout for the current circuit state. Resistance: "3/2 Ω", "OPEN",
## "???" or "ERROR". Current: "3/2 A", "0 A" (open), "SHORT", "???" or "ERROR".
func reading_label(result: CircuitResult) -> String:
	if result == null:
		return NO_READING
	match type:
		TYPE_RESISTANCE:
			if result.status == CircuitResult.Status.OK:
				return result.to_text() + OHM_SUFFIX
			return result.to_text()
		TYPE_CURRENT:
			match result.status:
				CircuitResult.Status.OK:
					var drawn: Rational = _current_of(result)
					if drawn == null:
						return READING_SHORT
					return drawn.to_text() + AMP_SUFFIX
				CircuitResult.Status.OPEN:
					return READING_NO_CURRENT
			return result.to_text()
	return NO_READING


## The caption of the plaque's reading row: "R EQ" or "I".
func reading_caption() -> String:
	match type:
		TYPE_CURRENT:
			return CAPTION_CURRENT
	return CAPTION_RESISTANCE


## The exact equivalent resistance between A and B that solves the goal
## (resistance: the target; current: V / I), or null for an unknown type.
func equivalent_resistance_target() -> Rational:
	match type:
		TYPE_RESISTANCE:
			return target
		TYPE_CURRENT:
			return OhmsLaw.resistance_for(voltage, current)
	return null


## The current drawn by a solved circuit, or null when it is not OK or R <= 0.
func _current_of(result: CircuitResult) -> Rational:
	if result.status != CircuitResult.Status.OK or result.value == null or result.value.sign() <= 0:
		return null
	return OhmsLaw.current(voltage, result.value)


static func _parse_for_type(goal_type: StringName, goal_dict: Dictionary, mission_text: String,
		source: String) -> LevelGoal:
	match goal_type:
		TYPE_RESISTANCE:
			if not goal_dict.get("value") is String:
				push_error("LevelGoal: %s: resistance goal needs a string 'value'" % source)
				return null
			return _make_resistance(goal_dict["value"], mission_text, source)
		TYPE_CURRENT:
			if not goal_dict.get("voltage") is String:
				push_error("LevelGoal: %s: current goal needs a string 'voltage'" % source)
				return null
			if not goal_dict.get("value") is String:
				push_error("LevelGoal: %s: current goal needs a string 'value'" % source)
				return null
			return _make_current(goal_dict["voltage"], goal_dict["value"], mission_text, source)
	push_error("LevelGoal: %s: goal type '%s' is not supported yet" % [source, goal_type])
	return null


static func _make_resistance(value_text: String, mission_text: String, source: String) -> LevelGoal:
	var value: Rational = _parse_positive(value_text, "resistance value", source)
	if value == null:
		return null
	var goal: LevelGoal = LevelGoal.new()
	goal.type = TYPE_RESISTANCE
	goal.target = value
	goal.mission = mission_text if not mission_text.is_empty() else DEFAULT_RESISTANCE_MISSION % value.to_text()
	return goal


static func _make_current(voltage_text: String, value_text: String, mission_text: String,
		source: String) -> LevelGoal:
	var volts: Rational = _parse_positive(voltage_text, "voltage", source)
	if volts == null:
		return null
	var amps: Rational = _parse_positive(value_text, "current value", source)
	if amps == null:
		return null
	var goal: LevelGoal = LevelGoal.new()
	goal.type = TYPE_CURRENT
	goal.voltage = volts
	goal.current = amps
	goal.mission = (mission_text if not mission_text.is_empty()
			else DEFAULT_CURRENT_MISSION % [amps.to_text(), volts.to_text()])
	return goal


## Parses an exact number > 0, or pushes an error naming `what` and returns null.
static func _parse_positive(text: String, what: String, source: String) -> Rational:
	if text.strip_edges().is_empty():
		push_error("LevelGoal: %s: the %s is empty" % [source, what])
		return null
	var value: Rational = Rational.parse(text)
	if value == null or not value.is_valid() or value.sign() <= 0:
		push_error("LevelGoal: %s: %s '%s' must be an exact number > 0" % [source, what, text])
		return null
	return value
