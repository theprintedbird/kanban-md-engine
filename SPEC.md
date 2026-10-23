# kanban-md-engine — behaviour specification

Status: living document. Version: tracks `lua/kanban-md/version.lua` (currently `0.1.0`), kept in
step by `make version VERSION=<x.y.z>`.

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
  adapter in `adapter_registry`; apply `user_config` via `config.setup()`; and register ULID
  `on_create` triggers on the `Board`, `Column` and `Card` classes. Registration **MUST NOT**
  depend on the global `auto_id`: the trigger resolves `auto_id` itself when it fires (§4.3), so
  that a board file can turn identifiers on as well as off.
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
when it spans more than one line. `content_lines[1]` mirrors the first line as parsed, but `text`
is authoritative: the writer and `get_full_text()` build the first line from `text` (the writer
prefixing `task_indent`, as for a single-line card) and take only the continuation lines from
`content_lines`, so an edit to `text` reaches the file whether or not the card spans lines.

`Board.archive` being separate from `Board.columns` is load-bearing: statistics, completion
detection and position-based column fallbacks all iterate `columns` only, so archived cards
**MUST NOT** affect WIP counts or semantic-state inference.

### 4.3 Identifiers

Every board, column and card has a non-nil `id` field on the in-memory object. Only a card's
identifier can ever appear in the Markdown; board and column identifiers exist in memory only and
are made afresh each time a file is parsed.

| Object | Kept in | Read from the file | Written to the file | Stable across parses |
|---|---|---|---|---|
| Board | `board.id` | Never | Never | No |
| Column | `column.id` | Never | Never | Only while the columns keep their order |
| Card | `card.id`, and `card.properties.id` when persisted | Yes, the `id` property | When `persist_card_ids` resolves true, or the `id` was authored | Only when written to the file |

Where each identifier comes from:

- **Board.** Generated in `Board:new()`, before any file is parsed: `board_<ULID>` when `auto_id`
  is on and `setup()` has been called, otherwise `board_<timestamp>`. It follows the plugin config
  only, because no board file has been read yet. An `id` key in a `kanban:config` comment is an
  ordinary config value in `board.config`; it does not set `board.id`.
- **Column.** A column the parser creates is given a positional identifier, `column_1`,
  `column_2` and so on, counting regular columns in document order. The `__ARCHIVE__` section is
  given `__ARCHIVE__`. These are assigned before the `on_create` triggers run, so `auto_id` does
  not replace them, and reordering the columns renumbers them. A column created in code without an
  identifier (`board:add_column(name)`, `board:add_new_column(name)`) gets `column_<ULID>` when
  `auto_id` is on, and falls back to its name otherwise. As with the board, an `id` key in a
  `column:config` comment is a config value in `column.config`, not the column's identifier.
- **Card.** An `id` property on the card in the Markdown becomes `card.id`. Without one, the card
  gets `card_<ULID>` when `auto_id` is on, otherwise `card_<timestamp>_<counter>`.

For cards, the trigger resolves `auto_id` and `persist_card_ids` through the owning board (board
file > plugin config) when it can reach one, and through the plugin config otherwise. The parser
passes the board into each card's `on_create` context, so a `kanban:config` that precedes the
columns governs the cards parsed after it, in either direction.

Identifier *presence* is a contract; identifier *format* is only a contract when `auto_id` is on.
Because board and column identifiers are not persisted, nothing that outlives one parse should
refer to them; refer to a column by its name.

A generated card identifier is ephemeral by default and **MUST NOT** be written back to the
Markdown unless `persist_card_ids` resolves true (§7.8). An identifier the user authored is an
ordinary property, so it is written back either way.

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
  `card.properties[normalised_column_name]` to the current time. Column names normalise to
  snake_case (`"Code Review"` → `code_review`). Every timestamp the engine writes comes from
  `kanban-md.helpers.clock`, whose `now()` is `os.time()` unless a test has replaced it via
  `clock.set()`; nothing in the engine calls `os.time()` directly.
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
- A `wip_limit` that is not a number, at board or column level, reported as
  `Ignoring non-numeric wip_limit …`. The limit is not enforced, the authored value is kept so a
  round trip preserves it, and `valid` is left alone.

Exceeding a WIP limit is a **warning** that sets `valid = false`; it does not raise.

