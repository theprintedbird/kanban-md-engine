# Advanced Column Configuration Implementation Plan

## Overview
Implement a flexible column type system where column types are user-defined in config, not hardcoded. The system will resolve column types through a priority chain and auto-register triggers based on type definitions.

**Implementation Status**: ✅ Complete (all core features implemented and tested)

## Progress Summary

### Completed ✅
- Config schema defined in `lua/kanban-md/config.lua`
- All config options fully documented with inline comments
- `column_config` structure with `types` and `definitions`
- `missing_property_requirement` validation option
- `write_full_config_to_markdown` flag added to config
- Writer support for `write_full_config_to_markdown = true` (implemented in writer_mixin.lua)
- `column_type_resolver.lua` module implemented with all functions
- Unit tests for resolver (comprehensive coverage of all functions)
- Integration tests for end-to-end flow (pattern matching, definitions, triggers, etc.)
- Parser integration (type resolution and property merging)
- Column.lua type field addition
- Board.lua trigger registration enhancements (`register_type_triggers()` method)
- Trigger auto-registration from type definitions
- Validation of required properties via `validate_requirements()`
- All 1111 tests passing

### In Progress 🚧
- None currently

### Pending ⬜
- None currently (all core features implemented and tested)

### Future 🔮
- Type inheritance (types inheriting from parent types)
- Computed properties (property values as functions)
- Transition validation (restricting card movement between column types)
- UI indicators (showing column type visually)

## Core Principles
- **No hardcoded types** - all types (including "archive", "completion", etc.) use the same mechanism available to users
- **Markdown always wins** - highest priority in property merging
- **Lua patterns** for pattern matching in type definitions
- **Fail early** with clear error messages for missing trigger registrations or required properties
- **Full backwards compatibility** with simple `<!-- config wip_limit: 3 -->` syntax

## Key Design Decisions

### Trigger Registration
- Trigger names in type definitions reference pre-registered functions
- Users must ensure triggers are loaded before config is processed
- If a trigger is missing at registration time, emit a clear error message
- Triggers are registered via existing `Triggerable:register_trigger` mechanism
- No external registry - triggers stored in object's `self.triggers` table

### Property Merging Strategy
When a column has both type-inherited properties AND explicit markdown properties:
1. Start with type definition properties
2. Merge in config definition properties (if column name matches a definition)
3. Merge in markdown properties (markdown always wins)
4. Example: Type has `is_active_state: true`, markdown has `wip_limit: 5` → both present in final config

### Pattern Matching
- Use **Lua patterns** (not regex)
- Patterns only in `types[*].patterns` for type matching
- Definitions use exact column name matching only
- Multiple patterns per type supported as array

### Validation
- `missing_property_requirement` config: `"none"` / `"warning"` / `"error"`
- Initial implementation: hardcode warnings, scaffold for future config-driven behavior
- Validate at parse time or during `auto_register_triggers()`

### Writer Behavior
- New config: `write_full_config_to_markdown = false` (default)
- When `false`: keep type implicit (current behavior)
- When `true`: write resolved type back to markdown (future implementation)

## Implementation Checklist

### Files to Create

#### 1. `lua/kanban-md/column_type_resolver.lua` (NEW)
- [x] Create file
- [x] Implement `resolve_type()` function
- [x] Implement `get_type_definition()` function
- [x] Implement `merge_properties()` function
- [x] Implement `validate_requirements()` function
- [x] Implement `get_type_triggers()` function
- [x] Add comprehensive inline documentation

### 1. `lua/kanban-md/column_type_resolver.lua` (NEW)

Core type resolution and property merging logic.

**Public API:**

