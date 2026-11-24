# ui/

PROTOTYPE placeholder UI, built entirely in code so it is cheap to throw away.

## Architecture
- `main.tscn` + `main.gd`: the one game screen (layout "take B"): relics, round strip + timer, board,
  bench zigzag + items, selected unit card, shop line + shop + rank/XP, players HP column, pick overlays,
  VICTORY/DEFEAT. Talks only to `Match`.
- `board_view.gd` (`BoardView`): tilted 2x3 + 2x3 board; planning preview (ghost of the next enemy) and battle replay.
- `unit_card.gd` (`UnitCard`): the unit card (fixed width, grows with rules; editable rules).
- `glyph.gd` (`Glyph`): vector shapes (rarity, stats, round icons, hex slots, buttons, faction emblems, keyword icons, Melee/Ranged). `hp_bar.gd` (`HpBar`): 25-HP segments.
- `info_card.gd` (`InfoCard`): hover card for items and relics (same look as the unit card).
- `sprite_view.gd` (`SpriteView`): shows a Duelyst SpriteFrames in a Control (cached loads).
- `describe.gd` (`Describe`): tooltip/detail text for units, gambits, items, relics.
- `debug_autoplay_round()` in main.gd is the hook the smoke test uses.

## Recap
- 2026-11-24: First playable UI.
- 2026-11-24: Rebuilt as one screen (take B): BoardView (tilted board, plays fights), UnitCard (editable rules), Glyph shapes, Overwatch HpBar, avatar HP column, round strip + timer, TFT-style shop; no results screen; VICTORY/DEFEAT popup. battle_view.gd removed.
- 2026-11-24: Playtest fixes: bench lists ALL units (board ones lit); drag and drop only (place, swap, unplace, equip, unequip, sell on the shop, drag an offer out to buy); battle narrator line + acting-cell highlight + hit lines; one-shot sprite animations no longer loop; InfoCard hover for items/relics; faction, keyword and Melee/Ranged icons; gold "+X" pop.
- 2026-11-24: Board cell hit areas are now placed in _ready (they had zero size, so board drops and clicks did nothing).
- 2026-11-24: Fight timer: the top bar drains over FIGHT_SECONDS (event durations from GameConfig.EVENT_SECONDS), turns red in overtime; playback speeds up per action in overtime; narrator announces it.
- 2026-11-24: Unit card rules: kit action names + cost pips + hover text; drag a row to reorder, pick conditions from a list (MenuButton), + lists the unit's actions.
