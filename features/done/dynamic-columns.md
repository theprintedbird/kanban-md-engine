### Dynamic Columns Implementation Summary

#### Status: SUBSTANTIALLY COMPLETE ✅

This document describes the original plan and design for transforming kanban-md from a hardcoded column system to a fully dynamic, trigger-based architecture. **Most of this work is now complete.**

For future work and remaining features, see `features/roadmap.md`.

#### Original Problem (Now Resolved)

The original implementation had several hardcoded assumptions:
- Fixed `column_flow` in actions.lua → **RESOLVED**: Dynamic column ordering implemented
- Hardcoded "Done" column detection for completion → **RESOLVED**: `is_completion_column()` helper with explicit/positional detection
- Rigid timestamp property names → **RESOLVED**: Dynamic property system with configurable timestamp triggers
- Limited extensibility for custom workflows → **RESOLVED**: Full trigger system with workflow engine

#### Solution Architecture: Trigger-Based Column System

##### Foundation Principle

**Column behaviours are defined by triggers, not types.** Any column can exhibit any behaviour by composing the appropriate triggers.

##### Trigger Categories

1. **Entry Triggers** (`on_entry`)
   - Execute when a task enters a column
   - Examples: `add_timestamp`, `mark_complete`, `assign_to_next`, `validate_requirements`

2. **Exit Triggers** (`on_exit`)
   - Execute when a task leaves a column
   - Examples: `add_exit_timestamp`, `check_dependencies`, `prevent_unless_archiving`

3. **Stay Triggers** (`on_stay`)
   - Execute continuously while task remains in column
   - Examples: `calculate_duration`, `check_sla`, `auto_escalate`

4. **Transition Triggers** (`on_transition`)
   - Execute during specific column-to-column movements
   - Can override general triggers for specific paths

##### Column Definition Example

```markdown
#### Review
<!-- column:config
triggers: {
  on_entry: ["add_timestamp", "assign_reviewer", "notify_team"],
  on_exit: ["validate_review_complete", "add_exit_timestamp"],
  on_stay: ["check_review_sla"]
}
properties: {
  wip_limit: 3,
  sla_hours: 24,
  requires: ["description", "test_plan"]
}
-->
```

#### Implementation Phases

##### Phase 0: Foundation Cleanup ✅ COMPLETED
- ✅ Dynamic column ordering (replaced hardcoded column_flow)
- ✅ Basic test infrastructure

