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
</content>
</invoke>