# Copilot Instructions — threematch

## GDScript Typing Rules

### Always declare explicit types for local variables
Use `: TypeName` instead of `:=` whenever the right-hand side expression does not have an unambiguous inferred type. Common cases that REQUIRE explicit types:

- Arithmetic on typed vectors: `var p: Vector2i = center + dir * dist`  ← `:=` fails here
- Mixed-type arithmetic results
- Variables assigned from untyped containers (Array, Dictionary lookups)
- Variables whose type is a GDScript class not directly returned by a typed function

```gdscript
# ✅ Correct
var p: Vector2i = center + dir * dist
var block: Block = grid[x][y]
var bt: Block.Type = b.block_type as Block.Type

# ❌ Avoid — may cause "Cannot infer type" errors
var p := center + dir * dist
var block := grid[x][y]
```

When using `:=` is acceptable:
- The RHS is a literal (`var x := 0`, `var s := "hello"`)
- The RHS is a typed function call (`var tween := create_tween()`)
- The RHS is a `new()` constructor (`var label := Label.new()`)

## Feature Preservation Invariants

Do not remove or silently rewrite these intentional gameplay/UI features when doing unrelated work:

- Battle HUD Exit button: `UILayer/ReturnButton` is visible in normal battle, uses `Locale.tr_ui("EXIT")`, sits left of Restart, and calls `_on_return_pressed()` to return to `res://scenes/map.tscn`. Stage editor may hide it.
- Bottom debug battle button row is intentionally `Exit / Restart / Kill All / Combo Test / Skill Reset`; keep the compact centered five-button layout unless the task is explicitly about that row.
- `Block.Type.ROCK` is an immutable stationary obstacle. ROCK cannot be broken, blasted, chain-blasted, matched, transformed by normal selection, or dropped by gravity. Clicking it should only shake.
- Stage fixed layouts support partial initialization: negative or missing cells are randomized normally. Stage 1-4 intentionally has ROCK at x0y1 and x7y1. Stage 1-5 intentionally has ROCK on row y1 except x4.
- Board collapse/refill with ROCK spawns new gems only from the top; spaces below ROCK remain empty unless gems slide diagonally under the ROCK roof.
- Long-press upper-gem preview includes a looping colored initial-explosion overlay. Water Slash initial preview follows the first actual sword segment/column, not the whole chain.
- Battle preparation and character list both have an independent elemental filter row. Character cards remain inside elemental color panels, and selected preparation cards show only a small green top-right check badge.
- Before editing files with existing user changes, inspect the current content and avoid reverting unrelated changes.