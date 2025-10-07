-- lua/kanban-md/transition_rules.lua
-- Transition rules engine for validating task movements

-- local config = require("kanban-md.config")

local M = {}

function M.is_completion_column(column, board)
	if not column or not column.name then
		return false
	end

  -- Priority order:
  -- 1. Explicit property
  if column.properties and column.properties.is_completion_state then
    return true
  end

  -- 2. Has completion triggers (Phase 2)
  if column.triggers and vim.tbl_contains(column.triggers.on_entry or {}, "mark_complete") then
    return true
  end

  -- 3. Position-based fallback (maintains backwards compatibility)
  local columns = board.columns
  local regular_columns = {}

  -- Collect all non-special columns
  for _, col in ipairs(columns) do
    if col.name and not col.name:match("^__") then
      table.insert(regular_columns, col)
    end
  end

  -- Check if column name suggests it's not a completion column
	-- TODO remove this hardcoded nonsense!
  local non_completion_patterns = {
    "progress", "doing", "working", "wip", "active", "current",
    "backlog", "todo", "ready", "waiting", "blocked", "review"
  }

  local column_name_lower = column.name:lower()
  for _, pattern in ipairs(non_completion_patterns) do
    if column_name_lower:match(pattern) then
      return false
    end
  end

	-- TODO check the config instead
  -- Check for explicit completion patterns
  local completion_patterns = {
    "done", "complete", "finished", "shipped", "deployed", "closed", "__ARCHIVE__"
  }

  for _, pattern in ipairs(completion_patterns) do
    if column_name_lower:match(pattern) then
      return true
    end
  end

  -- Don't use position-based fallback if there's only one column
  if #regular_columns <= 1 then
    return false
  end

  -- Only consider the last column as completion if there are multiple columns
  -- and the name doesn't suggest otherwise
  return column == regular_columns[#regular_columns]
end

-- Helper: Check WIP limits
function M.check_wip_limit(options)
	local board = options.board
	local column_name = options.column
	local config = options.config

	local column = M.get_column(board, column_name)
	if not column or not column.config.wip_limit then
		return true, nil
	end

	local current_wip = 0
	local tasks = column.tasks or column.cards or {}
	for _, task in ipairs(tasks) do
		-- Count all tasks toward WIP limit
		current_wip = current_wip + 1
	end


	if current_wip >= column.config.wip_limit then
		local msg = string.format("WIP limit exceeded in %s: %d/%d",
			column_name, current_wip + 1, column.config.wip_limit)

		if config.block_on_wip_exceeded then
			return false, msg
		else
			-- Return false with message for warning (workflow engine expects this)
			return false, msg
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


  -- Return results
  if #errors > 0 then
    return false, table.concat(errors, "; "), warnings
  else
    return true, nil, warnings
  end
end

-- 1. Workflow constraint checking
-- TODO convert to triggers, probably entry triggers
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
-- TODO convert to entry triggers
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
-- TODO convert to triggers
function M.check_dependencies_satisfied(board, task, target_column_name)
  -- Special rules for moving to completion columns
  local target_column = M.get_column(board, target_column_name)
  local is_completion_move = target_column and M.is_completion_column(target_column, board)

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
    local dep_task, dep_column = M.find_task(board, dep_id)

    if not dep_task then
      -- Dependency not found, this is an error
      return false
    end

    -- Check if dependency is complete (in completion column or has done timestamp)
    local is_completed = (dep_column and M.is_completion_column(dep_column, board))
    if not is_completed then
      return false
    end
  end

  return true
end

-- 5. Business rules for specific scenarios
-- TODO convert to triggers
function M.check_business_rules(board, task, source_name, target_name)
  local errors = {}

  -- Example business rules

  -- Rule: Can't skip Review for high-complexity tasks
  local target_column = M.get_column(board, target_name)
  if source_name == "In Progress" and target_column and M.is_completion_column(target_column, board) then
    if task.properties.complexity and task.properties.complexity >= 5 then
      table.insert(errors, "High complexity tasks must go through Review")
    end
  end

  -- Rule: Can't move directly from Backlog to completion
  if source_name == "Backlog" and target_column and M.is_completion_column(target_column, board) then
    table.insert(errors, "Tasks cannot skip from Backlog directly to completion")
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
  if target_column and M.is_completion_column(target_column, board) and task.properties.sla then
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
  local target_column = M.get_column(board, target_column_name)
  if not target_column or not M.is_completion_column(target_column, board) then
    return true
  end

  -- Check if task has subtasks
  if not task.properties.subtasks or #task.properties.subtasks == 0 then
    return true
  end

  -- Check each subtask
  for _, subtask_id in ipairs(task.properties.subtasks) do
    local subtask, subtask_column = M.find_task(board, subtask_id)

    if not subtask then
      -- Subtask not found
      return false
    end

    -- All subtasks must be complete (in completion column or has done timestamp)
    local is_completed = (subtask_column and M.is_completion_column(subtask_column, board))
    if not is_completed then
      return false
    end
  end

  return true
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
    for _, task in ipairs(column.tasks or column.cards or {}) do
      if task.properties.id == task_id then
        return task, column
      end
    end
  end

  -- Search in archive
  if board.archive then
    for _, task in ipairs(board.archive and (board.archive.tasks or board.archive.cards) or {}) do
      if task.properties.id == task_id then
        return task, board.archive
      end
    end
  end

  return nil, nil
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
