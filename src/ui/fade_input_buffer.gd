class_name FadeInputBuffer
extends RefCounted
## Remembers one key a screen would act on (for example Esc or Enter) that was
## pressed while ScreenFade was still revealing that screen, so the press is
## acted on when the fade ends instead of being lost. One action, not a queue:
## the first press is kept and later ones are ignored until it is taken.
## Presses during the fade OUT of a screen are never kept.

var _actions: PackedStringArray = PackedStringArray()
var _event: InputEvent = null


## `actions`: the input actions worth remembering.
func _init(actions: PackedStringArray) -> void:
	_actions = actions


## Keeps `event` when it presses one of the actions, `tree`'s ScreenFade is
## revealing the current screen and nothing is kept yet. Returns true if kept.
func offer(tree: SceneTree, event: InputEvent) -> bool:
	if _event != null or not ScreenFade.is_revealing(tree):
		return false
	for action: String in _actions:
		if event.is_action_pressed(action):
			_event = event
			return true
	return false


## The kept event, or null; clears it.
func take() -> InputEvent:
	var event: InputEvent = _event
	_event = null
	return event


func has_event() -> bool:
	return _event != null
