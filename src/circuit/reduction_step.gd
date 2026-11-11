class_name ReductionStep
extends RefCounted
## One step of a series-parallel reduction, recorded by CircuitSolver.
##
## PRUNE: one edge that cannot carry current is removed. input_ids holds it,
## output_id is "" and output_value is null; node_a/node_b are the removed
## edge's nodes.
## PARALLEL / SERIES: two edges are replaced by one new edge with a generated
## id (output_id) and value (output_value) between node_a and node_b.
## Node names are after wire merging (each wire-joined group of nodes is named
## by its alphabetically smallest member).

enum Kind { PRUNE, PARALLEL, SERIES }

var kind: Kind = Kind.PRUNE
var input_ids: Array[String] = []
var input_values: Array[Rational] = []
var output_id: String = ""
var output_value: Rational = null
var node_a: String = ""
var node_b: String = ""


## One-line description, for example "PARALLEL R1=2 R2=2 -> m1=1 (A-B)".
func to_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(Kind.keys()[kind])
	for i: int in input_ids.size():
		var value_text: String = input_values[i].to_text() if i < input_values.size() else "?"
		parts.append("%s=%s" % [input_ids[i], value_text])
	if kind != Kind.PRUNE:
		parts.append("-> %s=%s" % [output_id, output_value.to_text()])
	parts.append("(%s-%s)" % [node_a, node_b])
	return " ".join(parts)
