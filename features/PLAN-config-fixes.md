# Plan: Fix Ignored Board Config and Round-Trip Defects

**Status**: 🔴 Not started — this document is the hand-off plan.
**Date**: 2026-07-19

## Context

An audit of the engine found that several configuration options declared in the
kanban file itself (`<!-- kanban:config ... -->`) are silently ignored, and that
the parser/writer round trip loses or corrupts data in several cases. All
defects below were **reproduced empirically** against the current code (all 716
existing tests pass, so none of these are covered by the suite).

Two root causes explain most of the defects:

1. **No unified "effective config" resolution.** Some code paths honour board
   file config with a fallback to plugin config (`board.lua`
   `register_basic_triggers()`, `helpers/column.lua`), but the writer
   (`writer_mixin.lua`), the ID system (`extras/id_triggers.lua`) and stats
   formatting read *only* the global plugin config via
   `config_module.get_value()`. Anything the user sets in the board file that
   those modules consume — `persist_card_ids`, `timestamp_format`,
   `task_indent`, `property_separator`, `use_multiline_comments`, etc. — is
   ignored.
2. **No separation between authored and resolved column config.** The parser
   merges type-derived properties (from `column_config` types/definitions/
   patterns) directly into `column.config`, and the writer serialises
   `column.config` back to markdown. Implicit, resolved properties therefore
   get written into the user's file even though
   `write_full_config_to_markdown = false` (the default, and documented in
   `CONFIG_PLAN.md` as a *future* opt-in feature).

## Work items

Ordered so that dependencies come first. Each item lists severity, affected
code, a reproduction, the fix approach, tests to add, and a **delegation
recommendation** (which class of agent can safely do the work).

---

### Task 1 — Introduce effective-config resolution (board file > plugin config > defaults)

**Severity**: High (root cause of the "config in file is ignored" class).
**Depends on**: nothing. **Blocks**: Tasks 2, 3.
**Delegate to**: a *strong* model (architectural, cross-cutting). Do this first.

**Problem**: `<!-- kanban:config persist_card_ids: true -->` parses into
`board.config` but is never consulted:

- `writer_mixin.lua:118` — `config_module.get_value('persist_card_ids')`
- `extras/id_triggers.lua:61,64,96,99` — same
- `writer_mixin.lua` `format_timestamp()`, `properties_to_comment()`,
  `write_task()`, `write_from_blocks()`, `write_legacy()` — all read only the
  global config for `timestamp_format`, `property_separator`, `task_indent`,
  `blank_line_*`, `use_multiline_comments`, `multiline_threshold`,
  `wrap_properties_at`.

Repro (board file config set, global default `persist_card_ids = false`):

```lua
board:parse("# B\n<!-- kanban:config persist_card_ids: true -->\n\n###### Todo\n\n- Task\n\n###### Done\n")
board:write()  -- no id: written; file config ignored
```

**Fix approach**:

1. Add `Board:get_config_value(key)` that resolves
   `self.config[key]` → `plugin_config.get_value(key)` (board file wins when
   the key is present; use `TypeConverter:has()`/raw presence, not truthiness,
   so explicit `false` in the file wins over a `true` default).
2. Refactor `board.lua:register_basic_triggers()` and `auto_register_triggers()`
   to use it (they currently hand-roll the same pattern — keep behaviour).
3. Thread board context into the writer. `write_task()`/`write_column()`/
   `properties_to_comment()` are locals without board access; pass an
   `effective_config` (plain table snapshot from `Board:get_effective_config()`)
   down from `write()`/`write_from_blocks()`/`write_legacy()` instead of
   calling `config_module.get()` inside the helpers.
4. In `extras/id_triggers.lua`, resolve `persist_card_ids`/`auto_id` through
   the board when reachable (`context.board` or `card → column.board`), falling
   back to plugin config when there is no board in context.
5. Document in `config.lua` which options are board-file-overridable.

