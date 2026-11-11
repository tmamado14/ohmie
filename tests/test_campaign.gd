extends TestCase
## Tests for Campaign: the level order in res://levels/campaign.json.

const SLICE_01: String = "res://levels/slice_01.json"
const LEVEL_02: String = "res://levels/level_02.json"


func _campaign() -> Campaign:
	return Campaign.load_from_file(Campaign.DEFAULT_PATH)


func test_next_after_slice_01_is_level_02() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after(SLICE_01), LEVEL_02)


func test_last_level_has_no_next() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after(LEVEL_02), "")


func test_unknown_level_has_no_next() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after("res://levels/dev_room.json"), "")
	assert_eq(campaign.next_after(""), "")
