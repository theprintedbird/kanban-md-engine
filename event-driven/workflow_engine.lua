-- lua/kanban-md/event-driven/workflow_engine.lua
-- Event-driven workflow engine for validating and executing card transitions
-- Example usage
-- In the Board or refactored actions
-- local workflow_engine = WorkflowEngine:new(board)
-- local result, error, warnings, auto_move = workflow_engine:request_move(card, source_column, target_column_name)
--
-- if result == "warning" then
--     -- Show warnings to user and get decision
--     if user_confirms then
--         result = workflow_engine:override_warnings()
--     else
--         result = workflow_engine:cancel_transition()
--     end
-- end

local Command = require('kanban-md.event-driven.command')
local checker = require('kanban-md.actions.checker')

-- WorkflowEngine class for managing card transitions and validations
local WorkflowEngine = {}
WorkflowEngine.__index = WorkflowEngine

-- State constants matching the statechart
local STATES = {
    READY = "ready",
    VALIDATING = "validating_transition",
    CHECKING_RULES = "checking_workflow_rules",
    CHECKING_DEPS = "checking_dependencies",
    CHECKING_SUBTASKS = "checking_subtasks",
    CHECKING_CAPACITY = "checking_capacity",
    APPROVED = "transition_approved",
    DENIED = "transition_denied",
    WARNING = "transition_warning",
    EXECUTING = "executing_move"
}

function WorkflowEngine:new(board)
    local obj = {
        board = board,
        state = STATES.READY,
        current_transition = nil,
        validation_results = {},
        command_log = board.command_log -- Share command log with board
    }
    setmetatable(obj, WorkflowEngine)
    return obj
end

-- Main entry point for move requests
function WorkflowEngine:request_move(card, source_column, target_column_name)
    if self.state ~= STATES.READY then
        return false, "Workflow engine busy with another transition"
    end

    -- Store transition context
    self.current_transition = {
        card = card,
        source_column = source_column,
        target_column_name = target_column_name,
        target_column = self.board:get_column_by_name(target_column_name),
        timestamp = os.time()
    }

    -- Begin validation
    self.state = STATES.VALIDATING
    return self:validate_transition()
end

-- Validation orchestrator
function WorkflowEngine:validate_transition()
    local transition = self.current_transition
    if not transition then
        self.state = STATES.READY
        return false, "No transition to validate"
    end

    -- Reset validation results
    self.validation_results = {
        errors = {},
        warnings = {},
        passed_checks = {}
    }

    -- Execute validation pipeline
    local checks = {
        {state = STATES.CHECKING_RULES, method = "check_workflow_rules"},
        {state = STATES.CHECKING_DEPS, method = "check_dependencies"},
        {state = STATES.CHECKING_SUBTASKS, method = "check_subtasks"},
        {state = STATES.CHECKING_CAPACITY, method = "check_capacity"}
    }

    for _, check in ipairs(checks) do
        self.state = check.state
        local success, err, warn = self[check.method](self)

        if not success then
            -- Critical error - transition to denied
            if err then
                table.insert(self.validation_results.errors, err)
            end
            self.state = STATES.DENIED
            return self:handle_denied()
        elseif warn then
            -- Non-critical warning
            if type(warn) == "table" then
                for _, w in ipairs(warn) do
                    table.insert(self.validation_results.warnings, w)
                end
            else
                table.insert(self.validation_results.warnings, warn)
            end
        else
            -- Check passed
            table.insert(self.validation_results.passed_checks, check.method)
        end
    end

    -- Determine final state based on validation results
    if #self.validation_results.errors > 0 then
        self.state = STATES.DENIED
        return self:handle_denied()
    elseif #self.validation_results.warnings > 0 then
        self.state = STATES.WARNING
        return self:handle_warning()
    else
        self.state = STATES.APPROVED
        return self:handle_approved()
    end
end