A `wip_limit` written as a quoted number (`wip_limit: "7"`) parses to the string `7` (§7.6), which
config parsing coerces to the number 7, so it is enforced and written back unquoted.

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
- **Blocked time** — time spent in columns flagged blocked or waiting, counted only within the
  cycle it is reported against and subtracted from active time. Time blocked before the cycle
  started, or after it ended, is not counted, so `active_time` is never negative.

All three are derived from the column timestamps on card properties, so they are only as good as
the trigger-maintained timestamps that produced them. Durations are formatted according to
`cycle_time_unit` and `stats_time_format` (§10).

## 7. The Markdown syntax contract

The board format is ordinary Markdown. Every kanban-specific element is either a heading level
that documents rarely use or an HTML comment, so a board renders unremarkably in Obsidian or any
other viewer, and a viewer that knows nothing about kanban shows the user their content rather
than machinery.

Two rules govern the whole grammar:

- **Anything unrecognised is preserved verbatim.** The parser has no error state for unknown
  content; it becomes a `markdown` content block (§4.4).
- **Markdown always wins.** Where an authored value and a resolved or inherited one disagree, the
  authored value is what the engine uses and what the writer emits.

### 7.1 Board title

```markdown
# My Board
```

An H1 sets `board.title`. A board with no H1 has the title `"Untitled Board"` and the writer
emits no title line for it. A board **SHOULD** contain at most one H1; where there is more than
one, each is re-rendered from the single `board.title`, so the last one parsed determines the
text of them all.

### 7.2 Columns

```markdown
###### In Progress
```

Columns are **H6** — six hashes. H2–H5 are reserved for the user's own documentation and are
preserved as prose; H1 is the board title. H6 is chosen because it is almost never used
otherwise, degrades gracefully in any renderer, and makes an accidental collision obvious.

Column order in `board.columns` is document order.

Lines between a column header and its first card are that column's documentation, held on
`column.header_markdown` and written back verbatim. That includes the blank lines at either end,
so a column whose prose is separated from its first card by a blank line keeps it:

```markdown
###### Backlog

Everything that is not yet ready to start.

- First card
```

`blank_line_after_column_header` (§7.8) inserts a blank line after the header only when the
documentation does not already begin with one, so the setting cannot double a blank line the
author wrote.

The setting also works in reverse, so moving a card into a column and back out leaves the file
as it was. A card that lands in an empty column is written below a new blank line. When the
column is empty again and its documentation is only blank lines, the writer leaves out the first
of them. Documentation with any prose in it is written verbatim, with or without cards.

### 7.3 Special sections

A column name wrapped in double underscores is a special section:

```markdown
###### __ARCHIVE__
```

- `__ARCHIVE__` is the one the engine understands. It becomes `board.archive`, is **not** a member
  of `board.columns`, and its cards are excluded from WIP counts and from the position-based
  semantic-state fallbacks (§4.2).
- Any other `__NAME__` section has no defined structure. The parser **MUST** preserve it and
  everything after it verbatim, and **MUST** stop attributing following list items to the previous
  column — an unknown special section ends the current column rather than silently swallowing its
  content.

### 7.4 Cards

```markdown
- Write the specification
```

A card is an unordered list item. There is no checkbox syntax: `- [ ]` and `- [x]` are not part of
the format, and completion is decided by which column a card is in (§6.3).

A card may span several lines. Lines indented by two or more spaces, or by one or more tabs, that
follow the card's first line with no intervening blank line are **continuation lines** and belong
to the card:

```markdown
- Write the specification
  The continuation lines are preserved exactly as authored,
  including their indentation.
```

A continuation line may itself be a list item, so a card can carry a nested list. An indented
list item that directly follows a card's line or one of its continuation lines is a continuation
line; any other list item starts a new card:

```markdown
- Write the specification
    Sections still to do:
      - Cards
      - Properties
- Review the specification
```

A blank line ends the card. A non-indented, non-list line ends the card and becomes prose.

A bullet marker with nothing after it — `-` alone, or followed only by whitespace — is valid
CommonMark but gives a card no usable text. kanban-md breaks with CommonMark here: the line is
left as column documentation rather than becoming a card (so any indented lines that follow it are
themselves column documentation, not continuation lines), and the parser reports it through
`notify()` at `"warn"` level (§9) with the message `List items may not start with a blank line`.
An empty bullet that is a continuation line, in a card's nested list, is card content and is not
reported.

