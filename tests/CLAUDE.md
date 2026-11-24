# tests/

## Architecture
- `run_smoke.sh <godot>`: imports, runs `smoke_test.gd` headless, fails on a failed check OR any printed
  `SCRIPT ERROR` / `ERROR`. Must pass before review.
- `smoke_test.gd`: attribute merge/buff maths, battles (determinism + every unit/item/card/relic builds),
  economy numbers, two full 8-bot games (one winner, PvE/PvP/Champion rounds happen), UI plays 4 rounds.
- `tools/screenshot.gd`: PROTOTYPE visual check, needs a display (xvfb-run).

## Etiquette
- Dispose holders/matches you create (`dispose()`), or leak warnings become ERROR lines and fail the run.

## Recap
- 2026-11-24: Created smoke test and screenshot tool.
