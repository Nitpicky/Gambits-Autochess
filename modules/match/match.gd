class_name Match
extends RefCounted
## The game loop for 8 local players (1 human + 7 bots, or 8 bots for tests).
## Planning phase -> fights (PvP round-robin, PvE, or Champion pick) -> damage -> next round.
## The UI talks only to this class; it never touches modules directly.

signal changed

const BOT_NAMES := ["Aria", "Bram", "Cyra", "Dax", "Eko", "Fen", "Gale", "Hux"]

var rng := RandomNumberGenerator.new()
var round_no: int = 0
var round_type: StringName = &"pvp"   ## pvp | pve | champion
var players: Array[PlayerState] = []
var pool: UnitPool
var shop: Shop
var pairing := Pairing.new()
var human_id: int = -1
var over: bool = false
var last_report: Dictionary = {}
var ghost_specs: Dictionary = {}  ## player id -> last team spec (for ghosts)


func new_game(seed_value: int, with_human: bool = true) -> void:
	rng.seed = seed_value
	pool = UnitPool.new()
	shop = Shop.new(pool, rng)
	players.clear()
	for i in GameConfig.PLAYERS:
		var human := with_human and i == 0
		var p := PlayerState.new(i, "You" if human else BOT_NAMES[i], not human)
		var archs: Array = Keywords.ARCHETYPES.keys()
		for k in 2:
			var a: StringName = archs[rng.randi() % archs.size()]
			archs.erase(a)
			p.lean[a] = GameConfig.START_LEAN
		players.append(p)
	human_id = 0 if with_human else -1
	round_no = 0
	over = false
	start_round()


func human() -> PlayerState:
	return players[human_id] if human_id >= 0 else null


func alive_players() -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p in players:
		if p.alive:
			out.append(p)
	return out


func alive_ids() -> Array:
	return alive_players().map(func(p): return p.id)


# ---------------------------------------------------------------- round start

func start_round() -> void:
	round_no += 1
	if round_no == GameConfig.CHAMPION_ROUND:
		round_type = &"champion"
	elif GameConfig.is_pve(round_no):
		round_type = &"pve"
	else:
		round_type = &"pvp"
	_update_catchup()
	for p in alive_players():
		p.set_meta("income", Economy.pay_income(p, round_no))
		if round_no > 1:
			Economy.free_xp(p)
		ShopBias.decay_lean(p)
		shop.start_round(p)
		if round_no == 1:
			p.pending_picks.append(_starter_pick(p))
		if round_type == &"champion":
			p.pending_picks.append(_champion_pick(p))
	for p in alive_players():
		if p.is_bot:
			Bot.play(self, p)
	changed.emit()


func _update_catchup() -> void:
	var alive := alive_players()
	if alive.is_empty():
		return
	alive.sort_custom(func(a, b): return a.hp() > b.hp())
	var leader := alive[0]
	for i in alive.size():
		var p := alive[i]
		var place := float(i) / float(maxi(1, alive.size() - 1))
		var gap := float(leader.hp() - p.hp()) / float(leader.max_hp())
		p.catchup_score = gap * (0.5 + 0.5 * place)
		p.catchup_tier = 0
		for t in GameConfig.CATCHUP_THRESHOLDS.size():
			if p.catchup_score >= GameConfig.CATCHUP_THRESHOLDS[t]:
				p.catchup_tier = t + 1


# ---------------------------------------------------------------- picks

func _starter_pick(p: PlayerState) -> Dictionary:
	var bias := ShopBias.archetype_bias(p)
	var cands: Array = UnitCatalog.by_rarity(UnitCatalog.Rarity.COMMON).filter(func(id): return pool.available(id) > 0)
	var opts: Array = []
	for i in 3:
		var w: Array = cands.map(func(id): return ShopBias.weight(bias, &"unit", id))
		var id = ShopBias.weighted_pick(rng, cands, w)
		if id == null:
			break
		cands.erase(id)
		opts.append({"kind": "unit", "id": id})
	return {"kind": "starter", "title": "Choose your starter", "options": opts, "allow_skip": false}


func _champion_pick(p: PlayerState) -> Dictionary:
	var bias := ShopBias.archetype_bias(p)
	var cands: Array = UnitCatalog.by_rarity(UnitCatalog.Rarity.CHAMPION)
	var opts: Array = []
	for i in 3:
		var w: Array = cands.map(func(id): return ShopBias.weight(bias, &"unit", id))
		var id = ShopBias.weighted_pick(rng, cands, w)
		cands.erase(id)
		opts.append({"kind": "unit", "id": id})
	return {"kind": "champion", "title": "Choose a Champion", "options": opts, "allow_skip": true,
		"skip_text": "Skip: +%d gold" % GameConfig.CHAMPION_SKIP_GOLD}