-- Individual validation checks
function WorkflowEngine:check_workflow_rules()
    local t = self.current_transition

    -- Check if workflow is defined
    if not self.board.config or not self.board.config.workflow then
        -- No workflow defined - allow any transition
        return true
    end

    local allowed_targets = self.board.config.workflow[t.source_column.name]

    if not allowed_targets then
        -- No rules for this source - allow
        return true
    end

    -- Handle different workflow formats
    if type(allowed_targets) == "table" then
        -- Array of simple targets
        if #allowed_targets > 0 and type(allowed_targets[1]) == "string" then
            for _, target in ipairs(allowed_targets) do
                if target == t.target_column_name then
                    return true
                end
            end
        -- Object with conditional transitions
        else
            for target, config in pairs(allowed_targets) do
                if target == t.target_column_name then
                    -- Check conditions if present
                    if config.when then
                        local condition_met = self:evaluate_condition(config.when, t.card)
                        if condition_met then
                            -- Check for auto-move flag
                            if config.auto then
                                t.auto_move = true
                            end
                            return true
                        end
                    else
                        -- No condition, always allow
                        return true
                    end
                end
            end
        end
    elseif type(allowed_targets) == "string" then
        -- Single target
        if allowed_targets == t.target_column_name then
            return true
        end
    end

    return false, string.format(
        "Workflow does not allow transition from '%s' to '%s'",
        t.source_column.name, t.target_column_name
    )
end

function WorkflowEngine:check_dependencies()
    local t = self.current_transition

    -- Only check for moves to completion columns
    if not t.target_column or not checker.is_completion_column(t.target_column, self.board) then
        return true
    end

    -- Check task dependencies
    if not t.card.properties.depends_on or #t.card.properties.depends_on == 0 then
        return true
    end

    -- Verify all dependencies are complete
    for _, dep_id in ipairs(t.card.properties.depends_on) do
        local dep_task, dep_column = self.board:find_task(dep_id)

        if not dep_task then
            return false, string.format("Dependency '%s' not found", dep_id)
        end

        if not checker.is_completion_column(dep_column, self.board) then
            return false, string.format("Dependency '%s' is not complete", dep_id)
        end
    end

    return true
end

function WorkflowEngine:check_subtasks()
    local t = self.current_transition

    -- Only check for moves to completion columns
    if not t.target_column or not checker.is_completion_column(t.target_column, self.board) then
        return true
    end

    -- Check if task has subtasks
    if not t.card.properties.subtasks or #t.card.properties.subtasks == 0 then
        return true
    end

    -- Verify all subtasks are complete
    local incomplete = {}
    for _, subtask_id in ipairs(t.card.properties.subtasks) do
        local subtask, subtask_column = self.board:find_task(subtask_id)

        if not subtask then
            return false, string.format("Subtask '%s' not found", subtask_id)
        end

        if not checker.is_completion_column(subtask_column, self.board) then
            table.insert(incomplete, subtask_id)
        end
    end

    if #incomplete > 0 then
        return false, string.format(
            "Subtasks not complete: %s",
            table.concat(incomplete, ", ")
        )
    end

    return true
end

function WorkflowEngine:check_capacity()
    local t = self.current_transition

    -- Check WIP limits
    local config = self.board.config or {}
    local can_add, msg = checker.check_wip_limit{
        board = self.board,
        column = t.target_column_name,
        config = config
    }

    if not can_add then
        -- WIP limit exceeded - this is a warning, not an error
        return true, nil, msg
    end

    -- Check other capacity constraints
    local warnings = self:check_resource_availability(t.card, t.target_column)

    if #warnings > 0 then
        return true, nil, warnings
    end

    return true
end

