# Multi-Line List Items Support

## Overview

Enable full CommonMark-compliant multi-line list item parsing for cards whilst preserving the ability to include column-level documentation and prose between cards.

## Parsing Rules

### List Item Continuation

A line is considered a continuation of the previous list item if:
1. The previous line was a list item OR a continuation line
2. The current line is indented by 2+ spaces
3. There is NO blank line between the previous line and current line
4. The current line does NOT start with a bullet marker (`-`)

### Column Documentation

A block of text is treated as column-level markdown (not card content) if:
1. It appears before any list items in the column, OR
2. It follows a blank line after a list item AND does not start with a bullet marker (`-`)

### List Item Boundaries

List items are separated by:
- Another list item marker (`-`)
- A blank line followed by non-list content (column documentation)
- The end of the column section (next column header or board end)

## Example

```markdown
# Board

This is board-level documentation

###### Backlog

This is column documentation before any cards

- list item 1
- list item 2
  has a continuation line
  and another continuation line
- list item 3

This is column documentation (blank line above + no bullet)

More column documentation here

- list item 4
  with continuation

###### TODO

Column documentation for TODO
```

**Parsing result:**
- Board content block: "This is board-level documentation"
- Column "Backlog":
  - Markdown block: "This is column documentation before any cards"
  - Card 1: "list item 1"
  - Card 2: "list item 2\n  has a continuation line\n  and another continuation line"
  - Card 3: "list item 3"
  - Markdown block: "This is column documentation...\n\nMore column documentation here"
  - Card 4: "list item 4\n  with continuation"
- Column "TODO":
  - Markdown block: "Column documentation for TODO"

## State Machine

The parser maintains state whilst processing lines within a column:

**States:**
- `card_active` - Currently accumulating lines for a card
- `markdown_buffer` - Currently accumulating column documentation
- `blank_line_seen` - Just saw a blank line (determines next state transition)

**Transitions:**
```
State: card_active
  Current line: blank → Set blank_line_seen, stay in card_active
  Current line: bullet (-) → Flush card, start new card
  Current line: indented (2+ spaces) + no blank before → Add to card continuation
  Current line: not indented + no bullet → Invalid (error or flush to markdown)

State: blank_line_seen (after card)
  Current line: bullet (-) → Flush card, start new card
  Current line: no bullet → Flush card, transition to markdown_buffer
  Current line: column header → Flush card, end column

State: markdown_buffer
  Current line: bullet (-) → Flush markdown, start card
  Current line: no bullet → Add to markdown buffer
  Current line: column header → Flush markdown, end column
```

## Data Structure Changes

### Card Class (`lua/kanban-md/card.lua`)

Add a `content_lines` field to store multi-line content:

```lua
local obj = {
    id = id,
    text = text or "",              -- First line (for display/compatibility)
    content_lines = nil,            -- Array of ALL lines (including first line)
    properties = props,
    column = nil,
    triggers = {},
    trigger_order = {}
}
```

**Fields:**
- `text` - The first line of the card (for backwards compatibility, display purposes)
- `content_lines` - Array of all lines including continuations (nil for single-line cards)

**Helper method:**
```lua
function Card:get_full_text()
    if self.content_lines then
        return table.concat(self.content_lines, "\n")
    end
    return self.text
end
```

## Parser Changes (`lua/kanban-md/parser_mixin.lua`)

### New Helper Functions

```lua
-- Detect if a line is indented by 2+ spaces
local function is_continuation_line(line)
    return line:match("^  +")  -- 2+ spaces at start
end

-- Detect if a line has a list marker
local function has_list_marker(line)
    return line:match("^%s*%-%s+")
end
```

### Modified parse_task Function

Update `parse_task()` to return a task object that can accumulate continuation lines:

```lua
local function parse_task(line)
    local task = {
        text = "",
        content_lines = {line},  -- Start with first line
        properties = TypeConverter:new({}),
        raw = line,
    }

    -- Extract task text (same logic as before)
    -- ... existing property extraction code ...

    return task
end
```

### Parser Main Loop Modifications

Add state tracking variables before the main loop:
```lua
local current_card = nil          -- Card being accumulated
local blank_line_seen = false     -- Track blank lines
```

