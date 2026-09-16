# kanban-md-engine — behaviour specification

Status: living document. Version: tracks `lua/kanban-md/version.lua` (currently `0.1.0`).

This document specifies the observable behaviour of the kanban-md engine: what it accepts, what
it produces, and the contracts a host application may rely on. It is written to be testable —
every statement here should correspond to something a spec in `tests/` can assert. Where the
implementation and this document disagree, that is a bug in one of them; neither is allowed to
drift silently.

`README.md` explains what the project is and how to install it. `CLAUDE.md` gives working
guidance for contributors. This document is the contract.

## 1. Scope

In scope:

- The Lua module API exposed under `require('kanban-md.*')`.
- The Markdown dialect the parser reads and the writer emits (§7).
- The adapter contract a host must satisfy (§8) and the user-feedback contract (§9).
- Configuration resolution and precedence (§10).
- The trigger lifecycle, validation and statistics contracts (§5, §6).

Out of scope:

- Neovim commands, keymaps and buffer/cursor handling. Those live in `kanban-md.nvim`.
- Any executable. **The engine ships no binary and parses no `argv`.** "The CLI" in this
  repository means the CLI *adapter* (`kanban-md.adapters.cli`) and the CLI *entry module*
  (`kanban-md.cli`) — a library surface, not a command-line program.

## 2. Terminology

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT** and **MAY** are used in the
sense of RFC 2119.

- **Board** — one Markdown file's worth of kanban structure: a title, board configuration,
  ordered columns, an optional archive, and arbitrary surrounding prose.
- **Column** — a named bucket of cards, written as an H6 heading.
- **Card** — a single work item, written as a Markdown list item.
- **Property** — a `key: value` pair carried in an HTML comment attached to a card, column or
  board.
- **Content block** — an entry in the ordered `board.content_blocks` array, which is what makes
  round-tripping lossless (§4.4).
- **Host** — the application embedding the engine (Neovim, a script, CI).
- **Adapter** — the object through which the engine performs all I/O and user interaction.

## 3. Entry points

### 3.1 Pure library use (no setup)

`require('kanban-md.board')` and its siblings are usable with no initialisation at all:

```lua
local Board = require('kanban-md.board')
local board = Board:new()
board:parse(markdown_string_or_line_table)
local lines = board:write()
```

The engine **MUST NOT** require `setup()` to have been called in order to parse or write a
board. Features that need I/O or user interaction (anything reaching `adapter_registry`) **MAY**
error if no adapter has been registered; parsing and writing **MUST NOT**.

ID-generation triggers are registered by `setup()`, so without setup, objects fall back to the
built-in identifiers described in §4.3.

### 3.2 Configured use

```lua
local kanban = require('kanban-md.cli')
kanban.setup({ wip_limit = 5 })
```

`kanban-md.cli` re-exports `Board`, `Column`, `Card`, `Triggerable`, `triggers` and `config`, and
sets `kanban.adapter` to the CLI adapter instance.

- `cli.setup(user_config)` **MUST** raise an error when `vim ~= nil` and `_G._TEST` is not set,
  directing the caller to `require('kanban-md').setup()`. This guard exists so a Neovim user
  cannot silently install the CLI adapter over the Neovim one.
- `cli.setup()` delegates to `kanban-md.core.setup`, which **MUST**, in order: register the
  adapter in `adapter_registry`; apply `user_config` via `config.setup()`; and, if `auto_id`
  resolves true, register ULID `on_create` triggers on the `Board`, `Column` and `Card` classes.
- `core_setup.setup(user_config, adapter)` **MUST** error when called with no adapter.

A host that is not the CLI supplies its own adapter (§8) and calls `core.setup` itself.

## 4. Data model

### 4.1 Board

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `board_…`; see §4.3 |
| `title` | string | Text of the H1, or `"Untitled Board"` when absent |
| `config` | TypeConverter | Properties authored in `<!-- kanban:config … -->` |
| `columns` | array of Column | Regular columns, in document order |
| `archive` | Column or nil | The `__ARCHIVE__` column; **NOT** a member of `columns` |
| `content_blocks` | array | Ordered document structure (§4.4) |
| `stats` | table | Populated by `calculate_stats()` (§6) |
| `validation` | table | Populated by `validate()` (§6) |
| `raw_lines` | array of string | The input lines, as parsed |

`Board:new()` fires `on_create` triggers (class-level first, then instance-level) and **MUST**
propagate an error raised inside such a trigger, prefixed with the trigger's name.

### 4.2 Column and Card

A Column carries `id`, `name`, `cards`, `line_number`, `type`, and two config layers:

- `column.markdown_config` — exactly the properties the user authored in the column's config
  comment. This is the layer the writer serialises back by default.
