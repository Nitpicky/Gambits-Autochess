class_name Upgrades
extends RefCounted
## Upgrade cards offered when a unit levels up: the unit's 3 hand-written rank-ups from the roster kits.
## Card = {"type": "kit", "id", "name", "text", "mod": {kw, kw_del, acts, acts_del, trig, trig_del, stats, flags}},
## applied by BattleSim._apply_mod (actions merged by Kits.actions_for).


static func cards_for(def_id: StringName, _rng: RandomNumberGenerator) -> Array:
	var out := Kits.upgrades(def_id)
	if out.is_empty():  # PROTOTYPE: fallback for a unit without rank-ups
		out.append({"type": "kit", "id": "stats", "name": "Veteran", "text": "+1 HP, +1 Attack.", "mod": {"stats": {"hp": 1, "atk": 1}}})
	return out
