-- Polyfill for vim.* functions used in tests

-- Mark that we're in test mode (must be set before loading any modules)
_G._TEST = true

-- Inline deepcopy to avoid requiring kanban-md modules
local function deepcopy(tbl, seen)
  if type(tbl) ~= 'table' then return tbl end
  if seen and seen[tbl] then return seen[tbl] end

  local s = seen or {}
  local res = {}
  s[tbl] = res
  for k, v in next, tbl do
    res[deepcopy(k, s)] = deepcopy(v, s)
  end
  return setmetatable(res, getmetatable(tbl))
end

_G.vim = {
  -- Table utilities
  deepcopy = deepcopy,

  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
    end
    return false
  end,

  tbl_count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
  end,

  tbl_extend = function(behavior, ...)
    local tables = {...}
    local result = {}
    for _, tbl in ipairs(tables) do
      for k, v in pairs(tbl) do
        if behavior == "force" or result[k] == nil then
          result[k] = v
        end
      end
    end
    return result
  end,

  -- Vim functions
  fn = {
    getcwd = function()
      return os.getenv("PWD") or io.popen("pwd"):read("*l")
    end
  }
}

-- Initialize CLI adapter for standalone tests
-- This ensures tests use CLIAdapter instead of NeovimAdapter
-- We need to temporarily unset vim global to bypass the safety check in cli.lua
local vim_backup = _G.vim
_G.vim = nil

local kanban_cli = require('kanban-md.cli')
kanban_cli.setup()

-- Restore vim global for test use
_G.vim = vim_backup

return _G.vim

