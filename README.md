# Three Match

A match-3 puzzle game built with Godot 4.6.

## How to Play

- **Click/Tap** on a group of **2 or more** connected blocks of the same color to destroy them.
- Blocks connect **horizontally and vertically** (not diagonally).
- After blocks are destroyed, remaining blocks fall down and new blocks fill from the top.
- Each destroyed block awards **10 points**.

## Block Types

| Type   | Color  | Icon |
|--------|--------|------|
| Red    | 🔴     | ♥    |
| Blue   | 🔵     | ♦    |
| Green  | 🟢     | ♣    |
| Yellow | 🟡     | ★    |
| Purple | 🟣     | ●    |
| Orange | 🟠     | ▲    |

---

## Architecture

### Scene Tree

```
Main (Node2D)                      ← main.gd
├── Background (ColorRect)         ← dark fullscreen background
├── Board (instance: board.tscn)   ← board.gd — game logic
│   ├── Background (ColorRect)     ← board area background
│   └── [Block instances]          ← dynamically instantiated from block.tscn
└── UILayer (CanvasLayer)
    ├── TitleLabel (Label)
    ├── ScoreLabel (Label)
    └── RestartButton (Button)
```

### Scenes

| Scene            | Root Type | Script    | Purpose                              |
|------------------|-----------|-----------|--------------------------------------|
| `scenes/main.tscn`  | Node2D    | main.gd   | Root scene, UI layer, owns Board     |
| `scenes/board.tscn` | Node2D    | board.gd  | Grid, game logic, input handling     |
| `scenes/block.tscn` | Node2D    | block.gd  | Single block: visual + animations    |

### Resources

| Resource               | Type       | Purpose                                    |
|------------------------|------------|--------------------------------------------|
| `stages/stage_dev.tres` | StageData  | Dev stage: Red, Blue, Green only, min_match=2 |

### Scripts

| Script               | Responsibility                                                  |
|----------------------|-----------------------------------------------------------------|
| `scripts/block.gd`      | Block data (type, grid position), visuals, tween animations     |
| `scripts/board.gd`      | Grid state, click detection, match finding, collapse & refill   |
| `scripts/main.gd`       | Connects Board signals to UI, handles restart button            |
| `scripts/stage_data.gd` | Resource class defining stage config (allowed types, grid size, min match) |

---

## Game Logic

### Stage System

Each stage is a `StageData` resource (`scripts/stage_data.gd`) that defines:
- **allowed_types** — which block types can appear (e.g. only Red, Blue, Green)
- **min_match** — minimum connected blocks to trigger a clear (default: 2)
- **columns / rows** — grid dimensions

The Board loads a stage resource at startup. To create a new stage, duplicate `stages/stage_dev.tres` and change the exported properties.

### Core Loop

```
Player clicks block
    → Board converts click position to grid coordinates
    → Flood-fill finds all connected same-type blocks
    → If count >= min_match (stage-defined, default 2):
        1. Destroy matched blocks (scale-to-zero animation)
        2. Collapse columns (blocks above fall down with bounce)
        3. Fill empty cells (new blocks drop from above with pop animation)
    → If count < min_match:
        Shake the block (invalid move feedback)
```

### Matching Algorithm — Flood Fill (BFS)

1. Start from the clicked cell.
2. Maintain a visited dictionary and a queue.
3. For each cell in the queue, check 4 neighbors (up/down/left/right).
4. If neighbor is valid, not visited, not null, and same type → add to queue.
5. Return all connected positions.

### Gravity / Collapse

For each column (bottom to top):
- Use a write pointer starting at the bottom row.
- Move non-null blocks down to fill gaps.
- Animate each block falling to its new position.

### Refill

For each empty cell after collapse:
- Instantiate a new random block.
- Position it above the board (off-screen).
- Animate it falling into place.

---

## Game Settings

| Setting     | Value | Notes                    |
|-------------|-------|--------------------------|
| Grid size   | 8×8   | configurable per stage     |
| Cell size   | 64 px | `CELL_SIZE`              |
| Block types | 3 (dev stage) | Red, Blue, Green (configurable per stage)  |
| Match min   | 2     | Configurable per stage                     |
| Points/block| 10    | Score per destroyed block                |
| Viewport    | 576×1024 | Portrait mobile layout                |
| Stretch     | canvas_items | Scales to fit screen              |

---

## Animations

All falling blocks (both collapse and refill) use the same physics-based animation:
- **Fall speed**: 600 px/sec (`FALL_SPEED`), duration = distance / speed
- **Easing**: Bounce ease-out (`TRANS_BOUNCE`)

| Animation       | Duration | Effect                                      |
|-----------------|----------|---------------------------------------------|
| Block destroy   | 0.25s    | Scale to zero + fade out                    |
| Block fall      | distance-based | Bounce ease-out, same for collapse & refill |
| Invalid shake   | 0.15s    | Horizontal shake ±4px                        |

---

## Future Enhancements

- [ ] Chain reactions (auto-clear new matches formed after collapse)
- [ ] Combo multiplier (increasing points for consecutive clears)
- [ ] Special blocks (bombs, row/column clearers) for large matches
- [ ] Move counter or time limit for challenge modes
- [ ] Particle effects on block destruction
- [ ] Sound effects and background music
- [ ] High score persistence (save/load)
- [ ] Start screen and game-over screen
- [ ] Hint system highlighting valid groups
- [ ] No-valid-moves detection and board shuffle


## Muse
火 - 魔法, 燃燒
水 - 冰凍, 冰矛, 恢復, 生成
木 - 毒, 多段攻撃, 恢復, 生成
光 - 盾, 炸暗, 恢復, 變身
暗 - 炸暗以外, 吸血, 影子


