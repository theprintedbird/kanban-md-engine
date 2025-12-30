# Dependency Management Enhancement Plan

## Overview
This plan implements selective validation override for dependency/subtask checks while preserving other validations (WIP limits, workflow rules, custom triggers).

## Phase 1: Config Refactor

### Current State Issues
The current implementation uses `enable_dependencies` for both dependencies AND subtasks, and both share the same enforcement mode. This creates coupling and unclear configuration.

### Refactor Goals
1. Separate dependency and subtask enforcement modes
2. Make config more explicit and flexible

### Implementation

#### 1.1 Update `lua/kanban-md/config.lua`

**Current:**
```lua
enable_subtasks = false,
enable_dependencies = false, -- with "strict"/"warn"/false modes
```

**New:**
```lua
-- Dependency validation enforcement
dependency_validation = false,  -- false/"off", "strict"/"on"/true, "warn"
-- Subtask validation enforcement
subtask_validation = false,     -- false/"off", "strict"/"on"/true, "warn"
```

**Add helper functions:**
```lua
-- Get effective dependency mode
function M.get_dependency_mode()
  return M.normalize_dependency_mode(current_config.dependency_validation)
end

-- Get effective subtask mode
function M.get_subtask_mode()
  return M.normalize_dependency_mode(current_config.subtask_validation)
end
```

#### 1.2 Update `lua/kanban-md/board.lua:auto_register_triggers()`

**Change from:**
```lua
local dependency_mode = plugin_config.normalize_dependency_mode(...)
```

**To:**
```lua
local dependency_mode = plugin_config.get_dependency_mode()
local subtask_mode = plugin_config.get_subtask_mode()

-- Register dependency triggers
if dependency_mode then
  local dep_fn = subtasks_module.create_dependency_trigger(dependency_mode)
  column:register_on_checking("dependencies", dep_fn)
end

-- Register subtask triggers with potentially different mode
if subtask_mode then
  local subtask_fn = subtasks_module.create_subtask_trigger(subtask_mode)
  column:register_on_checking("subtasks", subtask_fn)
end
```

#### 1.3 Remove Old Config Options

Remove all references to `enable_dependencies` and `enable_subtasks` from the codebase.

## Phase 2: Selective Trigger Override Mechanism

### Design: Trigger Metadata System

Add metadata to triggers to mark them as "bypassable" for override scenarios.

#### 2.1 Update Trigger Registration

**In `lua/kanban-md/triggerable.lua`:**

```lua
-- Enhanced trigger registration with metadata
function Triggerable:register_trigger(event_type, name, execute_fn, metadata)
  if not self.triggers[event_type] then
    self.triggers[event_type] = {}
  end
  if not self.trigger_order[event_type] then
    self.trigger_order[event_type] = {}
  end
  if not self.trigger_metadata then
    self.trigger_metadata = {}
  end
  if not self.trigger_metadata[event_type] then
    self.trigger_metadata[event_type] = {}
  end

  -- Track insertion order if this is a new trigger
  if not self.triggers[event_type][name] then
    table.insert(self.trigger_order[event_type], name)
  end

  self.triggers[event_type][name] = execute_fn
  self.trigger_metadata[event_type][name] = metadata or {}
end

-- Convenience method for registering checking triggers with metadata
function Triggerable:register_on_checking(name, execute_fn, metadata)
  self:register_trigger("on_checking", name, execute_fn, metadata)
end
```

#### 2.2 Mark Dependency/Subtask Triggers as Bypassable

**In `lua/kanban-md/board.lua:auto_register_triggers()`:**

```lua
-- Register dependency triggers with bypass metadata
if dependency_mode then
  local dep_fn = subtasks_module.create_dependency_trigger(dependency_mode)
  column:register_on_checking("dependencies", dep_fn, {
    bypassable = true,
    category = "dependency"
  })
end

-- Register subtask triggers with bypass metadata
if subtask_mode then
  local subtask_fn = subtasks_module.create_subtask_trigger(subtask_mode)
  column:register_on_checking("subtasks", subtask_fn, {
    bypassable = true,
    category = "subtask"
  })
end
```

#### 2.3 Implement Selective Bypass in Column Validation

**In `lua/kanban-md/column.lua`:**

Update the `checkingStuff` function to respect bypass flags:

