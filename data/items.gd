class_name ItemCatalog
extends RefCounted
## Items: flat stats + one effect. Effects are interpreted by modules/battle/effects.gd.
## `req`: {"factions": [...], "keywords": [...], "row": 0} -- any listed faction OR keyword passes.

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(id, {})


static func _i(id: StringName, nm: String, price: int, icon: String, stats: Dictionary, kind: String, req: Dictionary, effect: Dictionary, text: String) -> void:
	# Stats are scaled like unit stats: HP in steps of HP_STEP, Attack/Defense scaled down.
	var s := {}
	for k in stats:
		match k:
			"hp": s[k] = GameConfig.round_hp(stats[k] * GameConfig.HP_SCALE)
			"atk": s[k] = maxf(1.0, roundf(stats[k] * GameConfig.ATK_SCALE))
			"def": s["dr"] = maxf(0.05, roundf(stats[k] * 0.015 / 0.05) * 0.05)  # PROTOTYPE: old Defense -> % damage reduction
			_: s[k] = stats[k]
	var rarity: int = {5: 0, 15: 1, 25: 2}.get(price, 0)
	_cache[id] = {"id": id, "name": nm, "price": price, "icon": icon, "stats": s, "kind": kind, "req": req, "effect": effect, "text": text, "rarity": rarity}


static func by_rarity(r: int) -> Array:
	return all().keys().filter(func(k): return all()[k].rarity == r)


