class_name Effects
extends RefCounted
## Factory + behaviour library for keywords, statuses, item effects, relic flags and passives.
## Every effect is an Attribute (one per id per unit) carrying small AttributeBehaviours.
## To remove an effect type: delete its class and its line in the factory.

const E = preload("res://core/events/game_events.gd")


# ---------------------------------------------------------------- factories

static func keyword(kw: StringName, extra := {}) -> Attribute:
	var a := Attribute.make(kw, 1.0, Attribute.Merge.IGNORE)
	a.tags = [&"keyword"]
	a.params = extra.duplicate()
	match kw:
		&"rally": a.behaviours = [RallyB.new()]
		&"ward": a.behaviours = [WardKwB.new()]
		&"chill": a.behaviours = [OnHitStatusB.make(&"chill", false)]
		&"swift": a.behaviours = [SwiftB.new()]
		&"mark": a.behaviours = [OnHitStatusB.make(&"mark", false)]
		&"grow": a.behaviours = [GrowB.new()]
		&"feast": a.behaviours = [FeastB.new()]
		&"construct": a.behaviours = [ConstructB.new()]
		&"fortify": a.behaviours = [FortifyB.new()]
		_: pass  # guard / sacrifice / deathwatch are gambits + tags
	return a


static func status(id: StringName, stacks: int = 1) -> Attribute:
	var a := Attribute.make(id, 0.0, Attribute.Merge.ADD_STACKS)
	a.tags = [&"status"]
	a.stacks = stacks
	match id:
		&"chill": a.behaviours = [ChillB.new()]; a.max_stacks = 9
		&"mark": a.behaviours = [MarkB.new()]; a.max_stacks = 1
		&"ward": a.behaviours = [WardB.new()]; a.max_stacks = 3
		&"frozen": a.max_stacks = 1
	return a


static func flag(name: StringName, v: float = 1.0) -> Attribute:
	var a := Attribute.make(name, v, Attribute.Merge.KEEP_MAX)
	a.tags = [&"flag"]
	return a


## Item effect -> Attribute (or null when the effect is handled at build time).
static func item_effect(effect: Dictionary, source: StringName) -> Attribute:
	if effect.is_empty():
		return null
	var t: StringName = effect.type
	var a := Attribute.make(StringName("fx_" + String(t)), 1.0, Attribute.Merge.KEEP_MAX)
	a.tags = [&"effect", source]
	a.params = effect.duplicate()
	match t:
		&"heal_turn_start": a.behaviours = [HealTurnStartB.new()]
		&"first_attack_bonus": a.behaviours = [FirstAttackB.new()]
		&"row_resist": a.behaviours = [RowResistB.new()]
		&"status_on_hit": a.behaviours = [OnHitStatusB.make(effect.status, effect.get("first_only", false))]
		&"lifesteal": a.behaviours = [LifestealB.new()]
		&"thorns": a.behaviours = [ThornsB.new()]
		&"coward": a.behaviours = [CowardB.new()]
		&"execute": a.behaviours = [ExecuteB.new()]
		&"tiebreak", &"taunt", &"berserk", &"phoenix", &"zealot", &"extra_slot":
			return flag(t, effect.get("pct", 1.0))
		&"flag":
			return flag(effect.flag, effect.get("value", 1.0))
		_:
			return null  # gambit / keyword: applied by the builder
	return a


static func passive(p: Dictionary) -> Attribute:
	if p.is_empty():
		return null
	var a := Attribute.make(StringName("passive_" + String(p.type)), 1.0, Attribute.Merge.IGNORE)
	a.tags = [&"passive"]
	a.params = p.duplicate()
	match p.type:
		&"row_aura": a.behaviours = [RowAuraB.new()]
		&"ruin": a.behaviours = [RuinB.new()]
		&"sacrifice_grows": a.behaviours = [SacrificeGrowsB.new()]
		&"tokens_fortify": a.behaviours = [TokensFortifyB.new()]
	return a


# ---------------------------------------------------------------- keywords

class RallyB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.PP_SPENT]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		var u = ctx.holder
		var heal: float = u.flag(&"rally_heal", 0.0)
		for ally in u.sim.row_units(u.side, u.row):
			ally.get_attr(&"attack").add_percent(&"rally", 0.1)
			var dr: float = ally.flag(&"rally_dr", 0.0)
			if dr > 0.0:
				ally.get_attr(&"damage_reduction").add_flat(&"rally", dr)
			if heal > 0.0:
				u.sim.heal(u, ally, ally.max_hp() * heal)
		u.sim.log_event({"t": "buff", "u": u.uid, "text": "Rally"})


class WardKwB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BATTLE_START]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		ctx.holder.sim.apply_status(ctx.holder, ctx.holder, &"ward", 1)


class SwiftB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_DEAL]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		if not ctx.target.acted_this_turn:
			ctx.mult += ctx.holder.flag(&"swift_pct", 0.25)


