class_name MenuSound
extends RefCounted
## Menu sounds through the Sfx autoload, looked up at its path so menus also
## work (silently) where autoloads do not exist (scripts started with --script).

const SELECT: StringName = &"switch"
const CONFIRM: StringName = &"connect"
const DENIED: StringName = &"invalid"
const MUSIC: AudioStream = preload("res://assets/audio/music_old_workshop_swing_16s.wav")


static func play(from: Node, sound: StringName) -> void:
	var sfx: SfxPlayer = _sfx(from)
	if sfx != null:
		sfx.play(sound)


## Starts the menu music (keeps it going if it is already playing).
static func play_music(from: Node) -> void:
	var sfx: SfxPlayer = _sfx(from)
	if sfx != null:
		sfx.play_music(MUSIC)


## Stops the music and every effect (before quitting, so no stream is reported as leaked).
static func stop_all(from: Node) -> void:
	var sfx: SfxPlayer = _sfx(from)
	if sfx != null:
		sfx.stop_all()


static func _sfx(from: Node) -> SfxPlayer:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
