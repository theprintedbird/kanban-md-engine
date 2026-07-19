-- tests/unit/column_config_layers_spec.lua
-- Regression tests for PLAN-config-fixes.md Task 3:
-- "Stop writing resolved/implicit column config to markdown".
--
-- Each column keeps two config layers:
--   * column.markdown_config -- exactly the properties authored in the markdown
--     `<!-- column:config ... -->` comment (absent when none was authored).
--     This is what the writer serialises back by default.
--   * column.config -- the merged/resolved config (type defaults < definition
--     < markdown) that triggers, helpers, stats and validation consult.
--
-- Under the default write_full_config_to_markdown = false, implicit/resolved
-- properties (from column_config types, definitions or patterns) must never be
-- injected into the user's file, while the resolved layer must still drive
-- engine behaviour such as is_completion_column().
require('polyfills.vim')

local Board = require('kanban-md.board')
local column_helpers = require('kanban-md.helpers.column')
local test_setup = require('helpers.setup')

local function write(board)
  return table.concat(board:write(), "\n")
end

describe("Column config layers (plan Task 3)", function()
  describe("pattern-resolved types are not injected into markdown", function()
    it("does not write a comment for a pattern-matched completion column", function()
      test_setup.with_config({
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local board = Board:new()
        board:parse("# B\n\n###### Todo\n\n- A task\n\n###### Done\n")

        local output = write(board)

        assert.is_nil(output:find("column:config", 1, true))
        assert.is_nil(output:find("is_completion_state", 1, true))
      end)
    end)

    it("still drives is_completion_column() from the resolved layer", function()
      test_setup.with_config({
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local board = Board:new()
        -- "Done" is the *first* regular column so position-based fallback would
        -- NOT mark it complete; only the resolved pattern type can.
        board:parse("# B\n\n###### Done\n\n- A task\n\n###### Todo\n")

        local done = board:get_column_by_name("Done")

        -- Resolved layer carries the type-derived property...
        assert.is_true(done.config.is_completion_state)
        -- ...but the authored layer is empty (nothing was authored).
        assert.is_true(done.markdown_config == nil
          or done.markdown_config:to_table().is_completion_state == nil)
        -- ...and engine behaviour reads the resolved layer.
        assert.is_true(column_helpers.is_completion_column(done, board))
      end)
    end)
  end)

  describe("definition-resolved types are not injected into markdown", function()
    it("does not write a comment for a named-definition column", function()
      test_setup.with_config({
        column_config = {
          types = {
            wip = { properties = { wip_limit = 3 } },
          },
          definitions = {
            ["In Progress"] = { type = "wip" },
          },
        },
      }, function()
        local board = Board:new()
        board:parse("# B\n\n###### Todo\n\n- A task\n\n###### In Progress\n")

        local output = write(board)
        local in_progress = board:get_column_by_name("In Progress")

        -- Resolved layer picked up the definition's wip_limit...
        assert.are.equal(3, in_progress.config.wip_limit)
        -- ...but nothing is written to markdown.
        assert.is_nil(output:find("column:config", 1, true))
        assert.is_nil(output:find("wip_limit", 1, true))
      end)
    end)
  end)

  describe("authored column config round-trips verbatim", function()
    it("preserves an authored wip_limit through parse -> write", function()
      local board = Board:new()
      board:parse("# B\n\n###### Todo\n<!-- column:config wip_limit: 3 -->\n\n- A task\n\n###### Done\n")

      local output = write(board)

      assert.is_not_nil(output:find("column:config", 1, true))
      assert.is_not_nil(output:find("wip_limit: 3", 1, true))

      -- Re-parsing the written output yields the same authored + resolved value.
      local reparsed = Board:new()
      reparsed:parse(output)
      assert.are.equal(3, reparsed:get_column_by_name("Todo").config.wip_limit)
      assert.are.equal(3, reparsed:get_column_by_name("Todo").markdown_config.wip_limit)
    end)

    it("writes only authored props, not resolved type props, for an authored column", function()
      test_setup.with_config({
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local board = Board:new()
        -- "Done" matches the completion pattern (adds is_completion_state to the
        -- resolved layer) but the user only authored wip_limit.
        board:parse("# B\n\n###### Done\n<!-- column:config wip_limit: 2 -->\n\n- A task\n")

        local output = write(board)
        local done = board:get_column_by_name("Done")

        -- Resolved layer has both; authored layer has only wip_limit.
        assert.is_true(done.config.is_completion_state)
        assert.are.equal(2, done.config.wip_limit)

        assert.is_not_nil(output:find("wip_limit: 2", 1, true))
        assert.is_nil(output:find("is_completion_state", 1, true))
      end)
    end)
  end)

  describe("write_full_config_to_markdown = true writes the resolved layer", function()
    it("honours a global config override", function()
      test_setup.with_config({
        write_full_config_to_markdown = true,
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local board = Board:new()
        board:parse("# B\n\n###### Todo\n\n- A task\n\n###### Done\n")

        local output = write(board)

        -- Now the resolved type property IS serialised.
        assert.is_not_nil(output:find("is_completion_state: true", 1, true))
      end)
    end)

    it("honours a board-file override", function()
      test_setup.with_config({
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local board = Board:new()
        board:parse("# B\n<!-- kanban:config write_full_config_to_markdown: true -->\n\n###### Todo\n\n- A task\n\n###### Done\n")

        local output = write(board)

        assert.is_not_nil(output:find("is_completion_state: true", 1, true))
      end)
    end)
  end)

  describe("programmatic columns still serialise their config", function()
    it("writes config supplied to add_new_column via write_legacy", function()
      local board = Board:new()
      board.title = "Prog"
      board:add_new_column("Todo", { wip_limit = 4 })
      board:add_new_column("Done")

      local output = write(board)

      assert.is_not_nil(output:find("wip_limit: 4", 1, true))
    end)
  end)
end)
