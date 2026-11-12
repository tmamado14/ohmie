extends SceneTree
## Deletes the real save (Progress.DEFAULT_PATH, user://progress.json) so the
## next run of the game starts as a fresh first run, for recording footage.
## Refuses to do anything unless the only argument after `--` is `--yes`.
## Tests must never call this tool.
##
## Usage:
##   godot --headless --path . --script res://tools/reset_progress.gd -- --yes

const CONFIRM_ARGUMENT: String = "--yes"


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] != CONFIRM_ARGUMENT:
		printerr("reset_progress: refusing to run. Pass exactly '-- %s' to delete %s (got: %s)"
				% [CONFIRM_ARGUMENT, Progress.DEFAULT_PATH, " ".join(args) if not args.is_empty() else "no arguments"])
		return 2
	var path: String = ProjectSettings.globalize_path(Progress.DEFAULT_PATH)
	if not FileAccess.file_exists(Progress.DEFAULT_PATH):
		print("reset_progress: no save at %s; nothing to delete. The next run is a first run." % path)
		return 0
	var err: Error = DirAccess.remove_absolute(path)
	if err != OK:
		printerr("reset_progress: could not delete %s (%s)" % [path, error_string(err)])
		return 1
	print("reset_progress: deleted %s. The next run is a first run." % path)
	return 0
