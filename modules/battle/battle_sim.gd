class_name BattleSim
extends RefCounted
## Deterministic auto-battle. Input: two team specs (plain Dictionaries), a seed.
## Output: result Dictionary + an event log the viewer replays.
##
## Team spec: {"name": String, "relics": [relic ids],
##   "units": [{"def": id, "level": 1, "items": [ids], "cards": [card dicts], "row": 0|1, "col": 0..2}]}
##
## Rules (plan doc): units act in Initiative order each turn; an action costs 1 AP;
## PP is spent by reactions. When nobody has AP left, everyone refills AP and PP
## (a new cycle). Battle ends when a side is wiped, else after MAX_BATTLE_CYCLES
## the side with the higher remaining HP% wins.

const E = preload("res://core/events/game_events.gd")

var rng := RandomNumberGenerator.new()
var units: Array[BattleUnit] = []
var events_log: Array = []
var turn: int = 0
var _next_uid: int = 1
var _react_depth: int = 0
var side_flags: Array = [{}, {}]
var team_names: Array = ["", ""]


func run(team_a: Dictionary, team_b: Dictionary, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	team_names = [team_a.get("name", "A"), team_b.get("name", "B")]
	_build_side(team_a, 0)
	_build_side(team_b, 1)
	log_event({"t": "start", "units": _snapshot()})
	for u in units.duplicate():
		if u.has_flag(&"zealot"):
			var pp: int = u.pp()
			u.get_attr(&"attack").add_flat(&"zealot", GameConfig.ZEALOT_ATK * pp)
			u.spend(&"pp", pp)
	for u in units.duplicate():
		u.emit(E.BATTLE_START, {"sim": self})
	var cycle := 1
	while cycle <= GameConfig.MAX_BATTLE_CYCLES and turn < GameConfig.MAX_BATTLE_TURNS:
		if _winner() != -2:
			break
		if not _anyone_can_act():
			cycle += 1
			if cycle > GameConfig.MAX_BATTLE_CYCLES:
				break
			for u in living():
				u.refill(&"ap")
				u.refill(&"pp")
				if u.has_flag(&"zealot"):
					u.spend(&"pp", u.pp())
			log_event({"t": "cycle", "n": cycle})
			continue
		_play_turn()
	var result := _result()
	dispose()
	return result


## Breaks the unit <-> sim <-> attribute reference cycles so nothing leaks.
func dispose() -> void:
	for u in units:
		u.sim = null
		u.dispose()
	units.clear()


# ---------------------------------------------------------------- building

func _build_side(team: Dictionary, side: int) -> void:
	var built: Array[BattleUnit] = []
	for spec in team.get("units", []):
		var u := build_unit(spec, side)
		if u:
			built.append(u)
	var counts := {}
	for u in built:
		counts[u.def.faction] = counts.get(u.def.faction, 0) + 1
	for rid in team.get("relics", []):
		var r := RelicCatalog.get_def(rid)
		if r.is_empty():
			continue
		var needs: Dictionary = r.needs
		if not needs.is_empty() and counts.get(needs.faction, 0) < needs.count:
			continue
		var eff: Dictionary = r.effect
		match eff.type:
			&"team_flat":
				for u in built:
					u.get_attr(eff.stat).add_flat(rid, eff.value)
					u.refill(eff.stat)
			&"flag":
				side_flags[side][eff.flag] = eff.get("value", 1.0)
				for u in built:
					u.add(Effects.flag(eff.flag, eff.get("value", 1.0)))


func build_unit(spec: Dictionary, side: int) -> BattleUnit:
	var def := UnitCatalog.get_def(spec.def)
	if def.is_empty():
		push_warning("Unknown unit %s" % spec.def)
		return null
	var u := BattleUnit.new()
	u.sim = self
	u.uid = _next_uid
	_next_uid += 1
	u.def = def
	u.side = side
	u.row = spec.get("row", def.row)
	u.col = spec.get("col", 0)
	u.level = spec.get("level", 1)
	u.is_token = def.rarity == UnitCatalog.Rarity.TOKEN
	u.tag_name = def.name
	var scale: float = spec.get("scale", 1.0)
	var lv: int = u.level - 1
	u.add(Attribute.make_pool(&"hp", GameConfig.round_hp(def.hp * scale) + GameConfig.UPGRADE_HP * lv))
	u.add(Attribute.make(&"attack", roundf(def.atk * scale) + GameConfig.UPGRADE_ATK * lv, Attribute.Merge.ADD_VALUE))
	u.add(Attribute.make(&"initiative", def.ini, Attribute.Merge.ADD_VALUE))
	u.add(Attribute.make(&"damage_reduction", def.get("dr", 0.0), Attribute.Merge.ADD_VALUE))
	u.add(Attribute.make_pool(&"ap", def.ap))
	u.add(Attribute.make_pool(&"pp", def.pp))
	u.gambits = (spec.rules if spec.has("rules") and not spec.rules.is_empty() else def.gambits).duplicate(true)
	if def.extra_actions > 0:
		u.add(Effects.flag(&"extra_actions", def.extra_actions))
	for kw in def.keywords:
		u.add(Effects.keyword(kw))
	var p := Effects.passive(def.passive)
	if p:
		u.add(p)
	for card in spec.get("cards", []):
		_apply_mod(u, card, &"card")
	for iid in spec.get("items", []):
		var item := ItemCatalog.get_def(iid)
		if item.is_empty():
			continue
		for stat in item.stats:
			var attr_id: StringName = {"hp": &"hp", "atk": &"attack", "dr": &"damage_reduction", "ini": &"initiative", "ap": &"ap", "pp": &"pp"}[stat]
			u.get_attr(attr_id).add_flat(iid, item.stats[stat])
		var eff: Dictionary = item.effect
		if eff.is_empty():
			continue
		match eff.type:
			&"gambit":
				_add_gambit(u, eff.gambit)
			&"keyword":
				u.add(Effects.keyword(eff.keyword, {"token": eff.get("token", &"")}))
				if UnitCatalog.KEYWORD_GAMBITS.has(eff.keyword):
					_add_gambit(u, UnitCatalog.KEYWORD_GAMBITS[eff.keyword])
			_:
				var a := Effects.item_effect(eff, iid)
				if a:
					u.add(a)
	u.refill(&"hp")
	u.refill(&"ap")
	u.refill(&"pp")
	units.append(u)
	return u


## Upgrade cards are generic modifiers: {hp, atk (flat), keyword, gambit, ap, pp}.
func _apply_mod(u: BattleUnit, card: Dictionary, src: StringName) -> void:
	if card.has("hp"):
		u.get_attr(&"hp").add_flat(src, card.hp)
	if card.has("atk"):
		u.get_attr(&"attack").add_flat(src, card.atk)
	if card.has("ap"):
		u.get_attr(&"ap").add_flat(src, card.ap)
	if card.has("pp"):
		u.get_attr(&"pp").add_flat(src, card.pp)
	if card.has("keyword"):
		u.add(Effects.keyword(card.keyword))
		if UnitCatalog.KEYWORD_GAMBITS.has(card.keyword):
			_add_gambit(u, UnitCatalog.KEYWORD_GAMBITS[card.keyword])
	if card.has("gambit"):
		_add_gambit(u, card.gambit)


## Extra gambits go before the role default (always last).
func _add_gambit(u: BattleUnit, g: Dictionary) -> void:
	u.gambits.insert(maxi(0, u.gambits.size() - 1), g.duplicate())


# ---------------------------------------------------------------- queries

func living(side: int = -1) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.alive and (side == -1 or u.side == side):
			out.append(u)
	return out


func row_units(side: int, row: int) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in living(side):
		if u.row == row:
			out.append(u)
	return out


func cell_free(side: int, row: int, col: int) -> bool:
	for u in living(side):
		if u.row == row and u.col == col:
			return false
	return true


func _anyone_can_act() -> bool:
	for u in living():
		if u.ap() > 0:
			return true
	return false


func _winner() -> int:
	var a := living(0).size()
	var b := living(1).size()
	if a == 0 and b == 0:
		return -1
	if a == 0:
		return 1
	if b == 0:
		return 0
	return -2


# ---------------------------------------------------------------- turn flow

## Overtime turns so far (0 = still within the fight timer).
func overtime() -> int:
	return maxi(0, turn - GameConfig.OVERTIME_TURN)


func _play_turn() -> void:
	turn += 1
	log_event({"t": "turn", "n": turn})
	if overtime() > 0:
		log_event({"t": "overtime", "n": overtime()})
	for u in living():
		u.acted_this_turn = false
		u.emit(E.TURN_START, {"sim": self})
	var order := living()
	var keys := {}
	for u in order:
		keys[u] = u.initiative() + (0.5 if u.has_flag(&"tiebreak") else 0.0) + rng.randf() * 0.01
	order.sort_custom(func(x, y): return keys[x] > keys[y])
	for u in order:
		if not u.alive:
			continue
		_take_turn(u)
		u.acted_this_turn = true
		if _winner() != -2:
			return


func _take_turn(u: BattleUnit) -> void:
	if u.has(&"frozen"):
		u.remove(&"frozen")
		log_event({"t": "status", "u": u.uid, "status": "Frozen: skips"})
		return
	if u.ap() <= 0:
		return
	u.emit(E.OWN_TURN_START, {"sim": self})
	if not u.alive:
		return
	var actions := 1 + int(u.flag(&"extra_actions", 0.0))
	for i in actions:
		if u.ap() <= 0 or not u.alive or _winner() != -2:
			break
		if _do_ap_gambit(u, 1.0):
			u.spend(&"ap", 1)
		else:
			break
	if u.alive:
		u.emit(E.OWN_TURN_END, {"sim": self})


func _do_ap_gambit(u: BattleUnit, power_mult: float) -> bool:
	for g in u.gambits:
		if g.kind != &"ap":
			continue
		if not _cond_ok(u, g, null):
			continue
		if _execute(u, g, null, power_mult):
			return true
	return false


## A rule (gambit) can carry up to two conditions: cond/arg and cond2/arg2. Both must hold.
func _cond_ok(u: BattleUnit, g: Dictionary, ctx) -> bool:
	return _check(u, g.get("cond", &""), g.get("arg", 0.0), g, ctx) and _check(u, g.get("cond2", &""), g.get("arg2", 0.0), g, ctx)


func _check(u: BattleUnit, c: StringName, arg, g: Dictionary, ctx) -> bool:
	match c:
		&"":
			return true
		&"self_below":
			return u.hp_ratio() < arg
		&"self_above":
			return u.hp_ratio() >= arg
		&"enemy_below":
			for e in enemies_of(u):
				if e.hp_ratio() < arg:
					return true
			return false
		&"front_row":
			return u.row == 0
		&"back_row":
			return u.row == 1
		&"has_ap_left":
			return u.ap() >= int(arg)
		&"ally_below":
			for a in living(u.side):
				if a.hp_ratio() < arg:
					return true
			return false
		&"target_below":
			return ctx != null and ctx.target.alive and ctx.target.hp_ratio() < arg
		&"ally_without":
			for a in living(u.side):
				if not a.is_token and not a.has(g.arg_kw):
					return true
			return false
		&"can_sacrifice":
			return _find_token(u) != null or u.hp_ratio() > 0.5
		&"has_token":
			return _find_token(u) != null
	return true


func _find_token(u: BattleUnit) -> BattleUnit:
	for a in living(u.side):
		if a.is_token:
			return a
	return null


# ---------------------------------------------------------------- targeting

func enemies_of(u: BattleUnit) -> Array[BattleUnit]:
	return living(1 - u.side)


func melee_candidates(u: BattleUnit) -> Array[BattleUnit]:
	var foes := enemies_of(u)
	var taunts: Array[BattleUnit] = []
	var front: Array[BattleUnit] = []
	for f in foes:
		if f.row == 0:
			front.append(f)
			if f.has_flag(&"taunt"):
				taunts.append(f)
	if not taunts.is_empty():
		return taunts
	return front if not front.is_empty() else foes


func pick_target(u: BattleUnit, candidates: Array[BattleUnit]) -> BattleUnit:
	if candidates.is_empty():
		return null
	var best: BattleUnit = candidates[0]
	if u.has_flag(&"berserk"):
		for c in candidates:
			if c.hp() < best.hp():
				best = c
		return best
	# Default: same column first, then lowest HP ratio.
	var score := func(c: BattleUnit) -> float:
		return (0.0 if c.col == u.col else 1.0) + c.hp_ratio()
	for c in candidates:
		if score.call(c) < score.call(best):
			best = c
	return best


func lowest_ally(u: BattleUnit, filter := Callable()) -> BattleUnit:
	var best: BattleUnit = null
	for a in living(u.side):
		if filter.is_valid() and not filter.call(a):
			continue
		if best == null or a.hp_ratio() < best.hp_ratio():
			best = a
	return best


# ---------------------------------------------------------------- actions

func _execute(u: BattleUnit, g: Dictionary, ctx, power_mult: float) -> bool:
	var power: float = g.get("power", 1.0) * power_mult
	match g.action:
		&"strike":
			var t := pick_target(u, melee_candidates(u))
			if t == null:
				return false
			_announce(u, "Strike")
			attack(u, t, power, true)
		&"shoot":
			var t := pick_target(u, enemies_of(u))
			if t == null:
				return false
			_announce(u, "Shoot")
			attack(u, t, power, false)
		&"row_strike", &"chill_row", &"mark_row":
			var foes := enemies_of(u)
			if foes.is_empty():
				return false
			var row := 0 if not row_units(1 - u.side, 0).is_empty() else 1
			var status: StringName = {&"chill_row": &"chill", &"mark_row": &"mark"}.get(g.action, &"")
			_announce(u, String(g.action).capitalize())
			for t in row_units(1 - u.side, row):
				deal_damage(u, t, power, {"row_wide": true})
				if status != &"" and t.alive and not u.has(status):
					apply_status(u, t, status, 1)
		&"heal":
			var t: BattleUnit = ctx.target if ctx else lowest_ally(u)
			if t == null or not t.alive:
				return false
			_announce(u, "Heal")
			heal(u, t, t.max_hp() * power)
		&"ward_ally":
			var t: BattleUnit = ctx.target if ctx else lowest_ally(u, func(a): return not a.has(&"ward"))
			if t == null or not t.alive or t.has(&"ward"):
				return false
			_announce(u, "Ward")
			apply_status(u, t, &"ward", 1)
		&"grant_grow":
			var t := lowest_ally(u, func(a): return not a.is_token and not a.has(&"grow"))
			if t == null:
				return false
			_announce(u, "Grant Grow")
			t.add(Effects.keyword(&"grow"))
			log_event({"t": "buff", "u": t.uid, "text": "Gains Grow"})
		&"sacrifice":
			var victim := _find_token(u)
			if victim == null and (g.get("cond", &"") == &"has_token" or u.hp_ratio() <= 0.5):
				return false
			var t := pick_target(u, enemies_of(u))
			if t == null:
				return false
			_announce(u, "Sacrifice")
			if victim:
				raw_damage(u, victim, victim.hp() + 1.0, "Sacrificed")
			else:
				raw_damage(u, u, u.max_hp() * 0.25, "Blood price")
			var bonus: float = u.flag(&"sacrifice_heal", 0.0)
			if bonus > 0.0:
				heal(u, u, u.max_hp() * bonus)
			u.emit(&"sacrificed", {"sim": self})
			if t.alive:
				attack(u, t, power, false)
		# ---- PP reactions (ctx = the triggering situation)
		&"guard":
			if ctx == null or ctx.target == u:
				return false
			_announce(u, "Guard", true)
			ctx.target = u
		&"dodge":
			_announce(u, "Dodge", true)
			ctx.cancel = true
		&"counter":
			if ctx == null or not ctx.source.alive:
				return false
			_announce(u, "Counter", true)
			attack(u, ctx.source, power, true, false)
		&"deathwatch_strike":
			var foes := enemies_of(u)
			if foes.is_empty():
				return false
			_announce(u, "Deathwatch", true)
			attack(u, foes[rng.randi() % foes.size()], power, false)
			var refunds: float = u.flag(&"deathwatch_refund", 0.0)
			if refunds > 0.0 and u.used.get("dw_refunds", 0) < refunds:
				u.used["dw_refunds"] = u.used.get("dw_refunds", 0) + 1
				u.gain(&"pp", 1)
		_:
			push_warning("Unknown action %s" % g.action)
			return false
	return true


func _announce(u: BattleUnit, label: String, reaction := false) -> void:
	log_event({"t": "act", "u": u.uid, "text": label, "reaction": reaction})


## Single-target attack with targeting reactions (Guard, Dodge) first.
func attack(src: BattleUnit, target: BattleUnit, power: float, melee: bool, allow_reactions := true) -> void:
	var ctx := {"source": src, "target": target, "cancel": false, "melee": melee}
	if allow_reactions:
		react(&"ally_targeted", row_units(target.side, target.row).filter(func(a): return a != target), ctx, true)
		react(&"self_targeted", [ctx.target], ctx)
	if ctx.cancel:
		log_event({"t": "blocked", "u": ctx.target.uid, "text": "Dodged"})
		return
	deal_damage(src, ctx.target, power, {"melee": melee})


func deal_damage(src: BattleUnit, dst: BattleUnit, power: float, opts := {}) -> float:
	if not dst.alive:
		return 0.0
	var ctx := {"sim": self, "source": src, "target": dst, "mult": 1.0, "cancel": false,
		"melee": opts.get("melee", false), "row_wide": opts.get("row_wide", false)}
	src.emit(E.BEFORE_DEAL, ctx)
	if dst.has(&"frozen"):
		ctx.mult += src.flag(&"frozen_vuln", 0.0)
	ctx.holder = dst
	dst.emit(E.BEFORE_TAKE, ctx)
	if ctx.cancel:
		log_event({"t": "blocked", "u": dst.uid, "text": ctx.get("cancel_reason", "Blocked")})
		return 0.0
	ctx.mult += src.flag(&"dmg_bonus", 0.0)
	var dmg: float = src.atk() * power * maxf(0.1, ctx.mult)
	dmg += dst.max_hp() * src.flag(&"pct_hp_damage", 0.0) * power
	var ot := overtime()
	if ot > 0:  # overtime: damage reduction is ignored and hits keep growing
		dmg *= 1.0 + GameConfig.OVERTIME_DMG_STEP * ot
	else:
		var dr := dst.value(&"damage_reduction") + dst.flag(&"flat_dr", 0.0)
		dmg *= 1.0 - clampf(dr, 0.0, 0.8)
	dmg = roundf(dmg)
	_apply_hp_loss(src, dst, dmg)
	var dealt := {"sim": self, "target": dst, "amount": dmg, "melee": ctx.melee}
	src.emit(E.DEALT, dealt)
	if dst.alive:
		dst.emit(E.DAMAGED, {"sim": self, "source": src, "amount": dmg, "melee": ctx.melee})
		if ctx.melee:
			react(&"self_hit_melee", [dst], {"source": src, "target": dst})
		if dst.alive:
			react(&"ally_damaged", living(dst.side).filter(func(a): return a != dst), {"source": src, "target": dst})
	else:
		_on_death(dst, src)
	return dmg


## Damage that ignores defense and modifiers (thorns, sacrifice costs).
func raw_damage(src: BattleUnit, dst: BattleUnit, amount: float, label: String) -> void:
	if not dst.alive:
		return
	_apply_hp_loss(src, dst, roundf(amount), label)
	if not dst.alive:
		_on_death(dst, src)


func _apply_hp_loss(src: BattleUnit, dst: BattleUnit, dmg: float, label := "") -> void:
	var new_hp := dst.hp() - dmg
	if new_hp <= 0.0 and dst.has_flag(&"phoenix") and not dst.used.get("phoenix", false):
		dst.used["phoenix"] = true
		new_hp = 1.0
		log_event({"t": "buff", "u": dst.uid, "text": "Phoenix!"})
	dst.set_current(&"hp", maxf(0.0, new_hp))
	log_event({"t": "hit", "src": src.uid, "u": dst.uid, "amount": dmg, "hp": dst.hp(), "max": dst.max_hp(), "text": label})
	if dst.hp() <= 0.0:
		dst.alive = false


func _on_death(dead: BattleUnit, killer: BattleUnit) -> void:
	log_event({"t": "death", "u": dead.uid})
	dead.emit(E.DIED, {"sim": self, "source": killer})
	if killer and killer.alive and killer != dead and killer.side != dead.side:
		killer.emit(E.KILLED, {"sim": self, "target": dead})
		if killer.has_flag(&"kill_extra_action") and not killer.used.get("mirror", false) and _winner() == -2:
			killer.used["mirror"] = true
			log_event({"t": "buff", "u": killer.uid, "text": "Mirror Blade"})
			_do_ap_gambit(killer, 0.5)
	for u in living():
		u.emit(&"any_died", {"sim": self, "dead": dead})
	if not dead.is_token and side_flags[dead.side].has(&"altar") and not side_flags[dead.side].has(&"altar_used"):
		side_flags[dead.side][&"altar_used"] = true
		var anyone := living(dead.side)
		if not anyone.is_empty():
			summon(anyone[0], &"wraithling")
	react(&"any_died", living(), {"source": killer, "target": dead})


func heal(src: BattleUnit, dst: BattleUnit, amount: float) -> void:
	if not dst.alive or amount <= 0.0:
		return
	if overtime() > 0:
		amount *= GameConfig.OVERTIME_HEAL_MULT
	var before := dst.hp()
	dst.set_current(&"hp", before + roundf(amount))
	var got := dst.hp() - before
	if got > 0.0:
		log_event({"t": "heal", "src": src.uid, "u": dst.uid, "amount": got, "hp": dst.hp(), "max": dst.max_hp()})
		dst.emit(E.HEALED, {"sim": self, "amount": got})


func apply_status(src: BattleUnit, dst: BattleUnit, id: StringName, stacks: int) -> void:
	if not dst.alive:
		return
	if id == &"frozen" and dst.has_flag(&"immune_frozen"):
		return
	var a := dst.add(Effects.status(id, stacks))
	log_event({"t": "status", "u": dst.uid, "status": "%s x%d" % [String(id).capitalize(), a.stacks]})
	dst.emit(&"status_applied", {"sim": self, "status": id, "source": src})


## PP reactions. Each candidate may answer once per trigger.
func react(trigger: StringName, candidates: Array, ctx: Dictionary, single := false) -> void:
	if _react_depth > 3:
		return
	_react_depth += 1
	for u in candidates:
		if not u.alive or u.pp() <= 0:
			continue
		for g in u.gambits:
			if g.kind != &"pp" or g.get("trigger", &"") != trigger:
				continue
			if u.has_flag(&"berserk") and g.action in [&"heal", &"ward_ally", &"guard"]:
				continue
			if not _cond_ok(u, g, ctx):
				continue
			var free: bool = g.action == &"guard" and u.has_flag(&"free_first_guard") and not u.used.get("free_guard", false)
			if _execute(u, g, ctx, 1.0):
				if free:
					u.used["free_guard"] = true
				else:
					u.spend(&"pp", 1)
					u.emit(E.PP_SPENT, {"sim": self})
				if single:
					_react_depth -= 1
					return
				break
	_react_depth -= 1


func summon(owner: BattleUnit, token: StringName) -> BattleUnit:
	for row in [1, 0]:
		for col in GameConfig.BOARD_COLS:
			if cell_free(owner.side, row, col):
				var t := build_unit({"def": token, "row": row, "col": col}, owner.side)
				for f in side_flags[owner.side]:
					t.add(Effects.flag(f, side_flags[owner.side][f]))
				log_event({"t": "summon", "unit": _unit_info(t)})
				for ally in living(owner.side):
					if ally != t:
						ally.emit(&"ally_summoned", {"sim": self, "token": t})
				t.emit(E.BATTLE_START, {"sim": self})
				return t
	return null


func move_to_back(u: BattleUnit) -> void:
	for col in [u.col, 0, 1, 2]:
		if cell_free(u.side, 1, col):
			u.row = 1
			u.col = col
			log_event({"t": "move", "u": u.uid, "row": 1, "col": col})
			return


# ---------------------------------------------------------------- output

func log_event(ev: Dictionary) -> void:
	events_log.append(ev)


func _unit_info(u: BattleUnit) -> Dictionary:
	return {"uid": u.uid, "side": u.side, "row": u.row, "col": u.col, "name": u.display_name(),
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
	var survivors := 0
	if w >= 0:
		for u in living(w):
			if not u.is_token:
				survivors += 1
	log_event({"t": "end", "winner": w, "survivors": survivors})
	var kills := [0, 0]  ## per side: enemy non-token units it killed
	for u in units:
		if not u.alive and not u.is_token:
			kills[1 - u.side] += 1
	return {"winner": w, "survivors": survivors, "turns": turn, "log": events_log, "kills": kills,
		"standing": [_standing(0), _standing(1)]}


func _standing(side: int) -> int:
	var n := 0
	for u in living(side):
		if not u.is_token:
			n += 1
	return n