```lua
local ColumnTypeResolver = {}

-- Resolve column type from all available sources
-- Returns: type_name (string or nil)
function ColumnTypeResolver.resolve_type(column_name, markdown_config, global_config)
  -- Priority chain:
  -- 1. Markdown explicit: markdown_config.type
  -- 2. Config named definition: global_config.column_config.definitions[column_name]
  -- 3. Config pattern matching: match column_name against types[*].patterns
  -- 4. Return nil if no match
end

-- Get type definition from global config
-- Returns: type_def table or nil
function ColumnTypeResolver.get_type_definition(type_name, global_config)
  -- Lookup: global_config.column_config.types[type_name]
end

-- Merge properties following priority: type < definition < markdown
-- Returns: merged config table
function ColumnTypeResolver.merge_properties(column_name, markdown_props, type_name, global_config)
  -- 1. Start with type definition properties (if type exists)
  -- 2. Merge config definition properties (if column_name in definitions)
  -- 3. Merge markdown properties (these override everything)
  -- Return merged result
end

-- Validate column has required properties
-- Emits warnings/errors based on global_config.missing_property_requirement
function ColumnTypeResolver.validate_requirements(column, global_config)
  -- Check type definition for requires_* properties
  -- Emit appropriate warnings/errors if missing
  -- Format: "Column 'In Progress' of type 'wip' requires wip_limit but none is set"
end

-- Extract trigger configuration from type definition
-- Returns: { on_entry = {...}, on_exit = {...}, ... }
function ColumnTypeResolver.get_type_triggers(type_def)
  -- Return type_def.triggers or {}
end

return ColumnTypeResolver
```

**Implementation Notes:**
- Pattern matching uses Lua `string.match()` with patterns from `types[*].patterns`
- First matching pattern wins
- All functions are pure (no side effects, no global state modification)

#### 2. `tests/unit/column_type_resolver_spec.lua` (NEW)
- [x] Create file
- [x] Test `resolve_type()` with all priority levels
- [x] Test `merge_properties()` with all combinations
- [x] Test `validate_requirements()` warning/error modes
- [x] Test `get_type_triggers()` function
- [x] Test edge cases (nil values, empty configs)

### 2. `tests/unit/column_type_resolver_spec.lua` (NEW)

Comprehensive unit tests for type resolution logic.

**Test Cases:**
- `resolve_type()`:
  - Explicit type in markdown takes priority
  - Named definition match
  - Pattern match (single pattern)
  - Pattern match (multiple patterns, first wins)
  - No match returns nil
  - Priority order verification
- `merge_properties()`:
  - Type properties only
  - Definition properties override type
  - Markdown properties override both
  - All three sources combined (markdown wins)
  - Empty configs handled gracefully
- `validate_requirements()`:
  - Warning emitted when required property missing
  - No warning when property present
  - Multiple required properties
  - Error level (if implementing config-driven severity)
- `get_type_triggers()`:
  - Returns trigger lists from type definition
  - Returns empty table if no triggers

#### 3. `tests/integration/column_type_spec.lua` (NEW)
- [x] Create file
- [x] Test end-to-end type resolution from markdown
- [x] Test trigger auto-registration from types
- [x] Test property inheritance and merging
- [x] Test backwards compatibility
- [x] Test error handling (missing triggers, missing properties)

### 3. `tests/integration/column_type_spec.lua` (NEW)

End-to-end tests for column type parsing and trigger registration.

**Test Cases:**
- Parse board with typed columns (via pattern matching)
- Parse board with explicit type in markdown
- Parse board with definition-based types
- Verify triggers auto-registered from type definition
- Verify property merging through full parse cycle
- Backwards compatibility: simple config still works
- Error when type trigger not found
- Warning when required property missing

### Files to Modify

#### 1. `lua/kanban-md/config.lua`
- [x] Add `column_config` structure to default config
- [x] Add `missing_property_requirement` option
- [x] Add `write_full_config_to_markdown` option
- [x] Document all config options with inline comments

## Files to Modify

### 1. `lua/kanban-md/config.lua`

**Status**: ✅ Complete - All config options added and documented

```lua
-- Column type system
column_config = {
  types = {
    -- Example structure (users populate this):
    -- completion = {
    --   properties = { is_completion_state = true },
    --   triggers = {
    --     on_entry = {
    --       { module = "kanban-md.triggers", function_name = "mark_complete", name = "mark_complete" }
    --     }
    --   },
    --   patterns = { "done", "complete", "finished" }
    -- }
  },
  definitions = {
    -- Example: ["Done"] = { type = "completion", wip_limit = 5 }
  }
},

-- Validation behavior
missing_property_requirement = "warning", -- none/warning/error

-- Writer config for future
write_full_config_to_markdown = false, -- when true, write resolved types back
```

#### 2. `lua/kanban-md/parser.lua`
- [x] Modify column config parsing to call resolver
- [x] Set `column.type` field after resolution
- [x] Merge properties using resolver
- [x] Support both `<!-- column:config -->` and `<!-- config -->` syntax

