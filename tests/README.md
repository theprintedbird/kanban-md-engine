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
| `tests/fixtures/` | `boards.lua` builders, plus `.md` boards under `fixtures/boards/` |
| `tests/helpers/` | `mocks.lua` (mock triggers and adapters) and `setup.lua` (opt-in `cli.setup()`) |
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

`os.time()` has one-second resolution, so every timestamp in a fast-running spec collides. A spec
asserting *ordering* or *duration* between transitions must inject the times it needs rather than
letting the clock supply them.

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
