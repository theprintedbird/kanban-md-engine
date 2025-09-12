-- lua/kanban-md/transition_rules.lua
-- Transition rules engine for validating task movements

local parser = require("kanban-md.parser")
-- local config = require("kanban-md.config")

local M = {}
-- Helper: Check WIP limits
function M.check_wip_limit(options)
	local board = options.board
	local column_name = options.column
	local config = options.config

	local column = parser.get_column(board, column_name)
	if not column or not column.config.wip_limit then
		return true, nil
	end

	local current_wip = 0
	for _, task in ipairs(column.tasks) do
		-- Task is completed if in Done column or has done timestamp
		local is_completed = column.name == "Done" or task.properties.done
		if not is_completed then
			current_wip = current_wip + 1
		end
	end

	if current_wip >= column.config.wip_limit then
		local msg = string.format("WIP limit exceeded in %s: %d/%d",
			column_name, current_wip + 1, column.config.wip_limit)

		if config.block_on_wip_exceeded then
			return false, msg
		elseif config.warn_on_wip_exceeded then
			vim.notify(msg, vim.log.levels.WARN)
		end
	end

	return true, nil
end

-- Check if a task can transition from source to target column
function M.check_transition_rules(board, task, source_column, target_column_name)
  local errors = {}
  local warnings = {}

	if not board then
		-- TODO error
	end
	if not task then
		-- TODO error
	end
	if not source_column then
		table.insert(errors, "Failure: a source column needs to be passed as an argument to check_transition_rules")
    return false, errors, warnings
	end
	if not target_column_name then
		table.insert(errors, "Failure: a target column name needs to be passed as an argument to check_transition_rules")
    return false, errors, warnings
	end
  -- 1. Check workflow constraints (if defined)
  if not M.check_workflow_allows(board, source_column.name, target_column_name) then
    table.insert(errors, string.format(
      "Workflow does not allow transition from '%s' to '%s'",
      source_column.name, target_column_name
    ))
  end

  -- 2. Check column-specific rules
  local target_column = M.get_column(board, target_column_name)
	if not target_column then
		table.insert(errors, "No target column name found")
    return false, table.concat(errors, "; "), warnings
	end


  if target_column and target_column.config then
    -- Check column entry requirements
    if not M.check_column_entry_requirements(task, target_column) then
      table.insert(errors, string.format(
        "Task does not meet entry requirements for '%s'",
        target_column_name
      ))
    end
  end

  -- 3. Check task dependencies
  if not M.check_dependencies_satisfied(board, task, target_column_name) then
    table.insert(errors, "Task has unsatisfied dependencies")
  end

  -- 5. Check business rules for specific transitions
  local business_errors = M.check_business_rules(board, task, source_column.name, target_column_name)
  for _, err in ipairs(business_errors) do
    table.insert(errors, err)
  end

  -- 6. Check sub-tasks (if parent task)
  if not M.check_subtasks_ready(board, task, target_column_name) then
    table.insert(errors, "Not all subtasks are ready for this transition")
  end

  -- 7. Check resource availability (non-blocking, just warning)
  local resource_issues = M.check_resources(board, task, target_column)
  for _, warning in ipairs(resource_issues) do
    table.insert(warnings, warning)
  end

  -- Return results
  if #errors > 0 then
    return false, table.concat(errors, "; "), warnings
  else
    return true, nil, warnings
  end
end

-- 1. Workflow constraint checking
function M.check_workflow_allows(board, source_name, target_name)
  -- If no workflow defined, allow any transition
  if not board.config or not board.config.workflow then
    return true
  end

  local allowed_targets = board.config.workflow[source_name]
  if not allowed_targets then
    -- No rules for this source, allow transition
    return true
  end

  -- Check if target is in allowed list
  for _, allowed in ipairs(allowed_targets) do
    if allowed == target_name then
      return true
    end
  end

  return false
end

-- 2. Column entry requirements
function M.check_column_entry_requirements(task, target_column)
  if not target_column.config then
    return true
  end

  local target_column_config = target_column.config

  -- Check required properties
  if target_column_config.requires then
    for _, required_prop in ipairs(target_column_config.requires) do
      if not task.properties[required_prop] then
        return false
      end
    end
  end

  -- Check required fields are filled
  if target_column_config.required_fields then
    for _, field in ipairs(target_column_config.required_fields) do
      local value = task.properties[field]
      if not value or value == "" then
        return false
      end
    end
  end

  -- Check minimum complexity/estimation
  if target_column_config.min_complexity and task.properties.complexity then
    if task.properties.complexity < target_column_config.min_complexity then
      return false
    end
  end

  -- Check assignee requirements
  if target_column_config.requires_assignee and not task.properties.assignee then
    return false
  end

  if target_column_config.requires_reviewer and target_column.name == "Review" then
    if not task.properties.reviewer then
      return false
    end
  end

  return true
end

-- 3. Task dependencies
function M.check_dependencies_satisfied(board, task, target_column_name)
  -- Special rules for moving to "Done" or similar completion columns
  local completion_columns = {"Done", "Complete", "Shipped", "Deployed"}
  local is_completion_move = false

  for _, col in ipairs(completion_columns) do
    if target_column_name == col then
      is_completion_move = true
      break
    end
  end

  -- Only check dependencies for completion moves
  if not is_completion_move then
    return true
  end

  -- Check if task has dependencies
  if not task.properties.depends_on or #task.properties.depends_on == 0 then
    return true
  end

  -- Check each dependency
  for _, dep_id in ipairs(task.properties.depends_on) do
    local dep_task, dep_column = parser.find_task(board, dep_id)

    if not dep_task then
      -- Dependency not found, this is an error
      return false
    end

    -- Check if dependency is complete (in Done column or has done timestamp)
    local is_completed = (dep_column and dep_column.name == "Done") or dep_task.properties.done
    if not is_completed then
      return false
    end
  end

  return true
