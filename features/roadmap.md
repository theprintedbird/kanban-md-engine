# Kanban-MD Feature Roadmap

This document outlines planned features and improvements for the kanban-md plugin. For completed work, see `features/dynamic-columns.md`.

## Current State Summary

The kanban-md plugin has achieved its core architectural goals:

✅ **Fully dynamic, trigger-based column system**
- Columns defined by triggers, not hardcoded types
- Complete trigger infrastructure (`on_entry`, `on_exit`, `on_stay`, `on_checking`, `on_create`)
- Selective bypass mechanism for override commands

✅ **Workflow validation system**
- Conditional transitions with property evaluation
- Simple and complex workflow definitions via markdown
- Integration with trigger system

✅ **Advanced task relationships**
- Dependencies validation (strict/warn modes)
- Subtask validation (strict/warn modes)
- Force complete override with selective bypass

✅ **Capacity planning foundation**
- Point-based capacity triggers
- Reviewer/skill-based capacity
- Velocity tracking

✅ **Column type system**
- Type resolution via markdown → definitions → patterns
- Property merging with three-layer priority system
- Validation for `requires_*` properties
- Trigger auto-registration from type definitions
- Full integration with parser and board lifecycle

## Short-Term Improvements

### 1. Code Cleanup (Priority: HIGH)

✅ **COMPLETED** - All hardcoded "Done" references have been removed

**Verification**:
- ✅ `lua/kanban-md/extras/capacity_triggers.lua` - Uses `column_helper.is_completion_column()` (lines 68, 75, 132)
- ✅ `lua/kanban-md/extras/workflow_triggers.lua` - No hardcoded "Done" references found
- ✅ All extras modules use dynamic column detection

**Status**: Full consistency with dynamic column system achieved

### 2. Auto-Move Feature (Priority: MEDIUM)

**Current State**: Workflow engine validates conditional transitions but doesn't auto-move cards

**Desired Behavior**:
```markdown
<!-- kanban:config
workflow: {
  "Review": {
    "Done": { when: "approved == true", auto: true },
    "In Progress": { when: "changes_requested == true", auto: true }
  }
}
-->
```

When a card's properties change to satisfy a condition with `auto: true`, the card should automatically move to the target column.

**Implementation Requirements**:
1. Property change detection/hooks
2. Queue system for automatic movements
3. Execution during save or on-demand trigger
4. Safety checks to prevent infinite loops
5. User notification of auto-moves

**Challenges**:
- When to evaluate? (On save, on property change, periodic?)
- How to handle multiple matching conditions?
- How to prevent infinite loops in circular workflows?
- How to notify users of automatic movements?

**Implementation Plan**:
```lua
-- New module: lua/kanban-md/auto_move.lua
M.queue_auto_move = function(card, target_column, reason)
  -- Queue card for automatic movement
end

M.process_auto_moves = function(board)
  -- Process all queued movements
  -- Check for loops
  -- Apply moves
  -- Return results
end

-- Hook into board:write() or create :KanbanProcessAutoMoves command
```

## Medium-Term Features

### 3. Time-Based Transitions (Priority: MEDIUM)

**Goal**: Automatically move cards after time limits or on schedules

**Use Cases**:
- Auto-archive completed cards after 30 days
- Escalate blocked cards after 3 days
- Move "Ready" to "In Progress" at sprint start
- Auto-complete time-boxed tasks

**Configuration Examples**:
```markdown
<!-- column:config
auto_transitions: {
  after_days: 30,
  target: "__ARCHIVE__",
  condition: "done != nil"
}
-->
```

Or via triggers:
```lua
column:register_on_stay("auto_archive", function(card, column, board)
  if card.properties.done then
    local age_days = (os.time() - card.properties.done) / 86400
    if age_days > 30 then
      return {
        auto_move = "__ARCHIVE__",
        reason = "Auto-archived after 30 days"
      }
    end
  end
end)
```

**Implementation Requirements**:
1. Background/periodic evaluation mechanism
2. Time-based trigger type (`on_timer`?)
3. Integration with auto-move queue
4. User control over when evaluation occurs

