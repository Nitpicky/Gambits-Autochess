# modules/match/

The orchestrator and the only API the UI uses.

## Architecture
- `match.gd` (`Match`): new game (8 players, starting lean), round start (income, XP, lean decay, shop roll,
  picks), player actions (buy, sell, reroll, lock, XP, equip, assign), `end_planning()` (fights, damage,
  streaks, rewards, elimination), `next_round()`. Emits `changed`.
- Schedule: rounds 1-3 PvE, 4-10 first round-robin cycle, 11 Champion pick (no fight), PvE every 5 from 15.
- `pairing.gd` (`Pairing`): circle-method round-robin; dead opponents become ghosts (copy of a last team).
- `pve.gd` (`PvE`): monster teams scaled by round, reward options.
- Picks queue (`PlayerState.pending_picks`): starter, upgrade card, PvE reward, champion. One shared UI.
- Catch-up score = HP gap to leader x (0.5 + 0.5 x placement). Tiers in `GameConfig`.

## Recap
- 2026-11-24: Created.
- 2026-11-24: Gold-style pick replaces the starter; unit choices on CHOICE_ROUNDS (rare/epic/champion+relic/legendary) replace PvE rewards and the champion round; pairs and monsters decided at round start (opponent preview); per-round history; set_rules.
