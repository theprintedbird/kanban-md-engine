#!/usr/bin/env lua
--- CLI Example: Standalone usage of kanban-md without Neovim
--- This demonstrates how to use the kanban-md core engine in a pure Lua environment
--- with the CLI adapter for command-line applications, automation scripts, or CI/CD.
---
--- Usage:
---   lua examples/cli_example.lua

-- Add the project to the Lua path so we can require modules
local script_dir = debug.getinfo(1).source:match("@?(.*/)")
package.path = script_dir .. "../lua/?.lua;" .. script_dir .. "../lua/?/init.lua;" .. package.path

print("=== Kanban-MD CLI Example ===\n")

-- Step 1: Load the CLI entry point and initialise kanban-md
print("1. Initialising kanban-md with CLI adapter...")

local kanban = require('kanban-md.cli')

-- Setup kanban-md with CLI adapter (no Neovim required!)
kanban.setup({
  auto_id = true,           -- Auto-generate card IDs
  auto_timestamp = true,    -- Auto-timestamp column transitions
  wip_limit = 10,          -- Default WIP limit
})

print("✓ Initialised with CLI adapter\n")

-- Step 2: Load a board from a file
print("2. Loading board from file...")

local Board = require('kanban-md.board')
local board = Board:new()

-- Read the sample board file
local file_path = script_dir .. "sample_board.md"
local file = io.open(file_path, "r")

if not file then
  print("✗ Could not open sample_board.md")
  print("  Make sure you're running from the project root or examples/ directory")
  os.exit(1)
end

local content = file:read("*all")
file:close()

-- Parse the markdown into board structure
board:parse(content)

-- Calculate statistics after parsing
board:calculate_stats()