**Tests**: board file setting each of `persist_card_ids`, `timestamp_format`,
`task_indent`, `auto_timestamp: false` overriding a different global value;
explicit `false` in file beating `true` global; absence falling back to global.

---

### Task 2 — Persist card IDs end-to-end when `persist_card_ids` is enabled

**Severity**: High (the reported symptom). **Depends on**: Task 1.
**Delegate to**: mid-tier model once Task 1 lands (the remaining work is
localised).

**Problem**: even with the config resolved correctly, persistence has gaps:

- `write_task()` (`writer_mixin.lua:112-121`) only writes `id` if `task.id` is
  set; parsed cards only get IDs if `core.setup()` registered the class-level
  ULID trigger. Library consumers using `Board:parse()` without `setup()` get
  `card.id = nil` and nothing persists.
- `id_triggers.lua` syncs `obj.properties.id` at *creation* time only, and only
  when the *global* flag is on at that moment.

**Fix approach**: make `write_task()` the single source of truth: when the
effective `persist_card_ids` is true, write `task.properties.id or task.id`;
when false, still preserve an `id` the user authored in the markdown
(`task.properties.id`), which already works today — add a regression test for
it. Consider a parse-time fallback ID (mirroring `Board:new`/`Column:new`
fallbacks) so cards always have IDs even without `setup()`.

**Tests**: round-trip with `persist_card_ids: true` in board file produces
stable `id:` properties; second round trip does not change them; user-authored
ids survive with the flag off.

---

### Task 3 — Stop writing resolved/implicit column config to markdown

**Severity**: High (writes properties the user never authored; violates
`write_full_config_to_markdown = false` and the "Markdown always wins"
contract in `CONFIG_PLAN.md`). **Depends on**: nothing (coordinate with Task 1).
**Delegate to**: a *strong* model (touches parser/writer data model).

**Problem**: with a `column_config` type whose pattern matches "done", parsing

```markdown
# Board

###### Todo

- A task

###### Done
```

and writing produces `###### Done\n<!-- column:config, is_completion_state: true -->`
— an injected comment. Cause: `parser.lua` `apply_column_config()` (lines
185-211) and the post-processing pass (lines 616-655) merge resolved type
properties into `column.config`, and both writers serialise `column.config`.

**Fix approach**: keep two layers on the column — the authored markdown
properties (what gets written back) and the resolved/effective config (what
triggers, helpers and stats consult). Suggested: store parsed markdown props as
`column.markdown_config`, keep merged result in `column.config`, and have the
writer serialise `column.markdown_config` unless the effective
`write_full_config_to_markdown` is true. Audit `helpers/column.lua`,
`stats.lua`, `board.lua` to confirm they read the merged layer.

**Tests**: round-trip fidelity with pattern/definition-based types (no injected
comments); `write_full_config_to_markdown = true` writes the resolved config;
authored column config still round-trips verbatim.

---

### Task 4 — Parser drops multiline task property comments

**Severity**: High (silent data loss). **Depends on**: nothing.
**Delegate to**: mid-tier model.

**Problem**: a multiline HTML comment after a card is parsed with
`config_type = "task"`, but the completion branch (`parser.lua:365-368`) is
`elseif current_column and pending_config then` — `pending_config` is nil for
multiline comments (only the single-line path creates it), so the properties
are discarded. Repro: card followed by

```markdown
<!--
complexity: 5
assignee: alice
-->
```

parses with `complexity = nil`, `assignee = nil` — and the comment is also
dropped from output (not added to any markdown buffer).

**Fix approach**: in the multiline completion branch, when `config_type ==
"task"` and there is a `current_column`, set
`pending_config = { properties = parse_properties(comment_buffer) }` so the
existing flush logic applies it to `current_card`.

**Tests**: multiline properties applied to preceding card; round-trip keeps the
properties (single-line re-serialisation is acceptable).

---

