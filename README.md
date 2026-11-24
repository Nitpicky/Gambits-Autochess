# Gambits Autochess

Godot 4.7.2 prototype of an 8-player autochess with gambit-style automatic battles.

- Open the folder in Godot 4.7.2 and press Play (main scene: `ui/main.tscn`).
- Smoke test: `tests/run_smoke.sh /path/to/Godot_v4.7.2` (headless; exit code 0 = pass).
- Screenshots (needs a display or `xvfb-run`): `godot --path . -s tests/tools/screenshot.gd -- /out/dir`.

How to play: pick a starter, buy from the shop (click a card), place units on the board
(click a unit, then a cell; your Rank is how many can fight), equip items (click an item, then a unit),
then press **Fight!**. Hover anything for details.

Art: Duelyst sprites (CC0) from https://github.com/Jordyfel/duelyst-animated-sprites-godot, copied as plain files.