### 7.5 Properties

Properties ride in HTML comments, which keeps them invisible in a rendered view.

**Card properties**, inline on the card's first line:

```markdown
- Write the specification <!-- id: card_01H…, in_progress: 1709567890, complexity: 3 -->
```

A property comment on its own line, inside a column, attaches to the card it accompanies. A
property comment that belongs to no card — one sitting between columns, for example — is
discarded.

A comment outside any column — before the first column header, or after an unrecognised `__X__`
section — is not kanban syntax unless it is a `kanban:config` comment. It is preserved verbatim as
Markdown, single-line or multi-line, so the `<!-- kanban-board -->` marker a host may use to
recognise boards survives every write.

A card's property block is the **last** HTML comment on the line, and it must close at the end of
the line. Any earlier comment is part of the card's text and is preserved verbatim, so a card may
talk about the syntax without being truncated:

```markdown
- Explain the <!-- kanban:config --> comment <!-- id: card_01H…, complexity: 2 -->
```

Here the text is `Explain the <!-- kanban:config --> comment` and only `id` and `complexity` are
read as properties. A card whose only comment is a literal one keeps it in its text, provided the
comment does not sit at the end of the line — there, it is read as the property block.

**Board configuration**, conventionally just after the title:

```markdown
<!-- kanban:config wip_limit: 7, auto_timestamp: false -->
```

**Column configuration**, just after the column header:

```markdown
###### In Progress
<!-- column:config wip_limit: 3, is_start_state: true -->
```

Inside a column, `<!-- config … -->` is accepted as a shorthand for `column:config`.

All three forms may be written across several lines; the parser joins them before parsing:

```markdown
<!--
  wip_limit: 3
  is_start_state: true
-->
```

Multiple `kanban:config` comments in one board merge, with later keys overriding earlier ones. A
comma directly after the `kanban:config` or `column:config` prefix is accepted on input; the
writer does not emit one.

### 7.6 Property values

Keys match `[%w_]+` and their authored case is preserved. Values are converted by shape:

| Written | Parsed as |
|---|---|
| `42` | number |
| `1.5` | number |
| `1709567890` | number (rendered back as a timestamp only for timestamp keys, §7.8) |
| `2024-03-04` or `2024-03-04T12:34:50Z` | number — converted to epoch seconds on parse |
| `true` / `false` (any case) | boolean |
| `[alpha, beta]` | array of strings, trimmed |
| `"42"` or `'42'` | string, quotes removed, no conversion — `"  "` keeps its whitespace |
| anything else | string |

Commas separate properties, except inside brackets or quotes, so an array or quoted value may
contain commas. A value ends at a comma or at whitespace followed by the next `key:`; inside quotes
neither ends it. A quoted value closes at the first matching quote character that is followed by
the end of the value, so a quote of the same kind elsewhere is part of the string
(`"say "hi" now"`). An unclosed or mismatched quote is kept as part of an ordinary string.

The writer quotes a string exactly when it would not read back as the same string unquoted: when
it is empty, has leading or trailing whitespace, contains a comma, whitespace followed by `word:`,
or a bracket, begins with a quote, or would parse as another type (`42`, `1.5`, anything starting
`YYYY-MM-DD`, `true`/`false` in any case). It uses double quotes, or single quotes when the string
contains a double quote that would close the value early. There is no escape syntax, so a string
that defeats both quote characters cannot round-trip; the writer emits it double-quoted and
reports it through `notify()` at `"warn"` level.

Array elements follow the same quoting rules, judged against the array's own separators. A quoted
element closes at the first matching quote followed by a comma or the closing bracket, and keeps
its content verbatim (`["one, two", " x "]`). An unquoted element is trimmed and is never
type-converted, so `[42, true]` is two strings; it ends at a comma or the closing bracket, counting
nested bracket pairs, and an empty one is dropped (`[a,, b]` is two elements). Text after an
array's closing bracket makes the whole value an ordinary string. The writer quotes an element
when it is empty, has leading or trailing whitespace, contains a comma or a bracket, or begins with
a quote, choosing and warning about quote characters as for any other string.

