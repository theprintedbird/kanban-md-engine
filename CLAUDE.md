# CLAUDE.md (Engine)

This file provides guidance to Claude Code (claude.ai/code) when working with the kanban-md engine code.

Use British English.

## Project Overview

This is a Kanban board engine for managing Markdown files, designed for compatibility with Obsidian. It allows users to create and manage Kanban boards using extended Markdown syntax with HTML comments for configuration and task properties. The engine is platform-agnostic and can be used in standalone Lua environments or integrated into applications like Neovim.

`SPEC.md` is the behaviour specification: the markdown syntax contract, the adapter contract, the
`notify()` contract and configuration resolution. When a change alters observable behaviour,
update `SPEC.md` in the same change - it is meant to be assertable against the test suite, so a
statement there that no longer holds is a bug.

## Core Modules

- **board.lua**: Board class with parser and writer mixins, core data structure
- **parser.lua**: Core parsing engine (the `ParserMixin` mixed into Board) that converts Markdown to Lua data structures. Handles board titles, columns, cards, properties, HTML comment configurations, and content blocks
- **writer_mixin.lua**: Converts Lua data structures back to Markdown format with full content preservation
- **content_block.lua**: Type definitions and utilities for content blocks (title, column, markdown)
- **column.lua**: Column class with card management
- **config.lua**: Default configuration setup
- **stats.lua**: Statistics calculation module for lead time, cycle time, and blocked time metrics
- **helpers/column.lua**: Column helper functions for semantic state detection (start, backlog, blocked, waiting, completion)

## Parser/Writer Architecture

### Data Structure

The parser creates a comprehensive board structure with:
- Board metadata (title, config, validation)
- Column arrays with cards and configurations
- Card objects with properties, completion status, and metadata
- **Content blocks** - ordered array tracking all content (both structured kanban elements and unstructured markdown)
- Automatic ID generation and timestamp handling
- Statistics calculation (WIP counts, lead time, cycle time, blocked time, complexity totals)
- Validation system for WIP limits and duplicate IDs
- Semantic state detection (backlog, start, blocked, waiting, completion states)

**Content Blocks Architecture:**
The board structure includes a `content_blocks` array that preserves the order and content of:
- `title` blocks: Board title (H1)
- `column` blocks: References to column objects (H6)
- `markdown` blocks: Arbitrary markdown content preserved verbatim

This architecture enables:
- Full round-trip fidelity (parse → modify → write preserves all content)
- Documentation sections coexist with kanban columns
- User prose and instructions remain intact after card operations

**Markdown Preservation:**
The parser/writer architecture preserves all markdown content in the board file, including:
- Prose paragraphs and descriptions
- Documentation sections (H2-H5 headers)
- Arbitrary content between/around kanban elements
- All non-kanban markdown is preserved verbatim during card operations

### Key Functions

- `board:parse(content)`: Main parsing function (instance method), builds content_blocks array
- `board:write()`: Main writing function, uses content_blocks for full preservation
- `board:write_from_blocks()`: Write from content blocks (preserves markdown)
- `board:write_legacy()`: Fallback writer for programmatically created boards
- `board:add_new_column(name, config)`: Add column with proper content block insertion
- `board:calculate_stats()`: Statistics calculation
- `board:validate()`: WIP limit and structure validation
- `board:find_task(task_id)`: Card lookup
- `board:get_column_by_name(column_name)`: Column lookup

### Implementation Notes

When working with parser/writer:
1. parser.lua and writer_mixin.lua are the most mature components - reference them for patterns and conventions
2. Columns use H6 headers (`######`), not H2 (`##`)
3. Content blocks architecture preserves all markdown - the board.content_blocks array tracks structured and unstructured content
4. Timestamps are held internally as epoch seconds for consistency; ISO dates in the markdown are
   converted on parse. How they are *written back* depends on `timestamp_format`: `epoch`
   (default), `iso` (`YYYY-MM-DDTHH:MM:SSZ`, UTC) or `date` (`YYYY-MM-DD`, local time). Only keys
   known to be timestamps are formatted - `archived` plus the normalised name of every column -
   so an ordinary number property stays a number. Note that `config.lua`'s own comment on
   `timestamp_format` lists only `epoch` and `iso`; `date` is implemented in `writer_mixin.lua`.
5. Special sections use double underscore naming and H6: `###### __ARCHIVE__`
6. HTML comments are used for configuration to maintain Obsidian compatibility
7. WIP limit validation occurs at both board and column levels
8. Card IDs are auto-generated using either a ULID (default) or hash functions if not specified *and* the config is set for it (default true)
9. When modifying parser/writer, ensure content blocks are built/used correctly for full round-trip fidelity

