-- lua/kanban-md/workflow_engine.lua
-- Simplified workflow engine for registering workflow rule triggers
-- Following statechart design: WorkflowReady → RegisteringCheckers → WorkflowReady → [*]
--
-- Example usage:
-- local workflow_engine = WorkflowEngine:new(board)
-- workflow_engine:setup_triggers() -- Registers workflow rules as on_checking triggers

local ValidationResult = require('kanban-md.validation_result')
local Triggerable = require("kanban-md.triggerable")

-- Static helper function to evaluate conditions (used by workflow validation)
-- Format: "property == value" or "property != value"
local function evaluate_condition(condition, card)
  -- Simple property-based conditions for now
  local prop, op, value = condition:match("(%w+)%s*([=!]+)%s*(.+)")

  if not prop then
    -- Try to evaluate as a simple boolean property
    return card.properties[condition] == true
  end

  local card_value = card.properties[prop]

  -- Clean up value
  value = value:gsub("^[\"']", ""):gsub("[\"']$", "")

  -- Convert "true"/"false" strings to booleans
  if value == "true" then value = true
  elseif value == "false" then value = false
  elseif value == "nil" then value = nil
  elseif tonumber(value) then value = tonumber(value)
  end

  if op == "==" or op == "=" then
    return card_value == value
  elseif op == "!=" then
    return card_value ~= value
  end

  return false
end

-- Static helper function to get valid transitions for a card
-- Returns array of valid target column names
local function get_valid_transitions(board, card, source_column)
  local workflow = board.config and board.config.workflow

  if not workflow then
    -- No workflow defined - return all columns except source
    local valid = {}
    for _, column in ipairs(board.columns) do
      if column.name ~= source_column.name then
        table.insert(valid, column.name)
      end
    end
    -- Add archive if not already there
    if source_column.name ~= "__ARCHIVE__" then
      table.insert(valid, "__ARCHIVE__")
    end
    return valid
  end

  local transitions = workflow[source_column.name]
  if not transitions then
    return {}  -- No transitions defined
  end

  local valid = {}

  -- Handle simple array of strings
  if type(transitions) == "table" then
    -- Check if it's a simple array
    local is_array = true
    for k, v in pairs(transitions) do
      if type(k) ~= "number" or type(v) == "table" then
        is_array = false
        break
      end
    end

    if is_array then
      return transitions
    end

    -- Handle conditional transitions
    for target, config in pairs(transitions) do
      if type(config) == "table" then
        if config.when then
          -- Evaluate condition
          if evaluate_condition(config.when, card) then
            table.insert(valid, target)
          end
        else
          -- No condition, always allow
          table.insert(valid, target)
        end
      else
        -- Simple inclusion
        table.insert(valid, target)
      end
    end
  end

  return valid
end

-- Simplified WorkflowEngine class for trigger registration only
local WorkflowEngine = {}
WorkflowEngine.__index = WorkflowEngine

-- Simple state constants matching the statechart
local STATES = {
	READY = "ready",
	REGISTERING_CHECKERS = "registering_checkers"
}

function WorkflowEngine:new(board)
	local obj = {
		board = board,
		state = STATES.READY
	}
	setmetatable(obj, WorkflowEngine)

	-- Auto-setup triggers during initialization
	obj:setup_triggers()

	return obj
end


-- Auto-setup triggers when workflow engine is created
function WorkflowEngine:setup_triggers()
	self.state = STATES.REGISTERING_CHECKERS

	-- Setup core triggers (dependencies, subtasks, WIP limits)
	self:setup_core_triggers(self.board)

	-- Setup workflow triggers if workflow config exists
	self:setup_workflow_triggers(self.board)

	self.state = STATES.READY
end


-- Convert dependencies to checking trigger
local function create_dependency_trigger()
  local execute_fn = function(column, context)
    -- Only check for completion columns
    local is_completion = context.target_column.name == "Done" or context.target_column.name == "__ARCHIVE__"
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
        return Triggerable:error(string.format("Dependency '%s' not found", dep_id))
      end

      local dep_complete = dep_column and (dep_column.name == "Done" or dep_column.name == "__ARCHIVE__")
      if not dep_complete then
        local error_result = Triggerable:error(string.format("Dependency '%s' is not complete", dep_id))
        if _G._TEST then
        end
        return error_result
      end
    end

    return Triggerable:success()
  end

  return execute_fn, nil
end

-- Convert subtasks to checking trigger
local function create_subtask_trigger()
  local execute_fn = function(column, context)
    -- Only check for completion columns
    local is_completion = context.target_column.name == "Done" or context.target_column.name == "__ARCHIVE__"
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
        return Triggerable:error(string.format("Subtask '%s' not found", subtask_id))
      end

      local subtask_complete = subtask_column and (subtask_column.name == "Done" or subtask_column.name == "__ARCHIVE__")
      if not subtask_complete then
        table.insert(incomplete, subtask_id)
      end
    end

    if #incomplete > 0 then
      return Triggerable:error(string.format(
        "Subtasks not complete: %s",
        table.concat(incomplete, ", ")
      ))
    end

    return Triggerable:success()
  end

  return execute_fn, nil
end

-- Convert capacity checks to checking triggers
local function create_wip_limit_checking_trigger(wip_limit)
  local execute_fn = function(column, context)
    local current_count = #context.target_column.cards
    if current_count >= wip_limit then
      return Triggerable:warning(string.format(
        "Column '%s' WIP limit reached (%d/%d)",
        context.target_column.name, current_count, wip_limit
      ))
    end
    return Triggerable:success()
  end

  return execute_fn, nil
end


-- Auto-register workflow triggers during board setup
function WorkflowEngine:setup_workflow_triggers(board)
  if not board.config.workflow then return end

  -- Load workflow trigger function from external module
  local workflow_triggers = require('kanban-md.extras.workflow_triggers')
  local create_workflow_rules_trigger = workflow_triggers.create_workflow_rules_trigger

  for source_column_name, targets in pairs(board.config.workflow) do
    local column = board:get_column_by_name(source_column_name)
    if column then
      local execute_fn, rollback_fn = create_workflow_rules_trigger(board.config.workflow)
      column:register_on_checking("workflow_rules", execute_fn, rollback_fn)
    end
  end
end

-- Auto-register core validation triggers
function WorkflowEngine:setup_core_triggers(board)
  -- Register dependency/subtask triggers on all columns
  for _, column in ipairs(board.columns) do
    local dep_fn, dep_rollback = create_dependency_trigger()
    column:register_on_checking("dependencies", dep_fn, dep_rollback)

    local subtask_fn, subtask_rollback = create_subtask_trigger()
    column:register_on_checking("subtasks", subtask_fn, subtask_rollback)

    -- Register capacity triggers based on column config
    if column.config.wip_limit then
      local wip_fn, wip_rollback = create_wip_limit_checking_trigger(column.config.wip_limit)
      column:register_on_checking("wip_limit", wip_fn, wip_rollback)
    end
  end
end


-- Get valid transitions for a card in its current column
-- Instance method for backwards compatibility
function WorkflowEngine:get_valid_transitions(card, source_column)
	return get_valid_transitions(self.board, card, source_column)
end


-- Export static helper function for use by Board
WorkflowEngine.get_valid_transitions_static = get_valid_transitions

return WorkflowEngine
