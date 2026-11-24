class_name Shop
extends RefCounted
## Rolls offers (3 units, 2 items, 1 relic), handles lock/reroll/discounts and buying.
## Buying a unit you already own upgrades it (see Upgrades module).

var pool: UnitPool
var rng: RandomNumberGenerator


func _init(p_pool: UnitPool, p_rng: RandomNumberGenerator) -> void:
	pool = p_pool
	rng = p_rng


## Unit def ids this player may be offered (maxed upgrades are filtered out).
func _unit_candidates(p: PlayerState, rarity: int) -> Array:
	var out: Array = []
	for id in UnitCatalog.by_rarity(rarity):
		if pool.available(id) <= 0:
			continue
		var owned := p.find_by_def(id)
		if not owned.is_empty() and owned.level > GameConfig.MAX_UPGRADE_LEVEL:
			continue
		out.append(id)
	return out


func roll(p: PlayerState) -> void:
	var bias := ShopBias.archetype_bias(p)
	var offers: Array = []
	var odds: Array = GameConfig.RARITY_ODDS[p.rank() - 1]
	for i in GameConfig.SHOP_UNITS:
		var cands: Array = []
		for attempt in 4:
			var r := _roll_index(odds)
			cands = _unit_candidates(p, r)
			if not cands.is_empty():
				break
		if cands.is_empty():
			continue
		var w: Array = cands.map(func(id): return ShopBias.weight(bias, &"unit", id))
		var id = ShopBias.weighted_pick(rng, cands, w)
		var def := UnitCatalog.get_def(id)
		offers.append({"kind": &"unit", "id": id, "price": UnitCatalog.PRICES[def.rarity], "discount": 0, "sold": false})
	var tier_odds: Array = GameConfig.ITEM_TIER_ODDS[p.rank() - 1]
	for i in GameConfig.SHOP_ITEMS:
		var price: int = [5, 15, 25][_roll_index(tier_odds)]
		var ids: Array = ItemCatalog.all().keys().filter(func(k): return ItemCatalog.get_def(k).price == price)
		var w: Array = ids.map(func(k): return ShopBias.weight(bias, &"item", k))
		var iid = ShopBias.weighted_pick(rng, ids, w)
		offers.append({"kind": &"item", "id": iid, "price": price, "discount": 0, "sold": false})
	for i in GameConfig.SHOP_RELICS:
		var ids: Array = RelicCatalog.shop_relics().filter(func(k): return not (k in p.relics))
		if ids.is_empty():
			break
		var w: Array = ids.map(func(k): return ShopBias.weight(bias, &"relic", k))
		var rid = ShopBias.weighted_pick(rng, ids, w)
		offers.append({"kind": &"relic", "id": rid, "price": RelicCatalog.get_def(rid).price, "discount": 0, "sold": false})
	_maybe_discount(p, offers)
	p.shop_offers = offers
	ShopBias.update_pity(p, offers)


func _roll_index(odds: Array) -> int:
	var total := 0
	for o in odds:
		total += o
	var r := rng.randi_range(1, total)
	for i in odds.size():
		r -= odds[i]
		if r <= 0:
			return i
	return 0


func _maybe_discount(p: PlayerState, offers: Array) -> void:
	if rng.randf() >= GameConfig.DISCOUNT_CHANCE[p.catchup_tier]:
		return
	var target: StringName = ShopBias.main_build(p)
	if target == &"":
		for a in p.lean:
			if p.lean[a] > 0.0:
				target = a
				break
	var picks: Array = offers.filter(func(o): return o.kind == &"unit" and (target == &"" or target in ShopBias.offer_archetypes(&"unit", o.id)))
	if picks.is_empty():
		return
	var o: Dictionary = picks[rng.randi() % picks.size()]
	o.discount = mini(GameConfig.DISCOUNT_GOLD, o.price - 1)
	o.price -= o.discount


## Start of planning: free roll unless locked.
func start_round(p: PlayerState) -> void:
	p.rerolls_this_round = 0
	if p.shop_locked and not p.shop_offers.is_empty():
		return
	roll(p)


func reroll(p: PlayerState) -> bool:
	var cost := Economy.reroll_cost(p)
	if p.gold() < cost:
		return false
	p.add_gold(-cost)
	p.rerolls_this_round += 1
	roll(p)
	return true


## Returns "" on success, else a reason.
func can_buy(p: PlayerState, idx: int) -> String:
	if idx < 0 or idx >= p.shop_offers.size():
		return "No offer"
	var o: Dictionary = p.shop_offers[idx]
	if o.sold:
		return "Sold"
	if p.gold() < o.price:
		return "Not enough gold"
	if o.kind == &"unit":
		var owned := p.find_by_def(o.id)
		if owned.is_empty() and p.roster.size() >= GameConfig.ROSTER_MAX:
			return "Roster full"
		if not owned.is_empty() and owned.level > GameConfig.MAX_UPGRADE_LEVEL:
			return "Max level"
		if pool.available(o.id) <= 0:
			return "Pool empty"
	return ""


## Buys an offer. Unit upgrades are reported back so the caller can queue the card pick.
func buy(p: PlayerState, idx: int) -> Dictionary:
	var why := can_buy(p, idx)
	if why != "":
		return {"ok": false, "why": why}
	var o: Dictionary = p.shop_offers[idx]
	p.add_gold(-o.price)
	o.sold = true
	match o.kind:
		&"unit":
			pool.take(o.id)
			var owned := p.find_by_def(o.id)
			if owned.is_empty():
				var u := new_unit(p, o.id, o.price)
				return {"ok": true, "unit": u}
			owned.level += 1
			owned.paid += o.price
			return {"ok": true, "upgraded": owned}
		&"item":
			p.item_bench.append(o.id)
		&"relic":
			add_relic(p, o.id)
	return {"ok": true}


static func new_unit(p: PlayerState, def_id: StringName, paid: int) -> Dictionary:
	var u := {"uid": p.new_uid(), "def": def_id, "level": 1, "items": [], "cards": [], "row": -1, "col": -1, "paid": paid, "rules": []}
	p.roster.append(u)
	return u


static func add_relic(p: PlayerState, rid: StringName) -> void:
	p.relics.append(rid)
	var a := Economy.relic_attribute(RelicCatalog.get_def(rid))
	if a:
		p.add(a)


func sell_unit(p: PlayerState, uid: int) -> int:
	var u := p.find_unit(uid)
	if u.is_empty():
		return 0
	var def := UnitCatalog.get_def(u.def)
	var refund: int = GameConfig.CHAMPION_SELL if def.rarity == UnitCatalog.Rarity.CHAMPION else u.paid
	pool.give_back(u.def, u.level)
	p.item_bench.append_array(u.items)
	p.roster.erase(u)
	p.add_gold(refund)
	return refund


static func item_sell_price(iid: StringName) -> int:
	return int(floor(ItemCatalog.get_def(iid).price * GameConfig.ITEM_SELL_RATIO))


func sell_item(p: PlayerState, bench_idx: int) -> int:
	if bench_idx < 0 or bench_idx >= p.item_bench.size():
		return 0
	var iid: StringName = p.item_bench[bench_idx]
	p.item_bench.remove_at(bench_idx)
	var g := item_sell_price(iid)
	p.add_gold(g)
	return g
