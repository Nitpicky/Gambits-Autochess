class_name Describe
extends RefCounted
## Human-readable text for tooltips and the detail panel.

const TRIGGERS := {
	&"ally_targeted": "when an ally in its row is targeted",
	&"self_targeted": "when it is targeted",
	&"ally_damaged": "when an ally takes damage",
	&"self_hit_melee": "when hit in melee",
	&"any_died": "when any unit dies",
}
const ACTIONS := {
	&"strike": "Strike (melee)", &"shoot": "Shoot (any target)", &"row_strike": "Row strike",
	&"chill_row": "Freezing wave (row + Chill)", &"mark_row": "Lantern burst (row + Mark)", &"heal": "Heal",
	&"ward_ally": "Give Ward", &"grant_grow": "Give Grow", &"sacrifice": "Sacrifice", &"guard": "Guard (take the hit)",
	&"dodge": "Dodge", &"counter": "Counterattack", &"deathwatch_strike": "Deathwatch strike",
}
const CONDS := {
	&"ally_below": "if an ally is below %d%%", &"target_below": "if it is below %d%%",
	&"ally_without": "if an ally lacks %s", &"can_sacrifice": "if a token or 50%%+ HP", &"has_token": "if an allied token exists",
	&"self_below": "if itself below %d%%", &"self_above": "if itself at %d%%+", &"enemy_below": "if an enemy is below %d%%",
	&"front_row": "if in the front row", &"back_row": "if in the back row",
}
## Short labels shown on the unit card's rule rows (minimal text on screen).
const ACTION_SHORT := {
	&"strike": "Strike", &"shoot": "Shoot", &"row_strike": "Cleave", &"chill_row": "Frost wave", &"mark_row": "Lantern",
	&"heal": "Heal", &"ward_ally": "Ward", &"grant_grow": "Grow", &"sacrifice": "Sacrifice", &"guard": "Guard",
	&"dodge": "Dodge", &"counter": "Counter", &"deathwatch_strike": "Deathwatch",
}
const COND_SHORT := {
	&"": "—", &"ally_below": "Ally <%d%%", &"target_below": "Ally <%d%%", &"self_below": "Self <%d%%", &"self_above": "Self ≥%d%%",
	&"enemy_below": "Foe <%d%%", &"front_row": "Front", &"back_row": "Back", &"ally_without": "No %s", &"can_sacrifice": "Fodder",
	&"has_token": "Token", &"enemy_has": "Foe %s", &"has_ap_left": "%d+ AP", &"token_died": "Totem dies", &"enemy_died": "Foe dies",
}
## Conditions a player can pick on a rule's condition chips.
const COND_PRESETS := [
	{}, {"c": &"ally_below", "a": 0.5}, {"c": &"ally_below", "a": 0.7}, {"c": &"target_below", "a": 0.5},
	{"c": &"self_below", "a": 0.5}, {"c": &"self_above", "a": 0.5}, {"c": &"enemy_below", "a": 0.3},
	{"c": &"enemy_has", "a": &"mark"}, {"c": &"front_row"}, {"c": &"back_row"}, {"c": &"has_ap_left", "a": 2},
]
## Long labels for the condition picker list.
const COND_LONG := {
	&"": "Always", &"ally_below": "An ally is below %d%%", &"target_below": "That ally is below %d%% (reactions)",
	&"self_below": "Itself below %d%%", &"self_above": "Itself at %d%% or more", &"enemy_below": "An enemy is below %d%%",
	&"enemy_has": "An enemy is %s", &"front_row": "It stands in the front row", &"back_row": "It stands in the back row",
	&"has_ap_left": "It has %d+ AP left",
}


static func cond_long(c: StringName, arg) -> String:
	var t: String = COND_LONG.get(c, String(c))
	if c == &"has_ap_left":
		return t % int(arg)
	if "%d" in t:
		return t % int(float(arg) * 100)
	if "%s" in t:
		return t % ("Marked" if arg == &"mark" else String(arg).capitalize())
	return t


static func cond_short(c: StringName, arg) -> String:
	var t: String = COND_SHORT.get(c, String(c))
	if c == &"has_ap_left":
		return t % int(arg)
	if c == &"enemy_has":
		return t % ("marked" if arg == &"mark" else String(arg))
	if "%d" in t:
		t = t % int(float(arg) * 100)
	elif "%s" in t:
		t = t % Keywords.kw_name(arg)
	return t


## The two condition chips of a rule: [[cond, arg], [cond, arg]].
static func rule_conds(g: Dictionary) -> Array:
	return [[g.get("cond", &""), g.get("arg", g.get("arg_kw", 0.0))], [g.get("cond2", &""), g.get("arg2", 0.0)]]


static func gambit(g: Dictionary) -> String:
	var s := "AP: " if g.kind == &"ap" else "PP %s: " % TRIGGERS.get(g.get("trigger", &""), "?")
	s += ACTIONS.get(g.action, String(g.action))
	if g.has("power") and g.action not in [&"heal"]:
		s += " %d%%" % int(g.power * 100)
	elif g.action == &"heal":
		s += " %d%% HP" % int(g.get("power", 0.2) * 100)
	var c: StringName = g.get("cond", &"")
	if c != &"":
		var t: String = CONDS.get(c, String(c))
		if "%d" in t:
			t = t % int(g.arg * 100)
		elif "%s" in t:
			t = t % Keywords.kw_name(g.arg_kw)
		s += " (" + t + ")"
	return s


static func unit_def(def: Dictionary, inst: Dictionary = {}) -> String:
	var lines: Array[String] = []
	var lvl: int = inst.get("level", 1)
	lines.append("%s%s  [%s %s, %s]" % [def.name, " (upgraded)" if lvl > 1 else "", Keywords.FACTION_NAMES[def.faction], UnitCatalog.RARITY_NAMES[def.rarity], String(def.role)])
	var kws: Array = PlayerState.unit_keywords(inst) if not inst.is_empty() else def.keywords
	for k in kws:
		if Keywords.kw_text(k) != "":
			lines.append("%s: %s" % [Keywords.kw_name(k), Keywords.kw_text(k)])
	if def.passive_text != "":
		lines.append(def.passive_text)
	if def.get("relic_name", "") != "":
		lines.append("Relic, %s: %s" % [def.relic_name, def.relic_text])
	for c in inst.get("cards", []):
		lines.append("Rank-up, %s: %s" % [c.get("name", "?"), c.get("text", "")])
	var perm: Dictionary = inst.get("perm", {})
	if int(perm.get("atk", 0)) > 0:
		lines.append("Permanent: +%d Attack" % int(perm.atk * GameConfig.ATK_UNIT))
	if def.get("dr", 0.0) > 0.0:
		lines.append("Takes %d%% less damage." % int(def.dr * 100))
	return "\n".join(lines)


static func item_line(it: Dictionary) -> String:
	var parts: Array[String] = []
	var names := {"hp": "HP", "atk": "Attack", "ini": "Speed", "ap": "AP", "pp": "PP"}
	for k in it.stats:
		if k == "dr":
			parts.append("-%d%% damage taken" % int(it.stats[k] * 100))
		else:
			parts.append("%+d %s" % [it.stats[k], names[k]])
	return ", ".join(parts) + ". " + it.text


static func item(it: Dictionary) -> String:
	var s := "%s\n%s" % [it.name, item_line(it)]
	var req := ItemCatalog.req_text(it)
	if req != "":
		s += "\nRequires: " + req
	return s


static func relic(r: Dictionary) -> String:
	var s := "%s\n%s" % [r.name, r.text]
	return s
