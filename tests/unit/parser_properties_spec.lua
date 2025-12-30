-- tests/unit/parser_properties_spec.lua
-- Tests for property parsing functionality

require('polyfills.vim')
_G._TEST = true

local Board = require("kanban-md.board")

describe("Parser property parsing", function()
  describe("parse_properties with comma-separated values", function()
    it("should parse board config with comma separators", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "<!-- kanban:config wip_limit: 7, cycle_time_unit: days -->",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.are.equals(7, board.config.wip_limit)
      assert.are.equals("days", board.config.cycle_time_unit)
    end)

    it("should parse column config with comma separators", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "<!-- column:config wip_limit: 3, is_backlog_state: true -->",
        "- Task one"
      })

      local column = board.columns[1]
      assert.are.equals(3, column.config.wip_limit)
      assert.is_true(column.config.is_backlog_state)
    end)

    it("should parse card properties with comma separators", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "- Task one <!-- complexity: 3, priority: high -->"
      })

      local card = board.columns[1].cards[1]
      assert.are.equals(3, card.properties.complexity)
      assert.are.equals("high", card.properties.priority)
    end)
  end)

  describe("parse_properties with whitespace-separated values", function()
    it("should parse board config with newline separators in multi-line comment", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "<!-- kanban:config",
        "wip_limit: 7",
        "cycle_time_unit: days",
        "-->",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.are.equals(7, board.config.wip_limit)
      assert.are.equals("days", board.config.cycle_time_unit)
    end)

    it("should parse column config with newline separators", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "<!-- column:config",
        "wip_limit: 3",
        "is_backlog_state: true",
        "-->",
        "- Task one"
      })

      local column = board.columns[1]
      assert.are.equals(3, column.config.wip_limit)
      assert.is_true(column.config.is_backlog_state)
    end)

    it("should parse board config with multiple numeric and string properties", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "<!-- kanban:config",
        "wip_limit: 15",
        "cycle_time_unit: days",
        "auto_archive: true",
        "default_start_column: In Progress",
        "-->",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.are.equals(15, board.config.wip_limit)
      assert.are.equals("days", board.config.cycle_time_unit)
      assert.is_true(board.config.auto_archive)
      assert.are.equals("In Progress", board.config.default_start_column)
    end)
  end)

  describe("parse_properties with mixed separators", function()
    it("should handle both commas and newlines in the same config", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "<!-- kanban:config",
        "wip_limit: 7, cycle_time_unit: days",
        "auto_archive: true",
        "-->",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.are.equals(7, board.config.wip_limit)
      assert.are.equals("days", board.config.cycle_time_unit)
      assert.is_true(board.config.auto_archive)
    end)
  end)

  describe("parse_properties with array values", function()
    it("should handle arrays with comma-separated items", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "- Task one <!-- tags: [urgent, backend, api] -->"
      })

      local card = board.columns[1].cards[1]
      assert.is_table(card.properties.tags)
      assert.are.equals(3, #card.properties.tags)
      assert.are.equals("urgent", card.properties.tags[1])
      assert.are.equals("backend", card.properties.tags[2])
      assert.are.equals("api", card.properties.tags[3])
    end)

    it("should handle arrays when followed by other properties (comma separator)", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "- Task one <!-- tags: [urgent, backend], priority: high -->"
      })

      local card = board.columns[1].cards[1]
      assert.is_table(card.properties.tags)
      assert.are.equals(2, #card.properties.tags)
      assert.are.equals("urgent", card.properties.tags[1])
      assert.are.equals("backend", card.properties.tags[2])
      assert.are.equals("high", card.properties.priority)
    end)

    it("should handle arrays when followed by other properties on single line (whitespace separator)", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "- Task one <!-- tags: [urgent, backend] priority: high -->"
      })

      local card = board.columns[1].cards[1]
      assert.is_table(card.properties.tags)
      assert.are.equals(2, #card.properties.tags)
      assert.are.equals("urgent", card.properties.tags[1])
      assert.are.equals("backend", card.properties.tags[2])
      assert.are.equals("high", card.properties.priority)
    end)
  end)

  describe("parse_properties edge cases", function()
    it("should handle properties with spaces in string values", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "<!-- kanban:config",
        "default_start_column: In Progress",
        "cycle_time_unit: days",
        "-->",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.are.equals("In Progress", board.config.default_start_column)
      assert.are.equals("days", board.config.cycle_time_unit)
    end)

    it("should handle empty values gracefully", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Backlog",
        "- Task one <!-- priority: , complexity: 3 -->"
      })

      local card = board.columns[1].cards[1]
      assert.are.equals(3, card.properties.complexity)
      -- Empty value should be empty string or nil
      assert.is_true(card.properties.priority == "" or card.properties.priority == nil)
    end)
  end)
end)
