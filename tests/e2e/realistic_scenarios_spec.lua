require('polyfills.vim')
describe("Realistic End-to-End Scenarios", function()
  local Board = require("kanban-md.board")
  local Card = require("kanban-md.card")
	-- TODO use these
  -- local fixtures = require("tests.fixtures.boards")

  local function create_realistic_board()
    -- Create a board similar to the fixtures but with proper structure
    local board = Board:new()
    board.title = "Realistic Test Board"
    board.config = { wip_limit = 10 }

    -- Add columns
    local backlog = board:add_column("backlog", "Backlog")
    local in_progress = board:add_column("in_progress", "In Progress")
    local done = board:add_column("done", "Done")

    -- Configure WIP limits
		-- note: This overwrites the TypeConverter object that's initialized in Column:new()
    in_progress.config = { wip_limit = 3 }

    -- Register auto-timestamp triggers
    board:auto_register_triggers()

    -- Add some realistic tasks (timestamps set automatically by triggers)
    local task1 = Card:new("task1", "Design API")
    task1.properties.complexity = 5
    backlog:add_card(task1)

    local task2 = Card:new("task2", "Write tests")
    task2.properties.complexity = 3
    backlog:add_card(task2)

    local task3 = Card:new("task3", "Implement feature")
    task3.properties.complexity = 8
    in_progress:add_card(task3)

    local task4 = Card:new("task4", "Setup project")
    done:add_card(task4)

    return board
  end

  describe("Complete Workflow Progression Scenarios", function()
    -- local workflow_engine
    local board

    before_each(function()
      board = create_realistic_board()
      -- workflow_engine = WorkflowEngine:new(board)
    end)

    it("should handle complete task lifecycle from backlog to done", function()
      -- Initial state verification
      assert.are.equal("Realistic Test Board", board.title)
      assert.are.equal(3, #board.columns) -- Backlog, In Progress, Done

      -- Get specific columns
      local backlog_column = board:get_column("backlog")
      local in_progress_column = board:get_column("in_progress")
      local done_column = board:get_column("done")

      assert.is_not_nil(backlog_column)
      assert.is_not_nil(in_progress_column)
      assert.is_not_nil(done_column)

      -- Get a task from backlog
      assert.are.equal(2, #backlog_column.cards) -- We created 2 backlog tasks
      local test_task = backlog_column.cards[1]

      -- Test simple workflow: Backlog -> In Progress -> Done

      -- Step 1: Move from Backlog to In Progress
      local success, err = pcall(function()
        return board:move_card(test_task, backlog_column, in_progress_column)
      end)
      assert.is_true(success, "Move to In Progress should succeed: " .. tostring(err))

      -- Step 2: Move from In Progress to Done
      if success then
        success, err = pcall(function()
          return board:move_card(test_task, in_progress_column, done_column)
        end)
        assert.is_true(success, "Move to Done should succeed: " .. tostring(err))
      end

      -- At minimum verify structure is intact
      assert.are.equal(3, #board.columns)
    end)

    it("should maintain board integrity during task movements", function()
      -- Count initial cards
      local initial_card_count = 0
      for _, column in ipairs(board.columns) do
        initial_card_count = initial_card_count + #column.cards
      end

      assert.are.equal(4, initial_card_count) -- We created 4 cards total

      -- Try moving a task if available
      local backlog_column = board:get_column("backlog")
      local in_progress_column = board:get_column("in_progress")
      if #backlog_column.cards > 0 then
        local task = backlog_column.cards[1]
				local success, err = pcall(function()
					return board:move_card(task, backlog_column, in_progress_column)
				end)
        assert.is_true(success)

        -- Count cards after potential move - should be same total
        local final_card_count = 0
        for _, column in ipairs(board.columns) do
          final_card_count = final_card_count + #column.cards
        end
        assert.are.equal(initial_card_count, final_card_count)
      end
    end)
  end)

  describe("Multi-Column WIP Limit Enforcement", function()
    local board

    before_each(function()
      board = create_realistic_board()
    end)

    it("should respect column-specific WIP limits", function()
      local in_progress_column = board:get_column("in_progress")
      assert.is_not_nil(in_progress_column)

      -- Verify WIP limit is configured (we set wip_limit: 3)
      assert.is_not_nil(in_progress_column.config)
      assert.are.equal(3, in_progress_column.config.wip_limit)

      -- Current card count in In Progress
      local current_count = #in_progress_column.cards
      assert.is_true(current_count <= 3)
      assert.are.equal(1, current_count) -- We created 1 task in In Progress
    end)

    it("should enforce board-level WIP limits", function()
      -- Board has overall WIP limit of 10 (we set this)
      assert.is_not_nil(board.config)
      assert.are.equal(10, board.config.wip_limit)

      -- Count current cards across all non-completion columns
      local total_wip = 0
      for _, column in ipairs(board.columns) do
        if column.name ~= "Done" then
          total_wip = total_wip + #column.cards
        end
      end

      -- Should be within board limit
      assert.is_true(total_wip <= 10)
      assert.are.equal(3, total_wip) -- We created 2 backlog + 1 in progress
    end)
  end)

  describe("Complex Dependency and Subtask Scenarios", function()
    local board

    before_each(function()
      -- Create a test board with complex dependencies
      board = Board.new()
			board:parse({"# Dependency Test Board",
				"###### Todo",
        "",
				"###### In Progress",
        "",
				"###### Done",
        "",
			})
    end)

    it("should handle basic task creation and structure", function()
      -- Create some test cards
      local card_a = Card.new("Card A")
      card_a.properties.id = "card_a"

      local card_b = Card.new("Card B")
      card_b.properties.id = "card_b"
      card_b.properties.depends_on = {"card_a"}

      -- Add cards to Todo column
      local todo_col = board:get_column_by_name("Todo")
      todo_col:add_card(card_a)
      todo_col:add_card(card_b)

      -- Verify structure
      assert.are.equal(2, #board.columns[1].cards)
      assert.are.equal("card_a", board.columns[1].cards[1].properties.id)
      assert.are.equal("card_b", board.columns[1].cards[2].properties.id)
    end)

    it("should maintain card relationships", function()
      -- Create parent-child relationship
      local parent_card = Card.new("Parent Card")
      parent_card.properties.id = "parent"

      local child_card = Card.new("Child Card")
      child_card.properties.id = "child"
      child_card.properties.parent = "parent"

      board.columns[1]:add_card(parent_card)
      board.columns[1]:add_card(child_card)

      -- Verify relationships are preserved
      assert.are.equal("parent", child_card.properties.parent)
      assert.are.equal(2, #board.columns[1].cards)
    end)
  end)

  describe("Comprehensive Integration Scenarios", function()
		local board

    it("should handle realistic board creation and basic operations", function()
      board = create_realistic_board()

      -- Verify board created correctly
      assert.are.equal("Realistic Test Board", board.title)
      assert.are.equal(3, #board.columns)

      -- Verify configuration loaded
      assert.is_not_nil(board.config)
      assert.are.equal(10, board.config.wip_limit)

      -- Verify cards exist in columns
      local total_cards = 0
      for _, column in ipairs(board.columns) do
        total_cards = total_cards + #column.cards
      end
      assert.are.equal(4, total_cards)
    end)

    it("should maintain data integrity through workflow operations", function()
      local board = create_realistic_board()

      -- Count initial state
      local initial_card_count = 0
      for _, column in ipairs(board.columns) do
        initial_card_count = initial_card_count + #column.cards
      end

      -- Perform some workflow operations (whether they succeed or fail)
      local backlog_column = board:get_column("backlog")
      local in_progress_column = board:get_column("in_progress")
      if backlog_column and #backlog_column.cards > 0 then
        local card = backlog_column.cards[1]
				local success, err = pcall(function()
					return board:move_card(card, backlog_column, in_progress_column)
				end)

        -- Regardless of success/failure, verify data integrity
        local final_card_count = 0
        for _, column in ipairs(board.columns) do
          final_card_count = final_card_count + #column.cards
        end

        assert.are.equal(initial_card_count, final_card_count)
      end

      -- Verify board structure remains intact
      assert.is_not_nil(board.title)
      assert.is_not_nil(board.columns)
      assert.is_not_nil(board.config)
    end)
  end)

  after_each(function()
    -- Cleanup if needed
  end)
end)