##### Phase 1: Remove Hardcoded Dependencies ✅ COMPLETE
**Status: 95% Complete - Minor cleanup needed in extras/**

###### 1.1 Dynamic Completion Detection ✅
- Implemented `is_completion_column()` in `lua/kanban-md/helpers/column.lua`
- Uses explicit property check: `column.properties.is_completion_state`
- Fallback to position-based detection: last regular column
- All core code updated to use helper function

###### 1.2 Property Name Independence ✅
- Dynamic property iteration implemented
- Timestamp triggers handle column transitions automatically
- Stats calculation uses `is_completion_column()` helper

**Completed Updates:**
- `lua/kanban-md/writer_mixin.lua` - Uses dynamic completion detection
- `lua/kanban-md/commands.lua` - Uses `is_completion_column()` helper
- `lua/kanban-md/stats.lua` - Uses `is_completion_column()` helper
- `lua/kanban-md/parser_mixin.lua` - No hardcoded completion logic

**Remaining Cleanup:**
- `lua/kanban-md/extras/capacity_triggers.lua` - Still has hardcoded "Done" references
- `lua/kanban-md/extras/workflow_triggers.lua` - Still has hardcoded "Done" references

##### Phase 2: Core Trigger System ✅ COMPLETE
**Status: 100% Complete - Production Ready**

###### 2.1 Trigger Infrastructure ✅
Fully implemented in `lua/kanban-md/triggerable.lua`:
- **Trigger Types**: `on_entry`, `on_exit`, `on_stay`, `on_checking`, `on_create`
- **Execution Engine**: Ordered trigger execution with result aggregation
- **Result System**: `success()`, `error()`, `warning()`, `merge()` factories
- **Metadata Support**: Triggers can be marked with metadata (e.g., `bypassable = true`)
- **Bypass Mechanism**: Selective trigger skipping by category (used for force complete)

###### 2.2 Integration Points ✅
- `lua/kanban-md/column.lua` implements Triggerable mixin
- `add_card()` executes checking + entry triggers with atomic copy-and-commit pattern
- `remove_card()` executes checking + exit triggers
- `lua/kanban-md/board.lua` provides `move_card()` and `move_card_with_bypass()`
- Context propagation supports bypass categories

###### 2.3 Standard Triggers ✅
Implemented in `lua/kanban-md/triggers.lua`:
- Timestamp triggers (auto-set timestamps on column entry)
- WIP limit validation triggers
- Assignment triggers
- Default complexity triggers

##### Phase 3: Workflow Graph System ✅ MOSTLY COMPLETE
**Status: 90% Complete - Auto-move feature not implemented**

###### 3.1 Workflow Definition ✅
Implemented in `lua/kanban-md/workflow_engine.lua`:

```markdown
### Complex Board
<!-- kanban:config
workflow: {
  "Backlog": {
    "Ready": { when: "has_requirements == true" },
    "Blocked": { when: "missing_info == true" }
  },
  "Ready": ["In Progress"],
  "In Progress": {
    "Review": { when: "tests_passed == true" },
    "Blocked": { when: "blocker != nil" },
    "QA": { when: "needs_testing == true", auto: true }
  },
  "Review": {
    "Done": { when: "approved == true", auto: true },
    "In Progress": { when: "changes_requested == true", auto: true }
  },
  "Done": ["__ARCHIVE__"]
}
-->
```

###### 3.2 Workflow Validation ✅
Implemented functions in `lua/kanban-md/workflow_engine.lua`:
- `get_valid_transitions_static()` - Returns array of valid target columns
- `evaluate_condition_static()` - Parses and evaluates property conditions
- Supports simple array transitions: `["Ready"] = ["In Progress", "Blocked"]`
- Supports conditional transitions: `{ when: "property == value" }`
- Integrated with `board:validate_move()` for transition checking

**Example Working Code:**
```lua
-- In workflow_engine.lua (lines 50-110)
function M.get_valid_transitions_static(workflow, source_column_name, card)
  if not workflow then
    return nil  -- No restrictions
  end

  local transitions = workflow[source_column_name]
  if not transitions then
    return nil  -- No restrictions for this column
  end

  -- Handle simple array
  if type(transitions) == "table" and #transitions > 0 then
    return transitions
  end

  -- Handle conditional transitions
  local valid = {}
  for target, config in pairs(transitions) do
    if type(config) == "table" and config.when then
      if M.evaluate_condition_static(config.when, card) then
        table.insert(valid, target)
      end
    else
      table.insert(valid, target)
    end
  end

  return valid
end
```

**Board Integration:**
- `board:validate_move()` uses workflow engine (board.lua lines 119-175)
- `lua/kanban-md/extras/workflow_triggers.lua` registers workflow rules as triggers

**Not Yet Implemented:**
- ❌ Auto-move feature (`auto: true` in transitions) - cards don't automatically move when conditions are met

##### Phase 4: Advanced Features 🟡 PARTIALLY COMPLETE
**Status: 60% Complete - Dependencies/subtasks done, swim lanes not implemented**

###### 4.1 Swim Lanes ❌ NOT IMPLEMENTED

Original design for swim lanes:
```markdown
#### Frontend:Ready
<!-- column:config
swimlane: Frontend
triggers: {
  on_entry: ["assign_to_frontend_team"]
}
-->
```
Status: Parser does not support swimlane grouping. See `features/roadmap.md` for future plans.

###### 4.2 Dependencies and Sub-tasks ✅✅ FULLY IMPLEMENTED

**Implemented in `lua/kanban-md/extras/subtasks_triggers.lua`:**
- `create_subtask_trigger()` - Validates parent cards can't complete until subtasks are done
- `create_dependency_trigger()` - Validates dependencies must complete first
- Both support "strict" (block) and "warn" (allow with warning) enforcement modes
- Registered as `on_checking` triggers
- Support bypass via metadata: `{bypassable = true, category = "subtask"|"dependency"}`

**Configuration Options:**
```lua
require('kanban-md').setup({
  subtask_validation = "strict",  -- or "warn" or false
  dependency_validation = "strict" -- or "warn" or false
})
```

**Property Types:**
```markdown
<!--
id: task-123
depends_on: [task-456, task-789]
subtasks: [subtask-1, subtask-2]
-->
```

**Commands:**
- `:KanbanAddDependency` - Add dependency to current card
- `:KanbanForceCompleteCard` - Bypass dependency/subtask checks

**Board Validation:**
- `board:validate_dependencies()` checks for missing/circular dependencies

###### 4.3 Capacity Planning ✅ FOUNDATION IMPLEMENTED

**Implemented in `lua/kanban-md/extras/capacity_triggers.lua`:**
- Point-based capacity (`create_capacity_points_trigger()`)
- Reviewer capacity (`create_reviewer_capacity_trigger()`)
- Velocity capacity (`create_velocity_capacity_trigger()`)
- Skill-based capacity (`create_skill_capacity_trigger()`)

**Example Configuration:**
```markdown
<!-- column:config
wip_limit: 5
capacity_points: 20
required_skills: ["frontend", "testing"]
-->
```

**Known Issues:**
- ⚠️ Still contains hardcoded "Done" references (needs cleanup)
- See `features/roadmap.md` for enhancement plans


#### Testing Strategy

##### Unit Tests

```lua
describe("trigger system", function()
  it("should execute entry triggers when task enters column", function()
    local fired = false
    triggers.register_trigger("test_trigger", function()
      fired = true
    end)
    
    local column = {
      triggers = { on_entry = {"test_trigger"} }
    }
    
    -- Move task to column
    actions.move_task_to_column(task, column)
    assert.is_true(fired)
  end)
  
  it("should respect workflow constraints", function()
    local board = {
      config = {
        workflow = {
          ["Ready"] = ["In Progress"],
          ["In Progress"] = ["Review", "Blocked"]
        }
      }
    }
    
    local valid = actions.get_valid_transitions(board, task, {name = "Ready"})
    assert.are.same({"In Progress"}, valid)
  end)
end)
```

##### Integration Tests

- Test complex workflows with conditional transitions
- Verify trigger chains work correctly
- Ensure backwards compatibility with simple boards

#### Configuration Simplification

##### Rule-Based Configuration

Instead of numerous specific options, use a general rule system:

```lua
-- kanban-md/config.lua
config = {
  rules = {
    {
      name = "auto_archive",
      trigger = "daily",
      condition = function(task)
        return task.properties.done and 
               (os.time() - task.properties.done) > (30 * 86400)
      end,
      action = "archive_task"
    },
    {
      name = "wip_limit_warning",
      trigger = "on_entry",
      condition = function(task, column)
        return column.properties.wip_limit and 
               #column.tasks >= column.properties.wip_limit
      end,
      action = "notify",
      params = { level = "WARN", message = "WIP limit exceeded" }
    }
  }
}
```

#### Implementation Checklist - UPDATED STATUS

##### Immediate (This Week) ✅ ALL COMPLETE
- [X] Implement `is_completion_column()` function
- [X] Replace all hardcoded "Done" references (95% - extras need cleanup)
- [X] Add basic trigger infrastructure
- [X] Update tests for dynamic completion detection

##### Short-term (Next Month) ✅ MOSTLY COMPLETE
- [X] Complete trigger system with all event types
- [X] Implement workflow graph validation
- [X] Add conditional transitions
- [X] Update documentation (ongoing)

##### Long-term (Future) 🟡 PARTIALLY COMPLETE
- [ ] Swim lanes support (not started - see roadmap.md)
- [X] Dependencies: Tasks that block other tasks
- [X] Sub-tasks: Tasks that must complete before parent can move
- [X] Capacity planning: Different columns could have different WIP limits or capacity calculations
- [ ] Visual workflow representation (not started)
- [X] Custom user triggers (via triggerable.lua)
- [ ] Time-based transitions: Auto-move after time limit (not started - see roadmap.md)

#### Success Metrics

1. **Flexibility**: Any board structure works without code changes
2. **Backwards Compatible**: Existing boards continue to work
3. **Extensible**: Users can add custom triggers without modifying core
4. **Testable**: All behaviours have comprehensive test coverage
5. **Performant**: Trigger execution doesn't slow down normal operations

#### Risk Mitigation

| Risk											| Mitigation																								|
|---------------------------|-----------------------------------------------------------|
| Complex configuration			| Sensible defaults, progressive disclosure of features			|
| Performance impact				| Lazy trigger loading, caching of workflow paths						|
| User confusion						| Clear documentation, example boards												|

#### Remaining Work

See `features/roadmap.md` for detailed plans on:
1. **Cleanup**: Remove hardcoded "Done" from extras/ modules
2. **Auto-move**: Implement automatic card transitions based on conditions
3. **Swim lanes**: Parser support for column grouping by swim lane
4. **Time-based transitions**: Auto-move cards after time limits
5. **Visual workflow**: Graphical representation of workflow graphs

#### Notes

- The trigger system is inspired by event-driven architectures and provides maximum flexibility
- Column "types" become emergent behaviour from trigger composition
- This approach scales from simple linear boards to complex enterprise workflows
- The system remains intuitive for basic use whilst enabling power users

## TODO

  Option 5: Hybrid Fallback Chain ⭐ RECOMMENDED

  Combine multiple approaches with clear priority:

  column_config = {
    -- Explicit named column definitions (highest priority after markdown)
    definitions = {
      ["Done"] = { is_completion_state = true },
      ["Archive"] = { is_completion_state = true, is_archive = true }
    },

    -- Pattern-based templates (medium priority)
    patterns = {
      { pattern = "^done$", case_insensitive = true, properties = { is_completion_state = true } },
      { pattern = "complete", properties = { is_completion_state = true } },
      { pattern = "blocked", properties = { is_blocked_state = true } }
    },

    -- Position-based defaults (lowest priority)
    positional = {
      last_regular = { is_completion_state = true },
      first_regular = { is_start_state = true }
    }
  }

  Priority Chain:
  1. Explicit markdown property (<!-- column:config is_completion_state: true -->)
  2. Completion triggers present (mark_complete in on_entry)
  3. Config named definitions
  4. Config pattern matching (first match)
  5. Config positional defaults
  6. Hardcoded fallback (current behavior)

  Pros:
  - Best of all worlds - explicit when needed, smart defaults when not
  - Backwards compatible - existing behavior is lowest priority
  - Progressive enhancement - users can add config as needed
  - Flexible for different board complexity levels
  - Removes hardcoded patterns to config

  Cons:
  - Most complex to understand
  - Priority order must be well-documented
  - Debugging could be harder (which rule applied?)
  - More code to maintain

  Implementation:
  - Checker.lua uses chain to resolve properties
  - Each level checked in order until match found
  - Add logging/debug mode to show which rule applied

  ---
  Additional Column Properties to Consider

  Beyond is_completion_state, other properties that could benefit:

  -- Semantic state flags
  is_completion_state = true/false
  is_start_state = true/false
  is_active_state = true/false
  is_blocked_state = true/false
  is_review_state = true/false
  is_archive = true/false

  -- Workflow properties
  requires_assignee = true/false
  requires_estimation = true/false
  auto_archive_after_days = number
  transition_rules = { allowed_from = {}, allowed_to = {} }

  -- Capacity properties
  default_wip_limit = number
  warn_on_wip_exceeded = true/false

  -- Display properties
  colour = "string"
  icon = "string"
  hide_in_stats = true/false

  ---
  Recommendation

  Implement Option 5 (Hybrid Fallback Chain) because:

  1. Solves the immediate problem - moves hardcoded patterns to config
  2. Enables gradual adoption - users can start simple, add config as needed
  3. Backwards compatible - existing behavior preserved as final fallback
  4. Extensible - easy to add new property types
  5. Clear semantics - priority chain is understandable

  The implementation would update:
  - config.lua - add column_config section
  - checker.lua - replace hardcoded patterns with config lookups
  - parser.lua - apply config during column creation
  - Documentation - explain priority chain

  Option 2: Column Type System

  Introduce a formal "type" concept for columns:

  column_types = {
    completion = {
      properties = { is_completion_state = true },
      triggers = { on_entry = { "mark_complete", "archive_after_days" } },
      patterns = { "done", "complete", "finished" }
    },
    wip = {
      properties = { is_active_state = true },
      requires_wip_limit = true,
      patterns = { "progress", "doing", "active" }
    },
    blocked = {
      properties = { is_blocked_state = true },
      patterns = { "blocked", "waiting" }
    }
  }

  Pros:
  - Semantic meaning - types represent workflow stages
  - Bundles properties, triggers, and validation together
  - Extensible - add new types without changing code
  - Self-documenting - types explain column purpose

  Cons:
  - More complex mental model
  - Requires type resolution logic
  - May be overkill for simple boards
  - Could conflict with user's own column naming

  Implementation:
  - Column gets type field during parsing
  - Type determines default properties, triggers, behavior
  - Type inference from patterns or explicit markdown declaration

