# modules/battle/

Deterministic auto-battle. Input: two team specs (plain dicts) + seed. Output: result + event log.

## Architecture
- `battle_sim.gd` (`BattleSim`): builds `BattleUnit`s from specs (stats, keywords, passives, items, upgrade
  cards, relics), runs turns in Initiative order. An AP gambit = 1 AP. PP gambits are reactions with a trigger
  (`ally_targeted`, `self_targeted`, `ally_damaged`, `self_hit_melee`, `any_died`). When nobody has AP left,
  everyone refills AP/PP (a cycle). Ends when a side is wiped, else after `MAX_BATTLE_CYCLES` by HP%.
  Damage = max(20% raw, raw - Defense) x (1 - damage_reduction), raw = Attack x power x mult.
- `battle_unit.gd` (`BattleUnit`): AttributeHolder + board position. Stats: hp, attack, defense, initiative,
  damage_reduction, ap, pp. Flags (`flag()`) are attributes items/relics set to tweak rules.
- `effects.gd` (`Effects`): factories + small behaviour classes for keywords, statuses (chill, mark, ward,
  frozen), item effects and passives. Remove an effect = delete its class and its factory line.
- Log events: start, turn, cycle, act, hit, heal, blocked, status, buff, death, summon, move, timeout, end.

## Etiquette
- Never read player/shop state here. Everything comes through the team spec.
- Use the sim RNG only (determinism; the smoke test checks same seed -> same battle).

## Recap
- 2026-11-24: First version: gambits, AP/PP, reactions, 12 keywords, statuses, 33 item effects, relic flags, tokens.
- 2026-11-24: Flat buffs only; no Defense (damage reduction %, dmg_bonus, pct_hp_damage flags); rules can carry two conditions (new conds: self_below/above, enemy_below, front/back row); unit rules override from the team spec; result reports kills and units standing.
