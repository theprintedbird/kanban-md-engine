# Implementation Plan: Two-Step Dependency Creation Command

**Command**: `:KanbanAddDependency`

## Approach
1. **First invocation**: Marks task under cursor as the "dependant" (task that will depend on another)
2. **Second invocation**: Marks task under cursor as the "dependency" (task that will be depended upon)
3. Adds dependency ID to first task's `depends_on` property array

## Implementation Steps

### 1. Add state management in `commands.lua`
- Module-level variable to store first selected card + column
- Clear state on completion/error

### 2. Create `M.add_dependency()` function
- Get card at cursor using existing `get_card_at_cursor()` helper
- **First call**: Store card/column, add visual feedback (virtual text or highlight)
- **Second call**:
  - Get second card at cursor
  - Validate both tasks have IDs
  - Check for circular dependencies (optional but recommended)
  - Add second card's ID to first card's `depends_on` array (initialize if needed)
  - Update buffer
  - Clear state and visual feedback

### 3. Visual feedback for marked card
- Add namespace for dependency marking highlights
- Set extmark with highlight on marked line
- Clear extmark on completion/cancellation

### 4. Error handling
- No card at cursor position
- Card missing ID property
- Trying to add self-dependency
- Duplicate dependency (already exists in array)
- Optional: circular dependency detection

### 5. Register command in `M.setup()`
- Add `KanbanAddDependency = M.add_dependency`

## Key Implementation Details
- Dependencies stored in `card.properties.depends_on` as string array
- Use `board:find_task(task_id)` for lookups
- Validation happens automatically via triggers if `dependency_validation` is enabled (set to "strict" or "warn")
- Follow existing command patterns (parse board, modify, write back)