```lua
local checkingStuff = function(event_type, self, context)
  -- ... existing setup code ...

  local checking_triggers = self:get_triggers("on_checking")
  local trigger_names = self.trigger_order["on_checking"] or {}

  for _, name in ipairs(trigger_names) do
    if checking_triggers[name] then
      -- Check if this trigger should be bypassed
      local metadata = self.trigger_metadata and
                      self.trigger_metadata["on_checking"] and
                      self.trigger_metadata["on_checking"][name] or {}

      local should_bypass = false
      if context._bypass_categories and metadata.bypassable then
        for _, category in ipairs(context._bypass_categories) do
          if metadata.category == category then
            should_bypass = true
            break
          end
        end
      end

      if not should_bypass then
        -- Execute trigger normally
        local success, result = pcall(checking_triggers[name], self, context)
        if not success then
          error(string.format("Card %s validation failed [%s]: %s",
                event_type, name, result or "Unknown error"))
        end
        if result and type(result) == "table" and result.success == false then
          local err_msg = result.errors and result.errors[1] or "Unknown error"
          error(string.format("Card %s validation failed [%s]: %s",
                event_type, name, err_msg))
        end
      end
    end
  end

  return context
end
```

#### 2.4 Add Board Method for Override Moves

**In `lua/kanban-md/board.lua`:**

```lua
-- Move a card with selective validation bypass
-- @param card Card - The card to move
-- @param from_column Column - Source column
-- @param to_column Column - Target column
-- @param bypass_categories table - Array of trigger categories to bypass (e.g., {"dependency", "subtask"})
-- @return boolean - Success status
function Board:move_card_with_bypass(card, from_column, to_column, bypass_categories)
  if type(card) ~= "table" or not card.id then
    error("Board:move_card_with_bypass() expects Card object as first parameter")
  end
  if type(from_column) ~= "table" or not from_column.id then
    error("Board:move_card_with_bypass() expects Column object as second parameter")
  end
  if type(to_column) ~= "table" or not to_column.id then
    error("Board:move_card_with_bypass() expects Column object as third parameter")
  end
  if type(bypass_categories) ~= "table" then
    error("Board:move_card_with_bypass() expects array of categories as fourth parameter")
  end

  -- Build context with bypass flag
  local context = {
    card = card,
    source_column = from_column,
    target_column = to_column,
    board = self,
    _bypass_categories = bypass_categories
  }

  -- Execute move with bypass context
  from_column:remove_card(card, context)
  to_column:add_card(card, context)

  return true
end
```

## Phase 3: Override Command Implementation

### 3.1 Add Force Complete Command

**In `lua/kanban-md/commands.lua`:**

```lua
-- Command: Force complete card (bypass dependency/subtask validation)
function M.force_complete_card()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    vim.notify("No card found at cursor position", vim.log.levels.WARN)
    return
  end

  -- Find completion column
  local done_column = nil
  for _, col in ipairs(board.columns) do
    if column_helper.is_completion_column(col, board) then
      done_column = col
      break
    end
  end

  if not done_column then
    vim.notify("No completion column found", vim.log.levels.ERROR)
    return
  end

  -- Check if card already in completion column
  if column_helper.is_completion_column(current_column, board) then
    vim.notify("Card is already in a completion column", vim.log.levels.WARN)
    return
  end

  -- Show confirmation if configured
  if config.get_value("confirm_destructive") then
    vim.ui.select(
      {"Yes, force complete", "Cancel"},
      {
        prompt = string.format(
          "Force complete '%s' (bypasses dependency/subtask checks)?\n" ..
          "⚠️  WIP limits and workflow rules will still apply.",
          card.text
        ),
      },
      function(choice)
        if choice == "Yes, force complete" then
          execute_force_complete(card, current_column, done_column, board)
        end
      end
    )
  else
    execute_force_complete(card, current_column, done_column, board)
  end
end

-- Helper function to execute force complete
local function execute_force_complete(card, current_column, done_column, board)
  -- Add completion timestamp if enabled
  if config.get_value("auto_timestamp") then
    local col_key = done_column.name:lower():gsub("%s+", "_")
    card.properties[col_key] = os.time()
  end

  -- Attempt move with dependency/subtask bypass
  local success, err = pcall(function()
    board:move_card_with_bypass(
      card,
      current_column,
      done_column,
      {"dependency", "subtask"}  -- Only bypass these categories
    )
  end)

  if not success then
    notify(extract_error_message(err), vim.log.levels.ERROR)
    return
  end

  update_buffer_with_board(board)
  notify(
    string.format("Force completed '%s' (bypassed dependency/subtask checks)", card.text),
    vim.log.levels.INFO
  )
end
```

### 3.2 Register Command

**In `lua/kanban-md/commands.lua:setup()`:**