### 2. `lua/kanban-md/parser.lua`

**Status**: ✅ Complete - Parser integrated with resolver for type resolution and property merging

Current code:
```lua
elseif config_type == "column" and comment_buffer:match("config") then
  column.config = TypeConverter:new(parse_properties(config_content))
end
```

New code:
```lua
elseif config_type == "column" and comment_buffer:match("config") then
  -- Parse markdown properties
  local markdown_props = parse_properties(config_content)

  -- Get global config and resolver
  local global_config = require("kanban-md.config").get()
  local resolver = require("kanban-md.column_type_resolver")

  -- Resolve column type
  local column_type = resolver.resolve_type(column.name, markdown_props, global_config)

  -- Merge properties (type defaults < definition < markdown)
  local final_config = resolver.merge_properties(
    column.name,
    markdown_props,
    column_type,
    global_config
  )

  -- Set column type and config
  column.type = column_type
  column.config = TypeConverter:new(final_config)

  -- Note: Validation happens later during auto_register_triggers()
end
```

**Also support simplified syntax** - accept both:
- `<!-- column:config ... -->` (legacy, backwards compatible)
- `<!-- config ... -->` (new, cleaner since context is obvious)

Update patterns to match both (line 26 area):
```lua
-- Keep existing pattern but also match without "column:" prefix
comment_single = "<!%-%-%s*(.-)%s*%-%->",
```

#### 3. `lua/kanban-md/column.lua`
- [x] Add `type` field to `Column:new()` constructor
- [x] Update constructor documentation

### 3. `lua/kanban-md/column.lua`

**Status**: ✅ Complete - `type` field added to Column constructor

```lua
function Column:new(id, name)
  local obj = {
    id = id,
    name = name or id,
    type = nil,  -- NEW: resolved column type (string or nil)
    cards = {},
    config = TypeConverter:new({}),
    triggers = {},
    trigger_order = {}
  }
  -- ... rest unchanged
end
```

#### 4. `lua/kanban-md/board.lua`
- [x] Enhance `Board:auto_register_triggers()` to call `register_type_triggers()`
- [x] Add validation call for column requirements
- [x] Implement new `Board:register_type_triggers(column)` method
- [x] Add error handling for missing trigger registrations

### 4. `lua/kanban-md/board.lua`

**Status**: ✅ Complete - Type trigger registration and validation integrated

After the existing column loop, add type-based trigger registration:

```lua
function Board:auto_register_triggers()
  -- ... existing code (workflow, board triggers) ...

  -- Register column-level triggers
  for _, column in ipairs(self.columns) do
    -- Register basic validation triggers on all columns
    self:register_basic_triggers(column)

    -- NEW: Register type-based triggers
    if column.type then
      self:register_type_triggers(column)
    end

    -- Validate column requirements (NEW)
    local global_config = require('kanban-md.config').get()
    local resolver = require('kanban-md.column_type_resolver')
    resolver.validate_requirements(column, global_config)

    -- Register column-specific configured triggers
    if column.config and column.config.triggers then
      self:register_configured_triggers(column.config.triggers, column)
    end
  end
end
```

**Add new method** `Board:register_type_triggers(column)`:

```lua
function Board:register_type_triggers(column)
  -- Get global config and type definition
  local global_config = require('kanban-md.config').get()
  local resolver = require('kanban-md.column_type_resolver')
  local type_def = resolver.get_type_definition(column.type, global_config)

  if not type_def then
    return -- Type not found in config, skip (already validated)
  end

  -- Get trigger configuration from type
  local type_triggers = resolver.get_type_triggers(type_def)

  -- Register triggers for each event type
  for event_type, trigger_list in pairs(type_triggers) do
    if type(trigger_list) == "table" then
      for _, trigger_config in ipairs(trigger_list) do
        -- Use existing method to register trigger
        local success, err = pcall(function()
          self:register_trigger_from_config(event_type, trigger_config, column)
        end)

        if not success then
          -- Emit clear error message about missing trigger
          error(string.format(
            "Column type '%s' requires trigger '%s' but it could not be registered: %s. " ..
            "Check that the trigger module '%s' is loaded.",
            column.type,
            trigger_config.name or "unknown",
            err,
            trigger_config.module or "unknown"
          ))
        end
      end
    end
  end
end
```

