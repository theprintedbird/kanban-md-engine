-- tests/helpers/tempfiles.lua
-- Per-run temporary files for specs that need a real file on disk.
--
-- Two problems this solves. os.tmpname() scatters files directly in the system
-- temp directory, which is shared with every other process, and the specs
-- cleaned up with an inline os.remove() at the end of the test body -- so an
-- assertion failing earlier leaked the file. Here every path lives under one
-- directory per `busted` process, and cleanup() runs from after_each, which
-- busted runs whether the test passed or failed.
--
-- Usage:
--
--   local temp = require('helpers.tempfiles')
--
--   after_each(function() temp.cleanup() end)
--
--   it("writes a board", function()
--     local path = temp.path()          -- a path; nothing is created yet
--     CLIAdapter:write_buffer({ "x" }, { file = path })
--   end)
--
-- Unlike os.tmpname(), path() does not create the file, so it is also the way
-- to get a path that is guaranteed not to exist.

local M = {}

local root
local counter = 0
local created = {}

--- The directory holding this process's temporary files, created on first use.
--- @return string
function M.root()
  if root then
    return root
  end

  -- os.tmpname() is the one portable source of a unique name, but where it
  -- puts it varies (on macOS it ignores $TMPDIR and uses /tmp). Keep only its
  -- basename for uniqueness and place the directory somewhere predictable, so
  -- `make clean` can name it without globbing over the whole temp directory.
  local unique = os.tmpname()
  os.remove(unique)

  local base = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  root = string.format("%s/kanban-md-tests-%s", base, unique:match("([^/]+)$"))
  os.execute(string.format("mkdir -p '%s'", root))

  return root
end

--- A path inside the run directory. The file is not created.
--- @param name string|nil basename to use, otherwise a generated one
--- @return string path
function M.path(name)
  counter = counter + 1

  local path = string.format("%s/%s", M.root(), name or string.format("temp-%d", counter))
  table.insert(created, path)

  return path
end

--- A path inside the run directory holding the given lines.
--- @param lines table array of lines, written with a trailing newline each
--- @param name string|nil basename to use
--- @return string path
function M.file(lines, name)
  local path = M.path(name)

  local handle = assert(io.open(path, "w"))
  for _, line in ipairs(lines or {}) do
    handle:write(line .. "\n")
  end
  handle:close()

  return path
end

--- Remove every path handed out since the last cleanup, and the run directory
--- with them once it is empty. Safe to call when nothing was created.
function M.cleanup()
  for _, path in ipairs(created) do
    os.remove(path)
  end
  created = {}

  if root then
    -- Only succeeds while the directory is empty, which is what we want: a
    -- file another helper put there is not ours to delete.
    if os.remove(root) then
      root = nil
    end
  end
end

return M
