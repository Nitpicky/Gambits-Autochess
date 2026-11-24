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
}


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
	lines.append("%s%s  [%s %s, %s]" % [def.name, " (upgraded)" if lvl > 1 else "", Keywords.FACTION_NAMES[def.faction], UnitCatalog.RARITY_NAMES[def.rarity], String(def.role).capitalize()])
	var m := 1.0 + GameConfig.UPGRADE_STAT_BONUS * (lvl - 1)
	lines.append("HP %d  Atk %d  Def %d  Init %d  |  AP %d  PP %d" % [def.hp * m, def.atk * m, def["def"], def.ini, def.ap, def.pp])
	var kws: Array = PlayerState.unit_keywords(inst) if not inst.is_empty() else def.keywords
	for k in kws:
		lines.append("- %s: %s" % [Keywords.kw_name(k), Keywords.KEYWORDS[k].text])
	if def.passive_text != "":
		lines.append("Passive: " + def.passive_text)
	lines.append("Gambits (in order):")
	for g in def.gambits:
		lines.append("  " + gambit(g))
	for c in inst.get("cards", []):
		lines.append("Card %s: %s" % [c.name, c.text])
	for i in inst.get("items", []):
		var it := ItemCatalog.get_def(i)
		lines.append("Item %s: %s" % [it.name, item_line(it)])
	return "\n".join(lines)


static func item_line(it: Dictionary) -> String:
	var parts: Array[String] = []
	var names := {"hp": "HP", "atk": "Atk", "def": "Def", "ini": "Init", "ap": "AP", "pp": "PP"}
	for k in it.stats:
		parts.append("%+d %s" % [it.stats[k], names[k]])
	return ", ".join(parts) + ". " + it.text


static func item(it: Dictionary) -> String:
	var s := "%s  (%d gold, sells for %d)\n%s\n%s" % [it.name, it.price, Shop.item_sell_price(it.id), it.kind, item_line(it)]
	var req := ItemCatalog.req_text(it)
	if req != "":
		s += "\nRequires: " + req
	return s


static func relic(r: Dictionary) -> String:
	var s := "%s  (%d gold, relic, can't be sold)\n%s" % [r.name, r.price, r.text]
	if not r.needs.is_empty():
		s += "\nSwitches on with %d+ %s units in battle." % [r.needs.count, Keywords.FACTION_NAMES[r.needs.faction]]
	return s
