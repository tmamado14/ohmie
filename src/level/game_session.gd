class_name GameSession
extends RefCounted
## Session state shared by the menus and the room, kept in static variables
## so it survives scene changes without an autoload (scripts started with
## --script cannot see autoloads).
##
## - `from_menus`: true once the boot scene has run. Only then does the room
##   offer Esc back to the map and use the menu victory lines.
## - `save_path`: where begin_menus() loads and saves progress. Tests and tools
##   point it at a temporary file before loading the boot scene.
## - `world_id`, `room_file`: the world and room the player last chose, so the
##   room knows what to load and the menus can return to the same place.
## - progress(): the saved progress after begin_menus(), otherwise an in-memory
##   Progress, so nothing started without the menus touches the real save.

static var from_menus: bool = false
static var save_path: String = Progress.DEFAULT_PATH
static var world_id: String = ""
static var room_file: String = ""

static var _progress: Progress = null


## Called by the boot scene: loads progress from `save_path` and marks the session as menu-driven.
static func begin_menus() -> void:
	from_menus = true
	_progress = ProgressStore.load_from(save_path)


## The session's progress (in memory only unless begin_menus() ran).
static func progress() -> Progress:
	if _progress == null:
		_progress = Progress.new()
	return _progress


## Back to the state of a fresh start without the menus.
static func reset() -> void:
	from_menus = false
	save_path = Progress.DEFAULT_PATH
	world_id = ""
	room_file = ""
	_progress = null
