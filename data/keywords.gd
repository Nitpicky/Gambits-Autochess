class_name Keywords
extends RefCounted
## Keyword registry (from the roster / the doc's "Keyword registry"), factions and archetypes. Pure data.
## Faction is the only tag; the shop bias "archetypes" are the six faction spectrums.

const FACTIONS: Array[StringName] = [&"lyonar", &"vanar", &"songhai", &"magmar", &"abyssian", &"vetruvian"]
const FACTION_NAMES := {
	&"lyonar": "Lyonar", &"vanar": "Vanar", &"songhai": "Songhai",
	&"magmar": "Magmar", &"abyssian": "Abyssian", &"vetruvian": "Vetruvian", &"neutral": "Neutral", &"common": "Common",
}
const FACTION_COLORS := {
	&"lyonar": Color("e8c35a"), &"vanar": Color("7fc8f0"), &"songhai": Color("e0605a"),
	&"magmar": Color("7ccf6a"), &"abyssian": Color("a070d8"), &"vetruvian": Color("d89a50"), &"neutral": Color("aaaaaa"),
	&"common": Color("c8c8d8"),
}

## Ring order; neighbours are adjacent entries (wrapping).
const RING: Array[StringName] = [&"lyonar", &"vanar", &"songhai", &"magmar", &"abyssian", &"vetruvian"]

## Archetype = a faction spectrum (used by the shop bias and the card's right edge).
const ARCHETYPES := {
	&"lyonar": {"name": "Lyonar: Cleric to Knight", "faction": &"lyonar"},
	&"songhai": {"name": "Songhai: Monk to Ninja", "faction": &"songhai"},
	&"vetruvian": {"name": "Vetruvian: Sun Priest to Dervish", "faction": &"vetruvian"},
	&"abyssian": {"name": "Abyssian: Cultist to Abomination", "faction": &"abyssian"},
	&"magmar": {"name": "Magmar: Tamer to Colossus", "faction": &"magmar"},
	&"vanar": {"name": "Vanar: Spirit to Viking", "faction": &"vanar"},
}

static var KEYWORDS: Dictionary = {}


static func _ensure() -> void:
	if not KEYWORDS.is_empty():
		return
	for k in Roster.keywords():
		KEYWORDS[StringName(k.id)] = {"name": k.name, "faction": StringName(k.owner), "text": k.text}


static func get_kw(k: StringName) -> Dictionary:
	_ensure()
	return KEYWORDS.get(k, {})


static func neighbours(faction: StringName) -> Array[StringName]:
	var i := RING.find(faction)
	if i < 0:
		return []
	return [RING[(i + RING.size() - 1) % RING.size()], RING[(i + 1) % RING.size()]]


static func faction_keywords(faction: StringName) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k in KEYWORDS:
		if KEYWORDS[k].faction == faction:
			out.append(k)
	return out


## Archetypes a keyword list leans into: the factions owning those keywords.
static func archetypes_of_keywords(kws: Array) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k in kws:
		var f: StringName = KEYWORDS.get(StringName(k), {}).get("faction", &"common")
		if ARCHETYPES.has(f) and not (f in out):
			out.append(f)
	return out


static func kw_name(k: StringName) -> String:
	_ensure()
	return KEYWORDS[k].name if KEYWORDS.has(k) else String(k).capitalize()


static func kw_text(k: StringName) -> String:
	_ensure()
	return KEYWORDS[k].text if KEYWORDS.has(k) else ""
