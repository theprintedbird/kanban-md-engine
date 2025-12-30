-- Manual test for complexity feature (trigger-based implementation)
-- Run this from Neovim with :luafile tests/manual-tests/test_complexity.lua

local config = require('kanban-md.config')
local Board = require('kanban-md.board')
local Card = require('kanban-md.card')

print("\n=== Testing Complexity Feature (Trigger-Based) ===\n")

-- Test 1: Config values are set
print("Test 1: Config defaults")
print("  use_complexity:", config.get_value('use_complexity'))
print("  default_complexity:", config.get_value('default_complexity'))
assert(config.get_value('use_complexity') == false, "use_complexity should default to false")
assert(config.get_value('default_complexity') == 1, "default_complexity should default to 1")
print("  ✓ Config defaults are correct\n")

-- Test 2: Cards created without board context don't get auto-complexity
print("Test 2: Cards created standalone (no board context)")
local card1 = Card:new(nil, "Standalone card", {})
print("  Card complexity:", card1.properties.complexity)
assert(card1.properties.complexity == nil, "Standalone cards should not get auto-complexity")
print("  ✓ Standalone cards don't get auto-complexity\n")

-- Test 3: Auto-add complexity when card is added to a column (trigger-based)
print("Test 3: Auto-add complexity via trigger when use_complexity is enabled")
config.setup({ use_complexity = true, default_complexity = 3 })

local board = Board:new()
local col = board:add_column("todo", "To Do")
board:auto_register_triggers()

local card2 = Card:new(nil, "Test card")
col:add_card(card2)

print("  Card complexity after adding to column:", card2.properties.complexity)
assert(card2.properties.complexity == 3, "Card should get complexity via trigger when added to column")
print("  ✓ Complexity auto-added via trigger with correct default\n")

-- Test 4: Don't override existing complexity
print("Test 4: Don't override existing complexity")
local card3 = Card:new(nil, "Card with existing complexity", { complexity = 5 })
col:add_card(card3)

print("  Card complexity:", card3.properties.complexity)
assert(card3.properties.complexity == 5, "Existing complexity should not be overridden")
print("  ✓ Existing complexity preserved\n")

-- Test 5: Different default value
print("Test 5: Different default complexity value")
config.setup({ use_complexity = true, default_complexity = 8 })

local board2 = Board:new()
local col2 = board2:add_column("todo", "To Do")
board2:auto_register_triggers()

local card4 = Card:new(nil, "Test card with different default", {})
col2:add_card(card4)

print("  Card complexity:", card4.properties.complexity)
assert(card4.properties.complexity == 8, "Should use new default value")
print("  ✓ Different default value works\n")

-- Test 6: Board-level config override
print("Test 6: Board-level config overrides plugin config")
config.setup({ use_complexity = false })  -- Disable at plugin level

local board3 = Board:new()
board3.config.use_complexity = true  -- Enable at board level
board3.config.default_complexity = 10

local col3 = board3:add_column("todo", "To Do")
board3:auto_register_triggers()

local card5 = Card:new(nil, "Test card")
col3:add_card(card5)

print("  Card complexity:", card5.properties.complexity)
assert(card5.properties.complexity == 10, "Should use board-level default (10)")
print("  ✓ Board-level config overrides plugin config\n")

-- Reset config to defaults
config.reset()

print("=== All Tests Passed! ===\n")
