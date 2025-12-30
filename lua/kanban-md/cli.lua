-- CLI entry point for kanban-md
-- This is the standalone Lua entry point for CLI usage (no Neovim dependencies)
-- For Neovim plugin usage, see lua/kanban-md/init.lua

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local Triggerable = require('kanban-md.triggerable')
local triggers = require('kanban-md.triggers')
local config = require('kanban-md.config')
local core_setup = require('kanban-md.core.setup')

local M = {
  Board = Board,
  Column = Column,
  Card = Card,
  Triggerable = Triggerable,
  triggers = triggers,
  config = config,
  adapter = nil, -- Injected adapter instance (CLIAdapter)
}

-- CLI setup function
-- @param user_config table|nil Optional configuration overrides
--
-- Example usage:
--   local kanban = require('kanban-md.cli')
--   kanban.setup({
--     wip_limit = 5,
--     auto_archive = true,
--   })
function M.setup(user_config)
  -- Prevent accidental use in Neovim (allow in test mode)
  if vim ~= nil and not _G._TEST then
    error("Use require('kanban-md').setup() in Neovim, not require('kanban-md.cli')")
  end

  -- Use CLIAdapter for standalone Lua
  local CLIAdapter = require('kanban-md.adapters.cli')
  M.adapter = CLIAdapter  -- CLIAdapter is already an instance, not a class

  -- Perform core setup (no Neovim commands)
  core_setup.setup(user_config, M.adapter)
end

return M
