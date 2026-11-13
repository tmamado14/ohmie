class_name ReadingLegend
extends RefCounted
## The one-line explanation the HUD shows while a special reading (a meter or a
## plaque row reading SHORT, ???, OL or ---) is on screen. Wording only: the
## reading tokens come from MeterText, and when several are on screen the most
## important one is explained (MeterText.SPECIAL_READINGS order: SHORT, ???,
## OL, ---).

const SEPARATOR: String = " · "
const SHORT_CAPTION: String = MeterText.SHORT_TEXT + SEPARATOR + "a battery has nothing to limit its current"
const INDETERMINATE_CAPTION: String = MeterText.INDETERMINATE_TEXT + SEPARATOR \
		+ "the meters cannot tell: two readings are possible"
const OPEN_LOOP_CAPTION: String = MeterText.OVER_LIMIT_TEXT + SEPARATOR \
		+ "open loop: no path between the ohmmeter's ends"
const NO_READING_CAPTION: String = MeterText.NO_READING_TEXT + SEPARATOR \
		+ "nothing to read: the meter's ends are not connected"
## Caption per special reading.
const CAPTIONS: Dictionary = {
	MeterText.SHORT_TEXT: SHORT_CAPTION,
	MeterText.INDETERMINATE_TEXT: INDETERMINATE_CAPTION,
	MeterText.OVER_LIMIT_TEXT: OPEN_LOOP_CAPTION,
	MeterText.NO_READING_TEXT: NO_READING_CAPTION,
}


## The caption for the most important special reading among `readings`, or ""
## when none of them is special.
static func caption_for(readings: PackedStringArray) -> String:
	var specials: PackedStringArray = MeterText.special_readings_in(readings)
	if specials.is_empty():
		return ""
	return String(CAPTIONS[specials[0]])
