class_name Upgrades
extends RefCounted
## Upgrade cards offered when a unit levels up: one per path (Deepen / Bridge / Subvert).
## Cards are generic modifier dicts consumed by BattleSim._apply_mod:
## {"stats_pct", "ap", "pp", "keyword", "gambit"} + display fields.
## PROTOTYPE: cards are generic per path, not hand-written per unit.


static func cards_for(def_id: StringName, rng: RandomNumberGenerator) -> Array:
	var def := UnitCatalog.get_def(def_id)
	var out: Array = []
	# Deepen: more of what it already does.
	var res := "pp" if def.pp >= def.ap else "ap"
	var deepen := {"type": "deepen", "name": "Deepen", "stats_pct": 0.2, res: 1,
		"text": "+20%% HP and Attack, +1 %s." % res.to_upper()}
	out.append(deepen)
	# Bridge: a keyword from a neighbouring faction.
	var pool: Array = []
	for f in Keywords.neighbours(def.faction):
		for k in Keywords.faction_keywords(f):
			if not (k in def.keywords):
				pool.append(k)
	if pool.is_empty():
		pool = Keywords.KEYWORDS.keys().filter(func(k): return not (k in def.keywords))
	var kw: StringName = pool[rng.randi() % pool.size()]
	out.append({"type": "bridge", "name": "Bridge: " + Keywords.kw_name(kw), "keyword": kw,
		"text": "Gains %s (%s). %s" % [Keywords.kw_name(kw), Keywords.FACTION_NAMES[Keywords.KEYWORDS[kw].faction], Keywords.KEYWORDS[kw].text]})
	# Subvert: a new role.
	match def.role:
		&"tank", &"bruiser":
			out.append({"type": "subvert", "name": "Subvert: Cleaver", "gambit": {"kind": &"ap", "action": &"row_strike", "power": 0.6},
				"text": "AP: hits a whole enemy row for 60% Attack instead of one target."})
		&"striker", &"ranged":
			out.append({"type": "subvert", "name": "Subvert: Field Medic", "pp": 1, "gambit": {"kind": &"pp", "trigger": &"ally_damaged", "cond": &"target_below", "arg": 0.5, "action": &"heal", "power": 0.15},
				"text": "+1 PP. PP: when an ally drops below 50%, heals it 15%."})
		_:
			out.append({"type": "subvert", "name": "Subvert: Retribution", "pp": 1, "gambit": {"kind": &"pp", "trigger": &"ally_damaged", "action": &"deathwatch_strike", "power": 0.5},
				"text": "+1 PP. PP: when an ally is hit, strikes a random enemy for 50% Attack (spends PP, not AP)."})
	return out
