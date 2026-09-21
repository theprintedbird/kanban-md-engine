# Implementation Plan: Content Blocks with H6 Columns

## Overview

**Goal**: Refactor parser/writer to preserve arbitrary markdown by using content blocks architecture with H6 (`######`) headers for columns.

**Breaking Change**: Columns now use `######` instead of `##`.

**Why H6?**
- Clear semantic separation: H1 for board title, H2-H5 for user documentation, H6 for kanban columns
- Rare collision: H6 is almost never used in typical markdown
- Graceful degradation: Renders fine in any markdown viewer
- Obvious errors: If someone accidentally uses H6 elsewhere, it's immediately visible

---

## Problem Statement

The current parser/writer architecture only captures and reconstructs kanban-structured data:
- Board title
- Column headers
- Cards
- HTML comments (config/properties)

**Everything else is discarded**, including:
- Prose paragraphs and documentation
- Non-kanban sections (e.g., `## Instructions`, `## Notes`)
- Arbitrary content between/around kanban elements

This means any board modifications destroy user documentation.

---

## Solution: Content Blocks Architecture

### Core Concept

Extend the board structure to track **all content as ordered blocks**, where each block is either:
1. **Structured** (kanban elements: title, column, card) - generated from parsed data
2. **Unstructured** (arbitrary markdown) - preserved verbatim

### Example Board Structure

**Input Markdown**:
```md
# Sprint Planning Board

This is the description of our sprint board. It uses the kanban-md plugin.

## Instructions

1. Add cards to Backlog
2. Move them through the workflow

## Workflow Rules

Cards must meet DoD before moving to Done.

###### Backlog
- Research API design
- Write user stories

###### Ready
<!-- column:config wip_limit: 3 -->
- Set up CI/CD

###### In Progress
- Implement auth

###### Done
- Create repository

###### __ARCHIVE__
- Old completed tasks

## Statistics

Average cycle time: 3.2 days (this section is preserved, not interpreted as kanban)
```

**Internal Data Structure**:
```lua
{
  title = "Sprint Planning Board",
  columns = [Column, Column, ...],  -- Parsed kanban data

  content_blocks = [
    {type = "title"},
    {type = "markdown", lines = {"", "This is the description..."}},
    {type = "markdown", lines = {"", "## Instructions", "1. Add cards...", ...}},
    {type = "markdown", lines = {"", "## Workflow Rules", "Cards must..."}},
    {type = "markdown", lines = {""}},
    {type = "column", ref = columns[1]},  -- Backlog
    {type = "markdown", lines = {""}},
    {type = "column", ref = columns[2]},  -- Ready
    {type = "markdown", lines = {""}},
    {type = "column", ref = columns[3]},  -- In Progress
    {type = "markdown", lines = {""}},
    {type = "column", ref = columns[4]},  -- Done
    {type = "markdown", lines = {""}},
    {type = "column", ref = columns[5]},  -- Archive
    {type = "markdown", lines = {"", "## Statistics", "Average cycle time: 3.2 days..."}}
  ]
}
```

---

## Phase 1: Data Structure Changes

### 1.1 Extend Board Structure
**File**: `lua/kanban-md/board.lua`

**Changes**:
```lua
function Board:new()
  local obj = {
    id = nil,
    columns = {},
    config = {},
    triggers = {},
    trigger_order = {},
    -- NEW: Content blocks for preserving markdown
    content_blocks = {},
  }
  -- ... rest unchanged
end
```

### 1.2 Define Content Block Types
**New File**: `lua/kanban-md/content_block.lua`

**Purpose**: Type definitions and utilities for content blocks

```lua
local ContentBlock = {}

-- Block types
ContentBlock.TYPES = {
  MARKDOWN = "markdown",    -- Arbitrary markdown content
  TITLE = "title",         -- Board title (H1)
  BOARD_CONFIG = "board_config",  -- Board config comment
  COLUMN = "column",       -- Column section (H6)
  ARCHIVE = "archive",     -- Archive section
  STATS = "stats",         -- Stats section
}

-- Create a markdown block
function ContentBlock.markdown(lines)
  return {
    type = ContentBlock.TYPES.MARKDOWN,
    lines = lines
  }
end

-- Create a title block
function ContentBlock.title()
  return {
    type = ContentBlock.TYPES.TITLE
  }
end

-- Create a column block (references Column object)
function ContentBlock.column(column_ref)
  return {
    type = ContentBlock.TYPES.COLUMN,
    ref = column_ref
  }
end

return ContentBlock
```

---

## Phase 2: Parser Refactoring

### 2.1 Update Pattern Matching
**File**: `lua/kanban-md/parser.lua`

