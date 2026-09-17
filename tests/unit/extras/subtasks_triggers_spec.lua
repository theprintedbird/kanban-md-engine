-- tests/unit/extras/subtasks_triggers_spec.lua
-- Unit tests for lua/kanban-md/extras/subtasks_triggers.lua.
--
-- The behaviour is covered end-to-end by subtask_validation_spec.lua and
-- dependency_validation_spec.lua; this file tests the module itself, so the
-- enforcement modes and the exact messages are pinned without a board move in
-- the way.
--
-- Both factories return an on_checking execute_fn(column, context) yielding a
-- Triggerable result table. Note find_task() matches on properties.id, not on
-- the Card's own id, so the fixtures below set both.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local subtasks_triggers = require('kanban-md.extras.subtasks_triggers')

--- A three-column board: To Do, In Progress and a completion column, Done.
local function make_board()
  local board = Board:new()
  local todo = board:add_column("col_todo", "To Do")
  local doing = board:add_column("col_doing", "In Progress")
  local done = board:add_column("col_done", "Done")
  done.config.is_completion_state = true
  return board, todo, doing, done
end

--- Put a card carrying `id` (and any extra properties) into `column`.
local function place(column, id, properties)
  properties = properties or {}
  properties.id = id
  local card = Card:new(id, id, properties)
  table.insert(column.cards, card)
  return card
end

--- The on_checking context for moving `card` into `target`.
local function context_for(board, card, target)
  return { card = card, target_column = target, board = board }
end

describe("subtasks_triggers", function()
  describe("register_property_types", function()
    it("registers subtasks and depends_on as array properties", function()
      local TypeConverter = require('kanban-md.type_converter')

      subtasks_triggers.register_property_types()

      local converted = TypeConverter:new({ subtasks = "a, b", depends_on = "c" })

      assert.same({ "a", "b" }, converted.subtasks)
      assert.same({ "c" }, converted.depends_on)
    end)
  end)

  describe("create_subtask_trigger", function()
    it("passes a move into a non-completion column", function()
      local board, todo, doing = make_board()
      local card = place(todo, "parent", { subtasks = { "child" } })

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, doing))

      assert.is_true(result.success)
    end)

    it("passes a card with no subtasks", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "solo")

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
    end)

    it("passes a card whose subtasks list is empty", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "parent", { subtasks = {} })

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
    end)

    it("passes when every subtask is already complete", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "parent", { subtasks = { "child-1", "child-2" } })
      place(done, "child-1")
      place(done, "child-2")

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
      assert.same({}, result.warnings)
    end)

    it("blocks completion in strict mode, listing the incomplete subtask", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "parent", { subtasks = { "child-1" } })
      place(doing, "child-1")

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      assert.is_false(result.success)
      assert.equals(
        "Cannot complete: 1 subtask still incomplete (child-1). Complete it first.",
        result.errors[1]
      )
    end)

    it("pluralises the message for several incomplete subtasks", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "parent", { subtasks = { "child-1", "child-2" } })
      place(doing, "child-1")
      place(doing, "child-2")

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      assert.equals(
        "Cannot complete: 2 subtasks still incomplete (child-1, child-2). Complete them first.",
        result.errors[1]
      )
    end)

    it("warns instead of blocking in warn mode", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "parent", { subtasks = { "child-1" } })
      place(doing, "child-1")

      local result = subtasks_triggers.create_subtask_trigger("warn")(nil, context_for(board, card, done))

      assert.is_true(result.success)
      assert.matches("1 subtask still incomplete %(child%-1%)", result.warnings[1])
      assert.same({}, result.errors)
    end)

    it("defaults to strict for an unrecognised mode", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "parent", { subtasks = { "child-1" } })
      place(doing, "child-1")

      local result = subtasks_triggers.create_subtask_trigger(nil)(nil, context_for(board, card, done))

      assert.is_false(result.success)
    end)

    it("errors on a missing subtask even in warn mode", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "parent", { subtasks = { "ghost" } })

      local result = subtasks_triggers.create_subtask_trigger("warn")(nil, context_for(board, card, done))

      assert.is_false(result.success)
      assert.equals("Subtask 'ghost' not found", result.errors[1])
    end)

    it("treats an archived subtask as incomplete", function()
      local Column = require('kanban-md.column')
      local board, todo, _, done = make_board()
      board.archive = Column:new("__ARCHIVE__", "__ARCHIVE__")
      board.archive.is_archive = true
      local card = place(todo, "parent", { subtasks = { "child-1" } })
      place(board.archive, "child-1")

      local result = subtasks_triggers.create_subtask_trigger("strict")(nil, context_for(board, card, done))

      -- The archive is not a completion column, so a subtask parked there does
      -- not count as done.
      assert.is_false(result.success)
      assert.matches("child%-1", result.errors[1])
    end)
  end)

  describe("create_dependency_trigger", function()
    it("passes a move into a non-completion column", function()
      local board, todo, doing = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker" } })

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, doing))

      assert.is_true(result.success)
    end)

    it("passes a card with no dependencies", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "solo")

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
    end)

    it("passes a card whose depends_on list is empty", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "dependent", { depends_on = {} })

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
    end)

    it("passes when every dependency is complete", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker-1", "blocker-2" } })
      place(done, "blocker-1")
      place(done, "blocker-2")

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, done))

      assert.is_true(result.success)
    end)

    it("blocks in strict mode, naming the column the dependency sits in", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker" } })
      place(doing, "blocker")

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, done))

      assert.is_false(result.success)
      assert.equals(
        "Cannot complete: dependency 'blocker' is not done (currently in 'In Progress'). Complete it first.",
        result.errors[1]
      )
    end)

    it("warns instead of blocking in warn mode", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker" } })
      place(doing, "blocker")

      local result = subtasks_triggers.create_dependency_trigger("warn")(nil, context_for(board, card, done))

      assert.is_true(result.success)
      assert.matches("dependency 'blocker' is not done", result.warnings[1])
    end)

    it("defaults to strict for an unrecognised mode", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker" } })
      place(doing, "blocker")

      local result = subtasks_triggers.create_dependency_trigger("off")(nil, context_for(board, card, done))

      assert.is_false(result.success)
    end)

    it("errors on a missing dependency even in warn mode", function()
      local board, todo, _, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "ghost" } })

      local result = subtasks_triggers.create_dependency_trigger("warn")(nil, context_for(board, card, done))

      assert.is_false(result.success)
      assert.equals("Dependency 'ghost' not found", result.errors[1])
    end)

    it("reports the first incomplete dependency and stops there", function()
      local board, todo, doing, done = make_board()
      local card = place(todo, "dependent", { depends_on = { "blocker-1", "blocker-2" } })
      place(doing, "blocker-1")
      place(doing, "blocker-2")

      local result = subtasks_triggers.create_dependency_trigger("strict")(nil, context_for(board, card, done))

      assert.equals(1, #result.errors)
      assert.matches("'blocker%-1'", result.errors[1])
    end)
  end)
end)
