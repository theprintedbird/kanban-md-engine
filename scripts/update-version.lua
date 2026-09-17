#!/usr/bin/env lua
-- scripts/update-version.lua
-- Set the engine's version number everywhere it is written down.
--
--   lua scripts/update-version.lua 0.2.0 [--dry-run]
--
-- The version lives in more than one file, and the copies drift silently: a
-- release that bumps lua/kanban-md/version.lua but leaves SPEC.md claiming
-- the old number is not a broken build, just a document that lies. This
-- script rewrites every copy at once, from one list.
--
-- Every target must match exactly once. A target whose pattern no longer
-- matches -- a line reworded, a file moved -- is an error, not a skip: the
-- point of the script is that it cannot quietly miss a place. Adding a new
-- place to the list is the only change needed when one appears.
--
-- Loading the file as a module (dofile) returns the table below without
-- running anything, which is how the spec drives it.

local M = {}

-- Each target names a file relative to the repository root, a Lua pattern
-- with a single capture around the version number itself, and a description
-- used in errors and in the summary.
M.targets = {
  {
    file = "lua/kanban-md/version.lua",
    pattern = '^return "([^"]+)"',
    description = "module version",
  },
  {
    file = "SPEC.md",
    pattern = "%(currently `([^`]+)`%)",
    description = "SPEC.md status line",
  },
}

--- Semantic version, optionally with a prerelease and/or build suffix.
--- @param version string
--- @return boolean
function M.is_valid_version(version)
  if type(version) ~= "string" then
    return false
  end

  local core, rest = version:match("^(%d+%.%d+%.%d+)(.*)$")
  if not core then
    return false
  end

  return rest == "" or rest:match("^[%-+][%w%.%-+]+$") ~= nil
end

local function read_file(path)
  local handle, err = io.open(path, "r")
  if not handle then
    return nil, err or ("cannot read " .. path)
  end

  local contents = handle:read("*a")
  handle:close()

  return contents
end

local function write_file(path, contents)
  local handle, err = io.open(path, "w")
  if not handle then
    return nil, err or ("cannot write " .. path)
  end

  handle:write(contents)
  handle:close()

  return true
end

--- Rewrite one target. Returns the version found before the change.
--- @param root string repository root
--- @param target table an entry from M.targets
--- @param version string
--- @param dry_run boolean|nil
--- @return string|nil previous, string|nil err
function M.update_target(root, target, version, dry_run)
  local path = root .. "/" .. target.file

  local contents, err = read_file(path)
  if not contents then
    return nil, string.format("%s: %s", target.file, err)
  end

  local before, after = contents:find(target.pattern)
  if not before then
    return nil, string.format("%s: %s pattern did not match", target.file, target.description)
  end

  local current = contents:match(target.pattern)

  -- A second match means the pattern is no longer specific enough, and a
  -- blind replace would rewrite the wrong line.
  if contents:find(target.pattern, after + 1) then
    return nil, string.format("%s: %s pattern matched more than once", target.file, target.description)
  end

  if current == version then
    return current
  end

  local matched = contents:sub(before, after)
  local replacement = matched:gsub(current:gsub("%W", "%%%0"), (version:gsub("%%", "%%%%")), 1)
  local updated = contents:sub(1, before - 1) .. replacement .. contents:sub(after + 1)

  if not dry_run then
    local ok, write_err = write_file(path, updated)
    if not ok then
      return nil, string.format("%s: %s", target.file, write_err)
    end
  end

  return current
end

