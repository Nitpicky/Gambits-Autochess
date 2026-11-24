class_name Kits
extends RefCounted
## Hand-written unit kits: each unit's own actions (AP actives, PP reactions) and its 3 upgrade
## options (pick 1 at rank-up), which change how the kit works. Pure data + small pure helpers.
## PROTOTYPE: only Lyonar has kits for now (test slice); other units still use their role/keyword
## gambits and the generic Upgrades cards.
##
## Action = {
##   "id", "name", "kind": &"ap" | &"pp", "cost": int (AP or PP spent, default 1),
##   "trigger": PP only (ally_targeted, self_targeted, ally_damaged, self_hit_melee, any_died),
##   "reach": &"row" (default) | &"all"   (ally_targeted only: which allies it guards),
##   "target": selector, "steps": [step...], "once": true (once per battle),
##   "cond"/"arg", "cond2"/"arg2": default rule conditions, "text": rules text shown on the card }
## Selectors: melee, enemy, enemy_lowest, enemy_row (front row, else back), ally_lowest, self,
##   row_allies, allies, trigger_target, trigger_source.
## Steps (apply to every selected target unless "on" picks another selector):
##   {"do": "damage", "power", "bonus_if": {"marked"|"below"|"above": x, "mult"}, "behind": power}
##   {"do": "heal", "pct"}  {"do": "status", "id", "stacks"}  {"do": "ward"}
##   {"do": "buff", "stat": attack|damage_reduction|initiative, "value"}  {"do": "gain", "res": ap|pp, "n"}
##   {"do": "redirect"} (Guard: the hit goes to this unit)  {"do": "cancel"} (dodge)
##   {"do": "summon", "token"}
##   Damage steps may carry "on_kill": [steps] (run on the attacker).
## Upgrade = {"id", "name", "text", "replace": {action_id: action}, "add": [action], "start": [steps],
##   "hp"/"atk"/"ap"/"pp" (flat), "keyword", "flags": {name: value}}

const L := &"lyonar"

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func has_kit(def_id: StringName) -> bool:
	return all().has(def_id)


static func kit(def_id: StringName) -> Dictionary:
	return all().get(def_id, {})


## The unit's actions after its upgrade cards: {id: action}. Empty when the unit has no kit.
static func actions_for(def_id: StringName, cards: Array = []) -> Dictionary:
	var k := kit(def_id)
	if k.is_empty():
		return {}
	var out := {}
	for a in k.actions:
		out[a.id] = a.duplicate(true)
	for c in cards:
		for id in c.get("replace", {}):
			out[id] = c.replace[id].duplicate(true)
			out[id]["id"] = id
		for a in c.get("add", []):
			out[a.id] = a.duplicate(true)
	return out


## Default rules (gambits) of a kit unit: one per action, in kit order, plus upgrade-added actions.
static func default_rules(def_id: StringName, cards: Array = []) -> Array:
	var acts := actions_for(def_id, cards)
	var rules: Array = []
	for id in acts:
		rules.append(rule_for(acts[id]))
	# AP actions without conditions go last so conditional ones get a chance first
	var cond_first: Array = rules.filter(func(r): return r.kind == &"pp" or r.has("cond"))
	var plain: Array = rules.filter(func(r): return not (r.kind == &"pp" or r.has("cond")))
	return cond_first + plain


static func rule_for(a: Dictionary) -> Dictionary:
	var r := {"kind": a.kind, "action": a.id}
	for k in ["trigger", "cond", "arg", "cond2", "arg2"]:
		if a.has(k):
			r[k] = a[k]
	return r


static func upgrades(def_id: StringName) -> Array:
	var out: Array = []
	for u in kit(def_id).get("upgrades", []):
		var c: Dictionary = u.duplicate(true)
		c["type"] = "kit"
		out.append(c)
	return out


# ---------------------------------------------------------------- shared action shapes

static func _strike(id := &"strike", nm := "Strike", power := 1.0) -> Dictionary:
	return {"id": id, "name": nm, "kind": &"ap", "target": &"melee", "steps": [{"do": "damage", "power": power}],
		"text": "%d%% Attack to a front enemy." % int(power * 100)}