### Task 5 — Unknown `__SPECIAL__` H6 sections are destroyed and their cards leak

**Severity**: High (data corruption). **Depends on**: nothing.
**Delegate to**: mid-tier model.

**Problem**: `parser.lua:460-493` — an H6 header matching `^__` that is not
`__ARCHIVE__` is neither made a column nor added to the markdown buffer
(`add_to_markdown = false` is set before the name check). The header line
vanishes on write, and because `current_column` is not reset, every card under
it is appended to the *previous* column. Repro: a `###### __NOTES__` section
between Todo and Done → its list items become Todo cards and `__NOTES__`
disappears from the written file.

**Fix approach**: decide the semantics (recommended: treat unknown `__X__`
sections as preserved markdown — add the header line and everything until the
next H6 to the markdown buffer and set `current_column = nil`; alternatively
parse them as special non-stat columns). Either way, no line loss and no card
leakage.

**Tests**: round trip preserves the section verbatim; cards under it do not
join the previous column; board stats unaffected.

---

### Task 6 — Board config comment lost when the file has no H1 title

**Severity**: Medium (data loss in a less common layout). **Depends on**: nothing.
**Delegate to**: cheap/fast model (small, well-specified).

**Problem**: `write_from_blocks()` only emits the `kanban:config` comment
inside the `TITLE` block branch (`writer_mixin.lua:235-250`). A file that has
`<!-- kanban:config wip_limit: 5 -->` but no `# Title` parses fine
(`board.config.wip_limit == 5`) but the comment is gone after `write()`.

**Fix approach**: track whether the config was emitted; if no TITLE block
exists, write the config comment at the top of the output (before the first
block). Keep the existing after-title placement when a title exists.

**Tests**: round trip of a title-less board keeps the config; board with title
unchanged.

---

### Task 7 — `archive_done_cards()` age check uses the wrong timestamp key and wrong column

**Severity**: Medium (archives cards regardless of age for multi-word
completion columns). **Depends on**: nothing.
**Delegate to**: cheap/fast model (repro and fix are mechanical).

**Problem**: `board.lua:640-652` computes `completion_column_name =
col.name:lower()` — but timestamp properties are snake_case
(`"All Done"` → `all_done`, set by `triggers.lua` `normalize_column_name`).
The lookup `task.properties["all done"]` misses, `done_time` defaults to 0,
`0 < cutoff_time` is always true, and the card is archived no matter how
recent. Repro: completion column named "All Done", card completed now,
`archive_done_cards(10)` → archives it (expected 0). Additionally the code
scans for the *first* completion column on the board instead of using the
column the card is actually in.

**Fix approach**: use the same normalisation as `triggers.lua`/`stats.lua`
(extract `normalize_column_name` into a shared helper, e.g.
`helpers/column.lua`) and read the timestamp for the card's own column
(`column`, already in scope).

**Tests**: multi-word completion column with recent card not archived with
`older_than_days > 0`; old card archived; multiple completion columns use each
card's own column timestamp.

---

### Task 8 — `Column:remove_card()` can remove the wrong card on duplicate IDs

**Severity**: Low-Medium (needs duplicate ids, which `validate()` flags but
does not prevent). **Depends on**: nothing.
**Delegate to**: cheap/fast model.

**Problem**: `column.lua:191-196` matches `c.id == card.id or c == card` and
takes the *first* hit. With two cards sharing an id (a state the parser happily
produces from user markdown), removing the second removes the first. Verified:
two cards with id `"dup"`, `remove_card(B)` leaves B and removes A.

**Fix approach**: prefer identity — scan for `c == card` first; fall back to id
match only if no identity match. Guard against `card.id == nil` matching other
nil-id cards.

**Tests**: duplicate-id removal removes the exact instance; nil-id cards.

---

### Task 9 — Minor issues batch

**Severity**: Low. **Depends on**: Tasks 1/3 for a few items.
**Delegate to**: cheap/fast model as a single batch, with the list below as the
spec.

