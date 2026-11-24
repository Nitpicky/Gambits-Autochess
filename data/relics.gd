class_name RelicCatalog
extends RefCounted
## Relics: team-wide. `needs` = {"faction": f, "count": 2} to switch on.
## Effect types: team_stat, economy, flag (read by battle behaviours).

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(id, {})


static func _r(id: StringName, nm: String, price: int, icon: String, needs: Dictionary, effect: Dictionary, text: String) -> void:
	_cache[id] = {"id": id, "name": nm, "price": price, "icon": icon, "needs": needs, "effect": effect, "text": text}


static func _build() -> void:
	_r(&"war_banner", "War Banner", 10, "icon_f1_lionheartblessing", {}, {"type": &"team_stat", "stat": &"attack", "pct": 0.05}, "All units +5% Attack.")
	_r(&"merchants_purse", "Merchant's Purse", 10, "generalspell_f2_twilightsurge", {}, {"type": &"economy", "gold": 2}, "+2 gold per round.")
	_r(&"lucky_coin", "Lucky Coin", 20, "icon_f3_scionsfirstwish", {}, {"type": &"economy", "free_rerolls": 1}, "Your second reroll each round is also free.")
	_r(&"mentors_tome", "Mentor's Tome", 20, "generalspell_f3_psionicrecall", {}, {"type": &"economy", "xp": 3}, "+3 free XP per round.")
	_r(&"chorus_bell", "Chorus Bell", 20, "icon_f2_mana_vortex", {}, {"type": &"team_flat", "stat": &"pp", "value": 1}, "All units +1 PP.")
	_r(&"hourglass", "Hourglass", 30, "icon_f3_astraflood", {}, {"type": &"team_flat", "stat": &"ap", "value": 1}, "All units +1 AP.")
	_r(&"sunforge_crest", "Sunforge Crest", 20, "icon_f1_sunbloom", {"faction": &"lyonar", "count": 2}, {"type": &"flag", "flag": &"rally_dr", "value": 0.05}, "Each Rally stack also gives 5% damage reduction.")
	_r(&"heart_of_winter", "Heart of Winter", 20, "icon_f6_flashfreeze", {"faction": &"vanar", "count": 2}, {"type": &"flag", "flag": &"freeze_at", "value": 2}, "Frozen triggers at 2 Chill stacks instead of 3.")
	_r(&"shrouded_path", "Shrouded Path", 20, "icon_f2_mistwalking", {"faction": &"songhai", "count": 2}, {"type": &"flag", "flag": &"swift_pct", "value": 0.4}, "Swift bonus rises to +40%.")
	_r(&"primal_totem", "Primal Totem", 30, "icon_f5_naturalselection", {"faction": &"magmar", "count": 2}, {"type": &"flag", "flag": &"grow_at_start"}, "Grow also triggers once at battle start.")
	_r(&"abyssal_altar", "Abyssal Altar", 30, "icon_f4_darkfiresacrifice", {"faction": &"abyssian", "count": 2}, {"type": &"flag", "flag": &"altar"}, "The first allied death each battle summons a Wraithling.")
	_r(&"sun_obelisk", "Sun Obelisk", 30, "icon_f3_summoningstones", {"faction": &"vetruvian", "count": 2}, {"type": &"flag", "flag": &"extra_token"}, "Each Construct summons 1 extra token.")
