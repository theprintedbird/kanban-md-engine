# Complexity Feature Implementation Summary

## Overview
Implemented board-level configuration for the complexity property feature, allowing different kanban boards to have different complexity defaults.

## Implementation Approach

### Architecture: Trigger-Based
Follows the same pattern as `auto_timestamp` - uses the trigger system rather than direct property setting. This provides:
- Consistency with existing features
- Extensibility (users can customize triggers)
- Clear separation of concerns
- Board-level configuration support

### Files Modified

#### 1. lua/kanban-md/triggers.lua
- Added `create_default_complexity_trigger(default_value)` function
- Trigger fires on card entry to column (`on_entry` event)
- Only adds complexity if card doesn't already have one
- Exported as `default_complexity` in module

#### 2. lua/kanban-md/board.lua
- Modified `Board:register_basic_triggers()` to register complexity trigger
- Checks `board.config.use_complexity` first, then falls back to plugin config
- Checks `board.config.default_complexity` first, then falls back to plugin config
- Follows exact same pattern as `auto_timestamp` implementation

#### 3. lua/kanban-md/card.lua
- **Removed** the old auto-add complexity logic from `Card:new()`
- Complexity is now added via triggers when cards enter columns
- Cards created outside of board context don't get auto-complexity

#### 4. tests/manual-tests/complexity_demo.md
- Updated documentation with board-level config examples
- Documented priority chain
- Added example markdown showing board-level usage

#### 5. tests/integration/auto_complexity_spec.lua
- Created comprehensive integration tests
- Mirrors structure of `auto_timestamp_spec.lua`
- Tests all scenarios: plugin config, board config, overrides, parsing, persistence

## Configuration Priority Chain

1. **Existing card complexity property** → Never overridden
2. **Board-level config** → `<!-- kanban:config use_complexity: true, default_complexity: 3 -->`
3. **Plugin-level config** → `require('kanban-md').setup({ use_complexity = true, default_complexity = 1 })`

## Behavior Details

### When Does Auto-Complexity Apply?
- ✅ When adding new cards via `:KanbanNewCard` command
- ✅ When programmatically adding cards to columns via `column:add_card()`
- ❌ **NOT** when parsing cards from markdown (preserves what's in markdown)

### Why Not During Parsing?
This matches the `auto_timestamp` behavior:
- Parsing should preserve what's in the markdown file
- Auto-features are for creating/moving cards via the UI
- Existing timestamps/complexity in markdown are parsed as properties
- New cards added after parsing will get auto-complexity if enabled

## Usage Examples

### Global Plugin Configuration
```lua
require('kanban-md').setup({
  use_complexity = true,
  default_complexity = 3,
})
```

### Board-Level Configuration (Markdown)
```markdown
# Sprint Board
<!-- kanban:config use_complexity: true, default_complexity: 5 -->

## To Do
- New task without complexity  <!-- Will get complexity: 5 when added via UI -->
- Task with complexity <!-- complexity: 2 -->  <!-- Keeps its value -->
```

### Programmatic Usage
```lua
local board = Board:new()
board.config.use_complexity = true
board.config.default_complexity = 8

local col = board:add_column("todo", "To Do")
board:auto_register_triggers()

local card = Card:new("card-1", "New task")
col:add_card(card)  -- Card will have complexity: 8
```

### Setting Complexity Manually
```vim
" Place cursor on any card line
:KanbanSetComplexity
" Enter a number when prompted
```

## Test Coverage

### Integration Tests (`tests/integration/auto_complexity_spec.lua`)
- Default behavior (disabled by default)
- Plugin-level config enabled
- Board-level config overrides plugin config
- Doesn't override existing complexity
- Works when cards move between columns
- Parsing preserves markdown values
- New cards added after parsing get auto-complexity
- Write/parse cycle persistence

### Manual Tests
- `test_complexity.lua` - Trigger-based functionality
- `test_set_complexity_command.lua` - Command functionality
- `test_board_level_complexity.lua` - End-to-end workflow
- `complexity_demo.md` - User documentation

### Test Results
All 12 integration tests passing:
- ✅ with default config (use_complexity = false)
- ✅ when use_complexity is enabled at plugin level
- ✅ board-level config overrides plugin-level config
- ✅ with parsed boards containing config

## Backwards Compatibility

- **Existing boards without complexity config**: Unchanged (feature disabled by default)
- **Existing cards with complexity**: Values preserved
- **`:KanbanSetComplexity` command**: Works exactly as before
- **Plugin config**: Works as fallback for boards without board-level config

## Design Decisions

### 1. Trigger-Based vs Direct Setting
**Chosen**: Trigger-based
**Rationale**: Consistency with auto_timestamp, extensibility, clear architecture

### 2. Auto-Add During Parsing vs Only on UI Actions
**Chosen**: Only on UI actions
**Rationale**: Matches auto_timestamp, preserves markdown fidelity, clearer semantics

### 3. Board Config Override Priority
**Chosen**: Board config > Plugin config
**Rationale**: More specific config should override general config, allows per-board customization

## Future Enhancements

Potential future improvements:
- Column-level complexity config (different defaults per column)
- Complexity validation (min/max values)
- Complexity templates (e.g., T-shirt sizes: S=1, M=2, L=5, XL=8)
- Auto-calculate complexity based on card properties
- Statistics aggregation by complexity

## Related Features

Works well with:
- Statistics calculation (total complexity per column)
- WIP limits (could be based on complexity instead of count)
- Cycle time tracking (complexity vs actual time)
- Capacity planning (team velocity based on complexity)
