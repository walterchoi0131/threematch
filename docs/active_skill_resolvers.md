# Active Skill Resolver Pipeline

Active skill behavior should not be added directly to the giant `match c.active_skill_name`
block in `scripts/main.gd` unless it is a temporary migration step.

## Contract

Every active skill is identified by `CharacterData.active_skill_name`.

Every resolver must expose this shape:

```gdscript
func resolve_some_skill(char_index: int, character: CharacterData) -> void:
```

The resolver may `await` animations, timers, board selection, and VFX. It should return only
after the skill has finished enough for the battle flow to continue.

## Runtime Flow

1. `main.gd` creates `ActiveSkillResolverRegistry`.
2. `main.gd` creates modules under `scripts/active_skills/*.gd`.
3. Each module calls `registry.register(skill_id, Callable(self, "..."))`.
4. `CharacterData.active_skill_name` provides the skill id at runtime.
5. `_handle_active_skill()` asks the registry to resolve the skill id.
6. If no resolver exists yet, `main.gd` falls back to the legacy `match` block.

## Where Code Belongs

- `characters/*.tres`: skill id, description, CD, display-facing data.
- `scripts/active_skills/*.gd`: active skill behavior.
- `scripts/active_skill_resolver_registry.gd`: skill id to resolver mapping.
- `scripts/main.gd`: battle orchestration and shared battle helpers.
- `scripts/board.gd`: reusable board primitives only. Avoid character-specific logic here.

## Active Skill Attributes

- `CharacterData.active_skill_blast` marks an active skill as `爆破`.
- `CharacterData.has_active_skill_blast()` is the runtime check and also honors the old
  `has_break_essence` flag for compatibility.
- A blast active skill may remove normal breakable structures such as `PLANK` and enemy-owned
  upper gems inside its affected area. It should not destroy player-owned upper gems unless the
  skill explicitly says so.
- Area conversion active skills should use `main.gd`'s `_apply_active_skill_area_convert()` so
  this behavior stays consistent across characters.

## Building Upper Gem Turn Resolvers

Building-type upper gems resolve at player turn end through `_register_building_upper_resolvers()`
in `scripts/main.gd`. Add the upper type to `Block.UPPER_BUILDING`, register a resolver with
`_register_building_upper_resolver()`, and keep repeated behavior in shared helpers. For example,
Emerald Tower and Dark Emerald Tower both use the spirit tower flow; only the upper type and target
element differ.

## Adding A New Active Skill

1. Pick a stable English skill id, for example `"Light Energy Transfer"`.
2. Set `active_skill_name` in the character `.tres` to that id.
3. Add localization in `scripts/locale.gd` for the id and `id + " DESC"`.
4. Add or reuse a module in `scripts/active_skills/`.
5. Implement `resolve_xxx(char_index, character)`.
6. Register it in that module's `register(registry)` method.
7. Add the module instance in `_register_active_skill_resolvers()` if it is a new module.

Existing localized or legacy ids may stay in the fallback `main.gd` match while they are being
migrated. New skills should prefer stable English ids and use `Locale.tr_ui()` only for display.

## Resolver Rules

- Consume CD with `ctx._use_active_skill_and_show_loot_toast(char_index)` only after validation passes.
- If the skill needs a target and no valid target exists, return before consuming CD.
- Set `ctx.board.is_busy = true` while the board must not accept input.
- For click-sensitive animation windows, use `ctx.board.set_input_queue_locked(true)` and
  `ctx.board.clear_deferred_clicks()`.
- Always unlock input and clear busy state after the skill finishes.
- Prefer board helper methods for common operations; add new board helpers only when they are
  genuinely reusable board behavior.

## Migrated Modules

- `scripts/active_skills/simple_conversion_active_skills.gd`
  - `Attack Form`
  - `Green to Fire`
  - `Kindling Blaze`
  - `Tranquil Mirror`
  - `Light Energy Transfer`

- `scripts/active_skills/emerald_tower_active_skills.gd`
  - `Wood Spirit Attack`
