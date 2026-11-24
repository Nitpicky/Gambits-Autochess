class_name UnitCatalog
extends RefCounted
## Every unit, champion, token and monster as plain data.
## Stats come from a role template x rarity multiplier, optionally overridden.
## Gambits: explicit ones first, then the keyword gambits, then the role default.
## Sprites are Duelyst SpriteFrames copied to res://art/duelyst/units/.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY, CHAMPION, TOKEN, MONSTER }
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Champion", "Token", "Monster"]
const RARITY_COLORS := [Color("c8c8c8"), Color("5aa0f0"), Color("b070e8"), Color("f0a030"), Color("ff5a5a"), Color("888888"), Color("909090")]
const PRICES := [15, 20, 25, 30, 0, 0, 0]
const POOL_SIZE := [12, 9, 6, 4, 0, 0, 0]

## role -> base stats (HP, Attack, Defense, Initiative, AP, PP)
const ROLES := {
	&"tank": {"hp": 620, "atk": 55, "def": 18, "ini": 3, "ap": 2, "pp": 2, "row": 0},
	&"bruiser": {"hp": 520, "atk": 75, "def": 10, "ini": 5, "ap": 2, "pp": 1, "row": 0},
	&"striker": {"hp": 400, "atk": 85, "def": 6, "ini": 8, "ap": 2, "pp": 1, "row": 0},
	&"ranged": {"hp": 340, "atk": 72, "def": 4, "ini": 6, "ap": 2, "pp": 1, "row": 1},
	&"caster": {"hp": 320, "atk": 80, "def": 3, "ini": 5, "ap": 2, "pp": 2, "row": 1},
	&"support": {"hp": 360, "atk": 48, "def": 6, "ini": 4, "ap": 1, "pp": 3, "row": 1},
	&"token": {"hp": 160, "atk": 32, "def": 0, "ini": 2, "ap": 1, "pp": 0, "row": 1},
}
const RARITY_MULT := [1.0, 1.15, 1.3, 1.5, 1.75, 1.0, 1.0]

const ROLE_DEFAULT_GAMBIT := {
	&"tank": {"kind": &"ap", "action": &"strike"},
	&"bruiser": {"kind": &"ap", "action": &"strike"},
	&"striker": {"kind": &"ap", "action": &"strike"},
	&"ranged": {"kind": &"ap", "action": &"shoot"},
	&"caster": {"kind": &"ap", "action": &"shoot"},
	&"support": {"kind": &"ap", "action": &"shoot"},
	&"token": {"kind": &"ap", "action": &"strike"},
}

const KEYWORD_GAMBITS := {
	&"guard": {"kind": &"pp", "trigger": &"ally_targeted", "action": &"guard"},
	&"deathwatch": {"kind": &"pp", "trigger": &"any_died", "action": &"deathwatch_strike", "power": 0.6},
	&"sacrifice": {"kind": &"ap", "action": &"sacrifice", "cond": &"can_sacrifice", "power": 2.0},
}

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(id, {})


