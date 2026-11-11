class_name RoomTheme
extends Resource
## The look and sound of one world: tiles, backdrop, music and wire colours.
## One file per world at res://resources/themes/<world>/theme.tres.

const THEME_PATH: String = "res://resources/themes/%s/theme.tres"
const DEFAULT_WORLD: String = "old_workshop"

@export var tileset: TileSet
@export var background: Texture2D
@export var background_modulate: Color = Color.WHITE
@export var music: AudioStream

@export_group("Wires")
@export var wire_normal: Color = Color("aa532c")
@export var wire_normal_outline: Color = Color("24180f")
@export var wire_closed: Color = Color("f7be5a")
@export var wire_closed_outline: Color = Color("24180f")
@export var wire_match: Color = Color("5cb29c")
@export var wire_match_outline: Color = Color("182822")


## The theme of `world`, or the default world's theme when that file does not exist.
static func load_for_world(world: String) -> RoomTheme:
	var path: String = THEME_PATH % world
	if not ResourceLoader.exists(path):
		print("RoomTheme: no theme for world '%s', using '%s'" % [world, DEFAULT_WORLD])
		path = THEME_PATH % DEFAULT_WORLD
	var theme: RoomTheme = load(path) as RoomTheme
	if theme == null:
		push_error("RoomTheme: could not load %s" % path)
	return theme
