extends Control
## The workshop background behind every menu: the art scaled to the screen,
## a uniform warm dim (`dim`, 0..1) so text reads, and a soft vignette.

@export_range(0.0, 1.0) var dim: float = 0.3

@onready var _dim: ColorRect = $Dim


func _ready() -> void:
	_dim.color.a = dim
