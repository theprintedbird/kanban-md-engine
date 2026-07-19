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

-- NOTE: this polyfill deliberately does NOT call
-- require('kanban-md.cli').setup() any more. Specs that need the CLI
-- adapter registered, class-level ULID id triggers on Board/Column/Card,
-- or plugin config initialised must opt in explicitly via
-- require('helpers.setup').setup() (see tests/helpers/setup.lua). This
-- keeps the "pure library, no setup()" path exercised by the test suite
-- instead of every spec silently depending on global setup side effects.

return _G.vim
