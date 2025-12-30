-- lua/kanban-md/validation_result.lua
-- Structured result object for workflow engine validation operations
-- Here's the structure of the ValidationResult class:
--
--   Core Properties:
--
--   {
--     success = boolean,        -- true/false for final success
--     state = string,          -- "approved", "denied", "warning"
--     errors = array,          -- list of error messages
--     warnings = array,        -- list of warning messages
--     passed_checks = array,   -- list of successful validations
--     auto_move = boolean,     -- flag for auto-move behavior
--     message = string         -- optional summary message
--   }
--
--   Factory Methods:
--
--   ValidationResult.success(options)    -- Creates approved result
--   ValidationResult.error(messages)     -- Creates denied result
--   ValidationResult.warning(messages)   -- Creates warning result
--
--   Helper Methods:
--
--   result:is_success()        -- boolean check
--   result:is_denied()         -- boolean check
--   result:is_warning()        -- boolean check
--   result:is_auto_move()      -- boolean check
--   result:get_error()         -- first error message
--   result:get_error_string()  -- all errors concatenated
--   result:get_warning_string() -- all warnings concatenated
--
--   Usage in WorkflowEngine:
--
--   The ValidationResult is imported and used in workflow_engine.lua:
--   local ValidationResult = require('kanban-md.validation_result')
--
--   -- All these methods now return ValidationResult objects:
--   function WorkflowEngine:validate_transition()
--   function WorkflowEngine:handle_denied()
--   function WorkflowEngine:handle_warning()
--   function WorkflowEngine:handle_approved()
--   function WorkflowEngine:request_move()
--   function WorkflowEngine:override_warnings()
--   function WorkflowEngine:cancel_transition()

local ValidationResult = {}
ValidationResult.__index = ValidationResult

-- Create a new ValidationResult
-- @param state string - "approved", "denied", "warning"
-- @param options table - optional parameters
--   - errors: array of error messages
--   - warnings: array of warning messages
--   - passed_checks: array of successful validation names
--   - auto_move: boolean flag for automatic transitions
--   - message: string summary message
function ValidationResult:new(state, options)
  options = options or {}

  local obj = {
    success = state == "approved",
    state = state,
    errors = options.errors or {},
    warnings = options.warnings or {},
    passed_checks = options.passed_checks or {},
    auto_move = options.auto_move or false,
    message = options.message
  }

  setmetatable(obj, ValidationResult)
  return obj
end

-- Static factory methods for common cases

function ValidationResult.success(options)
  return ValidationResult:new("approved", options)
end

function ValidationResult.error(error_messages, options)
  options = options or {}
  if type(error_messages) == "string" then
    error_messages = {error_messages}
  end
  options.errors = error_messages
  return ValidationResult:new("denied", options)
end

function ValidationResult.warning(warning_messages, options)
  options = options or {}
  if type(warning_messages) == "string" then
    warning_messages = {warning_messages}
  end
  options.warnings = warning_messages
  return ValidationResult:new("warning", options)
end

-- Check if the result represents a successful validation
function ValidationResult:is_success()
  return self.success
end

-- Check if the result represents a hard error/denial
function ValidationResult:is_denied()
  return self.state == "denied"
end

-- Check if the result has warnings requiring user decision
function ValidationResult:is_warning()
  return self.state == "warning"
end

-- Check if the result has auto-move flag set
function ValidationResult:is_auto_move()
  return self.auto_move
end

-- Get the primary error message (first error if multiple)
function ValidationResult:get_error()
  if #self.errors > 0 then
    return self.errors[1]
  end
  return nil
end

-- Get all errors as a concatenated string
function ValidationResult:get_error_string()
  if #self.errors > 0 then
    return table.concat(self.errors, "; ")
  end
  return nil
end

-- Get all warnings as a concatenated string
function ValidationResult:get_warning_string()
  if #self.warnings > 0 then
    return table.concat(self.warnings, "; ")
  end
  return nil
end

-- Add an error to the result
function ValidationResult:add_error(error_msg)
  table.insert(self.errors, error_msg)
  if self.state ~= "denied" then
    self.state = "denied"
    self.success = false
  end
end

-- Add a warning to the result
function ValidationResult:add_warning(warning_msg)
  table.insert(self.warnings, warning_msg)
  if self.state == "approved" then
    self.state = "warning"
    self.success = false
  end
end

-- Add a successful check to the result
function ValidationResult:add_passed_check(check_name)
  table.insert(self.passed_checks, check_name)
end

-- String representation for debugging
function ValidationResult:__tostring()
  local parts = {string.format("ValidationResult[%s]", self.state)}

  if #self.errors > 0 then
    table.insert(parts, string.format("errors: %s", table.concat(self.errors, ", ")))
  end

  if #self.warnings > 0 then
    table.insert(parts, string.format("warnings: %s", table.concat(self.warnings, ", ")))
  end

  if self.auto_move then
    table.insert(parts, "auto_move: true")
  end

  return table.concat(parts, " ")
end

return ValidationResult
