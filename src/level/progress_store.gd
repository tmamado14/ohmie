class_name ProgressStore
extends RefCounted
## Reads and writes Progress as JSON ({"completed": [level files]}).
## A missing, unreadable or corrupt file loads as empty progress without an
## error, so a damaged save never stops the game.


## The progress saved at `path`, with its `save_path` set to `path` so later
## completions are saved there too.
static func load_from(path: String) -> Progress:
	var progress: Progress = Progress.new()
	if FileAccess.file_exists(path):
		var text: String = FileAccess.get_file_as_string(path)
		if not text.is_empty():
			var json: JSON = JSON.new()
			if json.parse(text) == OK:
				progress = Progress.from_dictionary(json.data)
	progress.save_path = path
	return progress


## Writes `progress` to `path`. Returns false (with a warning) when the file cannot be written.
static func save(progress: Progress, path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ProgressStore: could not write '%s' (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(progress.to_dictionary(), "\t"))
	file.close()
	return true
