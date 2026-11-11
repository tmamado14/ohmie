extends Node
## The game's main scene. Starts a menu-driven session (loads the saved
## progress, see GameSession) and hands over to the splash screen.


func _ready() -> void:
	GameSession.begin_menus()
	get_tree().change_scene_to_file.call_deferred(ScreenFade.SPLASH)
