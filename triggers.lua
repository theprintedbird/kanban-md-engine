-- Example trigger implementations with rollback

-- Timestamp trigger with rollback
local function create_timestamp_trigger()
  local normalize_column_name = function(column_name)
    if column_name == "__ARCHIVE__" then
      return "archived"
    end
    return column_name:lower():gsub("[^%w_]", "_")
  end

  local execute_fn = function(self, context)
    local card = context.card
    local timestamp_key = normalize_column_name(self.name or self.id)
    local old_value = card.properties[timestamp_key]
    card.properties[timestamp_key] = os.time()

    -- Return old value for rollback
    return old_value
  end

  local rollback_fn = function(self, context)
    local card = context.card
    local timestamp_key = normalize_column_name(self.name or self.id)

    -- Restore previous value (might be nil)
    if context.result then
      card.properties[timestamp_key] = context.result
    else
      card.properties[timestamp_key] = nil
    end

    return true
  end

  return execute_fn, rollback_fn
end

-- WIP limit validation trigger with rollback
local function create_wip_limit_trigger(wip_limit)
  local execute_fn = function(self, context)
    if #self.cards >= wip_limit then
      error(string.format("WIP limit exceeded: %d/%d", #self.cards, wip_limit))
    end
    return true
  end

  local rollback_fn = function(self, context)
    -- Nothing to rollback for validation
    return true
  end

  return execute_fn, rollback_fn
end

-- Assignment trigger with rollback
local function create_assignment_trigger()
  local execute_fn = function(self, context)
    local card = context.card
    local old_assignee = card.properties.assignee

    -- Simple round-robin assignment
    local assignees = self.config.assignees or {"unassigned"}
    local last_assigned = self.last_assigned_index or 0
    local next_index = (last_assigned % #assignees) + 1

    card.properties.assignee = assignees[next_index]
    self.last_assigned_index = next_index

    return {old_assignee, last_assigned}
  end

  local rollback_fn = function(self, context)
    local card = context.card
    local result = context.result

    -- Handle case where result is a table with two values
    if type(result) == "table" and #result == 2 then
      local old_assignee, old_index = result[1], result[2]

      -- Restore previous assignee
      if old_assignee then
        card.properties.assignee = old_assignee
      else
        card.properties.assignee = nil
      end

      -- Restore index
      self.last_assigned_index = old_index
    end

    return true
  end

  return execute_fn, rollback_fn
end


return {
  timestamp = create_timestamp_trigger,
  wip_limit = create_wip_limit_trigger,
  assignment = create_assignment_trigger,
}
