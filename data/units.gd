class_name UnitCatalog
extends RefCounted
## Every unit, champion, token and monster, built from the roster (data/roster.gd).
## Doc stats are relative (HP / Attack / Speed 1..9); game numbers are HP x HP_UNIT, Attack x ATK_UNIT.
## Sprites are Duelyst SpriteFrames copied to res://art/duelyst/units/.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY, CHAMPION, TOKEN, MONSTER }
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Champion", "Token", "Monster"]
const RARITY_COLORS := [Color("2fb58a"), Color("2aa8c4"), Color("c55fd0"), Color("ef5b2f"), Color("f5a623"), Color("888888"), Color("909090")]
const PRICES := [15, 20, 25, 30, 0, 0, 0]
const POOL_SIZE := [12, 9, 6, 4, 0, 0, 0]

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func get_def(id) -> Dictionary:
	return all().get(StringName(id), {})


static func by_rarity(r: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all():
		if all()[id].rarity == r:
			out.append(id)
	return out


## The base pool (in every game): commons to legendaries that are not Adds.
static func shop_units() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all():
		if all()[id].rarity <= Rarity.LEGENDARY and not all()[id].choice_only:
			out.append(id)
	return out


## Units offered by the round choices: the faction Adds of that rarity, or the champions.
static func choice_units(rarity: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all():
		var d: Dictionary = all()[id]
		if d.rarity == rarity and (d.choice_only or rarity == Rarity.CHAMPION):
			out.append(id)
	return out


## &"melee" or &"ranged".
static func attack_range(d: Dictionary) -> StringName:
	return d.get("range", &"melee")


static func _add(k: Dictionary, rarity: int) -> void:
	var id := StringName(k.id)
	var ranged: bool = k.get("range", "melee") == "ranged"
	var kws: Array = []
	for w in k.get("keywords", []):
		kws.append(StringName(w))
	var d := {
		"id": id, "name": k.name, "faction": StringName(k.faction), "rarity": rarity, "role": k.get("spot", ""),
		"keywords": kws, "sprite": k.sprite,
		"hp": float(k.hp) * GameConfig.HP_UNIT, "atk": float(k.atk) * GameConfig.ATK_UNIT, "ini": float(k.spd),
		"ap": GameConfig.START_AP, "pp": GameConfig.START_PP,
		"range": &"ranged" if ranged else &"melee", "row": 1 if ranged else 0,
		"passive_text": k.get("kit_text", ""), "text": k.get("kit_text", ""),
		"choice_only": k.get("add", false), "relic": &"",
		"relic_name": k.get("relic_name", ""), "relic_text": k.get("relic_text", ""),
		"kit": k, "extra_actions": 0, "dr": 0.0, "token": &"",
	}
	d["gambits"] = Kits.default_rules(id)
	_cache[id] = d


static func _build() -> void:
	for id in Roster.units():
		var k: Dictionary = Roster.units()[id]
		_add(k, int(k.rarity))
	for id in Roster.tokens():
		_add(Roster.tokens()[id], Rarity.TOKEN)
	for id in Roster.monsters():
		_add(Roster.monsters()[id], Rarity.MONSTER)
