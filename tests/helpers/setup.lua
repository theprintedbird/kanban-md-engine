-- tests/helpers/setup.lua
-- Opt-in test helper for standalone Lua specs.
--
-- tests/polyfills/vim.lua only provides the vim.* shims required to load
-- kanban-md modules outside Neovim; it no longer runs
-- require('kanban-md.cli').setup() implicitly. Specs that need any of the
-- following must call M.setup() themselves (typically once, at the top of
-- the spec file, outside any describe/it block):
--
--   * a CLIAdapter registered in the adapter registry (adapter_registry.lua)
--   * class-level ULID on_create triggers registered on Board/Column/Card
--     (so Board:new()/Column:new()/Card:new() and parsed cards get ids)
--   * plugin config initialised with non-default overrides
--
-- Board/Column/Card are module-singletons shared across every spec file in
-- a single `busted` run, so trigger registration is deliberately written to
-- be idempotent (register_on_create just overwrites the trigger under the
-- same name) -- calling M.setup() from multiple spec files, or more than
-- once in the same file, is safe and does not double-register anything.

require('polyfills.vim') -- ensure the vim shims + _G._TEST are present first

local M = {}

--- Run kanban-md.cli setup(), registering the CLI adapter, plugin config
--- and (if auto_id is enabled) class-level ULID id triggers.
--- @param user_config table|nil optional plugin config overrides
--- @return table the kanban-md.cli module (Board/Column/Card/config/adapter)
function M.setup(user_config)
  -- cli.lua refuses to run under a real Neovim unless _G._TEST is set; in
  -- standalone tests _G.vim is our polyfill table, so temporarily hide it
  -- to go through the same "definitely not Neovim" path core.setup expects.
  local vim_backup = _G.vim
  _G.vim = nil

  local kanban_cli = require('kanban-md.cli')
  kanban_cli.setup(user_config)

  _G.vim = vim_backup

  return kanban_cli
end

--- Run fn() with the plugin config temporarily overridden by `overrides`,
--- guaranteeing config.reset() runs afterwards even if fn() errors.
--- @param overrides table config overrides, merged via config.setup()
--- @param fn function the function to run under the overridden config
function M.with_config(overrides, fn)
  local config = require('kanban-md.config')

  config.setup(overrides)

  local ok, err = pcall(fn)

  config.reset()

  if not ok then
    error(err, 0)
  end
end

return M