func _upgrade_pick(u: Dictionary) -> Dictionary:
	var opts: Array = []
	for c in Upgrades.cards_for(u.def, rng):
		opts.append({"kind": "card", "card": c})
	return {"kind": "upgrade", "title": "Upgrade %s: pick a path" % UnitCatalog.get_def(u.def).name, "uid": u.uid, "options": opts, "allow_skip": false}


## Returns "" on success, else why it failed.
func resolve_pick(p: PlayerState, option_idx: int) -> String:
	if p.pending_picks.is_empty():
		return "Nothing to pick"
	var pick: Dictionary = p.pending_picks[0]
	if option_idx < 0:
		if not pick.allow_skip:
			return "Must pick"
		p.add_gold(GameConfig.CHAMPION_SKIP_GOLD)
		p.pending_picks.pop_front()
		changed.emit()
		return ""
	var o: Dictionary = pick.options[option_idx]
	match o.kind:
		"unit":
			if p.roster.size() >= GameConfig.ROSTER_MAX:
				return "Roster full: sell a unit first"
			pool.take(o.id)
			var u := Shop.new_unit(p, o.id, UnitCatalog.PRICES[UnitCatalog.get_def(o.id).rarity])
			if pick.kind == "starter":
				auto_assign(p)
		"card":
			var u := p.find_unit(pick.uid)
			if not u.is_empty():
				u.cards.append(o.card)
		"gold":
			p.add_gold(o.amount)
		"xp":
			Economy.add_xp(p, o.amount)
		"item":
			p.item_bench.append(o.id)
		"relic":
			Shop.add_relic(p, o.id)
	p.pending_picks.pop_front()
	changed.emit()
	return ""


# ---------------------------------------------------------------- player actions

func buy(p: PlayerState, idx: int) -> String:
	var r := shop.buy(p, idx)
	if not r.ok:
		return r.why
	if r.has("upgraded"):
		p.pending_picks.append(_upgrade_pick(r.upgraded))
	elif r.has("unit") and p.assigned().size() < p.rank():
		_place_new(p, r.unit)
	changed.emit()
	return ""


func reroll(p: PlayerState) -> String:
	if not shop.reroll(p):
		return "Not enough gold"
	changed.emit()
	return ""


func toggle_lock(p: PlayerState) -> void:
	p.shop_locked = not p.shop_locked
	changed.emit()


func buy_xp(p: PlayerState) -> String:
	if not Economy.buy_xp(p):
		return "Can't buy XP"
	changed.emit()
	return ""


func sell_unit(p: PlayerState, uid: int) -> void:
	shop.sell_unit(p, uid)
	changed.emit()


func sell_item(p: PlayerState, bench_idx: int) -> void:
	shop.sell_item(p, bench_idx)
	changed.emit()


func can_equip(p: PlayerState, bench_idx: int, uid: int) -> String:
	var u := p.find_unit(uid)
	if u.is_empty() or bench_idx < 0 or bench_idx >= p.item_bench.size():
		return "Invalid"
	var item := ItemCatalog.get_def(p.item_bench[bench_idx])
	var is_slot_item: bool = item.effect.get("type", &"") == &"extra_slot"
	var used := 0
	for i in u.items:
		if ItemCatalog.get_def(i).effect.get("type", &"") != &"extra_slot":
			used += 1
	if not is_slot_item and used >= PlayerState.item_capacity(u):
		return "No free item slot"
	if not ItemCatalog.meets_req(item, UnitCatalog.get_def(u.def), PlayerState.unit_keywords(u)):
		return "Requires " + ItemCatalog.req_text(item)
	return ""


func equip(p: PlayerState, bench_idx: int, uid: int) -> String:
	var why := can_equip(p, bench_idx, uid)
	if why != "":
		return why
	p.find_unit(uid).items.append(p.item_bench[bench_idx])
	p.item_bench.remove_at(bench_idx)
	changed.emit()
	return ""


func unequip(p: PlayerState, uid: int, item_idx: int) -> void:
	var u := p.find_unit(uid)
	if u.is_empty() or item_idx >= u.items.size():
		return
	p.item_bench.append(u.items[item_idx])
	u.items.remove_at(item_idx)
	changed.emit()


## Move a unit to a battle cell (swaps with an occupant). row/col -1 = unassign.
func assign(p: PlayerState, uid: int, row: int, col: int) -> String:
	var u := p.find_unit(uid)
	if u.is_empty():
		return "Invalid"
	if col < 0:
		u.row = -1
		u.col = -1
		changed.emit()
		return ""
	var other := p.unit_at(row, col)
	if other.is_empty() and u.col < 0 and p.assigned().size() >= p.rank():
		return "Rank %d: only %d units can fight" % [p.rank(), p.rank()]
	if not other.is_empty() and other != u:
		other.row = u.row
		other.col = u.col
	u.row = row
	u.col = col
	changed.emit()
	return ""


