class_name Roster
extends RefCounted
## The unit roster from data/roster.json (built by tools/roster/build_roster.py from the
## "Keywords & Mechanics" doc + the Kit Sprite Board). 144 kits (126 units + 18 champions),
## tokens, PvE monsters and the keyword registry. Pure data: JSON keys stay Strings.

const PATH := "res://data/roster.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("Roster: can't open " + PATH)
			return {}
		var parsed = JSON.parse_string(f.get_as_text())
		_data = parsed if parsed is Dictionary else {}
	return _data


static func units() -> Dictionary:
	return data().get("units", {})


static func tokens() -> Dictionary:
	return data().get("tokens", {})


static func monsters() -> Dictionary:
	return data().get("monsters", {})


static func keywords() -> Array:
	return data().get("keywords", [])


## A kit by id (unit, champion, token or monster). Empty when unknown.
static func kit(id) -> Dictionary:
	var k := String(id)
	for group in [units(), tokens(), monsters()]:
		if group.has(k):
			return group[k]
	return {}


## Duelyst sprite for a form or token written as a board id ("form-bear"), or the id itself.
static func form_sprite(id: String) -> String:
	return data().get("form_sprites", {}).get(id, id)
