# Testing Improvements Task List

## Phase 1: Critical Foundation

- Setup up Docker for testing. Make sure it's runnable via Podman.
- Setup Github workflows/actions for testing, integrating the Docker setup.
- Adopt TAP (Test Anything Protocol) output format for test results


## Phase 2: CI/CD and Documentation

- Add performance regression tests with timing bounds
- Create `SPEC.md` behaviour specification document
- Document input/output contract in specification

### Scope note: what "the CLI" is in this repo

The engine has **no executable and no argv parsing**. `grep -rn '\barg\[\|os.exit' lua/` returns
nothing. The CLI surface is entirely a Lua module API:

- `lua/kanban-md/cli.lua` (46 lines) — `require('kanban-md.cli').setup(user_config)`, exporting
  `Board`/`Column`/`Card`/`Triggerable`/`triggers`/`config` and injecting `CLIAdapter`.
- `lua/kanban-md/adapters/cli.lua` (289 lines) — the `CLIAdapter` implementation of the adapter
  interface (notify, buffer read/write incl. file + stdin + stdout, cursor, prompts, virtual-text
  no-ops).
- `lua/kanban-md/adapters/interface.lua` (202 lines) — the contract itself, with `Adapter.validate()`.


---

## Current state (assessed 2026-09-16)

Baseline, measured on the working tree at `b1f7922`:

| Suite | Spec files | Assertions | Time |
|---|---|---|---|
| `tests/unit` | 30 | 544 | 1.02s |
| `tests/integration` | 16 | 201 | 1.08s |
| `tests/e2e` | 2 | 20 | 0.05s |
| **Total** | **48** | **765** | **~2.3s** |

`busted` is green. It was **not** reliably green under `busted --shuffle`: there was an
order-dependent flake failing in roughly half of runs (see *Order dependence*, below). That is now
fixed, and 12 consecutive `--shuffle` runs pass. The singleton-state risk that produced it is
structural, though — `Board`/`Column`/`Card`/`CLIAdapter`/`adapter_registry` are all module
singletons shared across the whole run — so **`--shuffle` belongs in CI** to stop the next one
going unnoticed.

What is genuinely good and should not be disturbed:

- `tests/polyfills/vim.lua` no longer calls `cli.setup()` implicitly, so the "pure library, no
  `setup()`" path is actually exercised. `tests/helpers/setup.lua` makes the setup-dependent path
  opt-in and idempotent, with `with_config()` restoring config even when the body errors.
- `tests/unit/roundtrip_fixtures_spec.lua` drives every fixture builder through
  `parse(write(parse(x)))`, which is the right shape for a parser/writer library.
- The `.busted` named suites (`unit`/`integration`/`e2e`) and the Makefile targets over them work.

Everything below is what is missing, wrong or stale.

---

## Phase 0: Bugs the test suite is currently hiding

These are defects found while assessing coverage. They are listed first because they are the
evidence that the coverage gaps in Phase 3 are real rather than theoretical.

- **`lua/kanban-md/extras/cursor_triggers.lua` does not exist — the dependency runs the wrong way.**
  `board.lua:584` does `require('kanban-md.extras.cursor_triggers')` when
  `enable_cursor_positioning` is truthy, but that module ships only in the Neovim plugin
  (`../kanban-md.nvim/lua/kanban-md/extras/cursor_triggers.lua`). So engine code hard-requires a
  module the engine does not ship: setting `enable_cursor_positioning = true` (a documented config
  key, `config.lua:266`) and calling `board:auto_register_triggers()` is a hard `module not found`
  error for any non-Neovim consumer. **Zero of the 765 tests enable this flag**, which is why it
  has survived.

  **Resolution: invert the dependency, don't port the module.** `cursor_triggers.lua` is 23 lines
  that set `card.properties._cursor_target = true` — but the feature is the plugin's, and the
  plugin already calls `setup()`. It should register its own `on_entry` trigger through the public
  trigger API, which is exactly the "optional features via triggers, no special core mechanism"
  pattern `CLAUDE.md` describes. The engine then deletes the `board.lua:581-587` branch, and either
  drops `enable_cursor_positioning` or documents it as plugin-owned. Add an engine test asserting
  the branch is gone — i.e. that no config value can make `auto_register_triggers()` require a
  module outside `lua/`.
