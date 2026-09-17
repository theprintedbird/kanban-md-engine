-- tests/unit/update_version_script_spec.lua
-- Tests for scripts/update-version.lua, the script that sets the engine
-- version in every file that records it.
--
-- The script is loaded with dofile rather than require: it lives outside the
-- package path (it is a build tool, not part of the engine) and returns its
-- module table when loaded rather than run. Every case works on a throwaway
-- copy of the two real files under a temporary root, so nothing here can bump
-- the version of the checkout it is running in.
local temp = require('helpers.tempfiles')

local script = dofile('scripts/update-version.lua')

describe("update-version script", function()
  local root

  after_each(function()
    -- The tree below `root` is nested, and tempfiles' cleanup only unlinks the
    -- paths it handed out; remove the directory itself so the run directory is
    -- empty enough for it to go too.
    if root then
      os.execute(string.format("rm -rf '%s'", root))
      root = nil
    end
    temp.cleanup()
  end)

  --- A temporary tree holding a version.lua and a SPEC.md at `version`.
  local function make_root(version)
    root = temp.path("repo")
    os.execute(string.format("mkdir -p '%s/lua/kanban-md'", root))

    local module = assert(io.open(root .. "/lua/kanban-md/version.lua", "w"))
    module:write(string.format('return "%s"\n', version))
    module:close()

    local spec = assert(io.open(root .. "/SPEC.md", "w"))
    spec:write("# kanban-md-engine — behaviour specification\n\n")
    spec:write(string.format(
      "Status: living document. Version: tracks `lua/kanban-md/version.lua` (currently `%s`).\n",
      version
    ))
    spec:write("\nProse that mentions no version at all.\n")
    spec:close()

    return root
  end

  local function read(path)
    local handle = assert(io.open(root .. "/" .. path, "r"))
    local contents = handle:read("*a")
    handle:close()
    return contents
  end

  describe("is_valid_version", function()
    it("accepts a bare semantic version", function()
      assert.is_true(script.is_valid_version("0.1.0"))
      assert.is_true(script.is_valid_version("10.20.30"))
    end)

    it("accepts prerelease and build suffixes", function()
      assert.is_true(script.is_valid_version("1.0.0-rc.1"))
      assert.is_true(script.is_valid_version("1.0.0+build.5"))
    end)

    it("rejects anything that is not three numbers", function()
      assert.is_false(script.is_valid_version("1.2"))
      assert.is_false(script.is_valid_version("v1.2.3"))
      assert.is_false(script.is_valid_version("1.2.3 "))
      assert.is_false(script.is_valid_version(""))
      assert.is_false(script.is_valid_version(nil))
    end)
  end)

  it("rewrites every target", function()
    make_root("0.1.0")

    local changes = assert(script.update({ version = "0.2.0", root = root }))

    assert.equal(2, #changes)
    assert.equal('return "0.2.0"\n', read("lua/kanban-md/version.lua"))
    assert.is_truthy(read("SPEC.md"):find("(currently `0.2.0`)", 1, true))
  end)

  it("leaves the surrounding text alone", function()
    make_root("0.1.0")

    script.update({ version = "0.2.0", root = root })

    local spec = read("SPEC.md")
    assert.is_truthy(spec:find("# kanban-md-engine", 1, true))
    assert.is_truthy(spec:find("Prose that mentions no version at all.", 1, true))
    assert.is_falsy(spec:find("0.1.0", 1, true))
  end)

  it("reports the previous version of each target", function()
    make_root("0.1.0")

    local changes = script.update({ version = "1.0.0", root = root })

    for _, change in ipairs(changes) do
      assert.equal("0.1.0", change.previous)
      assert.equal("1.0.0", change.version)
    end
  end)

  it("writes nothing under dry_run", function()
    make_root("0.1.0")

    local changes = assert(script.update({ version = "0.2.0", root = root, dry_run = true }))

    assert.equal("0.1.0", changes[1].previous)
    assert.equal('return "0.1.0"\n', read("lua/kanban-md/version.lua"))
    assert.is_truthy(read("SPEC.md"):find("(currently `0.1.0`)", 1, true))
  end)

  it("is idempotent when the version is already set", function()
    make_root("0.2.0")

    local changes = assert(script.update({ version = "0.2.0", root = root }))

    assert.equal("0.2.0", changes[1].previous)
    assert.equal('return "0.2.0"\n', read("lua/kanban-md/version.lua"))
  end)

  it("refuses a version that is not semantic", function()
    make_root("0.1.0")

    local changes, err = script.update({ version = "banana", root = root })

    assert.is_nil(changes)
    assert.is_truthy(err:find("not a semantic version", 1, true))
    assert.equal('return "0.1.0"\n', read("lua/kanban-md/version.lua"))
  end)

  -- The whole point of the script is that it cannot silently miss a place, so
  -- a target it can no longer find has to fail the run -- and fail it before
  -- any other file has been written.
  it("fails without writing when a target's pattern no longer matches", function()
    make_root("0.1.0")

    local spec = assert(io.open(root .. "/SPEC.md", "w"))
    spec:write("Status: living document. No version here any more.\n")
    spec:close()

    local changes, err = script.update({ version = "0.2.0", root = root })

    assert.is_nil(changes)
    assert.is_truthy(err:find("SPEC.md", 1, true))
    assert.is_truthy(err:find("did not match", 1, true))
    assert.equal('return "0.1.0"\n', read("lua/kanban-md/version.lua"))
  end)

  it("fails when a target's file is missing", function()
    make_root("0.1.0")
    os.remove(root .. "/SPEC.md")

    local changes, err = script.update({ version = "0.2.0", root = root })

    assert.is_nil(changes)
    assert.is_truthy(err:find("SPEC.md", 1, true))
    assert.equal('return "0.1.0"\n', read("lua/kanban-md/version.lua"))
  end)

  it("fails when a target's pattern matches more than once", function()
    make_root("0.1.0")

    local spec = assert(io.open(root .. "/SPEC.md", "a"))
    spec:write("And again (currently `0.1.0`).\n")
    spec:close()

    local changes, err = script.update({ version = "0.2.0", root = root })

    assert.is_nil(changes)
    assert.is_truthy(err:find("more than once", 1, true))
    assert.equal('return "0.1.0"\n', read("lua/kanban-md/version.lua"))
  end)

  it("reads the current version from the module target", function()
    make_root("0.3.1")

    assert.equal("0.3.1", script.current_version(root))
  end)

  -- main() is what the Makefile target and a release actually run. It works
  -- against the real checkout, so every case here is either read-only or a
  -- dry run; its two streams are captured so the suite's output stays clean
  -- and so the stdout/stderr split can be asserted.
  describe("main", function()
    local out, err, streams

    before_each(function()
      out, err = {}, {}
      streams = {
        out = { write = function(_, text) table.insert(out, text) end },
        err = { write = function(_, text) table.insert(err, text) end },
      }
    end)

    local function stdout()
      return table.concat(out)
    end

    local function stderr()
      return table.concat(err)
    end

    it("prints the current version to stdout for --current", function()
      assert.equal(0, script.main({ "--current" }, streams))
      assert.equal(script.current_version(".") .. "\n", stdout())
      assert.equal("", stderr())
    end)

    it("prints usage to stderr and exits 2 with no arguments", function()
      assert.equal(2, script.main({}, streams))
      assert.equal("", stdout())
      assert.is_truthy(stderr():find("Usage:", 1, true))
      assert.is_truthy(stderr():find("Current version:", 1, true))
    end)

    it("lists every target file in its usage", function()
      script.main({ "--help" }, streams)

      for _, target in ipairs(script.targets) do
        assert.is_truthy(stderr():find(target.file, 1, true), target.file .. " missing from usage")
      end
    end)

    it("exits 2 for an unknown option", function()
      assert.equal(2, script.main({ "--bump" }, streams))
      assert.is_truthy(stderr():find("Unknown option: --bump", 1, true))
    end)

    it("exits 2 for a second version argument", function()
      assert.equal(2, script.main({ "0.2.0", "0.3.0" }, streams))
      assert.is_truthy(stderr():find("Unexpected argument: 0.3.0", 1, true))
    end)

    -- Invalid input is rejected before anything is written, so this cannot
    -- touch the checkout it is running in.
    it("exits 1 for a version that is not semantic", function()
      assert.equal(1, script.main({ "1.2" }, streams))
      assert.is_truthy(stderr():find("not a semantic version", 1, true))
    end)

    it("reports every target on a dry run against the checkout", function()
      assert.equal(0, script.main({ "0.2.0", "--dry-run" }, streams))

      for _, target in ipairs(script.targets) do
        assert.is_truthy(stdout():find(target.file, 1, true))
      end
      assert.is_truthy(stdout():find("nothing written", 1, true))
      assert.equal("", stderr())
    end)
  end)

  -- The targets are the script's contract with the repository: each one has to
  -- match the checked-in file exactly once, or a release would skip it.
  it("matches every target in the real checkout exactly once", function()
    local current = assert(script.current_version("."))

    for _, target in ipairs(script.targets) do
      local handle = assert(io.open(target.file, "r"), target.file .. " is missing")
      local contents = handle:read("*a")
      handle:close()

      local _, first = contents:find(target.pattern)
      assert.is_truthy(first, target.file .. ": " .. target.description .. " pattern did not match")
      assert.is_falsy(contents:find(target.pattern, first + 1),
        target.file .. ": " .. target.description .. " pattern matched more than once")
      assert.equal(current, contents:match(target.pattern))
    end
  end)
end)