**Challenges**:
- Neovim doesn't have built-in cron/scheduling
- Need user to trigger evaluation (on open, on save, or manual command)
- Performance with large boards

### 4. Enhanced Column Properties (Priority: LOW)

**Goal**: Add useful column properties beyond the currently implemented ones

**Current State**:
- ✅ **Column Type System fully implemented** (`column_type_resolver.lua`)
  - Type resolution via markdown → definitions → patterns
  - Property merging with correct priority
  - Validation for `requires_*` properties already exists
- ✅ **Parser already recognises arbitrary properties** - no changes needed
- ✅ **Already implemented properties**:
  - `is_completion_state` - marks completion columns
  - `wip_limit` - enforces WIP limits
  - `is_active_state` - defined but not actively used

- ✅ **Semantic state flags** (IMPLEMENTED):
  - `is_start_state` - marks when active work begins (cycle time start)
  - `is_backlog_state` - marks backlog columns (lead time start)
  - `is_blocked_state` - marks blocked/on-hold states (tracked in blocked time)
  - `is_waiting_state` - marks waiting states (tracked in blocked time)
  - All flags support 3-tier detection: explicit → config default → position-based
  - Used by `helpers/column.lua` for state detection
  - Used by `stats.lua` for lead time, cycle time, and blocked time calculations
  - Displayed in `virtual_text.lua` with column names and time breakdowns

**Proposed Additional Properties**:
```lua
-- Semantic state flags (remaining, not implemented)
is_review_state = true/false
is_archive = true/false

-- Workflow properties (not implemented)
requires_assignee = true/false      -- Uses existing requires_* validation
requires_estimation = true/false     -- Uses existing requires_* validation
auto_archive_after_days = number
allowed_from = {"column1", "column2"}  -- Restrict entry sources
allowed_to = {"column3", "column4"}    -- Restrict exit targets

-- Display properties (not implemented)
colour = "string"
icon = "string"
hide_in_stats = true/false
virtual_text_template = "string"
```

**Implementation**:
- ~~Extend parser to recognise new properties~~ - Parser already handles arbitrary properties
- ~~Add validation triggers for `requires_*` properties~~ - Already implemented in `column_type_resolver.lua:155-203`
- ✅ **Semantic state flags implemented** - `is_start_state`, `is_backlog_state`, `is_blocked_state`, `is_waiting_state`
- ✅ **Column helper functions** - `helpers/column.lua` with 3-tier fallback detection
- ✅ **Metrics calculation** - Lead time, cycle time, blocked time in `stats.lua`
- ✅ **Virtual text display** - Rich display showing column names and time breakdowns
- ✅ **Configuration options** - `show_lead_time`, `show_cycle_time`, `default_start_column`, `default_backlog_column`
- ✅ **Documentation** - CLAUDE.md updated with semantic states and metrics sections
- Remaining: Add column type definitions to config with new properties
- Remaining: Write code for display properties (colour, icon, virtual_text_template)
- Remaining: Update user guide

### 5. Rule-Based Configuration System (Priority: LOW)

**Goal**: Simplify configuration by using general rule system instead of many specific options

**Current State**: Many specific config options (auto_timestamp, auto_archive, wip_limit, etc.)

**Proposed Approach**:
```lua
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
    },
    {
      name = "require_estimation",
      trigger = "on_entry",
      target_columns = {"In Progress"},
      condition = function(task)
        return not task.properties.complexity
      end,
      action = "block",
      message = "Tasks must have complexity estimate before starting"
    }
  }
}
```

**Benefits**:
- Unified mental model
- Easy to add custom rules without code changes
- Self-documenting
- More powerful than individual boolean flags

**Challenges**:
- More complex for simple use cases
- Requires good documentation and examples
- Backwards compatibility with current config

**Implementation Plan**:
1. Keep current config options as defaults
2. Add rule system as optional enhancement
3. Rules override default behaviors
4. Provide rule library for common patterns

## Long-Term Vision

### 6. Swim Lanes (Priority: MEDIUM)

**Goal**: Support parallel workflows with column grouping

