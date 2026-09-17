-- tests/unit/virtual_text_spec.lua
-- Unit tests for lua/kanban-md/virtual_text.lua
--
-- virtual_text.lua talks to the adapter rather than to Neovim directly
-- (create_namespace/clear_namespace/set_extmark/supports_virtual_text), so it
-- is testable in standalone Lua with a mock adapter -- no #neovim-only tag.
--
-- adapter_registry is a module singleton shared by every spec file in a
-- `busted` run, so the registered adapter is saved and restored around this
-- file rather than left pointing at the mock.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local Column = require('kanban-md.column')
local adapter_registry = require('kanban-md.adapter_registry')
local virtual_text = require('kanban-md.virtual_text')

describe("virtual_text", function()
  local mock_calls = {}
  local mock_adapter
  local previous_adapter

  -- Helper to find text in extmark calls
  local function find_extmark_text(calls)
    for _, call in ipairs(calls) do
      if call.text then
        return call.text
      end
    end
    return ""
  end

  local DAY = 86400

  -- A board with one column of each kind the metrics code distinguishes, all
  -- stated explicitly so none of the positional fallbacks in
  -- helpers/column.lua are in play.
  local function metrics_board()
    local board = Board:new()
    board.title = "Test Board"
    board.title_line = 1

    local backlog = board:add_column("col_backlog", "Backlog")
    backlog.config.is_backlog_state = true
    backlog.line_number = 2

    local in_progress = board:add_column("col_in_progress", "In Progress")
    in_progress.config.is_start_state = true
    in_progress.line_number = 3

    local blocked = board:add_column("col_blocked", "Blocked")
    blocked.config.is_blocked_state = true
    blocked.line_number = 4

    local done = board:add_column("col_done", "Done")
    done.config.is_completion_state = true
    done.line_number = 5

    return board, backlog, in_progress, blocked, done
  end

  --- Put a card with the given timestamp properties in `column`.
  local function add_card(column, properties, line_number)
    local card = Card:new("card-" .. tostring(#column.cards + 1), "A card", properties)
    card.line_number = line_number or 6
    table.insert(column.cards, card)
    return card
  end

  --- Render the board and return every emitted virtual-text line joined, so a
  --- single assertion can ask what the user would see.
  local function rendered_text(board)
    board:calculate_stats()
    virtual_text.update_virtual_text(board, 0)

    local lines = {}
    for _, call in ipairs(mock_calls) do
      table.insert(lines, call.text)
    end
    return table.concat(lines, "\n")
  end

  setup(function()
    previous_adapter = adapter_registry.has_adapter()
      and adapter_registry.get_adapter()
      or nil
  end)

  teardown(function()
    -- Restore whatever was registered before this file ran (nil included), so
    -- later spec files are not left talking to the mock.
    adapter_registry.set_adapter(previous_adapter)
  end)

  before_each(function()
    mock_calls = {}

    mock_adapter = {
      supports_virtual_text = function(self) return true end,
      create_namespace = function(self, name) return 1 end,
      clear_namespace = function(self, bufnr, ns, opts) end,
      set_extmark = function(self, bufnr, ns_id, line, col, opts)
        -- Join every virt_text segment: a card's metrics are emitted as
        -- several chunks (lead, separator, cycle, blocked breakdown) and the
        -- assertions below are about the line as the user reads it.
        local segments = {}
        for _, chunk in ipairs(opts.virt_text or {}) do
          table.insert(segments, chunk[1])
        end

        table.insert(mock_calls, {
          bufnr = bufnr,
          line = line,
          text = table.concat(segments)
        })
      end,
    }

    adapter_registry.set_adapter(mock_adapter)
  end)

  it("displays WIP warning when limit exceeded", function()
    local board = Board:new()
    board.title = "Test Board"
    board.title_line = 1

    local todo = board:add_column("col_todo", "To Do")
    todo.line_number = 2
    local done = board:add_column("col_done", "Done")
    done.config.is_completion_state = true
    done.line_number = 3
    todo.config.wip_limit = 1

    board:auto_register_triggers()

    -- Add cards directly to column's cards array to bypass WIP checking
    local card1 = Card:new("existing-1", "Existing card", {})
    local card2 = Card:new("breaks-wip-1", "WIP exceeded card", {})
    table.insert(todo.cards, card1)
    table.insert(todo.cards, card2)

    board:calculate_stats()

    virtual_text.update_virtual_text(board, 0)

    assert.is_true(#mock_calls > 0, "Expected at least one extmark call")
    local found = false
    for _, call in ipairs(mock_calls) do
      if call.text:match("⚠") and call.text:match("WIP") then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected to find WIP warning in extmark calls")
  end)

  it("displays lead time metrics", function()
    local board = Board:new()
    board.title = "Test Board"

    local todo = board:add_column("col_todo", "To Do")
    todo.line_number = 2
    local done = board:add_column("col_done", "Done")
    done.config.is_completion_state = true
    done.line_number = 3

    board:auto_register_triggers()

    -- Add completed cards with timestamps and line numbers
    local card1 = Card:new("card-1", "Completed card", {
      to_do = os.time() - 86400 * 5,  -- 5 days ago
      done = os.time(),
    })
    card1.line_number = 4  -- Set line number so virtual text knows where to display
    table.insert(done.cards, card1)

    board:calculate_stats()

    virtual_text.update_virtual_text(board, 0)

    assert.is_true(#mock_calls > 0, "Expected at least one extmark call")
    local text = find_extmark_text(mock_calls)
    assert.matches("Lead", text)
  end)

  it("gracefully degrades when adapter doesn't support virtual text", function()
    -- Create adapter that doesn't support virtual text
    local no_vt_adapter = {
      supports_virtual_text = function() return false end,
    }
    adapter_registry.set_adapter(no_vt_adapter)

    local board = Board:new()
    board.title = "Test Board"

    -- Should not error
    assert.has_no.errors(function()
      virtual_text.update_virtual_text(board, 0)
    end)

    -- Should not have created any extmarks
    assert.are.equals(0, #mock_calls)
  end)
  describe("cycle time", function()
    it("displays the cycle time alongside the lead time", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - 10 * DAY,
        in_progress = os.time() - 4 * DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("Lead %(Backlog → Done%): 10 days", text)
      assert.matches("Cycle %(In Progress → Done%): 4 days", text)
    end)

    it("reports N/A when the card never reached the start column", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - 3 * DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("Lead ", text)
      assert.matches("Cycle: N/A", text)
    end)

    it("breaks out active and blocked time when a blocked column was visited", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - 10 * DAY,
        in_progress = os.time() - 4 * DAY,
        blocked = os.time() - 3 * DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      -- 4 days from In Progress to Done, 3 of them sat in Blocked.
      assert.matches("%[active: 1%.0 day, blocked: 3%.0 days%]", text)
    end)

    it("omits the breakdown when no blocked column was visited", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - 10 * DAY,
        in_progress = os.time() - 4 * DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.is_nil(text:find("active:", 1, true))
      assert.is_nil(text:find("blocked:", 1, true))
    end)
  end)

  describe("cycle_time_unit", function()
    it("defaults to whole days", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - 2 * DAY - 3600,
        in_progress = os.time() - 2 * DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("Cycle %(In Progress → Done%): 2 days", text)
    end)

    it("singularises the unit for a duration of exactly one", function()
      local board, _, _, _, done = metrics_board()
      add_card(done, {
        backlog = os.time() - DAY,
        in_progress = os.time() - DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("1 day", text)
      assert.is_nil(text:find("1 days", 1, true))
    end)

    it("reports hours when cycle_time_unit is 'hours'", function()
      local board, _, _, _, done = metrics_board()
      board.config.cycle_time_unit = "hours"
      add_card(done, {
        backlog = os.time() - 5 * 3600,
        in_progress = os.time() - 3 * 3600,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("Lead %(Backlog → Done%): 5 hours", text)
      assert.matches("Cycle %(In Progress → Done%): 3 hours", text)
    end)

    it("singularises hours too", function()
      local board, _, _, _, done = metrics_board()
      board.config.cycle_time_unit = "hours"
      add_card(done, {
        backlog = os.time() - 3600,
        in_progress = os.time() - 3600,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("1 hour", text)
      assert.is_nil(text:find("1 hours", 1, true))
    end)

    it("falls through to raw seconds for any other unit", function()
      local board, _, _, _, done = metrics_board()
      board.config.cycle_time_unit = "seconds"
      add_card(done, {
        backlog = os.time() - 90,
        in_progress = os.time() - 90,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("90 seconds", text)
    end)

    it("uses the unit for the blocked breakdown as well", function()
      local board, _, _, _, done = metrics_board()
      board.config.cycle_time_unit = "hours"
      add_card(done, {
        backlog = os.time() - 10 * 3600,
        in_progress = os.time() - 4 * 3600,
        blocked = os.time() - 3 * 3600,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("%[active: 1%.0 hour, blocked: 3%.0 hours%]", text)
    end)
  end)

  describe("archive", function()
    it("displays metrics for archived cards", function()
      local board = metrics_board()
      board.archive = Column:new("__ARCHIVE__", "__ARCHIVE__")
      board.archive.is_archive = true
      add_card(board.archive, {
        backlog = os.time() - 8 * DAY,
        in_progress = os.time() - 2 * DAY,
        done = os.time(),
      }, 9)

      local text = rendered_text(board)

      assert.matches("Lead %(Backlog → Done%): 8 days", text)
      assert.matches("Cycle %(In Progress → Done%): 2 days", text)
    end)

    it("skips archived cards with no line number", function()
      local board = metrics_board()
      board.archive = Column:new("__ARCHIVE__", "__ARCHIVE__")
      board.archive.is_archive = true
      local card = add_card(board.archive, {
        backlog = os.time() - 8 * DAY,
        in_progress = os.time() - 2 * DAY,
        done = os.time(),
      })
      card.line_number = nil

      assert.equals("", rendered_text(board))
    end)
  end)

  describe("display toggles", function()
    it("emits nothing at all when show_stats_virtual_text is false", function()
      local board, _, _, _, done = metrics_board()
      board.config.show_stats_virtual_text = false
      board.config.wip_limit = 0
      add_card(done, {
        backlog = os.time() - 2 * DAY,
        in_progress = os.time() - DAY,
        done = os.time(),
      })

      assert.equals("", rendered_text(board))
    end)

    it("omits the lead time when show_lead_time is false", function()
      local board, _, _, _, done = metrics_board()
      board.config.show_lead_time = false
      add_card(done, {
        backlog = os.time() - 2 * DAY,
        in_progress = os.time() - DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.is_nil(text:find("Lead", 1, true))
      assert.matches("Cycle %(In Progress → Done%): 1 day", text)
    end)

    it("omits the cycle time when show_cycle_time is false", function()
      local board, _, _, _, done = metrics_board()
      board.config.show_cycle_time = false
      add_card(done, {
        backlog = os.time() - 2 * DAY,
        in_progress = os.time() - DAY,
        done = os.time(),
      })

      local text = rendered_text(board)

      assert.matches("Lead %(Backlog → Done%): 2 days", text)
      assert.is_nil(text:find("Cycle", 1, true))
    end)

    it("still shows WIP warnings when both metrics are disabled", function()
      local board, backlog = metrics_board()
      board.config.show_lead_time = false
      board.config.show_cycle_time = false
      backlog.config.wip_limit = 1
      add_card(backlog, {})
      add_card(backlog, {})

      local text = rendered_text(board)

      assert.matches("WIP limit exceeded %(2/1%)", text)
      assert.is_nil(text:find("Lead", 1, true))
    end)
  end)

  describe("WIP warnings", function()
    it("warns on the board title line when the board limit is exceeded", function()
      local board, backlog = metrics_board()
      board.config.wip_limit = 1
      add_card(backlog, {})
      add_card(backlog, {})

      local text = rendered_text(board)

      assert.matches("Board WIP limit exceeded %(2/1%)", text)

      -- title_line is 1-indexed in the parser, extmarks are 0-indexed.
      assert.equals(0, mock_calls[1].line)
    end)

    it("stays quiet when a column is exactly at its limit", function()
      local board, backlog = metrics_board()
      backlog.config.wip_limit = 2
      add_card(backlog, {})
      add_card(backlog, {})

      assert.equals("", rendered_text(board))
    end)

    it("places the column warning on the column's own line", function()
      local board, _, in_progress = metrics_board()
      in_progress.config.wip_limit = 1
      add_card(in_progress, {})
      add_card(in_progress, {})

      rendered_text(board)

      assert.equals(1, #mock_calls)
      assert.equals(in_progress.line_number - 1, mock_calls[1].line)
    end)
  end)

  describe("namespace handling", function()
    it("clears the namespace before redrawing", function()
      local cleared = {}
      mock_adapter.clear_namespace = function(_, bufnr, ns)
        table.insert(cleared, { bufnr = bufnr, ns = ns })
      end

      local board = metrics_board()
      rendered_text(board)

      assert.equals(1, #cleared)
      assert.equals(0, cleared[1].bufnr)
    end)

    it("does nothing without a buffer number", function()
      local board = metrics_board()

      virtual_text.update_virtual_text(board, nil)

      assert.equals(0, #mock_calls)
    end)
  end)
end)
