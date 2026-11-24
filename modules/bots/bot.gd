class_name Bot
extends RefCounted
## PROTOTYPE: random bot. Resolves picks, buys what it can afford, levels up, places units.


static func play(m: Match, p: PlayerState) -> void:
	var rng := m.rng
	_resolve_picks(m, p, rng)
	for step in 12:
		var bought := false
		var order := range(p.shop_offers.size())
		# upgrades first, then units, then the rest
		order.sort_custom(func(a, b): return _prio(p, p.shop_offers[a]) > _prio(p, p.shop_offers[b]))
		for i in order:
			var o: Dictionary = p.shop_offers[i]
			if o.sold or m.shop.can_buy(p, i) != "":
				continue
			if o.kind == &"relic" and rng.randf() > 0.35:
				continue
			if o.kind == &"item" and (p.roster.is_empty() or rng.randf() > 0.5):
				continue
			if m.buy(p, i) == "":
				bought = true
				_resolve_picks(m, p, rng)
				break
		if bought:
			continue
		if p.gold() >= 25 and rng.randf() < 0.5 and m.reroll(p) == "":
			continue
		if p.gold() >= GameConfig.XP_BUY_COST + 8 and p.rank() < GameConfig.MAX_RANK and rng.randf() < 0.6:
			m.buy_xp(p)
			continue
		break
	_equip_items(m, p)
	m.auto_assign(p)


static func _prio(p: PlayerState, o: Dictionary) -> float:
	if o.sold:
		return -1.0
	if o.kind == &"unit":
		return 3.0 if not p.find_by_def(o.id).is_empty() else 2.0
	return 1.0


static func _resolve_picks(m: Match, p: PlayerState, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while not p.pending_picks.is_empty() and guard < 10:
		guard += 1
		var pick: Dictionary = p.pending_picks[0]
		if pick.kind == "champion" and p.roster.size() >= GameConfig.ROSTER_MAX:
			var worst = p.roster[0]
			for u in p.roster:
				if Match._value(u) < Match._value(worst):
					worst = u
			m.sell_unit(p, worst.uid)
		var err := m.resolve_pick(p, rng.randi() % pick.options.size())
		if err != "":
			if pick.allow_skip:
				m.resolve_pick(p, -1)
			else:
				p.pending_picks.pop_front()


static func _equip_items(m: Match, p: PlayerState) -> void:
	var i := 0
	while i < p.item_bench.size():
		var done := false
		for u in p.roster:
			if m.can_equip(p, i, u.uid) == "":
				m.equip(p, i, u.uid)
				done = true
				break
		if not done:
			i += 1