static func by_rarity(r: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all():
		if all()[id].rarity == r:
			out.append(id)
	return out


static func shop_units() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all():
		if all()[id].rarity <= Rarity.LEGENDARY:
			out.append(id)
	return out


static func _u(id: StringName, nm: String, faction: StringName, rarity: int, role: StringName, kws: Array, sprite: String, extra := {}) -> void:
	var r: Dictionary = ROLES[role]
	var m: float = RARITY_MULT[rarity]
	var d := {
		"id": id, "name": nm, "faction": faction, "rarity": rarity, "role": role,
		"keywords": kws, "sprite": sprite,
		"hp": roundf(r.hp * m * extra.get("hp_mult", 1.0)),
		"atk": roundf(r.atk * m * extra.get("atk_mult", 1.0)),
		"def": r["def"] + rarity * 2 + extra.get("def_add", 0),
		"ini": r.ini + extra.get("ini_add", 0),
		"ap": extra.get("ap", r.ap), "pp": extra.get("pp", r.pp),
		"row": extra.get("row", r.row),
		"passive": extra.get("passive", {}),
		"passive_text": extra.get("passive_text", ""),
		"token": extra.get("token", &""),
		"extra_actions": extra.get("extra_actions", 0),
		"text": extra.get("text", ""),
	}
	var g: Array = []
	for eg in extra.get("gambits", []):
		g.append(eg)
	for k in kws:
		if KEYWORD_GAMBITS.has(k):
			g.append(KEYWORD_GAMBITS[k])
	g.append(ROLE_DEFAULT_GAMBIT[role])
	d["gambits"] = g
	_cache[id] = d


static func _build() -> void:
	var C := Rarity.COMMON; var R := Rarity.RARE; var E := Rarity.EPIC; var L := Rarity.LEGENDARY
	var CH := Rarity.CHAMPION; var T := Rarity.TOKEN; var M := Rarity.MONSTER
	var heal_pp := {"kind": &"pp", "trigger": &"ally_damaged", "cond": &"target_below", "arg": 0.5, "action": &"heal", "power": 0.2}
	var heal_ap := {"kind": &"ap", "cond": &"ally_below", "arg": 0.7, "action": &"heal", "power": 0.25}
	# --- Lyonar
	_u(&"squire", "Squire", &"lyonar", C, &"tank", [&"guard"], "f1_silverguardsquire")
	_u(&"acolyte", "Acolyte", &"lyonar", C, &"support", [&"rally"], "f1_support", {"gambits": [heal_pp, heal_ap]})
	_u(&"lancer", "Lancer", &"lyonar", R, &"bruiser", [&"rally"], "f1_sunforgelancer", {"pp": 1, "gambits": [{"kind": &"pp", "trigger": &"self_hit_melee", "action": &"counter", "power": 0.6}]})
	_u(&"shieldmaiden", "Shieldmaiden", &"lyonar", R, &"tank", [&"guard", &"ward"], "f1_sunstonemaiden", {"ap": 1, "pp": 3})
	_u(&"sunforger", "Sunforger", &"lyonar", E, &"support", [&"rally", &"construct"], "f1_shieldforger", {"token": &"sun_totem", "pp": 2, "gambits": [{"kind": &"pp", "trigger": &"ally_damaged", "cond": &"target_below", "arg": 0.4, "action": &"ward_ally"}]})
	_u(&"grand_templar", "Grand Templar", &"lyonar", L, &"tank", [&"guard", &"rally"], "f1_sunstonetemplar", {"ap": 2, "pp": 3, "passive": {"type": &"row_aura", "stat": &"defense", "pct": 0.15}, "passive_text": "Battle start: allies in its row get +15% Defense."})
	# --- Vanar
	_u(&"frost_scout", "Frost Scout", &"vanar", C, &"ranged", [&"chill"], "f6_icehornet")
	_u(&"glacier_sentry", "Glacier Sentry", &"vanar", C, &"tank", [&"ward"], "f6_tundraguardian")
	_u(&"snow_chaser", "Snow Chaser", &"vanar", R, &"ranged", [&"chill", &"swift"], "f6_snowchaser", {"ap": 3, "pp": 0, "ini_add": 3})
	_u(&"aurora_priest", "Aurora Priest", &"vanar", R, &"support", [&"ward"], "f6_icedryad", {"gambits": [{"kind": &"pp", "trigger": &"ally_damaged", "cond": &"target_below", "arg": 0.6, "action": &"ward_ally"}, heal_ap]})
	_u(&"ice_warden", "Ice Warden", &"vanar", E, &"tank", [&"ward", &"guard"], "f6_auroraguardian", {"ap": 1, "pp": 3})
	_u(&"winter_queen", "Winter Queen", &"vanar", L, &"caster", [&"chill"], "f6_frostiva", {"gambits": [{"kind": &"ap", "action": &"chill_row", "power": 0.6}]})
	# --- Songhai
	_u(&"blade_novice", "Blade Novice", &"songhai", C, &"striker", [&"swift"], "f2_melee")
	_u(&"shadow_archer", "Shadow Archer", &"songhai", C, &"ranged", [&"mark"], "f2_ranged")
	_u(&"twin_fang", "Twin Fang", &"songhai", R, &"striker", [&"swift", &"feast"], "f2_katara", {"ap": 3, "pp": 0})
	_u(&"mist_dancer", "Mist Dancer", &"songhai", R, &"ranged", [&"mark", &"chill"], "f2_onnabugeisha", {"pp": 2, "gambits": [{"kind": &"pp", "trigger": &"self_targeted", "action": &"dodge"}]})
	_u(&"lantern_monk", "Lantern Monk", &"songhai", E, &"caster", [&"mark"], "f2_caster", {"gambits": [{"kind": &"ap", "action": &"mark_row", "power": 0.6}]})
	_u(&"storm_master", "Storm Master", &"songhai", L, &"striker", [&"swift"], "f2_stormkage", {"ap": 4, "pp": 1, "extra_actions": 1, "passive_text": "Takes 2 actions per turn."})
	# --- Magmar
	_u(&"hatchling", "Hatchling", &"magmar", C, &"bruiser", [&"grow"], "f5_silitharyoung", {"pp": 0})
	_u(&"raptor", "Raptor", &"magmar", C, &"striker", [&"feast"], "f5_minibeast")
	_u(&"stalker", "Stalker", &"magmar", R, &"striker", [&"feast", &"mark"], "f5_pteryx", {"ap": 3, "pp": 0})
	_u(&"earth_shaman", "Earth Shaman", &"magmar", R, &"support", [&"grow"], "f5_earthwalker", {"gambits": [{"kind": &"ap", "cond": &"ally_without", "arg_kw": &"grow", "action": &"grant_grow"}, heal_ap]})
	_u(&"bloodmaw", "Bloodmaw", &"magmar", E, &"bruiser", [&"grow", &"sacrifice"], "f5_ragebinder", {"passive": {"type": &"sacrifice_grows"}, "passive_text": "Each Sacrifice also triggers Grow twice."})
	_u(&"elder_behemoth", "Elder Behemoth", &"magmar", L, &"tank", [&"grow", &"feast"], "f5_silitharelder", {"pp": 2})
	# --- Abyssian
	_u(&"gloom_cultist", "Gloom Cultist", &"abyssian", C, &"caster", [&"sacrifice"], "f4_skullcaster")
	_u(&"bone_wraith", "Bone Wraith", &"abyssian", C, &"bruiser", [&"deathwatch"], "f4_gloomchaser", {"pp": 2})
	_u(&"shadow_spawner", "Shadow Spawner", &"abyssian", R, &"support", [&"sacrifice", &"construct"], "f4_daemongate", {"token": &"wraithling", "pp": 2})
	_u(&"night_fiend", "Night Fiend", &"abyssian", R, &"striker", [&"deathwatch", &"feast"], "f4_nightfiend", {"pp": 2})
	_u(&"void_priestess", "Void Priestess", &"abyssian", E, &"caster", [&"sacrifice", &"deathwatch"], "f4_shadowdancer", {"pp": 3})
	_u(&"lord_of_ruin", "Lord of Ruin", &"abyssian", L, &"bruiser", [&"deathwatch"], "f4_reaperninemoons", {"ap": 3, "pp": 3, "passive": {"type": &"ruin"}, "passive_text": "+6% Attack whenever any unit dies."})
	# --- Vetruvian
	_u(&"dune_warden", "Dune Warden", &"vetruvian", C, &"tank", [&"fortify"], "f3_irondervish", {"ap": 1})
	_u(&"obelisk_weaver", "Obelisk Weaver", &"vetruvian", C, &"support", [&"construct"], "f3_dunecaster", {"token": &"obelisk"})
	_u(&"sun_sentinel", "Sun Sentinel", &"vetruvian", R, &"tank", [&"fortify", &"guard"], "f3_keeperofages", {"ap": 1, "pp": 3})
	_u(&"scarab_herder", "Scarab Herder", &"vetruvian", R, &"support", [&"construct", &"deathwatch"], "f3_orbweaver", {"token": &"scarab"})
	_u(&"glass_colossus", "Glass Colossus", &"vetruvian", E, &"tank", [&"fortify"], "f3_anubis", {"hp_mult": 1.35, "ap": 1})
	_u(&"sand_sovereign", "Sand Sovereign", &"vetruvian", L, &"caster", [&"construct", &"fortify"], "f3_rae", {"token": &"obelisk", "passive": {"type": &"tokens_fortify"}, "passive_text": "Allied tokens gain Fortify."})
	# --- Champions (12, never in shop)
	_u(&"zir", "Grandmaster Zir", &"lyonar", CH, &"tank", [&"guard", &"rally"], "f1_grandmasterzir", {"pp": 4, "passive": {"type": &"row_aura", "stat": &"attack", "pct": 0.2}, "passive_text": "Battle start: allies in its row get +20% Attack."})
	_u(&"radiant_dragoon", "Radiant Dragoon", &"lyonar", CH, &"striker", [&"rally", &"ward"], "f1_radiantdragoon", {"ap": 3, "pp": 2})
	_u(&"embla", "Grandmaster Embla", &"vanar", CH, &"caster", [&"chill", &"ward"], "f6_grandmasterembla", {"gambits": [{"kind": &"ap", "action": &"chill_row", "power": 0.8}]})
	_u(&"draugar_lord", "Draugar Lord", &"vanar", CH, &"bruiser", [&"chill", &"mark"], "f6_draugarlord", {"ap": 3})
	_u(&"zendo", "Grandmaster Zendo", &"songhai", CH, &"striker", [&"swift", &"mark"], "f2_grandmasterzendo", {"ap": 4, "extra_actions": 1, "passive_text": "Takes 2 actions per turn."})
	_u(&"tai_kwai", "Master of Tai Kwai", &"songhai", CH, &"striker", [&"swift", &"feast"], "f2_masteroftaikwai", {"ap": 3, "ini_add": 3})
	_u(&"kraigon", "Grandmaster Kraigon", &"magmar", CH, &"bruiser", [&"grow", &"feast"], "f5_grandmasterkraigon", {"ap": 3})
	_u(&"dreadnaught", "Dreadnaught", &"magmar", CH, &"tank", [&"grow", &"sacrifice"], "f5_dreadnaught", {"passive": {"type": &"sacrifice_grows"}, "passive_text": "Each Sacrifice also triggers Grow twice."})
	_u(&"variax", "Grandmaster Variax", &"abyssian", CH, &"caster", [&"sacrifice", &"deathwatch"], "f4_grandmastervariax", {"pp": 4, "token": &"wraithling", "passive": {"type": &"ruin"}, "passive_text": "+6% Attack whenever any unit dies."})
	_u(&"desolater", "Desolater", &"abyssian", CH, &"bruiser", [&"deathwatch", &"fortify"], "f4_desolater", {"pp": 3})
	_u(&"noshrak", "Grandmaster Noshrak", &"vetruvian", CH, &"caster", [&"construct", &"fortify"], "f3_grandmasternoshrak", {"token": &"obelisk", "passive": {"type": &"tokens_fortify"}, "passive_text": "Allied tokens gain Fortify."})
	_u(&"sand_howler", "Sand Howler", &"vetruvian", CH, &"bruiser", [&"construct", &"rally"], "f3_sandhowler", {"token": &"scarab", "pp": 2})
	# --- Tokens
	_u(&"sun_totem", "Sun Totem", &"lyonar", T, &"token", [], "f1_sunwisp")
	_u(&"wraithling", "Wraithling", &"abyssian", T, &"token", [], "f4_miniminion")
	_u(&"obelisk", "Obelisk", &"vetruvian", T, &"token", [], "f3_endlessobelysk", {"hp_mult": 1.6, "atk_mult": 0.8})
	_u(&"scarab", "Scarab", &"vetruvian", T, &"token", [], "f3_miniscarab")
	# --- Monsters (PvE)
	_u(&"stone_golem", "Stone Golem", &"neutral", M, &"tank", [], "neutral_golemstone", {"row": 0})
	_u(&"saberspine", "Saberspine Tiger", &"neutral", M, &"striker", [], "neutral_beastsaberspinetiger")
	_u(&"phase_hound", "Phase Hound", &"neutral", M, &"striker", [&"swift"], "neutral_beastphasehound")
	_u(&"ice_golem", "Ice Golem", &"neutral", M, &"tank", [&"chill"], "neutral_golemice")
	_u(&"giant_crab", "Giant Crab", &"neutral", M, &"bruiser", [&"fortify"], "neutral_giantcrab")
	_u(&"sand_panther", "Sand Panther", &"neutral", M, &"bruiser", [&"feast"], "boss_sandpanther", {"hp_mult": 1.6, "atk_mult": 1.3})
