-- Test that the complexity demo board parses and writes correctly

local Board = require('kanban-md.board')

print("\n=== Testing Complexity Demo Board ===\n")

-- Read the demo board
local file = io.open("tests/manual-tests/complexity_demo.md", "r")
if not file then
  error("Could not open complexity_demo.md")
end
local content = file:read("*all")
file:close()

-- Parse the board
local board = Board:new()
board:parse(content)

print("Board title:", board.title)
print("Number of columns:", #board.columns)
print()

-- Check cards have correct complexity values
print("To Do column cards:")
for i, card in ipairs(board.columns[1].cards) do
  local complexity = card.properties.complexity or "none"
  print(string.format("  %d. %s - complexity: %s", i, card.text, complexity))
end
print()

-- Verify specific complexity values
local todo_cards = board.columns[1].cards
assert(todo_cards[1].text == "Simple task", "First card should be 'Simple task'")
assert(todo_cards[1].properties.complexity == nil, "Simple task should have no complexity")

assert(todo_cards[2].text == "Medium task", "Second card should be 'Medium task'")
assert(todo_cards[2].properties.complexity == 3, "Medium task should have complexity 3")

assert(todo_cards[3].text == "Complex task", "Third card should be 'Complex task'")
assert(todo_cards[3].properties.complexity == 5, "Complex task should have complexity 5")

print("✓ All complexity values parsed correctly\n")

-- Test write and re-parse
print("Testing write/parse cycle:")
local lines = board:write()
local content2 = table.concat(lines, "\n")

local board2 = Board:new()
board2:parse(content2)

local todo_cards2 = board2.columns[1].cards
assert(todo_cards2[2].properties.complexity == 3, "Medium task complexity should persist")
assert(todo_cards2[3].properties.complexity == 5, "Complex task complexity should persist")

print("✓ Complexity values persist through write/parse cycle\n")

print("=== Demo Board Tests Passed! ===\n")