- `column.config` — the resolved merge of type defaults < named definition < authored markdown.
  This is the layer triggers, helpers, stats and validation consult.

Keeping the two apart is what stops implicit, type-resolved properties being injected into the
user's file (§7.5).

A Card carries `id`, `text`, `properties`, `line_number`, `column`, `raw`, and `content_lines`
when it spans more than one line.

`Board.archive` being separate from `Board.columns` is load-bearing: statistics, completion
detection and position-based column fallbacks all iterate `columns` only, so archived cards
**MUST NOT** affect WIP counts or semantic-state inference.

### 4.3 Identifiers

With `auto_id` enabled (the default) and `setup()` called, boards, columns and cards receive
ULID-based identifiers on creation: `board_01H…`, `column_01H…`, `card_01H…`.

Without those triggers the engine still guarantees a non-nil `id`, falling back to a
timestamp-derived value. Identifier *presence* is a contract; identifier *format* is only a
contract when `auto_id` is on.

Card identifiers are ephemeral by default: they are generated on parse and **MUST NOT** be
written back to the Markdown unless `persist_card_ids` resolves true (§7.4).

### 4.4 Content blocks

`board.content_blocks` is an ordered array whose entries are one of:

- `title` — the H1. Rendered from the current `board.title` on write.
- `column` — a reference (`block.ref`) to a Column object. Rendered from current column state.
- `markdown` — a `lines` array of arbitrary Markdown, preserved verbatim.

Everything the parser does not recognise as kanban structure becomes a `markdown` block. This is
the mechanism behind the round-trip guarantee in §5.2.

## 5. Parse and write

### 5.1 Parsing

`board:parse(content)` accepts either a single string (split on `\n`) or an array of lines, and
returns the board. It resets `columns`, `archive`, `stats` and `content_blocks` on every call, so
parsing is idempotent rather than cumulative.

After the line scan, `parse()` **MUST**, in order:

1. Resolve column types for any column that had no explicit config comment, via
   `column_type_resolver` (patterns and named definitions).
2. Do the same for the archive column.
3. Call `calculate_stats()`, then `validate()`.
4. Call `auto_register_triggers()`.

A parse **MUST NOT** raise on unrecognised content. Anything the grammar in §7 does not cover is
preserved as Markdown rather than rejected.

### 5.2 Writing and the round-trip guarantee

`board:write()` returns an array of lines. It dispatches to `write_from_blocks()` when
`content_blocks` is non-empty, and to `write_legacy()` for boards built programmatically.

The central contract:

> **Round-trip fidelity.** For any input `s`, `parse(s)` followed by `write()` **MUST** preserve
> all non-kanban Markdown verbatim — prose, H2–H5 documentation sections, fenced code blocks,
> lists outside columns, and blank-line structure between them. Structured elements (title,
> column headers, cards, config comments) are re-rendered from current state and so are subject
> to the normalisation rules in §7.

Corollary, and the reason the round trip matters: a card operation **MUST NOT** destroy
surrounding user content. Moving a card rewrites the affected list items and nothing else.

`parse(write(parse(s)))` **MUST** produce an equivalent board to `parse(s)`.

## 6. Triggers, validation and statistics

### 6.1 Trigger points

`triggerable.lua` is mixed into Board, Column and Card. The registration methods are the
authoritative names:

| Method | Fires when |
|---|---|
| `register_on_create` | The object is constructed |
| `register_on_checking` | A move is being validated; **MAY** block the move |
| `register_on_entry` | A card is about to enter a column |
| `register_on_exit` | A card is about to leave a column |
| `register_on_stay` | An attempted move left the card where it was |

There is no `on_entering` or `on_exiting`.

Triggers **MAY** carry metadata: `{ bypassable = true, category = "dependency" }`.
`board:move_card_with_bypass(card, from, to, categories)` **MUST** skip bypassable triggers whose
category is listed, and **MUST** still run every other trigger — bypassing a dependency check
does not bypass WIP limits.

### 6.2 Auto-registration

`board:auto_register_triggers()` is called at the end of every parse and registers, from resolved
configuration only:

- Timestamp triggers on every column when `auto_timestamp` resolves true. Entering a column sets
  `card.properties[normalised_column_name] = os.time()`. Column names normalise to snake_case
  (`"Code Review"` → `code_review`).
- Complexity defaulting when `use_complexity` resolves true.
- Dependency and subtask `on_checking` triggers when those modes resolve to `"strict"` or
  `"warn"` (§10.4), registered with bypass metadata.
- Workflow and capacity triggers where the board or column configuration asks for them.
- Any triggers declared by a column's resolved type.

`auto_register_triggers()` **MUST NOT** `require` a module outside this repository for any
configuration value. A host-specific feature is registered by the host through the public trigger
API, not by the engine reaching for the host's code.