- **`lua/kanban-md/templates.lua` is empty** (0 lines) and has no spec. It is unimplemented and should be marked as such.
- **`CLIAdapter:notify()` prefixes are mojibake.** `adapters/cli.lua:31-35` has
  `prefix = "9<0x0f> "`, `prefix = "<U+FFFD><0x0f> "`, `prefix = "L"` — corrupted emoji bytes, which
  is why the test run prints `9  Wrote 9 lines to ...` and `L Failed to read file: ...`. The
  existing `notify()` tests assert only that the call does not error; **none asserts the emitted
  string**, so the corruption is invisible to the suite. Fix the bytes and add prefix assertions.
- **Trigger method naming is inconsistent with the documentation.** `CLAUDE.md` describes an
  `on_entering` trigger point, but `lua/` uses `register_on_entry` exclusively (6 call sites,
  0 for `register_on_entering`). Likewise `CLAUDE.md` refers to `parser_mixin.lua`, which does not
  exist — the module is `lua/kanban-md/parser.lua`. The `CLAUDE.md` needs updating to match the 
	actual triggers.

## Phase 1 (revised): Critical foundation

Keep the three original items, with these specifics:

- **Docker/Podman test image.** Pin the Lua version explicitly. The repo currently hard-codes
  `/opt/local/bin/lua` (MacPorts) in `examples/test_cli.sh` and `CLAUDE.md`, which is a
  single-developer-machine assumption; the container is the chance to remove it. Verify the suite
  under at least Lua 5.1/LuaJIT *and* 5.3 — nothing currently proves the engine is portable across
  them, and a Neovim consumer runs LuaJIT while the local dev runs 5.3. Also, use an Alpine image,
	I want to keep the containers as light as possible.
- **GitHub Actions.** Must run `busted`, the linter, and the coverage gate (below). Include a
  matrix over the Lua versions above.
- **TAP output.** `busted --output=TAP` already exists; the work is wiring it into CI and into
  `tests/run_tests_standalone.sh`.

Add to Phase 1:

- **Add `luacov`.** There is no coverage tooling at all (no `.luacov`, no `luacov` in `.busted`).
  Without it, every claim in Phase 3 is guesswork from `grep`. Land coverage measurement *before*
  writing new tests, so the gaps can be ranked by real line coverage rather than by file name.
- **Add `luacheck`** with a `.luacheckrc` that declares `vim` and `_TEST` as globals. There is no
  linting, and the `_G.vim` / `_G._TEST` pattern is exactly the sort of thing that rots silently.
- **Add a rockspec.** There is none, so `busted`, `luacov`, `luacheck` and the Lua version are all
  undeclared dependencies discovered by trial and error. `make check-deps` only checks `busted`.
- **Fix `tests/run_tests_standalone.sh`.** It is an 8-byte file containing a blank line and
  `busted`, with no shebang and no `set -e`. It works only because it is invoked with the executable
  bit and falls through to the default shell.
- **Delete the Neovim/plenary runner leftovers.** `tests/run_tests.sh` and `tests/run_tests.lua`
  clone and drive `plenary.nvim` to run `#neovim-only` specs. This is the platform-agnostic engine;
  those specs live in the consuming projects now (`tests/README.md` says so), and no `*_spec.lua`
  in this repo carries the `#neovim-only` tag. The runner is dead code that will confuse CI setup.
- **Quarantine or promote `tests/manual-tests/`.** Ten files (`test_complexity.lua`,
  `diagnose_cursor.lua`, `test_commands.lua`, …) that no runner executes and no CI will catch when
  they break. Either convert the ones with assertions into specs or move them out of `tests/`.

## Phase 2 (revised): CI/CD and documentation

- Add performance regression tests with timing bounds. *(Note: the whole suite is 2.3s, so bounds
  must be per-operation — e.g. parse/write of a large board — not wall-clock on the suite, which
  will be dominated by CI runner noise.)*
- Create `SPEC.md` behaviour specification document.
- Document the input/output contract: the `Adapter` interface in `adapters/interface.lua` is the
  real contract — the eleven methods `Adapter.validate()` checks, plus the `opts` shapes
  (`{start, _end, file, stdin}` for `read_buffer`, `{bufnr, start, _end, file, stdout}` for
  `write_buffer`) and their 0-indexed/1-indexed conversion rules.
- Document the `notify()` severity contract — the `"info" | "warn" | "error"` levels, that output
  goes to **stderr** while data goes to **stdout**, and the prefix for each level (once Phase 0
  has fixed the bytes).
