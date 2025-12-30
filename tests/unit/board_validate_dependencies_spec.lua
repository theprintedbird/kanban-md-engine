-- Unit tests for Board:validate_dependencies()
require('polyfills.vim')
_G._TEST = true
local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')

describe("Board:validate_dependencies()", function()
  local board, todo_column, done_column

  before_each(function()
    board = Board:new()
    board.title = "Test Board"
    todo_column = board:add_column("todo", "To Do")
    done_column = board:add_column("done", "Done")
    -- Mark done column as completion column
    local TypeConverter = require("kanban-md.type_converter")
    done_column.config = TypeConverter:new({is_completion_state = true})
  end)

  after_each(function()
    board = nil
    todo_column = nil
    done_column = nil
    collectgarbage("collect")
  end)

  describe("missing dependencies", function()
    it("should detect missing dependencies", function()
      local card = Card:new("card_1", "Task with missing dep", {id = "card_1", depends_on = {"missing_id"}})
      card.id = "card_1"
      card.properties.id = "card_1"
      card.properties.depends_on = {"missing_id"}
      todo_column:add_card(card)

      local result = board:validate_dependencies()

      assert.is_false(result:is_success())
      assert.is_true(#result.errors > 0)
      assert.matches("missing dependency", result.errors[1])
      assert.matches("missing_id", result.errors[1])
    end)

    it("should detect multiple missing dependencies", function()
      local card = Card:new("card_1", "Task", {id = "card_1", depends_on = {"missing_1", "missing_2"}})
      card.id = "card_1"
      card.properties.id = "card_1"
      card.properties.depends_on = {"missing_1", "missing_2"}
      todo_column:add_card(card)

      local result = board:validate_dependencies()

      assert.is_false(result:is_success())
      assert.are.equals(2, #result.errors)
      assert.matches("missing_1", result.errors[1])
      assert.matches("missing_2", result.errors[2])
    end)
  end)

  describe("circular dependencies", function()
    it("should detect simple circular dependency", function()
      local card1 = Card:new("card_1", "Task 1", {id = "card_1", depends_on = {"card_2"}})
      card1.id = "card_1"
      card1.properties.id = "card_1"
      card1.properties.depends_on = {"card_2"}

      local card2 = Card:new("card_2", "Task 2", {id = "card_2", depends_on = {"card_1"}})
      card2.id = "card_2"
      card2.properties.id = "card_2"
      card2.properties.depends_on = {"card_1"}

      todo_column:add_card(card1)
      todo_column:add_card(card2)

      local result = board:validate_dependencies()

      assert.is_false(result:is_success())
      assert.is_true(#result.errors > 0)
      assert.matches("Circular dependency", result.errors[1])
    end)

    it("should detect longer circular dependency chain", function()
      local card1 = Card:new("card_1", "Task 1", {id = "card_1", depends_on = {"card_2"}})
      card1.id = "card_1"
      card1.properties.id = "card_1"
      card1.properties.depends_on = {"card_2"}

      local card2 = Card:new("card_2", "Task 2", {id = "card_2", depends_on = {"card_3"}})
      card2.id = "card_2"
      card2.properties.id = "card_2"
      card2.properties.depends_on = {"card_3"}

      local card3 = Card:new("card_3", "Task 3", {id = "card_3", depends_on = {"card_1"}})
      card3.id = "card_3"
      card3.properties.id = "card_3"
      card3.properties.depends_on = {"card_1"}

      todo_column:add_card(card1)
      todo_column:add_card(card2)
      todo_column:add_card(card3)

      local result = board:validate_dependencies()

      assert.is_false(result:is_success())
      assert.is_true(#result.errors > 0)
      assert.matches("Circular dependency", result.errors[1])
    end)
  end)

  describe("completion state consistency", function()
    it("should warn when complete card depends on incomplete card", function()
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      dep.properties.id = "dep_1"
      todo_column:add_card(dep)

      local complete_card = Card:new("card_1", "Complete task", {id = "card_1", depends_on = {"dep_1"}})
      complete_card.id = "card_1"
      complete_card.properties.id = "card_1"
      complete_card.properties.depends_on = {"dep_1"}
      done_column:add_card(complete_card)

      local result = board:validate_dependencies()

      -- Should have warnings but no errors
      -- Note: ValidationResult treats warnings as state="warning" with success=false
      -- So we check for no errors and presence of warnings instead
      assert.are.equals(0, #result.errors)
      assert.is_true(#result.warnings > 0)
      assert.matches("Complete card", result.warnings[1])
      assert.matches("incomplete", result.warnings[1])
    end)

    it("should not warn when complete card depends on complete card", function()
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      dep.properties.id = "dep_1"
      done_column:add_card(dep)

      local complete_card = Card:new("card_1", "Complete task", {id = "card_1", depends_on = {"dep_1"}})
      complete_card.id = "card_1"
      complete_card.properties.id = "card_1"
      complete_card.properties.depends_on = {"dep_1"}
      done_column:add_card(complete_card)

      local result = board:validate_dependencies()

      assert.is_true(result:is_success())
      assert.are.equals(0, #result.errors)
      assert.are.equals(0, #result.warnings)
    end)

    it("should not warn when incomplete card depends on incomplete card", function()
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      dep.properties.id = "dep_1"
      todo_column:add_card(dep)

      local card = Card:new("card_1", "Task", {id = "card_1", depends_on = {"dep_1"}})
      card.id = "card_1"
      card.properties.id = "card_1"
      card.properties.depends_on = {"dep_1"}
      todo_column:add_card(card)

      local result = board:validate_dependencies()

      assert.is_true(result:is_success())
      assert.are.equals(0, #result.errors)
      assert.are.equals(0, #result.warnings)
    end)
  end)

  describe("valid dependency structures", function()
    it("should pass validation for valid dependency chain", function()
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      dep.properties.id = "dep_1"
      done_column:add_card(dep)

      local card = Card:new("card_1", "Task", {id = "card_1", depends_on = {"dep_1"}})
      card.id = "card_1"
      card.properties.id = "card_1"
      card.properties.depends_on = {"dep_1"}
      todo_column:add_card(card)

      local result = board:validate_dependencies()

      assert.is_true(result:is_success())
      assert.are.equals(0, #result.errors)
      assert.are.equals(0, #result.warnings)
    end)

    it("should pass validation for cards without dependencies", function()
      local card1 = Card:new("card_1", "Task 1", {id = "card_1"})
      card1.id = "card_1"
      card1.properties.id = "card_1"
      todo_column:add_card(card1)

      local card2 = Card:new("card_2", "Task 2", {id = "card_2"})
      card2.id = "card_2"
      card2.properties.id = "card_2"
      done_column:add_card(card2)

      local result = board:validate_dependencies()

      assert.is_true(result:is_success())
      assert.are.equals(0, #result.errors)
      assert.are.equals(0, #result.warnings)
    end)

    it("should handle empty board", function()
      local result = board:validate_dependencies()

      assert.is_true(result:is_success())
      assert.are.equals(0, #result.errors)
      assert.are.equals(0, #result.warnings)
    end)
  end)

  describe("complex scenarios", function()
    it("should handle multiple errors and warnings", function()
      -- Card with missing dependency
      local card1 = Card:new("card_1", "Task 1", {id = "card_1", depends_on = {"missing"}})
      card1.id = "card_1"
      card1.properties.id = "card_1"
      card1.properties.depends_on = {"missing"}
      todo_column:add_card(card1)

      -- Complete card with incomplete dependency (warning)
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      dep.properties.id = "dep_1"
      todo_column:add_card(dep)

      local card2 = Card:new("card_2", "Task 2", {id = "card_2", depends_on = {"dep_1"}})
      card2.id = "card_2"
      card2.properties.id = "card_2"
      card2.properties.depends_on = {"dep_1"}
      done_column:add_card(card2)

      local result = board:validate_dependencies()

      assert.is_false(result:is_success())
      assert.are.equals(1, #result.errors)
      assert.are.equals(1, #result.warnings)
      assert.matches("missing", result.errors[1])
      assert.matches("incomplete", result.warnings[1])
    end)
  end)
end)
