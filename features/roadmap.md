# kanban-md Engine Roadmap

This is the single live plan for the kanban-md engine. Everything the trigger-based architecture
already achieved (dynamic columns, workflow validation, dependencies/subtasks, capacity triggers,
the column type system) is done and specified in `SPEC.md`; it is not repeated here. This document
lists only what is genuinely still open. For historical design notes on the trigger system itself,
see `features/dynamic-columns.md`.

The engine has no UI and no host bindings of its own (`SPEC.md` §1) - Neovim commands, buffers and
keymaps belong to a separate host such as `kanban-md.nvim`, not to this repository. Every item
below is scoped to the Lua API under `require('kanban-md.*')`, delivered - like every advanced
feature the engine already has - as triggers registered via `triggerable.lua`
(`register_on_checking`, `register_on_entry`, `register_on_exit`, `register_on_stay`,
`register_on_create`; see `SPEC.md` §6.1 and `CLAUDE.md`), not as new core mechanisms.

## Open Items

### 1. Auto-move on condition

**Current state**: `lua/kanban-md/extras/workflow_triggers.lua` (`create_workflow_rules_trigger`,
around line 230) already parses `auto: true` on a workflow transition and, when the transition's
`when` condition holds, sets `context.auto_move = true` on the `on_checking` result.
`lua/kanban-md/validation_result.lua` carries the same flag through as `ValidationResult.auto_move`
/ `:is_auto_move()`. **Nothing reads that flag to move the card.** It is only ever computed while a
move to the target column is already being validated - i.e. something has to request the move
first. There is no mechanism that notices a property change on a card sitting still in a column and
initiates the move itself.

**What is still needed**:
- A trigger (`on_stay` on the source column is the natural point, per the trigger points in
  `SPEC.md` §6.1) that evaluates outstanding `auto: true` workflow transitions for cards already in
  a column and, when `is_auto_move()` would be true, performs the move rather than just flagging it.
- A decision on when that evaluation runs (see "Open question" below) and how repeated/cascading
  auto-moves are prevented from looping.
- Adapter notification of the move via `notify()` (`SPEC.md` §9), since the card moved without an
  explicit host-initiated call.

**Open question - evaluation timing**: on every `board:save`/write, on-demand via an explicit
engine call the host can invoke, or both. The engine has no timer or background scheduler of its
own, so periodic evaluation would have to be driven by the host adapter calling into the engine,
not by anything inside `lua/kanban-md/`.

### 2. Time-based transitions

**Current state**: `config.lua` documents `archive_after_days` (line ~43) and `auto_archive` (line
~138), and `column_type_resolver.lua`'s doc comment shows a per-column `auto_archive_days`
property. None of these keys are read anywhere outside `config.lua`'s own comments and
`column_type_resolver.lua`'s example - there is no code that inspects a card's age and moves or
archives it. This is a documented but entirely unimplemented config surface, not a partial feature.

**Design should follow the same shape as completion timestamps** (`CLAUDE.md`, "Completion
Tracking"): a trigger, not hand-written logic, using `clock.now()` from
`lua/kanban-md/helpers/clock.lua` so tests can control time. A `register_on_stay` trigger on a
completion column (detected via `column.is_completion_column()`,
`lua/kanban-md/helpers/column.lua`) comparing `clock.now() - card.properties[<completion
timestamp key>]` against `archive_after_days` is the natural implementation; moving the card to
`__ARCHIVE__` reuses the existing archive column handling described in `SPEC.md` §7.3.

**Open question - evaluation timing**: same as auto-move above; the engine cannot schedule itself,
so this needs an explicit call the host makes (on open, on save, or on demand).

### 3. Swim lanes

**Current state**: not implemented at all. There is no `swimlane` concept anywhere in `lua/`
(confirmed by search) - no parser support for a `swimlane:` prefix or property, no grouping in the
board data model (`SPEC.md` §4.1), and no column-naming convention for it.

**What it needs**: this is a data-model change, not just a trigger - `SPEC.md` §4 would need a
swim-lane concept added to the Board/Column shape, `parser.lua` would need to recognise the
markdown convention, and `writer_mixin.lua` would need to round-trip it. Once the model exists,
per-lane WIP limits, capacity and stats could most likely be layered on with the existing trigger
and stats infrastructure rather than new mechanisms. Worth scoping as a `SPEC.md` change first
before writing code, since it affects the markdown syntax contract (§7) other tooling depends on.

### 4. `is_active_state` is defined but unused

**Current state**: `is_active_state` is a real, documented column property
(`config.lua:520`, explicitly marked `[DEFINED BUT NOT ACTIVELY USED]`) and is part of the default
`wip` column type (`type_converter.lua:49`). It round-trips through the column type resolver and is
asserted on in `tests/unit/column_type_resolver_spec.lua` and
`tests/integration/column_type_spec.lua`, but no helper or trigger in `lua/kanban-md/helpers/` or
`lua/kanban-md/extras/` ever reads it. Compare with `is_completion_state`, which
`helpers/column.lua:is_completion_column()` actually consults.

**What it needs**: either give it a consumer - e.g. a `helpers/column.lua:is_active_column()`
alongside `is_completion_column()`, used the same way `is_start_state` etc. already feed
`stats.lua`'s cycle-time calculation (`SPEC.md` §6.3/§6.5) - or drop the property and its config
entry if no use case is going to consume it. Leaving it half-wired is the current state and should
not persist indefinitely.

### 5. Complexity-overload check

**Current state**: an idea, not a design. Complexity/story-point tracking itself is implemented
(`use_complexity`/`default_complexity` in `config.lua`, the `default_complexity` trigger in
`lua/kanban-md/triggers.lua`, and per-column complexity totals already computed in `stats.lua`
around line 296 - `wip_complexity`, `active_complexity`, etc.). What is missing is any check or
warning that *acts* on those totals - nothing in the codebase enforces or warns about a column
carrying too much complexity at once, the way `wip_limit` enforces a card-count limit.

**What it needs**: a `register_on_checking` trigger on the column, modelled directly on the
existing WIP-limit trigger pattern shown in `triggerable.lua`'s own docstring - summing
`card.properties.complexity` for the column's cards (`stats.lua` already does this arithmetic) and
comparing against a configurable `max_complexity`/`complexity_limit`, denying or warning on entry
the same way WIP limits do today. No new column property is needed beyond a limit value; the
existing complexity plumbing already produces the numbers.
