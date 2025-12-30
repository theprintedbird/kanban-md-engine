-- Test for timestamp behavior on initial card placement and subsequent moves
require('polyfills.vim')
local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local triggers = require('kanban-md.triggers')

describe("Card timestamp behavior", function()
  local board, todo_col, in_progress_col, done_col

  before_each(function()
    board = Board:new()
    todo_col = board:add_column("todo", "Todo")
    in_progress_col = board:add_column("in_progress", "In Progress")
    done_col = board:add_column("done", "Done")

    -- Register timestamp triggers on all columns
    local timestamp_exec, timestamp_rollback = triggers.timestamp()
    todo_col:register_on_entry("add_timestamp", timestamp_exec, timestamp_rollback)
    in_progress_col:register_on_entry("add_timestamp", timestamp_exec, timestamp_rollback)
    done_col:register_on_entry("add_timestamp", timestamp_exec, timestamp_rollback)
  end)

  describe("initial placement", function()
    it("should add timestamp when card is first placed in a column", function()
      -- Create a new card
      local card = Card:new("card-1", "Test task")

      -- Verify no timestamp yet
      assert.is_nil(card.properties.todo)

      -- Add card to Todo column (initial placement)
      todo_col:add_card(card)

      -- Card should now have a timestamp for the Todo column
      assert.is_not_nil(card.properties.todo, "Card should have 'todo' timestamp after initial placement")
      assert.is_number(card.properties.todo)
    end)
  end)

  describe("subsequent moves", function()
    it("should add timestamps for each column the card moves to", function()
      -- Create and place card in Todo
      local card = Card:new("card-2", "Test task")
      todo_col:add_card(card)

      local todo_timestamp = card.properties.todo
      assert.is_not_nil(todo_timestamp, "Card should have 'todo' timestamp")

      -- Small delay to ensure different timestamps
      os.execute("sleep 0.1")

      -- Move to In Progress
      board:move_card(card, todo_col, in_progress_col)

      -- Should have both timestamps now
      assert.is_not_nil(card.properties.todo, "Card should still have 'todo' timestamp")
      assert.is_not_nil(card.properties.in_progress, "Card should have 'in_progress' timestamp")
      assert.are.equal(todo_timestamp, card.properties.todo, "Original 'todo' timestamp should be unchanged")

      -- Small delay
      os.execute("sleep 0.1")

      -- Move to Done
      board:move_card(card, in_progress_col, done_col)

      -- Should have all three timestamps now
      assert.is_not_nil(card.properties.todo, "Card should still have 'todo' timestamp")
      assert.is_not_nil(card.properties.in_progress, "Card should still have 'in_progress' timestamp")
      assert.is_not_nil(card.properties.done, "Card should have 'done' timestamp")
    end)
  end)

  describe("reproduction of reported bug", function()
    it("DEMONSTRATES: new cards should get timestamp on initial placement (current behavior test)", function()
      -- This test documents the expected behavior that the user is reporting as missing

      -- Step 1: Create a new card and add to first column
      local card = Card:new("card-3", "New card")
      todo_col:add_card(card)

      -- Expected: Card should have timestamp for Todo column
      -- This is what we want to verify is working
      local todo_ts = card.properties.todo
      print(string.format("After initial placement in Todo: todo=%s", tostring(todo_ts)))

      -- Step 2: Move to In Progress
      os.execute("sleep 0.1")
      board:move_card(card, todo_col, in_progress_col)

      -- Expected: Card should have timestamps for BOTH columns
      local in_progress_ts = card.properties.in_progress
      print(string.format("After move to In Progress: todo=%s, in_progress=%s",
        tostring(card.properties.todo), tostring(in_progress_ts)))

      -- Step 3: Move to Done
      os.execute("sleep 0.1")
      board:move_card(card, in_progress_col, done_col)

      -- Expected: Card should have timestamps for ALL columns
      local done_ts = card.properties.done
      print(string.format("After move to Done: todo=%s, in_progress=%s, done=%s",
        tostring(card.properties.todo), tostring(card.properties.in_progress), tostring(done_ts)))

      -- Assertions based on expected behavior
      assert.is_not_nil(todo_ts, "BUG: Card should have 'todo' timestamp from initial placement")
      assert.is_not_nil(in_progress_ts, "Card should have 'in_progress' timestamp")
      assert.is_not_nil(done_ts, "Card should have 'done' timestamp")

      -- All timestamps should be different (since we added delays)
      if todo_ts and in_progress_ts then
        assert.is_true(in_progress_ts >= todo_ts, "in_progress timestamp should be >= todo timestamp")
      end
      if in_progress_ts and done_ts then
        assert.is_true(done_ts >= in_progress_ts, "done timestamp should be >= in_progress timestamp")
      end
    end)
  end)
end)
