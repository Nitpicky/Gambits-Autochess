class_name Economy
extends RefCounted
## Gold income, interest, streaks, XP and rank. Stateless: works on a PlayerState.
## Economy relics hook in through player Attributes reacting to ROUND_INCOME / ROUND_XP / REROLL_COST.

const E = preload("res://core/events/game_events.gd")


## Returns {"total", "base", "interest", "streak", "bonus"} and pays it.
static func pay_income(p: PlayerState, round_no: int) -> Dictionary:
	var r := {"base": 0, "interest": 0, "streak": 0, "bonus": 0}
	if round_no == 1:
		r.base = GameConfig.FIRST_ROUND_GOLD
	else:
		r.base = GameConfig.INCOME
		r.interest = mini(GameConfig.INTEREST_CAP, p.gold() / GameConfig.INTEREST_PER)
		r.streak = streak_bonus(p.streak())
		var ctx := p.emit(E.ROUND_INCOME, {"gold": 0})
		r.bonus = ctx.gold
	r["total"] = r.base + r.interest + r.streak + r.bonus
	p.add_gold(r.total)
	return r


static func streak_bonus(streak: int) -> int:
	var s := absi(streak)
	for pair in GameConfig.STREAK_BONUS:
		if s >= pair[0]:
			return pair[1]
	return 0


static func record_result(p: PlayerState, won: bool) -> void:
	var s := p.streak()
	if won:
		p.set_streak(s + 1 if s > 0 else 1)
	else:
		p.set_streak(s - 1 if s < 0 else -1)


static func free_xp(p: PlayerState) -> void:
	var ctx := p.emit(E.ROUND_XP, {"xp": GameConfig.FREE_XP})
	add_xp(p, ctx.xp)


static func can_buy_xp(p: PlayerState) -> bool:
	return p.rank() < GameConfig.MAX_RANK and p.gold() >= GameConfig.XP_BUY_COST


static func buy_xp(p: PlayerState) -> bool:
	if not can_buy_xp(p):
		return false
	p.add_gold(-GameConfig.XP_BUY_COST)
	add_xp(p, GameConfig.XP_BUY_AMOUNT)
	return true


static func add_xp(p: PlayerState, n: int) -> void:
	var xp_attr := p.get_attr(&"xp")
	var rank_attr := p.get_attr(&"rank")
	if p.rank() >= GameConfig.MAX_RANK:
		return
	xp_attr.base += n
	while p.rank() < GameConfig.MAX_RANK and xp_attr.base >= GameConfig.xp_to_next(p.rank()):
		xp_attr.base -= GameConfig.xp_to_next(p.rank())
		rank_attr.base += 1
	if p.rank() >= GameConfig.MAX_RANK:
		xp_attr.base = 0


static func reroll_cost(p: PlayerState) -> int:
	## The round's first roll is free (automatic); manual reroll n costs n gold.
	var n := p.rerolls_this_round + 1
	var ctx := p.emit(E.REROLL_COST, {"cost": n, "reroll_index": n})
	return maxi(0, ctx.cost)


## Economy relics become player attributes with a behaviour.
static func relic_attribute(relic: Dictionary) -> Attribute:
	var eff: Dictionary = relic.effect
	if eff.type != &"economy":
		return null
	var a := Attribute.make(StringName("relic_" + String(relic.id)), 1.0, Attribute.Merge.IGNORE)
	a.params = eff.duplicate()
	a.behaviours = [EconomyRelicB.new()]
	return a


class EconomyRelicB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.ROUND_INCOME, E.ROUND_XP, E.REROLL_COST]
	func handle(e: StringName, ctx: Dictionary, a: Attribute) -> void:
		match e:
			E.ROUND_INCOME: ctx.gold += a.params.get("gold", 0)
			E.ROUND_XP: ctx.xp += a.params.get("xp", 0)
			E.REROLL_COST:
				# free_rerolls = how many manual rerolls are free before paying starts.
				var free: int = a.params.get("free_rerolls", 0)
				if free > 0 and ctx.reroll_index <= free:
					ctx.cost = 0
				elif free > 0:
					ctx.cost = ctx.reroll_index - free
