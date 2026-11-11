extends TestCase
## Tests for Campaign: the level order in res://levels/campaign.json.

const W1_02: String = "res://levels/w1_02.json"
const W1_07: String = "res://levels/w1_07.json"


func _campaign() -> Campaign:
	return Campaign.load_from_file(Campaign.DEFAULT_PATH)


func test_first_level_is_w1_02() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.first(), W1_02)


func test_next_after_w1_02_is_w1_07() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after(W1_02), W1_07)


func test_last_level_has_no_next() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after(W1_07), "")


func test_unknown_level_has_no_next() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.next_after("res://levels/dev_room.json"), "")
	assert_eq(campaign.next_after(""), "")


func test_every_campaign_level_loads() -> void:
	var campaign: Campaign = _campaign()
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.levels.size(), 2)
	for path: String in campaign.levels:
		assert_not_null(LevelData.load_from_file(path), path)


func test_empty_campaign_has_no_first() -> void:
	assert_eq(Campaign.new().first(), "")
