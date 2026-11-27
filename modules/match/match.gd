class_name Match
extends RefCounted
## The game loop for 8 local players (1 human + 7 bots, or 8 bots for tests).
## Planning phase -> fights (PvP round-robin or PvE) -> damage -> next round.
## Picks: gold style at the start, unit choices on GameConfig.CHOICE_ROUNDS, upgrade paths.
## The UI talks only to this class; it never touches modules directly.

signal changed

const BOT_NAMES := ["Aria", "Bram", "Cyra", "Dax", "Eko", "Fen", "Gale", "Hux"]

var rng := RandomNumberGenerator.new()
var round_no: int = 0
var round_type: StringName = &"pvp"   ## pvp | pve
var players: Array[PlayerState] = []
var pool: UnitPool
var shop: Shop
var pairing := Pairing.new()
var human_id: int = -1
var over: bool = false
var last_report: Dictionary = {}
var ghost_specs: Dictionary = {}  ## player id -> last team spec (for ghosts)
var round_pairs: Array = []        ## this round's PvP pairs, decided when the round starts
var pve_team: Dictionary = {}      ## this round's monsters (PvE rounds)


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
	if GameConfig.is_pve(round_no):
		round_type = &"pve"
	else:
		round_type = &"pvp"
	_update_catchup()
	round_pairs = pairing.next_pairs(alive_ids(), rng) if round_type == &"pvp" else []
	pve_team = PvE.monster_team(round_no, rng) if round_type == &"pve" else {}
	for p in alive_players():
		p.set_meta("income", Economy.pay_income(p, round_no))
		if round_no > 1:
			Economy.free_xp(p)
		ShopBias.decay_lean(p)
		shop.start_round(p)
		if round_no == 1:
			p.pending_picks.append(_gold_style_pick())
		if GameConfig.CHOICE_ROUNDS.has(round_no):
			p.pending_picks.append(_unit_choice(p, GameConfig.CHOICE_ROUNDS[round_no]))
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

## Opening pick: how this player earns extra gold. Options are shuffled, so the
## auto-resolve (first option) when the player doesn't choose is a random style.
func _gold_style_pick() -> Dictionary:
	var opts: Array = GameConfig.GOLD_STYLES.map(func(s): return {"kind": "gold_style", "id": s})
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = opts[i]
		opts[i] = opts[j]
		opts[j] = t
	return {"kind": "gold_style", "title": "", "options": opts, "allow_skip": false}


## Pick 1 of N new units of `rarity`, each paired with an item (or its unique relic for champions).
func _unit_choice(p: PlayerState, rarity: int) -> Dictionary:
	var bias := ShopBias.archetype_bias(p)
	var cands: Array = UnitCatalog.choice_units(rarity).filter(func(id): return pool.available(id) == 0 or rarity == UnitCatalog.Rarity.CHAMPION)
	if cands.size() < GameConfig.CHOICE_OPTIONS:
		cands = UnitCatalog.choice_units(rarity)
	var item_rarity: int = GameConfig.CHOICE_ITEM_RARITY[mini(rarity, GameConfig.CHOICE_ITEM_RARITY.size() - 1)]
	var items: Array = ItemCatalog.by_rarity(item_rarity)
	var opts: Array = []
	for i in GameConfig.CHOICE_OPTIONS:
		if cands.is_empty():
			break
		var w: Array = cands.map(func(id): return ShopBias.weight(bias, &"unit", id))
		var id = ShopBias.weighted_pick(rng, cands, w)
		cands.erase(id)
		var o := {"kind": "unit", "id": id}
		var relic: StringName = UnitCatalog.get_def(id).relic
		if rarity == UnitCatalog.Rarity.CHAMPION and relic != &"":
			o["relic"] = relic
		elif not items.is_empty():
			o["item"] = items[rng.randi() % items.size()]
		opts.append(o)
	return {"kind": "choice", "rarity": rarity, "title": "", "options": opts, "allow_skip": false}


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
			# Round choices may go over the roster cap (the player can't sell while choosing).
			if p.roster.size() >= GameConfig.ROSTER_MAX and pick.kind != "choice":
				return "Roster full: sell a unit first"
			pool.take(o.id)
			pool.add_choice_unit(o.id)
			var u := Shop.new_unit(p, o.id, UnitCatalog.PRICES[UnitCatalog.get_def(o.id).rarity])
			if p.assigned().size() < p.rank():
				_place_new(p, u)
			if o.has("item"):
				p.item_bench.append(o.item)
			if o.has("relic"):
				Shop.add_relic(p, o.relic)
		"gold_style":
			p.gold_style = o.id
		"card":
			var u := p.find_unit(pick.uid)
			if not u.is_empty():
				u.cards.append(o.card)
				# edited rules keep working; an upgrade's new actions get a rule at the end
				var mine: Array = u.get("rules", [])
				if not mine.is_empty():
					for a in o.card.get("mod", {}).get("acts", []):
						mine.insert(maxi(0, mine.size() - 1), Kits.rule_for(a))
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


