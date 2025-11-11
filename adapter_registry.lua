-- lua/kanban-md/adapter_registry.lua
-- Central adapter registry to avoid circular dependencies
-- This module provides a single source of truth for the current adapter instance

local M = {
  _adapter = nil, -- The current adapter instance
}

-- Get the current adapter instance
-- @return Adapter The current adapter (NeovimAdapter or CLIAdapter)
-- @throws error if no adapter has been set
function M.get_adapter()
  if not M._adapter then
    error("No adapter registered. Call require('kanban-md').setup() first.")
  end
  return M._adapter
end

-- Set the adapter instance (called by init.lua during setup)
-- @param adapter Adapter The adapter instance to register
function M.set_adapter(adapter)
  M._adapter = adapter
end

-- Check if an adapter has been registered
-- @return boolean True if adapter is registered
function M.has_adapter()
  return M._adapter ~= nil
end

return M
