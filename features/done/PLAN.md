# Implementation Plan: Built-in Triggers and move_task Refactoring

## Current Status Analysis

**Implemented:**
- Trigger infrastructure in `/lua/kanban-md/actions/triggers.lua` with registration/execution system
- Two basic triggers already implemented: `add_timestamp` (for card_created and card_moved)
- Basic move_task functionality in writer.lua with some trigger calls

**Missing Built-in Triggers from README Section 2.1:**

### Core Triggers (README lines 76-84):
- ✅ Card Created - Add timestamp, assign ID (partially implemented)
- ✅ Card Moved - Update column timestamp (implemented)
- ✅  Card Completed - Mark done (not implemented)
- ✅  Card Archived - Move to archive section (not implemented) 
- ❌ Card Deleted - Remove completely (not implemented)
- ❌ Board Opened - Calculate and display stats (not implemented)
- ❌ Board Saved - Update statistics, validate WIP limits (not implemented)

### Additional Triggers (README lines 86-91):
- ❌ Card Blocked - Add blocker property (not implemented)
- ❌ Card Prioritised - Reorder within column (not implemented)
- ❌ Card Estimated - Add/update complexity (not implemented)
- ❌ Card Tagged - Add tags for filtering (not implemented)

## Implementation Plan

### Phase 1: Implement Missing Built-in Triggers

**Location:** Add to `/lua/kanban-md/actions/triggers.lua` or create a separate built-ins file

**Core Triggers to implement:**
1. `assign_id` - Generate unique ID for new tasks 
2. `archive_task` - Handle archiving logic when moved to archive
3. `calculate_stats` - Board-level statistics calculation
4. `validate_wip_limits` - Check and warn about WIP limit violations
5. `soft_delete` - Mark task as deleted before hard removal

**Additional Triggers to implement:**
1. `add_blocker` - Add/update blocker property
2. `reorder_in_column` - Handle task prioritization within column
3. `update_complexity` - Add/update complexity estimates
4. `add_tags` - Handle task tagging functionality

### Phase 2: Refactor move_task Method 

**Issues with current writer.lua move_task (lines 392-430):**
- Uses direct trigger calls instead of proper event system
- Doesn't use on_enter/on_exit trigger framework
- Has TODO comments indicating incomplete implementation

**Refactoring approach:**
1. Update `writer.move_task` to use proper trigger event system
2. Remove direct `triggers_module.call_trigger` calls
3. Implement proper `on_exit` and `on_enter` trigger execution
4. Integrate with the column-based trigger configuration

### Phase 3: Integration Points

**Update locations where triggers should be called:**
1. `actions.lua` - move_task functions should call trigger events
2. `writer.lua` - Archive, create, and delete operations
3. Board-level operations for opened/saved events

### Phase 4: Configuration and Testing

**Add trigger configuration support:**
- Column-level trigger definitions in board configs
- Default trigger assignments for standard workflows
- Integration with existing WIP limit and validation systems

## File Organization Strategy

**Option A:** Add all built-ins to existing `triggers.lua`
**Option B:** Create `triggers/built_ins.lua` and keep infrastructure separate
**Recommendation:** Option A for simplicity, as the current trigger system can handle registration well

## Testing Strategy

- Add trigger-specific tests to verify each built-in trigger
- Integration tests for trigger execution during moves
- Round-trip tests to ensure triggers don't break board parsing/writing

## Detailed Implementation Steps

### Step 1: Implement Core Built-in Triggers

Add to `/lua/kanban-md/actions/triggers.lua`:

```lua
-- Generate unique ID for new tasks
M.register_trigger("card_created", "assign_id", function(task, column, board)
  if not task.properties.id then
    task.properties.id = require("kanban-md.helpers").generate_id(task)
  end
end)

-- Handle archiving
M.register_trigger("card_archived", "archive_task", function(task, column, board)
  task.properties.archived = os.time()
  task.properties.archived_from = task.previous_column or "unknown"
end)

-- Board statistics calculation
M.register_trigger("board_opened", "calculate_stats", function(board)
  local stats = require("kanban-md.stats")
  board.stats = stats.calculate_board_stats(board)
end)

-- WIP limit validation
M.register_trigger("board_saved", "validate_wip_limits", function(board)
  local checker = require("kanban-md.actions.checker")
  for _, column in ipairs(board.columns) do
    if column.config and column.config.wip_limit then
      local current_wip = #column.tasks
      if current_wip > column.config.wip_limit then
        vim.notify(string.format("WIP limit exceeded in %s: %d/%d", 
          column.name, current_wip, column.config.wip_limit), vim.log.levels.WARN)
      end
    end
  end
end)

-- Soft delete
M.register_trigger("card_deleted", "soft_delete", function(task, column, board)
  task.properties.deleted = os.time()
  task.properties.deleted_from = column.name
end)
```

