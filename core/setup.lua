-- Core setup logic shared between platform-specific entry points
-- This module contains the platform-agnostic initialization logic

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local config = require('kanban-md.config')
local adapter_registry = require('kanban-md.adapter_registry')

local M = {}

--- Perform core setup with the provided adapter
--- @param user_config table|nil Optional configuration overrides
--- @param adapter table The adapter instance to use for this platform
--- @return table Module state with adapter and config
function M.setup(user_config, adapter)
  if not adapter then
    error('core.setup requires an adapter instance')
  end

  -- Register adapter in central registry for use by other modules
  adapter_registry.set_adapter(adapter)

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

  return {
    adapter = adapter,
    config = config,
  }
end

return M