class GrowB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.OWN_TURN_START, E.BATTLE_START]
	func handle(e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		var u = ctx.holder
		if e == E.BATTLE_START and not u.has_flag(&"grow_at_start"):
			return
		Effects.do_grow(u)


static func do_grow(u) -> void:
	var pct: float = u.flag(&"grow_pct", 0.08)
	u.get_attr(&"attack").add_percent(&"grow", pct)
	u.get_attr(&"hp").add_percent(&"grow", pct)
	u.sim.log_event({"t": "buff", "u": u.uid, "text": "Grow", "hp": u.hp(), "max": u.max_hp()})


class FeastB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.KILLED]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		var u = ctx.holder
		u.sim.heal(u, u, u.max_hp() * 0.2)
		u.gain(&"ap", 1)
		u.sim.log_event({"t": "buff", "u": u.uid, "text": "Feast +1 AP"})


class ConstructB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BATTLE_START]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		var u = ctx.holder
		var token: StringName = a.params.get("token", u.def.get("token", &""))
		if token == &"":
			token = &"obelisk"
		var n := 2 if u.has_flag(&"extra_token") else 1
		for i in n:
			u.sim.summon(u, token)


class FortifyB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.OWN_TURN_END]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		var u = ctx.holder
		var cap: float = u.flag(&"fortify_cap", 0.4)
		var cur: float = a.params.get("stacks", 0.0)
		if cur + 0.1 <= cap + 0.001:
			a.params["stacks"] = cur + 0.1
			u.get_attr(&"damage_reduction").add_flat(&"fortify", 0.1)
			u.sim.log_event({"t": "buff", "u": u.uid, "text": "Fortify"})


class OnHitStatusB extends AttributeBehaviour:
	@export var status_id: StringName
	@export var first_only := false
	static func make(s: StringName, first: bool) -> OnHitStatusB:
		var b := OnHitStatusB.new()
		b.status_id = s
		b.first_only = first
		return b
	func key() -> String: return String(status_id)
	func events() -> Array[StringName]: return [E.DEALT]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if not ctx.target.alive:
			return
		if first_only:
			if a.params.get("done", false):
				return
			a.params["done"] = true
		ctx.holder.sim.apply_status(ctx.holder, ctx.target, status_id, 1)


# ---------------------------------------------------------------- statuses

class ChillB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [&"status_applied"]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if ctx.status != &"chill":
			return
		var u = ctx.holder
		u.get_attr(&"initiative").set_percent(&"chill", -0.1 * a.stacks)
		var at: int = int(ctx.source.flag(&"freeze_at", 3.0)) if ctx.source else 3
		if a.stacks >= at and not u.has_flag(&"immune_frozen"):
			u.remove(&"chill")
			u.get_attr(&"initiative").remove_source(&"chill")
			u.add(Effects.status(&"frozen"))
			u.sim.log_event({"t": "status", "u": u.uid, "status": "Frozen"})


class MarkB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_TAKE]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		ctx.mult += 0.2


class WardB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_TAKE]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if ctx.get("cancel", false):
			return
		ctx.cancel = true
		ctx.cancel_reason = "Ward"
		a.stacks -= 1
		if a.stacks <= 0:
			ctx.holder.remove(&"ward")


# ---------------------------------------------------------------- item effects

class HealTurnStartB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.OWN_TURN_START]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		var u = ctx.holder
		if u.hp() < u.max_hp():
			u.sim.heal(u, u, u.max_hp() * a.params.pct)


class FirstAttackB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_DEAL]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if not a.params.get("done", false):
			a.params["done"] = true
			ctx.mult += a.params.pct


class RowResistB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_TAKE]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if ctx.get("row_wide", false):
			ctx.mult -= a.params.pct


class LifestealB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.DEALT]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		ctx.holder.sim.heal(ctx.holder, ctx.holder, ctx.amount * a.params.pct)


class ThornsB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.DAMAGED]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if ctx.get("melee", false) and ctx.source and ctx.source.alive and not ctx.get("reflected", false):
			ctx.holder.sim.raw_damage(ctx.holder, ctx.source, ctx.amount * a.params.pct, "Thorns")


class CowardB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.DAMAGED]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		var u = ctx.holder
		if a.params.get("done", false) or not u.alive or u.hp_ratio() >= a.params.threshold:
			return
		a.params["done"] = true
		u.get_attr(&"defense").add_percent(&"coward", a.params.pct)
		if u.row == 0:
			u.sim.move_to_back(u)


class ExecuteB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BEFORE_DEAL]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		if ctx.target.hp_ratio() < a.params.threshold:
			ctx.mult += a.params.pct


# ---------------------------------------------------------------- passives

class RowAuraB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [E.BATTLE_START]
	func handle(_e: StringName, ctx: Dictionary, a: Attribute) -> void:
		var u = ctx.holder
		for ally in u.sim.row_units(u.side, u.row):
			ally.get_attr(a.params.stat).add_percent(&"aura", a.params.pct)


class RuinB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [&"any_died"]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		if ctx.holder.alive:
			ctx.holder.get_attr(&"attack").add_percent(&"ruin", 0.06)


class SacrificeGrowsB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [&"sacrificed"]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		Effects.do_grow(ctx.holder)
		Effects.do_grow(ctx.holder)


class TokensFortifyB extends AttributeBehaviour:
	func events() -> Array[StringName]: return [&"ally_summoned"]
	func handle(_e: StringName, ctx: Dictionary, _a: Attribute) -> void:
		ctx.token.add(Effects.keyword(&"fortify"))
