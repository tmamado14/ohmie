class_name LevelGoal
extends RefCounted
## What a level asks for (GDD 12.3): a one-line mission for the sign and a list
## of GoalConditions, all of which must hold.
##
## Pure data and wording: every test and every text comes from GoalCondition
## (src/circuit/); this class only combines them and adds a short symbol per
## quantity for the readout plaque.

## Readout symbols, indexed by GoalCondition.Quantity.
const QUANTITY_SYMBOLS: Array[String] = ["I", "V", "R", "P"]

## The sentence on the mission sign, e.g. "Draw 2 A.".
var mission: String = ""
var conditions: Array[GoalCondition] = []


static func create(mission_text: String, goal_conditions: Array[GoalCondition]) -> LevelGoal:
	var goal: LevelGoal = LevelGoal.new()
	goal.mission = mission_text
	goal.conditions = goal_conditions.duplicate()
	return goal


## True when the circuit is solvable (status OK) and every condition holds.
## False for a null solution or a goal without conditions. Requiring status OK
## matches DcPuzzleSearch's definition of a solution: a SHORT never opens the
## door, even when an ohmmeter (which reads the dead network) would agree.
func is_met(solution: DcSolution) -> bool:
	if solution == null or not solution.is_ok() or conditions.is_empty():
		return false
	for condition: GoalCondition in conditions:
		if not condition.is_met(solution):
			return false
	return true


func condition_count() -> int:
	return conditions.size()


## "I", "V", "R" or "P" for condition `index`.
func symbol(index: int) -> String:
	return quantity_symbol(conditions[index].quantity)


static func quantity_symbol(quantity: GoalCondition.Quantity) -> String:
	return QUANTITY_SYMBOLS[quantity]


## GoalCondition.target_text of condition `index`, e.g. "2 A".
func target_text(index: int) -> String:
	return conditions[index].target_text()


## GoalCondition.reading_text of condition `index`, e.g. "3/2 A", "OL", "SHORT".
func reading_text(index: int, solution: DcSolution) -> String:
	return conditions[index].reading_text(solution)


## GoalCondition.is_met of condition `index` alone.
func is_condition_met(index: int, solution: DcSolution) -> bool:
	return conditions[index].is_met(solution)