end

-- 5. Business rules for specific scenarios
function M.check_business_rules(board, task, source_name, target_name)
  local errors = {}

  -- Example business rules

  -- Rule: Can't skip Review for high-complexity tasks
  if source_name == "In Progress" and target_name == "Done" then
    if task.properties.complexity and task.properties.complexity >= 5 then
      table.insert(errors, "High complexity tasks must go through Review")
    end
  end

  -- Rule: Can't move directly from Backlog to Done
  if source_name == "Backlog" and target_name == "Done" then
    table.insert(errors, "Tasks cannot skip from Backlog directly to Done")
  end

  -- Rule: Blocked tasks must go through Ready when unblocked
  if source_name == "Blocked" and target_name == "In Progress" then
    if not task.properties.revalidated then
      table.insert(errors, "Blocked tasks must be revalidated in Ready before returning to In Progress")
    end
  end

  -- Rule: Tasks in Review can only go back to In Progress if changes requested
  if source_name == "Review" and target_name == "In Progress" then
    if not task.properties.changes_requested then
      table.insert(errors, "Can only return to In Progress if changes are requested")
    end
  end

  -- Rule: Check SLA requirements
  if target_name == "Done" and task.properties.sla then
    local sla_deadline = task.properties.created + (task.properties.sla * 86400)  -- SLA in days
    if os.time() > sla_deadline then
      table.insert(errors, "Task has exceeded SLA deadline")
    end
  end

  return errors
end

-- 6. Sub-task checking
function M.check_subtasks_ready(board, task, target_column_name)
  -- Only check for completion moves
  if target_column_name ~= "Done" and target_column_name ~= "Complete" then
    return true
  end

  -- Check if task has subtasks
  if not task.properties.subtasks or #task.properties.subtasks == 0 then
    return true
  end

  -- Check each subtask
  for _, subtask_id in ipairs(task.properties.subtasks) do
    local subtask, subtask_column = parser.find_task(board, subtask_id)

    if not subtask then
      -- Subtask not found
      return false
    end

    -- All subtasks must be complete (in Done column or has done timestamp)
    local is_completed = (subtask_column and subtask_column.name == "Done") or subtask.properties.done
    if not is_completed then
      return false
    end
  end

  return true
end

-- 7. Resource checking (warnings only)
function M.check_resources(board, task, target_column)
  local warnings = {}

  -- Check if target column has resource constraints
  if target_column and target_column.config then
    -- Check test environment availability
    if target_column.name == "Testing" or target_column.name == "QA" then
      if board.config and board.config.test_environments then
        local available = board.config.test_environments.available or 0
        if available <= 0 then
            table.insert(warnings, "No test environments currently available")
        end
      end
    end

    -- Check reviewer availability
    if target_column.name == "Review" then
      if not task.properties.reviewer then
        -- Count available reviewers
        local reviewers_busy = M.count_tasks_in_review(board)
        local total_reviewers = board.config and board.config.reviewers and #board.config.reviewers or 0

        if reviewers_busy >= total_reviewers then
            table.insert(warnings, "All reviewers are currently busy")
        end
      end
    end

    -- Check deployment slots
    if target_column.name == "Deploying" then
      local deploying_count = #target_column.tasks
      local max_parallel_deploys = board.config and board.config.max_parallel_deploys or 1

      if deploying_count >= max_parallel_deploys then
        table.insert(warnings, string.format(
            "Deployment queue is full (%d/%d)",
            deploying_count, max_parallel_deploys
        ))
      end
    end
  end

  return warnings
end

-- Helper functions
function M.get_column(board, column_name)
  for _, column in ipairs(board.columns) do
    if column.name == column_name then
      return column
    end
  end

  if board.archive and column_name == "__ARCHIVE__" then
    return board.archive
  end

  return nil
end

function M.find_task(board, task_id)
  -- Search in regular columns
  for _, column in ipairs(board.columns) do
    for _, task in ipairs(column.tasks) do
      if task.properties.id == task_id then
        return task, column
      end
    end
  end

  -- Search in archive
  if board.archive then
    for _, task in ipairs(board.archive.tasks) do
      if task.properties.id == task_id then
        return task, board.archive
      end
    end
  end

  return nil, nil
end

function M.count_tasks_in_review(board)
  local count = 0
  for _, column in ipairs(board.columns) do
    if column.name == "Review" then
      count = #column.tasks
      break
    end
  end
  return count
end

-- Extended configuration example for column entry requirements
--[[
Column configurations can include:

<!-- column:config
type: review
requires: ["description", "test_plan"]
required_fields: ["assignee", "complexity"]
requires_reviewer: true
min_complexity: 1
-->

<!-- column:config
type: blocked
auto_add_property: { "blocked": true, "blocked_at": <timestamp> }
auto_remove_property: ["started"]
-->

<!-- column:config
type: done
auto_complete: true
requires: ["acceptance_criteria_met"]
-->
--]]

return M
