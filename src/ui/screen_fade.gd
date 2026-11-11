class_name ScreenFade
extends CanvasLayer
## The shared transition layer: every screen change fades to near-black,
## swaps the scene, and fades back in. One instance lives under the tree's root
## (outside the current scene, so it survives the swap), created on first use
## by go_to(). Works the same in the game and in scripts started with --script.
##
## While a change is under way is_busy() is true and the layer swallows mouse
## input; screens also ignore their keys then.

## Emitted when a change has finished fading back in.
signal finished

const BOOT: String = "res://scenes/boot.tscn"
const SPLASH: String = "res://scenes/ui/splash.tscn"
const TITLE: String = "res://scenes/ui/title.tscn"
const WORLD_SELECT: String = "res://scenes/ui/world_select.tscn"
const LEVEL_SELECT: String = "res://scenes/ui/level_select.tscn"
const GAME: String = "res://scenes/main.tscn"

const NODE_NAME: String = "ScreenFade"
const LAYER_INDEX: int = 100
const FADE_SECONDS: float = 0.25
const COVER_COLOR: Color = Color("0d0907")
## Frames to wait after the swap so the new scene has drawn once before it is revealed.
const SETTLE_FRAMES: int = 2

var _rect: ColorRect = null
var _busy: bool = false


func _init() -> void:
	name = NODE_NAME
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Cover"
	_rect.color = Color(COVER_COLOR, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Fades out, loads the scene at `path`, and fades in over `reveal_seconds`.
## Ignored while another change is under way.
static func go_to(tree: SceneTree, path: String, reveal_seconds: float = FADE_SECONDS) -> void:
	var fade: ScreenFade = instance(tree)
	fade.change_scene(path, reveal_seconds)


## True while a scene change is fading.
static func is_busy(tree: SceneTree) -> bool:
	var fade: ScreenFade = tree.root.get_node_or_null(NODE_NAME) as ScreenFade
	return fade != null and fade._busy


## The tree's transition layer, created if needed.
static func instance(tree: SceneTree) -> ScreenFade:
	var fade: ScreenFade = tree.root.get_node_or_null(NODE_NAME) as ScreenFade
	if fade == null:
		fade = ScreenFade.new()
		tree.root.add_child(fade)
	return fade


func change_scene(path: String, reveal_seconds: float = FADE_SECONDS) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, FADE_SECONDS)
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("ScreenFade: could not change to '%s' (%s)" % [path, error_string(err)])
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await _fade_to(0.0, reveal_seconds)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	finished.emit()


func _fade_to(alpha: float, seconds: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "color:a", alpha, seconds)
	await tween.finished
