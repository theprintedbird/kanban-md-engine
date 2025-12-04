-- Neovim plugin entry point for kanban-md
-- This is the Neovim-specific entry point that sets up commands, keymaps, and autocommands
-- For CLI usage, see lua/kanban-md/cli.lua

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local Triggerable = require('kanban-md.triggerable')
local triggers = require('kanban-md.triggers')
local config = require('kanban-md.config')
local commands = require('kanban-md.commands')
local core_setup = require('kanban-md.core.setup')

local M = {
  _VERSION = require('kanban-md.version'),
  Board = Board,
  Column = Column,
  Card = Card,
  Triggerable = Triggerable,
  triggers = triggers,
  config = config,
  adapter = nil, -- Injected adapter instance (defaults to NeovimAdapter)
}

-- Neovim plugin setup function
-- @param user_config table|nil Optional configuration overrides
--
-- Example usage:
--   require('kanban-md').setup({
--     wip_limit = 5,
--     auto_archive = true,
--   })
function M.setup(user_config)
  -- Use NeovimAdapter for Neovim plugin
  -- Note: neovim.lua returns an already-instantiated adapter, don't call .new()
  local NeovimAdapter = require('kanban-md.adapters.neovim')
  M.adapter = NeovimAdapter

  -- Perform core setup
  core_setup.setup(user_config, M.adapter)

  -- Register Neovim-specific commands, keymaps, and autocommands
  commands.setup()
end

return M