- Document the markdown syntax contract (H1 title, H6 columns, `<!-- kanban:config -->`,
  `<!-- column:config -->`, card property comments, `###### __ARCHIVE__` and unknown
  `__SPECIAL__` sections) as the parser/writer's actual input/output format.
- Document the config-resolution layering: hard defaults → `config.setup()` → board-file
  `<!-- kanban:config -->` → column-level config, and which keys are `[BOARD-OVERRIDABLE]`.
  `effective_config_spec.lua` and `column_config_layers_spec.lua` test this but nothing states it.
- Refresh `tests/README.md`. It claims "675 tests", "36 standalone test files", "Unit tests: 19
  files (456 tests)" and embeds a hand-maintained `tree` listing — all stale against the measured
  47 files / 762 tests. It also opens with "a dual-framework approach: **Busted** for standalone
  Lua tests", a sentence left half-edited when the Neovim half was removed. Drop them, they are stale.

## Phase 3: Coverage gaps

Modules with **no spec requiring them at all**:

| Module | Lines | Note |
|---|---|---|
| `adapters/interface.lua` | 202 | The contract itself — `Adapter.validate()` and `Adapter.new()` are never tested directly. Highest priority: this is what any future adapter is checked against. |
| ~~`virtual_text.lua`~~ | ~~267~~ | **Done** — `tests/unit/virtual_text_spec.lua` pulled in from the consuming project (3 assertions). Still thin: covers WIP warnings, lead-time display and the unsupported-adapter path only. Untested: cycle time, blocked-time breakdown, `format_time` singularisation, `cycle_time_unit` variants, archive cards, and `show_stats_virtual_text == false`. |
| `core/setup.lua` | — | Only reached indirectly via `helpers/setup.lua`. |
| `extras/workflow_triggers.lua` | — | SLA / business hours / approvals. |
| `extras/capacity_triggers.lua` | — | Referenced from `board.lua` when `column.config.capacity.max_points` is set; that branch is untested. |
| `extras/subtasks_triggers.lua` | — | The *behaviour* is covered by `subtask_validation_spec.lua`, but the module is never unit-tested. |
| `helpers/ulid.lua` | — | ID generation, including monotonicity and collision behaviour. |
| `validation_result.lua` | 185 | Factory methods and state transitions. |
| `templates.lua` | 0 | Empty — see Phase 0. |
| `version.lua` | 1 | Trivial, but worth an assertion if a rockspec is added. |

Thinly covered (one spec file each): `adapter_registry.lua`, `column_type_resolver.lua`,
`extras/id_triggers.lua`, `utils/string.lua`, `utils/table.lua`, `writer_mixin.lua`.

### CLI API gaps specifically

The CLI adapter is the best-tested part of the CLI surface (`tests/unit/adapters/cli_adapter_spec.lua`
has ~50 assertions across notify/read/write/cursor/prompts). What it misses:

- **`read_buffer` with `opts.stdin`** — the stdin branch (`adapters/cli.lua`, `elseif opts.stdin`)
  has no test. For a CLI this is a primary input path.
- **`write_buffer` with `opts.stdout`** — `writer_cli_adapter_spec.lua` has a test named
  "should support writing to stdout (simulated)" that does not exercise the real branch.
- **`notify()` output content** — asserted only for "does not error", never for prefix or level
  routing. This is what let the mojibake through.
- **`cli.lua` itself** — the guard `error("Use require('kanban-md').setup() in Neovim, ...")` when
  `vim ~= nil and not _G._TEST` is never tested, and neither is `setup()` with user config
  overrides reaching `core_setup.setup()`.
- **`Adapter.validate()` rejection** — no test constructs a deliberately incomplete adapter and
  asserts it is rejected with a useful message.
- **Error paths generally** — unreadable file, unwritable path (one test exists), malformed
  markdown, empty input, a board file that is not a board at all.

### Hygiene items

- **`tests/integration/timestamp_on_initial_placement_spec.lua` prints debug output** on every run
  (`After initial placement in Todo: todo=...`). Remove it.
- **Fixture warnings are printed as test noise** — "Warning: Column 'Test' of type 'multi_req'
  requires wip_limit but none is set" etc. appear mid-run. Capture and assert them instead.
- **`os.tmpname()` used in 5 spec files without `after_each` cleanup guarantees.** Cleanup is
  inline `os.remove()` calls that are skipped when an assertion fails earlier in the test. Move to
  `after_each`, or a temp-dir helper in `tests/helpers/`.
