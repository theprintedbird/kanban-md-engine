-- Event-driven kanban board implementation
-- Single entry point for all classes and utilities

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local Triggerable = require('kanban-md.triggerable')
local triggers = require('kanban-md.triggers')
local config = require('kanban-md.config')
local commands = require('kanban-md.commands')
local adapter_registry = require('kanban-md.adapter_registry')

local M = {
  Board = Board,
  Column = Column,
  Card = Card,
  Triggerable = Triggerable,
  triggers = triggers,
  config = config,
  adapter = nil, -- Injected adapter instance (defaults to NeovimAdapter)
}

-- Plugin setup function
-- @param user_config table|nil Optional configuration overrides
-- @param opts table|nil Optional setup options:
--   - adapter: Adapter instance to use (defaults to NeovimAdapter if not provided)
--
-- Example usage:
--   -- Default Neovim setup
--   require('kanban-md').setup({})
--
--   -- Custom adapter injection (for CLI, web, etc.)
--   local CLIAdapter = require('kanban-md.adapters.cli')
--   require('kanban-md').setup({}, { adapter = CLIAdapter.new() })
function M.setup(user_config, opts)
  opts = opts or {}

  -- Inject adapter or default to NeovimAdapter
  if opts.adapter then
    M.adapter = opts.adapter
  else
    -- Default to NeovimAdapter when running in Neovim
    -- Note: neovim.lua returns an already-instantiated adapter, don't call .new()
    local NeovimAdapter = require('kanban-md.adapters.neovim')
    M.adapter = NeovimAdapter
  end

  -- Register adapter in central registry for use by other modules
  adapter_registry.set_adapter(M.adapter)

  -- Configure the plugin
  config.setup(user_config)

  -- Register default ID generation triggers if auto_id is enabled
  if config.get_value('auto_id') then
    local id_triggers = require('kanban-md.extras.id_triggers')
    local ulid_exec = id_triggers.ulid_id()

    -- Register on all three classes
    Board:register_on_create("generate_ulid_id", ulid_exec)
    Column:register_on_create("generate_ulid_id", ulid_exec)
    Card:register_on_create("generate_ulid_id", ulid_exec)
  end

  -- Note: Cursor positioning trigger is registered per-column in Board:register_basic_triggers()
  -- This happens automatically during parsing via auto_register_triggers()

  -- Register Neovim commands
  commands.setup()
end

return M
