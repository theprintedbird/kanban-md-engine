-- lua/kanban-md/extras/workflow_triggers.lua
-- Extended workflow validation triggers for complex business rules

local Triggerable = require('kanban-md.triggerable')
local WorkflowEngine = require('kanban-md.workflow_engine')
local column_helper = require('kanban-md.helpers.column')

local M = {}

-- SLA compliance trigger
-- Checks if a task transition would violate SLA requirements
function M.create_sla_compliance_trigger(sla_config)
  local execute_fn = function(column, context)
    local task_sla = context.card.properties.sla or sla_config.default_sla
    if not task_sla then
      return true -- No SLA defined
    end

    -- Find earliest timestamp from any column (task start time)
    local earliest_time = nil
    for key, value in pairs(context.card.properties) do
      if type(value) == "number" and value > 1000000000 and value < 2000000000 then
        if not earliest_time or value < earliest_time then
          earliest_time = value
        end
      end
    end

    if not earliest_time then
      return true -- No timestamp to check against
    end

    local current_time = context.timestamp or os.time()
    local elapsed_hours = (current_time - earliest_time) / 3600

    -- Check if task is moving to completion after SLA deadline
    if column_helper.is_completion_column(context.target_column, context.board) or context.target_column.name == "__ARCHIVE__" then
      if elapsed_hours > task_sla.completion_hours then
        return true, nil, string.format(
          "Task completed after SLA deadline: %.1f hours (limit: %d hours)",
          elapsed_hours, task_sla.completion_hours
        )
      end
    end

    -- Check if task is stuck in a column too long
    local started_time = context.card.properties.started
    if started_time and task_sla.max_column_hours then
      local column_time = (current_time - started_time) / 3600
      if column_time > task_sla.max_column_hours then
        return true, nil, string.format(
          "Task has been in column too long: %.1f hours (limit: %d hours)",
          column_time, task_sla.max_column_hours
        )
      end
    end

    return true
  end

  return execute_fn
end

-- Business hours trigger
-- Restricts certain transitions to business hours only
function M.create_business_hours_trigger(business_hours_config)
  local execute_fn = function(column, context)
    local restricted_columns = business_hours_config.restricted_columns or {}
    local is_restricted = false

    for _, col_pattern in ipairs(restricted_columns) do
      if context.target_column.name:match(col_pattern) then
        is_restricted = true
        break
      end
    end

    if not is_restricted then
      return true -- No restrictions for this column
    end

    local current_time = os.date("*t", context.timestamp or os.time())
    local current_hour = current_time.hour
    local current_wday = current_time.wday -- 1=Sunday, 2=Monday, ..., 7=Saturday

    -- Check if it's a weekend (assuming Saturday=7, Sunday=1)
    if current_wday == 1 or current_wday == 7 then
      return false, string.format(
        "Transitions to '%s' are not allowed on weekends",
        context.target_column.name
      )
    end

    -- Check business hours (default 9-17)
    local start_hour = business_hours_config.start_hour or 9
    local end_hour = business_hours_config.end_hour or 17

    if current_hour < start_hour or current_hour >= end_hour then
      return false, string.format(
        "Transitions to '%s' are only allowed during business hours (%d:00-%d:00)",
        context.target_column.name, start_hour, end_hour
      )
    end

    return true
  end

  return execute_fn
end

-- Priority-based workflow trigger
-- Enforces that high-priority tasks must follow fast-track workflows
function M.create_priority_workflow_trigger(priority_workflows)
  local execute_fn = function(column, context)
    local task_priority = context.card.properties.priority or "normal"
    local priority_workflow = priority_workflows[task_priority]

    if not priority_workflow then
      return true -- No special workflow for this priority
    end

    -- Check if current transition is allowed for this priority
    local allowed_targets = priority_workflow[context.source_column.name]
    if not allowed_targets then
      return true -- No restrictions from this source column
    end

    -- Check if target is in allowed list
    for _, allowed_target in ipairs(allowed_targets) do
      if allowed_target == context.target_column_name then
        return true
      end
    end

    return false, string.format(
      "Priority '%s' tasks cannot move from '%s' to '%s'",
      task_priority, context.source_column.name, context.target_column_name
    )
  end

  return execute_fn
end

-- Approval requirement trigger
-- Ensures certain transitions require approval from authorized users
function M.create_approval_requirement_trigger(approval_config)
  local execute_fn = function(column, context)
    local requires_approval = false
    local approval_reasons = {}

    -- Check if target column requires approval
    for column_pattern, config in pairs(approval_config.columns or {}) do
      if context.target_column.name:match(column_pattern) then
        requires_approval = true
        table.insert(approval_reasons, config.reason or "Column transition requires approval")
      end
    end

    -- Check if task properties require approval
    local task_value = context.card.properties.estimated_value or 0
    if approval_config.high_value_threshold and task_value > approval_config.high_value_threshold then
      requires_approval = true
      table.insert(approval_reasons, string.format(
        "High value task ($%.2f) requires approval", task_value
      ))
    end

    if requires_approval then
      -- Check if approval is present
      local approver = context.card.properties.approved_by
      if not approver then
        return false, string.format(
          "Approval required: %s", table.concat(approval_reasons, "; ")
        )
      end

      -- Verify approver is authorized
      local authorized_approvers = approval_config.authorized_approvers or {}
      local is_authorized = false
      for _, auth_approver in ipairs(authorized_approvers) do
        if auth_approver == approver then
          is_authorized = true
          break
        end
      end

      if not is_authorized then
        return false, string.format(
          "Approver '%s' is not authorized. Authorized approvers: %s",
          approver, table.concat(authorized_approvers, ", ")
        )
      end
    end

    return true
  end

  return execute_fn
end

-- Basic workflow rules trigger
-- Validates that card transitions follow configured workflow rules
function M.create_workflow_rules_trigger(workflow_config)
  local execute_fn = function(column, context)
    -- If there's no source column, this is a direct add (not a move), so allow it
    if not context.source_column then
      return Triggerable:success()
    end

    local allowed_targets = workflow_config[context.source_column.name]
    if not allowed_targets then
      return Triggerable:success() -- No restrictions
    end

    -- Handle different workflow formats
    if type(allowed_targets) == "table" then
      -- Array of simple targets
      if #allowed_targets > 0 and type(allowed_targets[1]) == "string" then
        for _, target in ipairs(allowed_targets) do
          if target == context.target_column_name then
            return Triggerable:success()
          end
        end
      -- Object with conditional transitions
      else
        for target, config in pairs(allowed_targets) do
          if target == context.target_column_name then
            -- Check for simple inclusion (no config or empty config)
            if type(config) ~= "table" or not config.when then
              -- Check for auto-move flag
              if type(config) == "table" and config.auto then
                context.auto_move = true
              end
              return Triggerable:success()
            end

            -- Check conditions if present
            if config.when then
              local condition_met = WorkflowEngine.evaluate_condition_static(config.when, context.card)
              if condition_met then
                -- Check for auto-move flag
                if config.auto then
                  context.auto_move = true
                end
                return Triggerable:success()
              else
                return Triggerable:error(string.format(
                  "Workflow condition '%s' not met for transition from '%s' to '%s'",
                  config.when, context.source_column.name, context.target_column_name
                ))
              end
            end
          end
        end
      end
    elseif type(allowed_targets) == "string" then
      -- Single target
      if allowed_targets == context.target_column_name then
        return Triggerable:success()
      end
    end

    return Triggerable:error(string.format(
      "Workflow does not allow transition from '%s' to '%s'",
      context.source_column.name, context.target_column_name
    ))
  end

  return execute_fn
end

return M
