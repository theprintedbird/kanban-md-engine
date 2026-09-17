-- tests/unit/effective_config_spec.lua
-- Regression tests for Task 1: effective-config resolution
-- (board file > plugin config > defaults)

require('polyfills.vim')

_G._TEST = true

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local config = require('kanban-md.config')
local TypeConverter = require('kanban-md.type_converter')

describe("effective config resolution (Task 1)", function()
  -- The polyfill runs cli.setup() with defaults at require time; make sure each
  -- test starts from a known global config and restores it afterwards.
  after_each(function()
    config.reset()
  end)

  describe("Board:get_config_value", function()
    it("falls back to global config when board has no override (plain-table config)", function()
      config.setup({ timestamp_format = "epoch" })
      local board = Board:new()  -- self.config is a plain table {}
      assert.are.equals("epoch", board:get_config_value("timestamp_format"))
    end)

    it("returns the board file value when present (TypeConverter config after parse)", function()
      config.setup({ timestamp_format = "epoch" })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config timestamp_format: iso -->",
        "",
        "###### Todo",
      })
      assert.are.equals("iso", board:get_config_value("timestamp_format"))
    end)

    it("falls back to global config for a key absent from the board file", function()
      config.setup({ property_separator = " | " })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config wip_limit: 5 -->",
        "",
        "###### Todo",
      })
      assert.are.equals(" | ", board:get_config_value("property_separator"))
    end)

    it("lets an explicit false in the board file beat a true global default", function()
      config.setup({ blank_line_after_column_header = true })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config blank_line_after_column_header: false -->",
        "",
        "###### Todo",
      })
      assert.are.equals(false, board:get_config_value("blank_line_after_column_header"))
    end)

    it("resolves by presence not truthiness for plain-table config too", function()
      config.setup({ auto_timestamp = true })
      local board = Board:new()
      board.config = { auto_timestamp = false }
      assert.are.equals(false, board:get_config_value("auto_timestamp"))
    end)
  end)

  describe("Board:get_effective_config", function()
    it("overlays board file config onto a global snapshot", function()
      config.setup({ timestamp_format = "epoch", property_separator = ", " })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config timestamp_format: iso -->",
        "",
        "###### Todo",
      })
      local eff = board:get_effective_config()
      assert.are.equals("iso", eff.timestamp_format)    -- overridden by board file
      assert.are.equals(", ", eff.property_separator)   -- inherited from global
    end)

    it("returns a snapshot that does not alias the global config", function()
      local board = Board:new()
      local eff = board:get_effective_config()
      eff.timestamp_format = "mutated-only-here"
      assert.are_not.equals("mutated-only-here", config.get_value("timestamp_format"))
    end)
  end)

  describe("writer honours board-file config", function()
    it("timestamp_format from the board file changes written timestamps while global is epoch", function()
      config.setup({ timestamp_format = "epoch" })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config timestamp_format: iso -->",
        "",
        "###### Done",
        "- Task <!-- done: 1609459200 -->",
      })
      local out = table.concat(board:write(), "\n")
      assert.is_truthy(out:find("2021%-01%-01T00:00:00Z"), "expected ISO timestamp in output")
      assert.is_nil(out:find("done: 1609459200"), "epoch timestamp should not be written")
    end)

    it("uses the global epoch format when the board file does not override it", function()
      config.setup({ timestamp_format = "epoch" })
      local board = Board:new()
      board:parse({
        "# B",
        "",
        "###### Done",
        "- Task <!-- done: 1609459200 -->",
      })
      local out = table.concat(board:write(), "\n")
      assert.is_truthy(out:find("done: 1609459200"), "expected epoch timestamp in output")
    end)

    it("honours task_indent authored in the board file", function()
      config.setup({ task_indent = "" })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config task_indent: >> -->",
        "",
        "###### Todo",
        "- Task",
      })
      local out = board:write()
      local found = false
      for _, line in ipairs(out) do
        if line == ">>- Task" then
          found = true
          break
        end
      end
      assert.is_true(found, "expected task line to use board-file task_indent")
    end)

    it("honours property_separator from the board config (writer threading)", function()
      config.setup({ property_separator = ", " })
      local board = Board:new()
      board:parse({
        "# B",
        "",
        "###### Todo",
        "- Task <!-- alpha: a, beta: b -->",
      })
      -- Represents a parsed `<!-- kanban:config property_separator: ... -->`.
      -- (A separator containing spaces cannot be authored inline because the
      -- parser trims surrounding whitespace from the value.)
      board.config = TypeConverter:new({ property_separator = " | " })
      local out = table.concat(board:write(), "\n")
      assert.is_truthy(out:find("alpha: a | beta: b"), "expected board-config property separator in output")
    end)
  end)

  describe("trigger registration honours board-file config", function()
    it("auto_timestamp:false in the board file overrides a true global default", function()
      config.setup({ auto_timestamp = true })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config auto_timestamp: false -->",
        "",
        "###### Todo",
        "- Existing",
      })
      local todo = board:get_column_by_name("Todo")
      local card = Card:new(nil, "New card", {})
      todo:add_card(card)
      assert.is_nil(card.properties.todo, "no timestamp should be set when auto_timestamp is disabled")
    end)

    it("global auto_timestamp true still applies when the board file does not override it", function()
      config.setup({ auto_timestamp = true })
      local board = Board:new()
      board:parse({
        "# B",
        "",
        "###### Todo",
        "- Existing",
      })
      local todo = board:get_column_by_name("Todo")
      local card = Card:new(nil, "New card", {})
      todo:add_card(card)
      assert.is_not_nil(card.properties.todo, "timestamp should be set when auto_timestamp is enabled")
    end)

    -- The mirror of the auto_timestamp cases above: auto_timestamp defaults on
    -- and the board file turns it off, whereas dependency_validation and
    -- subtask_validation default off, so the board file has to turn them on.
    local function checking_trigger_names(column)
      local names = {}
      for name, _ in pairs(column.triggers.on_checking or {}) do
        table.insert(names, name)
      end
      table.sort(names)
      return names
    end

    it("registers no dependency or subtask trigger when both default to off", function()
      config.setup({ dependency_validation = false, subtask_validation = false })
      local board = Board:new()
      board:parse({
        "# B",
        "",
        "###### Todo",
        "- A",
        "",
        "###### Done",
      })
      for _, column in ipairs(board.columns) do
        local names = checking_trigger_names(column)
        assert.is_nil(column.triggers.on_checking and column.triggers.on_checking.dependencies,
          "dependencies trigger should not be registered on " .. column.name ..
          " (registered: " .. table.concat(names, ", ") .. ")")
        assert.is_nil(column.triggers.on_checking and column.triggers.on_checking.subtasks,
          "subtasks trigger should not be registered on " .. column.name ..
          " (registered: " .. table.concat(names, ", ") .. ")")
      end
    end)

    it("dependency_validation:true in the board file registers the trigger a false global default leaves off", function()
      config.setup({ dependency_validation = false, subtask_validation = false })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config dependency_validation: true -->",
        "",
        "###### Todo",
        "- A",
        "",
        "###### Done",
      })
      assert.are.equals(true, board:get_config_value("dependency_validation"))
      for _, column in ipairs(board.columns) do
        assert.is_function(column.triggers.on_checking.dependencies,
          "dependencies trigger should be registered on " .. column.name)
        local metadata = column.trigger_metadata.on_checking.dependencies
        assert.are.equals("dependency", metadata.category)
        assert.is_true(metadata.bypassable)
        assert.is_nil(column.triggers.on_checking.subtasks,
          "subtask validation is still off, so its trigger should not be registered")
      end
    end)

    it("subtask_validation:true in the board file registers the trigger a false global default leaves off", function()
      config.setup({ dependency_validation = false, subtask_validation = false })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config subtask_validation: true -->",
        "",
        "###### Todo",
        "- A",
        "",
        "###### Done",
      })
      assert.are.equals(true, board:get_config_value("subtask_validation"))
      for _, column in ipairs(board.columns) do
        assert.is_function(column.triggers.on_checking.subtasks,
          "subtasks trigger should be registered on " .. column.name)
        local metadata = column.trigger_metadata.on_checking.subtasks
        assert.are.equals("subtask", metadata.category)
        assert.is_true(metadata.bypassable)
        assert.is_nil(column.triggers.on_checking.dependencies,
          "dependency validation is still off, so its trigger should not be registered")
      end
    end)

    it("the trigger a board file switched on actually validates the move", function()
      config.setup({ dependency_validation = false, subtask_validation = false })
      local board = Board:new()
      board:parse({
        "# B",
        "<!-- kanban:config dependency_validation: true -->",
        "",
        "###### Todo",
        "- Blocker <!-- id: blocker_1 -->",
        "- Blocked <!-- id: blocked_1, depends_on: blocker_1 -->",
        "",
        "###### Done",
      })
      local todo = board:get_column_by_name("Todo")
      local done = board:get_column_by_name("Done")
      local blocked = todo.cards[2]
      assert.are.equals("Blocked", blocked.text)

      local success, err = pcall(function()
        board:move_card(blocked, todo, done)
      end)
      assert.is_false(success, "move to completion should be blocked while the dependency is incomplete")
      assert.matches("not complete", tostring(err))
    end)
  end)
end)