#### 5. `lua/kanban-md/writer_mixin.lua`
- [x] Implement `write_full_config_to_markdown = true` support
- [x] Detect which properties came from markdown vs type
- [x] Write back explicit properties or all resolved properties (controlled by config flag)

### 5. `lua/kanban-md/writer_mixin.lua`

**Status**: ✅ Complete - Writer support fully implemented and tested

**Implementation** - when `write_full_config_to_markdown = true`:
- Selects resolved column.config for writing instead of authored markdown_config
- Preserves default behaviour (markdown_config only) when flag is false
- Supports both global and board-level config overrides
- Tested via column_config_layers_spec.lua (lines 151-192)

## Example Configurations

### User Config Example

```lua
require("kanban-md").setup({
  column_config = {
    types = {
      completion = {
        properties = {
          is_completion_state = true,
          auto_archive_days = 30
        },
        triggers = {
          on_entry = {
            {
              module = "kanban-md.triggers",
              function_name = "mark_complete",
              name = "mark_complete"
            },
            {
              module = "my_custom_triggers",
              function_name = "notify_team",
              name = "completion_notification"
            }
          }
        },
        patterns = { "done", "complete", "finished" }
      },
      wip = {
        properties = {
          is_active_state = true
        },
        requires_wip_limit = true, -- Validation requirement
      },
      blocked = {
        properties = {
          is_blocked_state = true
        },
        patterns = { "blocked", "waiting", "parked" }
      },
      archive = {
        properties = {
          is_archive_state = true
        },
        patterns = { "__ARCHIVE__" }
      }
    },
    definitions = {
      -- Explicit column name mappings (override patterns)
      ["Done"] = { type = "completion" },
      ["Completed"] = { type = "completion", wip_limit = 10 },
      ["Archive"] = { type = "archive" },
      ["Blocked Tasks"] = { type = "blocked", wip_limit = 5 }
    }
  },
  missing_property_requirement = "warning", -- or "error" or "none"
  write_full_config_to_markdown = false
})
```

### Markdown Examples

**Example 1: Simple config (backwards compatible)**
```markdown
## In Progress
<!-- config wip_limit: 3 -->
- [ ] Task 1
```
Result: `type = nil`, `wip_limit = 3`

**Example 2: Pattern-based type resolution**
```markdown
## Done
<!-- config wip_limit: 5 -->
- [x] Completed task
```
Result: `type = "completion"` (matched pattern "done"), `wip_limit = 5`, `is_completion_state = true`

**Example 3: Explicit type**
```markdown
## My Custom Column
<!-- config type: wip, wip_limit: 3 -->
- [ ] Active task
```
Result: `type = "wip"`, `wip_limit = 3`, `is_active_state = true`

**Example 4: Definition-based**
```markdown
## Done
- [x] Task
```
Result: `type = "completion"` (from definitions), inherits all type properties

**Example 5: Property override**
```markdown
## Completed
<!-- config auto_archive_days: 7 -->
```
Result: `type = "completion"` (from definitions), `wip_limit = 10` (from definition), `auto_archive_days = 7` (markdown wins over type default of 30)

## Resolution Priority Examples

**Scenario 1: All sources conflict**
- Type `completion` has: `auto_archive_days: 30`
- Definition `["Done"]` has: `type: "completion", auto_archive_days: 14`
- Markdown has: `<!-- config auto_archive_days: 7 -->`
- **Result**: `auto_archive_days = 7` (markdown wins)

**Scenario 2: Type from pattern, property from markdown**
- Column name: "Finished Tasks"
- Type `completion` has pattern: "finished"
- Markdown: `<!-- config wip_limit: 5 -->`
- **Result**: `type = "completion"`, `wip_limit = 5`, `is_completion_state = true`

**Scenario 3: Definition overrides pattern**
- Column name: "Done"
- Type `completion` has pattern: "done"
- Definition: `["Done"] = { type: "wip" }`
- **Result**: `type = "wip"` (definition takes priority over pattern)

## Implementation Order

### Phase 1: Foundation (Tests First)
- [x] 1. Write unit tests for `column_type_resolver.lua` ✅
  - [x] Test `resolve_type()` priority chain
  - [x] Test `merge_properties()` combinations
  - [x] Test `validate_requirements()` modes
  - [x] Test `get_type_triggers()`

