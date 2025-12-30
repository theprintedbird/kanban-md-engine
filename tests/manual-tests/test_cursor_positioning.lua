-- Manual test for cursor positioning feature
-- Run this in Neovim with: :luafile tests/manual-tests/test_cursor_positioning.lua

print("=== Testing Cursor Positioning Feature ===\n")

-- 1. Check if config is set correctly
local config = require('kanban-md.config')
local is_enabled = config.get_value('enable_cursor_positioning')
print("1. Config check:")
print("   enable_cursor_positioning = " .. tostring(is_enabled))

if not is_enabled then
  print("   ERROR: Cursor positioning is disabled!")
  print("   Make sure to call setup() with enable_cursor_positioning = true")
  return
end

-- 2. Test programmatically creating a board and adding a card
print("\n2. Testing trigger registration:")
local Board = require('kanban-md.board')
local Card = require('kanban-md.card')

local board = Board:new()
board.title = "Test Board"
local todo_col = board:add_column("todo", "Todo")

print("   Board created with Todo column")

-- Register triggers (this is what parser does)
board:auto_register_triggers()
print("   Triggers registered")

-- Check if trigger was registered
local triggers = todo_col:get_triggers("on_entry")
if triggers and triggers["mark_for_cursor"] then
  print("   ✓ Cursor trigger found on Todo column")
else
  print("   ✗ ERROR: Cursor trigger NOT found on Todo column")
  print("   Available triggers:")
  for event_type, trigger_list in pairs(todo_col.triggers or {}) do
    print("     " .. event_type .. ":")
    for name, _ in pairs(trigger_list) do
      print("       - " .. name)
    end
  end
end

-- 3. Test adding a card and checking for flag
print("\n3. Testing card addition:")
local card = Card:new("card-1", "Test task")
todo_col:add_card(card)

if card.properties._cursor_target then
  print("   ✓ Card has _cursor_target flag")
else
  print("   ✗ ERROR: Card does NOT have _cursor_target flag")
  print("   Card properties:")
  for k, v in pairs(card.properties:to_table()) do
    print("     " .. k .. " = " .. tostring(v))
  end
end

-- 4. Test that it doesn't appear in markdown
print("\n4. Testing markdown output:")
local lines = board:write()
local markdown = table.concat(lines, "\n")

if markdown:find("_cursor_target") then
  print("   ✗ ERROR: _cursor_target found in markdown output")
  print("   Markdown:")
  for i, line in ipairs(lines) do
    print("     " .. i .. ": " .. line)
  end
else
  print("   ✓ _cursor_target not in markdown output")
end

-- 5. Test the helper function
print("\n5. Testing cursor positioning helper:")

-- Create a buffer with the board content
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

-- Switch to the buffer
vim.api.nvim_set_current_buf(bufnr)

-- Parse it back (simulating what commands.lua does)
local commands = require('kanban-md.commands')
-- Access the private function via debug
local move_cursor = debug.getupvalue(commands.new_card, 6)  -- Get move_cursor_to_target_card function

if move_cursor then
  print("   Found move_cursor_to_target_card function")
  local success, result = pcall(move_cursor)
  if success then
    if result then
      print("   ✓ Cursor moved successfully")
      local cursor = vim.api.nvim_win_get_cursor(0)
      print("   Cursor at line: " .. cursor[1])
    else
      print("   ✗ Cursor move returned false (card not found)")
    end
  else
    print("   ✗ ERROR calling move_cursor: " .. tostring(result))
  end
else
  print("   ✗ ERROR: Could not find move_cursor_to_target_card function")
end

print("\n=== Test Complete ===")
