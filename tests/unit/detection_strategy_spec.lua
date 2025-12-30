-- tests/unit/detection_strategy_spec.lua
-- Tests for board detection strategy logic
require('polyfills.vim')

_G._TEST = true

local config = require("kanban-md.config")

-- Mock adapter for testing
local MockAdapter = {
  _buffer_name = "",
  get_buffer_name = function(self, bufnr)
    return self._buffer_name
  end
}

-- Helper to test detection logic
local function test_detection(lines, bufname, strategy)
  -- Simulate the detection logic from commands.lua
  local is_kanban = false

  -- Handle legacy config option for backwards compatibility
  if not strategy or strategy == "" then
    strategy = "marker" -- default
  end

  -- Check buffer name
  local has_kanban_extension = bufname and bufname:match("%.kanban%.md$") ~= nil

  if strategy == "marker" then
    -- Look for explicit <!-- kanban-board --> marker in first 10 lines
    for i = 1, math.min(10, #lines) do
      if lines[i]:match("<!%-%-%s*kanban%-board%s*%-%->") then
        is_kanban = true
        break
      end
    end
  elseif strategy == "extension" then
    -- Only parse files with .kanban.md extension
    is_kanban = has_kanban_extension
  elseif strategy == "both" then
    -- Accept either marker OR .kanban.md extension
    if has_kanban_extension then
      is_kanban = true
    else
      -- Check for marker
      for i = 1, math.min(10, #lines) do
        if lines[i]:match("<!%-%-%s*kanban%-board%s*%-%->") then
          is_kanban = true
          break
        end
      end
    end
  elseif strategy == "auto" then
    -- Legacy behaviour: Look for H6 headers (######) which are used for columns
    for _, line in ipairs(lines) do
      if line:match("^######%s+") then
        is_kanban = true
        break
      end
    end
  end

  return is_kanban
end

describe("Board detection strategies", function()
  local test_lines_with_marker = {
    "<!-- kanban-board -->",
    "# Test Board",
    "",
    "###### Todo",
    "- Task 1"
  }

  local test_lines_without_marker = {
    "# Test Board",
    "",
    "###### Todo",
    "- Task 1"
  }

  local test_lines_no_h6 = {
    "# Regular Markdown",
    "",
    "Some text here.",
    "No kanban columns."
  }

  describe("marker strategy", function()
    it("should detect files with kanban-board marker", function()
      local detected = test_detection(test_lines_with_marker, "board.md", "marker")
      assert.is_true(detected)
    end)

    it("should NOT detect files without marker even with H6 headers", function()
      local detected = test_detection(test_lines_without_marker, "board.md", "marker")
      assert.is_false(detected)
    end)

    it("should NOT detect .kanban.md files without marker", function()
      local detected = test_detection(test_lines_without_marker, "board.kanban.md", "marker")
      assert.is_false(detected)
    end)

    it("should detect marker within first 10 lines", function()
      local lines_with_late_marker = {
        "# Some Board",
        "",
        "",
        "",
        "",
        "<!-- kanban-board -->",
        "###### Todo"
      }
      local detected = test_detection(lines_with_late_marker, "board.md", "marker")
      assert.is_true(detected)
    end)

    it("should NOT detect marker after line 10", function()
      local lines_with_very_late_marker = {
        "# Some Board",
        "", "", "", "", "", "", "", "", "",
        "<!-- kanban-board -->", -- line 11
        "###### Todo"
      }
      local detected = test_detection(lines_with_very_late_marker, "board.md", "marker")
      assert.is_false(detected)
    end)
  end)

  describe("extension strategy", function()
    it("should detect .kanban.md files", function()
      local detected = test_detection(test_lines_without_marker, "board.kanban.md", "extension")
      assert.is_true(detected)
    end)

    it("should NOT detect regular .md files", function()
      local detected = test_detection(test_lines_with_marker, "board.md", "extension")
      assert.is_false(detected)
    end)

    it("should NOT detect files without .kanban.md extension even with marker", function()
      local detected = test_detection(test_lines_with_marker, "README.md", "extension")
      assert.is_false(detected)
    end)

    it("should detect project.kanban.md", function()
      local detected = test_detection(test_lines_no_h6, "project.kanban.md", "extension")
      assert.is_true(detected)
    end)
  end)

  describe("both strategy", function()
    it("should detect .kanban.md files without marker", function()
      local detected = test_detection(test_lines_without_marker, "board.kanban.md", "both")
      assert.is_true(detected)
    end)

    it("should detect regular .md files with marker", function()
      local detected = test_detection(test_lines_with_marker, "board.md", "both")
      assert.is_true(detected)
    end)

    it("should detect .kanban.md files with marker", function()
      local detected = test_detection(test_lines_with_marker, "board.kanban.md", "both")
      assert.is_true(detected)
    end)

    it("should NOT detect regular .md files without marker", function()
      local detected = test_detection(test_lines_without_marker, "README.md", "both")
      assert.is_false(detected)
    end)
  end)

  describe("auto strategy (legacy)", function()
    it("should detect files with H6 headers", function()
      local detected = test_detection(test_lines_without_marker, "board.md", "auto")
      assert.is_true(detected)
    end)

    it("should NOT detect files without H6 headers", function()
      local detected = test_detection(test_lines_no_h6, "board.md", "auto")
      assert.is_false(detected)
    end)

    it("should detect README.md with H6 headers (legacy problem)", function()
      local readme_lines = {
        "# My Project",
        "",
        "## Example",
        "",
        "```md",
        "###### Todo",
        "- Task 1",
        "```"
      }
      local detected = test_detection(readme_lines, "README.md", "auto")
      assert.is_true(detected, "This demonstrates why auto strategy is not recommended")
    end)

    it("should ignore marker when using auto strategy", function()
      local detected = test_detection(test_lines_with_marker, "board.md", "auto")
      -- Should still detect based on H6 headers
      assert.is_true(detected)
    end)

    it("should ignore extension when using auto strategy", function()
      local detected = test_detection(test_lines_without_marker, "board.kanban.md", "auto")
      -- Should detect based on H6 headers
      assert.is_true(detected)
    end)
  end)

  describe("backwards compatibility", function()
    it("should handle empty strategy by defaulting to marker", function()
      local detected = test_detection(test_lines_with_marker, "board.md", "")
      assert.is_true(detected)
    end)

    it("should handle nil strategy by defaulting to marker", function()
      local detected = test_detection(test_lines_with_marker, "board.md", nil)
      assert.is_true(detected)
    end)
  end)
end)
