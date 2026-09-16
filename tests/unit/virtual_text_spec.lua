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
        table.insert(mock_calls, {
          bufnr = bufnr,
          line = line,
          text = opts.virt_text and opts.virt_text[1] and opts.virt_text[1][1] or ""
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
end)
