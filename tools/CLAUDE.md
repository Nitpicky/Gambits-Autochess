# tools/

Offline scripts (not loaded by Godot).

## Architecture
- `roster/build_roster.py`: builds `data/roster.json` from `doc_units.json` (the 144 rows of the "Keywords &
  Mechanics" doc) + `board_sprites.json` (Kit Sprite Board picks) + the hand-written kit DSL inside the script
  (KITS, TOKENS, MONSTERS, REGISTRY). Run: `python3 tools/roster/build_roster.py`.

## Etiquette
- Kits are PROTOTYPE approximations of the doc text; the approximations are noted next to each kit.

## Recap
- 2026-11-27: Created with the roster builder.
