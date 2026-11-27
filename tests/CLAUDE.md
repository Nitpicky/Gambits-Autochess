# tests/

## Architecture
- `run_smoke.sh <godot>`: imports, runs `smoke_test.gd` headless, fails on a failed check OR any printed
  `SCRIPT ERROR` / `ERROR`. Must pass before review.
- `smoke_test.gd`: attribute merge/buff maths, battles (determinism + every unit/item/card/relic builds),
  economy numbers, two full 8-bot games (one winner, PvE/PvP/Champion rounds happen), UI plays 4 rounds.
- `tools/screenshot.gd`: PROTOTYPE, walks one seeded game and saves every screen (11 shots) for the screen notes board. Needs a display (xvfb-run).

## Etiquette
- Dispose holders/matches you create (`dispose()`), or leak warnings become ERROR lines and fail the run.

## Recap
- 2026-11-24: Created smoke test and screenshot tool.
- 2026-11-24: Screenshot tool captures every screen (picks, planning, battles, results, game over); fixed it racing main._ready().
- 2026-11-24: Smoke test updated for flat stats, HP steps, gold styles, async UI round; screenshot tool walks the new screen states.
- 2026-11-24: Screenshot tool also captures the unit card and an item/relic hover card.
- 2026-11-24: Fixed board cells having no hit area (drops and clicks on the board did nothing); `tools/drag_probe.gd` checks drag and drop with real mouse events.
- 2026-11-24: Smoke test fights every kit unit with each upgrade and checks most kit actions get used; drag probe checks rule-row reordering.
- 2026-11-27: Smoke test uses roster ids and checks keyword merging, 144 units and every sprite; tools/balance_probe.gd prints fight length and faction win rates.
