# core/

Shared foundations every module uses. Nothing here knows about shops, battles or UI.

## Architecture
- `attributes/attribute.gd` (`Attribute`): one generic value. `value() = (base + flat) * (1 + sum of percents)`.
  Optional `current` (HP, AP pools). `stacks`, `duration`, `tags`, `params`, `behaviours`.
  Merge rule per attribute (`ADD_STACKS`, `ADD_VALUE`, `KEEP_MAX`, `REFRESH`, `REPLACE`, `IGNORE`).
- `attributes/attribute_holder.gd` (`AttributeHolder`): one attribute per id; adding the same id merges.
  `emit(event, ctx)` dispatches to every behaviour listening to that event; `ctx` is mutable.
  Call `dispose()` when throwing a holder away (breaks the holder <-> attribute cycle).
- `attributes/attribute_behaviour.gd` (`AttributeBehaviour`): override `events()` and `handle()`.
- `events/game_events.gd` (`GameEvents`): event name constants. In scripts use
  `const E = preload("res://core/events/game_events.gd")` (a class_name is not a constant expression).
- `player/player_state.gd` (`PlayerState`): a player as an AttributeHolder + roster/bench/relics/shop state.

## Etiquette
- Buffs are percent only (`add_percent`). Flat is reserved for item stats (`add_flat`) and summed first.
- Add a new event name in `GameEvents`, nothing else to register.

## Recap
- 2026-11-24: Created Attribute / AttributeHolder / AttributeBehaviour, GameEvents, PlayerState.
- 2026-11-24: Attribute percent layer removed (every stat increase is flat); PlayerState gains gold_style and per-unit editable rules.
- 2026-11-27: PlayerState: unit keywords from cards/items keyword lists, fixed item slots, team spec carries uid + perm.
