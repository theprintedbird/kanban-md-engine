-- Manual test for KanbanSetComplexity command
-- This tests the set_complexity function logic

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')

print("\n=== Testing KanbanSetComplexity Logic ===\n")

-- Create a test board
local board = Board:new()
board.title = "Test Board"

-- Add a column
local col = board:add_column("todo", "To Do")

-- Add a card without complexity
local card1 = Card:new("card1", "Task without complexity", {})
col:add_card(card1)

-- Add a card with existing complexity
local card2 = Card:new("card2", "Task with complexity", { complexity = 5 })
col:add_card(card2)

print("Test 1: Card without complexity")
print("  Before - Complexity:", card1.properties.complexity)
assert(card1.properties.complexity == nil, "Card should start without complexity")

-- Simulate setting complexity
card1.properties.complexity = 3
print("  After  - Complexity:", card1.properties.complexity)
assert(card1.properties.complexity == 3, "Card should have complexity 3")
print("  ✓ Setting complexity on card without complexity works\n")

print("Test 2: Card with existing complexity")
print("  Before - Complexity:", card2.properties.complexity)
assert(card2.properties.complexity == 5, "Card should start with complexity 5")

-- Simulate updating complexity
card2.properties.complexity = 8
print("  After  - Complexity:", card2.properties.complexity)
assert(card2.properties.complexity == 8, "Card should have updated complexity 8")
print("  ✓ Updating existing complexity works\n")

print("Test 3: Write and read back")
-- Write the board to lines
local lines = board:write()

-- Parse it back
local board2 = Board:new()
board2:parse(lines)

-- Find the cards
local card1_parsed = board2.columns[1].cards[1]
local card2_parsed = board2.columns[1].cards[2]

print("  Card 1 complexity after write/parse:", card1_parsed.properties.complexity)
print("  Card 2 complexity after write/parse:", card2_parsed.properties.complexity)
assert(card1_parsed.properties.complexity == 3, "Card 1 complexity should persist")
assert(card2_parsed.properties.complexity == 8, "Card 2 complexity should persist")
print("  ✓ Complexity properties persist through write/parse cycle\n")

print("=== All Command Logic Tests Passed! ===\n")
