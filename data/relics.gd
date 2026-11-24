class_name RelicCatalog
extends RefCounted
## Relics: team-wide. `needs` = {"faction": f, "count": 2} to switch on.
## Effect types: team_flat (flat stat for every unit), economy, flag (read by battle behaviours).
## Rarity comes from the price (10 common, 20 rare, 30 epic); champion relics only come with their champion.

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(id, {})


static func _r(id: StringName, nm: String, price: int, icon: String, needs: Dictionary, effect: Dictionary, text: String) -> void:
	var rarity: int = {10: 0, 20: 1, 30: 2}.get(price, 4)
	_cache[id] = {"id": id, "name": nm, "price": price, "icon": icon, "needs": needs, "effect": effect, "text": text, "rarity": rarity, "champion": price == 0}


## Relics the shop and other rewards can offer (champion relics excluded).
static func shop_relics() -> Array:
	return all().keys().filter(func(k): return not all()[k].champion)


static func _build() -> void:
	_r(&"war_banner", "War Banner", 10, "icon_f1_lionheartblessing", {}, {"type": &"team_flat", "stat": &"attack", "value": 1}, "All units +1 Attack.")
	_r(&"merchants_purse", "Merchant's Purse", 10, "generalspell_f2_twilightsurge", {}, {"type": &"economy", "gold": 2}, "+2 gold per round.")
	_r(&"lucky_coin", "Lucky Coin", 20, "icon_f3_scionsfirstwish", {}, {"type": &"economy", "free_rerolls": 1}, "Your second reroll each round is also free.")
	_r(&"mentors_tome", "Mentor's Tome", 20, "generalspell_f3_psionicrecall", {}, {"type": &"economy", "xp": 3}, "+3 free XP per round.")
	_r(&"chorus_bell", "Chorus Bell", 20, "icon_f2_mana_vortex", {}, {"type": &"team_flat", "stat": &"pp", "value": 1}, "All units +1 PP.")
	_r(&"hourglass", "Hourglass", 30, "icon_f3_astraflood", {}, {"type": &"team_flat", "stat": &"ap", "value": 1}, "All units +1 AP.")
	_r(&"sunforge_crest", "Sunforge Crest", 20, "icon_f1_sunbloom", {"faction": &"lyonar", "count": 2}, {"type": &"flag", "flag": &"rally_dr", "value": 0.05}, "Each Rally stack also gives 5% damage reduction.")
	_r(&"heart_of_winter", "Heart of Winter", 20, "icon_f6_flashfreeze", {"faction": &"vanar", "count": 2}, {"type": &"flag", "flag": &"freeze_at", "value": 2}, "Frozen triggers at 2 Chill stacks instead of 3.")
	_r(&"shrouded_path", "Shrouded Path", 20, "icon_f2_mistwalking", {"faction": &"songhai", "count": 2}, {"type": &"flag", "flag": &"swift_pct", "value": 0.4}, "Swift bonus rises to +40% damage.")
	_r(&"primal_totem", "Primal Totem", 30, "icon_f5_naturalselection", {"faction": &"magmar", "count": 2}, {"type": &"flag", "flag": &"grow_at_start"}, "Grow also triggers once at battle start.")
	_r(&"abyssal_altar", "Abyssal Altar", 30, "icon_f4_darkfiresacrifice", {"faction": &"abyssian", "count": 2}, {"type": &"flag", "flag": &"altar"}, "The first allied death each battle summons a Wraithling.")
	_r(&"sun_obelisk", "Sun Obelisk", 30, "icon_f3_summoningstones", {"faction": &"vetruvian", "count": 2}, {"type": &"flag", "flag": &"extra_token"}, "Each Construct summons 1 extra token.")
	# --- Champion relics (price 0: never sold, only come with their champion)
	_r(&"relic_zir", "Zir's Banner", 0, "icon_f1_warsurge", {}, {"type": &"team_flat", "stat": &"damage_reduction", "value": 0.05}, "All units take 5% less damage.")
	_r(&"relic_dragoon", "Dragoon's Charge", 0, "icon_f1_chargeintobattle", {}, {"type": &"team_flat", "stat": &"initiative", "value": 1}, "All units +1 Speed.")
	_r(&"relic_embla", "Embla's Corona", 0, "icon_f6_frigidcorona", {}, {"type": &"flag", "flag": &"freeze_at", "value": 2}, "Frozen triggers at 2 Chill stacks.")
	_r(&"relic_draugar", "Draugar's Avalanche", 0, "icon_f6_avalanche", {}, {"type": &"team_flat", "stat": &"hp", "value": 25}, "All units +25 HP.")
	_r(&"relic_zendo", "Eight Gates", 0, "icon_f2_eightgates", {}, {"type": &"team_flat", "stat": &"ap", "value": 1}, "All units +1 AP.")
	_r(&"relic_taikwai", "Twin Strike", 0, "icon_f2_twin_strike", {}, {"type": &"flag", "flag": &"swift_pct", "value": 0.4}, "Swift bonus rises to +40% damage.")
	_r(&"relic_kraigon", "Bloodrage", 0, "icon_f5_bloodrage", {}, {"type": &"team_flat", "stat": &"attack", "value": 2}, "All units +2 Attack.")
	_r(&"relic_dreadnaught", "Greater Fortitude", 0, "icon_f5_greaterfortitude", {}, {"type": &"flag", "flag": &"grow_at_start"}, "Grow also triggers once at battle start.")
	_r(&"relic_variax", "Wraithling Swarm", 0, "icon_f4_wraithlingswarm", {}, {"type": &"flag", "flag": &"altar"}, "The first allied death each battle summons a Wraithling.")
	_r(&"relic_desolater", "Doom", 0, "icon_f4_doom", {}, {"type": &"team_flat", "stat": &"pp", "value": 1}, "All units +1 PP.")
	_r(&"relic_noshrak", "Stones to Spears", 0, "icon_f3_stonestospears", {}, {"type": &"flag", "flag": &"extra_token"}, "Each Construct summons 1 extra token.")
	_r(&"relic_howler", "Sandwave", 0, "icon_f3_sandwave", {}, {"type": &"team_flat", "stat": &"hp", "value": 25}, "All units +25 HP.")
