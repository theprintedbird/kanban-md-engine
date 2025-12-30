-- Quick diagnostic for cursor positioning
-- Run in Neovim with: :luafile tests/manual-tests/diagnose_cursor.lua
-- Or: :lua dofile('tests/manual-tests/diagnose_cursor.lua')

local function diagnose()
  print("\n=== Cursor Positioning Diagnostic ===\n")

  -- Check 1: Config value
  local config = require('kanban-md.config')
  local enabled = config.get_value('enable_cursor_positioning')
  print("1. Config: enable_cursor_positioning = " .. tostring(enabled))

  if not enabled then
    print("   ❌ DISABLED - enable it in your config")
    return
  end
  print("   ✓ ENABLED\n")

  -- Check 2: Parse current buffer
  print("2. Parsing current buffer...")
  local Board = require('kanban-md.board')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local board = Board:new()
  board:parse(lines)

  if #board.columns == 0 then
    print("   ❌ No columns found")
    return
  end
  print("   ✓ Found " .. #board.columns .. " columns\n")

  -- Check 3: Verify triggers registered
  print("3. Checking trigger registration:")
  local found_trigger = false
  for _, col in ipairs(board.columns) do
    local triggers = col:get_triggers("on_entry")
    if triggers and triggers["mark_for_cursor"] then
      print("   ✓ Column '" .. col.name .. "' HAS cursor trigger")
      found_trigger = true
    else
      print("   ❌ Column '" .. col.name .. "' MISSING cursor trigger")
    end
  end

  if not found_trigger then
    print("\n   PROBLEM: No triggers registered!")
    print("   This means auto_register_triggers() didn't run or failed")
    return
  end
  print("")

  -- Check 4: Test adding a card
  print("4. Testing card addition:")
  local Card = require('kanban-md.card')
  local test_col = board.columns[1]
  local test_card = Card:new("test", "Test Card")

  local success, err = pcall(function()
    test_col:add_card(test_card)
  end)

  if not success then
    print("   ❌ Failed to add card: " .. tostring(err))
    return
  end

  if test_card.properties._cursor_target then
    print("   ✓ Card has _cursor_target flag")
  else
    print("   ❌ Card MISSING _cursor_target flag")
    print("   Available properties:")
    for k, v in pairs(test_card.properties:to_table()) do
      print("     - " .. k .. " = " .. tostring(v))
    end
  end

  print("\n=== Diagnostic Complete ===\n")
end

-- Run it
local ok, err = pcall(diagnose)
if not ok then
  print("ERROR: " .. tostring(err))
end