Completion timestamps are set by triggers and **MUST NOT** be assigned by hand — in engine code
or in tests.

### 6.3 Semantic column states

Five flags, settable via `<!-- column:config … -->`:

`is_backlog_state`, `is_start_state`, `is_blocked_state`, `is_waiting_state`,
`is_completion_state`.

Detection, in priority order:

1. The explicit property on the column.
2. A configuration default (`default_start_column`, `default_backlog_column`) matched
   case-insensitively as a substring of the column name.
3. Position: first regular column for start/backlog, last regular column for completion, and only
   when more than one regular column exists.

`is_blocked_state` and `is_waiting_state` have **no** fallback: they **MUST** be declared
explicitly. No detection path may use hardcoded column-name patterns such as "Done" or
"In Progress"; pattern matching is available only through user-supplied `column_config.types`.

Completion is column-based. The engine has no checkbox syntax, and a card's completion **MUST**
be derived from the column it is in.

### 6.4 Validation

`board:validate()` populates `board.validation = { valid, warnings, errors }`. It **MUST** flag:

- Board-level WIP limit exceeded (sum of column WIP against `config.wip_limit`).
- Each column-level WIP limit exceeded.
- Duplicate card identifiers, reported with the location they were found in.

Exceeding a WIP limit is a **warning** that sets `valid = false`; it does not raise.

`ValidationResult` (`validation_result.lua`) is the return type for move validation, with three
states — `approved`, `warning`, `denied` — constructed via `ValidationResult.success()`,
`.warning()` and `.error()`, and interrogated via `is_success()`, `is_warning()`, `is_denied()`
and `get_error()`.

`board:validate_move(card, from_column, to_column)` returns a `ValidationResult`. It accepts a
Column instance or a column name as the target, returns an error result for an unknown target
column, and returns success unconditionally when `from_column` is nil (a card being placed for
the first time).

### 6.5 Statistics

`board:calculate_stats()` populates `board.stats` with counts (`total_tasks`, `completed_tasks`,
`in_progress_tasks`, `blocked_tasks`), per-column WIP and complexity maps, complexity totals
segmented by semantic state, and `lead_times` / `cycle_times` arrays.

- **Lead time** — backlog timestamp → completion timestamp.
- **Cycle time** — start-state timestamp → completion timestamp.
- **Blocked time** — total time spent in columns flagged blocked or waiting, subtracted from
  active time.

All three are derived from the column timestamps on card properties, so they are only as good as
the trigger-maintained timestamps that produced them. Durations are formatted according to
`cycle_time_unit` and `stats_time_format` (§10).

## 7. The Markdown syntax contract

*To be specified.*

## 8. The adapter contract

The engine never calls `vim.*`, `io.*` or any other host API directly. Every piece of I/O and
user interaction goes through an adapter registered in `kanban-md.adapter_registry`. The contract
is `lua/kanban-md/adapters/interface.lua`; `lua/kanban-md/adapters/cli.lua` is the reference
implementation.

### 8.1 Constructing and validating an adapter

```lua
local Adapter = require('kanban-md.adapters.interface')
local MyAdapter = Adapter.new({
  name = "MyAdapter",
  notify = function(self, message, level) … end,
  -- … the rest of the required methods
})
```

- `Adapter.new(implementation)` sets `Adapter` as the implementation's metatable and then
  validates it. An incomplete implementation **MUST** raise; `Adapter.new` never returns a
  half-formed adapter.
- `Adapter.validate(adapter)` returns `(true, nil)` for a conforming adapter and
  `(false, "Adapter missing required method: <name>")` for the first missing one. Validation
  checks only that each required key is a function; it does not check arity or behaviour.
- The required set is exactly these seven:

  `notify`, `read_buffer`, `write_buffer`, `get_cursor`, `set_cursor`, `prompt_input`,
  `prompt_select`.

- Any required method left to the base class raises
  `"Abstract method '<name>' must be implemented by adapter…"`, identifying the adapter by its
  `name` field, its `_type` field, or its metatable's `__name`, in that order. An adapter
  **SHOULD** therefore set `name`.
- `adapter_registry.get_adapter()` **MUST** raise when no adapter has been registered;
  `has_adapter()` is the non-raising check.

### 8.2 Index conventions

The interface follows Neovim's conventions, and every adapter **MUST** honour them regardless of
what its host prefers natively:

| Value | Convention |
|---|---|
| Buffer line ranges (`opts.start`, `opts._end`) | 0-indexed, end-exclusive-by-count, `-1` meaning "to the end" |
| Cursor line | 1-indexed |
| Cursor column | 0-indexed |
| Virtual-text `line` and `col` | 0-indexed |

