# modules/upgrades/

## Architecture
- `upgrades.gd` (`Upgrades`): 3 cards per upgrade, one per path. Cards are generic modifier dicts
  (`stats_pct`, `ap`, `pp`, `keyword`, `gambit`) applied by `BattleSim._apply_mod`.
  PROTOTYPE: generic per path, not hand-written per unit. Sprite swaps on upgrade are not done yet
  (waiting on the rank 1 to 2 sprite pairs).

## Recap
- 2026-11-24: Created.
