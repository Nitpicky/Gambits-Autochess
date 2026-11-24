# ui/

PROTOTYPE placeholder UI, built entirely in code so it is cheap to throw away.

## Architecture
- `main.tscn` + `main.gd`: planning screen (players, board 2x3, roster, item bench, shop, details),
  pick overlay, round summary, game over. Talks only to `Match`.
- `battle_view.gd` (`BattleView`): replays a battle log with sprites, HP bars, floating text, text log, speed/skip.
- `sprite_view.gd` (`SpriteView`): shows a Duelyst SpriteFrames in a Control (cached loads).
- `describe.gd` (`Describe`): tooltip/detail text for units, gambits, items, relics.
- `debug_autoplay_round()` in main.gd is the hook the smoke test uses.

## Recap
- 2026-11-24: First playable UI.
