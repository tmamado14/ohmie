class_name Hurtbox
extends Area2D
## The dangerous part of an enemy or hazard. Sits on physics layer 5
## (`hazard`) and watches layer 3 (`player`).
##
## Emits `touched` in every physics frame in which a body overlaps it, not just
## when the body enters, so whoever listens decides what one contact means (the
## room ignores touches while Ohmie is already zapped or invulnerable, and a
## body still inside when that ends is zapped again).

signal touched(body: Node2D)


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	for body: Node2D in get_overlapping_bodies():
		touched.emit(body)