**Changes** (around line 17):
```lua
-- Line 17: Change column pattern from ## to ######
local patterns = {
  board_title = "^#%s+(.+)$",
  column_header = "^######%s+(.+)$",  -- CHANGED: H6 instead of H2
  task_item = "^%s*%-%s*(.+)$",
  -- ... rest unchanged

  -- NEW: Detect non-kanban sections (H2-H5)
  section_header = "^##[^#]",  -- H2-H5 headers

  -- Update special sections to use H6
  archive_section = "^######%s+__ARCHIVE__",
  stats_section = "^######%s+__STAT(ISTIC)?S__",
}
```

### 2.2 Implement Content Block Building
**File**: `lua/kanban-md/parser.lua`

**Add helper functions** (before `ParserMixin:parse`):

```lua
-- Helper: Flush accumulated markdown lines into a block
local function flush_markdown_buffer(board, buffer)
  if #buffer > 0 then
    local ContentBlock = require("kanban-md.content_block")
    table.insert(board.content_blocks, ContentBlock.markdown(vim.deepcopy(buffer)))
  end
end

-- Helper: Add a structured block reference
local function add_structured_block(board, block)
  local ContentBlock = require("kanban-md.content_block")
  table.insert(board.content_blocks, block)
end
```

### 2.3 Refactor Main Parse Function
**File**: `lua/kanban-md/parser.lua`

**Replace the parse function** (lines 236-440) with new logic that:
1. Maintains a `markdown_buffer` for non-kanban lines
2. Flushes buffer when encountering structured elements
3. Builds `content_blocks` array alongside existing parsed structures

**Key changes**:
- Add `markdown_buffer = {}` and `seen_title = false` tracking
- When encountering H1 (title): flush buffer, add title block
- When encountering H6 (column): flush buffer, parse column, add column block
- When encountering H2-H5 or other content: accumulate in markdown buffer
- At end: flush remaining markdown buffer

**Implementation note**: The existing logic for parsing cards, comments, properties, etc. remains unchanged. We're only adding the content block building layer on top.

---

## Phase 3: Writer Refactoring

### 3.1 Refactor Main Write Function
**File**: `lua/kanban-md/writer_mixin.lua`

**Replace the write function** (lines 179-260):

```lua
-- Main writer function
function WriterMixin:write()
  local config = config_module.get()
  local lines = {}

  -- Use content blocks if available (new behavior)
  if self.content_blocks and #self.content_blocks > 0 then
    return self:write_from_blocks()
  else
    -- Fallback: Generate structure without blocks (for programmatically created boards)
    return self:write_legacy()
  end
end

-- NEW: Write from content blocks (preserves markdown)
function WriterMixin:write_from_blocks()
  local config = config_module.get()
  local lines = {}

  for i, block in ipairs(self.content_blocks) do
    local ContentBlock = require("kanban-md.content_block")

    if block.type == ContentBlock.TYPES.MARKDOWN then
      -- Preserve markdown verbatim
      for _, line in ipairs(block.lines) do
        table.insert(lines, line)
      end

    elseif block.type == ContentBlock.TYPES.TITLE then
      -- Generate from current board title
      table.insert(lines, "# " .. (self.title or "Untitled Board"))

      -- Add board config if present (immediately after title)
      local plain_board_config = to_plain_table(self.config)
      if plain_board_config and not vim.tbl_isempty(plain_board_config) then
        local config_comment = properties_to_comment(plain_board_config, "kanban:config")
        if type(config_comment) == "table" then
          for _, line in ipairs(config_comment) do
            table.insert(lines, line)
          end
        else
          table.insert(lines, config_comment)
        end
      end

    elseif block.type == ContentBlock.TYPES.COLUMN then
      -- Generate from current column data
      local column = block.ref

      -- Column header (H6)
      table.insert(lines, "###### " .. column.name)

      -- Column configuration comment if present
      local plain_config = to_plain_table(column.config)
      if plain_config and not vim.tbl_isempty(plain_config) then
        local config_comment = properties_to_comment(plain_config, "column:config")
        if type(config_comment) == "table" then
          for _, line in ipairs(config_comment) do
            table.insert(lines, line)
          end
        else
          table.insert(lines, config_comment)
        end
      end

      -- Add blank line after header/config if configured and there are cards
      if config.blank_line_after_column_header and column.cards and #column.cards > 0 then
        table.insert(lines, "")
      end

      -- Cards (skip for stats columns)
      if not column.is_stats then
        for _, task in ipairs(column.cards or {}) do
          local task_output = write_task(task, column.name)
          if type(task_output) == "table" then
            for _, line in ipairs(task_output) do
              table.insert(lines, line)
            end
          else
            table.insert(lines, task_output)
          end
        end
      end
    end
  end

  return lines
end

-- Legacy write (for backwards compatibility, non-parsed boards)
function WriterMixin:write_legacy()
  -- Keep existing implementation but change ## to ######
  -- This is used when boards are created programmatically without parsing

  local config = config_module.get()
  local lines = {}

  -- Board title
  table.insert(lines, "# " .. (self.title or "Untitled Board"))
  -- ... rest of existing logic, but use ###### for columns instead of ##
end
```

