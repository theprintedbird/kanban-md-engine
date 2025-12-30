require('polyfills.vim')
_G._TEST = true
local WorkflowEngine = require('kanban-md.workflow_engine')
local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')

-- Helper to get a fresh board with basic structure for tests that need simple setup
-- Optimized to minimize memory usage
local function create_simple_test_board()
  local board = Board:new()
  board.title = "Test Board"

  -- Enable optional features for testing
  board.config.subtask_validation = true
  board.config.dependency_validation = true

  -- Create columns using board's add_column method
  local todo_column = board:add_column("todo", "To Do")
  local done_column = board:add_column("done", "Done")

  return board, todo_column, done_column
end

-- Helper to cleanup test objects and force garbage collection
local function cleanup_test_objects()
  -- Force garbage collection to free memory
  if collectgarbage then
    collectgarbage("collect")
    collectgarbage("collect") -- Run twice for better cleanup
  end
end

-- Helper function to check if a column has a card (since column:has_card doesn't exist)
local function column_has_card(column, card_id)
  for _, card in ipairs(column.cards) do
    if card.id == card_id then
      return true
    end
  end
  return false
end


describe("WorkflowEngine", function()
  local board, engine, card, todo_column, done_column

  before_each(function()
    -- Use simple board for most tests
    board, todo_column, done_column = create_simple_test_board()

    -- Create a test card
    card = Card:new("test_task_1", "Test task", {id = "test_task_1"})
    todo_column:add_card(card)

    -- Register all triggers (including optional features)
    board:auto_register_triggers()

    -- Create workflow engine reference (triggers already registered)
    engine = WorkflowEngine:new(board)
  end)

  after_each(function()
    -- Clear references to help garbage collection
    board = nil
    engine = nil
    card = nil
    todo_column = nil
    done_column = nil
    cleanup_test_objects()
  end)

  describe("basic operations", function()
    it("should start in READY state", function()
      assert.are.equal("ready", engine.state)
    end)

    it("should register WIP limit triggers when configured", function()
      -- Set up WIP limit on Done column
      done_column.config = {wip_limit = 1}

      -- Recreate engine to register WIP limit triggers
      engine = WorkflowEngine:new(board)

      -- Verify WIP trigger was registered on the column
      local checking_triggers = done_column:get_triggers("on_checking")
      assert.is_not_nil(checking_triggers, "Should have checking triggers")
      assert.is_not_nil(checking_triggers.wip_limit, "Should have wip_limit trigger registered")
    end)
  end)

  describe("workflow validation", function()
    describe("transitions defined in workflow", function()

			it("should allow allowed workflows", function()
				-- Set up workflow with specific allowed transitions
				board.config.workflow = {
					["To Do"] = {"In Progress", "Done"},
					["In Progress"] = {"Done", "To Do"}
				}
				-- Recreate engine to register workflow triggers
				engine = WorkflowEngine:new(board)

				-- Test allowed transition
				local success, err = board:move_card(card, todo_column, done_column)
				assert.is_true(success, "Move should succeed: " .. tostring(err))
			end)

			it("should allow a different allowed transition", function()
				-- Set up workflow with specific allowed transitions
				board.config.workflow = {
					["To Do"] = {"In Progress", "Done"},
					["In Progress"] = {"Done", "To Do"}
				}
				-- Reset and test another allowed transition
				local in_progress_column = board:add_column("in_progress", "In Progress")
				engine = WorkflowEngine:new(board)
				local card2 = Card:new("task_2", "Task 2", {id = "task_2"})
				in_progress_column:add_card(card2)

				local success2, err2 = board:move_card(card2, in_progress_column, todo_column)
				assert.is_true(success2, "Move should succeed: " .. tostring(err2))
			end)

			it("should block undefined transitions", function()
				-- Set up restrictive workflow
				board.config.workflow = {
					["To Do"] = {"In Progress"} -- Only allow To Do -> In Progress
				}

				-- Recreate engine to pick up the workflow configuration
				engine = WorkflowEngine:new(board)

				-- Try disallowed transition
				local success, err = pcall(function()
					board:move_card(card, todo_column, done_column)
				end)
				assert.is_false(success)
				assert.matches("Workflow does not allow", err)
			end)

			describe("conditional transitions", function()
				it("should handle met conditions", function()
					-- Set up conditional workflow
					board.config.workflow = {
						["To Do"] = {
							["Done"] = {
								when = "priority == high"
							},
							["In Progress"] = {} -- No condition, always allowed
						}
					}

					-- Recreate engine to pick up the workflow configuration
					engine = WorkflowEngine:new(board)

					-- Test with condition not met
					card.properties.priority = "low"
					local success, err = pcall(function()
						board:move_card(card, todo_column, done_column)
					end)
					assert.is_false(success)
					assert.matches("Workflow", err)
				end)

				it("should handle unmet conditions", function()
					-- Set up conditional workflow
					board.config.workflow = {
						["To Do"] = {
							["Done"] = {
								when = "priority == high"
							},
							["In Progress"] = {} -- No condition, always allowed
						}
					}
					-- Test with condition met
					card.properties.priority = "high"
					local success2, err2 = board:move_card(card, todo_column, done_column)
					assert.is_true(success2, "Move should succeed: " .. tostring(err2))
				end)
			end)

			describe("evaluation of transition conditions", function()
				it("should handle a met complexity condition", function()
					-- Test different condition formats
					board.config.workflow = {
						["To Do"] = {
							["Done"] = {
								when = "complexity != 5"
							}
						}
					}

					-- Recreate engine to pick up the workflow configuration
					engine = WorkflowEngine:new(board)

					-- Test numeric condition - should pass
					card.properties.complexity = 3
					local success, err = board:move_card(card, todo_column, done_column)
					assert.is_true(success, "Move should succeed: " .. tostring(err))
				end)

				it("should handle an unment complexity condition", function()
					-- Test different condition formats
					board.config.workflow = {
						["To Do"] = {
							["Done"] = {
								when = "complexity != 5"
							}
						}
					}

					-- Recreate engine to pick up the workflow configuration
					engine = WorkflowEngine:new(board)

					-- Test condition failure - should block
					card.properties.complexity = 5
					local success2, err2 = pcall(function()
						board:move_card(card, todo_column, done_column)
					end)
					assert.is_false(success2)
				end)

				it("should hand a boolean condition", function()
					-- Test different condition formats
					board.config.workflow = {
						["To Do"] = {
							["Done"] = {
								when = "complexity != 5"
							}
						}
					}
					board.config.workflow["To Do"]["Done"].when = "reviewed"
					card.properties.reviewed = true

					-- Recreate engine to pick up the updated workflow configuration
					engine = WorkflowEngine:new(board)

					local success3, err3 = board:move_card(card, todo_column, done_column)
					assert.is_true(success3, "Move should succeed: " .. tostring(err3))
				end)
			end)
		end)
	end)


  -- Note: Capacity validation behavior is tested in integration tests.
  -- This section only tests that WorkflowEngine registers the appropriate triggers.


  describe("transition options", function()
			it("should work with no workflow (all transitions allowed)", function()
				local valid_transitions = engine:get_valid_transitions(card, todo_column)
				assert.is_true(#valid_transitions > 0)
				assert.are.equal(1, table.concat(valid_transitions, ","):find("Done"))
				assert.are.equal("__ARCHIVE__", valid_transitions[2])
			end)
      
      it("should work with defined workflow", function()
				board.config.workflow = {
					["To Do"] = {"In Progress", "Done"}
				}
				
				local valid_transitions2 = engine:get_valid_transitions(card, todo_column)
				assert.are.equal(2, #valid_transitions2)
				assert.are.equal("In Progress", valid_transitions2[1])
				assert.are.equal("Done",valid_transitions2[2])
			end)
      
      it("should work with conditional transitions", function()
				board.config.workflow = {
					["To Do"] = {
						["Done"] = {
							when = "priority == high"
						},
						["In Progress"] = {} -- Always allowed
					}
				}
				
				-- Without meeting condition
				card.properties.priority = "low"
				local valid_transitions3 = engine:get_valid_transitions(card, todo_column)
				assert.are.equal(1, #valid_transitions3)
				assert.are.equal("In Progress", valid_transitions3[1])
			end)
      
      it("should work with condition met", function()
				card.properties.priority = "high"
				local valid_transitions4 = engine:get_valid_transitions(card, todo_column)
				assert.are.equal(2, #valid_transitions4)
				assert.are.equal("Done",valid_transitions4[1])
				assert.are.equal("__ARCHIVE__",valid_transitions4[2])
			end)
      
      it("should work with no defined transitions for column", function()
				board.config.workflow = {
					["Other Column"] = {"Somewhere"}
				}
				
				local valid_transitions5 = engine:get_valid_transitions(card, todo_column)
				assert.are.equal(0, #valid_transitions5)
			end)
  end)


  describe("trigger execution and validation", function()
    local pipeline_board, pipeline_engine, test_card, source_column, target_column

    before_each(function()
      pipeline_board, source_column, target_column = create_simple_test_board()
      test_card = Card:new("pipeline_test", "Pipeline test task", {id = "pipeline_test"})
      test_card.id = "pipeline_test"
      source_column:add_card(test_card)
      pipeline_engine = WorkflowEngine:new(pipeline_board)
    end)

    after_each(function()
      pipeline_board = nil
      pipeline_engine = nil
      test_card = nil
      source_column = nil
      target_column = nil
      cleanup_test_objects()
    end)

    it("should register workflow triggers when workflow config exists", function()
      -- Set up workflow config
      pipeline_board.config.workflow = {
        ["To Do"] = {"In Progress"}
      }

      pipeline_engine = WorkflowEngine:new(pipeline_board)

      -- Verify workflow trigger was registered
      local checking_triggers = source_column:get_triggers("on_checking")
      assert.is_not_nil(checking_triggers, "Should have checking triggers")
      assert.is_not_nil(checking_triggers.workflow_rules, "Should have workflow_rules trigger")
    end)

    -- Note: Dependency and subtask triggers are registered by Board:auto_register_triggers()
    -- when the respective features are enabled, not by WorkflowEngine.
    -- Those are tested in the integration specs (dependency_validation_spec, subtask_validation_spec)

    it("should register WIP limit triggers when configured", function()
      -- Set up WIP limit
      target_column.config = {wip_limit = 3}

      pipeline_engine = WorkflowEngine:new(pipeline_board)

      -- Verify WIP trigger was registered
      local checking_triggers = target_column:get_triggers("on_checking")
      assert.is_not_nil(checking_triggers, "Should have checking triggers")
      assert.is_not_nil(checking_triggers.wip_limit, "Should have wip_limit trigger")
    end)

    it("should block moves when multiple validations fail", function()
      -- Set up multiple error conditions
      pipeline_board.config.workflow = {
        ["To Do"] = {"In Progress"} -- Only allow To Do -> In Progress, not Done
      }
      test_card.properties.depends_on = {"missing_dep"}

      pipeline_engine = WorkflowEngine:new(pipeline_board)

      -- Try to move - should be blocked by first failing trigger
      local success, err = pcall(function()
        pipeline_board:move_card(test_card, source_column, target_column)
      end)
      assert.is_false(success)
      -- Should get error from one of the failing validations
      assert.is_not_nil(err)
    end)

  end)
end)
