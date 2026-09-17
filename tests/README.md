# Test Suite

Every test here is a [Busted](https://lunarmodules.github.io/busted/) spec running under plain
Lua. There is no Neovim in the loop: the engine is platform-agnostic, and specs that need a host
use the CLI adapter or a mock. Specs that genuinely require Neovim live in `kanban-md.nvim`.

`SPEC.md` in the repository root is the behaviour specification these tests exist to hold the
engine to. When a spec and `SPEC.md` disagree, one of them is wrong — decide which before
changing either.

## Layout

| Path | What lives there |
|---|---|
| `tests/unit/` | One module, one spec, minimal collaborators |
| `tests/integration/` | Several modules together: parse → mutate → write, triggers, validation |
| `tests/e2e/` | Whole-workflow scenarios over realistic boards |
| `tests/fixtures/` | `boards.lua` builders, `large_board.lua` (generated boards of any size), plus `.md` boards under `fixtures/boards/` |
| `tests/helpers/` | `mocks.lua` (mock triggers and adapters), `setup.lua` (opt-in `cli.setup()`) and `perf.lua` (timing and calibration) |
| `tests/polyfills/` | `vim.lua`, the pure-Lua stand-ins for the `vim.*` utilities the engine calls |
| `tests/run_tests_standalone.sh` | The suite runner, with optional TAP output |

The directories are the suites: `.busted` defines `unit`, `integration` and `e2e` over exactly
these paths, which is what `make test-unit` and friends select.

File and assertion counts are deliberately not recorded here. `busted` prints the current numbers,
and a hand-maintained tally is a line of documentation that is wrong within a fortnight.

## Running

```bash
make test               # the whole suite
make test-unit          # one suite
make test-integration
make test-e2e

make test-file FILE=tests/unit/parser_content_blocks_spec.lua

make test-shuffle       # random order; SEED=<n> reproduces a given run
make test-tap           # TAP output; TAP_FILE=<path> also saves it
make test-perf          # the performance specs alone, uninstrumented
make coverage           # luacov, summary printed, no threshold
make lint               # luacheck over lua/ and tests/
```

Or drive `busted` directly — `.busted` supplies the module paths, so no flags are needed:

```bash
busted                          # everything
busted tests/unit               # one directory
busted --run=unit               # one named suite
busted --filter="Complete Workflow"
busted --list
busted --shuffle --seed=1234    # reproduce a shuffled run
```

**Requirements:** Lua 5.1+ or LuaJIT, and the rocks declared as `test_dependencies` in
`kanban-md-engine-scm-1.rockspec` (`busted`, `luacov`, `luacheck`). `luarocks test --prepare`
installs them; `make check-deps` checks for `busted`.

### In a container

`docker/Dockerfile.alpine` builds a small image with the toolchain already in it. The Makefile
prefers Podman and falls back to Docker (`CONTAINER_ENGINE=docker` to force one):

```bash
make test-container                   # default Lua version
make test-container LUA_VERSION=5.1   # 5.1, 5.3, 5.4 or jit
make lint-container                   # luacheck in the image
make ci-local                         # run the GitHub workflows locally with act
```

## Writing a spec

Every spec file **must** start with the polyfill require. Do not rely on another file in the run
having loaded it — that works under `busted` and breaks the moment the file is run on its own:

```lua
require('polyfills.vim')

describe("MyModule", function()
  local MyModule

  before_each(function()
    MyModule = require('kanban-md.my_module')
  end)

  it("does something", function()
    assert.are.equal("expected", MyModule.do_thing())
  end)
end)
```

The polyfill provides `vim.deepcopy`, `vim.tbl_contains`, `vim.tbl_count`, `vim.tbl_extend`,
`vim.fn.getcwd` and `_G._TEST`. It does **not** call `setup()`, so the default path a spec
exercises is the pure-library one: no adapter registered, no ID triggers, defaults in force. That
is deliberate — it is the path a consumer gets when they only want to parse and write.

### When a spec needs setup

`tests/helpers/setup.lua` makes the configured path opt-in:

```lua
local test_setup = require('helpers.setup')
test_setup.setup()                       -- CLI adapter + ULID id triggers + config
test_setup.setup({ persist_card_ids = true })
```

It is idempotent, so calling it from several spec files in one run is safe.

To change configuration for part of a spec, use `with_config`, which restores the config even when
the body raises:

```lua
test_setup.with_config({ timestamp_format = "iso" }, function()
  -- assertions under the override
end)
```

### Singletons: the rule that bites

`Board`, `Column`, `Card`, `CLIAdapter`, `adapter_registry` and `config` are module singletons
shared by every spec in a run. Two consequences:

- A spec that mutates one **must** restore it, in `after_each` rather than inline, so a failing
  assertion cannot skip the cleanup.
- A spec asserting a *default* or *initial* value is asserting something another file may already
  have changed. Snapshot the value at require time, before any test body runs, or assert against a
  freshly reset object.

`make test-shuffle` is the cheap way to catch the first shape. It does not catch the second —
`busted` shuffles within a process, so a file that only passes because an earlier file loaded
something still passes. Running a single file on its own is the check for that.

### Timestamps and completion

Completion is column-based, and column timestamps are set by triggers. A spec **must not** write
`card.properties.done = os.time()` by hand: call `board:auto_register_triggers()` and move the
card. A hand-set timestamp asserts a state the engine would never produce.

`os.time()` has one-second resolution, so every timestamp in a fast-running spec collides: three
moves in a millisecond give three identical timestamps, and any assertion about their order or the
gaps between them passes by coincidence. Every timestamp the engine writes comes from
`kanban-md.helpers.clock`, so a spec asserting *ordering* or *duration* freezes that clock and
advances it by hand:

```lua
local test_clock = require('helpers.clock')
local clock

before_each(function() clock = test_clock.install() end)
after_each(function() clock.restore() end)

it("measures a two-day lead time", function()
  backlog:add_card(card)
  clock.advance(2 * test_clock.DAY)
  board:move_card(card, backlog, done)

  assert.equals(2 * test_clock.DAY, stats._private.calculate_lead_time(card.properties, board).duration)
end)
```

`install()` freezes the clock at `test_clock.EPOCH` (2024-01-01T00:00:00Z); `MINUTE`, `HOUR` and
`DAY` are there so durations read as durations. `tests/integration/lead_cycle_time_spec.lua` is the
worked example.

### Temporary files

Create them under a path the spec owns and remove them in `after_each`, never in the body:

```lua
local tmpfile

after_each(function()
  if tmpfile then os.remove(tmpfile) end
  tmpfile = nil
end)
```

Do not use `git stash`, `git reset` or any other git command to save or restore state in a test.
Copy the file instead.

## Performance regression tests

`tests/integration/performance_spec.lua` bounds individual operations — parse, write, stats,
validation, lookup, move — over generated boards of 240 and 1440 cards. There is deliberately no
bound on how long the suite takes: it runs in a few seconds, so a wall-clock bound over it would be
measuring the CI runner rather than the engine.

Two kinds of assertion, because they catch different things:

- A **budget** says the operation cost no more than N milliseconds on the 1440-card board. It
  catches "this got several times more expensive".
- A **scaling ratio** says six times the cards cost no more than nine times the time. It catches a
  change of algorithmic shape — a budget loose enough not to flake will absorb a quadratic at these
  sizes, and in testing an injected quadratic slipped under the parse budget while the ratio failed
  at 11x.

Only `parse`, `write` and `calculate_stats` make a scaling claim. `validate`, `find_task` and
`move_card` cost tenths of a millisecond even on the large board, where memory latency rather than
the work sets the price: the small board stays in cache and the large one does not. That reads as
6.1x–7.7x under Lua 5.3 and 12.8x–15.2x under LuaJIT with no change to the engine, which is a wider
spread than a quadratic would produce — so those three are left to their budgets.

Every operation is measured at both sizes once, in `setup()`; the assertions read those
measurements rather than re-timing anything.

`tests/helpers/perf.lua` is what keeps the bounds from flaking:

- Timings are **CPU time** (`os.clock`), not wall clock, so a runner descheduled while another job
  hogs the box does not fail the build.
- Every figure is the **best of N runs**. Noise only ever makes a run slower, so the minimum is the
  closest estimate of the real cost and much steadier than an average.
- `perf.per_call()` **sizes its own batch**: it runs the operation in a growing batch until one
  batch takes at least 5ms, then divides. Operations costing microseconds cannot be timed one at a
  time — they are the same size as the clock's resolution and a single GC step. A *fixed* batch
  size does not work either: 50 calls of `find_task()` is a healthy 15ms sample under Lua 5.3 and
  an unmeasurable 0.2ms under LuaJIT. The sizing runs double as JIT warm-up.
- Budgets are milliseconds measured on a reference machine, **scaled by a calibration factor**
  taken from a fixed pure-Lua workload run in-process. A machine half the speed gets twice the
  budget, which is what lets one set of figures hold across Lua 5.1, 5.3, 5.4 and LuaJIT.
- Headroom is roughly 3x. What fails here is an operation that got several times more expensive,
  not a slow afternoon. Scaling ratios need no calibration at all: a ratio of two timings taken in
  the same process is immune to how fast the machine is.

The specs **skip themselves under luacov**, whose per-line hook costs the calibration workload
about 10x and board parsing about 40x — unevenly, so calibration cannot correct for it. `make
coverage` and CI's coverage run therefore report them as pending; `make test-perf` and a separate
uninstrumented CI step are what actually measure them.

Two environment variables:

| Variable | Effect |
|---|---|
| `KANBAN_SKIP_PERF=1` | Skip the performance specs entirely |
| `KANBAN_PERF_TOLERANCE=n` | Multiply every budget by `n` on a box known to be noisy (CI uses `2`) |

If a budget fails, read the failure message before touching the number: it prints what was
measured, what was allowed, and the reference/calibration/tolerance the budget was built from.
Raise a budget only once you know what got slower and have decided it is acceptable.

## Assertions

```lua
assert.are.equal(expected, actual)   -- identity / primitive equality
assert.are.same(expected, actual)    -- deep equality (tables)

assert.is_true(value)                -- boolean true, not merely truthy
assert.is_false(value)
assert.truthy(value)
assert.falsy(value)

assert.is_nil(value)
assert.is_not_nil(value)

assert.has_error(fn, pattern)
assert.has_no_error(fn)

assert.matches(pattern, str)
```

Busted syntax, not Plenary syntax: `assert.are.equal`, not `assert.equals`.

## Configuration files

| File | Purpose |
|---|---|
| `.busted` | Module paths, the `_spec.lua` pattern, and the named suites |
| `.luacov` | Coverage over `lua/kanban-md` only; tests and rocks excluded |
| `.luacheckrc` | `std = "max"`, `vim`/`_TEST` declared, muted families each given a reason |
| `kanban-md-engine-scm-1.rockspec` | The single declaration of the dev toolchain |

## CI

`.github/workflows/ci.yml` runs on push, pull request and manual dispatch:

- **Luacheck** over `lua` and `tests`. A clean run is the baseline.
- **Tests** across a matrix of Lua 5.1, 5.3, 5.4 and LuaJIT — 5.1 and LuaJIT because that is what
  Neovim embeds, the rest for standalone use. Each run is shuffled with an echoed seed, so a red
  run can be reproduced with `busted --shuffle --seed=<seed>`, and emits TAP, kept as an artifact.
- **Performance bounds** on every matrix version, in a separate uninstrumented run (the main run
  is under luacov, where the specs skip themselves) with `KANBAN_PERF_TOLERANCE=2` for runner noise.
- **Coverage** reported once, on 5.4. There is no threshold: the number is there to be read, not
  to fail the build.

`make ci-local` runs the same workflows locally through [act](https://github.com/nektos/act).

## Troubleshooting

| Symptom | Cause |
|---|---|
| `module 'kanban-md.…' not found` | Running `busted` from outside the repository root, so `.busted`'s `lpath` does not apply |
| `attempt to index a nil value (global 'vim')` | Missing `require('polyfills.vim')` at the top of the spec |
| Passes in the suite, fails alone | The spec depends on another file's side effects — usually the polyfill or `helpers.setup` |
| Passes alone, fails under `--shuffle` | A singleton left dirty by another spec; see above |
| `assert.equals` is nil | Plenary syntax; use `assert.are.equal` |
| A performance budget fails on an unchanged engine | The machine is noisier or slower than calibration can account for; rerun, then raise `KANBAN_PERF_TOLERANCE` |
