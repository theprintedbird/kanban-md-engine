-- tests/unit/task9_regressions_spec.lua
-- Regression tests for the Task 9 minor-issues batch (features/PLAN-config-fixes.md).
-- The batch commit landed the code changes; these specs pin the behaviour of
-- items 1, 2, 4, 5, 7 and 10, which had no dedicated coverage.

require('polyfills.vim')

local Board = require('kanban-md.board')
local helpers = require('helpers.setup')

local function parse_board(markdown)
  local board = Board:new()
  board:parse(markdown)
  return board
end

local function written(board)
  return table.concat(board:write(), "\n")
end

describe("Task 9 regressions", function()

  -- Item 1: config comment prefix is joined with a space, not property_separator
  it("writes config comments without a stray comma after the prefix", function()
    local board = parse_board(table.concat({
      "# Board",
      "<!-- kanban:config wip_limit: 5 -->",
      "",
      "###### Todo",
      "<!-- column:config wip_limit: 3 -->",
      "",
      "- A task",
      "",
      "###### Done",
      "",
    }, "\n"))

    local output = written(board)
    assert.truthy(output:find("<!-- kanban:config wip_limit: 5 -->", 1, true))
    assert.truthy(output:find("<!-- column:config wip_limit: 3 -->", 1, true))
    assert.falsy(output:find("kanban:config,", 1, true))
    assert.falsy(output:find("column:config,", 1, true))
  end)

  -- Item 2: multiple kanban:config comments merge instead of replacing wholesale
  it("merges multiple kanban:config comments, later keys overriding earlier ones", function()
    local board = parse_board(table.concat({
      "# Board",
      "<!-- kanban:config wip_limit: 5, auto_timestamp: false -->",
      "",
      "<!-- kanban:config wip_limit: 9 -->",
      "",
      "###### Todo",
      "",
      "###### Done",
      "",
    }, "\n"))

    assert.equals(9, board.config.wip_limit)          -- later comment wins
    assert.equals(false, board.config.auto_timestamp) -- earlier key kept
  end)

  -- Item 4: only real column timestamp keys are formatted as timestamps
  it("does not render large plain numbers as dates under timestamp_format iso", function()
    helpers.with_config({ timestamp_format = "iso" }, function()
      local board = parse_board(table.concat({
        "# Board",
        "",
        "###### Todo",
        "",
        "- Task <!-- todo: 1700000000, estimate: 1700000000 -->",
        "",
        "###### Done",
        "",
      }, "\n"))

      local output = written(board)
      -- the column timestamp renders as an ISO date...
      assert.truthy(output:find("todo: 2023-11-14T22:13:20Z", 1, true))
      -- ...while the non-timestamp numeric key stays numeric
      assert.truthy(output:find("estimate: 1700000000", 1, true))
    end)
  end)

  -- Item 5: authored key case is preserved through parse and write
  it("preserves the authored case of custom property keys", function()
    local board = parse_board(table.concat({
      "# Board",
      "",
      "###### Todo",
      "",
      "- Task <!-- dueDate: soon -->",
      "",
      "###### Done",
      "",
    }, "\n"))

    local card = board.columns[1].cards[1]
    assert.equals("soon", card.properties.dueDate)
    assert.truthy(written(board):find("dueDate: soon", 1, true))
  end)

  -- Item 7: completion timestamp is the LATEST entry into any completion column
  it("uses the latest completion-column timestamp for lead time", function()
    local board = parse_board(table.concat({
      "# Board",
      "",
      "###### Backlog",
      "<!-- column:config is_backlog_state: true -->",
      "",
      "###### Review",
      "<!-- column:config is_completion_state: true -->",
      "",
      "###### Done",
      "<!-- column:config is_completion_state: true -->",
      "",
      "- Task <!-- backlog: 1000, review: 2000, done: 3000 -->",
      "",
    }, "\n"))

    board:calculate_stats()
    assert.equals(1, #board.stats.lead_times)
    local lead = board.stats.lead_times[1]
    assert.equals(3000, lead.end_time)     -- latest completion entry, not earliest
    assert.equals("Done", lead.end_column)
    assert.equals(2000, lead.duration)     -- 3000 - 1000
  end)

  -- Item 10: an orphaned property comment before a column header is dropped,
  -- not applied to the next column's first card
  it("does not carry an orphaned property comment across a column boundary", function()
    local board = parse_board(table.concat({
      "# Board",
      "",
      "###### A",
      "",
      "- Task in A",
      "",
      "<!-- complexity: 9 -->",
      "###### B",
      "",
      "- First card of B",
      "",
    }, "\n"))

    local column_b = board:get_column_by_name("B")
    assert.is_not_nil(column_b)
    local first_card = column_b.cards[1]
    assert.equals("First card of B", first_card.text)
    assert.is_nil(first_card.properties.complexity)
  end)
end)
