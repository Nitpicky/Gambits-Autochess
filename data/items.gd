class_name ItemCatalog
extends RefCounted
## Items: flat stats (game units) + a "mod" (same format as upgrade cards: kw, trig, acts, flags) read by
## BattleSim._apply_mod. PROTOTYPE: the old 33 items ported onto the new keywords, not a real item design.
## `req`: {"factions": [...], "keywords": [...], "row": 0} -- any listed faction OR keyword passes.

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(StringName(id), {})


static func _i(id: StringName, nm: String, price: int, icon: String, stats: Dictionary, req: Dictionary, mod: Dictionary, text: String) -> void:
	var rarity: int = {5: 0, 15: 1, 25: 2}.get(price, 0)
	var kws: Array = []
	for k in mod.get("kw", {}):
		if not Keywords.get_kw(StringName(k)).is_empty():
			kws.append(StringName(k))
	_cache[id] = {"id": id, "name": nm, "price": price, "icon": icon, "stats": stats, "req": req,
		"effect": {"type": &"mod"}, "mod": mod, "keywords": kws, "text": text, "rarity": rarity, "kind": "Item"}


static func by_rarity(r: int) -> Array:
	return all().keys().filter(func(k): return all()[k].rarity == r)


static func _act(id: String, nm: String, cost: int, tgt: String, fx: Array, extra: Dictionary = {}) -> Dictionary:
	var a := {"id": id, "name": nm, "kind": "ap", "cost": cost, "tgt": tgt, "fx": fx}
	a.merge(extra)
	return a


