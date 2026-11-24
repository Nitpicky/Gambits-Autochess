# ui/

PROTOTYPE placeholder UI, built entirely in code so it is cheap to throw away.

## Architecture
- `main.tscn` + `main.gd`: the one game screen (layout "take B"): relics, round strip + timer, board,
  bench zigzag + items, selected unit card, shop line + shop + rank/XP, players HP column, pick overlays,
  VICTORY/DEFEAT. Talks only to `Match`.
- `board_view.gd` (`BoardView`): tilted 2x3 + 2x3 board; planning preview (ghost of the next enemy) and battle replay.
- `unit_card.gd` (`UnitCard`): the unit card (fixed width, grows with rules; editable rules).
- `glyph.gd` (`Glyph`): vector shapes (rarity, stats, round icons, hex slots, buttons). `hp_bar.gd` (`HpBar`): 25-HP segments.
- `sprite_view.gd` (`SpriteView`): shows a Duelyst SpriteFrames in a Control (cached loads).
- `describe.gd` (`Describe`): tooltip/detail text for units, gambits, items, relics.
- `debug_autoplay_round()` in main.gd is the hook the smoke test uses.

## Recap
- 2026-11-24: First playable UI.
- 2026-11-24: Rebuilt as one screen (take B): BoardView (tilted board, plays fights), UnitCard (editable rules), Glyph shapes, Overwatch HpBar, avatar HP column, round strip + timer, TFT-style shop; no results screen; VICTORY/DEFEAT popup. battle_view.gd removed.
