# modules/shop/

## Architecture
- `shop.gd` (`Shop`): rolls 3 units / 2 items / 1 relic, lock, reroll, buy (buying an owned unit upgrades it),
  sell unit (refund paid, champion 30), sell item (half).
- `unit_pool.gd` (`UnitPool`): shared copies per unit (12/9/6/4 by rarity).
- `bias.gd` (`ShopBias`): per-archetype bias = (starting lean + pursuit + pity) x catch-up multiplier.
  Offer weight = 1 + best bias of its archetypes. Lean decays for ignored archetypes; pity grows on dry rolls.
- Discounts: chance by catch-up tier, -5 gold on a unit of the main build (or lean).

## Recap
- 2026-11-24: Created.
