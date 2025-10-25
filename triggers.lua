-- Example trigger implementations

local Triggerable = require('kanban-md.triggerable')

-- Timestamp trigger
local function create_timestamp_trigger()
  local normalize_column_name = function(column_name)
    if column_name == "__ARCHIVE__" then
      return "archived"
    end
    return column_name:lower():gsub("[^%w_]", "_")
  end

  return function(self, context)
    local card = context.card
    local timestamp_key = normalize_column_name(self.name or self.id)
    card.properties[timestamp_key] = os.time()
    return true
  end
end

-- WIP limit validation trigger
-- Checks target column capacity (works correctly for both entry and exit validation)
local function create_wip_limit_trigger(wip_limit)
  local execute_fn = function(column, context)
    local current_count = #context.target_column.cards
    if current_count >= wip_limit then
      local action_hint = "Remove or complete a card before adding more."
      return Triggerable:error(string.format(
        "WIP limit reached for '%s' (%d/%d). %s",
        context.target_column.name, current_count, wip_limit, action_hint
      ))
    end
    return Triggerable:success()
  end

  return execute_fn, nil
end

-- Assignment trigger
local function create_assignment_trigger()
  return function(self, context)
    local card = context.card

    -- Simple round-robin assignment
    local assignees = self.config.assignees or {"unassigned"}
    local last_assigned = self.last_assigned_index or 0
    local next_index = (last_assigned % #assignees) + 1

    card.properties.assignee = assignees[next_index]
    self.last_assigned_index = next_index

    return true
  end
end

-- Default complexity trigger
-- Adds default complexity to cards that don't already have it
local function create_default_complexity_trigger(default_value)
  return function(self, context)
    local card = context.card

    -- Only add complexity if not already set
    if not card.properties.complexity then
      card.properties.complexity = default_value
    end

    return true
  end
end


return {
  timestamp = create_timestamp_trigger,
  wip_limit = create_wip_limit_trigger,
  assignment = create_assignment_trigger,
  default_complexity = create_default_complexity_trigger,
}
