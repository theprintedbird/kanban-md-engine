-- tests/helpers/singletons.lua
-- Snapshot and restore the module-level state the engine keeps: the class
-- triggers on Board/Column/Card, the adapter registry, and plugin config.
--
-- busted loads every spec file into one Lua state, so those three are shared
-- by the whole run. Two failure shapes follow from that, and this helper is
-- for both:
--
--   * A spec that registers a class-level trigger, or an adapter, leaves it
--     behind for every file that runs after it.
--   * A spec asserting a *default* or *initial* value gets whatever the
--     previous file left, not the default -- and passes or fails on the
--     execution order rather than on the code.
--
-- Usage:
--
--   local singletons = require('helpers.singletons')
--   local restore
--
--   before_each(function() restore = singletons.snapshot() end)
--   after_each(function() restore() end)
--
-- snapshot() leaves the current state in place; pair it with reset() to start
-- from the engine's as-loaded state. The returned restore() is idempotent.

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local adapter_registry = require('kanban-md.adapter_registry')
local config = require('kanban-md.config')

local M = {}

M.CLASSES = { Board = Board, Column = Column, Card = Card }

-- The tables Triggerable keeps its registrations in. Copied one level deep:
-- the trigger functions themselves are shared, but the tables holding them
-- are not, so a spec registering a trigger cannot reach the snapshot.
local TRIGGER_FIELDS = { "triggers", "trigger_order", "trigger_metadata", "command_factories" }

local function copy_two_levels(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, inner in pairs(value) do
    if type(inner) == "table" then
      local inner_copy = {}
      for inner_key, inner_value in pairs(inner) do
        inner_copy[inner_key] = inner_value
      end
      copy[key] = inner_copy
    else
      copy[key] = inner
    end
  end

  return copy
end

--- Snapshot the class-level triggers on Board, Column and Card.
--- @return function restore
function M.snapshot_class_triggers()
  local saved = {}

  for name, class in pairs(M.CLASSES) do
    saved[name] = {}
    for _, field in ipairs(TRIGGER_FIELDS) do
      saved[name][field] = copy_two_levels(class[field])
    end
  end

  return function()
    for name, class in pairs(M.CLASSES) do
      for _, field in ipairs(TRIGGER_FIELDS) do
        class[field] = saved[name][field]
      end
    end
  end
end

--- Remove every class-level trigger, leaving Board/Column/Card as bare as a
--- consumer who has never called setup() would find them.
--- @return nil
function M.clear_class_triggers()
  for _, class in pairs(M.CLASSES) do
    class.triggers = {}
    class.trigger_order = {}
    class.trigger_metadata = {}
    class.command_factories = {}
  end
end

--- Snapshot whichever adapter is registered, if any.
--- @return function restore
function M.snapshot_adapter()
  local previous = adapter_registry.has_adapter() and adapter_registry.get_adapter() or nil

  return function()
    adapter_registry.set_adapter(previous)
  end
end

--- Snapshot plugin config. Restoring resets to defaults and re-applies the
--- snapshot, rather than merging over whatever the spec left: config.setup()
--- merges, so a key the spec added would otherwise survive the restore.
--- @return function restore
function M.snapshot_config()
  local saved = vim.deepcopy(config.get())

  return function()
    config.reset()
    config.setup(saved)
  end
end

--- Snapshot all three at once.
--- @return function restore Idempotent; safe to call from both the body and after_each
function M.snapshot()
  local restorers = {
    M.snapshot_class_triggers(),
    M.snapshot_adapter(),
    M.snapshot_config(),
  }
  local restored = false

  return function()
    if restored then
      return
    end
    restored = true

    for _, restore in ipairs(restorers) do
      restore()
    end
  end
end

--- Put the engine into its as-loaded state: no class triggers, no adapter,
--- default config. Snapshot first if the state is to come back.
--- @return nil
function M.reset()
  M.clear_class_triggers()
  adapter_registry.set_adapter(nil)
  config.reset()
end

return M
