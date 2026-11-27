class_name BattleSim
extends RefCounted
## Deterministic auto-battle over the roster kits (data/roster.json). Input: two team specs + a seed.
## Output: result + an event log the board replays.
##
## Team spec: {"name", "relics": [ids], "units": [{"def", "uid", "level", "items", "cards", "row", "col",
##   "rules", "perm": {key: n}, "scale"}]}
##
## Flow: Warcry phase -> rounds. Each round every living unit takes one turn in Speed order (Swift first).
## A turn: +AP/+PP, start-of-turn keywords (Creep, Regenerate, Grow, triggers, Stall), then ONE action:
## the first rule whose action it can pay for (AP cost, Souls) and whose conditions hold; the free
## basic Attack is the last rule. PP pays reactions (Guard, Strikeback and kit reactions).
## Fights end when a side is wiped; past the fight timer, overtime ramps damage (see GameConfig).
## The vocabulary (selectors, steps, triggers) is listed in modules/battle/CLAUDE.md.

const SINGLE := ["foe", "foe_strongest", "foe_lowest", "foe_next", "foe_back", "foe_facing", "foe_buffed", "foe_random", "foe_nocreep"]
const HARMFUL := [&"chill", &"frozen", &"icehold", &"vuln", &"weaken", &"curse", &"hush"]
const BUFF_STATUSES := [&"barrier", &"haste", &"vanished"]

var rng := RandomNumberGenerator.new()
var units: Array[BattleUnit] = []
var events_log: Array = []
var turn: int = 0            ## round number
var clock: float = 0.0       ## fight time in playback seconds (same table the UI waits on)
var _overtime: int = 0
var _next_uid: int = 1
var _depth: int = 0
var side_flags: Array = [{}, {}]
var souls: Array = [0, 0]
var gold: Array = [0, 0]
var combo: Array = [0, 0]
var stall_mod: Array = [0, 0]
var hatched: Array = [0, 0]
var deaths: int = 0
var creep: Array = [{}, {}]  ## side -> {Vector2i(row, col): n}
var perm_delta: Array = [{}, {}]  ## side -> {spec uid: {key: n}}
var team_names: Array = ["", ""]
var _cur_actor: BattleUnit = null
var _extra: int = 0