`_end` carries the leading underscore because `end` is a Lua keyword.

### 8.3 Required methods

#### `notify(message, level)`

Display a message to the user. Specified in full in §9.

#### `read_buffer(bufnr, opts) -> lines`

Returns an array of strings, one per line, with no trailing newlines.

`opts` (all optional):

| Key | Type | Meaning |
|---|---|---|
| `start` | number | First line to return, 0-indexed. Default `0`. |
| `_end` | number | Last line to return, or `-1` for "to the end". Default `-1`. |
| `file` | string | Read from this path instead of the current buffer. |
| `stdin` | boolean | Read from standard input instead of the current buffer. |

Source precedence is `file`, then `stdin`, then the adapter's current buffer. Range selection is
applied *after* the source is read, so `{ file = "board.md", start = 10, _end = 20 }` is well
defined.

Conversion: a request for `start = 0, _end = -1` returns every line; internally `start + 1` is
the first 1-indexed Lua line and `_end == -1` resolves to the line count. Lines requested beyond
the end of the source **MUST** be returned as empty strings rather than `nil`, so the result is a
dense array.

A read failure **MUST NOT** raise: the adapter notifies at `"error"` level and returns an empty
array. The caller distinguishes "empty file" from "unreadable file" by the notification, not by
the return value.

The CLI adapter additionally caches what it read: `_buffer_lines`, and for the `file` case
`_buffer_filename`, so a subsequent `write_buffer` with no `file` updates the same content
in memory.

#### `write_buffer(lines, opts)`

Writes an array of strings. Each element is one line; the adapter supplies line endings.

`opts` (all optional):

| Key | Type | Meaning |
|---|---|---|
| `bufnr` | number | Target buffer. Default: current. |
| `start` | number | First line to replace, 0-indexed. Default `0`. |
| `_end` | number | Last line to replace, or `-1` for "to the end". Default `-1`. |
| `file` | string | Write to this path. |
| `stdout` | boolean | Write to standard output. |

Destination precedence is `stdout`, then `file`, then the current buffer. `start`/`_end` apply to
the buffer case only: the range is removed and the new lines spliced in at `start`, so a
whole-buffer rewrite is the default and a partial replacement is opt-in.

A successful file write **SHOULD** notify at `"info"` level; a failed one **MUST** notify at
`"error"` level and return without raising.

#### `get_cursor() -> line, col`

Returns two values: a 1-indexed line and a 0-indexed column. An adapter with no real cursor
**MUST** still return a coherent pair (the CLI adapter tracks one in memory, starting at `1, 0`).

#### `set_cursor(line, col)`

Stores the position. No bounds checking is specified; a host **MAY** clamp.

#### `prompt_input(prompt, default, callback)`

Asks for a line of text and calls `callback(input)`. When the user supplies nothing, `default`
**MUST** be passed to the callback — including when `default` is nil, in which case the callback
receives nil. The prompt itself is user feedback and goes to stderr, never stdout (§9).

#### `prompt_select(items, opts, callback)`

Asks the user to choose from `items` and calls `callback(item, index)`.

`opts` (all optional): `prompt` (string, the heading) and `format_item` (function, item → string;
defaults to `tostring`).

Cancellation and invalid input **MUST** call `callback(nil, nil)` rather than raising or
silently doing nothing, so callers have one code path for "no selection". In the CLI adapter the
menu is 1-indexed and `0` cancels.

Both prompts are callback-style rather than return-style because a host's UI may be asynchronous.
An adapter **MAY** call the callback synchronously; a caller **MUST NOT** assume it will.

### 8.4 Optional methods

These have working defaults on the interface, so an adapter omits them unless its host supports
them. They are not checked by `Adapter.validate()`.

| Method | Default | Contract |
|---|---|---|
| `supports_virtual_text()` | `false` | Callers **MUST** consult this before using the rest of this table |
| `create_namespace(name)` | `nil` | Returns a host-specific namespace handle |
| `set_extmark(bufnr, ns, line, col, opts)` | `nil` | 0-indexed `line`/`col`; returns a mark id |
| `clear_namespace(bufnr, ns)` | no-op | Removes every mark in the namespace |
| `get_current_buffer()` | `false` | Current buffer handle |
| `buf_line_count(bufnr)` | `false` | Line count of a buffer |

`get_current_buffer` and `buf_line_count` return `false` rather than raising, marking them as
"not implemented" without making them mandatory. An adapter that cannot support virtual text
**MUST** return `false` from `supports_virtual_text()` rather than implementing the remaining
methods as approximations; `virtual_text.lua` degrades to doing nothing in that case.

## 9. User feedback: `notify()`

*To be specified.*

## 10. Configuration resolution

*To be specified.*