Timestamps are held internally as epoch seconds regardless of how they were authored.

### 7.7 Fenced code blocks

Content inside a fenced code block is never kanban syntax:

````markdown
```markdown
###### This is not a column
- This is not a card <!-- nor is this a property -->
```
````

A fence opens on a line whose first non-space content is three or more backticks or tildes, and
closes on a line of the same character, at least as long, with nothing but whitespace after it.
Everything between, blank lines included, is passed through untouched.

A fence opened inside a card's continuation lines belongs to that card, and the blank lines
within it do not terminate the card.

### 7.8 What the writer normalises

Round-tripping preserves prose exactly (§5.2), but structured elements are re-rendered, so these
normalisations apply:

- **Property order.** Properties are emitted in alphabetical order by key, not in the order
  authored.
- **Underscore-prefixed properties are never serialised.** Any property whose key begins with `_`
  is ephemeral, internal state — `_cursor_target`, `_scratch`, anything — and **MUST NOT** appear
  in the output. Re-parsing therefore never resurrects it. Only a leading underscore counts:
  `due_date` is an ordinary property. When the filter leaves nothing to write, no comment is
  emitted at all — a card whose properties are all underscore-prefixed is written as a bare list
  item, not with an empty `<!--  -->`. A `kanban:config` or `column:config` comment, whose prefix
  is itself content, is still written with the prefix alone.
- **Comment placement.** A card's properties are re-emitted inline on the card's first line, even
  when they were authored in a standalone comment beneath it.
- **Card identifiers.** A generated id is written only when `persist_card_ids` resolves true
  (§10). When it does, an id the user authored in the Markdown wins over the in-memory `card.id`,
  so a generated id can never overwrite an authored one. An authored id is written back whatever
  `persist_card_ids` says. Board and column identifiers are never written (§4.3).
- **Column configuration.** Only the authored layer (`column.markdown_config`) is written, so
  properties inferred from a column type or pattern are not injected into the user's file. Setting
  `write_full_config_to_markdown` writes the fully resolved `column.config` instead.
- **Timestamp rendering.** Controlled by `timestamp_format`: `epoch` (default) writes the raw
  number, `iso` writes `YYYY-MM-DDTHH:MM:SSZ` in UTC, `date` writes `YYYY-MM-DD` in local time.
  Only keys known to be timestamps are formatted — `archived` plus the normalised name of every
  column on the board — so an ordinary number property stays a number.
- **Comment layout.** `property_separator` (default `", "`) joins properties. When
  `use_multiline_comments` is set and the assembled comment exceeds `multiline_threshold`
  characters, the comment is split across lines instead.
- **Blank lines.** `blank_line_after_title`, `blank_line_after_config`,
  `blank_line_after_column_header` and `blank_lines_between_sections` govern spacing around
  structured elements. Blank lines within preserved prose are untouched.
- **Card indentation.** `task_indent` prefixes single-line cards. Continuation lines keep their
  authored indentation.

### 7.9 Board detection

Deciding whether a given Markdown file is a board at all is the host's job, not the parser's —
`board:parse()` will happily parse anything. The `detection_strategy` setting exists for hosts
that scan files: `"marker"` requires `<!-- kanban-board -->` near the top of the file,
`"extension"` requires a `.kanban.md` name, `"both"` accepts either, and `"auto"` infers from the
presence of H6 headings. `"marker"` is the default and `"auto"` **SHOULD NOT** be used on
directories of general documentation.

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

- `Adapter.new(implementation)` validates the implementation table and only then sets `Adapter`
  as its metatable, so the abstract stubs inherited from the interface never stand in for a
  missing method. An incomplete implementation **MUST** raise; `Adapter.new` never returns a
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

`adapter:notify(message, level)` is the engine's only channel for telling a user something. It is
a required adapter method (§8.3) and carries a contract of its own, because the engine's callers
rely on the severity to decide whether a result is usable.

### 9.1 Levels

`level` is one of three strings, and defaults to `"info"` when omitted or nil:

| Level | Meaning | Caller expectation |
|---|---|---|
| `"info"` | Something succeeded or is worth reporting | The operation completed |
| `"warn"` | The operation completed, but not cleanly | Result is usable; a limit or rule was breached |
| `"error"` | The operation did not complete | Result is not usable |