---

## Phase 4: Column Operations

### 4.1 Add New Column Operation
**File**: `lua/kanban-md/board.lua`

**Add method**:
```lua
-- Add a new column to the board
-- Inserts column block before archive/stats if present, otherwise at end
function Board:add_new_column(name, config)
  local column = Column:new(nil, name)
  if config then
    column.config = TypeConverter:new(config)
  end

  table.insert(self.columns, column)

  -- If we have content blocks, insert column block at appropriate position
  if self.content_blocks and #self.content_blocks > 0 then
    local ContentBlock = require("kanban-md.content_block")
    local insert_pos = #self.content_blocks + 1

    -- Find position before archive or stats
    for i, block in ipairs(self.content_blocks) do
      if block.type == ContentBlock.TYPES.COLUMN then
        if block.ref and (block.ref.is_archive or block.ref.is_stats) then
          insert_pos = i
          break
        end
      end
    end

    table.insert(self.content_blocks, insert_pos, ContentBlock.column(column))
  end

  return column
end
```

---

## Phase 5: Testing

### 5.1 Parser Tests
**New File**: `tests/unit/parser_content_blocks_spec.lua`

Tests should cover:
- Parsing board with preamble text
- Distinguishing H2 sections from H6 columns
- Parsing multiple columns with preserved markdown between
- Handling blank lines and spacing
- Special sections (archive, stats) with H6

### 5.2 Writer Tests
**New File**: `tests/unit/writer_content_blocks_spec.lua`

Tests should cover:
- Preserving preamble text
- Preserving H2 sections
- Writing columns with H6
- Preserving markdown after card operations
- Round-trip consistency

### 5.3 Integration Tests
**New File**: `tests/integration/content_preservation_spec.lua`

Tests should cover:
- Full board lifecycle with mixed content
- Card operations preserving documentation
- Column operations preserving sections
- Archive operations preserving content

---

## Phase 6: Documentation Updates

### 6.1 Update README
**File**: `README.md`

**Changes needed**:
1. Update all example syntax to use `######` for columns
2. Add section explaining markdown preservation
3. Update "Example syntax" section (around line 28)
4. Document why H6 is used

**Example section to add**:

```md
## Markdown Syntax

kanban-md uses H6 headers (`######`) for column definitions, allowing you to include arbitrary markdown documentation in your boards.

### Basic Structure

\```md
# Sprint Planning Board

This board tracks our current sprint. Updated daily.

## How to Use

1. Add new cards to Backlog
2. Move cards through the workflow
3. Archive completed items weekly

###### Backlog
- Research API design
- Write user stories

###### In Progress
- Implement authentication

###### Done
- Set up CI/CD

###### __ARCHIVE__
- Old completed tasks
\```

### Why H6?

- **H1** (`#`) is reserved for the board title
- **H2-H5** (`##` to `#####`) can be used for documentation sections
- **H6** (`######`) marks kanban columns and is rarely used elsewhere
- If you accidentally use H6 for non-column headers, it will be obvious (tasks will appear underneath)


### 6.2 Update Example Files
**Files to update**:
- `tests/manual-tests/test_board.md`
- `tests/manual-tests/complexity_demo.md`
- Any other example boards

**Action**: Convert `## Column` to `###### Column` for all kanban columns, but keep `## Section` for documentation sections.

### 6.3 Update CLAUDE.md
**File**: `CLAUDE.md`

Update the project instructions to reflect:
- H6 headers for columns
- Content blocks architecture
- Markdown preservation feature

---

## Phase 7: Cleanup and Final Steps

### 7.1 Update Template Generation
**File**: `lua/kanban-md/templates.lua` (if exists)

Update any board generation templates to use H6 for columns.

### 7.2 Review All Code References
Search codebase for:
- Pattern `"^##"` used for column detection
- Comments mentioning H2 columns
- Documentation referring to `## Column`

### 7.3 Update Command Help Text
**File**: `plugin/kanban-md.lua`

Ensure all command descriptions are accurate.

---

## Implementation Checklist

### Phase 1: Data Structure ✓
- [x] Add `content_blocks` to Board structure (`board.lua`)
- [x] Create `content_block.lua` module with type definitions

