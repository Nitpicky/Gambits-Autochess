# Gambits Autochess (Godot 4.7.2 prototype)

A playground for iterating on the core loop: 8-player local autochess (1 human + 7 bots) with
Unicorn Overlord / FFXII-style gambit battles. Not final code, but it must run.
Design source of truth: the plan doc "Gambits Autochess prototype plan" (Claude Docs, linked in the project).

## Architecture
```
core/attributes/  Attribute, AttributeHolder, AttributeBehaviour  (everything is an Attribute)
core/events/      GameEvents: event names shared by every module
core/player/      PlayerState: one player (HP/Rank/XP/Gold/streak are Attributes) + roster data
data/             Pure data: roster.json (generated kits), units, keywords, items, relics, config (all tunable numbers)
modules/battle/   BattleSim (deterministic, headless): rounds, kits, keywords, statuses, triggers
modules/economy/  income, interest, streaks, XP/rank, economy relics
modules/shop/     offers, shared unit pool, archetype bias + catch-up, discounts
modules/upgrades/ upgrade cards (each unit's 3 rank-ups from the roster)
modules/match/    round loop, pairing (round-robin), PvE, picks, damage, elimination
modules/bots/     random bot
ui/               PROTOTYPE planning screen, battle viewer, pick screen (built in code)
art/duelyst/      Duelyst sprites (CC0) copied as plain files: only the ones used
tests/            headless smoke test (must pass before review) + tools (screenshots, drag probe, balance probe)
tools/roster/     build_roster.py: kit doc + sprite board -> data/roster.json
```
Dependency direction: `data` <- `core` <- `modules/*` <- `modules/match` <- `ui`.
Modules never reach into `ui`. Only `modules/match` orchestrates other modules.

## Etiquette
- Question phase + restate before any task; flag clashes with what is built.
- Every directory has a CLAUDE.md. Add a dated recap line to each one you touch.
- Mark throwaway code with `# PROTOTYPE:`.
- Ask before adding plugins or addons (there are none).
- Numbers live in `data/config.gd` or the catalogs, never inline in modules.
- Run `tests/run_smoke.sh <godot-4.7.2-binary>` before review. It fails on any script error.
- Times are Europe/Paris.

## Recap
- 2026-11-24: First playable prototype: attribute core, battle sim, economy, shop/bias, upgrades, match loop, bots, UI, smoke test.
- 2026-11-24: Redesigned game from the UX phase (screens canvas + notes doc): one screen (take B), fights on the board, gold styles, unit choice rounds, editable rules, flat stats, HP in steps of 25, no Defense.
- 2026-11-24: Playtest fixes: full-roster bench, drag and drop, battle narrator, item/relic hover cards, faction/keyword/range icons, fights until wipe, softer PvE.
- 2026-11-24: Fight timer + overtime; hand-written unit kits (Lyonar test slice) with per-unit upgrades; easier rule editing.
- 2026-11-27: New roster: the 144 doc kits (Keywords & Mechanics doc) + champion relics as data (tools/roster -> data/roster.json), sprites from the Kit Sprite Board, a new battle engine for the agreed keywords, items/relics ported onto the new keywords.