These are the only defined levels. An adapter **MUST** accept an unrecognised level without
raising; it **SHOULD** treat it as `"info"`.

`"error"` is a report, not a raise. Engine code that notifies at `"error"` level **MUST** also
return a value that reflects the failure — an empty array from `read_buffer`, an early return
from `write_buffer` — because the host never learns about the failure from the control flow.
Conversely, a WIP limit being exceeded is a `"warn"` (§6.4), never an `"error"`: the board is
still written.

### 9.2 The stdout/stderr split

This is the contract that makes the engine usable in a pipeline:

> **Data goes to stdout. Everything else goes to stderr.**

For the CLI adapter specifically:

- `notify()` at every level writes to **stderr**, and flushes.
- `prompt_input()` and `prompt_select()` write their prompts, defaults and menus to **stderr**,
  and read the reply from stdin.
- The only thing that reaches **stdout** is board content, and only via
  `write_buffer(lines, { stdout = true })`.

So `lua script.lua > board.md` produces a clean board file even when the run emits warnings, and
`2>/dev/null` silences the commentary without touching the data. An adapter whose host has no
such split (an editor, say) satisfies this clause by routing notifications to its own message
area and board content to its own buffer; the requirement is the separation, not the file
descriptors.

### 9.3 Prefixes

The CLI adapter emits `<prefix><space><message><newline>`:

| Level | Prefix | Codepoints |
|---|---|---|
| `"info"` | ℹ️ | U+2139 U+FE0F |
| `"warn"` | ⚠️ | U+26A0 U+FE0F |
| `"error"` | ❌ | U+274C |

An unrecognised level yields an empty prefix, so the line begins with the separating space.

The prefixes are part of the CLI adapter's observable output and **SHOULD** be asserted by tests
on the emitted string rather than by "the call did not error" — these bytes have been corrupted
before, and a test that only checks for absence of an error cannot see it. Other adapters are
free to present severity however their host does; the *levels* are the contract, the emoji are
not.

## 10. Configuration resolution

Configuration arrives from four places. They form a strict precedence, most specific last:

```
hard defaults (config.lua)
  → host configuration (config.setup(user_config))
    → board file (<!-- kanban:config … -->)
      → column configuration (<!-- column:config … -->, and column types)
```

### 10.1 Plugin layer

`kanban-md.config` holds one module-level table:

| Function | Behaviour |
|---|---|
| `config.get()` | The current table, live |
| `config.get_value(key)` | One current value |
| `config.setup(user_config)` | Deep-merges `user_config` over the current table and returns it |
| `config.reset()` | Restores a deep copy of the hard defaults |
| `config.get_defaults()` | A deep copy of the hard defaults |

`setup()` merges recursively: nested tables such as `column_config.types` are merged key by key
rather than replaced wholesale. It is also cumulative — two calls layer on one another; only
`reset()` returns to defaults.

Because this table is a module singleton shared by everything in a process, a test that mutates
it **MUST** restore it afterwards, and a test asserting a *default* value **MUST NOT** depend on
having run before anything that changes it.

### 10.2 Board layer

`board:get_config_value(key)` resolves one key: the board file's value if the board file
authored that key, otherwise the plugin value.

Presence, not truth, decides. A key written in the board file counts as present even when its
value is `false`, so `<!-- kanban:config auto_timestamp: false -->` **MUST** override a plugin
default of `true`. `board.config` may be a `TypeConverter` (after a parse) or a plain table (from
`Board:new()`); both are handled, using `:has()` and `rawget` respectively so that a stored
`false` is never mistaken for an absent key.

`board:get_effective_config()` returns a plain-table snapshot: a deep copy of the plugin config
with every key authored in the board file overlaid. This is what the writer is given, so a
board-file formatting option applies to that board's output without touching global state.

### 10.3 Board-overridable keys

Any key *may* be written in a board file, and `get_config_value` will resolve it. The keys the
engine actually consults through that resolution — i.e. the ones where writing them in a board
file changes behaviour — are these:

**Writer and formatting**

`timestamp_format`, `task_indent`, `property_separator`, `blank_line_after_title`,
`blank_line_after_config`, `blank_line_after_column_header`, `blank_lines_between_sections`,
`use_multiline_comments`, `multiline_threshold`, `wrap_properties_at`, `persist_card_ids`

