class_name PlayerState
extends AttributeHolder
## One of the 8 players. Player HP, Rank, XP, Gold and streak are Attributes,
## so relics and future effects can modify them like unit stats.
##
## Roster entries are plain Dictionaries (a "unit instance"):
## {"uid": int, "def": StringName, "level": int, "items": [ids], "cards": [card dicts],
##  "row": int, "col": int (-1 = not assigned), "paid": int, "rules": [gambit dicts] (empty = unit default)}

var id: int = 0
var display: String = ""
var is_bot: bool = true
var alive: bool = true
var placement: int = 0
var roster: Array = []
var item_bench: Array = []
var relics: Array = []
var shop_offers: Array = []
var shop_locked: bool = false
var rerolls_this_round: int = 0
var lean: Dictionary = {}   ## archetype -> starting lean value
var pity: Dictionary = {}   ## archetype -> pity value
var catchup_tier: int = 0
var catchup_score: float = 0.0
var pending_picks: Array = []
var gold_style: StringName = &""  ## interest | bounty | streak (see GameConfig.GOLD_STYLES)
var history: Array = []     ## per round: {"round", "opponent", "result", "damage"}
var _next_uid: int = 1


func _init(p_id: int = 0, p_name: String = "", bot: bool = true) -> void:
	id = p_id
	display = p_name
	is_bot = bot
	tag_name = p_name
	add(Attribute.make_pool(&"player_hp", GameConfig.START_HP))
	add(Attribute.make(&"rank", 1.0, Attribute.Merge.ADD_VALUE))
	add(Attribute.make(&"xp", 0.0, Attribute.Merge.ADD_VALUE))
	add(Attribute.make(&"gold", 0.0, Attribute.Merge.ADD_VALUE))
	add(Attribute.make(&"streak", 0.0, Attribute.Merge.REPLACE))


# ---- simple accessors over the attributes
func hp() -> int: return int(current(&"player_hp"))
func max_hp() -> int: return int(value(&"player_hp"))
func rank() -> int: return int(get_attr(&"rank").base)
func xp() -> int: return int(get_attr(&"xp").base)
func gold() -> int: return int(get_attr(&"gold").base)
func streak() -> int: return int(get_attr(&"streak").base)

func set_gold(v: int) -> void: get_attr(&"gold").base = v
func add_gold(v: int) -> void: get_attr(&"gold").base += v
func set_streak(v: int) -> void: get_attr(&"streak").base = v

func lose_hp(n: int) -> void:
	set_current(&"player_hp", hp() - n)


func new_uid() -> int:
	_next_uid += 1
	return _next_uid


func find_unit(uid: int) -> Dictionary:
	for u in roster:
		if u.uid == uid:
			return u
	return {}


func find_by_def(def_id: StringName) -> Dictionary:
	for u in roster:
		if u.def == def_id:
			return u
	return {}


func assigned() -> Array:
	return roster.filter(func(u): return u.col >= 0)


func unit_at(row: int, col: int) -> Dictionary:
	for u in roster:
		if u.row == row and u.col == col:
			return u
	return {}


## Keywords of a unit instance (def + upgrade cards + keyword items).
static func unit_keywords(u: Dictionary) -> Array:
	var def := UnitCatalog.get_def(u.def)
	var out: Array = def.keywords.duplicate()
	for c in u.cards:
		for k in c.get("keywords", []):
			if not (StringName(k) in out):
				out.append(StringName(k))
	for i in u.items:
		for k in ItemCatalog.get_def(i).get("keywords", []):
			if not (k in out):
				out.append(k)
	return out


static func item_capacity(u: Dictionary) -> int:
	return GameConfig.ITEM_SLOTS


## Battle-ready team spec for BattleSim.
func team_spec() -> Dictionary:
	var units: Array = []
	for u in assigned():
		var def := UnitCatalog.get_def(u.def)
		var kws := PlayerState.unit_keywords(u)
		var items: Array = []
		for i in u.items:
			if ItemCatalog.meets_req(ItemCatalog.get_def(i), def, kws, u.row):
				items.append(i)
		units.append({"def": u.def, "uid": u.uid, "perm": u.get("perm", {}), "level": u.level, "items": items, "cards": u.cards, "row": u.row, "col": u.col, "rules": u.get("rules", [])})
	return {"name": display, "units": units, "relics": relics.duplicate()}


func snapshot() -> Dictionary:
	return {"id": id, "name": display, "hp": hp(), "rank": rank(), "gold": gold(), "alive": alive,
		"placement": placement, "streak": streak(), "units": roster.size()}
