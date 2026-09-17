# CLAUDE.md (Engine)

This file provides guidance to Claude Code (claude.ai/code) when working with the kanban-md engine code.

Use British English.

## Project Overview

This is a Kanban board engine for managing Markdown files, designed for compatibility with Obsidian. It allows users to create and manage Kanban boards using extended Markdown syntax with HTML comments for configuration and task properties. The engine is platform-agnostic and can be used in standalone Lua environments or integrated into applications like Neovim.

`SPEC.md` is the behaviour specification: the data model, the markdown syntax contract, the adapter
contract, the `notify()` contract and configuration resolution. Read it rather than restating it
here. When a change alters observable behaviour, update `SPEC.md` in the same change - it is meant
to be assertable against the test suite, so a statement there that no longer holds is a bug.

## Implementation Notes

When working with parser/writer:

1. parser.lua and writer_mixin.lua are the most mature components - reference them for patterns and conventions
2. Timestamps are held internally as epoch seconds for consistency; ISO dates in the markdown are
   converted on parse. How they are *written back* depends on `timestamp_format`: `epoch`
   (default), `iso` (`YYYY-MM-DDTHH:MM:SSZ`, UTC) or `date` (`YYYY-MM-DD`, local time). Only keys
   known to be timestamps are formatted - `archived` plus the normalised name of every column -
   so an ordinary number property stays a number.
3. Card IDs are auto-generated using either a ULID (default) or hash functions if not specified *and* the config is set for it (default true)
4. When modifying parser/writer, ensure content blocks are built/used correctly for full round-trip fidelity

## Completion Tracking

Completion is **column-based**, not checkbox-based:

1. A card is "complete" when it's in a completion column (detected via `lua/kanban-md/helpers/column.lua:is_completion_column()`)
2. The detection function contains NO hardcoded column name patterns - all detection is explicit
   (`is_completion_state`) or position-based. See `SPEC.md` section 6.3 for the full fallback order.
3. **Timestamps are automatically set via triggers**: When `auto_timestamp = true` (default in `config.lua`), the `board:auto_register_triggers()` method registers timestamp triggers that automatically set `card.properties[column_name] = os.time()` when a card enters any column
4. **NEVER manually set completion timestamps in code**: Use `board:auto_register_triggers()` and let the trigger system handle it automatically. Tests that manually set `card.properties.done = os.time()` are incorrect and should be refactored.

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

All trigger points come from `triggerable.lua`, which Board, Column and Card mix in. The
registration methods are the names to use in code: `register_on_checking`, `register_on_entry`,
`register_on_exit`, `register_on_stay`, `register_on_create`. There is no `on_entering` or
`on_exiting` method; the points are `on_entry` and `on_exit`. `SPEC.md` section 6 defines when each
one fires and what a trigger may return.

Advanced features (subtasks, dependencies, workflow and capacity rules, ULID ids) are implemented
entirely via triggers in `lua/kanban-md/extras/`, with no special core mechanisms. Triggers carry
metadata (`bypassable`, `category`) so that `board:move_card_with_bypass()` can skip one category
of check - dependencies, say - while still enforcing WIP limits and everything else.

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

Busted, run through the Makefile - `make help` lists every target. `make test` is the whole suite.
Tests use `tests/polyfills/vim.lua` for a pure Lua stand-in for the `vim` utility functions, wired
up by `.busted`. `tests/README.md` has the rationale for the suite's layout and for the performance
specs in particular, including the `KANBAN_SKIP_PERF` / `KANBAN_PERF_TOLERANCE` escape hatches.

**Important:**

- **DO NOT use git commands (stash, reset, etc.) for testing or temporary state management.**
  Use temporary files instead to save/restore state if needed - `cp config.lua config.lua.backup`
  rather than `git stash`.
