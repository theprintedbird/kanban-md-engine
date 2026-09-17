-- tests/unit/validation_result_spec.lua
-- Unit tests for lua/kanban-md/validation_result.lua: the structured result
-- Board:validate_move() and the workflow engine hand back.
--
-- The three factories set a state, and the add_* mutators move that state on:
-- approved -> warning -> denied, one way only. That transition table is the
-- substance of the module and is what this file pins.
require('polyfills.vim')

local ValidationResult = require('kanban-md.validation_result')

describe("ValidationResult", function()
  describe("success()", function()
    it("is approved and successful, with everything else empty", function()
      local result = ValidationResult.success()

      assert.equals("approved", result.state)
      assert.is_true(result.success)
      assert.same({}, result.errors)
      assert.same({}, result.warnings)
      assert.same({}, result.passed_checks)
      assert.is_false(result.auto_move)
      assert.is_nil(result.message)
    end)

    it("carries the options it is given", function()
      local result = ValidationResult.success({
        passed_checks = { "wip_limit" },
        auto_move = true,
        message = "All clear",
      })

      assert.same({ "wip_limit" }, result.passed_checks)
      assert.is_true(result.auto_move)
      assert.equals("All clear", result.message)
    end)
  end)

  describe("error()", function()
    it("wraps a single message in a list and denies", function()
      local result = ValidationResult.error("WIP limit exceeded")

      assert.equals("denied", result.state)
      assert.is_false(result.success)
      assert.same({ "WIP limit exceeded" }, result.errors)
    end)

    it("takes a list of messages as it stands", function()
      local result = ValidationResult.error({ "First", "Second" })

      assert.same({ "First", "Second" }, result.errors)
    end)

    it("keeps the other options alongside the errors", function()
      local result = ValidationResult.error("Denied", { message = "Move refused" })

      assert.equals("Move refused", result.message)
      assert.same({ "Denied" }, result.errors)
    end)
  end)

  describe("warning()", function()
    it("wraps a single message in a list and is not successful", function()
      local result = ValidationResult.warning("Nearly at the limit")

      assert.equals("warning", result.state)
      assert.is_false(result.success)
      assert.same({ "Nearly at the limit" }, result.warnings)
      assert.same({}, result.errors)
    end)

    it("takes a list of messages as it stands", function()
      local result = ValidationResult.warning({ "First", "Second" })

      assert.same({ "First", "Second" }, result.warnings)
    end)
  end)

  describe("new()", function()
    it("treats only 'approved' as success", function()
      assert.is_true(ValidationResult:new("approved").success)
      assert.is_false(ValidationResult:new("denied").success)
      assert.is_false(ValidationResult:new("warning").success)
      assert.is_false(ValidationResult:new("anything else").success)
    end)

    it("gives each result its own tables", function()
      local first = ValidationResult.success()
      local second = ValidationResult.success()

      first:add_error("Only mine")

      assert.same({}, second.errors)
    end)
  end)

  describe("predicates", function()
    it("distinguishes the three states", function()
      local approved = ValidationResult.success()
      local denied = ValidationResult.error("No")
      local warned = ValidationResult.warning("Careful")

      assert.is_true(approved:is_success())
      assert.is_false(approved:is_denied())
      assert.is_false(approved:is_warning())

      assert.is_false(denied:is_success())
      assert.is_true(denied:is_denied())
      assert.is_false(denied:is_warning())

      assert.is_false(warned:is_success())
      assert.is_false(warned:is_denied())
      assert.is_true(warned:is_warning())
    end)

    it("reports the auto_move flag", function()
      assert.is_false(ValidationResult.success():is_auto_move())
      assert.is_true(ValidationResult.success({ auto_move = true }):is_auto_move())
    end)
  end)

  describe("message accessors", function()
    it("return nil when there is nothing to report", function()
      local result = ValidationResult.success()

      assert.is_nil(result:get_error())
      assert.is_nil(result:get_error_string())
      assert.is_nil(result:get_warning_string())
    end)

    it("get_error() gives the first error only", function()
      local result = ValidationResult.error({ "First", "Second" })

      assert.equals("First", result:get_error())
    end)

    it("join multiple messages with a semicolon", function()
      local denied = ValidationResult.error({ "First", "Second" })
      local warned = ValidationResult.warning({ "One", "Two" })

      assert.equals("First; Second", denied:get_error_string())
      assert.equals("One; Two", warned:get_warning_string())
    end)
  end)

  describe("state transitions", function()
    it("add_error() takes an approved result to denied", function()
      local result = ValidationResult.success()

      result:add_error("Something broke")

      assert.equals("denied", result.state)
      assert.is_false(result.success)
      assert.same({ "Something broke" }, result.errors)
    end)

    it("add_error() takes a warning result to denied", function()
      local result = ValidationResult.warning("Careful")

      result:add_error("Something broke")

      assert.equals("denied", result.state)
      assert.is_false(result.success)
      assert.same({ "Careful" }, result.warnings)
    end)

    it("add_warning() takes an approved result to warning", function()
      local result = ValidationResult.success()

      result:add_warning("Careful")

      assert.equals("warning", result.state)
      assert.is_false(result.success)
      assert.same({ "Careful" }, result.warnings)
    end)

    it("add_warning() does not soften a denied result", function()
      local result = ValidationResult.error("Denied")

      result:add_warning("Careful")

      assert.equals("denied", result.state)
      assert.is_false(result.success)
      assert.same({ "Careful" }, result.warnings)
    end)

    it("accumulates repeated errors and warnings", function()
      local result = ValidationResult.success()

      result:add_warning("First warning")
      result:add_warning("Second warning")
      result:add_error("First error")
      result:add_error("Second error")

      assert.same({ "First warning", "Second warning" }, result.warnings)
      assert.same({ "First error", "Second error" }, result.errors)
      assert.equals("denied", result.state)
    end)

    it("never returns to approved once it has left", function()
      local result = ValidationResult.success()

      result:add_warning("Careful")
      result:add_passed_check("wip_limit")

      assert.equals("warning", result.state)
      assert.is_false(result:is_success())
    end)

    it("add_passed_check() records checks without changing state", function()
      local result = ValidationResult.success()

      result:add_passed_check("wip_limit")
      result:add_passed_check("dependencies")

      assert.same({ "wip_limit", "dependencies" }, result.passed_checks)
      assert.equals("approved", result.state)
      assert.is_true(result.success)
    end)
  end)

  describe("tostring", function()
    it("names the state", function()
      assert.equals("ValidationResult[approved]", tostring(ValidationResult.success()))
    end)

    it("lists errors and warnings", function()
      local result = ValidationResult.error({ "First", "Second" })
      result:add_warning("Careful")

      assert.equals(
        "ValidationResult[denied] errors: First, Second warnings: Careful",
        tostring(result)
      )
    end)

    it("notes an auto move", function()
      local result = ValidationResult.success({ auto_move = true })

      assert.equals("ValidationResult[approved] auto_move: true", tostring(result))
    end)
  end)
end)