static func _guard(extra_steps: Array = [], text := "") -> Dictionary:
	return {"id": &"guard", "name": "Guard", "kind": &"pp", "trigger": &"ally_targeted", "target": &"self",
		"steps": [{"do": "redirect"}] + extra_steps, "text": text if text != "" else "When an ally in its row is targeted, takes the hit instead."}


static func _k(id: StringName, actions: Array, ups: Array) -> void:
	_cache[id] = {"actions": actions, "upgrades": ups}


# ---------------------------------------------------------------- Lyonar

static func _build() -> void:
	# Squire (common tank): plain bodyguard.
	_k(&"squire", [_strike(), _guard()], [
		{"id": &"shield_bash", "name": "Shield Bash", "text": "Guard also strikes back at the attacker for 50% Attack.",
			"replace": {&"guard": _guard([{"do": "damage", "on": &"trigger_source", "power": 0.5}], "Takes a hit for a row ally, then strikes the attacker for 50%.")}},
		{"id": &"oath", "name": "Squire's Oath", "text": "+1 PP. Each Guard gives it +2 Attack for the battle.", "pp": 1,
			"replace": {&"guard": _guard([{"do": "buff", "stat": &"attack", "value": 2}], "Takes a hit for a row ally and gains +2 Attack.")}},
		{"id": &"brace", "name": "Brace", "text": "New AP action: below 50% HP, gains 25% damage reduction (once).",
			"add": [{"id": &"brace", "name": "Brace", "kind": &"ap", "target": &"self", "once": true, "cond": &"self_below", "arg": 0.5,
				"steps": [{"do": "buff", "stat": &"damage_reduction", "value": 0.25}], "text": "Gains 25% damage reduction for the battle. Once."}]},
	])
	# Acolyte (common support): heals and pokes.
	var mend := {"id": &"mend", "name": "Mend", "kind": &"ap", "target": &"ally_lowest", "cond": &"ally_below", "arg": 0.7,
		"steps": [{"do": "heal", "pct": 0.25}], "text": "Heals the most hurt ally 25%."}
	var smite := {"id": &"smite", "name": "Smite", "kind": &"ap", "target": &"enemy", "steps": [{"do": "damage", "power": 0.6}],
		"text": "60% Attack to any enemy."}
	var prayer := {"id": &"prayer", "name": "Prayer", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
		"cond": &"target_below", "arg": 0.5, "steps": [{"do": "heal", "pct": 0.2}], "text": "When an ally drops below 50%, heals it 20%."}
	_k(&"acolyte", [mend, smite, prayer], [
		{"id": &"radiance", "name": "Radiance", "text": "Mend heals the target's whole row 15% instead.",
			"replace": {&"mend": {"name": "Radiance", "kind": &"ap", "target": &"ally_lowest", "cond": &"ally_below", "arg": 0.7,
				"steps": [{"do": "heal", "on": &"row_allies_of_target", "pct": 0.15}], "text": "Heals the most hurt ally's whole row 15%."}}},
		{"id": &"zeal", "name": "Zealous Smite", "text": "Smite also gives the most hurt ally +2 Attack for the battle.",
			"replace": {&"smite": {"name": "Zealous Smite", "kind": &"ap", "target": &"enemy",
				"steps": [{"do": "damage", "power": 0.6}, {"do": "buff", "on": &"ally_lowest", "stat": &"attack", "value": 2}],
				"text": "60% Attack to any enemy; the most hurt ally gets +2 Attack."}}},
		{"id": &"sanctuary", "name": "Sanctuary", "text": "Prayer also gives the ally Ward (blocks the next hit).",
			"replace": {&"prayer": {"name": "Sanctuary", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
				"cond": &"target_below", "arg": 0.5, "steps": [{"do": "heal", "pct": 0.2}, {"do": "ward"}],
				"text": "When an ally drops below 50%, heals it 20% and gives it Ward."}}},
	])
	# Lancer (rare bruiser): opens fights hard, punishes melee.
	var charge := {"id": &"charge", "name": "Lance Charge", "kind": &"ap", "target": &"melee",
		"steps": [{"do": "damage", "power": 1.0, "bonus_if": {"above": 0.75, "mult": 0.5}}], "text": "100% Attack to a front enemy, +50% if it is above 75% HP."}
	var riposte := {"id": &"riposte", "name": "Riposte", "kind": &"pp", "trigger": &"self_hit_melee", "target": &"trigger_source",
		"steps": [{"do": "damage", "power": 0.6}], "text": "When hit in melee, strikes back for 60%."}
	_k(&"lancer", [charge, riposte], [
		{"id": &"impale", "name": "Impale", "text": "Lance Charge also pierces the unit behind its target for 60%.",
			"replace": {&"charge": {"name": "Impale", "kind": &"ap", "target": &"melee",
				"steps": [{"do": "damage", "power": 1.0, "bonus_if": {"above": 0.75, "mult": 0.5}, "behind": 0.6}],
				"text": "100% Attack to a front enemy (+50% above 75% HP) and 60% to the one behind it."}}},
		{"id": &"sunforged", "name": "Sunforged Riposte", "text": "Riposte also gives allies in its row +1 Attack.",
			"replace": {&"riposte": {"name": "Sunforged Riposte", "kind": &"pp", "trigger": &"self_hit_melee", "target": &"trigger_source",
				"steps": [{"do": "damage", "power": 0.6}, {"do": "buff", "on": &"row_allies", "stat": &"attack", "value": 1}],
				"text": "When hit in melee, strikes back for 60%; its row gets +1 Attack."}}},
		{"id": &"momentum", "name": "Momentum", "text": "Kills with Lance Charge refund 1 AP.",
			"replace": {&"charge": {"name": "Lance Charge", "kind": &"ap", "target": &"melee",
				"steps": [{"do": "damage", "power": 1.0, "bonus_if": {"above": 0.75, "mult": 0.5}, "on_kill": [{"do": "gain", "res": &"ap", "n": 1}]}],
				"text": "100% Attack to a front enemy (+50% above 75% HP). A kill refunds 1 AP."}}},
	])
	# Shieldmaiden (rare tank): Guard + Ward support.
	var slam := {"id": &"slam", "name": "Shield Slam", "kind": &"ap", "target": &"melee", "steps": [{"do": "damage", "power": 0.7}],
		"text": "70% Attack to a front enemy."}
	var sunshield := {"id": &"sunshield", "name": "Sunshield", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
		"cond": &"target_below", "arg": 0.4, "steps": [{"do": "ward"}], "text": "When an ally drops below 40%, gives it Ward."}
	_k(&"shieldmaiden", [slam, _guard(), sunshield], [
		{"id": &"aegis", "name": "Aegis", "text": "Battle start: allies in its row get Ward.",
			"start": [{"do": "ward", "on": &"row_allies"}]},
		{"id": &"shared_shield", "name": "Shared Shield", "text": "Guard also gives the protected ally Ward.",
			"replace": {&"guard": _guard([{"do": "ward", "on": &"trigger_original"}], "Takes a hit for a row ally and gives that ally Ward.")}},
		{"id": &"shield_throw", "name": "Shield Throw", "text": "Shield Slam reaches any enemy and Marks it (+20% damage taken).",
			"replace": {&"slam": {"name": "Shield Throw", "kind": &"ap", "target": &"enemy",
				"steps": [{"do": "damage", "power": 0.7}, {"do": "status", "id": &"mark", "stacks": 1}], "text": "70% Attack to any enemy and Marks it."}}},
	])
	# Sunforger (epic support): totems and wards.
	var sunbeam := {"id": &"sunbeam", "name": "Sunbeam", "kind": &"ap", "target": &"enemy",
		"steps": [{"do": "damage", "power": 0.7, "bonus_if": {"token_alive": true, "mult": 0.5}}], "text": "70% Attack to any enemy, +50% while it has a Totem."}
	var forge := {"id": &"forge_ward", "name": "Forge Ward", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
		"cond": &"target_below", "arg": 0.4, "steps": [{"do": "ward"}], "text": "When an ally drops below 40%, gives it Ward."}
	var vigil := {"id": &"totem_vigil", "name": "Totem Vigil", "kind": &"pp", "trigger": &"any_died", "target": &"allies", "cond": &"token_died",
		"steps": [{"do": "buff", "stat": &"attack", "value": 2}], "text": "When one of its Totems dies, all allies get +2 Attack."}
	_k(&"sunforger", [sunbeam, forge, vigil], [
		{"id": &"twin_totems", "name": "Twin Totems", "text": "Construct builds a second Totem.", "flags": {&"extra_token": 1.0}},
		{"id": &"conduit", "name": "Solar Conduit", "text": "Sunbeam hits the whole enemy row for 50% (+50% with a Totem).",
			"replace": {&"sunbeam": {"name": "Solar Conduit", "kind": &"ap", "target": &"enemy_row",
				"steps": [{"do": "damage", "power": 0.5, "bonus_if": {"token_alive": true, "mult": 0.5}}], "text": "50% Attack to a whole enemy row, +50% while it has a Totem."}}},
		{"id": &"forgemaster", "name": "Forgemaster", "text": "Forge Ward also heals the ally 15%.",
			"replace": {&"forge_ward": {"name": "Forge Ward", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
				"cond": &"target_below", "arg": 0.4, "steps": [{"do": "ward"}, {"do": "heal", "pct": 0.15}], "text": "When an ally drops below 40%, gives it Ward and heals 15%."}}},
	])
	# Grand Templar (legendary tank): marks, guards, consecrates.
	var judgement := {"id": &"judgement", "name": "Judgement", "kind": &"ap", "target": &"melee",
		"steps": [{"do": "damage", "power": 1.0}, {"do": "status", "id": &"mark", "stacks": 1}], "text": "100% Attack to a front enemy and Marks it."}
	var consecrate := {"id": &"consecrate", "name": "Consecrate", "kind": &"ap", "target": &"row_allies", "cond": &"self_below", "arg": 0.5,
		"steps": [{"do": "heal", "pct": 0.15}], "text": "Heals allies in its row 15%."}
	_k(&"grand_templar", [judgement, _guard(), consecrate], [
		{"id": &"bulwark", "name": "Divine Bulwark", "text": "+1 PP. Guard also heals it 10%.", "pp": 1,
			"replace": {&"guard": _guard([{"do": "heal", "pct": 0.1}], "Takes a hit for a row ally, then heals 10%.")}},
		{"id": &"crusade", "name": "Crusade", "text": "Judgement deals +50% to Marked enemies and gives its row +2 Attack.",
			"replace": {&"judgement": {"name": "Crusade", "kind": &"ap", "target": &"melee",
				"steps": [{"do": "damage", "power": 1.0, "bonus_if": {"marked": true, "mult": 0.5}}, {"do": "status", "id": &"mark", "stacks": 1},
					{"do": "buff", "on": &"row_allies", "stat": &"attack", "value": 2}], "text": "100% Attack (+50% if Marked), Marks; its row gets +2 Attack."}}},
		{"id": &"lightbringer", "name": "Lightbringer", "text": "Consecrate heals all allies and Wards the most hurt one.",
			"replace": {&"consecrate": {"name": "Lightbringer", "kind": &"ap", "target": &"allies", "cond": &"self_below", "arg": 0.5,
				"steps": [{"do": "heal", "pct": 0.15}, {"do": "ward", "on": &"ally_lowest"}], "text": "Heals all allies 15%; the most hurt gets Ward."}}},
	])
	# Azurite Lion (rare striker, choice): grows on enemy deaths.
	var pounce := _strike(&"pounce", "Pounce", 1.0)
	var roar := {"id": &"roar", "name": "Roar", "kind": &"pp", "trigger": &"any_died", "target": &"self", "cond": &"enemy_died",
		"steps": [{"do": "buff", "stat": &"attack", "value": 2}], "text": "When an enemy dies, gains +2 Attack."}
	_k(&"azurite_lion", [pounce, roar], [
		{"id": &"pride", "name": "Pride", "text": "Roar also gives allies in its row +1 Attack.",
			"replace": {&"roar": {"name": "Pride", "kind": &"pp", "trigger": &"any_died", "target": &"self", "cond": &"enemy_died",
				"steps": [{"do": "buff", "stat": &"attack", "value": 2}, {"do": "buff", "on": &"row_allies", "stat": &"attack", "value": 1}],
				"text": "When an enemy dies, gains +2 Attack; its row +1."}}},
		{"id": &"leap", "name": "Leap", "text": "Pounce reaches any enemy, preferring the most hurt.",
			"replace": {&"pounce": {"name": "Leap", "kind": &"ap", "target": &"enemy_lowest", "steps": [{"do": "damage", "power": 1.0}],
				"text": "100% Attack to the most hurt enemy."}}},
		{"id": &"swiftmane", "name": "Swiftmane", "text": "+1 AP and +2 Speed.", "ap": 1, "ini": 2},
	])
	# Ironcliffe Guardian (epic tank, choice): the wall.
	var crush := _strike(&"crush", "Crush", 0.8)
	var stoneskin := {"id": &"stoneskin", "name": "Stoneskin", "kind": &"pp", "trigger": &"self_targeted", "target": &"self", "once": true,
		"cond": &"self_below", "arg": 0.5, "steps": [{"do": "ward"}], "text": "Below 50% HP, when targeted, gains Ward. Once."}
	_k(&"ironcliffe", [crush, _guard(), stoneskin], [
		{"id": &"unbreakable", "name": "Unbreakable", "text": "+25% damage reduction.", "dr": 0.25},
		{"id": &"wall", "name": "Living Wall", "text": "Guard protects allies in any row.",
			"replace": {&"guard": {"name": "Guard", "kind": &"pp", "trigger": &"ally_targeted", "reach": &"all", "target": &"self",
				"steps": [{"do": "redirect"}], "text": "When any ally is targeted, takes the hit instead."}}},
		{"id": &"landslide", "name": "Landslide", "text": "Crush hits the whole front enemy row for 60%.",
			"replace": {&"crush": {"name": "Landslide", "kind": &"ap", "target": &"enemy_row", "steps": [{"do": "damage", "power": 0.6}],
				"text": "60% Attack to the whole front enemy row."}}},
	])
	# Solarius (legendary support, choice): light that marks and mends.
	var flare := {"id": &"flare", "name": "Solar Flare", "kind": &"ap", "target": &"enemy",
		"steps": [{"do": "damage", "power": 0.8}, {"do": "status", "id": &"mark", "stacks": 1}], "text": "80% Attack to any enemy and Marks it."}
	var benediction := {"id": &"benediction", "name": "Benediction", "kind": &"ap", "target": &"ally_lowest", "cond": &"ally_below", "arg": 0.7,
		"steps": [{"do": "heal", "pct": 0.3}], "text": "Heals the most hurt ally 30%."}
	var sunward := {"id": &"sunward", "name": "Sunward", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
		"cond": &"target_below", "arg": 0.5, "steps": [{"do": "ward"}, {"do": "heal", "pct": 0.15}], "text": "When an ally drops below 50%, Wards it and heals 15%."}
	_k(&"solarius", [flare, benediction, sunward], [
		{"id": &"zenith", "name": "Zenith", "text": "Benediction heals all allies 15%.",
			"replace": {&"benediction": {"name": "Zenith", "kind": &"ap", "target": &"allies", "cond": &"ally_below", "arg": 0.7,
				"steps": [{"do": "heal", "pct": 0.15}], "text": "Heals all allies 15%."}}},
		{"id": &"wrath", "name": "Solar Wrath", "text": "Solar Flare hits a whole enemy row for 50% and Marks them all.",
			"replace": {&"flare": {"name": "Solar Wrath", "kind": &"ap", "target": &"enemy_row",
				"steps": [{"do": "damage", "power": 0.5}, {"do": "status", "id": &"mark", "stacks": 1}], "text": "50% Attack to a whole enemy row; Marks them."}}},
		{"id": &"dawn", "name": "Eternal Dawn", "text": "+1 PP. Sunward also gives the ally +2 Attack.", "pp": 1,
			"replace": {&"sunward": {"name": "Sunward", "kind": &"pp", "trigger": &"ally_damaged", "target": &"trigger_target",
				"cond": &"target_below", "arg": 0.5, "steps": [{"do": "ward"}, {"do": "heal", "pct": 0.15}, {"do": "buff", "stat": &"attack", "value": 2}],
				"text": "When an ally drops below 50%, Wards it, heals 15% and gives +2 Attack."}}},
	])
	# Grandmaster Zir (champion tank): the commander.
	var gm_strike := _strike(&"gm_strike", "Grandmaster's Strike", 1.2)
	var rally_cry := {"id": &"rally_cry", "name": "Rally Cry", "kind": &"ap", "target": &"allies", "once": true,
		"steps": [{"do": "buff", "stat": &"attack", "value": 3}], "text": "All allies get +3 Attack. Once."}
	_k(&"zir", [rally_cry, gm_strike, _guard()], [
		{"id": &"will", "name": "Grandmaster's Will", "text": "Guard also gives the protected ally Ward.",
			"replace": {&"guard": _guard([{"do": "ward", "on": &"trigger_original"}], "Takes a hit for a row ally and gives that ally Ward.")}},
		{"id": &"commander", "name": "Commander", "text": "Rally Cry also gives allies in its row +1 AP.",
			"replace": {&"rally_cry": {"name": "Rally Cry", "kind": &"ap", "target": &"allies", "once": true,
				"steps": [{"do": "buff", "stat": &"attack", "value": 3}, {"do": "gain", "on": &"row_allies", "res": &"ap", "n": 1}],
				"text": "All allies +3 Attack; its row +1 AP. Once."}}},
		{"id": &"bastion", "name": "Last Bastion", "text": "New AP action: below 50% HP, gains 30% damage reduction and Ward (once).",
			"add": [{"id": &"bastion", "name": "Last Bastion", "kind": &"ap", "target": &"self", "once": true, "cond": &"self_below", "arg": 0.5,
				"steps": [{"do": "buff", "stat": &"damage_reduction", "value": 0.3}, {"do": "ward"}], "text": "Gains 30% damage reduction and Ward. Once."}]},
	])
	# Radiant Dragoon (champion striker): flies at the weak.
	var dive := {"id": &"dive", "name": "Dive", "kind": &"ap", "target": &"enemy_lowest", "steps": [{"do": "damage", "power": 0.9}],
		"text": "90% Attack to the most hurt enemy."}
	var wing := {"id": &"wing", "name": "Radiant Wing", "kind": &"ap", "cost": 2, "target": &"enemy_row", "cond": &"has_ap_left", "arg": 2,
		"steps": [{"do": "damage", "power": 0.6}], "text": "Costs 2 AP. 60% Attack to a whole enemy row."}
	var evade := {"id": &"evade", "name": "Evade", "kind": &"pp", "trigger": &"self_targeted", "target": &"self", "cond": &"self_below", "arg": 0.5,
		"steps": [{"do": "cancel"}], "text": "Below 50% HP, dodges an attack."}
	_k(&"radiant_dragoon", [wing, dive, evade], [
		{"id": &"executioner", "name": "Executioner", "text": "Dive deals +60% to enemies below 50%; kills refund 1 AP.",
			"replace": {&"dive": {"name": "Executioner", "kind": &"ap", "target": &"enemy_lowest",
				"steps": [{"do": "damage", "power": 0.9, "bonus_if": {"below": 0.5, "mult": 0.6}, "on_kill": [{"do": "gain", "res": &"ap", "n": 1}]}],
				"text": "90% Attack to the most hurt enemy (+60% below 50%). A kill refunds 1 AP."}}},
		{"id": &"sky_shield", "name": "Sky Shield", "text": "Each kill gives it Ward again.",
			"replace": {&"dive": {"name": "Dive", "kind": &"ap", "target": &"enemy_lowest",
				"steps": [{"do": "damage", "power": 0.9, "on_kill": [{"do": "ward"}]}], "text": "90% Attack to the most hurt enemy. A kill gives it Ward."}}},
		{"id": &"herald", "name": "Dawn Herald", "text": "Radiant Wing also heals allies in its row 10%.",
			"replace": {&"wing": {"name": "Dawn Herald", "kind": &"ap", "cost": 2, "target": &"enemy_row", "cond": &"has_ap_left", "arg": 2,
				"steps": [{"do": "damage", "power": 0.6}, {"do": "heal", "on": &"row_allies", "pct": 0.1}], "text": "Costs 2 AP. 60% to an enemy row; heals its row 10%."}}},
	])
