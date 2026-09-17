-- tests/unit/extras/capacity_triggers_spec.lua
-- Unit tests for lua/kanban-md/extras/capacity_triggers.lua and for the
-- board.lua branch that registers the points trigger.
--
-- Each factory returns an on_checking execute_fn(column, context) that reports
-- an over-capacity condition as (true, nil, warning): capacity is advisory,
-- never a refusal, so every one of these returns true as its first value.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local capacity_triggers = require('kanban-md.extras.capacity_triggers')

--- A column stub with cards carrying the given property tables.
local function column(name, card_properties, config)
  local cards = {}
  for i, properties in ipairs(card_properties or {}) do
    table.insert(cards, { id = name .. "-" .. i, properties = properties })
  end
  return { name = name, cards = cards, config = config or {} }
end

--- A context moving a card with `properties` into `target`.
local function context_for(target, properties, board)
  return {
    card = { properties = properties or {} },
    target_column = target,
    source_column = nil,
    board = board or { columns = { target }, config = {} },
  }
end

describe("capacity_triggers", function()
  describe("create_capacity_points_trigger", function()
    it("stays quiet while the column is under capacity", function()
      local trigger = capacity_triggers.create_capacity_points_trigger(10)
      local target = column("In Progress", { { points = 3 } })

      local ok, err, warning = trigger(nil, context_for(target, { points = 2 }))

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_nil(warning)
    end)

    it("stays quiet at exactly the limit", function()
      local trigger = capacity_triggers.create_capacity_points_trigger(10)
      local target = column("In Progress", { { points = 8 } })

      local _, _, warning = trigger(nil, context_for(target, { points = 2 }))

      assert.is_nil(warning)
    end)

    it("warns, without refusing, when the card would take it over", function()
      local trigger = capacity_triggers.create_capacity_points_trigger(10)
      local target = column("In Progress", { { points = 8 } })

      local ok, err, warning = trigger(nil, context_for(target, { points = 5 }))

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("Column capacity exceeded: 8 + 5 > 10 points", warning)
    end)

    it("counts cards with no points as zero", function()
      local trigger = capacity_triggers.create_capacity_points_trigger(1)
      local target = column("In Progress", { {}, {}, {} })

      local _, _, warning = trigger(nil, context_for(target, {}))

      assert.is_nil(warning)
    end)

    it("sums the points already in the target column", function()
      local trigger = capacity_triggers.create_capacity_points_trigger(5)
      local target = column("In Progress", { { points = 2 }, { points = 2 }, { points = 2 } })

      local _, _, warning = trigger(nil, context_for(target, {}))

      assert.matches("6 %+ 0 > 5 points", warning)
    end)
  end)

  describe("create_capacity_points_trigger registration (board.lua)", function()
    local function board_with_capacity(capacity)
      local board = Board:new()
      local todo = board:add_column("col_todo", "To Do")
      todo.config.capacity = capacity
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      board:auto_register_triggers()

      return board, todo
    end

    it("registers the points trigger when capacity.max_points is set", function()
      local _, todo = board_with_capacity({ max_points = 8 })

      assert.is_function(todo:get_triggers("on_checking")["capacity_points"])
    end)

    it("does not register it without a capacity config", function()
      local _, todo = board_with_capacity(nil)

      assert.is_nil(todo:get_triggers("on_checking")["capacity_points"])
    end)

    it("does not register it when capacity omits max_points", function()
      local _, todo = board_with_capacity({ max_cards = 3 })

      assert.is_nil(todo:get_triggers("on_checking")["capacity_points"])
    end)

    it("registers it with the column's own limit", function()
      local _, todo = board_with_capacity({ max_points = 4 })
      local registered = todo:get_triggers("on_checking")["capacity_points"]

      local target = column("To Do", { { points = 3 } })
      local _, _, warning = registered(todo, context_for(target, { points = 3 }))

      assert.equals("Column capacity exceeded: 3 + 3 > 4 points", warning)
    end)

    it("lets an over-capacity move through, warning only", function()
      local board, todo = board_with_capacity({ max_points = 1 })
      local done = board:get_column_by_name("Done")
      local card = Card:new("card-over", "Heavy card", { points = 99 })

      todo:add_card(card, { board = board, target_column = todo })

      assert.is_true(board:move_card(card, todo, done))
      assert.equals(0, #todo.cards)
      assert.equals(1, #done.cards)
    end)
  end)

  describe("create_reviewer_capacity_trigger", function()
    local function review_board(review_cards, reviewers)
      local review = column("In Review", review_cards)
      return {
        columns = { column("To Do"), review, column("Done") },
        config = { reviewers = reviewers },
      }, review
    end

    it("ignores columns that are not review columns", function()
      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local board = review_board({}, {})
      local target = column("To Do")

      local ok, _, warning = trigger(nil, context_for(target, {}, board))

      assert.is_true(ok)
      assert.is_nil(warning)
    end)

    it("stays quiet while a reviewer is free", function()
      local board, review = review_board({ { reviewer = "alice" } }, { "alice", "bob" })

      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(review, {}, board))

      assert.is_nil(warning)
    end)

    it("warns when every reviewer is busy", function()
      local board, review = review_board(
        { { reviewer = "alice" }, { reviewer = "bob" } },
        { "alice", "bob" }
      )

      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local ok, err, warning = trigger(nil, context_for(review, {}, board))

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("All reviewers are currently busy", warning)
    end)

    it("counts cards without a reviewer as not occupying anyone", function()
      local board, review = review_board({ {}, {} }, { "alice" })

      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(review, {}, board))

      assert.is_nil(warning)
    end)

    it("warns when the board declares no reviewers at all", function()
      local board, review = review_board({}, nil)

      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(review, {}, board))

      assert.equals("All reviewers are currently busy", warning)
    end)

    it("counts busy reviewers across every review column", function()
      local first = column("Code Review", { { reviewer = "alice" } })
      local second = column("Design Review", { { reviewer = "bob" } })
      local board = {
        columns = { column("To Do"), first, second },
        config = { reviewers = { "alice", "bob" } },
      }

      local trigger = capacity_triggers.create_reviewer_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(second, {}, board))

      assert.equals("All reviewers are currently busy", warning)
    end)
  end)

  describe("create_velocity_capacity_trigger", function()
    --- todo/doing are work-in-progress, done is the completion column.
    local function velocity_board(todo_cards, doing_cards, done_cards)
      local todo = column("To Do", todo_cards)
      local doing = column("In Progress", doing_cards)
      local done = column("Done", done_cards, { is_completion_state = true })
      return { columns = { todo, doing, done }, config = {} }, todo, doing, done
    end

    it("ignores moves into the completion column", function()
      local board, _, _, done = velocity_board({ { points = 50 } }, {}, {})

      local trigger = capacity_triggers.create_velocity_capacity_trigger(10)
      local _, _, warning = trigger(nil, context_for(done, { points = 50 }, board))

      assert.is_nil(warning)
    end)

    it("ignores moves into the archive", function()
      local board = velocity_board({ { points = 50 } }, {}, {})
      local archive = column("__ARCHIVE__")
      table.insert(board.columns, archive)

      local trigger = capacity_triggers.create_velocity_capacity_trigger(10)
      local _, _, warning = trigger(nil, context_for(archive, { points = 50 }, board))

      assert.is_nil(warning)
    end)

    it("stays quiet while the team is under its velocity", function()
      local board, _, doing = velocity_board({ { points = 2 } }, { { points = 3 } }, {})

      local trigger = capacity_triggers.create_velocity_capacity_trigger(10)
      local ok, _, warning = trigger(nil, context_for(doing, { points = 1 }, board))

      assert.is_true(ok)
      assert.is_nil(warning)
    end)

    it("warns when in-progress points would exceed the velocity", function()
      local board, _, doing = velocity_board({ { points = 5 } }, { { points = 4 } }, {})

      local trigger = capacity_triggers.create_velocity_capacity_trigger(10)
      local ok, err, warning = trigger(nil, context_for(doing, { points = 3 }, board))

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("Team velocity capacity exceeded: 9 + 3 > 10 points", warning)
    end)

    it("excludes completed and archived points from the total", function()
      local board, _, doing = velocity_board({ { points = 1 } }, {}, { { points = 100 } })
      table.insert(board.columns, column("__ARCHIVE__", { { points = 100 } }))

      local trigger = capacity_triggers.create_velocity_capacity_trigger(10)
      local _, _, warning = trigger(nil, context_for(doing, { points = 1 }, board))

      assert.is_nil(warning)
    end)
  end)

  describe("create_skill_capacity_trigger", function()
    local function skills_board(team_members, in_progress_cards)
      local doing = column("In Progress", in_progress_cards)
      local done = column("Done", {}, { is_completion_state = true })
      return { columns = { doing, done }, config = { team_members = team_members } }, doing
    end

    it("passes a card that requires no skills", function()
      local board, doing = skills_board({}, {})

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local ok, _, warning = trigger(nil, context_for(doing, {}, board))

      assert.is_true(ok)
      assert.is_nil(warning)
    end)

    it("passes a card whose required_skills list is empty", function()
      local board, doing = skills_board({}, {})

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(doing, { required_skills = {} }, board))

      assert.is_nil(warning)
    end)

    it("stays quiet when a skilled member is free", function()
      local board, doing = skills_board({ { name = "alice", skills = { "lua", "docs" } } }, {})

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(doing, { required_skills = { "lua" } }, board))

      assert.is_nil(warning)
    end)

    it("requires a member to have every listed skill", function()
      local board, doing = skills_board({ { name = "alice", skills = { "lua" } } }, {})

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(doing, {
        required_skills = { "lua", "design" },
      }, board))

      assert.equals("No team members available with required skills: lua, design", warning)
    end)

    it("warns when the only skilled member is already assigned work", function()
      local board, doing = skills_board(
        { { name = "alice", skills = { "lua" } } },
        { { assignee = "alice" } }
      )

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local ok, err, warning = trigger(nil, context_for(doing, { required_skills = { "lua" } }, board))

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("No team members available with required skills: lua", warning)
    end)

    it("does not count completed work as making a member busy", function()
      local board, doing = skills_board({ { name = "alice", skills = { "lua" } } }, {})
      board.columns[2].cards = { { properties = { assignee = "alice" } } }

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(doing, { required_skills = { "lua" } }, board))

      assert.is_nil(warning)
    end)

    it("warns when the board declares no team members", function()
      local board, doing = skills_board(nil, {})

      local trigger = capacity_triggers.create_skill_capacity_trigger()
      local _, _, warning = trigger(nil, context_for(doing, { required_skills = { "lua" } }, board))

      assert.equals("No team members available with required skills: lua", warning)
    end)
  end)
end)
