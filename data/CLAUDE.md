# data/

Pure data, no game logic. Catalogs are GDScript dictionaries built once and cached.
PROTOTYPE: data lives in code for fast iteration; can move to .tres later.

## Architecture
- `config.gd` (`GameConfig`): every tunable number (economy, XP curve, shop odds, bias, catch-up, schedule).
- `keywords.gd` (`Keywords`): 12 keywords, faction ring, 6 archetypes, faction names/colours.
- `units.gd` (`UnitCatalog`): 36 shop units, 12 champions, 4 tokens, 6 monsters. Stats = role template x rarity.
  Gambits = explicit ones, then keyword gambits (Guard, Deathwatch, Sacrifice), then the role default.
- `items.gd` (`ItemCatalog`): 33 items = flat stats + one effect + optional requirement.
- `relics.gd` (`RelicCatalog`): 12 team-wide relics; faction relics need 2+ units of that faction in battle.

## Etiquette
- Adding a unit/item/relic is one `_u(...)` / `_i(...)` / `_r(...)` line. New effect types need a
  matching case in `modules/battle/effects.gd`.
- Sprite/icon names must exist in `art/duelyst/`.

## Recap
- 2026-11-24: Initial catalogs matching the plan doc (attack values raised ~45% so fights resolve in ~3 cycles).
- 2026-11-24: Rarities common/rare/epic/legendary/champion with new colours; HP scaled and rounded to 25, Attack scaled; Defense removed (roles and items give % damage reduction); 18 choice-only units; 12 champion relics; % buffs turned flat; new items Battle Fury, Giant Slayer, Bulwark; config: gold styles, CHOICE_ROUNDS, flat buff numbers.
