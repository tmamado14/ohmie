class_name Campaign
extends RefCounted
## The ordered list of level files played one after another, read from a JSON
## file such as {"levels": ["res://levels/a.json", "res://levels/b.json"]}.
## Pure data: no nodes.

const DEFAULT_PATH: String = "res://levels/campaign.json"

var levels: Array[String] = []


## Loads a campaign file. Returns null and pushes an error when it is missing or invalid.
static func load_from_file(path: String = DEFAULT_PATH) -> Campaign:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Campaign: could not read '%s'" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not (parsed as Dictionary).get("levels") is Array:
		push_error("Campaign: '%s' needs a 'levels' array" % path)
		return null
	var campaign: Campaign = Campaign.new()
	for entry: Variant in (parsed as Dictionary)["levels"]:
		if not entry is String:
			push_error("Campaign: '%s': every level must be a path string" % path)
			return null
		campaign.levels.append(entry as String)
	return campaign


## The first level of the campaign, or "" when it has none.
func first() -> String:
	return levels[0] if not levels.is_empty() else ""


## The level that follows `path`, or "" when `path` is the last level or not in the campaign.
func next_after(path: String) -> String:
	var index: int = levels.find(path)
	if index < 0 or index + 1 >= levels.size():
		return ""
	return levels[index + 1]
