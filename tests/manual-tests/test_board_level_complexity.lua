-- End-to-end test for board-level complexity configuration
-- Tests the complete workflow: parse → add cards → write → parse again

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')

print("\n=== Board-Level Complexity Configuration E2E Test ===\n")

-- Test 1: Parse a board with board-level complexity config
print("Test 1: Parse board with complexity config in markdown")
local content = [[
# Sprint Planning
<!-- kanban:config use_complexity: true, default_complexity: 5 -->

## Backlog
- Existing task without complexity
- Estimated task <!-- complexity: 8 -->

## In Progress
- Current work <!-- complexity: 3 -->
]]

local board = Board:new()
board:parse(content)

print("  Board title:", board.title)
print("  Board use_complexity:", board.config.use_complexity)
print("  Board default_complexity:", board.config.default_complexity)

assert(board.title == "Sprint Planning", "Board title should match")
assert(board.config.use_complexity == true, "Board should have use_complexity enabled")
assert(board.config.default_complexity == 5, "Board should have default_complexity = 5")
print("  ✓ Board config parsed correctly from markdown\n")

-- Test 2: Cards parsed from markdown only have what's explicitly set
print("Test 2: Parsed cards preserve markdown complexity values")
local backlog = board.columns[1]
local card1 = backlog.cards[1]
local card2 = backlog.cards[2]

print("  Card 1 text:", card1.text)
print("  Card 1 complexity:", card1.properties.complexity)
print("  Card 2 text:", card2.text)
print("  Card 2 complexity:", card2.properties.complexity)

assert(card1.text == "Existing task without complexity", "Card 1 text should match")
assert(card1.properties.complexity == nil, "Card 1 should NOT have auto-added complexity (parsing preserves markdown)")
assert(card2.text == "Estimated task", "Card 2 text should match")
assert(card2.properties.complexity == 8, "Card 2 should keep its explicit complexity")
print("  ✓ Parsed cards preserve markdown values\n")

-- Test 3: New cards added after parsing get auto-complexity
print("Test 3: New cards added after parsing get auto-complexity")
local new_card = Card:new("new-1", "New task after parsing")
backlog:add_card(new_card)

print("  New card text:", new_card.text)
print("  New card complexity:", new_card.properties.complexity)

assert(new_card.properties.complexity == 5, "New card should get board's default_complexity (5)")
print("  ✓ New cards get auto-complexity from board config\n")

-- Test 4: Write and re-parse preserves complexity
print("Test 4: Write and re-parse cycle")
local lines = board:write()
local markdown_output = table.concat(lines, "\n")

print("Generated markdown (first 10 lines):")
for i = 1, math.min(10, #lines) do
  print("  " .. lines[i])
end
print()

local board2 = Board:new()
board2:parse(lines)

-- Check board config persisted
assert(board2.config.use_complexity == true, "Board config should persist")
assert(board2.config.default_complexity == 5, "Board default_complexity should persist")

-- Check card complexity values persisted
local backlog2 = board2.columns[1]
assert(backlog2.cards[1].properties.complexity == nil, "Card 1 should still have no complexity")
assert(backlog2.cards[2].properties.complexity == 8, "Card 2 should still have complexity 8")
assert(backlog2.cards[3].properties.complexity == 5, "Card 3 (new card) should still have complexity 5")

print("  ✓ Complexity values persist through write/parse cycle\n")

-- Test 5: Add another card to the re-parsed board
print("Test 5: Add card to re-parsed board")
local another_card = Card:new("new-2", "Another new task")
backlog2:add_card(another_card)

print("  Another card complexity:", another_card.properties.complexity)
assert(another_card.properties.complexity == 5, "Card added to re-parsed board should get default_complexity (5)")
print("  ✓ Board config works after re-parsing\n")

-- Test 6: Board without complexity config doesn't auto-add
print("Test 6: Board without complexity config")
local content_no_config = [[
# Simple Board

## To Do
- Simple task
]]

local board3 = Board:new()
board3:parse(content_no_config)

local simple_card = Card:new("simple-1", "New simple task")
board3.columns[1]:add_card(simple_card)

print("  Board use_complexity:", board3.config.use_complexity)
print("  New card complexity:", simple_card.properties.complexity)

assert(simple_card.properties.complexity == nil, "Card should NOT have complexity when board doesn't enable it")
print("  ✓ Boards without complexity config don't auto-add\n")

print("=== All E2E Tests Passed! ===\n")