function WorkflowEngine:check_resource_availability(card, target_column)
    local warnings = {}

    if not target_column then
        return warnings
    end

    -- Check test environment availability
    if target_column.name == "Testing" or target_column.name == "QA" then
        if self.board.config and self.board.config.test_environments then
            local available = self.board.config.test_environments.available or 0
            if available <= 0 then
                table.insert(warnings, "No test environments currently available")
            end
        end
    end

    -- Check reviewer availability
    if target_column.name == "Review" then
        if not card.properties.reviewer then
            -- Count reviewers
            local reviewers_busy = 0
            for _, col in ipairs(self.board.columns) do
                if col.name == "Review" then
                    reviewers_busy = #(col.cards or col.tasks or {})
                    break
                end
            end

            local total_reviewers = self.board.config and 
                                   self.board.config.reviewers and 
                                   #self.board.config.reviewers or 0

            if reviewers_busy >= total_reviewers then
                table.insert(warnings, "All reviewers are currently busy")
            end
        end
    end

    return warnings
end

-- State handlers
function WorkflowEngine:handle_approved()
    self.state = STATES.EXECUTING

    -- Create command for the move
    local t = self.current_transition
    local command = self:create_move_command(t)

    -- Execute with logging
    local success, result = pcall(command.execute, command)

    if self.command_log then
        self.command_log:add(command, {success = success, result = result}, {
            workflow_engine = self,
            transition = t,
            validation = self.validation_results
        })
    end

    self.state = STATES.READY
    self.current_transition = nil

    if success then
        return true, nil, nil, t.auto_move  -- Include auto_move flag
    else
        return false, result
    end
end

function WorkflowEngine:handle_denied()
    local errors = table.concat(self.validation_results.errors, "; ")

    self.state = STATES.READY
    self.current_transition = nil

    return false, errors
end

function WorkflowEngine:handle_warning()
    -- Store warnings for user override decision
    local warnings = self.validation_results.warnings

    -- Return warnings to caller for user decision
    return "warning", nil, warnings
end

-- User override for warnings
function WorkflowEngine:override_warnings()
    if self.state ~= STATES.WARNING then
        return false, "No warnings to override"
    end

    self.state = STATES.APPROVED
    return self:handle_approved()
end

-- Cancel transition with warnings
function WorkflowEngine:cancel_transition()
    if self.state ~= STATES.WARNING then
        return false, "No transition to cancel"
    end

    self.state = STATES.READY
    self.current_transition = nil

    return false, "Transition cancelled by user"
end

-- Helper: Evaluate workflow conditions
function WorkflowEngine:evaluate_condition(condition, card)
    -- Simple property-based conditions for now
    -- Format: "property == value" or "property != value"
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

-- Create move command with rollback support
function WorkflowEngine:create_move_command(transition)
    local execute_fn = function()
        -- Remove from source column
        local card = transition.source_column:remove_card(transition.card.id)
        if not card then
            error("Card not found in source column")
        end

        -- Add to target column (triggers on_enter events)
        transition.target_column:add_card(card)

        return true
    end

    local rollback_fn = function()
        -- Remove from target column
        local card = transition.target_column:remove_card(transition.card.id)
        if not card then
            return false, "Card not found in target column for rollback"
        end

        -- Add back to source column
        transition.source_column:add_card(card)

        return true
    end

    return Command:new(
        string.format("move_%s_%s_to_%s",
            transition.card.id,
            transition.source_column.name,
            transition.target_column_name),
        execute_fn,
        rollback_fn,
        {transition = transition}
    )
end

-- Get valid transitions for a card in its current column
function WorkflowEngine:get_valid_transitions(card, source_column)
    local workflow = self.board.config and self.board.config.workflow

    if not workflow then
        -- No workflow defined - return all columns except source
        local valid = {}
        for _, column in ipairs(self.board.columns) do
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
    if type(transitions) == "table" and #transitions > 0 then
        return transitions
    end

    -- Handle conditional transitions
    for target, config in pairs(transitions) do
        if type(config) == "table" and config.when then
            if self:evaluate_condition(config.when, card) then
                table.insert(valid, target)
            end
        else
            -- Simple string target or no condition
            table.insert(valid, target)
        end
    end

    return valid
end

return WorkflowEngine
