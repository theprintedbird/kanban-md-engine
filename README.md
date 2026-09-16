# kanban-md-engine

The platform-agnostic Lua engine behind kanban-md: parses Kanban boards out of Markdown files, lets you mutate them (move cards, add columns, archive, validate), and writes them back out with full round-trip fidelity. It has no dependency on Neovim or any other host — pure Lua in, pure Lua out.

## The kanban-md project

kanban-md used to be a single repository. It has since been split into three:

- **[kanban-md](https://github.com/theprintedbird/kanban-md)** – defines the Markdown syntax/spec for kanban boards (columns, cards, properties, archive, configuration comments).
- **kanban-md-engine** (this repo) – the platform-agnostic Lua engine: parsing, writing, the board/column/card model, triggers, statistics, validation, and dependency/subtask handling.
- **[kanban-md.nvim](https://github.com/theprintedbird/kanban-md.nvim)** – the Neovim integration: user commands (`:KanbanNewCard`, `:KanbanMoveCard`, etc.), keymaps, buffer/cursor handling, and virtual text (WIP warnings, cycle time). It pulls this repo in as a git submodule and talks to it via the adapter interface below.

If you're looking for Neovim commands, keymaps, or virtual text, they live in `kanban-md.nvim`, not here. This README only covers the engine.

## What this repo provides

- **Board / Column / Card model** (`board.lua`, `column.lua`, `card.lua`) — the core data structures.
- **Parser** (`parser.lua`) — converts Markdown into the board data structure, building an ordered `content_blocks` array that preserves titles, columns, and arbitrary documentation prose.
- **Writer** (`writer_mixin.lua`) — converts the data structure back into Markdown, using `content_blocks` for full round-trip fidelity (parse → modify → write preserves everything, including non-kanban markdown).
- **Trigger system** (`triggerable.lua`, `triggers.lua`, `extras/`) — the extensibility mechanism used for timestamps, WIP limits, dependencies, subtasks, workflow rules, and capacity management.
- **Statistics** (`stats.lua`) — WIP counts, lead time, cycle time, blocked time, complexity totals.
- **Validation** — WIP limit checking (board and column level) and duplicate ID detection.
- **Adapter interface** (`adapters/interface.lua`) — the strategy-pattern contract that lets the engine talk to a host environment without depending on it, plus a reference `adapters/cli.lua` implementation for standalone/CI usage. The Neovim adapter lives in `kanban-md.nvim`.

## Installation

This repo is a library, not a standalone application. It's typically consumed as a git submodule by a host project (e.g. `kanban-md.nvim` includes it at `lib/kanban-md`):

```sh
git submodule add https://github.com/theprintedbird/kanban-md-engine lib/kanban-md
```

Add `lua/` to your Lua module path (or `lib/kanban-md/lua/` if used as a submodule) so `require('kanban-md.*')` resolves.

For pure command-line/CI usage with no host at all, see the CLI adapter below.

## Adapter pattern

The engine never touches `vim.*`, `io.*`, or any host API directly — all I/O and UI interaction goes through an adapter that implements the contract in `lua/kanban-md/adapters/interface.lua`:

```
┌─────────────────────────────────────────┐
│   Host application                       │  Neovim, a CLI tool, Obsidian, a web app…
├─────────────────────────────────────────┤
│   Adapter Interface (Strategy Pattern)   │  lua/kanban-md/adapters/
│   - notify() / read_buffer() / write_buffer()
│   - prompt_input() / prompt_select()
│   - cursor & (optional) virtual text
├─────────────────────────────────────────┤
│   kanban-md-engine (this repo)           │  Board / Column / Card, parser, writer,
│                                           │  triggers, stats, config, validation
└─────────────────────────────────────────┘
```

`lua/kanban-md/adapters/cli.lua` ships as a reference adapter using plain `io.*`/`print`, useful for CI automation, batch processing, or exercising the engine outside any editor. See `lua/kanban-md/adapters/README.md` for the full method reference and a guide to writing your own adapter (Obsidian, web, etc.).

## Quick start (standalone Lua)

```lua
local kanban = require('kanban-md.cli')
kanban.setup({ auto_id = true, auto_timestamp = true })

local Board = require('kanban-md.board')
local board = Board:new()

local file = io.open("board.md", "r")
board:parse(file:read("*all"))
file:close()

board:calculate_stats()
print(string.format("%s: %d cards, %d WIP", board.title, board.stats.total_card_count, board.stats.total_wip))

-- Mutate, then write back out
local backlog = board:get_column_by_name("Backlog")
local ready = board:get_column_by_name("Ready")
board:move_card(backlog.cards[1], backlog, ready)

local lines = board:write()
```

A fuller walkthrough (loading, inspecting, moving/adding cards, validating, archiving, writing) lives in `examples/cli_example.lua`, runnable with `lua examples/cli_example.lua` or via Neovim's headless Lua runtime — see `examples/README.md`.

## Markdown Syntax Reference

kanban-md uses H6 headers (`######`) for column definitions, allowing arbitrary Markdown documentation to coexist in the same file as the board.

### Basic Structure

```md
<!-- kanban-board -->
# Board Title
<!-- kanban:config
wip_limit: 7
cycle_time_unit: days
-->

###### Backlog
- Task name
- Complex task <!-- complexity: 3 -->

###### Ready
<!-- column:config wip_limit: 3 -->

###### In Progress
<!-- column:config wip_limit: 4 -->
- Current task <!-- in_progress: 1735948800 -->

###### Done
- Completed task <!-- in_progress: 1735948800, done: 1736035200 -->

###### __ARCHIVE__
<!-- archived tasks older than 30 days -->
```

A board with non-kanban Markdown sections, all of which survive parse → write round-trips:

```md
<!-- kanban-board -->
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
```

Cards are plain unordered list items (`- Task name`) — the engine does **not** use checkbox syntax (`- [ ]`/`- [x]`). Completion is tracked by which column a card is in, not by checkbox state.

### Rationale

- HTML comments are invisible in Obsidian's preview and won't break rendering
- Timestamps in epoch format are unambiguous and easy to calculate with
- Special sections use double underscores: `__ARCHIVE__`
- The `<!-- kanban-board -->` marker (enabled by default) prevents accidental parsing of documentation files

### Board Detection Strategies

Detection of which Markdown files should be parsed as boards is controlled by the `detection_strategy` config option (enforced by the host, using the engine's config):

- **`"marker"`** (default) — requires an explicit `<!-- kanban-board -->` comment in the first 10 lines. Invisible in rendered Markdown.
- **`"extension"`** — only parses files with a `.kanban.md` extension.
- **`"both"`** — accepts either the marker or the `.kanban.md` extension.
- **`"auto"`** — legacy: detects any file containing H6 headers (`######`). May parse unintended files.

### Why H6?

- **H1** (`#`) is reserved for the board title
- **H2–H5** (`##` to `#####`) can be used for documentation sections
- **H6** (`######`) marks kanban columns and is rarely used elsewhere
- If you accidentally use H6 for non-column headers, it will be obvious (tasks will appear underneath)

## Data Structures & API

### Content Blocks Architecture

The parsed board includes a `content_blocks` array that preserves the order and content of:

- `title` blocks: the board title (H1)
- `column` blocks: references to column objects (H6)
- `markdown` blocks: arbitrary Markdown content preserved verbatim

This is what gives full round-trip fidelity — user prose and documentation sections survive card/column operations untouched.

### Key Functions

- `board:parse(content)` — parse Markdown into the board structure, building `content_blocks`
- `board:write()` — serialise the board back to Markdown, using `content_blocks` for full preservation
- `board:write_from_blocks()` / `board:write_legacy()` — lower-level writer entry points (the latter for programmatically-constructed boards without content blocks)
- `board:add_new_column(name, config)` — add a column with correct content block insertion
- `board:move_card(card, from_column, to_column)` / `board:move_card_with_bypass(card, from_column, to_column, bypass_categories)` — move a card, respecting (or selectively bypassing) trigger validations
- `board:calculate_stats()` — compute WIP, lead/cycle/blocked time, complexity totals
- `board:validate()` — WIP limit and structural validation (errors/warnings)
- `board:find_task(task_id)` — card lookup by ID
- `board:get_column_by_name(column_name)` — column lookup

See `CLAUDE.md` for the full architectural notes (parser/writer conventions, ID generation, completion detection, semantic column states).

### Completion Tracking

Completion is **column-based**, not checkbox-based. A card is "complete" when it's in a completion column, detected via `helpers/column.lua:is_completion_column()`:

1. Explicit property: `<!-- column:config is_completion_state: true -->`
2. Position-based fallback: the last regular column on the board
3. No hardcoded name patterns — detection is always explicit or positional

## Properties System

Card properties are **completely arbitrary** — any property name works. Properties live in HTML comments and are parsed as `key: value` pairs; `type_converter.lua` optionally converts specific names to numbers, booleans, or arrays.

```markdown
<!-- project: backend-api, story_points: 5, reviewer: bob, custom_field: whatever -->
```

### Commonly Used Properties

| Property | Type | Used By | Description |
|----------|------|---------|-------------|
| `id` | string | All triggers | Unique card identifier (auto-generated by default, via ULID) |
| `complexity` | number | Stats, triggers | Story points or estimation |
| `parent` | string | Subtasks | Parent task ID (when using the subtask feature) |
| `position` | number | N/A | Position in column (for custom ordering) |
| `tags` | array | N/A | Categories/labels (comma-separated) |

**Timestamp properties (epoch format):** set automatically when `auto_timestamp = true` (default), via the trigger system — never set them manually in code. Property names match the column name, normalised to `snake_case` (e.g. moving to "In Progress" sets `in_progress: 1735948800`). The archive column uses `archived` instead of `__archive__`.

**Optional properties (require enabling the relevant extra):**
- `depends_on` (array) — task IDs this card depends on, requires `dependency_validation` enabled
- `subtasks` (array) — task IDs of subtasks, requires `subtask_validation` enabled
- `assignee` (string) — requires `extras/capacity_triggers` enabled
- `sla`, `sla_config`, `started`, `priority`, `estimated_value`, `approved_by` — used by `extras/workflow_triggers`

### Type Conversion Rules

- **Numbers:** `complexity`, `wip_limit`, `max_points`, timestamps, `actual_time`, `blocked_time`, `position`
- **Booleans:** `blocked`, `urgent`, `reviewed`, `auto`, `revalidated`, `changes_requested`
- **Arrays:** `tags`, `authorized_approvers`, `depends_on` (when enabled), `subtasks` (when enabled)

### Registering Custom Properties

```lua
local TypeConverter = require('kanban-md.type_converter')
TypeConverter.register_numeric_property('story_points')
TypeConverter.register_array_property('reviewers')
TypeConverter.register_boolean_property('needs_documentation')
```

## Trigger System

Triggers are the extensibility mechanism for the whole engine — timestamps, WIP limits, dependency/subtask validation, and workflow rules are all implemented as triggers, not special-cased core logic.

### Trigger Events

- **on_create** — fires when a board/column/card is created
- **on_entry** — fires when a card enters a column
- **on_exit** — fires when a card leaves a column
- **on_stay** — fires while a card remains in a column (uncommon)
- **on_checking** — fires to validate a transition before it happens (can block the move)

### Writing a Trigger

```lua
function(self, context)
  -- self: the triggerable object (column, board, or card)
  -- context: table with board, column, card, timestamp, etc.
  -- Returns: true on success, or error() on failure
end
```

```lua
-- Register on a column
column:register_on_entry("timestamp", trigger_fn)

-- Register on a board
board:register_on_checking("wip_limit", trigger_fn)
```

### Bypassing Triggers Selectively

Triggers can be tagged with metadata for selective bypass:

```lua
column:register_on_checking("dependencies", dep_fn, {
  bypassable = true,
  category = "dependency"
})
```

`board:move_card_with_bypass()` then lets a host skip specific trigger categories (e.g. a "force complete" command bypassing dependency/subtask checks) while preserving everything else, like WIP limits.

### Optional Trigger Modules (`lua/kanban-md/extras/`)

- `subtasks_triggers.lua` — parent/subtask and dependency validation (`"off"` / `"strict"` / `"warn"` modes)
- `workflow_triggers.lua` — SLA, business hours, approval workflows
- `capacity_triggers.lua` — points, reviewers, skills-based capacity management
- `id_triggers.lua` — ULID-based ID generation

## Testing

Tests run with [Busted](https://olivinelabs.com/busted/) against pure Lua — no Neovim dependency. `tests/polyfills/vim.lua` provides pure-Lua stand-ins for the handful of Neovim utility functions the engine still references.

```bash
make test                # all tests
make test-standalone     # same as above (explicit)
make test-unit           # tests/unit only
make test-integration    # tests/integration only
make test-e2e            # tests/e2e only
make test-file FILE=tests/unit/parser_content_blocks_spec.lua
make test-shuffle        # random order; SEED=<n> reproduces one
make test-tap            # TAP output; TAP_FILE=<path> also saves it
make coverage            # luacov summary (no threshold)
make lint                # luacheck (make lint-container if it isn't installed)

# or directly:
busted
busted tests/unit
busted --list
```

**Requirements:** Lua and Busted (`luarocks install busted`).

Coverage includes parser/writer round-trip consistency, property parsing, WIP/duplicate-ID validation, statistics (lead time, cycle time, blocked time, complexity), and the trigger system (including the optional dependency/subtask/workflow/capacity extras).

### Containers and local CI

The suite also runs inside a small Alpine image, which is handy for checking a
Lua version you don't have installed locally. Podman is used if it is present,
otherwise Docker:

```bash
make test-container                  # build the image and run the suite
make test-container LUA_VERSION=5.1  # 5.1, 5.3, 5.4 or jit
make container-build                 # build only
```

The GitHub Actions workflows can be run locally with
[act](https://github.com/nektos/act):

```bash
make ci-local-list                   # list the jobs act can see
make ci-local                        # run them
make ci-local ACT_ARGS="-j test"     # run one job
```

Shared options live in `.actrc`. Under Podman the Makefile points act at the
machine's API socket automatically; an existing `DOCKER_HOST` is left alone.
The podman machine has to be running (`podman machine start`).

## Related Projects

- **[kanban-md](https://github.com/theprintedbird/kanban-md)** — the Markdown syntax specification
- **[kanban-md.nvim](https://github.com/theprintedbird/kanban-md.nvim)** — the Neovim plugin built on this engine