**Automation**

`auto_timestamp`, `auto_id`, `use_complexity`, `default_complexity`

**Optional features**

`dependency_validation`, `subtask_validation`

Plus the structural keys read directly off `board.config` rather than through the resolver:
`wip_limit` (board-level WIP validation, §6.4), `workflow` and `triggers` (trigger
auto-registration, §6.2).

New code that reads configuration **SHOULD** go through `board:get_config_value()` rather than
`config.get_value()`, so the board file keeps its say; a key added to this list needs no other
change.

### 10.4 Mode-valued keys

`dependency_validation` and `subtask_validation` accept a boolean or a string and normalise
through `config.normalize_dependency_mode()`:

| Written | Normalises to | Effect |
|---|---|---|
| `true`, `"on"`, `"strict"` | `"strict"` | Block the move to completion |
| `"warn"` | `"warn"` | Warn, allow the move |
| `false`, `"off"`, absent, anything else | `false` | No validation, no trigger registered |

Normalisation is deliberately total: an unrecognised value is off, not an error. The triggers are
only registered when the mode is truthy (§6.2), so the default costs nothing.

### 10.5 Column layer

A column's configuration is resolved when it is parsed, from three sources:

**Type resolution**, in priority order:

1. An explicit `type` in the column's own config comment.
2. A named definition: `column_config.definitions[column_name].type`.
3. A pattern: the column name matched against each `column_config.types[*].patterns` (case-insensitive). Where more
   than one pattern matches, the longest — most specific — wins. If multiple patterns of equal length match,
   the type name that sorts first alphabetically wins.
4. No match: the column is untyped.

**Property merging**, lowest to highest precedence:

```
type properties  <  named definition properties  <  authored markdown properties
```

The result is `column.config`. The authored layer alone is kept as `column.markdown_config`,
which is what the writer serialises (§7.8) — so type-derived properties change behaviour without
rewriting the user's file.

There are no built-in column types: `column_config.types` is empty by default, and the engine
contains no hardcoded name patterns. A board with no `column_config` is resolved entirely by
explicit properties and the positional fallbacks in §6.3.

**Type-declared triggers.** A type may declare triggers, keyed by trigger point:

```lua
types.completion = {
  triggers = {
    on_entry = {
      { module = "my.triggers", function_name = "mark_done", name = "mark_done", args = { 30 } },
    },
  },
}
```

`auto_register_triggers()` **MUST** register each of them on every column resolving to that type
(§6.2). `module` is `require`d, `function_name` is called as a factory with `args` (empty when
absent) and the function it returns is registered under `name`. A trigger that cannot be
registered — the module does not load, or the named field is not a function — **MUST** raise an
error naming the type, the trigger and the module; it **MUST NOT** be skipped silently.

**Requirement validation.** A type may declare `requires_wip_limit = true`. When a column of that
type has no `wip_limit`, `missing_property_requirement` decides what happens: `"none"` is silent,
`"warning"` (the default) emits a warning, `"error"` raises.

`"error"` raises a Lua error out of `parse()`; it does **NOT** call `notify()`, so nothing reaches
the adapter and a host cannot route or style it. A host that wants to report the fault rather than
crash **MUST** `pcall` around `parse()` and notify itself. The raised message carries no
`file:line:` prefix, so it may be shown to a user as-is. This is the one validation fault the
engine signals by raising rather than by reporting through §9; an invalid type *reference* — a
column naming a type that is not defined — always warns through `notify()` instead, whatever
`missing_property_requirement` is set to.

### 10.6 Host-owned keys

Some defaults in `config.lua` are consumed by hosts rather than by the engine — `use_telescope`,
`dependency_marking_hl`, `confirm_destructive`, `use_input`, `detection_strategy`. The engine
carries them so a host has a single place to configure, and passes them through unexamined.

The display options (`show_stats_virtual_text`, `show_lead_time`, `show_cycle_time`,
`cycle_time_unit`, `stats_time_format`) are read by engine code — `stats.lua` and
`virtual_text.lua` — but only have a visible effect on a host whose adapter supports virtual text
(§8.4).

The engine **MUST NOT** load host code on the strength of a configuration value (§6.2). A key
that only a host understands is a key the engine stores and hands back, never one that makes the
engine `require` something it does not ship.
