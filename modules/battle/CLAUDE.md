# modules/battle/

Deterministic auto-battle. Input: two team specs (plain dicts) + seed. Output: result + event log.

## Architecture
- `battle_sim.gd` (`BattleSim`): Warcry phase, then rounds: every living unit takes one turn in Speed order
  (Swift first). Turn: +1 AP/+1 PP (caps 3/2, start 0/1), Creep, Regenerate, Grow, Stall/turn triggers, then
  ONE action = first rule it can pay for whose conditions hold (basic Attack is free and last). `free` actions
  and Extra action steps give more. PP pays reactions (Guard, Strikeback, kit reactions). Turn end: Vanish,
  Curse, Ephemeral, timers tick. Ends when a side is wiped (eggs don't count); past FIGHT_SECONDS overtime.
  Result: winner, survivors, kills, standing, log, gold [a, b] (Bounty/Raid/gold steps) and perm (per roster
  uid: permanent stacks such as atk, deaths, bounties, raids, earned).
  Damage = Attack x p + bonus points x ATK_UNIT (Charge, Backstab, Combo, Execute...) + Vulnerable - Weaken
  - Tough x TOUGH_UNIT (min 1; overtime ignores Tough). Barrier blocks a whole hit.
- Vocabulary (kits in data/roster.json): triggers `on` warcry, deathwish, deathwatch, turn, turn_end, bitemark,
  hit_taken, kill, ally_died, below_half, moved_by_enemy, guard, token_died, charged, sacrificed, stall.
  Reactions: front_ally_hit, status_landing, hit_taken, ally_targeted_any, self_targeted, melee_hit.
  Steps: see `_step` (hit, dmg, heal, status, barrier, cleanse, purge, buff, kw, gain, numb, summon, push, pull,
  swap, blink, reposition, souls, gold, perm, transform, revive, sacrifice, creep, extra_action, stall_mod,
  special). Selectors: see `_select`. Conditions: `_cond` (kit) and `_check` (player rule chips).
- `battle_unit.gd` (`BattleUnit`): AttributeHolder + board position + kit. Stats hp/attack/initiative/ap/pp;
  keywords are "kw_<id>" attributes (merge by adding; temporary grants are timed flat sources); statuses are
  "st_<id>" attributes (stacks + duration in its own turns).
- Log events: start, turn, act, hit, heal, blocked, status, buff, death, summon, move, transform, overtime, timeout, end.

## Etiquette
- Never read player/shop state here. Everything comes through the team spec.
- Use the sim RNG only (determinism; the smoke test checks same seed -> same battle).

## Recap
- 2026-11-24: First version: gambits, AP/PP, reactions, 12 keywords, statuses, 33 item effects, relic flags, tokens.
- 2026-11-24: Flat buffs only; no Defense (damage reduction %, dmg_bonus, pct_hp_damage flags); rules can carry two conditions (new conds: self_below/above, enemy_below, front/back row); unit rules override from the team spec; result reports kills and units standing.
- 2026-11-24: Overtime once the fight clock (sum of GameConfig.EVENT_SECONDS per logged event) passes FIGHT_SECONDS: heals x OVERTIME_HEAL_MULT, hits ignore damage reduction and grow +OVERTIME_DMG_STEP per overtime turn; 'overtime' log event.
- 2026-11-24: Kit actions: generic executor (_run_action/_select/_step) for data/kits.gd actions (selectors, damage/heal/status/ward/buff/gain/redirect/cancel/summon steps, bonus_if, behind, on_kill, once, AP/PP cost); upgrade cards can add ini/dr/flags/start steps; attack() returns the unit hit; Guard reach checked per action.
- 2026-11-27: Rewritten for the roster kits: round-based turns, one action per turn + free basic attack, data-driven triggers/reactions/steps/selectors, ~50 keywords, statuses (Chill->Frozen, Icehold, Curse, Vulnerable, Weaken, Hush, Barrier, Haste, Vanished), Creep, Souls, eggs/Rebirth, forms, gold and permanent stacks in the result. effects.gd removed.
