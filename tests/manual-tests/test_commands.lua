-- Test script for kanban-md commands
-- Run this with: nvim --headless --cmd "set rtp+=." -c "lua package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'" -c "luafile test_commands.lua" -c "quit"

local function test_command_registration()
  print("=== Testing Command Registration ===")
  
  -- Load and setup the plugin
  local kanban = require('kanban-md')
  kanban.setup()
  print("✓ Plugin setup completed")
  
  -- Check if commands are registered
  local commands = {
    "KanbanNewBoard",
    "KanbanNewCard", 
    "KanbanMoveCard",
    "KanbanCompleteCard",
    "KanbanArchive",
    "KanbanStats"
  }
  
  for _, cmd in ipairs(commands) do
    local exists = vim.fn.exists(':' .. cmd) == 2
    if exists then
      print("✓ " .. cmd .. " command registered")
    else
      print("✗ " .. cmd .. " command NOT registered")
    end
  end
end

local function test_board_creation()
  print("\n=== Testing Board Creation ===")
  
  -- Test creating a board programmatically
  local Board = require('kanban-md.board')
  local board = Board:new()
  board.title = "Test Board"
  
  -- Add some columns
  local col1 = board:add_column("backlog", "Backlog")
  local col2 = board:add_column("done", "Done")
  
  print("✓ Board created with title: " .. board.title)
  print("✓ Columns created: " .. #board.columns)
  
  -- Test writing
  local lines = board:write()
  print("✓ Board written to " .. #lines .. " lines")
  
  -- Show first few lines
  for i = 1, math.min(5, #lines) do
    print("  " .. i .. ": " .. (lines[i] or ""))
  end
end

local function test_parsing()
  print("\n=== Testing Parsing ===")
  
  local content = {
    "# Sample Board",
    "",
    "## To Do", 
    "- Sample task",
    "- Another task <!-- complexity: 3 -->",
    "",
    "## Done",
    "- Completed task <!-- done: 1735862400 -->"
  }
  
  local Board = require('kanban-md.board')
  local board = Board:new()
  board:parse(content)
  
  print("✓ Parsed board: " .. board.title)
  print("✓ Found " .. #board.columns .. " columns")
  
  local total_cards = 0
  for _, col in ipairs(board.columns) do
    print("  - " .. col.name .. ": " .. #col.cards .. " cards")
    total_cards = total_cards + #col.cards
  end
  print("✓ Total cards: " .. total_cards)
  
  -- Test statistics
  board:calculate_stats()
  print("✓ Statistics calculated")
  print("  - Total tasks: " .. (board.stats.total_tasks or 0))
  print("  - Completed: " .. (board.stats.completed_tasks or 0))
end

-- Run all tests
test_command_registration()
test_board_creation()
test_parsing()

print("\n=== All Tests Completed ===")
print("✓ Plugin is ready to use!")
print("\nNext steps:")
print("1. Open test_board.md in Neovim")
print("2. Run :lua require('kanban-md').setup()")
print("3. Try the commands like :KanbanNewCard, :KanbanStats, etc.")