- **`make clean` runs `rm -rf /tmp/lua_*`** — a glob over shared system temp that could hit another
  process's files. Scope temp files to a per-run directory instead.
- **`examples/test_cli.sh` mutates a tracked file.** Running it rewrites
  `examples/sample_board_modified.md`, leaving the working tree dirty. It is also the only thing
  exercising `examples/cli_example.lua`, and CI will not run it. Make it write to a temp path and
  add it to CI as a smoke test. `examples/sample_board_modified.md` has been untracked. If testing
	creates it, have it cleaned up afterwards.
- **Time-dependent assertions.** Nine spec files call `os.time()`; with second resolution, all
  timestamps in a run collide (visible in the debug output above:
  `todo=1789535789, in_progress=1789535789, done=1789535789`). Any test asserting *ordering* or
  *duration* between column transitions is passing by coincidence. Inject a clock so lead/cycle/
  blocked-time maths can be tested with real deltas.
- **Four spec files do not `require('polyfills.vim')`** and work only because an earlier file in
  the run set `_G.vim`. They will fail if run alone. `busted --shuffle` does not catch this because
  it does not isolate files. A `make test-each-file` target that runs every spec in its own
  `busted` process would.

### Order dependence (one found and fixed)

`tests/unit/adapters/cli_adapter_spec.lua` failed intermittently under `--shuffle` — about half of
runs — with `CLIAdapter initialisation should initialise with default cursor position` getting
`9999` instead of `1`. `CLIAdapter` is a module singleton; line 422 (`should allow arbitrary
cursor positions`) leaves `_cursor = {9999, 9999}`, and the `before_each` that resets it is scoped
*inside* the `cursor operations` block, so it does not protect the `initialisation` block that
asserts the as-loaded value. Fixed by snapshotting the cursor and buffer-line count at require
time, before any test body runs, so the initialisation assertions describe real initial state
regardless of execution order.

Worth auditing for the same shape elsewhere: any test asserting a *default* or *initial* value on
a singleton (`CLIAdapter._buffer_lines`, `CLIAdapter._buffer_filename`, `adapter_registry._adapter`,
the class-level triggers on `Board`/`Column`/`Card`, `config` defaults) is vulnerable to it.
- **The four `pending()` round-trip defects** in `roundtrip_fixtures_spec.lua` reference
  PLAN-config-fixes Tasks 3–6, and those tasks appear to have landed (commits `5cd696f`, `99d30fe`,
  `378599b`, `aaf9d06`). The `pending()` calls should be removed so they become live regression
  tests — or, if they still fail, the fixes are incomplete.

## Phase 4: Known risk — divergence from the consuming project

`meta-project-tests` symlinks to `../kanban-md/tests`, the suite of the project that consumes this
engine. Comparing the two:

- **39 of the 41 shared spec files are byte-identical.** The consuming project holds a verbatim copy
  of the engine's test suite.
