extends TestCase
## Tests for Progress (unlock rules) and ProgressStore (save, load, damaged
## files). Campaigns are synthetic (file existence decided by a Callable).
## Save files go to a temporary path under user:// that each test deletes;
## the real save (user://progress.json) is never touched.

const TEMP_SAVE: String = "user://test_progress_tmp.json"

## Rooms 1..10 regular, 11..13 Overtime.
func _file(number: int) -> String:
	return "res://levels/tp_%02d.json" % number


func _world(built: Array[int], locked: bool = false) -> CampaignWorld:
	var rooms: Array = []
	for n: int in range(1, 14):
		rooms.append({"number": n, "file": _file(n), "overtime": n > 10})
	var data: Dictionary = {"worlds": [{"id": "w", "number": 1, "name": "W", "locked": locked, "rooms": rooms}]}
	var built_files: Array[String] = []
	for n: int in built:
		built_files.append(_file(n))
	var campaign: Campaign = Campaign.from_dictionary(data, "test",
			func(path: String) -> bool: return built_files.has(path))
	return campaign.worlds[0]


func _unlocked(progress: Progress, world: CampaignWorld, number: int) -> bool:
	return progress.is_unlocked(world, world.find_room(_file(number)))


func _completed(numbers: Array[int]) -> Progress:
	var progress: Progress = Progress.new()
	for n: int in numbers:
		progress.mark_completed(_file(n))
	return progress


func _delete_temp() -> void:
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))


func test_first_built_room_is_always_unlocked() -> void:
	var world: CampaignWorld = _world([2, 7])
	var progress: Progress = Progress.new()
	assert_true(_unlocked(progress, world, 2), "the first built room")
	assert_false(_unlocked(progress, world, 7), "the next built room before the first is completed")


func test_next_built_room_unlocks_after_previous_built_room() -> void:
	var world: CampaignWorld = _world([1, 2, 3])
	assert_false(_unlocked(_completed([]), world, 2))
	assert_true(_unlocked(_completed([1]), world, 2))
	assert_false(_unlocked(_completed([1]), world, 3))
	assert_true(_unlocked(_completed([1, 2]), world, 3))


func test_unbuilt_rooms_in_between_are_skipped() -> void:
	var world: CampaignWorld = _world([2, 7])
	assert_true(_unlocked(_completed([2]), world, 7), "room 7 follows room 2 when 3-6 are not built")
	assert_false(_unlocked(_completed([2]), world, 3), "an unbuilt room is never unlocked")


func test_unbuilt_room_is_never_unlocked_even_if_completed() -> void:
	var world: CampaignWorld = _world([1])
	assert_false(_unlocked(_completed([1, 2]), world, 2))


func test_completed_room_stays_unlocked() -> void:
	# Room 3 appears later between completed rooms 2 and 7: 7 stays playable.
	var world: CampaignWorld = _world([2, 3, 7])
	var progress: Progress = _completed([2, 7])
	assert_true(_unlocked(progress, world, 3))
	assert_true(_unlocked(progress, world, 7))


func test_locked_world_has_nothing_unlocked() -> void:
	var world: CampaignWorld = _world([1, 2], true)
	assert_false(_unlocked(_completed([1]), world, 1))
	assert_false(_unlocked(_completed([1]), world, 2))


func test_overtime_unlocks_when_room_ten_is_completed() -> void:
	var world: CampaignWorld = _world([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
	assert_false(_unlocked(_completed([1, 2, 3, 4, 5, 6, 7, 8, 9]), world, 11))
	var all_regular: Progress = _completed([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	assert_true(_unlocked(all_regular, world, 11))
	assert_true(_unlocked(all_regular, world, 12), "every Overtime room opens at once")
	assert_true(_unlocked(all_regular, world, 13))


func test_overtime_without_room_ten_needs_every_built_regular_room() -> void:
	var world: CampaignWorld = _world([2, 7, 11, 12])
	assert_false(_unlocked(_completed([2]), world, 11))
	assert_true(_unlocked(_completed([2, 7]), world, 11))
	assert_true(_unlocked(_completed([2, 7]), world, 12))
	assert_false(_unlocked(_completed([2, 7]), world, 13), "an unbuilt Overtime room stays shut")


func test_overtime_alone_is_open() -> void:
	var world: CampaignWorld = _world([11])
	assert_true(_unlocked(Progress.new(), world, 11), "the first built room of the world")


func test_completed_count_and_files() -> void:
	var world: CampaignWorld = _world([1, 2, 3])
	var progress: Progress = _completed([2, 1])
	assert_eq(progress.completed_count(world), 2)
	assert_eq(progress.completed_files(), PackedStringArray([_file(1), _file(2)]))
	assert_true(progress.is_completed(_file(1)))
	assert_false(progress.is_completed(_file(3)))


func test_in_memory_progress_writes_nothing() -> void:
	_delete_temp()
	var progress: Progress = Progress.new()
	progress.mark_completed(_file(1))
	assert_eq(progress.save_path, "")
	assert_false(FileAccess.file_exists(TEMP_SAVE))


func test_save_and_load_round_trip() -> void:
	_delete_temp()
	var progress: Progress = ProgressStore.load_from(TEMP_SAVE)
	assert_eq(progress.completed_files().size(), 0, "a missing file loads as empty progress")
	assert_eq(progress.save_path, TEMP_SAVE)
	progress.mark_completed(_file(2))
	progress.mark_completed(_file(7))
	assert_true(FileAccess.file_exists(TEMP_SAVE), "mark_completed saves at once")
	var reloaded: Progress = ProgressStore.load_from(TEMP_SAVE)
	assert_true(reloaded.is_completed(_file(2)))
	assert_true(reloaded.is_completed(_file(7)))
	assert_false(reloaded.is_completed(_file(3)))
	_delete_temp()


func test_corrupt_file_loads_empty_without_errors() -> void:
	for text: String in ["{ this is not json", "[1, 2, 3]", "{\"completed\": \"nope\"}", ""]:
		var file: FileAccess = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var progress: Progress = ProgressStore.load_from(TEMP_SAVE)
		assert_eq(progress.completed_files().size(), 0, "'%s' loads as empty progress" % text)
	var mixed: FileAccess = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	mixed.store_string("{\"completed\": [\"%s\", 5, null, \"\"]}" % _file(4))
	mixed.close()
	assert_eq(ProgressStore.load_from(TEMP_SAVE).completed_files(), PackedStringArray([_file(4)]),
			"only string entries are kept")
	_delete_temp()
