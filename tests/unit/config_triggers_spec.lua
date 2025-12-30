require('polyfills.vim')
describe("Configuration Parsing and Trigger Auto-Setup", function()
  local Board = require("kanban-md.board")
  local parser = require("kanban-md.parser")

  -- Fixture loader utility with caching to reduce memory usage
  local fixture_cache = {}
  local function load_fixture(fixture_name)
    -- Check if we already loaded this fixture's content
    if not fixture_cache[fixture_name] then
      local fixture_path = string.format("%s/%s", vim.fn.getcwd(), fixture_name)
      local file = io.open(fixture_path, "r")
      if not file then
        error("Could not load fixture: " .. fixture_path)
      end
      local content = file:read("*all")
      file:close()

      -- Split content into lines for parser and cache it
      local lines = {}
      for line in content:gmatch("[^\r\n]*") do
        table.insert(lines, line)
      end
      fixture_cache[fixture_name] = lines
    end

    -- Create new board instance from cached lines
    local board = Board:new()
    board:parse(fixture_cache[fixture_name])
    return board
  end

  describe("Configuration Parsing from Markdown", function()
    it("should parse board-level configuration", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- Verify board-level wip_limit is parsed
      assert.is_not_nil(board.config)
      assert.are.equals(5, board.config.wip_limit)
    end)

    it("should parse column-level configuration", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- Find the "Backlog" column
      local backlog_column = board:get_column_by_name("Backlog")
      assert.is_not_nil(backlog_column)

      -- Verify column-level configuration is parsed
      assert.is_not_nil(backlog_column.config)
      assert.are.equals(2, backlog_column.config.wip_limit)
    end)

    it("should handle columns without trigger configuration", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      local in_progress_column = board:get_column_by_name("In Progress")
      assert.is_not_nil(in_progress_column)

      -- In Progress column should have WIP limit but no triggers
      assert.is_not_nil(in_progress_column.config)
      assert.are.equals(3, in_progress_column.config.wip_limit)
      -- Should not have triggers configuration
      if in_progress_column.config.triggers then
        assert.fail("In Progress column should not have triggers configured")
      end
    end)
  end)

  describe("Trigger Auto-Registration", function()
    it("should call auto_register_triggers method without errors", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- Verify auto_register_triggers method exists and can be called
      assert.is_function(board.auto_register_triggers)

      -- This should complete without errors
      local success, err = pcall(function()
        board:auto_register_triggers()
      end)

      assert.is_true(success, "auto_register_triggers should not throw errors: " .. tostring(err))
    end)

    it("should handle basic configuration registration", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- Auto-registration should work with basic WIP limit configuration
      local success, err = pcall(function()
        board:auto_register_triggers()
      end)

      assert.is_true(success, "Registration with basic config should succeed: " .. tostring(err))
    end)
  end)

  describe("Configuration Type Validation", function()
    it("should handle board config type conversion", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- WIP limit should be converted from string to number
      assert.is_number(board.config.wip_limit)
      assert.are.equals(5, board.config.wip_limit)
    end)

    it("should handle column config type conversion", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      local backlog_column = board:get_column_by_name("Backlog")
      local in_progress_column = board:get_column_by_name("In Progress")

      -- Verify columns exist
      assert.is_not_nil(backlog_column, "Backlog column should exist")
      assert.is_not_nil(in_progress_column, "In Progress column should exist")

      -- WIP limits should be numbers, not strings
      if backlog_column.config then
        assert.is_number(backlog_column.config.wip_limit)
        assert.are.equals(2, backlog_column.config.wip_limit)
      end

      if in_progress_column.config then
        assert.is_number(in_progress_column.config.wip_limit)
        assert.are.equals(3, in_progress_column.config.wip_limit)
      end
    end)

    it("should verify basic board structure", function()
      local board = load_fixture("tests/fixtures/boards/test_basic_config.md")

      -- Verify board structure is properly created
      assert.is_table(board)
      assert.is_function(board.get_column_by_name)
      assert.is_function(board.auto_register_triggers)

      -- List all columns for debugging
      local all_columns = {}
      if board.columns then
        for _, col in ipairs(board.columns) do
          table.insert(all_columns, '"' .. col.name .. '"')
        end
      end

      -- Verify columns exist
      local backlog = board:get_column_by_name("Backlog")
      local in_progress = board:get_column_by_name("In Progress")
      local done = board:get_column_by_name("Done")

      assert.is_not_nil(backlog, "Backlog should exist in: [" .. table.concat(all_columns, ", ") .. "]")
      assert.is_not_nil(in_progress, "In Progress should exist in: [" .. table.concat(all_columns, ", ") .. "]")
      assert.is_not_nil(done, "Done should exist in: [" .. table.concat(all_columns, ", ") .. "]")
    end)
  end)
end)