### Phase 2: Parser ✓
- [x] Update patterns to use H6 (`parser.lua` line ~17)
- [x] Add `flush_markdown_buffer()` helper function
- [x] Add `add_structured_block()` helper function
- [x] Refactor `parse()` function to build content blocks
- [x] Update special section patterns (archive, stats)

### Phase 3: Writer ✓
- [x] Implement `write_from_blocks()` method
- [x] Update `write_legacy()` to use H6
- [x] Refactor main `write()` function to dispatch

### Phase 4: Column Operations ✓
- [x] Add `add_new_column()` method to Board
- [x] Ensure proper block insertion logic

### Phase 5: Testing ✓
- [x] Create `parser_content_blocks_spec.lua`
- [x] Create `writer_content_blocks_spec.lua`
- [x] Create `content_preservation_spec.lua`
- [x] Run full test suite with `./tests/run_tests.sh`

### Phase 6: Documentation ✓
- [x] Update README syntax examples
- [x] Add markdown preservation section to README
- [x] Update `tests/manual-tests/test_board.md`
- [x] Update `tests/manual-tests/complexity_demo.md`
- [x] Update `CLAUDE.md`

### Phase 7: Cleanup ✓
- [x] Update template generation (if applicable)
- [x] Search and fix remaining H2 references
- [x] Review command help text
- [x] Final test pass

---

## Edge Cases Handled

1. **User accidentally uses H6 for non-column**:
   - Cards will appear under it → immediately obvious
   - Fix: Change to H2-H5

2. **Markdown within column** (between cards):
   - Out of scope - notes should be at beginning/end, not mixed in list
   - Card-level notes should be part of the list item

3. **Column reordering**:
   - Reorder column blocks in `content_blocks` array
   - Markdown between columns moves with them

4. **Adding new column**:
   - If no config specified: place before archive/stats, or at end
   - User can manually reorder by editing the file
   - Parser/writer preserve layout as user has defined it

5. **Special sections** (`__ARCHIVE__`, `__STATS__`):
   - Use H6: `###### __ARCHIVE__`
   - Parser recognizes these specially

6. **Programmatically created boards** (no parse):
   - Use `write_legacy()` fallback
   - Generate structure without content blocks
   - Use H6 for columns

7. **Empty content blocks**:
   - Empty markdown buffers are not added as blocks
   - Prevents unnecessary empty block entries

---

## Risk Mitigation

1. **Breaking Change Impact**:
   - Clearly documented in README
   - Heuristic migration (auto-detect columns)

2. **Test Coverage**:
   - Comprehensive unit tests for parser/writer
   - Integration tests for full workflows

3. **Validation**:
   - Manual testing with real boards
   - Test with various markdown complexity levels

4. **Rollback Plan**:
   - Keep v1.x branch for emergency rollback

---

## Success Criteria

1. ✅ Parser preserves all markdown content
2. ✅ Writer reconstructs boards with preserved markdown
3. ✅ H2-H5 sections are never interpreted as columns
4. ✅ H6 sections are always interpreted as columns
5. ✅ Card operations (add, move, delete) preserve documentation
6. ✅ All existing tests pass
7. ✅ New content preservation tests pass
8. ✅ Round-trip fidelity maintained
9. ✅ Documentation is complete and accurate

---

## Implementation Notes

### Order of Implementation

Recommended order to minimize breaking changes during development:

1. **Phase 1** (Data Structure) - Non-breaking, adds new fields
2. **Phase 2** (Parser) - Updates parsing logic, builds content blocks
3. **Phase 3** (Writer) - Updates writing logic, uses content blocks
4. **Phase 5** (Testing) - Validate each phase as implemented
5. **Phase 6** (Documentation) - Document completed changes
6. **Phase 4** (Column Operations) - Enhanced operations after core works
7. **Phase 5** (Testing again) - Re-validate each phase as implemented
8. **Phase 6** (Documentation) - Re-document completed changes
9. **Phase 7** (Cleanup) - Final polish

### Development Tips

- Test frequently with `./tests/run_tests.sh`
- Keep backup of working test boards
- Test manually with example boards during development
- Use `_G._TEST = true` to expose private functions for testing
- Consider feature flag for gradual rollout

### Performance Considerations

- Content blocks add minimal memory overhead
- Parser complexity: O(n) where n = number of lines (same as before)
- Writer complexity: O(n) where n = number of blocks (same as before)
- No performance regression expected

---

## Future Enhancements

After this implementation, consider:

1. **Column metadata blocks**: Notes/documentation that belong to a column but aren't cards
2. **Board metadata sections**: Structured data about the board itself
3. **Custom block types**: Allow users to define their own block types
4. **Block-level styling**: Per-block rendering hints for UI
5. **Nested boards**: Boards within boards using different header levels