--- Set the version in every target.
--- @param opts table { version = string, root = string|nil, dry_run = boolean|nil }
--- @return table|nil changes array of { file, description, previous, version }, string|nil err
function M.update(opts)
  local version = opts.version
  local root = opts.root or "."

  if not M.is_valid_version(version) then
    return nil, string.format("not a semantic version: %s", tostring(version))
  end

  -- Read and validate every target before writing any of them, so a typo in
  -- the last file does not leave the first one bumped.
  for _, target in ipairs(M.targets) do
    local _, err = M.update_target(root, target, version, true)
    if err then
      return nil, err
    end
  end

  local changes = {}
  for _, target in ipairs(M.targets) do
    local previous, err = M.update_target(root, target, version, opts.dry_run)
    if err then
      return nil, err
    end

    table.insert(changes, {
      file = target.file,
      description = target.description,
      previous = previous,
      version = version,
    })
  end

  return changes
end

--- The version the engine currently reports, read from the first target.
--- @param root string|nil
--- @return string|nil version, string|nil err
function M.current_version(root)
  local target = M.targets[1]
  local contents, err = read_file((root or ".") .. "/" .. target.file)
  if not contents then
    return nil, string.format("%s: %s", target.file, err)
  end

  return contents:match(target.pattern)
end

--- The usage message, listing the files from M.targets so it cannot go stale.
--- @return string
local function usage()
  local files = {}
  for _, target in ipairs(M.targets) do
    table.insert(files, target.file)
  end

  return string.format([[
Usage: lua scripts/update-version.lua <version> [--dry-run]

Sets the engine version in every file that records it:
  %s

Options:
  --dry-run   report what would change without writing
  --current   print the current version and exit
  -h, --help  show this message
]], table.concat(files, ", "))
end

--- Run the script.
---
--- Data (the summary, the current version) goes to stdout; usage and errors
--- go to stderr, so `make version` output stays pipeable. `streams` overrides
--- both, which is how the spec keeps its own output quiet.
---
--- @param argv table command-line arguments
--- @param streams table|nil { out = file-like, err = file-like }
--- @return number exit code
function M.main(argv, streams)
  local out = (streams or {}).out or io.stdout
  local err_out = (streams or {}).err or io.stderr

  local function say(fmt, ...)
    out:write(string.format(fmt, ...) .. "\n")
  end

  local function complain(fmt, ...)
    err_out:write(string.format(fmt, ...))
  end

  local version, dry_run, show_current

  for _, value in ipairs(argv or {}) do
    if value == "--dry-run" then
      dry_run = true
    elseif value == "--current" then
      show_current = true
    elseif value == "-h" or value == "--help" then
      complain("%s", usage())
      return 0
    elseif value:match("^%-") then
      complain("Unknown option: %s\n%s", value, usage())
      return 2
    elseif version then
      complain("Unexpected argument: %s\n%s", value, usage())
      return 2
    else
      version = value
    end
  end

  if show_current then
    local current, err = M.current_version(M.root)
    if not current then
      complain("Error: %s\n", err)
      return 1
    end

    say("%s", current)
    return 0
  end

  if not version then
    local current = M.current_version(M.root)
    complain("Current version: %s\n%s", current or "unknown", usage())
    return 2
  end

  local changes, err = M.update({ version = version, root = M.root, dry_run = dry_run })
  if not changes then
    complain("Error: %s\n", err)
    return 1
  end

  for _, change in ipairs(changes) do
    if change.previous == change.version then
      say("%s already at %s (%s)", change.file, change.version, change.description)
    else
      say("%s %s -> %s (%s)", change.file, change.previous, change.version, change.description)
    end
  end

  if dry_run then
    say("--dry-run: nothing written")
  end

  return 0
end

-- The repository root, derived from this script's own path, so the script
-- works from any working directory. dofile() from a spec leaves it nil, and
-- update() is then given an explicit root.
local this = (debug.getinfo(1, "S").source or ""):match("^@(.*)$")
if this then
  M.root = this:match("^(.*)/scripts/[^/]+$") or "."
end

-- Run only when invoked as a script: dofile() and require() both leave `arg`
-- pointing at busted's own arguments, so check that this file is the one the
-- interpreter was given.
if arg and arg[0] and arg[0]:match("update%-version%.lua$") then
  os.exit(M.main(arg))
end

return M
