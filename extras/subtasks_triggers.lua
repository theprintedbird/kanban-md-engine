-- lua/kanban-md/extras/subtasks_triggers.lua
-- Optional subtasks and dependencies validation triggers
-- Enable via config: subtask_validation = "strict"/"warn", dependency_validation = "strict"/"warn"

local Triggerable = require('kanban-md.triggerable')

local M = {}

-- Register property types with TypeConverter when this module is loaded
function M.register_property_types()
  local TypeConverter = require('kanban-md.type_converter')
  TypeConverter.register_array_property('subtasks')
  TypeConverter.register_array_property('depends_on')
end

-- Convert subtasks to checking trigger
function M.create_subtask_trigger(enforcement_mode)
  local execute_fn = function(column, context)
    -- Only check for completion columns
    local column_helper = require('kanban-md.helpers.column')
    local is_completion = column_helper.is_completion_column(context.target_column, context.board)
    if not is_completion then
      return Triggerable:success()
    end

    -- Check if task has subtasks
    if not context.card.properties.subtasks or #context.card.properties.subtasks == 0 then
      return Triggerable:success()
    end

    -- Verify all subtasks are complete
    local incomplete = {}
    for _, subtask_id in ipairs(context.card.properties.subtasks) do
      local subtask, subtask_column = context.board:find_task(subtask_id)

      if not subtask then
        -- Missing subtasks are always errors, regardless of mode
        return Triggerable:error(string.format("Subtask '%s' not found", subtask_id))
      end

      local subtask_complete = subtask_column and column_helper.is_completion_column(subtask_column, context.board)
      if not subtask_complete then
        table.insert(incomplete, subtask_id)
      end
    end

    if #incomplete > 0 then
      local count = #incomplete
      local task_list = table.concat(incomplete, ", ")
      local message = string.format(
        "Cannot complete: %d subtask%s still incomplete (%s). Complete %s first.",
        count,
        count > 1 and "s" or "",
        task_list,
        count > 1 and "them" or "it"
      )

      -- Return warning or error based on enforcement mode
      if enforcement_mode == "warn" then
        return Triggerable:warning(message)
      else
        -- Default to strict mode (error)
        return Triggerable:error(message)
      end
    end

    return Triggerable:success()
  end

  return execute_fn
end

-- Convert dependencies to checking trigger
function M.create_dependency_trigger(enforcement_mode)
  local execute_fn = function(column, context)
    -- Only check for completion columns
    local column_helper = require('kanban-md.helpers.column')
    local is_completion = column_helper.is_completion_column(context.target_column, context.board)
    if not is_completion then
      return Triggerable:success()
    end

    if not context.card.properties.depends_on or #context.card.properties.depends_on == 0 then
      return Triggerable:success()
    end

    -- Verify all dependencies are complete
    for _, dep_id in ipairs(context.card.properties.depends_on) do
      local dep_task, dep_column = context.board:find_task(dep_id)
      if not dep_task then
        -- Missing dependencies are always errors, regardless of mode
        return Triggerable:error(string.format("Dependency '%s' not found", dep_id))
      end

      local dep_complete = dep_column and column_helper.is_completion_column(dep_column, context.board)
      if not dep_complete then
        local current_status = dep_column and dep_column.name or "Unknown"
        local message = string.format(
          "Cannot complete: dependency '%s' is not done (currently in '%s'). Complete it first.",
          dep_id,
          current_status
        )

        -- Return warning or error based on enforcement mode
        if enforcement_mode == "warn" then
          return Triggerable:warning(message)
        else
          -- Default to strict mode (error)
          return Triggerable:error(message)
        end
      end
    end

    return Triggerable:success()
  end

  return execute_fn
end

return M
