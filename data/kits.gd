class_name Kits
extends RefCounted
## Thin view over the roster kits (data/roster.json) for the UI and the match:
## a unit's actions after its upgrade cards, its default rules (gambits) and its 3 upgrade options.
##
## Action (from the roster) = {"id", "name", "kind": "ap" | "pp", "cost", "tgt", "fx": [steps],
##   "react": PP trigger, "cond", "souls", "free", "once", "uses", "per_turn", "cost_if", "text"}.
## Every unit also has the free basic "attack" action (last rule) unless it can't attack.
## Upgrade card = {"type": "kit", "id", "name", "text", "mod": {kw, kw_del, acts, acts_del, trig, trig_del, stats, flags}}.

const ATTACK := {"id": "attack", "name": "Attack", "kind": "ap", "cost": 0, "tgt": "foe", "fx": [{"do": "hit", "p": 1}],
	"text": "Hits for its Attack (free)."}


static func all() -> Dictionary:
	return Roster.units()


static func has_kit(def_id) -> bool:
	return not Roster.kit(def_id).is_empty()


static func kit(def_id) -> Dictionary:
	return Roster.kit(def_id)


## {action id (StringName): action} after the unit's upgrade cards (and its champion relic).
static func actions_for(def_id, cards: Array = []) -> Dictionary:
	var k := kit(def_id)
	var out := {}
	if k.is_empty():
		return out
	var mods: Array = []
	if k.has("relic_mod"):
		mods.append(k.relic_mod)
	for c in cards:
		mods.append(c.get("mod", {}))
	for a in k.get("acts", []):
		out[StringName(a.id)] = _norm(a)
	for m in mods:
		for id in m.get("acts_del", []):
			out.erase(StringName(id))
		for a in m.get("acts", []):
			out[StringName(a.id)] = _norm(a)
	if not k.get("no_attack", false):
		out[&"attack"] = _norm(ATTACK)
	return out


static func _norm(a: Dictionary) -> Dictionary:
	var d: Dictionary = a.duplicate(true)
	d["kind"] = StringName(d.get("kind", "ap"))
	d["cost"] = int(d.get("cost", 1))
	return d


## Default rules: PP reactions first, then AP actions by cost (dearest first), basic attack last.
static func default_rules(def_id, cards: Array = []) -> Array:
	var acts := actions_for(def_id, cards)
	var pp: Array = []
	var ap: Array = []
	for id in acts:
		if id == &"attack":
			continue
		(pp if acts[id].kind == &"pp" else ap).append(acts[id])
	ap.sort_custom(func(x, y): return int(x.cost) > int(y.cost))
	var rules: Array = []
	for a in pp + ap:
		rules.append(rule_for(a))
	if acts.has(&"attack"):
		rules.append(rule_for(acts[&"attack"]))
	return rules


static func rule_for(a: Dictionary) -> Dictionary:
	var r := {"kind": StringName(a.get("kind", "ap")), "action": StringName(a.id)}
	if a.has("react"):
		r["trigger"] = StringName(a.react)
	return r


static func upgrades(def_id) -> Array:
	var out: Array = []
	for u in kit(def_id).get("ups", []):
		var c: Dictionary = u.duplicate(true)
		c["type"] = "kit"
		out.append(c)
	return out