static func _build() -> void:
	_i(&"iron_band", "Iron Band", 5, "artifact_f1_ironbanner", {"hp": 20}, {}, {"kw": {"regen": 1}}, "Regenerate 1.")
	_i(&"whetstone", "Whetstone", 5, "artifact_f3_spinecleaver", {"atk": 5}, {}, {"kw": {"backstab": 1}}, "Backstab 1.")
	_i(&"stone_skin", "Stone Skin", 5, "artifact_f5_irridiumscale", {}, {}, {"kw": {"tough": 1}}, "Tough 1.")
	_i(&"quick_boots", "Quick Boots", 5, "artifact_f2_cyclonemask", {"ini": 2}, {}, {}, "+2 Speed.")
	_i(&"hunters_eye", "Hunter's Eye", 5, "artifact_f2_maskofshadows", {"atk": 5}, {}, {"trig": [{"on": "bitemark", "once": true, "fx": [{"do": "status", "on": "target", "id": "vuln", "n": 1}]}]}, "First hit each fight makes the target Vulnerable.")
	_i(&"taunting_horn", "Taunting Horn", 5, "artifact_f1_skywindglaives", {"hp": 40}, {"row": 0}, {"kw": {"taunt": 1}}, "Taunt.")
	_i(&"focus_gem", "Focus Gem", 15, "artifact_f2_unboundedenergyamulet", {"atk": 5, "ap": 1}, {}, {}, "+1 AP.")
	_i(&"prayer_bead", "Prayer Bead", 15, "artifact_f1_dawnseye", {"hp": 20, "pp": 1}, {}, {}, "+1 PP.")
	_i(&"smoke_mask", "Smoke Mask", 15, "artifact_f3_sandscepter", {"ini": 1}, {}, {"kw": {"vanish": 1}}, "Vanish.")
	_i(&"vampiric_fang", "Vampiric Fang", 15, "artifact_f2_bloodleechmask", {"atk": 5}, {}, {"kw": {"lifesteal": 1}}, "Lifesteal.")
	_i(&"thorn_mail", "Thorn Mail", 15, "artifact_f6_frostplate", {"hp": 20}, {}, {"kw": {"tough": 1}, "trig": [{"on": "hit_taken", "fx": [{"do": "dmg", "on": "source", "n": 1}]}]}, "Tough 1. When hit, deals 5 damage back.")
	_i(&"healing_charm", "Healing Charm", 15, "artifact_f3_repairstaff", {"hp": 40}, {}, {"acts": [_act("charm_heal", "Healing Charm", 1, "ally_lowest", [{"do": "heal", "n": 4}], {"cond": "ally_hurt", "text": "1 AP: heal the lowest ally 20."})]}, "Action (1 AP): heal the lowest ally 20.")
	_i(&"riposte_blade", "Riposte Blade", 15, "artifact_f2_crescentspear", {"atk": 5}, {}, {"kw": {"strikeback": 1}}, "Strikeback.")
	_i(&"bomb_satchel", "Bomb Satchel", 15, "artifact_f3_thunderclap", {"atk": 5}, {}, {"acts": [_act("bomb", "Bomb", 3, "foe_front_row", [{"do": "hit", "p": 0.7}], {"text": "3 AP: hit the enemy front row for 70% Attack."})]}, "Action (3 AP): hit the enemy front row for 70% Attack.")
	_i(&"lion_crest", "Lion Crest", 15, "artifact_f1_bigshield", {"hp": 40}, {"row": 0}, {"kw": {"guard": 1}}, "Guard.")
	_i(&"frost_shard", "Frost Shard", 15, "artifact_f6_frostbiter", {"atk": 5}, {"factions": [&"vanar", &"songhai"]}, {"kw": {"hit_chill": 1}}, "Hits apply Chill 1.")
	_i(&"scarab_idol", "Scarab Idol", 15, "artifact_f3_staffofykir", {"hp": 20}, {"factions": [&"vetruvian", &"abyssian"]}, {"trig": [{"on": "warcry", "fx": [{"do": "summon", "tok": "scarab"}]}]}, "Warcry: summon a Scarab.")
	_i(&"berserker_mask", "Berserker Mask", 15, "artifact_f2_markgorehorn", {"atk": 15}, {}, {"flags": {"berserk_target": 1}}, "Its attacks always go for the lowest-HP enemy it can reach.")
	_i(&"cowards_cloak", "Coward's Cloak", 15, "artifact_f4_ghostazalea", {"hp": 20, "ini": 2}, {}, {"trig": [{"on": "below_half", "once": true, "fx": [{"do": "barrier", "on": "self"}]}]}, "The first time it drops below half HP, gains Barrier.")
	_i(&"tower_shield", "Tower Shield", 15, "artifact_f1_shieldofphalanx", {}, {}, {"kw": {"tough": 1, "barrier_start": 1}}, "Tough 1. Starts each fight with Barrier.")
	_i(&"blood_chalice", "Blood Chalice", 15, "artifact_f4_heartborrower", {"hp": 40}, {"factions": [&"abyssian"]}, {"trig": [{"on": "ally_died", "fx": [{"do": "souls", "n": 1}]}]}, "Whenever an ally dies, +1 Soul.")
	_i(&"sun_lantern", "Sun Lantern", 15, "artifact_f1_sunstonebracers", {"hp": 20}, {"factions": [&"lyonar"]}, {"trig": [{"on": "turn", "every": 2, "fx": [{"do": "heal", "on": "row_allies", "n": 2}]}]}, "Every 2nd turn, heals its row 10.")
	_i(&"titans_belt", "Titan's Belt", 25, "artifact_f5_adamantineclaws", {"hp": 80, "ini": -1}, {}, {"flags": {"immune_frozen": 1}}, "Can't be Frozen.")
	_i(&"executioners_edge", "Executioner's Edge", 25, "artifact_f4_spectralblade", {"atk": 10}, {}, {"flags": {"execute": 2}}, "+10 damage to targets below 30% HP.")
	_i(&"phoenix_feather", "Phoenix Feather", 25, "artifact_f5_eternalheart", {"hp": 40}, {}, {"kw": {"undying": 1}, "flags": {"undying_pct": 0.25}}, "Once per fight, survives a lethal hit at 25% HP.")
	_i(&"ritual_dagger", "Ritual Dagger", 25, "artifact_f4_soulgrimwar", {"atk": 10}, {"factions": [&"abyssian"]}, {"acts": [_act("ritual", "Ritual", 1, "token_any", [{"do": "sacrifice", "then": [{"do": "hit", "on": "foe", "p": 2}]}], {"cond": "has_token", "text": "1 AP: sacrifice an allied token, then hit for 200% Attack."})]}, "Action (1 AP): sacrifice an allied token, then hit for 200% Attack.")
	_i(&"mutagen_vial", "Mutagen Vial", 25, "artifact_f5_eggsoul", {"hp": 40}, {"factions": [&"magmar"]}, {"kw": {"grow": 1}}, "Grow 1.")
	_i(&"zealots_chain", "Zealot's Chain", 25, "artifact_f4_darkstonering", {"atk": 10}, {}, {"kw": {"zeal": 1}}, "Zeal 1.")
	_i(&"grafting_seed", "Grafting Seed", 25, "artifact_f5_morinkhur", {"hp": 40}, {"factions": [&"magmar"]}, {"kw": {"rebirth": 1}}, "Rebirth.")
	_i(&"bone_charm", "Bone Charm", 25, "artifact_f4_hornofforsaken", {"atk": 5, "hp": 40}, {}, {"trig": [{"on": "deathwatch", "fx": [{"do": "buff", "on": "self", "stat": "atk", "n": 1}]}]}, "Deathwatch: +5 Attack.")
	_i(&"mirror_blade", "Mirror Blade", 25, "artifact_f2_spellfan", {"atk": 10}, {"factions": [&"songhai"]}, {"trig": [{"on": "kill", "per_turn": 1, "fx": [{"do": "extra_action"}]}]}, "After a kill, takes an extra action (once per turn).")
	_i(&"glacier_heart", "Glacier Heart", 25, "artifact_f6_winterblade", {"atk": 10}, {"factions": [&"vanar"]}, {"kw": {"frozen_bonus": 2}}, "+10 damage to Frozen enemies.")
	_i(&"sandglass", "Sandglass", 25, "artifact_f3_hexblade", {"hp": 40}, {"factions": [&"vetruvian"]}, {"trig": [{"on": "warcry", "fx": [{"do": "stall_mod", "on": "self", "n": -1}]}]}, "Its Stall effects come 1 turn sooner.")
	_i(&"battle_fury", "Battle Fury", 15, "artifact_f2_crescentspear", {"atk": 10}, {}, {}, "+10 Attack.")
	_i(&"giant_slayer", "Giant Slayer", 25, "artifact_f4_spectralblade", {"atk": 5}, {}, {"flags": {"pct_hp": 0.06}}, "Hits also deal 6% of the target's max HP.")
	_i(&"bulwark", "Bulwark", 25, "artifact_f1_shieldofphalanx", {"hp": 60}, {}, {"kw": {"tough": 2}}, "Tough 2.")


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
