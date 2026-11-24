class_name Keywords
extends RefCounted
## Keyword vocabulary, faction ring and archetypes. Pure data.

const FACTIONS: Array[StringName] = [&"lyonar", &"vanar", &"songhai", &"magmar", &"abyssian", &"vetruvian"]
const FACTION_NAMES := {
	&"lyonar": "Lyonar", &"vanar": "Vanar", &"songhai": "Songhai",
	&"magmar": "Magmar", &"abyssian": "Abyssian", &"vetruvian": "Vetruvian", &"neutral": "Neutral",
}
const FACTION_COLORS := {
	&"lyonar": Color("e8c35a"), &"vanar": Color("7fc8f0"), &"songhai": Color("e0605a"),
	&"magmar": Color("7ccf6a"), &"abyssian": Color("a070d8"), &"vetruvian": Color("d89a50"), &"neutral": Color("aaaaaa"),
}

const KEYWORDS := {
	&"guard": {"name": "Guard", "faction": &"lyonar", "text": "PP reaction: takes a hit aimed at an ally in its row."},
	&"rally": {"name": "Rally", "faction": &"lyonar", "text": "Each time it spends PP, allies in its row get +10% Attack for the battle (stacks)."},
	&"ward": {"name": "Ward", "faction": &"vanar", "text": "Starts battle with a Ward that blocks the next damage instance."},
	&"chill": {"name": "Chill", "faction": &"vanar", "text": "Hits apply Chill (-10% Initiative per stack). At 3 stacks the target is Frozen and loses its next action."},
	&"swift": {"name": "Swift", "faction": &"songhai", "text": "+25% damage against a target that has not acted yet this turn."},
	&"mark": {"name": "Mark", "faction": &"songhai", "text": "Hits apply Mark: Marked units take +20% damage from everyone."},
	&"grow": {"name": "Grow", "faction": &"magmar", "text": "+8% Attack and max HP at each of its turn starts."},
	&"feast": {"name": "Feast", "faction": &"magmar", "text": "On a kill, heals 20% and refunds 1 AP."},
	&"sacrifice": {"name": "Sacrifice", "faction": &"abyssian", "text": "AP: consumes an allied token (or 25% own HP) to deal 200% Attack."},
	&"deathwatch": {"name": "Deathwatch", "faction": &"abyssian", "text": "PP reaction whenever any unit dies: strike a random enemy for 60% Attack."},
	&"construct": {"name": "Construct", "faction": &"vetruvian", "text": "Summons a token unit into an empty cell at battle start."},
	&"fortify": {"name": "Fortify", "faction": &"vetruvian", "text": "+10% damage reduction for each of its turns ended in place (max 40%)."},
}

## Ring order; neighbours are adjacent entries (wrapping).
const RING: Array[StringName] = [&"lyonar", &"vanar", &"songhai", &"magmar", &"abyssian", &"vetruvian"]

const ARCHETYPES := {
	&"fortress": {"name": "Fortress", "keywords": [&"guard", &"ward"]},
	&"control": {"name": "Control", "keywords": [&"chill", &"mark"]},
	&"tempo": {"name": "Tempo", "keywords": [&"swift", &"feast"]},
	&"ramp": {"name": "Ramp", "keywords": [&"grow", &"sacrifice"]},
	&"attrition": {"name": "Attrition", "keywords": [&"deathwatch", &"fortify"]},
	&"swarm": {"name": "Swarm", "keywords": [&"construct", &"rally"]},
}


static func neighbours(faction: StringName) -> Array[StringName]:
	var i := RING.find(faction)
	if i < 0:
		return []
	return [RING[(i + RING.size() - 1) % RING.size()], RING[(i + 1) % RING.size()]]


static func faction_keywords(faction: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in KEYWORDS:
		if KEYWORDS[k].faction == faction:
			out.append(k)
	return out


static func archetypes_of_keywords(kws: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for a in ARCHETYPES:
		for k in ARCHETYPES[a].keywords:
			if k in kws and not (a in out):
				out.append(a)
	return out


static func kw_name(k: StringName) -> String:
	return KEYWORDS[k].name if KEYWORDS.has(k) else String(k).capitalize()
