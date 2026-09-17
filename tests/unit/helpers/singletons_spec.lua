-- tests/unit/helpers/singletons_spec.lua
-- The snapshot/restore helper the rest of the suite leans on. If it silently
-- failed to restore something, every spec using it would go back to depending
-- on execution order, so its own restoration is asserted here.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local Column = require('kanban-md.column')
local adapter_registry = require('kanban-md.adapter_registry')
local config = require('kanban-md.config')
local singletons = require('helpers.singletons')

local function noop_trigger()
  return true
end

local function stub_adapter(name)
  return {
    name = name,
    notify = function() end,
    read_buffer = function() return {} end,
    write_buffer = function() end,
    get_cursor = function() return 1, 0 end,
    set_cursor = function() end,
    prompt_input = function() end,
    prompt_select = function() end,
  }
end

describe("helpers.singletons", function()
  -- The helper under test is the thing that would normally protect the run, so
  -- this file takes its own snapshot around every test.
  local restore

  before_each(function()
    restore = singletons.snapshot()
  end)

  after_each(function()
    restore()
  end)

  describe("class triggers", function()
    it("removes a trigger registered after the snapshot", function()
      Card:register_on_create("spec_only", noop_trigger)
      assert.is_not_nil(Card:get_triggers("on_create")["spec_only"])

      restore()

      assert.is_nil(Card:get_triggers("on_create")["spec_only"])
    end)

    it("brings back a trigger the spec cleared", function()
      Board:register_on_entry("kept", noop_trigger)
      local kept_restore = singletons.snapshot()

      Board:clear_triggers()
      assert.is_nil(Board:get_triggers("on_entry")["kept"])

      kept_restore()

      assert.equals(noop_trigger, Board:get_triggers("on_entry")["kept"])
    end)

    it("covers all three classes", function()
      Board:register_on_entry("spec_only", noop_trigger)
      Column:register_on_exit("spec_only", noop_trigger)
      Card:register_on_create("spec_only", noop_trigger)

      restore()

      assert.is_nil(Board:get_triggers("on_entry")["spec_only"])
      assert.is_nil(Column:get_triggers("on_exit")["spec_only"])
      assert.is_nil(Card:get_triggers("on_create")["spec_only"])
    end)

    it("snapshots the tables, not references to them", function()
      Card:register_on_create("before_snapshot", noop_trigger)
      local later = singletons.snapshot()

      -- Registering mutates Card.triggers.on_create in place; a shallow
      -- snapshot of that table would see the new trigger too and restore
      -- nothing.
      Card:register_on_create("after_snapshot", noop_trigger)
      later()

      assert.is_not_nil(Card:get_triggers("on_create")["before_snapshot"])
      assert.is_nil(Card:get_triggers("on_create")["after_snapshot"])
    end)

    it("clear_class_triggers empties every registration", function()
      Board:register_on_entry("spec_only", noop_trigger)
      Card:register_on_create("spec_only", noop_trigger)

      singletons.clear_class_triggers()

      assert.same({}, Board.triggers)
      assert.same({}, Column.triggers)
      assert.same({}, Card.triggers)
    end)
  end)

  describe("adapter registry", function()
    it("puts back the adapter that was registered", function()
      local original = stub_adapter("Original")
      adapter_registry.set_adapter(original)

      local adapter_restore = singletons.snapshot_adapter()
      adapter_registry.set_adapter(stub_adapter("Replacement"))
      adapter_restore()

      assert.equals(original, adapter_registry.get_adapter())
    end)

    it("puts back an empty registry", function()
      adapter_registry.set_adapter(nil)

      local adapter_restore = singletons.snapshot_adapter()
      adapter_registry.set_adapter(stub_adapter("Replacement"))
      adapter_restore()

      assert.is_false(adapter_registry.has_adapter())
    end)
  end)

  describe("config", function()
    it("restores a value the spec changed", function()
      config.reset()
      local default_unit = config.get_defaults().cycle_time_unit
      assert.is_string(default_unit)

      local config_restore = singletons.snapshot_config()
      config.setup({ cycle_time_unit = "fortnights" })
      config_restore()

      assert.equals(default_unit, config.get_value("cycle_time_unit"))
    end)

    it("removes a key the spec added, which a merge-back restore would keep", function()
      config.reset()

      local config_restore = singletons.snapshot_config()
      config.setup({ spec_only_key = "left behind" })
      config_restore()

      assert.is_nil(config.get_value("spec_only_key"))
    end)

    it("keeps overrides that were in place before the snapshot", function()
      config.reset()
      config.setup({ wip_limit = 42 })

      local config_restore = singletons.snapshot_config()
      config.setup({ wip_limit = 7 })
      config_restore()

      assert.equals(42, config.get_value("wip_limit"))
    end)
  end)

  describe("reset", function()
    it("leaves the engine as a fresh require would find it", function()
      Card:register_on_create("spec_only", noop_trigger)
      adapter_registry.set_adapter(stub_adapter("Spec"))
      config.setup({ cycle_time_unit = "fortnights" })

      singletons.reset()

      assert.same({}, Card.triggers)
      assert.is_false(adapter_registry.has_adapter())
      assert.equals(config.get_defaults().cycle_time_unit, config.get_value("cycle_time_unit"))
    end)
  end)

  describe("snapshot()", function()
    it("restores triggers, adapter and config together", function()
      config.reset()
      adapter_registry.set_adapter(nil)

      local all_restore = singletons.snapshot()

      Card:register_on_create("spec_only", noop_trigger)
      adapter_registry.set_adapter(stub_adapter("Spec"))
      config.setup({ cycle_time_unit = "fortnights" })

      all_restore()

      assert.is_nil(Card:get_triggers("on_create")["spec_only"])
      assert.is_false(adapter_registry.has_adapter())
      assert.equals(config.get_defaults().cycle_time_unit, config.get_value("cycle_time_unit"))
    end)

    it("is idempotent, so a test body and after_each can both call it", function()
      config.reset()
      local all_restore = singletons.snapshot()
      all_restore()

      config.setup({ wip_limit = 123 })
      all_restore() -- the stale restore must not undo this

      assert.equals(123, config.get_value("wip_limit"))
    end)
  end)
end)
