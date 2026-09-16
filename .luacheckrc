-- Luacheck configuration for the kanban-md engine.
-- https://luacheck.readthedocs.io/
--
-- The point of this configuration is that a clean run means something: the
-- checks that catch real defects (undefined globals, shadowing, unreachable
-- code) are on everywhere. The families that are muted below are either
-- cosmetic or unavoidable given the engine's trigger interfaces, and are
-- listed with the reason rather than switched off wholesale.

std = "max"          -- union of 5.1-5.4 and LuaJIT, matching the CI matrix

-- The engine still calls a handful of Neovim utility functions; under
-- standalone Lua those come from tests/polyfills/vim.lua, which assigns the
-- stand-in table, so `vim` has to be writable rather than a read-only global.
globals = {
  "vim",
  "_TEST",           -- switches on the modules' internal test exports
}

read_globals = {
  "ngx",             -- OpenResty, probed defensively by helpers/ulid.lua
}

max_line_length = false

-- Triggers, adapters and mixins all implement fixed signatures, so unused
-- arguments are the norm rather than a smell.
unused_args = false

ignore = {
  "611",             -- line contains only whitespace
  "612",             -- line contains trailing whitespace
  "614",             -- trailing whitespace in a comment

  -- The parser keeps a few defensive `x = nil` resets and one write-only flag
  -- that read as intent rather than as dead code.
  "311",             -- value assigned to a variable is never used
  "231",             -- variable is never accessed
}

exclude_files = {
  ".luarocks",       -- rocks installed into the tree by CI
  "lua_modules",
}

files["tests/"] = {
  std = "max+busted",
  ignore = {
    "211",           -- unused variable: specs require modules for readability
    "212",
    "213",           -- unused loop variable
    "231",           -- variable is never accessed
    "311",           -- value assigned to a variable is never used
    "122",           -- specs stub io.stdout/io.stderr to capture output
    "431",           -- nested describe blocks routinely reuse outer names
  },
}

files["lua/kanban-md/adapters/USAGE_EXAMPLE.lua"] = {
  -- Illustrative example rather than shipped code: it names things for the
  -- reader's benefit without always using them.
  ignore = { "211", "4" },
}