print(string.format("✓ Loaded board: '%s'", board.title))
print(string.format("  Columns: %d", #board.columns))
print(string.format("  Total cards: %d\n", board.stats.total_card_count or 0))

-- Step 3: Display board statistics
print("3. Board statistics:")
print(string.format("  WIP (all active columns): %d", board.stats.total_wip or 0))
print(string.format("  Board WIP limit: %s", board.config.wip_limit or "none"))

-- Display column-by-column breakdown
for _, col in ipairs(board.columns) do
  local wip_info = col.config.wip_limit
    and string.format(" (limit: %d)", col.config.wip_limit)
    or ""
  print(string.format("  - %-15s %d cards%s", col.name .. ":", #col.cards, wip_info))
end
print()

-- Step 4: Find and inspect a specific card
print("4. Finding a card by name...")

local target_card = nil
local current_column = nil
for _, col in ipairs(board.columns) do
  for _, card in ipairs(col.cards) do
    -- Cards use 'text' field for the card content
    local card_text = card and card.text
    if card_text and card_text:match("CLI adapter") then
      target_card = card
      current_column = col
      break
    end
  end
  if target_card then break end
end

if target_card then
  print(string.format("✓ Found card: '%s'", target_card.text))
  print(string.format("  ID: %s", target_card.properties.id or "none"))
  print(string.format("  Complexity: %s", target_card.properties.complexity or "none"))
  print(string.format("  Assignee: %s", target_card.properties.assignee or "unassigned"))

  print(string.format("  Current column: %s\n", current_column and current_column.name or "unknown"))
else
  print("✗ Card not found\n")
end

-- Step 5: Move a card between columns
print("5. Moving a card...")

if target_card and current_column then
  -- Find the "Review" column
  local review_column = nil
  for _, col in ipairs(board.columns) do
    if col.name == "Review" then
      review_column = col
      break
    end
  end

  if review_column then
    print(string.format("  Moving '%s' from '%s' to '%s'...",
      target_card.text, current_column.name, review_column.name))

    -- Perform the move
    local success, err = board:move_card(target_card, current_column, review_column)

    if success then
      print("✓ Card moved successfully")

      -- Verify the move
      local found_in_review = false
      for _, card in ipairs(review_column.cards) do
        if card == target_card then
          found_in_review = true
          break
        end
      end
      print(string.format("  Card now in '%s': %s\n", review_column.name, found_in_review and "yes" or "no"))
    else
      print(string.format("✗ Move failed: %s\n", err or "unknown error"))
    end
  else
    print("✗ Review column not found\n")
  end
else
  print("  Skipping move (no target card)\n")
end

-- Step 6: Add a new card
print("6. Adding a new card...")

local todo_column = board:get_column_by_name("Backlog")
if todo_column then
  -- Create a new Card object
  local Card = require('kanban-md.card')
  local new_card = Card:new("New feature request")
  new_card.properties.complexity = 3
  new_card.properties.assignee = "charlie"

  -- Add the card to the column
  todo_column:add_card(new_card)

  print(string.format("✓ Added card: '%s'", new_card.text))
  print(string.format("  ID: %s", new_card.properties.id or "none"))
  print(string.format("  Column '%s' now has %d cards\n", todo_column.name, #todo_column.cards))
else
  print("✗ Backlog column not found\n")
end

-- Step 7: Calculate statistics
print("7. Recalculating statistics...")

board:calculate_stats()

print(string.format("✓ Statistics updated"))
print(string.format("  Total cards: %d", board.stats.total_card_count or 0))
print(string.format("  Active WIP: %d", board.stats.total_wip or 0))
print(string.format("  Total complexity: %d\n", board.stats.total_complexity or 0))

-- Step 8: Write the modified board back to markdown
print("8. Writing modified board to string...")

local output_markdown = board:write()

print(string.format("✓ Generated markdown (%d lines)", #output_markdown))
print(string.format("  First line: %s", output_markdown[1] or ""))

-- Optionally write to a file
local output_file_path = script_dir .. "sample_board_modified.md"
local output_file = io.open(output_file_path, "w")

if output_file then
  for _, line in ipairs(output_markdown) do
    output_file:write(line .. "\n")
  end
  output_file:close()
  print(string.format("✓ Saved to: %s\n", output_file_path))
else
  print("✗ Could not write output file\n")
end

-- Step 9: Demonstrate validation
print("9. Board validation...")

board:validate()

if #board.validation.errors > 0 then
  print(string.format("✗ Validation errors found (%d):", #board.validation.errors))
  for _, error in ipairs(board.validation.errors) do
    print(string.format("  - %s", error))
  end
else
  print("✓ No validation errors")
end

if #board.validation.warnings > 0 then
  print(string.format("⚠ Validation warnings (%d):", #board.validation.warnings))
  for _, warning in ipairs(board.validation.warnings) do
    print(string.format("  - %s", warning))
  end
else
  print("✓ No validation warnings")
end
print()

-- Step 10: Show archive functionality
print("10. Archive functionality...")

local done_column = board:get_column_by_name("Done")
if done_column and #done_column.cards > 0 then
  local cards_to_archive = #done_column.cards
  print(string.format("  Cards in Done column: %d", cards_to_archive))

  -- Archive all done cards
  local archive_column = board:get_column_by_name("__ARCHIVE__")
  if not archive_column then
    archive_column = board:add_column("__ARCHIVE__")
    print("  Created archive column")
  end

  -- Move cards to archive
  local archived_count = 0
  for i = #done_column.cards, 1, -1 do
    local card = done_column.cards[i]
    local success = board:move_card(card, done_column, archive_column)
    if success then
      archived_count = archived_count + 1
    end
  end

  print(string.format("✓ Archived %d cards\n", archived_count))
else
  print("  No cards in Done column to archive\n")
end

-- Summary
print("=== Summary ===")
print("This example demonstrated:")
print("  ✓ Loading the CLI adapter without Neovim")
print("  ✓ Parsing a markdown kanban board")
print("  ✓ Reading board statistics and card properties")
print("  ✓ Moving cards between columns")
print("  ✓ Adding new cards programmatically")
print("  ✓ Validating board state")
print("  ✓ Writing the modified board back to markdown")
print("  ✓ Archive functionality")
print()
print("All operations completed without Neovim!")
print("Check 'sample_board_modified.md' to see the changes.")
