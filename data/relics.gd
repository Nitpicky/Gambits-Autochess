class_name RelicCatalog
extends RefCounted
## Relics: team-wide. Effect types: mod (a unit mod for every unit, or only one faction's units: "faction"),
## economy (player attribute, see modules/economy). Rarity comes from the price (10, 20, 30).
## Champions carry their own relic inside their kit (UnitCatalog def relic_name/relic_text, Roster relic_mod).
## PROTOTYPE: ported from the old relics onto the new keywords.

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id: StringName) -> Dictionary:
	return all().get(StringName(id), {})


static func _r(id: StringName, nm: String, price: int, icon: String, effect: Dictionary, text: String) -> void:
	var rarity: int = {10: 0, 20: 1, 30: 2}.get(price, 4)
	_cache[id] = {"id": id, "name": nm, "price": price, "icon": icon, "needs": {}, "effect": effect, "text": text, "rarity": rarity, "champion": price == 0}


static func _mod(m: Dictionary, faction: StringName = &"") -> Dictionary:
	return {"type": &"mod", "faction": faction, "mod": m}


## Relics the shop and other rewards can offer.
static func shop_relics() -> Array:
	return all().keys().filter(func(k): return not all()[k].champion)


static func _build() -> void:
	_r(&"war_banner", "War Banner", 10, "icon_f1_lionheartblessing", _mod({"stats": {"atk": 1}}), "All units +5 Attack.")
	_r(&"merchants_purse", "Merchant's Purse", 10, "generalspell_f2_twilightsurge", {"type": &"economy", "gold": 2}, "+2 gold per round.")
	_r(&"lucky_coin", "Lucky Coin", 20, "icon_f3_scionsfirstwish", {"type": &"economy", "free_rerolls": 1}, "Your second reroll each round is also free.")
	_r(&"mentors_tome", "Mentor's Tome", 20, "generalspell_f3_psionicrecall", {"type": &"economy", "xp": 3}, "+3 free XP per round.")
	_r(&"chorus_bell", "Chorus Bell", 20, "icon_f2_mana_vortex", _mod({"stats": {"pp": 1}}), "All units +1 PP.")
	_r(&"hourglass", "Hourglass", 30, "icon_f3_astraflood", _mod({"stats": {"ap": 1}}), "All units +1 AP.")
	_r(&"sunforge_crest", "Sunforge Crest", 20, "icon_f1_sunbloom", _mod({"kw": {"tough": 1}}, &"lyonar"), "Lyonar units have Tough 1.")
	_r(&"heart_of_winter", "Heart of Winter", 20, "icon_f6_flashfreeze", _mod({"kw": {"barrier_start": 1}}, &"vanar"), "Vanar units start each fight with Barrier.")
	_r(&"shrouded_path", "Shrouded Path", 20, "icon_f2_mistwalking", _mod({"kw": {"backstab": 1}}, &"songhai"), "Songhai units have Backstab 1.")
	_r(&"primal_totem", "Primal Totem", 30, "icon_f5_naturalselection", _mod({"kw": {"regen": 1}}, &"magmar"), "Magmar units have Regenerate 1.")
	_r(&"abyssal_altar", "Abyssal Altar", 30, "icon_f4_darkfiresacrifice", _mod({"trig": [{"on": "warcry", "fx": [{"do": "souls", "n": 1}]}]}, &"abyssian"), "Each Abyssian unit brings 1 Soul to the fight.")
	_r(&"sun_obelisk", "Sun Obelisk", 30, "icon_f3_summoningstones", _mod({"trig": [{"on": "warcry", "fx": [{"do": "stall_mod", "on": "self", "n": -1}]}]}, &"vetruvian"), "Vetruvian units' Stall effects come 1 turn sooner.")