```lua
function M.setup()
  local commands = {
    -- ... existing commands ...
    KanbanCompleteCard = M.complete_card,
    KanbanForceCompleteCard = M.force_complete_card,
    -- ... rest of commands ...
  }

  -- ... registration code ...
end
```

### 3.3 Add Keybinding Documentation

Update plugin documentation to suggest:
- `<leader>kc` - Complete card (respects all validations)
- `<leader>kC` - Force complete card (bypasses dependency/subtask checks)

## Phase 4: Testing

### 4.1 Config Refactor Tests

**New file: `tests/unit/config_dependency_refactor_spec.lua`**

Test cases:
- `get_dependency_mode()` with new config format
- `get_subtask_mode()` with new config format
- Mode normalization (strict/warn/off/true/false)
- Independent configuration of dependencies and subtasks

### 4.2 Selective Bypass Tests

**New file: `tests/integration/selective_bypass_spec.lua`**

Test cases:
- Force complete bypasses dependency checks
- Force complete bypasses subtask checks
- Force complete DOES NOT bypass WIP limits
- Force complete DOES NOT bypass workflow rules
- Force complete DOES NOT bypass custom triggers
- Bypass with multiple categories works
- Bypass metadata correctly identifies bypassable triggers

### 4.3 Override Command Tests

**New file: `tests/integration/force_complete_command_spec.lua`**

Test cases:
- Command finds completion column correctly
- Command respects confirmation dialog setting
- Command adds completion timestamp
- Command handles errors from non-bypassable triggers
- Command updates buffer after successful move
- Command shows appropriate error messages

### 4.4 Update Existing Tests

Update `tests/integration/dependency_validation_spec.lua`:
- Update all tests to use new config format (`dependency_validation`, `subtask_validation`)
- Remove any tests related to old config format

## Phase 5: Documentation

### 5.1 Update CLAUDE.md

Add section on selective validation override:
```markdown
## Override Commands

### Force Complete Card

The `:KanbanForceCompleteCard` command allows moving a card to the completion column
while bypassing dependency and subtask validations.

**What it bypasses:**
- ✓ Dependency validation
- ✓ Subtask validation

**What it preserves:**
- ✓ WIP limit validation
- ✓ Workflow transition rules
- ✓ Custom validation triggers

**Configuration:**
- `confirm_destructive: true` - Shows confirmation dialog (default: true)
```

### 5.2 Update README.md

Add documentation for:
- New config format (`dependency_validation`, `subtask_validation`)
- Enforcement modes (strict/warn/off)
- Override command usage

### 5.3 Update Config Documentation

Document the new config options:
```markdown
## Configuration Options

### `dependency_validation`
Controls enforcement of dependency checks when moving cards.

- `false` or `"off"` - Disabled (default)
- `true`, `"on"`, or `"strict"` - Strict enforcement (blocks moves)
- `"warn"` - Warning mode (allows moves but shows warnings)

### `subtask_validation`
Controls enforcement of subtask completion checks when moving parent cards.

- `false` or `"off"` - Disabled (default)
- `true`, `"on"`, or `"strict"` - Strict enforcement (blocks moves)
- `"warn"` - Warning mode (allows moves but shows warnings)
```

## Implementation Order

1. **Phase 1: Config Refactor** (implement first, test, commit)
   - Update config.lua with new format and helpers
   - Update board.lua to use new helpers
   - Remove all old config option references
   - Update all tests to use new format
   - Run full test suite

2. **Phase 2: Selective Bypass** (implement second, test, commit)
   - Add trigger metadata system
   - Update column validation logic
   - Add `move_card_with_bypass()` method
   - Write bypass mechanism tests
   - Run full test suite

3. **Phase 3: Override Command** (implement third, test, commit)
   - Implement `force_complete_card()` command
   - Add confirmation dialog
   - Register command
   - Write command integration tests
   - Run full test suite

4. **Phase 4: Testing**

5. **Phase 4: Documentation** (final step)
   - Update all documentation
   - Update CLAUDE.md
   - Update README.md

## Rollback Plan

Each phase can be rolled back independently:
- Phase 1: Revert config changes
- Phase 2: Remove bypass mechanism, standard validation only
- Phase 3: Remove force complete command
- Phase 4: Testing
- Phase 5: Documentation-only, no rollback needed

## Success Criteria

- [x] All 24+ existing tests pass with updated config format
- [x] New tests for each phase pass
- [x] Force complete bypasses only dependency/subtask checks
- [x] WIP limits and workflow rules still enforced on override
- [x] Documentation complete and accurate
- [x] Config is simpler and more explicit than before
