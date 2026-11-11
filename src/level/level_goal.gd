class_name LevelGoal
extends RefCounted
## What a level asks the player to achieve, and how its readout is worded.
##
## Built from the level dictionary by `from_level`: the optional "goal" object
## wins; without it the legacy "target" field defines a resistance goal.
## Pure data: no nodes. The circuit math itself stays in src/circuit/ (this
## only compares a CircuitResult with the goal through CircuitResult's API).
##
## Each goal type is one branch in `_parse_for_type`, `is_met`, `goal_label`
## and `reading_label`. A new type adds a branch here; the board, HUD and door
## only use this API.

const TYPE_RESISTANCE: StringName = &"resistance"
const OHM_SUFFIX: String = " Ω"
## Default mission for a resistance goal; %s is the value, e.g. "3/2".
const DEFAULT_RESISTANCE_MISSION: String = "Make exactly %s Ω between A and B."
## Shown by reading_label when there is no reading yet.
const NO_READING: String = "?"

var type: StringName = &""
## The player-facing sentence shown on the mission sign.
var mission: String = ""
## The exact equivalent resistance that solves a resistance goal.
var target: Rational = null


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


## True when `result` solves the goal. Resistance: status OK and exactly the target.
func is_met(result: CircuitResult) -> bool:
	if result == null:
		return false
	match type:
		TYPE_RESISTANCE:
			return result.matches(target)
	return false


## The goal in a few characters for the readout plaque, for example "1 Ω" or "3/2 Ω".
func goal_label() -> String:
	match type:
		TYPE_RESISTANCE:
			return target.to_text() + OHM_SUFFIX
	return NO_READING


## The readout for the current circuit state: "3/2 Ω", "OPEN", "???" or "ERROR".
func reading_label(result: CircuitResult) -> String:
	if result == null:
		return NO_READING
	match type:
		TYPE_RESISTANCE:
			if result.status == CircuitResult.Status.OK:
				return result.to_text() + OHM_SUFFIX
			return result.to_text()
	return NO_READING


static func _parse_for_type(goal_type: StringName, goal_dict: Dictionary, mission_text: String,
		source: String) -> LevelGoal:
	match goal_type:
		TYPE_RESISTANCE:
			if not goal_dict.get("value") is String:
				push_error("LevelGoal: %s: resistance goal needs a string 'value'" % source)
				return null
			return _make_resistance(goal_dict["value"], mission_text, source)
	push_error("LevelGoal: %s: goal type '%s' is not supported yet" % [source, goal_type])
	return null


static func _make_resistance(value_text: String, mission_text: String, source: String) -> LevelGoal:
	if value_text.strip_edges().is_empty():
		push_error("LevelGoal: %s: the resistance value is empty" % source)
		return null
	var value: Rational = Rational.parse(value_text)
	if value == null or not value.is_valid() or value.sign() <= 0:
		push_error("LevelGoal: %s: resistance value '%s' must be an exact number > 0" % [source, value_text])
		return null
	var goal: LevelGoal = LevelGoal.new()
	goal.type = TYPE_RESISTANCE
	goal.target = value
	goal.mission = mission_text if not mission_text.is_empty() else DEFAULT_RESISTANCE_MISSION % value.to_text()
	return goal