1. **Stray comma after config prefix**: `properties_to_comment()` joins the
   prefix with `property_separator`, producing `<!-- kanban:config, wip_limit: 5 -->`
   instead of the documented `<!-- kanban:config wip_limit: 5 -->`
   (`writer_mixin.lua:70-93`). Join the prefix with a space instead.
2. **Multiple `kanban:config` comments**: each one *replaces* `board.config`
   wholesale (`parser.lua:354-357, 385-389`). Merge instead, or document
   last-wins.
3. **`board.config` type inconsistency**: `Board:new()` sets a plain table,
   `parse()` may replace it with a `TypeConverter`. Normalise to
   `TypeConverter` in `Board:new()`.
4. **Timestamp heuristic misformats plain numbers**: `format_property_value()`
   treats any number in `(946684800, 2147483647)` as a timestamp; with
   `timestamp_format = "iso"` a large numeric property (e.g. a numeric id)
   becomes a date. Maintain an explicit set of timestamp keys (column
   timestamp keys + `archived`) instead of a magnitude heuristic.
5. **Property keys are lowercased** on parse (`parse_properties`,
   `parser.lua:129`), so `dueDate:` round-trips as `duedate:`. Either preserve
   case or document the normalisation.
6. **`patterns.property` in `parser.lua:30` is dead code** (custom scanner is
   used); remove it. `parse_task()`'s inline-property extraction is also
   redundant with `finalize_card()` — deduplicate.
7. **`find_completion_timestamp()`** (`stats.lua:140-148`) says "latest" but
   uses the earliest-matching helper; with multiple completion columns the
   semantics are unclear. Pick one (latest entry into any completion column is
   the sensible reading) and test it.
8. **`is_backlog_column()` fallback** uses `board.columns[1]` without filtering
   `__`-prefixed specials (`helpers/column.lua:122-127`), unlike its siblings
   which use `get_regular_columns()`. Align it.
9. **`id_triggers.lua` seeds `math.randomseed` using `math.random`** before any
   seed is set (line 19) — harmless but confused; seed from `os.time()` +
   `os.clock()`.

---

### Task 10 — Test-infrastructure gap that hid all of the above

**Severity**: Process. **Depends on**: nothing; ideally done alongside Task 1.
**Delegate to**: mid-tier model.

`tests/polyfills/vim.lua:64-65` unconditionally runs `require('kanban-md.cli').setup()`
with *default* config for every standalone test. Consequences:

- No test exercises the engine without `setup()` (the pure-library path).
- No test exercises non-default global config or board-file config overrides.
- Class-level ULID triggers registered by one spec leak into all specs
  (module-level state), masking nil-id behaviour.

**Fix approach**: keep the polyfill's vim shims but move the `setup()` call
into a helper tests opt into; add a small config-override helper
(`with_config(overrides, fn)` that calls `config.setup`/`config.reset`); add a
"no setup" spec exercising parse→write. Add round-trip property tests: for the
fixture boards in `tests/fixtures/boards.lua`, `parse(write(parse(x)))` must
equal `parse(x)`.

---

## Suggested execution order

| Phase | Tasks | Notes |
|-------|-------|-------|
| 1 | Task 1, Task 10 | Foundation: effective config + testability. Strong model for 1, mid-tier for 10. |
| 2 | Task 3, Task 4, Task 5 | Round-trip integrity. Strong model for 3; mid-tier for 4 and 5. |
| 3 | Task 2, Task 6, Task 7, Task 8 | Localised fixes. Mid-tier for 2; cheap/fast agents for 6, 7, 8 (specs above are self-contained). |
| 4 | Task 9 | Cheap/fast agent, single batch PR. |

Each task should land with regression tests (`busted` suite) and keep the full
suite green. Tasks 4-9 are independent of one another and can run in parallel
worktrees.