func _place_new(p: PlayerState, u: Dictionary) -> void:
	var def := UnitCatalog.get_def(u.def)
	for row in [def.row, 1 - def.row]:
		for col in GameConfig.BOARD_COLS:
			if p.unit_at(row, col).is_empty():
				u.row = row
				u.col = col
				return


## Assign the best units (by rarity, level) up to Rank, front roles in front.
func auto_assign(p: PlayerState) -> void:
	for u in p.roster:
		u.row = -1
		u.col = -1
	var sorted := p.roster.duplicate()
	sorted.sort_custom(func(a, b): return _value(a) > _value(b))
	for u in sorted.slice(0, p.rank()):
		_place_new(p, u)
	changed.emit()


static func _value(u: Dictionary) -> float:
	var def := UnitCatalog.get_def(u.def)
	return def.rarity * 10.0 + u.level * 8.0 + u.items.size() * 3.0


# ---------------------------------------------------------------- fights

func end_planning() -> Dictionary:
	# Unresolved picks are auto-resolved (first option) so the game never stalls.
	for p in alive_players():
		while not p.pending_picks.is_empty():
			var pick: Dictionary = p.pending_picks[0]
			var err := resolve_pick(p, 0)
			if err != "":
				if pick.allow_skip:
					resolve_pick(p, -1)
				else:
					p.pending_picks.pop_front()
	var report := {"round": round_no, "type": round_type, "fights": []}
	for p in alive_players():
		ghost_specs[p.id] = p.team_spec()
	if round_type == &"pve":
		for p in alive_players():
			report.fights.append(_fight(p, null, PvE.monster_team(round_no, rng)))
	elif round_type == &"pvp":
		for pr in pairing.next_pairs(alive_ids(), rng):
			var a := players[pr[0]]
			var b: PlayerState = players[pr[1]] if pr[1] >= 0 else null
			report.fights.append(_fight(a, b, _ghost_for(a) if b == null else {}))
	_eliminate(report)
	last_report = report
	changed.emit()
	return report


func _ghost_for(p: PlayerState) -> Dictionary:
	var others: Array = ghost_specs.keys().filter(func(k): return k != p.id)
	var k = others[rng.randi() % others.size()] if not others.is_empty() else p.id
	var spec: Dictionary = ghost_specs[k].duplicate(true)
	spec.name = "Ghost of " + players[k].display
	return spec


## b == null: a fights `fixed_b` (monsters or ghost) and only a can be damaged.
func _fight(a: PlayerState, b: PlayerState, fixed_b: Dictionary) -> Dictionary:
	var spec_b: Dictionary = b.team_spec() if b else fixed_b
	var sim := BattleSim.new()
	var res := sim.run(a.team_spec(), spec_b, rng.randi())
	var fight := {"a": a.id, "b": b.id if b else -1, "b_name": spec_b.name, "winner": res.winner,
		"survivors": res.survivors, "turns": res.turns, "log": res.log, "damage": 0}
	var pve := round_type == &"pve"
	match res.winner:
		0:
			if b:
				fight.damage = _loss_damage(res.survivors, a.rank())
				b.lose_hp(fight.damage)
				Economy.record_result(b, false)
			if not pve:
				Economy.record_result(a, true)
			if pve:
				a.pending_picks.append({"kind": "reward", "title": "PvE reward", "options": PvE.reward_options(round_no, rng, a.relics), "allow_skip": false})
		1:
			fight.damage = _loss_damage(res.survivors, b.rank() if b else 1)
			a.lose_hp(fight.damage)
			if not pve:
				Economy.record_result(a, false)
			if b:
				Economy.record_result(b, true)
		_:
			fight.damage = GameConfig.DRAW_DAMAGE
			a.lose_hp(GameConfig.DRAW_DAMAGE)
			if b:
				b.lose_hp(GameConfig.DRAW_DAMAGE)
	return fight


static func _loss_damage(survivors: int, winner_rank: int) -> int:
	return GameConfig.LOSS_BASE + survivors + winner_rank


func _eliminate(report: Dictionary) -> void:
	var dead: Array[PlayerState] = []
	for p in alive_players():
		if p.hp() <= 0:
			dead.append(p)
	dead.sort_custom(func(a, b): return a.hp() > b.hp())
	var remaining := alive_players().size()
	for p in dead:
		p.alive = false
		p.placement = remaining
		remaining -= 1
		for u in p.roster:
			pool.give_back(u.def, u.level)
	report["eliminated"] = dead.map(func(p): return p.id)
	var alive := alive_players()
	if alive.size() <= 1:
		over = true
		if alive.size() == 1:
			alive[0].placement = 1
	if round_no >= GameConfig.MAX_ROUNDS:
		over = true  # PROTOTYPE: safety stop
	var h := human()
	if h and not h.alive:
		over = true


## Breaks player <-> attribute reference cycles. Call when throwing a match away.
func dispose() -> void:
	for p in players:
		p.dispose()
	players.clear()


func next_round() -> void:
	if not over:
		start_round()