- **2 files have diverged, and one now asserts contradictory behaviour.**
  `unit/writer_mixin_spec.lua` in the consumer expects `<!-- kanban:config, wip_limit: 5 -->`
  (comma-separated); the engine changed this to `<!-- kanban:config wip_limit: 5 -->` in commit
  `2141725`, this (the engine's) is the correct behaviour. 
	**One of the two suites must now be failing**, and whichever passes is describing
  behaviour the other project does not have. `integration/content_preservation_spec.lua` has
  diverged the same way over the Task 3 `markdown_config` change.
- **The engine is ahead by 6 spec files** the consumer does not have: `column_config_layers`,
  `effective_config`, `no_setup`, `persist_card_ids_e2e`, `roundtrip_fixtures`, `task9_regressions`
  — i.e. all the recent config/round-trip fix work.
- **The consumer has 4 the engine does not**, of which two are relevant here:
  - ~~`unit/virtual_text_spec.lua`~~ — **pulled in**, now `tests/unit/virtual_text_spec.lua`. It
    tests `lua/kanban-md/virtual_text.lua`, which lives in this engine; it was tagged
    `#neovim-only` but uses a mock adapter and runs fine in standalone Lua. Adapted on the way in:
    added `require('polyfills.vim')`, dropped the misleading `#neovim-only` tag, reindented to the
    engine's 2-space style, and — necessarily — made it save and restore
    `adapter_registry._adapter`. The original registers a mock at file load and its last test
    swaps in a second mock that is **never** removed, so as written it would have left every
    subsequent spec file in the run talking to a mock adapter.
  - `cursor_positioning_spec.lua` — would catch the missing `cursor_triggers.lua` in Phase 0.
    See Phase 5, which supersedes this line: the same spec also lives in the Neovim plugin, and
    most of what it tests is engine behaviour.
  - (`writer_neovim_adapter_spec.lua` and `backend/services/board_service_persist_ids_spec.lua`
    are genuinely consumer-side: this engine has no `adapters/neovim.lua` and no `backend/`.)

Recorded as a risk, per your call — the de-duplication strategy is a separate decision. The
immediate, strategy-independent actions are: confirm which of the two `writer_mixin` expectations
is correct and fix the loser, and ~~pull `virtual_text_spec.lua` into this repo~~ (done).

My answer - de-duplication will happen, but this project will be the source of truth for the engine.
Other projects may added tests for what they extend, but anything this engine does should be tested here.

---

## Phase 5: The Neovim plugin's tests (`neovim-plugin-tests` → `../kanban-md.nvim/tests`)

The plugin holds only three specs — `unit/cursor_positioning_spec.lua`,
`integration/virtual_text_spec.lua`, `integration/writer_neovim_adapter_spec.lua` — plus
`test_helper.lua` and a plenary runner. `writer_neovim_adapter_spec.lua` is correctly placed
(`adapters/neovim.lua` exists only there). `virtual_text_spec.lua` is now also covered here.
`cursor_positioning_spec.lua` is the interesting one.

**On placement — agreed for the Neovim part, but most of that spec is not the Neovim part.**
`cursor_triggers.lua` is 23 lines of pure Lua with no Neovim API calls; it sets a property flag.
The genuinely Neovim-only half — acting on `_cursor_target` to move the cursor in a buffer — lives
in the plugin's `commands.lua` and **is not tested by this spec at all**. Of the 11 tests in
`cursor_positioning_spec.lua`, what is actually being asserted is:

| What the test asserts | Whose behaviour |
|---|---|
| `auto_register_triggers()` registers the trigger on every column | engine (`board.lua:581-587`) |
| board-level config overrides plugin-level config, both directions | engine (`Board:get_config_value`) |
| `_cursor_target` is not written to markdown | engine (`writer_mixin.lua:123`) |
| re-parsing does not resurrect `_cursor_target`; `line_number` is set | engine (parser/writer) |
| the cursor actually moves | **not tested anywhere** |

By the source-of-truth rule stated above — "anything this engine does should be tested here" —
those four rows belong in this repo. The point is not to move the cursor spec across; it is that
the engine is currently borrowing a downstream `#neovim-only` spec as proxy coverage for its own
contracts. Two of them have **no engine test at all**:

- **`writer_mixin.lua:123`: properties matching `^_` are ephemeral and never serialised.** This is
  a general engine contract — it applies to any `_foo`, not just `_cursor_target` — and
  `grep -rn '_cursor_target\|underscore' tests/` returns nothing. Needs an engine spec written in
  its own terms: set `_scratch`, `_internal`, write, assert absent; confirm a normal property
  alongside it survives; confirm a round trip does not reintroduce it.
- **A board-level `true` overriding a plugin-level `false` for trigger *registration*.**
  `effective_config_spec.lua` covers `get_config_value` for `timestamp_format`,
  `property_separator`, `auto_timestamp` etc., but not the case where the board config flips a
  default-off boolean *on* and a trigger must consequently be registered. That is the general
  mechanism `enable_cursor_positioning` happens to exercise.

So: **keep `cursor_positioning_spec.lua` in the plugin** (agreed), **fix `test_helper.lua`**, and
**add the two engine specs above** expressed generically, so the engine stops depending on a
Neovim-only spec in another repo to notice if it breaks its own contracts.

---

## Open questions

1. ~~`enable_cursor_positioning` — port `cursor_triggers.lua` in, or remove the feature?~~
   **Answered:** the triggers are Neovim-only and stay in `kanban-md.nvim`. Remaining decision is
   narrower — when the engine deletes the `board.lua:581-587` branch, does `enable_cursor_positioning`
   stay in `config.lua` as a plugin-owned key the engine merely passes through, or come out
   entirely? See Phase 5. Answer: it comes out entirely.
2. Which Lua versions must the engine support? This determines the CI matrix and whether the
   LuaJIT/5.1 compatibility risk is real. Answer: Both 5.1 and Luajit, as Neovim supports both.
3. Is there a coverage percentage worth gating CI on, or should coverage be reported without a
   threshold to begin with? Answer: begin without a coverage percentage.