static func _build() -> void:
	_i(&"iron_band", "Iron Band", 5, "artifact_f1_ironbanner", {"hp": 80}, "Passive", {}, {"type": &"heal_turn_start", "pct": 0.05}, "Heals 5% max HP at each of its turn starts.")
	_i(&"whetstone", "Whetstone", 5, "artifact_f3_spinecleaver", {"atk": 6}, "Passive", {}, {"type": &"first_attack_bonus", "pct": 0.2}, "First attack each battle deals +20% damage.")
	_i(&"stone_skin", "Stone Skin", 5, "artifact_f5_irridiumscale", {"def": 4}, "Passive", {}, {"type": &"row_resist", "pct": 0.15}, "Takes 15% less damage from row-wide attacks.")
	_i(&"quick_boots", "Quick Boots", 5, "artifact_f2_cyclonemask", {"ini": 1}, "Passive", {}, {"type": &"tiebreak"}, "Wins every Speed tie.")
	_i(&"hunters_eye", "Hunter's Eye", 5, "artifact_f2_maskofshadows", {"atk": 4}, "Passive", {}, {"type": &"status_on_hit", "status": &"mark", "first_only": true}, "First hit each battle applies Mark.")
	_i(&"taunting_horn", "Taunting Horn", 5, "artifact_f1_skywindglaives", {"hp": 100}, "Behaviour", {"row": 0}, {"type": &"taunt"}, "Melee enemies must target this unit.")
	_i(&"focus_gem", "Focus Gem", 15, "artifact_f2_unboundedenergyamulet", {"atk": 6, "ini": 1, "ap": 1}, "Resource", {}, {}, "+1 AP.")
	_i(&"prayer_bead", "Prayer Bead", 15, "artifact_f1_dawnseye", {"hp": 80, "def": 2, "pp": 1}, "Resource", {}, {}, "+1 PP.")
	_i(&"bandolier", "Bandolier", 15, "artifact_f3_sandscepter", {"hp": 60}, "Utility", {}, {"type": &"extra_slot"}, "+1 item slot (takes none itself).")
	_i(&"vampiric_fang", "Vampiric Fang", 15, "artifact_f2_bloodleechmask", {"atk": 8}, "Passive", {}, {"type": &"lifesteal", "pct": 0.15}, "Heals 15% of damage dealt.")
	_i(&"thorn_mail", "Thorn Mail", 15, "artifact_f6_frostplate", {"hp": 60, "def": 6}, "Passive", {}, {"type": &"thorns", "pct": 0.2}, "Reflects 20% of melee damage taken.")
	_i(&"healing_charm", "Healing Charm", 15, "artifact_f3_repairstaff", {"hp": 100}, "PP action", {}, {"type": &"gambit", "gambit": {"kind": &"pp", "trigger": &"ally_damaged", "cond": &"target_below", "arg": 0.5, "action": &"heal", "power": 0.2}}, "PP: when an ally drops below 50%, heal it 20%.")
	_i(&"riposte_blade", "Riposte Blade", 15, "artifact_f2_crescentspear", {"atk": 8}, "PP action", {}, {"type": &"gambit", "gambit": {"kind": &"pp", "trigger": &"self_hit_melee", "action": &"counter", "power": 0.7}}, "PP: counterattack when hit in melee.")
	_i(&"bomb_satchel", "Bomb Satchel", 15, "artifact_f3_thunderclap", {"atk": 6}, "AP action", {}, {"type": &"gambit", "gambit": {"kind": &"ap", "action": &"row_strike", "power": 0.5}}, "AP: hit a whole enemy row for 50% Attack.")
	_i(&"lion_crest", "Lion Crest", 15, "artifact_f1_bigshield", {"hp": 120, "def": 3}, "Keyword", {"row": 0}, {"type": &"keyword", "keyword": &"guard"}, "Gains Guard.")
	_i(&"frost_shard", "Frost Shard", 15, "artifact_f6_frostbiter", {"atk": 6, "ini": 1}, "Keyword", {"factions": [&"vanar", &"songhai"]}, {"type": &"keyword", "keyword": &"chill"}, "Gains Chill.")
	_i(&"scarab_idol", "Scarab Idol", 15, "artifact_f3_staffofykir", {"hp": 80}, "Keyword", {"factions": [&"vetruvian", &"abyssian"]}, {"type": &"keyword", "keyword": &"construct", "token": &"scarab"}, "Gains Construct (summons a Scarab).")
	_i(&"berserker_mask", "Berserker Mask", 15, "artifact_f2_markgorehorn", {"atk": 15}, "Behaviour", {}, {"type": &"berserk"}, "Always targets the lowest-HP enemy and never uses PP support actions.")
	_i(&"cowards_cloak", "Coward's Cloak", 15, "artifact_f4_ghostazalea", {"hp": 80, "ini": 2}, "Behaviour", {}, {"type": &"coward", "threshold": 0.4, "value": 0.15}, "Below 40% HP, moves to the back row and takes 15% less damage.")
	_i(&"tower_shield", "Tower Shield", 15, "artifact_f1_shieldofphalanx", {"def": 6}, "Synergy", {"keywords": [&"guard"]}, {"type": &"flag", "flag": &"free_first_guard"}, "First Guard each battle costs no PP.")
	_i(&"blood_chalice", "Blood Chalice", 15, "artifact_f4_heartborrower", {"hp": 100}, "Synergy", {"keywords": [&"sacrifice"]}, {"type": &"flag", "flag": &"sacrifice_heal", "value": 0.15}, "Sacrifice also heals this unit 15%.")
	_i(&"sun_lantern", "Sun Lantern", 15, "artifact_f1_sunstonebracers", {"hp": 80, "def": 3}, "Synergy", {"factions": [&"lyonar"]}, {"type": &"flag", "flag": &"rally_heal", "value": 0.05}, "Each Rally also heals its row 5%.")
	_i(&"titans_belt", "Titan's Belt", 25, "artifact_f5_adamantineclaws", {"hp": 250, "ini": -1}, "Passive", {}, {"type": &"flag", "flag": &"immune_frozen"}, "Can't be Frozen.")
	_i(&"executioners_edge", "Executioner's Edge", 25, "artifact_f4_spectralblade", {"atk": 14}, "Passive", {}, {"type": &"execute", "pct": 0.25, "threshold": 0.3}, "+25% damage to targets below 30% HP.")
	_i(&"phoenix_feather", "Phoenix Feather", 25, "artifact_f5_eternalheart", {"hp": 150}, "Passive", {}, {"type": &"phoenix"}, "Once per battle, survives a lethal hit at 1 HP.")
	_i(&"ritual_dagger", "Ritual Dagger", 25, "artifact_f4_soulgrimwar", {"atk": 12}, "AP action", {"factions": [&"abyssian"], "keywords": [&"construct"]}, {"type": &"gambit", "gambit": {"kind": &"ap", "action": &"sacrifice", "cond": &"has_token", "power": 2.0}}, "AP: consume an allied token to deal 200% Attack.")
	_i(&"mutagen_vial", "Mutagen Vial", 25, "artifact_f5_eggsoul", {"hp": 150}, "Keyword", {"factions": [&"magmar"], "keywords": [&"feast"]}, {"type": &"keyword", "keyword": &"grow"}, "Gains Grow.")
	_i(&"zealots_chain", "Zealot's Chain", 25, "artifact_f4_darkstonering", {"atk": 12, "def": 4}, "Behaviour", {}, {"type": &"zealot"}, "Can't use PP. Each unspent PP becomes +3 Attack.")
	_i(&"grafting_seed", "Grafting Seed", 25, "artifact_f5_morinkhur", {"hp": 150}, "Synergy", {"factions": [&"magmar"]}, {"type": &"flag", "flag": &"grow_atk", "value": 3}, "Grow gives +3 Attack instead of +2.")
	_i(&"bone_charm", "Bone Charm", 25, "artifact_f4_hornofforsaken", {"atk": 8, "hp": 100}, "Synergy", {"keywords": [&"deathwatch"]}, {"type": &"flag", "flag": &"deathwatch_refund", "value": 3}, "Each Deathwatch trigger refunds 1 PP, up to 3 per battle.")
	_i(&"mirror_blade", "Mirror Blade", 25, "artifact_f2_spellfan", {"atk": 12, "ini": 1}, "Synergy", {"factions": [&"songhai"]}, {"type": &"flag", "flag": &"kill_extra_action"}, "After a kill, takes an extra action at 50% damage.")
	_i(&"glacier_heart", "Glacier Heart", 25, "artifact_f6_winterblade", {"atk": 10, "def": 5}, "Synergy", {"factions": [&"vanar"]}, {"type": &"flag", "flag": &"frozen_vuln", "value": 0.3}, "Frozen enemies take +30% damage from this unit.")
	_i(&"sandglass", "Sandglass", 25, "artifact_f3_hexblade", {"hp": 120, "def": 8}, "Synergy", {"factions": [&"vetruvian"]}, {"type": &"flag", "flag": &"fortify_cap", "value": 0.6}, "Fortify stacks up to 60% instead of 40%.")
	_i(&"battle_fury", "Battle Fury", 15, "artifact_f2_crescentspear", {"atk": 4}, "Passive", {}, {"type": &"flag", "flag": &"dmg_bonus", "value": 0.1}, "Deals +10% damage.")
	_i(&"giant_slayer", "Giant Slayer", 25, "artifact_f4_spectralblade", {"atk": 8}, "Passive", {}, {"type": &"flag", "flag": &"pct_hp_damage", "value": 0.06}, "Hits also deal 6% of the target's max HP.")
	_i(&"bulwark", "Bulwark", 25, "artifact_f1_shieldofphalanx", {"hp": 150}, "Passive", {}, {"type": &"flag", "flag": &"flat_dr", "value": 0.15}, "Takes 15% less damage.")


static func meets_req(item: Dictionary, unit_def: Dictionary, keywords: Array, row: int = -1) -> bool:
	var req: Dictionary = item.req
	if req.has("row") and row != -1 and row != req.row:
		return false
	var fs: Array = req.get("factions", [])
	var ks: Array = req.get("keywords", [])
	if fs.is_empty() and ks.is_empty():
		return true
	if unit_def.faction in fs:
		return true
	for k in ks:
		if k in keywords:
			return true
	return false


static func req_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	for f in item.req.get("factions", []):
		parts.append(Keywords.FACTION_NAMES[f])
	for k in item.req.get("keywords", []):
		parts.append(Keywords.kw_name(k))
	var s := " or ".join(parts)
	if item.req.has("row"):
		s = (s + ", " if s != "" else "") + ("front row" if item.req.row == 0 else "back row")
	return s