func run(team_a: Dictionary, team_b: Dictionary, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	team_names = [team_a.get("name", "A"), team_b.get("name", "B")]
	_build_side(team_a, 0)
	_build_side(team_b, 1)
	log_event({"t": "start", "units": _snapshot()})
	_warcry_phase()
	while turn < GameConfig.MAX_BATTLE_TURNS and _winner() == -2:
		_play_round()
	var result := _result()
	dispose()
	return result


## Breaks the unit <-> sim <-> attribute reference cycles so nothing leaks.
func dispose() -> void:
	for u in units:
		u.sim = null
		u.egg_of = null
		u.summoner = null
		u.dispose()
	units.clear()


# ================================================================ building

func _build_side(team: Dictionary, side: int) -> void:
	var built: Array[BattleUnit] = []
	for spec in team.get("units", []):
		var u := build_unit(spec, side)
		if u:
			built.append(u)
	for rid in team.get("relics", []):
		var r := RelicCatalog.get_def(rid)
		if r.is_empty() or r.effect.get("type", &"") != &"mod":
			continue
		var fac: StringName = r.effect.get("faction", &"")
		for u in built:
			if fac == &"" or u.def.faction == fac:
				_apply_mod(u, r.effect.mod, "relic")
	for u in built:
		u.set_current(&"hp", u.max_hp())
		if u.kw("barrier_start") > 0 and u.st(&"barrier") == 0:
			u.set_status(&"barrier", 1, -1, 1)
		for f in u.flags:
			if String(f).begins_with("side_"):
				side_flags[side][String(f).substr(5)] = u.flags[f]


func build_unit(spec: Dictionary, side: int) -> BattleUnit:
	var def := UnitCatalog.get_def(spec.def)
	if def.is_empty():
		push_warning("Unknown unit %s" % spec.def)
		return null
	var u := BattleUnit.new()
	u.sim = self
	u.uid = _next_uid
	_next_uid += 1
	u.spec_uid = int(spec.get("uid", -1))
	u.def = def
	u.kit = def.kit
	u.side = side
	u.row = int(spec.get("row", def.row))
	u.col = int(spec.get("col", 0))
	u.level = int(spec.get("level", 1))
	u.is_token = def.rarity == UnitCatalog.Rarity.TOKEN
	u.tag_name = def.name
	u.perm = spec.get("perm", {}).duplicate()
	var scale: float = spec.get("scale", 1.0)
	var lv: int = u.level - 1
	u.add(Attribute.make_pool(&"hp", roundf(def.hp * scale) + GameConfig.UPGRADE_HP * lv))
	u.add(Attribute.make(&"attack", roundf(def.atk * scale) + GameConfig.UPGRADE_ATK * lv, Attribute.Merge.ADD_VALUE))
	u.add(Attribute.make(&"initiative", def.ini, Attribute.Merge.ADD_VALUE))
	u.add(Attribute.make_pool(&"ap", GameConfig.AP_MAX))
	u.add(Attribute.make_pool(&"pp", GameConfig.PP_MAX))
	for k in u.kit.get("kw", {}):
		u.add_kw(k, float(u.kit.kw[k]))
	u.trigs = u.kit.get("trig", []).duplicate(true)
	u.flags = u.kit.get("flags", {}).duplicate(true)
	var cards: Array = spec.get("cards", [])
	u.actions = Kits.actions_for(def.id, cards)
	if u.kit.has("relic_mod"):
		_apply_mod(u, u.kit.relic_mod, "relic", false)
	for c in cards:
		_apply_mod(u, c.get("mod", {}), "card", false)
	for iid in spec.get("items", []):
		var item := ItemCatalog.get_def(iid)
		if item.is_empty():
			continue
		for stat in item.stats:
			var attr_id: StringName = {"hp": &"hp", "atk": &"attack", "ini": &"initiative", "ap": &"ap", "pp": &"pp"}.get(stat, &"")
			if attr_id != &"":
				u.get_attr(attr_id).add_flat(StringName("item_" + String(iid)), item.stats[stat])
		_apply_mod(u, item.get("mod", {}), "item")
	var rules: Array = spec.get("rules", [])
	u.gambits = (rules if not rules.is_empty() else Kits.default_rules(def.id, cards)).duplicate(true)
	# rules must point at actions it has; the basic attack stays last
	u.gambits = u.gambits.filter(func(g): return u.actions.has(StringName(g.action)))
	if u.actions.has(&"attack") and not u.gambits.any(func(g): return StringName(g.action) == &"attack"):
		u.gambits.append(Kits.rule_for(u.actions[&"attack"]))
	for g in u.gambits:
		if not g.has("trigger") and u.actions.has(StringName(g.action)) and u.actions[StringName(g.action)].has("react"):
			g["trigger"] = StringName(u.actions[StringName(g.action)].react)
	# permanent stacks earned in earlier fights
	u.get_attr(&"attack").add_flat(&"perm", float(u.perm.get("atk", 0)) * GameConfig.ATK_UNIT)
	if u.kw("perm_deaths_atk") > 0:
		u.get_attr(&"attack").add_flat(&"perm_deaths", float(u.perm.get("deaths", 0)) * GameConfig.ATK_UNIT * u.kw("perm_deaths_atk"))
	if u.kw("perm_deaths_hp") > 0:
		u.get_attr(&"hp").add_flat(&"perm_deaths", float(u.perm.get("deaths", 0)) * GameConfig.GROW_HP_UNIT * u.kw("perm_deaths_hp"))
	u.set_current(&"hp", u.max_hp())
	u.set_current(&"ap", GameConfig.START_AP + u.get_attr(&"ap").flat.values().reduce(func(s, v): return s + v, 0.0))
	u.set_current(&"pp", GameConfig.START_PP + u.get_attr(&"pp").flat.values().reduce(func(s, v): return s + v, 0.0))
	if u.kw("barrier_start") > 0:
		u.set_status(&"barrier", 1, -1, 1)
	units.append(u)
	return u


## Applies an upgrade / item / relic / summon mod: {kw, kw_del, acts, acts_del, trig, trig_del, stats, flags}.
## Actions of cards are already merged by Kits.actions_for (with_acts = false).
func _apply_mod(u: BattleUnit, m: Dictionary, src: String, with_acts := true) -> void:
	if m.is_empty():
		return
	for k in m.get("kw_del", []):
		u.del_kw(k)
	for k in m.get("kw", {}):
		var cur := u.kw_raw(k)
		var want := float(m.kw[k])
		if src == "card" or src == "relic":
			if want > cur:
				u.add_kw(k, want - cur)  # upgrade text "Tough 3" sets the value
		else:
			u.add_kw(k, want)
	for id in m.get("trig_del", []):
		u.trigs = u.trigs.filter(func(t): return t.get("id", "") != id)
	for t in m.get("trig", []):
		if t.has("id"):
			u.trigs = u.trigs.filter(func(o): return o.get("id", "") != t.id)
		u.trigs.append(t.duplicate(true))
	for f in m.get("flags", {}):
		u.flags[f] = m.flags[f]
	var stats: Dictionary = m.get("stats", {})
	if stats.has("hp"):
		u.get_attr(&"hp").add_flat(StringName(src), float(stats.hp) * GameConfig.HP_UNIT)
	if stats.has("atk"):
		u.get_attr(&"attack").add_flat(StringName(src), float(stats.atk) * GameConfig.ATK_UNIT)
	if stats.has("spd"):
		u.get_attr(&"initiative").add_flat(StringName(src), float(stats.spd))
	for pool in ["ap", "pp"]:
		if stats.has(pool):
			u.get_attr(StringName(pool)).add_flat(StringName(src), float(stats[pool]))
			u.gain(StringName(pool), float(stats[pool]))
	if with_acts:
		for id in m.get("acts_del", []):
			u.actions.erase(StringName(id))
		for a in m.get("acts", []):
			var na := Kits._norm(a)
			u.actions[StringName(a.id)] = na
			if not u.gambits.is_empty():
				u.gambits.insert(maxi(0, u.gambits.size() - 1), Kits.rule_for(na))


# ================================================================ queries

func living(side: int = -1) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.alive and (side == -1 or u.side == side):
			out.append(u)
	return out


func allies_of(u: BattleUnit, include_self := true) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for a in living(u.side):
		if include_self or a != u:
			out.append(a)
	return out


func enemies_of(u: BattleUnit) -> Array[BattleUnit]:
	return living(1 - u.side)


func row_units(side: int, row: int) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in living(side):
		if u.row == row:
			out.append(u)
	return out


func unit_at(side: int, row: int, col: int) -> BattleUnit:
	for u in living(side):
		if u.row == row and u.col == col:
			return u
	return null


func cell_free(side: int, row: int, col: int) -> bool:
	return row >= 0 and row <= 1 and col >= 0 and col < GameConfig.BOARD_COLS and unit_at(side, row, col) == null


func free_cells(side: int, front_first := true) -> Array:
	var out: Array = []
	for r in ([0, 1] if front_first else [1, 0]):
		for c in GameConfig.BOARD_COLS:
			if cell_free(side, r, c):
				out.append(Vector2i(r, c))
	return out


## Orthogonal neighbours on its own side.
func adjacent_allies(u: BattleUnit) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for a in living(u.side):
		if a != u and absi(a.row - u.row) + absi(a.col - u.col) == 1:
			out.append(a)
	return out


## Enemies adjacent to u across the board: both in the front row, columns at most 1 apart.
func adjacent_enemies(u: BattleUnit) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	if u.row != 0:
		return out
	for e in enemies_of(u):
		if e.row == 0 and absi(e.col - u.col) <= 1:
			out.append(e)
	return out


## Enemies next to a target on its own side (for bounces, Frenzy).
func neighbours_of(t: BattleUnit) -> Array[BattleUnit]:
	return adjacent_allies(t)


func behind(t: BattleUnit) -> BattleUnit:
	return unit_at(t.side, 1, t.col) if t.row == 0 else null


func in_front(u: BattleUnit) -> BattleUnit:
	return unit_at(u.side, 0, u.col) if u.row == 1 else null


func _winner() -> int:
	var a := living(0).filter(func(u): return not (u.is_token and u.def.id == &"egg")).size()
	var b := living(1).filter(func(u): return not (u.is_token and u.def.id == &"egg")).size()
	if a == 0 and b == 0:
		return -1
	if a == 0:
		return 1
	if b == 0:
		return 0
	return -2


func overtime() -> int:
	return _overtime


func _aura(u: BattleUnit, key: String, adjacent := false) -> float:
	var s := 0.0
	for a in living(u.side):
		if a == u or a.is_token:
			continue
		if adjacent and absi(a.row - u.row) + absi(a.col - u.col) != 1:
			continue
		s += a.kw(key)
	return s


func tok_aura(u: BattleUnit, key: String) -> float:
	if not u.is_token:
		return 0.0
	return _aura(u, "aura_tok_" + key) + _aura(u, "aura_tok_adj_" + key, true)


func solitary(u: BattleUnit) -> bool:
	return adjacent_allies(u).is_empty()


## Attack after position/keyword bonuses (the Attribute plus Zeal, Fearless, Solitary, auras...).
func atk(u: BattleUnit) -> float:
	var a := u.value(&"attack")
	var pts := 0.0
	var front := in_front(u)
	if u.kw("zeal") > 0 and (front != null or u.kw("zeal_any") > 0):
		pts += u.kw("zeal")
	elif u.kw("zeal_any") > 0:
		pts += 1.0
	if u.kw("fearless") > 0 and u.row == 0:
		pts += GameConfig.FEARLESS_ATK
	if u.kw("solitary_atk") > 0 and solitary(u):
		pts += u.kw("solitary_atk")
	if u.kw("atk_per_token") > 0:
		pts += u.kw("atk_per_token") * living(u.side).filter(func(x): return x.is_token).size()
	if u.kw("atk_per_adj_ally") > 0:
		pts += u.kw("atk_per_adj_ally") * adjacent_allies(u).size()
	if u.kw("atk_per_faction_ally") > 0:
		pts += u.kw("atk_per_faction_ally") * allies_of(u, false).filter(func(x): return x.def.faction == u.def.faction).size()
	if u.kw("atk_per_hatch") > 0:
		pts += u.kw("atk_per_hatch") * hatched[u.side]
	if u.kw("pride") > 0:
		pts += allies_of(u, false).filter(func(x): return not x.is_token).size()
	if u.kw("berserk") > 0:
		pts += floorf((1.0 - u.hp_ratio()) * 4.0)
	pts += tok_aura(u, "atk") + _aura(u, "aura_adj_atk", true)
	if u.flags.get("apex", 0) and u.forms_taken > 0:
		pts += u.forms_taken
	var grow_off: float = u.used.get("grow_atk", 0.0) if u.used.get("purged_round", -1) == turn else 0.0
	return maxf(0.0, a + pts * GameConfig.ATK_UNIT - grow_off)


func tough(u: BattleUnit) -> float:
	var t := u.kw("tough") + tok_aura(u, "tough")
	if u.kw("tough_low") > 0 and u.hp_ratio() < 0.5:
		t += u.kw("tough_low")
	return t


func speed(u: BattleUnit) -> float:
	var s := u.value(&"initiative") + u.st(&"haste") - u.st(&"chill") + tok_aura(u, "haste")
	if u.kw("swift") > 0:
		s += GameConfig.SWIFT_INI
	return s


func has_taunt(u: BattleUnit) -> bool:
	return u.kw("taunt") > 0 or (u.kw("taunt_high") > 0 and u.hp_ratio() >= 0.5)


func elusive(u: BattleUnit) -> bool:
	return u.kw("elusive") > 0 or u.st(&"vanished") > 0


func has_dash(u: BattleUnit) -> bool:
	return u.kw("dash") > 0 or tok_aura(u, "dash") > 0


func is_ranged(u: BattleUnit) -> bool:
	return u.def.get("range", &"melee") == &"ranged"


# ================================================================ round flow

func _warcry_phase() -> void:
	for u in _order():
		if u.alive:
			fire(u, "warcry", {})
	for u in _order():
		if not u.alive:
			continue
		_check_stall(u, true)


func _order() -> Array[BattleUnit]:
	var order := living()
	var keys := {}
	for u in order:
		keys[u] = speed(u) + rng.randf() * 0.01
	order.sort_custom(func(x, y): return keys[x] > keys[y])
	return order


func _play_round() -> void:
	turn += 1
	log_event({"t": "turn", "n": turn})
	if clock >= GameConfig.FIGHT_SECONDS:
		_overtime += 1
		log_event({"t": "overtime", "n": _overtime})
	for u in living():
		u.acted_this_turn = false
	for u in _order():
		if not u.alive:
			continue
		_take_turn(u)
		u.acted_this_turn = true
		if _winner() != -2:
			return


func _take_turn(u: BattleUnit) -> void:
	u.turns += 1
	u.moved_turn = false
	u.charge_used = false
	u.turn_used.clear()
	u.gain(&"ap", GameConfig.AP_PER_TURN)
	u.gain(&"pp", GameConfig.PP_PER_TURN)
	# eggs hatch on their first turn
	if u.def.id == &"egg":
		_hatch(u)
		return
	var cell := Vector2i(u.row, u.col)
	var cr: int = creep[u.side].get(cell, 0)
	if cr > 0:
		raw_damage(null, u, cr * GameConfig.CREEP_UNIT, "Creep")
		if side_flags[1 - u.side].get("creep_curse_on", false) and u.alive:
			apply_status(null, u, &"curse", 1)
		if not u.alive:
			return
	var regen := u.kw("regen") + tok_aura(u, "regen")
	if regen > 0 and u.hp() < u.max_hp():
		heal(u, u, regen * GameConfig.REGEN_UNIT)
	if u.kw("grow") > 0:
		_grow(u, u.kw("grow"))
	if u.kw("solitary_barrier") > 0 and solitary(u) and u.st(&"barrier") == 0:
		u.set_status(&"barrier", 1, -1, 1)
		log_event({"t": "status", "u": u.uid, "status": "Barrier"})
	_check_stall(u, false)
	fire(u, "turn", {})
	if not u.alive:
		return
	if u.st(&"frozen") > 0:
		log_event({"t": "status", "u": u.uid, "status": "Frozen: skips"})
		_end_turn(u)
		return
	_extra = 0
	var actions_left := 1
	var guard := 0
	while actions_left > 0 and u.alive and _winner() == -2 and guard < 8:
		guard += 1
		var r := _do_ap_gambit(u)
		if r == 0:
			break
		if r == 1:
			actions_left -= 1
		actions_left += _extra
		_extra = 0
		actions_left = mini(actions_left, 3)
	if u.alive:
		_end_turn(u)


func _end_turn(u: BattleUnit) -> void:
	fire(u, "turn_end", {})
	if not u.alive:
		return
	if not u.moved_turn and u.flags.get("still_atk", 0):
		var n := 1.0
		if u.flags.get("still_zeal", 0) and in_front(u) != null:
			n = 2.0
		u.buff(&"attack", n * GameConfig.ATK_UNIT)
		u.used["still_stacks"] = u.used.get("still_stacks", 0.0) + n
	if u.kw("vanish") > 0 and u.st(&"vanished") == 0:
		u.set_status(&"vanished", 1, -1, 1)
	var curse := u.st(&"curse")
	if curse > 0:
		raw_damage(null, u, maxf(1.0, roundf(u.max_hp() * GameConfig.CURSE_PCT * curse)), "Curse")
		if not u.alive:
			return
	var eph := u.kw("ephemeral")
	if eph > 0 and not (u.is_token and tok_aura(u, "noeph") > 0):
		if u.turns >= int(eph):
			raw_damage(null, u, u.hp() + 1.0, "Ephemeral")
			return
	u.tick()


func _grow(u: BattleUnit, n: float) -> void:
	var a := n * GameConfig.ATK_UNIT
	var h := n * GameConfig.GROW_HP_UNIT
	u.get_attr(&"attack").add_flat(&"grow", a)
	u.get_attr(&"hp").add_flat(&"grow", h)
	u.used["grow_atk"] = u.used.get("grow_atk", 0.0) + a
	log_event({"t": "buff", "u": u.uid, "text": "Grow +%d/+%d" % [a, h], "hp": u.hp(), "max": u.max_hp()})


# ---------------------------------------------------------------- stall / rush

func eff_stall(u: BattleUnit, n: int) -> int:
	var s: int = n + u.stall_mod + stall_mod[u.side]
	if side_flags[u.side].has("stall_cap"):
		s = mini(s, int(side_flags[u.side].stall_cap))
	return maxi(0, s)


func stall_live(u: BattleUnit, n: int) -> bool:
	if side_flags[u.side].get("stall_twice", 0):
		return true
	return u.turns - 1 >= eff_stall(u, n) or (u.turns == 0 and eff_stall(u, n) == 0)


func rush_live(u: BattleUnit, n: int) -> bool:
	return u.turns <= n


## One-shot "stall" triggers fire once their count is reached (and again for Scioness Sajj).
func _check_stall(u: BattleUnit, at_start: bool) -> void:
	for t in u.trigs.duplicate():
		if t.on != "stall":
			continue
		var key := "stall_%d" % u.trigs.find(t)
		var n := int(t.get("stall", 0))
		var done: int = u.used.get(key, 0)
		var twice: bool = side_flags[u.side].get("stall_twice", 0)
		if at_start:
			if (eff_stall(u, n) == 0 and done == 0) or (twice and done == 0):
				u.used[key] = done + 1
				_run_trigger(u, t, {}, "Stall")
			continue
		var reached := u.turns - 1 >= eff_stall(u, n)
		var third: int = int(side_flags[u.side].get("stall_third", 0))
		if reached and (done == 0 or (twice and done == 1)):
			u.used[key] = done + 1
			_run_trigger(u, t, {}, "Stall")
		elif third > 0 and u.turns == third and done < 3:
			u.used[key] = done + 1
			_run_trigger(u, t, {}, "Stall")


func _gate(u: BattleUnit, d: Dictionary, ctx: Dictionary) -> bool:
	if d.has("stall") and d.get("on", "") != "stall" and not stall_live(u, int(d.stall)):
		return false
	if d.has("rush") and not rush_live(u, int(d.rush)):
		return false
	if d.has("every") and (u.turns <= 0 or u.turns % int(d.every) != 0):
		return false
	if d.has("if") and not _cond(u, d.get("if"), ctx):
		return false
	return true


# ---------------------------------------------------------------- triggers

func fire(u: BattleUnit, ev: String, ctx: Dictionary) -> void:
	if not u.alive and ev != "deathwish":
		return
	if u.hushed():
		return
	if _depth > 6:
		return
	for t in u.trigs.duplicate():
		if t.on != ev:
			continue
		if not _gate(u, t, ctx):
			continue
		if t.has("cond") and not _cond(u, t.cond, ctx):
			continue
		var idx := u.trigs.find(t)
		var key := "trig_%d" % idx
		if t.get("once", false) and u.used.get(key, 0) >= 1:
			continue
		if t.has("uses") and u.used.get(key, 0) >= int(t.uses):
			continue
		if t.has("per_turn") and u.turn_used.get(key, 0) >= int(t.per_turn):
			continue
		if t.has("per_round"):
			var rk := "%s_r%d" % [key, turn]
			if u.used.get(rk, 0) >= int(t.per_round):
				continue
			u.used[rk] = u.used.get(rk, 0) + 1
		u.used[key] = u.used.get(key, 0) + 1
		u.turn_used[key] = u.turn_used.get(key, 0) + 1
		_run_trigger(u, t, ctx, _trigger_label(ev))


func _trigger_label(ev: String) -> String:
	return {"warcry": "Warcry", "deathwish": "Deathwish", "deathwatch": "Deathwatch", "bitemark": "Bitemark",
		"kill": "Kill", "turn": "", "turn_end": "", "hit_taken": "", "guard": "", "charged": "Charge"}.get(ev, "")


func _run_trigger(u: BattleUnit, t: Dictionary, ctx: Dictionary, label: String) -> void:
	_depth += 1
	if label != "":
		log_event({"t": "act", "u": u.uid, "text": label, "reaction": not (label in ["Warcry", "Deathwish", "Stall"])})
	var c := ctx.duplicate()
	_steps(u, t.fx, [], c)
	_depth -= 1


# ================================================================ actions

## Returns 0 = nothing done, 1 = an action that uses the turn, 2 = a free action (turn goes on).
func _do_ap_gambit(u: BattleUnit) -> int:
	for g in u.gambits:
		if StringName(g.get("kind", &"ap")) != &"ap":
			continue
		var id := StringName(g.action)
		if not u.actions.has(id):
			continue
		var a: Dictionary = u.actions[id]
		var free: bool = a.get("free", false)
		if free and u.turn_used.get("free_" + String(id), 0) >= int(a.get("per_turn", 1)):
			continue
		if not free and a.has("per_turn") and u.turn_used.get("act_" + String(id), 0) >= int(a.per_turn):
			continue
		var cost := _cost(u, a)
		if cost > u.ap():
			continue
		if int(a.get("souls", 0)) > souls[u.side]:
			continue
		if not _uses_ok(u, a):
			continue
		if not _rule_ok(u, g, {}):
			continue
		if a.has("cond") and not _cond(u, a.cond, {}):
			continue
		if _run_action(u, a, {}):
			u.spend(&"ap", cost)
			souls[u.side] -= int(a.get("souls", 0))
			_mark_used(u, a)
			if free:
				u.turn_used["free_" + String(id)] = u.turn_used.get("free_" + String(id), 0) + 1
				return 2
			u.turn_used["act_" + String(id)] = u.turn_used.get("act_" + String(id), 0) + 1
			return 1
	return 0


func _cost(u: BattleUnit, a: Dictionary) -> int:
	var c := int(a.get("cost", 1))
	for ci in a.get("cost_if", []):
		if ci.has("stall") and stall_live(u, int(ci.stall)):
			c = int(ci.cost)
		elif ci.has("rush") and rush_live(u, int(ci.rush)):
			c = int(ci.cost)
		elif ci.has("souls") and souls[u.side] >= int(ci.souls):
			c = int(ci.cost)
	if u.flags.has("cost_mod_stall") and stall_live(u, int(u.flags.cost_mod_stall)) and a.id != "attack":
		c -= 1
	return maxi(0, c)


func _uses_ok(u: BattleUnit, a: Dictionary) -> bool:
	var key := "act_" + String(a.id)
	if a.get("once", false) and u.used.get(key, 0) >= 1:
		return false
	if a.has("uses") and u.used.get(key, 0) >= int(a.uses):
		return false
	return true


func _mark_used(u: BattleUnit, a: Dictionary) -> void:
	var key := "act_" + String(a.id)
	u.used[key] = u.used.get(key, 0) + 1


func _run_action(u: BattleUnit, a: Dictionary, ctx: Dictionary) -> bool:
	var targets := _select(u, a.get("tgt", "foe"), ctx, [])
	if targets.is_empty() and a.get("tgt", "") != "self":
		return false
	if targets.is_empty():
		targets = [u]
	var reaction: bool = a.get("kind", &"ap") == &"pp"
	_cur_actor = u
	log_event({"t": "act", "u": u.uid, "text": a.name, "reaction": reaction})
	var c := ctx.duplicate()
	c["single"] = String(a.get("tgt", "foe")) in SINGLE
	_steps(u, a.fx, targets, c)
	if not reaction:
		_combo_after(u)
		if u.flags.get("aftershock", 0) and String(a.id) == "quake":
			if u.used.get("aftershock_pending", false):
				u.used["aftershock_pending"] = false
			else:
				u.used["aftershock_pending"] = true
	return true


func _combo_after(u: BattleUnit) -> void:
	if u.def.faction == &"songhai":
		combo[u.side] += 1
	elif not side_flags[u.side].get("combo_keep", 0):
		combo[u.side] = 0


## Rule conditions (the player's chips): cond/arg and cond2/arg2 must both hold.
func _rule_ok(u: BattleUnit, g: Dictionary, ctx: Dictionary) -> bool:
	return _check(u, g.get("cond", &""), g.get("arg", 0.0), ctx) and _check(u, g.get("cond2", &""), g.get("arg2", 0.0), ctx)


func _check(u: BattleUnit, c, arg, ctx: Dictionary) -> bool:
	match StringName(c):
		&"":
			return true
		&"self_below":
			return u.hp_ratio() < float(arg)
		&"self_above":
			return u.hp_ratio() >= float(arg)
		&"enemy_below":
			return enemies_of(u).any(func(e): return e.hp_ratio() < float(arg))
		&"front_row":
			return u.row == 0
		&"back_row":
			return u.row == 1
		&"has_ap_left":
			return u.ap() >= int(arg)
		&"ally_below":
			return living(u.side).any(func(a): return a.hp_ratio() < float(arg))
		&"target_below":
			return ctx.has("target") and ctx.target.alive and ctx.target.hp_ratio() < float(arg)
		&"enemy_has":
			return enemies_of(u).any(func(e): return e.st(StringName(arg)) > 0)
	return true


## Kit conditions (actions, triggers, step "if").
func _cond(u: BattleUnit, c: String, ctx: Dictionary) -> bool:
	match c:
		"ally_hurt":
			return living(u.side).any(func(a): return a.hp_ratio() < GameConfig.HURT_RATIO and a.def.id != &"egg")
		"ally_needy":
			return not _select(u, "ally_needy", ctx, []).is_empty()
		"foe_buffed":
			return enemies_of(u).any(func(e): return _has_buffs(e))
		"empty_cell":
			return not free_cells(u.side).is_empty()
		"has_token":
			return living(u.side).any(func(a): return a.is_token and a.def.id != &"egg")
		"repos":
			return _repos_pair(u).size() == 2
		"stall_pending":
			return u.trigs.any(func(t): return t.on == "stall" and not u.used.has("stall_%d" % u.trigs.find(t)))
		"creep_front":
			return enemies_of(u).any(func(e): return e.row == 1) and _foe_creep_front(u)
		"adj_victim":
			return not _select(u, "adj_victim", ctx, []).is_empty()
		"adj_token":
			return not _select(u, "adj_token", ctx, []).is_empty()
		"dead_ally":
			return not _select(u, "dead_ally", ctx, []).is_empty() and not free_cells(u.side).is_empty()
		"egg":
			return living(u.side).any(func(a): return a.def.id == &"egg")
		"not_form":
			return u.form.is_empty()
		"avatar_bear":
			return u.form.get("id", "") != "g_bear" and u.hp_ratio() < 0.5
		"avatar_wyrm":
			return u.form.get("id", "") != "g_wyrm" and row_units(1 - u.side, 0).size() >= 2
		"avatar_wolf":
			return u.form.get("id", "") != "g_wolf" and u.form.get("id", "") == ""
		"ally_nobarrier":
			return living(u.side).any(func(a): return a.st(&"barrier") == 0 and a.def.id != &"egg")
		"self_below":
			return u.hp_ratio() < 0.5
		"not_moved":
			return not u.moved_turn
		"target_cursed":
			return ctx.has("target") and ctx.target != null and ctx.target.st(&"curse") > 0
		"iceheld_any":
			return ctx.get("iceheld", 0) > 0
		"solitary":
			return solitary(u)
	return true


func _has_buffs(e: BattleUnit) -> bool:
	for s in BUFF_STATUSES:
		if e.st(s) > 0:
			return true
	for id in [&"attack", &"initiative"]:
		for src in e.get_attr(id).flat:
			if String(src).begins_with("buff_") or String(src) == "grow":
				return true
	return false


func _foe_creep_front(u: BattleUnit) -> bool:
	var s := 1 - u.side
	for c in GameConfig.BOARD_COLS:
		if creep[s].get(Vector2i(0, c), 0) > 0 and cell_free(s, 0, c):
			return true
	return false


# ================================================================ selectors

func _select(u: BattleUnit, sel, ctx: Dictionary, base: Array) -> Array:
	var s := String(sel)
	var out: Array = []
	var foes := enemies_of(u)
	var t: BattleUnit = ctx.get("target") if ctx.get("target") is BattleUnit else (base[0] if not base.is_empty() and base[0] is BattleUnit else null)
	match s:
		"self":
			out = [u]
		"target":
			out = [t]
		"source":
			out = [ctx.get("source")]
		"dead":
			return [ctx.get("dead")] if ctx.get("dead") is BattleUnit else []
		"dead_ally":
			for d in units:
				if d.side == u.side and not d.alive and not d.is_token and not d.used.get("unlifed", false) and d.egg_of == null and not _egg_pending(d):
					return [d]
			return []
		"dead_allies":
			return units.filter(func(d): return d.side == u.side and not d.alive and not d.is_token and not _egg_pending(d))
		"foe":
			out = [pick_target(u, reachable(u))]
		"foe_strongest":
			out = [_best(targetable(u), func(e): return atk(e))]
		"foe_lowest":
			out = [_best(targetable(u), func(e): return -e.hp_ratio())]
		"foe_next":
			var cands := targetable(u).filter(func(e): return not e.acted_this_turn)
			out = [_best(cands if not cands.is_empty() else targetable(u), func(e): return speed(e))]
		"foe_back":
			var back := targetable(u).filter(func(e): return e.row == 1)
			out = [pick_target(u, back if not back.is_empty() else targetable(u))]
		"foe_facing":
			var f := unit_at(1 - u.side, 0, u.col)
			out = [f if f != null else pick_target(u, reachable(u))]
		"foe_random":
			out = [foes[rng.randi() % foes.size()]] if not foes.is_empty() else []
		"foe_buffed":
			out = [_best(foes.filter(func(e): return _has_buffs(e)), func(e): return atk(e))]
		"foe_buffed2":
			var bs := foes.filter(func(e): return _has_buffs(e))
			bs.sort_custom(func(x, y): return atk(x) > atk(y))
			out = bs.slice(0, 2)
		"foe_nocreep":
			var nc := foes.filter(func(e): return creep[e.side].get(Vector2i(e.row, e.col), 0) == 0)
			out = [pick_target(u, nc if not nc.is_empty() else foes)]
		"foe_front_row":
			out = row_units(1 - u.side, 0) if not row_units(1 - u.side, 0).is_empty() else row_units(1 - u.side, 1)
		"foes":
			out = foes
		"foe_row":
			if t != null:
				out = row_units(t.side, t.row)
		"foe_adj":
			if t != null:
				out = neighbours_of(t)
		"foe_adj1":
			if t != null:
				var n := neighbours_of(t)
				out = [n[rng.randi() % n.size()]] if not n.is_empty() else []
		"behind":
			if t != null:
				out = [behind(t)]
		"foe_adjacent":
			out = adjacent_enemies(u)
		"allies":
			out = living(u.side).filter(func(a): return a.def.id != &"egg")
		"allies_other":
			out = allies_of(u, false).filter(func(a): return a.def.id != &"egg")
		"ally_lowest":
			out = [_best(living(u.side).filter(func(a): return a.def.id != &"egg" and a.hp() < a.max_hp()), func(a): return -a.hp_ratio())]
		"ally_low_half":
			out = [_best(allies_of(u, false).filter(func(a): return a.hp_ratio() < 0.5 and not a.is_token and _movable(a)), func(a): return -a.hp_ratio())]
		"ally_hurt_front":
			out = [_best(allies_of(u, false).filter(func(a): return a.row == 0 and a.hp_ratio() < 0.6 and not a.is_token and _movable(a)), func(a): return -a.hp_ratio())] if u.row == 1 else []
		"ally_needy":
			out = [_best(living(u.side).filter(func(a): return a.hp_ratio() < GameConfig.HURT_RATIO or _harmful(a) > 0), func(a): return _harmful(a) * 2.0 - a.hp_ratio())]
		"ally_front":
			out = [in_front(u)]
		"ally_front_or_adj":
			var f2 := in_front(u)
			out = [f2 if f2 != null else _best(adjacent_allies(u), func(a): return atk(a))]
		"ally_near":
			var f3 := in_front(u)
			out = [f3 if f3 != null else _best(adjacent_allies(u).filter(func(a): return not a.is_token), func(a): return a.max_hp())]
		"ally_near2":
			var near := adjacent_allies(u).filter(func(a): return not a.is_token)
			near.sort_custom(func(x, y): return x.max_hp() > y.max_hp())
			out = near.slice(0, 2)
		"ally_strongest":
			out = [_best(allies_of(u, false).filter(func(a): return a.def.id != &"egg"), func(a): return atk(a))]
		"ally_highest_hp":
			out = [_best(allies_of(u, false), func(a): return a.hp())]
		"ally_nobarrier":
			out = [_best(living(u.side).filter(func(a): return a.st(&"barrier") == 0 and a.def.id != &"egg"), func(a): return (1.0 if a.row == 0 else 0.0) - a.hp_ratio())]
		"ally_nobarrier2":
			var nb := living(u.side).filter(func(a): return a.st(&"barrier") == 0 and a.def.id != &"egg")
			nb.sort_custom(func(x, y): return x.row < y.row)
			out = nb.slice(0, 2)
		"adj_allies":
			out = adjacent_allies(u)
		"row_allies":
			out = row_units(u.side, u.row)
		"row_allies_other":
			out = row_units(u.side, u.row).filter(func(a): return a != u)
		"front_allies":
			out = row_units(u.side, 0)
		"lane_allies":
			out = living(u.side).filter(func(a): return a.col == u.col)
		"songhai_allies":
			out = living(u.side).filter(func(a): return a.def.faction == &"songhai")
		"viking_allies":
			out = allies_of(u, false).filter(func(a): return a.def.get("role", "") == "Viking")
		"spirit_allies":
			out = allies_of(u, false).filter(func(a): return a.def.get("role", "") == "Spirit")
		"tokens":
			out = living(u.side).filter(func(a): return a.is_token)
		"token_any":
			out = [_best(living(u.side).filter(func(a): return a.is_token and a != u and a.def.id != &"egg"), func(a): return a.hp())]
		"token_lowest":
			out = [_best(living(u.side).filter(func(a): return a.is_token and a.def.id != &"egg"), func(a): return -a.hp())]
		"adj_token":
			out = [_best(adjacent_allies(u).filter(func(a): return a.is_token and a.def.id != &"egg"), func(a): return -a.hp())]
		"adj_victim":
			var vs := adjacent_allies(u).filter(func(a): return a.def.id != &"egg" and (a.is_token or a.hp_ratio() < GameConfig.SACRIFICE_BELOW))
			out = [_best(vs, func(a): return (10.0 if a.is_token else 0.0) - a.hp())]
		"egg":
			out = [_best(living(u.side).filter(func(a): return a.def.id == &"egg"), func(a): return 0.0)]
		_:
			push_warning("Unknown selector " + s)
	return out.filter(func(x): return x != null and x is BattleUnit and x.alive)


func _egg_pending(d: BattleUnit) -> bool:
	for e in living(d.side):
		if e.egg_of == d:
			return true
	return false


func _harmful(a: BattleUnit) -> int:
	var n := 0
	for s in HARMFUL:
		n += a.st(s)
	return n


func _best(arr: Array, score: Callable):
	var best = null
	var bs := -INF
	for x in arr:
		var v: float = score.call(x)
		if best == null or v > bs:
			best = x
			bs = v
	return best


## Enemies u may target with a single-target attack: Elusive needs Ranged or Elusive; Taunt forces itself.
func targetable(u: BattleUnit) -> Array:
	var foes := enemies_of(u).filter(func(e): return e.def.id != &"egg" or true)
	var can_elusive := is_ranged(u) or elusive(u)
	var ok := foes.filter(func(e): return can_elusive or not elusive(e))
	return ok


## Melee reaches the front row (back row once it is empty); Ranged reaches everyone. Taunt pulls.
func reachable(u: BattleUnit) -> Array:
	var cands := targetable(u)
	if not is_ranged(u):
		var front := cands.filter(func(e): return e.row == 0)
		var any_front := enemies_of(u).any(func(e): return e.row == 0)
		if not front.is_empty():
			cands = front
		elif any_front:
			cands = []  # only Elusive units up front: melee can't reach past them
	var taunts := cands.filter(func(e): return has_taunt(e))
	if not taunts.is_empty():
		return taunts
	return cands


func pick_target(u: BattleUnit, cands: Array) -> BattleUnit:
	if cands.is_empty():
		return null
	var vul := cands.filter(func(c): return c.st(&"vuln") > 0)
	if not vul.is_empty():
		cands = vul
	if u.flags.get("berserk_target", 0):
		return _best(cands, func(c): return -c.hp())
	return _best(cands, func(c): return -((0.0 if c.col == u.col else 1.0) + c.hp_ratio()))


# ================================================================ steps

func _steps(u: BattleUnit, steps: Array, targets: Array, ctx: Dictionary) -> void:
	for st in steps:
		if not u.alive and ctx.get("dead") != u and not st.get("posthumous", true):
			return
		if not _gate(u, st, ctx):
			continue
		var on: Array = _select(u, st.on, ctx, targets) if st.has("on") else targets
		if not st.has("on") and targets.is_empty() and st.do in ["heal", "status", "barrier", "buff", "kw", "cleanse", "gain"]:
			on = [u]
		_step(u, st, on, ctx, not st.has("on") and ctx.get("single", false))


func _step(u: BattleUnit, st: Dictionary, on: Array, ctx: Dictionary, single: bool) -> void:
	match String(st.do):
		"hit":
			var p := float(st.get("p", 1.0))
			var hits := on.duplicate()
			for t in hits:
				if not (t is BattleUnit) or not t.alive:
					continue
				var tgt: BattleUnit = t
				if single:
					tgt = _targeted(u, t)
					if tgt == null:
						continue
				var group: Array = [tgt]
				if (single or st.get("on", "") == "") and (u.kw("blast") > 0 or _tok_blast(u)):
					group = row_units(tgt.side, tgt.row)
				elif u.kw("frenzy") > 0 and not is_ranged(u):
					group = [tgt] + neighbours_of(tgt)
				for g in group:
					if g.alive:
						var dealt := deal_hit(u, g, p, st)
						ctx["dealt"] = ctx.get("dealt", 0.0) + dealt
						ctx["target"] = g
						if st.get("combo_each", false):
							combo[u.side] += 1
						if not g.alive and st.has("on_kill"):
							_steps(u, st.on_kill, [u], ctx)
		"dmg":
			for t in on:
				raw_damage(u, t, float(st.n) * GameConfig.DMG_UNIT, "")
		"heal":
			for t in on:
				var amt: float
				match String(st.get("amount", "")):
					"dealt": amt = ctx.get("dealt", 0.0)
					"dealt_half": amt = ctx.get("dealt", 0.0) * 0.5
					"victim": amt = ctx.get("victim_hp", 0.0)
					_: amt = float(st.n) * GameConfig.HEAL_UNIT if st.has("n") else GameConfig.HEAL_BASE + atk(u)
				heal(u, t, amt)
		"status":
			var dur := int(st.get("dur", -1))
			var ice := 0
			for t in on:
				if apply_status(u, t, StringName(st.id), int(st.get("n", 1)), dur) and st.id == "icehold":
					ice += 1
			ctx["iceheld"] = ice
		"barrier":
			for t in on:
				if t.st(&"barrier") == 0:
					t.set_status(&"barrier", 1, -1, 1)
					log_event({"t": "status", "u": t.uid, "status": "Barrier"})
		"cleanse":
			for t in on:
				var removed := false
				for s in HARMFUL:
					if t.st(s) > 0:
						t.clear_status(s)
						removed = true
				if removed:
					log_event({"t": "status", "u": t.uid, "status": "Cleansed"})
		"purge":
			for t in on:
				_purge(t)
		"buff":
			var stat: StringName = {"atk": &"attack", "hp": &"hp", "spd": &"initiative"}.get(String(st.stat), &"attack")
			var n := float(st.n)
			for t in on:
				var amount := n
				if st.get("from_victim", false):
					amount = ctx.get("victim_hp", 0.0)
				elif stat == &"attack":
					amount = n * GameConfig.ATK_UNIT
				elif stat == &"hp":
					amount = n * (GameConfig.GROW_HP_UNIT if st.get("grow", false) else GameConfig.HP_UNIT)
				if amount == 0.0:
					continue
				t.buff(stat, amount, int(st.get("dur", -1)))
				var label := "+%d %s" % [amount, {&"attack": "Attack", &"hp": "HP", &"initiative": "Speed"}[stat]]
				log_event({"t": "buff", "u": t.uid, "text": label, "hp": t.hp(), "max": t.max_hp()})
		"kw":
			for t in on:
				var before: float = t.kw_raw(st.k)
				t.add_kw(st.k, float(st.get("n", 1)), int(st.get("dur", -1)), float(st.get("cap", 0)))
				if t.kw_raw(st.k) > before:
					log_event({"t": "buff", "u": t.uid, "text": "%s %s" % [Keywords.kw_name(StringName(st.k)) if Keywords.get_kw(StringName(st.k)).size() > 0 else String(st.k).capitalize(), _num(t.kw_raw(st.k))]})
		"kw_del":
			for t in on:
				t.del_kw(st.k)
		"gain":
			for t in on:
				var res := StringName(st.res)
				var a: Attribute = t.get_attr(res)
				a.current = minf(a.value() + 3.0, a.current + float(st.n))
				log_event({"t": "buff", "u": t.uid, "text": "+%d %s" % [st.n, String(res).to_upper()]})
		"numb", "drain_pp":
			for t in on:
				_numb(t, int(st.get("n", 1)), String(st.do) == "drain_pp")
		"summon":
			for i in int(st.get("n", 1)):
				var tok := summon(u, String(st.tok), st.get("mod", {}), st, ctx)
				if tok == null:
					break
		"push":
			for t in on:
				push(u, t, int(st.get("n", 1)))
		"pull":
			for t in on:
				pull(u, t)
		"swap":
			for t in on:
				swap(u, t, u)
		"blink":
			for t in on:
				blink(t)
		"reposition":
			var pair := _repos_pair(u)
			if pair.size() == 2:
				swap(pair[0], pair[1], u)
				if st.has("haste"):
					for x in pair:
						apply_status(u, x, &"haste", int(st.haste))
		"redirect":
			if ctx.has("attack"):
				ctx.attack.target = u
		"redirect_to_target":
			if ctx.has("attack") and not on.is_empty():
				ctx.attack.target = on[0]
		"souls":
			souls[u.side] += int(st.n)
			log_event({"t": "buff", "u": u.uid, "text": "+%d Soul%s" % [st.n, "s" if int(st.n) > 1 else ""]})
		"gold":
			earn(u, int(st.n))
		"perm":
			add_perm(u, String(st.key), int(st.n))
		"transform":
			transform(u, st.form)
		"revive":
			for d in on:
				var r := revive(d, float(st.get("pct", 0.5)))
				if r and st.has("then"):
					_steps(u, st.then, [d], ctx)
		"sacrifice":
			for v in on:
				if not v.alive:
					continue
				ctx["victim_hp"] = v.hp()
				log_event({"t": "act", "u": u.uid, "text": "Sacrifice", "reaction": true})
				fire(v, "sacrificed", {"source": u})
				raw_damage(u, v, v.hp() + 1.0, "Sacrificed")
				if st.has("then"):
					_steps(u, st.then, [u], ctx)
		"creep":
			_creep(u, int(st.n), String(st.get("cells", "target")), on)
		"extra_action":
			_extra += 1
		"stall_mod":
			for t in on:
				t.stall_mod += int(st.n)
			log_event({"t": "buff", "u": u.uid, "text": "Stall %d" % int(st.n)})
		"special":
			_special(u, String(st.name), st, ctx, on)
		_:
			push_warning("Unknown step " + String(st.do))


func _num(v: float) -> String:
	return str(int(v)) if v > 1.0 else ""


func _tok_blast(u: BattleUnit) -> bool:
	if not u.is_token:
		return false
	if tok_aura(u, "blast") > 0:
		return true
	if tok_aura(u, "blast_once") > 0 and not u.used.get("blast_once", false):
		u.used["blast_once"] = true
		return true
	return false


# ================================================================ damage

## Targeting reactions on a single-target attack (Guard, Mirage, Gale Step...). Returns who gets hit.
func _targeted(src: BattleUnit, t: BattleUnit) -> BattleUnit:
	var atk_ctx := {"source": src, "target": t}
	var ctx := {"attack": atk_ctx, "source": src, "target": t}
	react("self_targeted", [t], ctx)
	if atk_ctx.target == t:
		_guard(src, t, atk_ctx)
	if atk_ctx.target == t:
		react("ally_targeted_any", allies_of(t, false), ctx)
	return atk_ctx.target if atk_ctx.target is BattleUnit and atk_ctx.target.alive else null


func _guard(src: BattleUnit, t: BattleUnit, atk_ctx: Dictionary) -> void:
	for g in allies_of(t, false):
		if g.hushed() or g.def.id == &"egg":
			continue
		var adjacent := absi(g.row - t.row) + absi(g.col - t.col) == 1
		var all_once: bool = g.flags.get("guard_all_once", 0) and not g.used.get("guard_all", false)
		if g.kw("guard") <= 0 and not all_once:
			continue
		if not adjacent and not all_once:
			continue
		var free: bool = g.flags.get("guard_free", 0) or (g.flags.get("guard_free_turn", 0) and g.used.get("guard_free_round", -1) != turn) or all_once
		if not free and g.pp() < 1:
			continue
		if not adjacent:
			g.used["guard_all"] = true
		elif not free:
			g.spend(&"pp", 1)
		if g.flags.get("guard_free_turn", 0):
			g.used["guard_free_round"] = turn
		log_event({"t": "act", "u": g.uid, "text": "Guard", "reaction": true})
		atk_ctx.target = g
		if g.flags.has("guard_tough"):
			g.add_kw("tough", float(g.flags.guard_tough), 1)
		fire(g, "guard", {"target": t, "source": src})
		return


func deal_hit(src: BattleUnit, dst: BattleUnit, p: float, st: Dictionary = {}) -> float:
	if not dst.alive:
		return 0.0
	if dst.st(&"vanished") > 0:
		dst.clear_status(&"vanished")
	if dst.st(&"barrier") > 0:
		dst.clear_status(&"barrier")
		log_event({"t": "blocked", "u": dst.uid, "text": "Barrier"})
		return 0.0
	var dmg := atk(src) * p
	var pts := 0.0
	if src.kw("charge") > 0 and src.moved_turn and not src.charge_used:
		src.charge_used = true
		pts += src.kw("charge")
		fire(src, "charged", {"target": dst})
	var bs := src.kw("backstab") + float(st.get("backstab", 0))
	if bs > 0 and not dst.acted_this_turn:
		pts += bs
	if src.kw("combo") > 0:
		pts += combo[src.side] * src.kw("combo")
	if dst.st(&"frozen") > 0 and src.kw("frozen_bonus") > 0:
		pts += src.kw("frozen_bonus")
	if src.flags.has("execute") and dst.hp_ratio() < 0.3:
		pts += float(src.flags.execute)
	dmg += pts * GameConfig.ATK_UNIT
	if dst.st(&"vuln") > 0:
		dmg += GameConfig.VULN_BONUS
		dst.set_status(&"vuln", -1)
	dmg += dst.max_hp() * float(src.flags.get("pct_hp", 0.0))
	var weaken := src.st(&"weaken") + (1 if _on_weakening_creep(src) else 0)
	dmg -= weaken * GameConfig.WEAKEN_UNIT
	var ot := overtime()
	if ot > 0:
		dmg *= 1.0 + GameConfig.OVERTIME_DMG_STEP * ot
	else:
		dmg -= tough(dst) * GameConfig.TOUGH_UNIT
	dmg = maxf(GameConfig.MIN_DAMAGE, roundf(dmg))
	var before := dst.hp()
	_apply_hp_loss(src, dst, dmg, "")
	var spill := dmg - before
	if src.kw("lifesteal") > 0 and src.alive:
		heal(src, src, minf(dmg, before))
	# on-hit statuses
	for k in ["chill", "icehold", "curse", "numb", "hush", "vuln", "weaken"]:
		var n := int(src.kw("hit_" + k))
		if n > 0 and dst.alive:
			if k == "numb":
				_numb(dst, n, false)
			else:
				apply_status(src, dst, StringName(k), n, 1 if k in ["icehold", "hush"] else -1)
	if src.kw("push_first") > 0 and not src.used.get("push_first", false) and dst.alive:
		src.used["push_first"] = true
		push(src, dst, 1)
	if src.form.get("bitemark_grow", 0) and src.alive:
		_grow(src, float(src.form.bitemark_grow))
	if dst.alive:
		if dst.hp_ratio() < 0.5 and not dst.below_half_fired:
			dst.below_half_fired = true
			fire(dst, "below_half", {"source": src})
		fire(dst, "hit_taken", {"source": src, "target": dst})
		react("hit_taken", [dst], {"source": src, "target": dst})
		var melee := not is_ranged(src)
		if melee:
			react("melee_hit", [dst], {"source": src, "target": dst})
			_strikeback(dst, src)
		var back := behind(dst)
		if dst.row == 0:
			for b in living(dst.side):
				if b.row == 1 and b.col == dst.col:
					react("front_ally_hit", [b], {"source": src, "target": dst})
	else:
		if spill > 0 and src.kw("overwhelm") > 0:
			var b2 := unit_at(dst.side, 1, dst.col) if dst.row == 0 else null
			if b2 != null:
				raw_damage(src, b2, spill, "Overwhelm")
	if src.alive:
		fire(src, "bitemark", {"target": dst, "dealt": dmg})
	return dmg


func _strikeback(dst: BattleUnit, src: BattleUnit) -> void:
	if not dst.alive or not src.alive or dst.kw("strikeback") <= 0 or dst.pp() < 1 or _depth > 3:
		return
	dst.spend(&"pp", 1)
	_depth += 1
	log_event({"t": "act", "u": dst.uid, "text": "Strikeback", "reaction": true})
	deal_hit(dst, src, 1.0)
	if dst.flags.get("strikeback_push", 0) and src.alive:
		push(dst, src, 1)
	_depth -= 1


func _on_weakening_creep(u: BattleUnit) -> bool:
	if creep[u.side].get(Vector2i(u.row, u.col), 0) <= 0:
		return false
	return living(1 - u.side).any(func(e): return e.kw("creep_weaken") > 0)


## Damage that skips Barrier/Tough (Creep, Curse, Deathwatch drain, sacrifice, overwhelm spill).
func raw_damage(src, dst: BattleUnit, amount: float, label: String) -> void:
	if not dst.alive or amount <= 0.0:
		return
	_apply_hp_loss(src, dst, roundf(amount), label)


func _apply_hp_loss(src, dst: BattleUnit, dmg: float, label := "") -> void:
	var new_hp := dst.hp() - dmg
	dst.set_current(&"hp", maxf(0.0, new_hp))
	log_event({"t": "hit", "src": src.uid if src is BattleUnit else -1, "u": dst.uid, "amount": dmg, "hp": dst.hp(), "max": dst.max_hp(), "text": label})
	if dst.hp() <= 0.0:
		_on_death(dst, src)


func _on_death(dead: BattleUnit, killer) -> void:
	if not dead.alive:
		return
	# Undying (Reassemble, Phylactery, Phoenix Feather): returns once.
	if dead.kw_raw("undying") > 0 and not dead.used.get("undying", false):
		dead.used["undying"] = true
		var pct: float = float(dead.flags.get("undying_pct", 0.0))
		dead.set_current(&"hp", maxf(1.0, roundf(dead.max_hp() * pct)))
		log_event({"t": "buff", "u": dead.uid, "text": "Returns!", "hp": dead.hp(), "max": dead.max_hp()})
		return
	dead.alive = false
	log_event({"t": "death", "u": dead.uid})
	if not dead.is_token:
		deaths += 1
	if not dead.hushed():
		fire(dead, "deathwish", {"dead": dead, "source": killer})
	if dead.kw_raw("rebirth") > dead.used.get("rebirths", 0) and not dead.is_token:
		dead.used["rebirths"] = dead.used.get("rebirths", 0) + 1
		var egg := summon_at(dead, "egg", Vector2i(dead.row, dead.col))
		if egg:
			egg.egg_of = dead
	if killer is BattleUnit and killer.alive and killer.side != dead.side:
		var b: float = killer.kw("bounty")
		if b > 0 and not dead.is_token:
			var extra: int = int(killer.perm.get("bounties", 0)) if killer.kw("bounty_grows") > 0 else 0
			earn(killer, int(b) + extra)
			add_perm(killer, "bounties", 1)
		fire(killer, "kill", {"target": dead, "dead": dead})
	for u in living():
		if u == dead:
			continue
		fire(u, "deathwatch", {"dead": dead, "source": killer})
		if u.side == dead.side:
			if dead.is_token:
				fire(u, "token_died", {"dead": dead})
			elif dead.def.id != &"egg":
				fire(u, "ally_died", {"dead": dead})


func heal(src: BattleUnit, dst: BattleUnit, amount: float) -> void:
	if not dst.alive or amount <= 0.0:
		return
	if overtime() > 0:
		amount *= GameConfig.OVERTIME_HEAL_MULT
	amount = roundf(amount)
	var before := dst.hp()
	var room := dst.max_hp() - before
	dst.set_current(&"hp", before + amount)
	var got := dst.hp() - before
	if got > 0.0:
		log_event({"t": "heal", "src": src.uid, "u": dst.uid, "amount": got, "hp": dst.hp(), "max": dst.max_hp()})
	# Radiance: overheal becomes Tough for the fight (capped)
	var rad := src.kw("radiance")
	if rad > 0 and amount > room:
		var t := floorf((amount - room) / GameConfig.OVERHEAL_PER_TOUGH)
		var have: float = dst.used.get("radiance", 0.0)
		t = minf(t, rad - have)
		if t >= 1.0:
			dst.used["radiance"] = have + t
			dst.add_kw("tough", t)
			log_event({"t": "buff", "u": dst.uid, "text": "Tough +%d" % t})
	if src.flags.has("heal_tough"):
		dst.add_kw("tough", float(src.flags.heal_tough), 1)
	if src.flags.get("heal_cleanse", 0):
		for s in HARMFUL:
			dst.clear_status(s)


## Returns true when the status landed.
func apply_status(src, dst: BattleUnit, id: StringName, n: int, dur: int = -1) -> bool:
	if not dst.alive or n == 0:
		return false
	if id in HARMFUL:
		var ctx := {"target": dst, "status": id, "cancel": false, "source": src}
		react("status_landing", allies_of(dst, true), ctx)
		if ctx.cancel:
			return false
	match id:
		&"frozen", &"icehold":
			if id == &"frozen" and dst.flags.get("immune_frozen", 0):
				return false
			var times: int = dst.cc_count.get(id, 0)
			var d := maxi(1, dur) + (int(side_flags[1 - dst.side].get("freeze_extra", 0)) if id == &"frozen" else 0)
			d = d >> times
			dst.cc_count[id] = times + 1
			if d <= 0:
				log_event({"t": "status", "u": dst.uid, "status": "Resists %s" % String(id).capitalize()})
				return false
			dst.set_status(id, 1, d + (1 if dst == _cur_actor else 0), 1)
		&"chill":
			dst.set_status(&"chill", n)
			if dst.st(&"chill") >= GameConfig.FREEZE_AT:
				dst.clear_status(&"chill")
				log_event({"t": "status", "u": dst.uid, "status": "Chill x%d" % GameConfig.FREEZE_AT})
				return apply_status(src, dst, &"frozen", 1, 1)
		&"hush":
			dst.set_status(&"hush", 1, maxi(1, dur), 1)
		&"barrier":
			dst.set_status(&"barrier", 1, -1, 1)
		_:
			dst.set_status(id, n, dur)
	log_event({"t": "status", "u": dst.uid, "status": "%s%s" % [_status_name(id), (" x%d" % dst.st(id)) if dst.st(id) > 1 else ""]})
	return true


func _status_name(id: StringName) -> String:
	return {&"vuln": "Vulnerable", &"frozen": "Frozen", &"vanished": "Vanished"}.get(id, String(id).capitalize())


func _numb(t: BattleUnit, n: int, pp_only: bool) -> void:
	var left := n
	if not pp_only:
		var take := mini(left, t.ap())
		t.spend(&"ap", take)
		left -= take
	if left > 0:
		t.spend(&"pp", left)
	log_event({"t": "status", "u": t.uid, "status": "Numb" if not pp_only else "Drained"})


func _purge(t: BattleUnit) -> void:
	for id in [&"attack", &"initiative"]:
		var a := t.get_attr(id)
		for src in a.flat.keys():
			if String(src).begins_with("buff_"):
				a.remove_source(src)
	for a in t.attributes.values():
		if &"keyword" in a.tags:
			for src in a.flat.keys():
				if String(src).begins_with("buff_"):
					a.remove_source(src)
	for s in BUFF_STATUSES:
		t.clear_status(s)
	t.used["purged_round"] = turn
	log_event({"t": "status", "u": t.uid, "status": "Purged"})


# ================================================================ reactions (PP)

func react(trigger: String, candidates: Array, ctx: Dictionary) -> void:
	if _depth > 4:
		return
	_depth += 1
	for u in candidates:
		if not (u is BattleUnit) or not u.alive or u.hushed():
			continue
		for g in u.gambits:
			if StringName(g.get("kind", &"ap")) != &"pp" or String(g.get("trigger", "")) != trigger:
				continue
			var id := StringName(g.action)
			if not u.actions.has(id):
				continue
			var a: Dictionary = u.actions[id]
			var cost := _cost(u, a)
			var free: bool = cost == 0 and (not a.has("per_turn") or u.used.get("free_r_%s_%d" % [id, turn], 0) < int(a.per_turn))
			if not free and cost > u.pp():
				continue
			if cost == 0 and not free:
				continue
			if not _uses_ok(u, a) or not _rule_ok(u, g, ctx):
				continue
			if trigger == "ally_targeted_any" and (ctx.target == u or ctx.target.row == u.row and ctx.target.col == u.col):
				continue
			var c := ctx.duplicate()
			if _run_action(u, a, c):
				if c.has("cancel"):
					ctx.cancel = c.cancel
				if a.fx.any(func(s): return s.do == "cleanse"):
					ctx["cancel"] = true
				u.spend(&"pp", cost)
				if cost == 0:
					u.used["free_r_%s_%d" % [id, turn]] = u.used.get("free_r_%s_%d" % [id, turn], 0) + 1
				_mark_used(u, a)
				break
	_depth -= 1


# ================================================================ movement

func _movable(u: BattleUnit) -> bool:
	return u.kw("anchor") <= 0 and u.st(&"icehold") <= 0


func move(u: BattleUnit, row: int, col: int) -> void:
	if u.row == row and u.col == col:
		return
	var old := Vector2i(u.row, u.col)
	u.row = row
	u.col = col
	u.moved_turn = true
	if u.flags.get("still_atk", 0) and not u.flags.get("still_keep", 0) and u.used.get("still_stacks", 0.0) > 0:
		u.used["still_stacks"] = 0.0
		var a := u.get_attr(&"attack")
		# moving resets "each turn it doesn't move" stacks
		for src in a.flat.keys():
			if String(src).begins_with("buff_"):
				a.remove_source(src)
	log_event({"t": "move", "u": u.uid, "row": row, "col": col})


func push(src: BattleUnit, t: BattleUnit, n: int) -> void:
	if not t.alive:
		return
	if t.row == 0 and _movable(t) and cell_free(t.side, 1, t.col):
		move(t, 1, t.col)
		log_event({"t": "status", "u": t.uid, "status": "Pushed"})
		fire(t, "moved_by_enemy", {"source": src})
	else:
		raw_damage(src, t, n * GameConfig.PUSH_UNIT, "Push")


func pull(src: BattleUnit, t: BattleUnit) -> void:
	if t.alive and t.row == 1 and _movable(t) and cell_free(t.side, 0, t.col):
		move(t, 0, t.col)
		log_event({"t": "status", "u": t.uid, "status": "Pulled"})
		fire(t, "moved_by_enemy", {"source": src})


func swap(a: BattleUnit, b: BattleUnit, by: BattleUnit) -> void:
	if a == b or not a.alive or not b.alive or a.side != b.side:
		return
	if (a != by and not _movable(a)) or (b != by and not _movable(b)) or a.st(&"icehold") > 0 or b.st(&"icehold") > 0:
		return
	var ar := a.row
	var ac := a.col
	move(a, b.row, b.col)
	move(b, ar, ac)


func blink(u: BattleUnit) -> void:
	if not u.alive or u.st(&"icehold") > 0:
		return
	var cells := free_cells(u.side, not is_ranged(u))
	if cells.is_empty():
		return
	var c: Vector2i = cells[rng.randi() % cells.size()]
	if not is_ranged(u):
		var front := cells.filter(func(x): return x.x == 0)
		if not front.is_empty():
			c = front[rng.randi() % front.size()]
	move(u, c.x, c.y)


## Dash: moves one cell for free before attacking (towards the front, else sideways).
func dash(u: BattleUnit) -> void:
	if u.moved_turn or not _movable(u):
		return
	var opts: Array = []
	if u.row == 1 and cell_free(u.side, 0, u.col):
		opts.append(Vector2i(0, u.col))
	for dc in [-1, 1]:
		if cell_free(u.side, u.row, u.col + dc):
			opts.append(Vector2i(u.row, u.col + dc))
	if opts.is_empty():
		return
	var c: Vector2i = opts[0]
	move(u, c.x, c.y)


## The ally pair a reposition swaps: the most hurt front-row ally and the healthiest back-row ally.
func _repos_pair(u: BattleUnit) -> Array:
	var hurt = _best(living(u.side).filter(func(a): return a.row == 0 and a.hp_ratio() < 0.6 and _movable(a) and not a.is_token), func(a): return -a.hp_ratio())
	var fresh = _best(living(u.side).filter(func(a): return a.row == 1 and a.hp_ratio() > 0.75 and _movable(a)), func(a): return a.hp())
	if hurt == null or fresh == null:
		return []
	return [hurt, fresh]


# ================================================================ summons, forms, rebirth

func summon(owner: BattleUnit, tok: String, mod: Dictionary = {}, st: Dictionary = {}, ctx: Dictionary = {}) -> BattleUnit:
	var cells := free_cells(owner.side, true)
	if cells.is_empty():
		return null
	return summon_at(owner, tok, cells[0], mod, st, ctx)


func summon_at(owner: BattleUnit, tok: String, cell: Vector2i, mod: Dictionary = {}, st: Dictionary = {}, ctx: Dictionary = {}) -> BattleUnit:
	if not cell_free(owner.side, cell.x, cell.y):
		return null
	var t := build_unit({"def": tok, "row": cell.x, "col": cell.y}, owner.side)
	if t == null:
		return null
	t.summoner = owner
	t.turns = 0
	if st.get("copy_self", false):
		t.get_attr(&"hp").base = owner.max_hp() * 0.5
		t.get_attr(&"attack").base = owner.value(&"attack")
		t.set_current(&"hp", t.max_hp())
	if st.get("from_dead", false) and ctx.get("target") is BattleUnit:
		var d: BattleUnit = ctx.target
		d.used["unlifed"] = true
		t.get_attr(&"attack").base = d.value(&"attack")
		t.tag_name = d.def.name
	if tok == "egg":
		var hp_stat := float(side_flags[owner.side].get("egg_hp", 1))
		t.get_attr(&"hp").base = hp_stat * GameConfig.HP_UNIT
		t.set_current(&"hp", t.max_hp())
		if side_flags[owner.side].get("egg_taunt", 0):
			t.add_kw("taunt", 1)
		t.hatch_tok = String(st.get("hatch", ""))
	if tok == "raptor" and side_flags[owner.side].get("raptor_grow", 0):
		t.add_kw("grow", 1)
	_apply_mod(t, mod, "summon")
	if tok == "obelysk" and mod.get("flags", {}).has("obelysk_n"):
		for tr in t.trigs:
			for s in tr.fx:
				if s.do == "summon":
					s["n"] = int(mod.flags.obelysk_n)
	log_event({"t": "summon", "unit": _unit_info(t)})
	fire(t, "warcry", {})
	return t


func _hatch(egg: BattleUnit) -> void:
	var side := egg.side
	var cell := Vector2i(egg.row, egg.col)
	egg.alive = false
	log_event({"t": "death", "u": egg.uid})
	if egg.egg_of != null:
		var d: BattleUnit = egg.egg_of
		egg.egg_of = null
		var keep: bool = side_flags[side].get("rebirth_keep", 0) or d.flags.get("rebirth_keep_self", 0)
		d.row = cell.x
		d.col = cell.y
		revive(d, GameConfig.REBIRTH_PCT, keep)
		if d.alive:
			hatched[side] += 1
			_hatch_bonus(d)
	else:
		var t := summon_at(egg, egg.hatch_tok if egg.hatch_tok != "" else "raptor", cell)
		if t:
			hatched[side] += 1
			_hatch_bonus(t)


func _hatch_bonus(u: BattleUnit) -> void:
	var a := float(side_flags[u.side].get("hatch_atk", 0))
	if a > 0:
		u.buff(&"attack", a * GameConfig.ATK_UNIT)
	if side_flags[u.side].get("hatch_grow", 0):
		u.add_kw("grow", 1)
	log_event({"t": "buff", "u": u.uid, "text": "Hatched", "hp": u.hp(), "max": u.max_hp()})


func revive(d: BattleUnit, pct: float, keep_grow := true) -> bool:
	if d.alive:
		return false
	if not cell_free(d.side, d.row, d.col):
		var cells := free_cells(d.side, not is_ranged(d))
		if cells.is_empty():
			return false
		d.row = cells[0].x
		d.col = cells[0].y
	if not keep_grow:
		d.get_attr(&"attack").remove_source(&"grow")
		d.get_attr(&"hp").remove_source(&"grow")
		d.used["grow_atk"] = 0.0
	for s in d.statuses():
		d.clear_status(s)
	d.alive = true
	d.set_current(&"hp", maxf(1.0, roundf(d.max_hp() * pct)))
	log_event({"t": "summon", "unit": _unit_info(d)})
	log_event({"t": "buff", "u": d.uid, "text": "Returns", "hp": d.hp(), "max": d.max_hp()})
	return true


## Transform: a form adds stats and keywords and swaps the sprite. "stack" forms keep earlier bonuses.
func transform(u: BattleUnit, f: Dictionary) -> void:
	if not u.alive:
		return
	if not f.get("stack", false) and not u.form.is_empty():
		_remove_form(u)
	elif f.get("stack", false) and not u.form.is_empty():
		for k in u.form.get("kw", {}):
			if not f.kw.has(k):
				u.del_kw(k)
	u.form = f
	u.forms_taken += 1
	var src := StringName("form_%d" % u.forms_taken)
	u.get_attr(&"hp").add_flat(src, float(f.get("hp", 0)) * GameConfig.HP_UNIT)
	u.get_attr(&"attack").add_flat(src, float(f.get("atk", 0)) * GameConfig.ATK_UNIT)
	u.get_attr(&"initiative").add_flat(src, float(f.get("spd", 0)))
	for k in f.get("kw", {}):
		u.add_kw(k, float(f.kw[k]))
		if k == "barrier_start":
			u.set_status(&"barrier", 1, -1, 1)
	var spr := Roster.form_sprite(String(f.get("sprite", "")))
	log_event({"t": "transform", "u": u.uid, "sprite": spr, "name": f.get("name", "Form"), "hp": u.hp(), "max": u.max_hp()})


func _remove_form(u: BattleUnit) -> void:
	for k in u.form.get("kw", {}):
		u.del_kw(k)
	var src := StringName("form_%d" % u.forms_taken)
	u.get_attr(&"hp").remove_source(src)
	u.get_attr(&"attack").remove_source(src)
	u.get_attr(&"initiative").remove_source(src)
	u.form = {}


func _creep(u: BattleUnit, n: int, cells: String, on: Array) -> void:
	var s := 1 - u.side
	var list: Array = []
	match cells:
		"target":
			for t in on:
				list.append(Vector2i(t.row, t.col))
		"two":
			for t in on:
				list.append(Vector2i(t.row, t.col))
			var others := enemies_of(u).filter(func(e): return creep[s].get(Vector2i(e.row, e.col), 0) == 0 and not (e in on))
			if not others.is_empty():
				var e: BattleUnit = others[rng.randi() % others.size()]
				list.append(Vector2i(e.row, e.col))
		"front":
			for c in GameConfig.BOARD_COLS:
				list.append(Vector2i(0, c))
		"all":
			for r in 2:
				for c in GameConfig.BOARD_COLS:
					list.append(Vector2i(r, c))
	if u.kw("creep_curse") > 0:
		side_flags[u.side]["creep_curse_on"] = true
	for c in list:
		creep[s][c] = maxi(creep[s].get(c, 0), n)
		var occ := unit_at(s, c.x, c.y)
		if occ:
			log_event({"t": "status", "u": occ.uid, "status": "Creep %d" % creep[s][c]})


# ================================================================ gold and permanent stacks

func earn(u: BattleUnit, n: int) -> void:
	if n == 0:
		return
	gold[u.side] += n
	add_perm(u, "earned", maxi(0, n))
	log_event({"t": "buff", "u": u.uid, "text": "%+d gold" % n})


func add_perm(u: BattleUnit, key: String, n: int) -> void:
	if u.spec_uid < 0:
		return
	var d: Dictionary = perm_delta[u.side].get(u.spec_uid, {})
	d[key] = d.get(key, 0) + n
	perm_delta[u.side][u.spec_uid] = d
	u.perm[key] = int(u.perm.get(key, 0)) + n


# ================================================================ unit specials

func _special(u: BattleUnit, name: String, st: Dictionary, ctx: Dictionary, on: Array) -> void:
	match name:
		"tokens_hit":  # Oserix Command: every allied token hits the target
			var t = on[0] if not on.is_empty() else pick_target(u, reachable(u))
			for tok in living(u.side).filter(func(a): return a.is_token and a.def.id != &"egg" and not a.def.kit.get("no_attack", false)):
				if t != null and t.alive:
					deal_hit(tok, t, 1.0)
		"phalanx":  # Grand Strategos: +1 Attack per adjacent ally
			for a in allies_of(u):
				var n := adjacent_allies(a).size()
				if n > 0:
					a.buff(&"attack", n * GameConfig.ATK_UNIT)
					log_event({"t": "buff", "u": a.uid, "text": "Phalanx +%d" % (n * GameConfig.ATK_UNIT)})
		"guild_master":  # Songhai allies gain Haste 1 per 10 gold earned this game
			var h := int(u.perm.get("earned", 0)) / 10
			if h > 0:
				for a in living(u.side).filter(func(x): return x.def.faction == &"songhai"):
					apply_status(u, a, &"haste", h)
		"jugg_shades":  # a Shade per 2 Attack (stat points)
			var n := int(atk(u) / (2.0 * GameConfig.ATK_UNIT))
			for i in n:
				if summon(u, "shade") == null:
					break
		"throne_of_souls":
			souls[u.side] += int(u.perm.get("deaths", 0)) / 3
		"hatch":  # Warm: an egg hatches now
			for e in on:
				if e.alive and e.def.id == &"egg":
					_hatch(e)
		"freeze_if_chilled":
			var t2: BattleUnit = ctx.get("target")
			if t2 != null and t2.alive and t2.st(&"chill") > 0:
				t2.clear_status(&"chill")
				apply_status(u, t2, &"frozen", 1, 1)
		"raptyr":  # alternates Bear (+3 HP) and Panther (+3 Attack, Dash) each turn
			var bear := u.turns % 2 == 1
			var keep: bool = u.flags.get("raptyr_keep", 0)
			var kwb := {"regen": float(u.flags.raptyr_regen)} if u.flags.has("raptyr_regen") else {}
			var kwp := {"dash": 1.0}
			if u.flags.has("raptyr_charge"):
				kwp["charge"] = float(u.flags.raptyr_charge)
			if bear:
				transform(u, {"id": "r_bear", "hp": 3, "atk": 3 if keep and u.forms_taken > 0 else 0, "kw": kwb, "sprite": "form-bear", "name": "Bear form"})
			else:
				transform(u, {"id": "r_panther", "atk": 3, "hp": 3 if keep else 0, "kw": kwp, "sprite": "form-panther", "name": "Panther form"})
		"starhorn":  # bigger form each turn: +2/+2 stacking, Dash, then Frenzy, Overwhelm, Grow 2
			var stage := u.forms_taken + (1 if u.flags.get("starhorn_idol", 0) and u.forms_taken == 0 else 0)
			var gains := [{"dash": 1}, {"frenzy": 1}, {"overwhelm": 1}, {"grow": 2}]
			if u.flags.get("starhorn_idol", 0) and u.forms_taken == 0:
				transform(u, {"id": "s0", "hp": 2, "atk": 2, "kw": gains[0], "sprite": "form-wolf", "name": "First form", "stack": true})
			var big: bool = stage >= 4
			var step := 3 if (big and u.flags.get("starhorn_idol", 0)) else 2
			if stage < 4 or u.flags.get("starhorn_idol", 0):
				var sprites := ["form-wolf", "form-panther", "form-wyrm", "form-ages"]
				var kwn: Dictionary = gains[mini(stage, 3)] if stage < 4 else {}
				transform(u, {"id": "s%d" % (stage + 1), "hp": step, "atk": step, "kw": kwn, "sprite": sprites[mini(stage, 3)], "name": "Form %d" % (stage + 1), "stack": true})
		_:
			push_warning("Unknown special " + name)


# ================================================================ output

func log_event(ev: Dictionary) -> void:
	events_log.append(ev)
	clock += GameConfig.EVENT_SECONDS.get(ev.t, 0.0)


func _unit_info(u: BattleUnit) -> Dictionary:
	return {"uid": u.uid, "side": u.side, "row": u.row, "col": u.col, "name": u.tag_name if u.is_token else u.display_name(),
		"def": u.def.id, "sprite": u.def.sprite, "hp": u.hp(), "max": u.max_hp(), "level": u.level}


func _snapshot() -> Array:
	var out: Array = []
	for u in units:
		out.append(_unit_info(u))
	return out


func _result() -> Dictionary:
	var w := _winner()
	if w == -2:
		var r := [0.0, 0.0]
		for s in 2:
			var cur := 0.0
			var mx := 0.0
			for u in units:
				if u.side == s and not u.is_token:
					mx += u.max_hp()
					cur += u.hp() if u.alive else 0.0
			r[s] = cur / mx if mx > 0.0 else 0.0
		w = 0 if r[0] > r[1] + 0.001 else (1 if r[1] > r[0] + 0.001 else -1)
		log_event({"t": "timeout", "ratios": r})
	# Raid: survivors earn gold
	for u in living():
		if u.is_token:
			continue
		var raid := u.kw_raw("raid")
		var g := 0
		if raid > 0:
			g += int(raid) + (int(u.perm.get("raids", 0)) if u.kw_raw("raid_grows") > 0 else 0)
		if u.kw_raw("raid_vikings") > 0:
			g += living(u.side).filter(func(a): return a.def.get("role", "") == "Viking").size()
		if g > 0:
			earn(u, g)
			add_perm(u, "raids", 1)
			if u.kw_raw("raid_atk") > 0:
				add_perm(u, "atk", 1)
	# deaths seen (Underlord Xorxuul)
	for u in units:
		if u.kw_raw("perm_deaths_atk") > 0 or u.kw_raw("perm_deaths_hp") > 0:
			add_perm(u, "deaths", deaths)
	var survivors := 0
	if w >= 0:
		for u in living(w):
			if not u.is_token:
				survivors += 1
	log_event({"t": "end", "winner": w, "survivors": survivors})
	var kills := [0, 0]
	for u in units:
		if not u.alive and not u.is_token:
			kills[1 - u.side] += 1
	return {"winner": w, "survivors": survivors, "turns": turn, "log": events_log, "kills": kills,
		"standing": [_standing(0), _standing(1)], "gold": gold.duplicate(), "perm": perm_delta.duplicate(true)}


func _standing(side: int) -> int:
	var n := 0
	for u in living(side):
		if not u.is_token:
			n += 1
	return n