### Step 2: Implement Additional Triggers

```lua
-- Add blocker property
M.register_trigger("card_blocked", "add_blocker", function(task, column, board)
  if not task.properties.blocker then
    local blocker = vim.fn.input("Blocker description: ")
    if blocker ~= "" then
      task.properties.blocker = blocker
      task.properties.blocked_at = os.time()
    end
  end
end)

-- Reorder within column
M.register_trigger("card_prioritised", "reorder_in_column", function(task, column, board)
  local position = vim.fn.input("Position (1-" .. #column.tasks .. "): ")
  local pos = tonumber(position)
  if pos and pos >= 1 and pos <= #column.tasks then
    task.properties.position = pos
    task.properties.prioritised_at = os.time()
  end
end)

-- Update complexity
M.register_trigger("card_estimated", "update_complexity", function(task, column, board)
  local complexity = vim.fn.input("Complexity (1-5): ", tostring(task.properties.complexity or ""))
  local comp = tonumber(complexity)
  if comp and comp >= 1 and comp <= 5 then
    task.properties.complexity = comp
    task.properties.estimated_at = os.time()
  end
end)

-- Add tags
M.register_trigger("card_tagged", "add_tags", function(task, column, board)
  local tags_input = vim.fn.input("Tags (comma-separated): ", 
    table.concat(task.properties.tags or {}, ", "))
  if tags_input ~= "" then
    local tags = {}
    for tag in tags_input:gmatch("([^,]+)") do
      table.insert(tags, vim.trim(tag))
    end
    task.properties.tags = tags
    task.properties.tagged_at = os.time()
  end
end)
```

### Step 3: Refactor move_task in writer.lua

Replace the current `move_task` function with:

```lua
function M.move_task(board, task_id, target_column_name)
  local parser = require("kanban-md.parser")
  local triggers_module = require("kanban-md.actions.triggers")

  -- Find the task and columns
  local task, source_column = parser.find_task(board, task_id)
  if not task then
    return false, "Task not found"
  end
  if not source_column then
    return false, "This task has no column, it is corrupted"
  end

  local target_column = parser.get_column(board, target_column_name)
  if not target_column then
    return false, "Target column not found"
  end

  -- Store previous column for trigger context
  task.previous_column = source_column.name

  -- Execute exit triggers
  triggers_module.call_all_trigger_functions("on_exit", task, source_column, board)

  -- Remove from source
  for i, t in ipairs(source_column.tasks) do
    if t.properties.id == task_id then
      table.remove(source_column.tasks, i)
      break
    end
  end

  -- Update task's column reference
  task.column = target_column_name

  -- Add to target
  table.insert(target_column.tasks, task)

  -- Execute entry triggers
  triggers_module.call_all_trigger_functions("on_enter", task, target_column, board)

  -- Execute move-specific triggers
  triggers_module.call_all_trigger_functions("card_moved", task, target_column, board)

  -- Special case handling
  local checker = require("kanban-md.actions.checker")
  if checker.is_completion_column(target_column, board) then
    triggers_module.call_all_trigger_functions("card_completed", task, target_column, board)
  end
  
  if target_column_name == "__ARCHIVE__" then
    triggers_module.call_all_trigger_functions("card_archived", task, target_column, board)
  end

  return true
end
```

### Step 4: Update Integration Points

1. **actions.lua**: Update move_task functions to use the new writer.move_task
2. **Add board-level trigger calls**: For board_opened and board_saved events
3. **Update delete operations**: To call card_deleted triggers

### Step 5: Testing Plan

Create tests in `tests/triggers_spec.lua`:

```lua
describe("built-in triggers", function()
  it("should mark task complete when moved to completion column", function()
    -- Test implementation
  end)
  
  it("should assign ID to new tasks", function()
    -- Test implementation
  end)
  
  it("should archive tasks properly", function()
    -- Test implementation
  end)
  
  -- Additional trigger tests...
end)
```

## Migration and Backwards Compatibility

- Existing boards will continue to work
- New trigger functionality is opt-in via column configuration
- Default triggers can be applied automatically for standard workflows
- Migration utility can add trigger configurations to existing boards
