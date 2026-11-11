class_name SfxPlayer
extends Node
## Autoload `Sfx`: plays short sound effects by name from a small pool of
## players, and loops the background music quietly.
##
## Usage: Sfx.play(&"jump"). Scripts that may be compiled before autoloads
## exist (anything a --script tool or test loads) look it up at AUTOLOAD_PATH. Sound n is res://assets/audio/sfx_<n>.wav.
## Gameplay objects never call this; the room connects their signals to it.
##
## A stream still playing when the engine shuts down is reported as leaked,
## so audio is stopped on a window close request, and tools that quit by
## script call stop_all() and wait a few frames first. Silent when the display
## server is headless (tests and tools), where the dummy audio driver never
## releases a playing stream.

const SOUND_NAMES: Array[StringName] = [
	&"jump", &"land", &"pickup", &"place_resistor", &"invalid", &"connect", &"door_open", &"win",
]
const SOUND_PATH: String = "res://assets/audio/sfx_%s.wav"
const MUSIC_PATH: String = "res://assets/audio/music_copper_works_loop_16s.wav"
const POOL_SIZE: int = 6
const AUTOLOAD_PATH: NodePath = ^"/root/Sfx"
const HEADLESS_DISPLAY: String = "headless"

@export var music_volume_db: float = -18.0
@export var effects_volume_db: float = 0.0

var _streams: Dictionary = {}  # StringName -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music: AudioStreamPlayer = null
var _enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = DisplayServer.get_name() != HEADLESS_DISPLAY
	for sound: StringName in SOUND_NAMES:
		var stream: AudioStream = load(SOUND_PATH % sound) as AudioStream
		if stream == null:
			push_error("Sfx: could not load %s" % (SOUND_PATH % sound))
			continue
		_streams[sound] = stream
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Effect%d" % i
		player.volume_db = effects_volume_db
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = music_volume_db
	_music.stream = load(MUSIC_PATH) as AudioStream
	add_child(_music)
	if _enabled and _music.stream != null:
		_music.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all()


## Stops the music and every effect.
func stop_all() -> void:
	if _music != null:
		_music.stop()
	for player: AudioStreamPlayer in _pool:
		player.stop()


## Plays one of SOUND_NAMES. Uses an idle pool player, or the oldest one.
func play(sound: StringName) -> void:
	if not _streams.has(sound):
		push_error("Sfx.play: unknown sound '%s'" % sound)
		return
	if not _enabled:
		return
	var player: AudioStreamPlayer = _idle_player()
	player.stream = _streams[sound]
	player.play()


func _idle_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _pool:
		if not player.playing:
			return player
	var oldest: AudioStreamPlayer = _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	return oldest