## Property System

Cards support rich properties via HTML comments:
- Timestamps: Column-based timestamps (e.g., backlog, ready, in_progress, done) and archived (epoch seconds internally; serialised per `timestamp_format`)
- Work metrics: complexity, actual_time, blocked_time
- Metadata: assignee, tags, blocker, parent, id, position
- Automatic type conversion (numbers, booleans, arrays, strings)

**Completion Tracking:**
Completion is **column-based**, not checkbox-based:
1. A card is "complete" when it's in a completion column (detected via `lua/kanban-md/helpers/column.lua:is_completion_column()`)
2. Completion detection checks (in priority order):
   - **Explicit column property**: `is_completion_state = true` (set via `<!-- column:config is_completion_state: true -->`)
   - **Position-based fallback**: Last regular column in the board (if multiple regular columns exist)
   - **No hardcoded patterns**: The function contains NO hardcoded column name patterns - all detection is explicit or position-based
3. **Timestamps are automatically set via triggers**: When `auto_timestamp = true` (default in `config.lua`), the `board:auto_register_triggers()` method registers timestamp triggers that automatically set `card.properties[column_name] = os.time()` when a card enters any column
4. **NEVER manually set completion timestamps in code**: Use `board:auto_register_triggers()` and let the trigger system handle it automatically. Tests that manually set `card.properties.done = os.time()` are incorrect and should be refactored.

### Semantic Column States

The plugin uses semantic state flags on columns to enable sophisticated metrics calculation:

**State Flags** (set via `<!-- column:config property: true -->`):
- `is_backlog_state` - Marks the backlog column (start of lead time)
- `is_start_state` - Marks when active work begins (start of cycle time)
- `is_blocked_state` - Marks blocked/on-hold states (excluded from active time)
- `is_waiting_state` - Marks waiting states (excluded from active time)
- `is_completion_state` - Marks completion columns (end of lead/cycle time)

**Detection Strategy** (3-tier fallback):
1. **Explicit property**: `<!-- column:config is_start_state: true -->`
2. **Configuration default**: `config.default_start_column = "In Progress"`
3. **Position-based fallback**: First/last regular column (for start/completion states)

**Note**: Blocked and waiting states require explicit declaration (no fallback).

## Adapters and User Feedback

All I/O and user interaction goes through an adapter (`lua/kanban-md/adapters/interface.lua`); the
engine never calls `vim.*` or `io.*` directly. `adapters/cli.lua` is the reference implementation.
See `SPEC.md` sections 8 and 9 for the full contract. The two rules that are easiest to break:

- **Data goes to stdout, everything else goes to stderr.** `notify()` at every level, and both
  prompts, write to stderr. Board content reaches stdout only via
  `write_buffer(lines, { stdout = true })`, so a redirect produces a clean board file even when the
  run emits warnings.
- **`notify()` prefixes are part of the observable output.** The CLI adapter emits an emoji per
  level (info U+2139 U+FE0F, warn U+26A0 U+FE0F, error U+274C). Assert the emitted string, not just
  that the call did not error - these bytes have been corrupted before, and a "does not error" test
  cannot see it.

`notify(message, "error")` is a report, not a raise: engine code that notifies at error level must
also return a value reflecting the failure, because the host learns nothing from the control flow.

## Trigger System

The plugin uses a trigger-based architecture for extensibility and optional features. Triggers are callback functions that execute at specific points in the card lifecycle.

### Trigger Types

All trigger points come from `triggerable.lua`, which Board, Column and Card
mix in. The registration methods are the names to use in code:

- **`register_on_checking`**: Called when validating a card move (can block the move)
- **`register_on_entry`**: Called when a card is about to enter a column (validation and transformation)
- **`register_on_exit`**: Called when a card is about to leave a column
- **`register_on_stay`**: Called when a card stays put during an attempted move
- **`register_on_create`**: Called when an object is created (used for ID generation)

There is no `on_entering` or `on_exiting` method; the points are `on_entry` and
`on_exit`.

### Auto-Register Triggers

The `board:auto_register_triggers()` method automatically registers core triggers based on configuration:
- **Timestamp triggers**: When `auto_timestamp = true`, automatically sets `card.properties[column_name] = os.time()` when a card enters any column
- Registered on all columns via the `on_entry` trigger point

### Optional Feature Triggers

Advanced features are implemented entirely via triggers with no special core mechanisms:

**Subtasks and Dependencies** (`lua/kanban-md/extras/subtasks_triggers.lua`):
- Validates task relationships during column transitions
- Prevents parent tasks from moving to completion until all subtasks complete
- Prevents tasks from moving to completion until all dependencies complete
- Implemented via `register_on_checking` triggers registered on all columns
- Configurable validation modes: "off", "strict", "warn"

**Other Trigger Modules** (see `lua/kanban-md/extras/`):
- `workflow_triggers.lua` - Complex workflow validations (SLA, business hours, approvals)
- `capacity_triggers.lua` - Advanced capacity management (points, reviewers, skills)
- `id_triggers.lua` - ULID-based ID generation

### Trigger Metadata and Bypass

Triggers support metadata for selective bypass:
```lua
column:register_on_checking("dependencies", dep_fn, {
  bypassable = true,
  category = "dependency"
})
```

The `board:move_card_with_bypass()` method allows bypassing specific trigger categories while preserving other validations. This enables override commands like `:KanbanForceCompleteCard` to skip dependency/subtask checks while maintaining WIP limits and other validations.

## Working with TODO.kanban.md

`TODO.kanban.md` is a kanban-md board. **Always change it through the kanban-md
skill**, not by editing the Markdown by hand:

```bash
K=~/.claude/skills/kanban-md/scripts/kanban.lua
lua $K show TODO.kanban.md
lua $K move TODO.kanban.md --card "<substring>" --to "In Progress"
```

The skill drives the engine, so triggers set the column timestamps and WIP
limits are enforced. Hand-editing skips all of that and silently produces a
board the engine would not have written. Every change command takes
`--dry-run`; preview the diff before the first change in a session.

## Testing

### Test Framework

The engine uses **Standalone Lua Tests** for all core functionality:

**Standalone Lua Tests:**
- Framework: Busted
- Runner: `busted` or `make test-standalone`
- Coverage: All core functionality (parser, writer, board, actions, stats, triggers)
- Files: `tests/unit/*`, `tests/integration/*`, `tests/e2e/*`
- Speed: Fast (no external dependencies)
- Polyfills: Uses `tests/polyfills/vim.lua` to provide pure Lua implementations of utility functions

### Running Tests

**All tests:**
```bash
make test
```

**Standalone tests only (fast):**
```bash
./tests/run_tests_standalone.sh
# or
make test-standalone
```

**Specific test categories:**
```bash
make test-unit          # Unit tests only
make test-integration   # Integration tests only
make test-e2e          # E2E tests only
```

**Specific test file:**
```bash
make test-file FILE=tests/unit/parser_content_blocks_spec.lua
# or
busted tests/unit/parser_content_blocks_spec.lua
```

**Using busted directly:**
```bash
busted                    # Run all tests (uses .busted config)
busted tests/unit         # Run unit tests
busted tests/integration  # Run integration tests
busted tests/e2e         # Run E2E tests
busted --list            # List all available tests
```

**Requirements:**
- Lua 5.1+ or LuaJIT on `PATH` (set `LUA` to pick a specific interpreter)
- Busted (`luarocks install busted`)

**Configuration:**
The `.busted` file in the project root configures:
- Lua module paths (including `tests/?.lua` for polyfills)
- Test file patterns (`*_spec.lua`)
- Test directories and verbosity

**Important Notes:**
- **DO NOT use git commands (stash, reset, etc.) for testing or temporary state management**
  - Use temporary files instead to save/restore state if needed
  - Example: `cp config.lua config.lua.backup` instead of `git stash`

## Markdown Syntax

The engine uses extended Markdown with HTML comments:
- Board titles: `# Board Title` (H1)
- Columns: `###### Column Name` (H6 - six hashes)
- Documentation sections: `## Section Name` through `##### Section Name` (H2-H5)
- Cards: `- Task name` (unordered list items)
- Properties: `<!-- property: value, property2: value2 -->`
- Board config: `<!-- kanban:config wip_limit: 7 -->`
- Column config: `<!-- column:config wip_limit: 3 -->`
- Special sections: `###### __ARCHIVE__` for archived cards

**Note on Card Syntax:**
Cards are represented as simple unordered list items (`- Task name`). The engine does NOT use checkbox syntax (`- [ ]` or `- [x]`). Completion is tracked by which column a card is in, not by checkbox state.

**Why H6 for columns?**
- Clear semantic separation: H1 for board title, H2-H5 for user documentation, H6 for kanban columns
- Rare collision: H6 is almost never used in typical markdown
- Graceful degradation: Renders fine in any markdown viewer
- Obvious errors: If someone accidentally uses H6 elsewhere, it's immediately visible