## Edit a unit's rules (gambits, in priority order). Empty = back to the unit's defaults.
func set_rules(p: PlayerState, uid: int, rules: Array) -> void:
	var u := p.find_unit(uid)
	if u.is_empty():
		return
	u["rules"] = rules.duplicate(true)
	changed.emit()


## The rules a unit currently fights with (its own edits, else the unit default).
static func rules_of(u: Dictionary) -> Array:
	var r: Array = u.get("rules", [])
	if not r.is_empty():
		return r
	return Kits.default_rules(u.def, u.get("cards", [])) if Kits.has_kit(u.def) else UnitCatalog.get_def(u.def).gambits


func sell_item(p: PlayerState, bench_idx: int) -> void:
	shop.sell_item(p, bench_idx)
	changed.emit()


func can_equip(p: PlayerState, bench_idx: int, uid: int) -> String:
	var u := p.find_unit(uid)
	if u.is_empty() or bench_idx < 0 or bench_idx >= p.item_bench.size():
		return "Invalid"
	var item := ItemCatalog.get_def(p.item_bench[bench_idx])
	if u.items.size() >= PlayerState.item_capacity(u):
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
			report.fights.append(_fight(p, null, pve_team))
	else:
		for pr in round_pairs:
			var a := players[pr[0]]
			var b: PlayerState = players[pr[1]] if pr[1] >= 0 else null
			report.fights.append(_fight(a, b, _ghost_for(a) if b == null else {}))
	_eliminate(report)
	last_report = report
	changed.emit()
	return report


## Who `p` fights this round: a player id, -1 for a ghost (odd count), -2 for monsters.
func opponent_of(p: PlayerState) -> int:
	if round_type == &"pve":
		return -2
	for pr in round_pairs:
		if pr[0] == p.id:
			return pr[1]
		if pr[1] == p.id:
			return pr[0]
	return -1


## The team `p` is about to face, for the planning-screen preview.
func preview_spec(p: PlayerState) -> Dictionary:
	var o := opponent_of(p)
	if o == -2:
		return pve_team
	if o >= 0:
		return players[o].team_spec()
	return {}


func opponent_name(p: PlayerState) -> String:
	var o := opponent_of(p)
	return players[o].display if o >= 0 else ("" if o == -2 else "Ghost")


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
		"survivors": res.survivors, "turns": res.turns, "log": res.log, "damage": 0,
		"bounty": [Economy.pay_bounty(a, res.kills[0], res.standing[0]), Economy.pay_bounty(b, res.kills[1], res.standing[1]) if b else 0]}
	_battle_rewards(a, res, 0)
	if b:
		_battle_rewards(b, res, 1)
	var pve := round_type == &"pve"
	a.history.append({"round": round_no, "result": "W" if res.winner == 0 else ("L" if res.winner == 1 else "D")})
	if b:
		b.history.append({"round": round_no, "result": "W" if res.winner == 1 else ("L" if res.winner == 0 else "D")})
	match res.winner:
		0:
			if b:
				fight.damage = _loss_damage(res.survivors, a.rank())
				b.lose_hp(fight.damage)
				Economy.record_result(b, false)
			if not pve:
				Economy.record_result(a, true)
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


## Gold earned in the fight (Bounty, Raid, gold steps) and permanent stacks go back to the player's units.
func _battle_rewards(p: PlayerState, res: Dictionary, side: int) -> void:
	var g: int = res.get("gold", [0, 0])[side]
	if g > 0:
		p.add_gold(g)
	elif g < 0:
		p.add_gold(-mini(-g, p.gold()))
	var perm: Dictionary = res.get("perm", [{}, {}])[side]
	for uid in perm:
		var u := p.find_unit(uid)
		if u.is_empty():
			continue
		var mine: Dictionary = u.get("perm", {})
		for k in perm[uid]:
			mine[k] = int(mine.get(k, 0)) + int(perm[uid][k])
		u["perm"] = mine


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
