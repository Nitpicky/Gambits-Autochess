class_name ShopBias
extends RefCounted
## Archetype bias: small starting lean, pursuit (what you own), pity (dry rolls),
## all scaled by the catch-up tier. See plan doc, Shop section.


static func owned_counts(p: PlayerState) -> Dictionary:
	var counts := {}
	for a in Keywords.ARCHETYPES:
		counts[a] = 0
	for u in p.roster:
		var kws := PlayerState.unit_keywords(u)
		for a in Keywords.archetypes_of_keywords(kws):
			counts[a] += 1
	return counts


static func main_build(p: PlayerState) -> StringName:
	var counts := owned_counts(p)
	var best: StringName = &""
	var best_n := 0
	for a in counts:
		if counts[a] > best_n:
			best_n = counts[a]
			best = a
	return best


## Per-archetype bias before the catch-up multiplier.
static func archetype_bias(p: PlayerState) -> Dictionary:
	var counts := owned_counts(p)
	var out := {}
	for a in Keywords.ARCHETYPES:
		var b: float = p.lean.get(a, 0.0)
		b += minf(GameConfig.PURSUIT_CAP, GameConfig.PURSUIT_PER_UNIT * counts[a])
		b += p.pity.get(a, 0.0)
		out[a] = b * GameConfig.CATCHUP_MULT[p.catchup_tier]
	return out


static func offer_archetypes(kind: StringName, id: StringName) -> Array[StringName]:
	match kind:
		&"unit":
			var fac: StringName = UnitCatalog.get_def(id).faction
			return [fac] if Keywords.ARCHETYPES.has(fac) else []
		&"item":
			var it := ItemCatalog.get_def(id)
			var out: Array[StringName] = []
			for f in it.req.get("factions", []):
				if Keywords.ARCHETYPES.has(f):
					out.append(f)
			return out
		&"relic":
			var r := RelicCatalog.get_def(id)
			var f: StringName = r.effect.get("faction", &"")
			if f == &"":
				return []
			return [f]
	return []


static func weight(bias: Dictionary, kind: StringName, id: StringName) -> float:
	var best := 0.0
	for a in offer_archetypes(kind, id):
		best = maxf(best, bias.get(a, 0.0))
	return 1.0 + best


static func weighted_pick(rng: RandomNumberGenerator, ids: Array, weights: Array):
	var total := 0.0
	for w in weights:
		total += w
	if ids.is_empty() or total <= 0.0:
		return null
	var r := rng.randf() * total
	for i in ids.size():
		r -= weights[i]
		if r <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## Called once per round: starting lean fades for archetypes you ignore.
static func decay_lean(p: PlayerState) -> void:
	var counts := owned_counts(p)
	for a in p.lean.keys():
		if counts[a] == 0:
			p.lean[a] = maxf(0.0, p.lean[a] - GameConfig.LEAN_DECAY)


## Called after each roll: pity grows for the main build when it's missing.
static func update_pity(p: PlayerState, offers: Array) -> void:
	var build := main_build(p)
	if build == &"" or owned_counts(p)[build] < GameConfig.PITY_MIN_UNITS:
		return
	for o in offers:
		if o.kind == &"unit" and build in offer_archetypes(&"unit", o.id):
			p.pity[build] = 0.0
			return
	p.pity[build] = minf(GameConfig.PITY_CAP, p.pity.get(build, 0.0) + GameConfig.PITY_STEP)