**Use Cases**:
- Separate "Frontend" and "Backend" tracks
- Team-based lanes (Team A, Team B)
- Priority lanes (Urgent, Normal, Low)
- Project-based lanes

**Markdown Syntax**:
```markdown
###### Frontend:Backlog
<!-- column:config
swimlane: Frontend
triggers: {
  on_entry: ["assign_to_frontend_team"]
}
-->

###### Frontend:In Progress
<!-- column:config
swimlane: Frontend
wip_limit: 3
-->

###### Backend:Backlog
<!-- column:config
swimlane: Backend
-->

###### Backend:In Progress
<!-- column:config
swimlane: Backend
wip_limit: 2
-->
```

**Parser Changes Required**:
- Recognize `swimlane:column` naming convention or explicit `swimlane` property
- Group columns by swim lane
- Maintain order within each lane
- Support cross-lane movements

**Data Structure**:
```lua
board = {
  swimlanes = {
    {
      name = "Frontend",
      columns = {column1, column2, ...}
    },
    {
      name = "Backend",
      columns = {column3, column4, ...}
    }
  },
  -- Or keep flat columns array and add swimlane property
  columns = {
    {name = "Backlog", swimlane = "Frontend"},
    {name = "In Progress", swimlane = "Frontend"},
    {name = "Backlog", swimlane = "Backend"},
    ...
  }
}
```

**UI Considerations**:
- How to display in plain text markdown?
- Stats per swim lane or aggregate?
- Virtual text display for swim lane info?

**Challenges**:
- Column naming conflicts (multiple "In Progress" columns)
- Stats calculation across lanes
- Workflow transitions between lanes
- Backwards compatibility with flat structure

### 7. Visual Workflow Representation (Priority: LOW)

**Goal**: Generate graphical representation of workflow graphs

**Output Formats**:
- ASCII art in buffer
- Mermaid diagram
- DOT/Graphviz format
- HTML visualization

**Example Output**:
```
Backlog ──→ Ready ──→ In Progress ──┬──→ Review ──→ Done
                          ↓         │       ↓
                      Blocked ←─────┘    Archive
```

**Command**:
```vim
:KanbanShowWorkflow
```

**Implementation**:
- Parse workflow config
- Generate graph structure
- Render to chosen format
- Display in split or floating window

**Use Cases**:
- Onboarding new team members
- Documentation generation
- Workflow design and validation
- Identifying bottlenecks

### 8. Capacity Planning Enhancements (Priority: LOW)

**Current State**: Basic capacity triggers exist but need refinement

**Improvements Needed**:
1. Remove hardcoded "Done" references
2. Better allocation strategies
3. Team member assignment automation
4. Velocity forecasting
5. Burndown/burnup chart data

**Enhanced Configuration**:
```markdown
<!-- column:config
capacity: {
  max_points: 20,
  max_tasks: 5,
  team_members: ["alice", "bob", "charlie"],
  allocation_strategy: "round_robin",  -- or "least_busy", "skill_match"
  required_skills: ["frontend", "testing"],
  optional_skills: ["design"]
}
-->
```

**New Triggers**:
- Auto-assign based on workload
- Warning when team member overallocated
- Skill matching for assignments
- Velocity tracking per team member

**Stats Integration**:
- Show capacity utilization in `:KanbanStats`
- Per-column capacity reports
- Team member workload summaries

## Open Design Questions

### Hybrid Fallback Chain for Column Properties

**Status**: ✅ **PARTIALLY IMPLEMENTED** - Simpler version in use

**Current Implementation** (see `helpers/column.lua:6-34` and `column_type_resolver.lua`):

**For completion detection**:
1. ✅ Explicit markdown property (`<!-- column:config is_completion_state: true -->`)
2. ✅ Position-based fallback (last regular column, if multiple columns exist)

**For general column properties**:
1. ✅ Explicit markdown property (`<!-- column:config wip_limit: 3 -->`)
2. ✅ Config named definitions (`column_config.definitions["Done"]`)
3. ✅ Config pattern matching (`column_config.types.completion.patterns = { "done" }`)
4. ✅ Type default properties (`column_config.types.completion.properties`)