Update the card parsing section to implement the state machine:
```lua
-- Within column section
elseif current_column then
    local is_blank = line:match("^%s*$")
    local is_task = line:match(patterns.task_item)
    local is_continuation = is_continuation_line(line)

    -- Handle blank lines
    if is_blank then
        if current_card then
            blank_line_seen = true
        end
        table.insert(markdown_buffer, line)
        add_to_markdown = false

    -- Handle list items
    elseif is_task then
        -- Flush current card if any
        if current_card then
            finalize_card(current_column, current_card)
            current_card = nil
        end

        -- Flush markdown buffer
        flush_markdown_buffer(board, markdown_buffer)
        markdown_buffer = {}

        -- Start new card
        current_card = parse_task(line)
        current_card.line_number = line_number
        current_card.column = current_column.name
        blank_line_seen = false
        add_to_markdown = false

    -- Handle continuation lines
    elseif current_card and is_continuation and not blank_line_seen then
        table.insert(current_card.content_lines, line)
        add_to_markdown = false

    -- Handle column documentation
    else
        -- Flush current card if transitioning to markdown
        if current_card then
            finalize_card(current_column, current_card)
            current_card = nil
        end

        table.insert(markdown_buffer, line)
        add_to_markdown = false
        blank_line_seen = false
    end
end
```

Add helper to finalize a card:
```lua
local function finalize_card(column, card_data)
    -- Extract text from first line
    local first_line = card_data.content_lines[1]
    local text = first_line:match(patterns.task_item)

    -- Check for inline properties on first line
    local task_text, comment = text:match("^(.-)%s*<!%-%-%s*(.-)%s*%-%->%s*$")
    if task_text and comment then
        card_data.text = task_text:gsub("^%s+", ""):gsub("%s+$", "")
        card_data.properties = TypeConverter:new(parse_properties(comment))

        -- Update first line in content_lines to remove properties
        card_data.content_lines[1] = "- " .. card_data.text
    else
        card_data.text = text:gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- Create Card object
    local card = Card:new(
        card_data.properties.id,
        card_data.text,
        card_data.properties
    )

    card.line_number = card_data.line_number
    card.column = card_data.column
    card.raw = card_data.raw

    -- Store content lines if multi-line
    if #card_data.content_lines > 1 then
        card.content_lines = card_data.content_lines
    end

    column:add_card(card)
end
```

### End of Column Handling

Ensure cards are flushed when column ends:
```lua
-- When detecting new column or end of file
if current_card then
    finalize_card(current_column, current_card)
    current_card = nil
end
```

## Writer Changes (`lua/kanban-md/writer_mixin.lua`)

### Modified write_task Function

Update to output multi-line content:

```lua
local function write_task(task, column_name)
    local config = config_module.get()
    local lines = {}

    -- Get properties to write
    local props_to_write = to_plain_table(task.properties or {})
    if config_module.get_value('persist_card_ids') and task.id then
        props_to_write.id = task.id
    end

    -- Build property comment
    local comment = properties_to_comment(props_to_write)

    -- Handle multi-line cards
    if task.content_lines then
        -- First line with properties
        local first_line = task.content_lines[1]
        if comment then
            if type(comment) == "table" then
                table.insert(lines, first_line .. " " .. comment[1])
                for i = 2, #comment do
                    table.insert(lines, comment[i])
                end
            else
                table.insert(lines, first_line .. " " .. comment)
            end
        else
            table.insert(lines, first_line)
        end

        -- Continuation lines (preserve original indentation)
        for i = 2, #task.content_lines do
            table.insert(lines, task.content_lines[i])
        end

        return lines
    end

    -- Single-line card (existing behaviour)
    local line = string.format("%s- %s", config.task_indent, task.text)
    if comment then
        if type(comment) == "table" then
            return { line .. " " .. comment[1], unpack(comment, 2) }
        else
            return line .. " " .. comment
        end
    end

    return line
end
```

### Column Writing

Ensure `write_column()` handles arrays returned from `write_task()`:

```lua
-- In write_column function
for _, card in ipairs(column.cards) do
    local card_output = write_task(card, column.name)

    if type(card_output) == "table" then
        -- Multi-line output
        for _, card_line in ipairs(card_output) do
            table.insert(lines, card_line)
        end
    else
        -- Single line output
        table.insert(lines, card_output)
    end
end
```

## Testing

### Unit Tests

Create `tests/unit/parser_multiline_spec.lua`:

**Test cases:**
- Single-line cards (ensure no regression)
- Two-line card (basic continuation)
- Multi-line card (3+ continuation lines)
- Multiple cards with continuations
- Column documentation before cards
- Column documentation after cards (blank line separator)
- Column documentation between cards
- Mixed: cards with/without continuations in same column
- Cards with inline properties AND continuation lines
- Edge case: blank lines within column (should break to documentation)
- Edge case: indented code blocks in column documentation
- Edge case: nested lists in column documentation
- Card followed immediately by column header (no continuation)

Create `tests/unit/writer_multiline_spec.lua`:

**Test cases:**
- Write single-line card (no regression)
- Write multi-line card
- Write card with properties and continuations
- Preserve indentation of continuation lines
- Multi-line property comments with multi-line cards

### Integration Tests

Add to `tests/integration/content_preservation_spec.lua`:

**Test cases:**
- Round-trip: multi-line cards preserve exact text
- Round-trip: column documentation preserved around multi-line cards
- Round-trip: mixed single/multi-line cards
- Move multi-line card between columns (full content preserved)
- Archive multi-line card (full content preserved)
- Complete multi-line card (full content + timestamps preserved)

### Example Test Board

Create `tests/fixtures/multiline_board.md`:

```markdown
# Multi-Line Test Board

Board documentation

###### Backlog

Column documentation for backlog

- Simple card
- Multi-line card
  with a continuation
  and another line
- Another simple card

Some more documentation here.

###### In Progress

- Working on this
  it has notes
  and more notes

###### Done

- Completed task
```

## Documentation Updates

### README.md

Update the "Markdown Syntax" section:

```markdown
### Card Syntax

Cards support multi-line content following CommonMark list item rules:

- **Single-line card**: `- Task name`
- **Multi-line card**:
  ```markdown
  - Task name
    continuation line (indented by 2+ spaces)
    another continuation line
  ```

**Rules:**
- Continuation lines must be indented by 2+ spaces
- No blank line can appear between the card and its continuation
- A blank line followed by non-list content starts column documentation

**Example:**
```markdown
###### TODO

Column notes here

- Card 1
- Card 2
  with details
  and more details
- Card 3

More column notes (blank line above)

- Card 4
```
```

### CLAUDE.md

Update the "Markdown Syntax" section with the parsing rules and state machine description.

## Edge Cases & Considerations

### Indentation Preservation

- Store continuation lines with their original indentation
- Writer outputs lines exactly as stored (no re-indentation)
- Ensures round-trip fidelity for varying indentation styles

### Property Comments

- Properties remain on first line only (inline HTML comment)
- Continuation lines cannot contain property comments
- If properties detected on continuation line, treat as parse error or ignore

### Nested Lists

Column documentation can contain nested lists:
```markdown
###### TODO

Documentation:
- This is documentation
  - Nested docs
  - More nested

- Card 1 (this is a card)
```

The parser distinguishes based on blank line rule (blank line before "Documentation:" means it's not a card).

### Empty Cards

```markdown
-
  continuation
```

An empty first line is technically valid CommonMark but may be confusing. Consider:
- Allow it (store empty string as `text`)
- Treat as parse error
- Collapse: treat first non-empty line as card text

**Decision:** Break with CommonMark compliance, treat it as a parse error and provide a warning to the user that list items may not start with blank lines.

### Very Long Cards

No artificial limit on continuation lines. A card can have dozens of lines if needed. Performance impact should be minimal as cards are stored as arrays.

### Display Considerations

- `:KanbanStats` display uses `card.text` (first line only) for compact view
- Virtual text uses `card.text` (first line only)
- Full content accessible via `card:get_full_text()` for detailed views

## Implementation Checklist

- [x] Create `tests/fixtures/multiline_board.md`
- [x] Create `tests/unit/parser_multiline_spec.lua`
- [x] Create `tests/unit/writer_multiline_spec.lua`
- [x] Add round-trip tests to `tests/integration/content_preservation_spec.lua`
- [x] Update Card class with `content_lines` field and `get_full_text()` method
- [x] Add parser helper functions (`is_continuation_line`, `has_list_marker`)
- [x] Add `finalize_card()` helper function
- [x] Update parser state tracking (add `current_card`, `blank_line_seen`)
- [x] Implement parser state machine in main loop
- [x] Ensure card flushing at column boundaries
- [x] Update `write_task()` to output multi-line content
- [x] Update `write_column()` to handle array output from `write_task()`
- [x] Update README.md markdown syntax section
- [x] Update CLAUDE.md parsing rules section
- [x] Test with real-world boards
- [x] Verify Neovim commands work with multi-line cards (`:KanbanMoveCard`, etc.)
- [x] Verify actions preserve multi-line content (`complete_card`, `archive_card`, etc.)

## Success Criteria

- [x] All existing tests pass (no regression)
- [x] All new multi-line tests pass
- [x] Round-trip preservation: parse → modify → write maintains exact content
- [x] Moving multi-line cards between columns preserves all content
- [x] Column documentation coexists with multi-line cards
- [x] Virtual text display remains functional (uses first line)
- [x] Manual testing with complex real-world boards succeeds