- [x] 2. Write integration tests for end-to-end flow ✅
  - [x] Test type resolution from markdown
  - [x] Test trigger auto-registration
  - [x] Test backwards compatibility
  - [x] Test error scenarios

### Phase 2: Core Implementation
- [x] 3. Add config schema to `lua/kanban-md/config.lua` ✅
  - [x] Add `column_config` structure
  - [x] Add `missing_property_requirement`
  - [x] Add `write_full_config_to_markdown`
  - [x] Document all options with inline comments

- [x] 4. Create `lua/kanban-md/column_type_resolver.lua` ✅
  - [x] Implement `resolve_type()`
  - [x] Implement `get_type_definition()`
  - [x] Implement `merge_properties()`
  - [x] Implement `validate_requirements()`
  - [x] Implement `get_type_triggers()`
  - [x] Add comprehensive documentation

### Phase 3: Integration
- [x] 5. Update `lua/kanban-md/column.lua` ✅
  - [x] Add `type` field to constructor

- [x] 6. Update existing tests for type field ✅
  - [x] Add `type` expectations where needed
  - [x] Ensure backwards compatibility

- [x] 7. Integrate resolver into `lua/kanban-md/parser.lua` ✅
  - [x] Call resolver during column config parsing
  - [x] Set `column.type` field
  - [x] Merge properties using resolver

- [x] 8. Enhance `lua/kanban-md/board.lua` ✅
  - [x] Add `Board:register_type_triggers(column)` method
  - [x] Integrate into `Board:auto_register_triggers()`
  - [x] Add requirement validation call
  - [x] Add error handling for missing triggers

- [x] 9. Implement `write_full_config_to_markdown = true` in writer ✅
  - [x] Detect property sources (markdown_config vs resolved config)
  - [x] Select appropriate config layer based on flag
  - [x] Support global and board-level config overrides
  - [x] Tested via column_config_layers_spec.lua

### Phase 4: Future Enhancements
- [ ] 10. (Future) Type inheritance
  - [ ] Support `type_parent` field for type definitions
  - [ ] Merge properties through inheritance chain

- [ ] 11. (Future) Computed properties
  - [ ] Allow property values to be functions
  - [ ] Evaluate at resolution time

- [ ] 12. (Future) Transition validation
  - [ ] Restrict card movement between column types
  - [ ] Define allowed source/target type pairs

- [ ] 13. (Future) UI indicators
  - [ ] Virtual text showing column type
  - [ ] Highlight columns by type in editor



## Error Handling

### Missing Trigger Function
```
Error: Column type 'wip' requires trigger 'mark_complete' but it could not be registered:
module not found 'kanban-md.triggers'. Check that the trigger module 'kanban-md.triggers' is loaded.
```
- **When**: During `Board:auto_register_triggers()`
- **Action**: Halt with error (fail early)

### Missing Required Property
```
Warning: Column 'In Progress' of type 'wip' requires wip_limit but none is set
```
- **When**: During validation in `auto_register_triggers()`
- **Action**: Emit warning (configurable to error or none)

### Invalid Type Reference
```
Warning: Column 'Done' references type 'unknown_type' which is not defined in config
```
- **When**: During type resolution
- **Action**: Continue with `type = nil`, log warning

### Pattern Matching Failure
- **When**: No pattern matches and no definition found
- **Action**: Silent, `type = nil` (this is normal/expected)

## Backwards Compatibility

All existing boards continue to work:
- `<!-- column:config wip_limit: 3 -->` still works (treated as unnamed type)
- Columns without config still work (type = nil)
- Simple property-based configs work unchanged
- New `type` field is optional everywhere

## Future Enhancements

### Phase 4a: Type Inheritance
- Allow types to inherit from other types: `type_parent: "base_wip"`
- Merge properties through inheritance chain
- Enables DRY configurations for related column types

### Phase 4b: Computed Properties
- Allow property values to be functions: `wip_limit: function(column) return #column.cards * 2 end`
- Evaluate computed properties at resolution time
- Enables dynamic, context-aware column configuration

### Phase 4c: Transition Validation
- Validate type transitions: "cards can only move from wip → completion"
- Define allowed source/target types per type (e.g., `allowed_sources: { "wip", "blocked" }`)
- Enables workflow enforcement via the type system

### Phase 4d: UI Indicators
- Virtual text showing column type: `## Done [completion]`
- Highlight columns by type in UI
- Supports Neovim and web-based interfaces