**NOT Implemented**:
- ❌ Trigger-based detection (e.g., `mark_complete` in `on_entry` → is_completion_state)
- ❌ Hardcoded pattern fallbacks (intentionally avoided - no hardcoded "Done" references)

**Decision**: Current implementation strikes good balance:
- Simpler than full 6-level chain
- Still flexible via type system
- Well-documented priority order
- No hardcoded patterns per architectural goals

**Remaining Work**:
- None needed - current system is sufficient
- Trigger-based detection could be added if use case emerges

### Column Type System

**Status**: ✅ **IMPLEMENTED** - This system is fully functional as of current codebase.

**Implementation**: See `lua/kanban-md/column_type_resolver.lua` and `config.lua:306-378`

**How it works**:
```lua
-- In user config or global defaults
column_config = {
  types = {
    completion = {
      properties = { is_completion_state = true },
      triggers = { on_entry = { "mark_complete" } },
      patterns = { "done", "complete", "finished" }
    },
    wip = {
      properties = { is_active_state = true },
      requires_wip_limit = true,
      patterns = { "progress", "doing", "active" }
    }
  },
  definitions = {
    ["Done"] = { type = "completion", wip_limit = 5 }
  }
}
```

**Type Resolution Priority** (implemented):
1. Markdown explicit: `<!-- config type: completion -->`
2. Named definition: `definitions["Done"] = { type = "completion" }`
3. Pattern matching: `patterns = { "done", "complete" }`
4. No match: `type = nil`

**Property Merging** (implemented):
- Type properties (lowest) < Definition properties < Markdown properties (highest)

**Validation** (implemented):
- `requires_*` pattern detection in `column_type_resolver.lua:155-203`
- Configurable requirement level: "none", "warning", "error"

**Remaining Work**:
- Add default type definitions to config (currently empty)
- Document user-facing API
- Add examples to user guide

### Auto-Move Timing Strategy

**Question**: When should auto-move evaluations occur?

**Options**:
1. **On Save**: Check all cards when board is written
   - Pros: Automatic, no user action needed
   - Cons: Could be slow on large boards, unexpected changes

2. **On Demand**: Via `:KanbanProcessAutoMoves` command
   - Pros: User control, predictable timing
   - Cons: Requires manual action, easy to forget

3. **On Property Change**: Hook into property modifications
   - Pros: Immediate, targeted
   - Cons: Complex to implement, many evaluation points

4. **Periodic/Timer**: Background evaluation (if possible in Neovim)
   - Pros: Automatic, doesn't block user
   - Cons: Neovim limitations, timing control

5. **Hybrid**: On save + manual command available
   - Pros: Balance of automatic and control
   - Cons: More complex, need to avoid duplicates

**Decision Needed**: Which strategy to implement?

## Implementation Priorities

Based on impact and effort:

### High Priority (Next Release)
1. ✅ **COMPLETED** - Code cleanup - Remove hardcoded "Done" from extras
2. Auto-move feature - Complete Phase 3 workflow system

### Medium Priority (Future Releases)
3. Time-based transitions - Useful for automation
4. Swim lanes - Requested feature, moderate complexity
5. ~~Enhanced column properties~~ - ✅ **INFRASTRUCTURE COMPLETE** - Type system exists, just needs property definitions and usage code

### Low Priority (Long Term)
6. Rule-based configuration - Nice to have, backwards compat concerns
7. Visual workflow representation - Polish feature
8. Capacity planning enhancements - Niche use case

## Contributing

If you'd like to contribute to any of these features:

1. Check `features/` directory for existing design docs
2. Open an issue to discuss approach before implementing
3. Follow existing code patterns (triggers, mixins, etc.)
4. Add tests for new functionality
5. Update documentation

## Questions and Feedback

Have ideas for other features? Open an issue or discussion on the project repository.

----

Have a check/prevention mechanism for having too many complex tasks.


There are three core metrics in Kanban that you just have to be aware of.

One is throughput, meaning how much you deliver per period of time, let’s say, per week, per month.

(Second) its cycle time, meaning how much time it takes the card to exit the process.

And then it’s work in progress: how many cards do I have in progress?
