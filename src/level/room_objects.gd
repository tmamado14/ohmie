class_name RoomObjects
extends Node2D
## Builds a level's bounce pads, enemies and hazards (LevelData.objects) as
## children and passes their announcements on: `touched` when any hazard
## touches a body, `bounced` when a pad launches one. It performs nothing
## itself; the room decides what a touch or a bounce does.
##
## Drawn at z 0 between the board (wires and fixed parts, earlier in the
## room) and Ohmie (added to the room later); slots and loose parts draw in
## front at z 1.

## A hazard touched `body`; `sound` is the hazard's zap sound.
signal touched(body: Node2D, sound: StringName)
## A bounce pad launches `body` from `surface_y` at `launch_speed` px/s upward.
signal bounced(body: Node2D, surface_y: float, launch_speed: float)

@export var bounce_pad_scene: PackedScene
@export var jelly_scene: PackedScene
@export var bot_scene: PackedScene
@export var spark_orb_scene: PackedScene
@export var spikes_scene: PackedScene
@export var live_wire_scene: PackedScene

var _pads: Array[BouncePad] = []
var _hazards: Array[Hazard] = []


## Instances one node per entry, in file order.
func build(entries: Array[LevelObject]) -> void:
	for i: int in entries.size():
		var entry: LevelObject = entries[i]
		var scene: PackedScene = _scene_for(entry)
		if scene == null:
			push_error("RoomObjects: no scene for %s '%s'" % [entry.type, entry.kind])
			continue
		var node: Node2D = scene.instantiate() as Node2D
		node.name = "%s_%d" % [entry.type.to_pascal_case(), i]
		add_child(node)
		var pad: BouncePad = node as BouncePad
		var hazard: Hazard = node as Hazard
		if pad != null:
			pad.setup(entry)
			pad.bounced.connect(bounced.emit)
			_pads.append(pad)
		elif hazard != null:
			hazard.setup(entry)
			hazard.touched.connect(_on_hazard_touched.bind(hazard.zap_sound))
			_hazards.append(hazard)
		else:
			push_error("RoomObjects: the scene for %s '%s' is neither a BouncePad nor a Hazard" % [
					entry.type, entry.kind])
			node.queue_free()


## Every bounce pad, in file order.
func get_pads() -> Array[BouncePad]:
	return _pads.duplicate()


## Every enemy and hazard, in file order.
func get_hazards() -> Array[Hazard]:
	return _hazards.duplicate()


func _scene_for(entry: LevelObject) -> PackedScene:
	match entry.type:
		LevelObject.TYPE_BOUNCE_PAD:
			return bounce_pad_scene
		LevelObject.TYPE_PATROLLER:
			return jelly_scene if entry.kind == LevelObject.KIND_JELLY else bot_scene
		LevelObject.TYPE_FLOATER:
			return spark_orb_scene
		LevelObject.TYPE_HAZARD:
			return spikes_scene if entry.kind == LevelObject.KIND_SPIKES else live_wire_scene
	return null


func _on_hazard_touched(body: Node2D, sound: StringName) -> void:
	touched.emit(body, sound)
