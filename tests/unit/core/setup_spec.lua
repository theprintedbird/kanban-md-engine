-- tests/unit/core/setup_spec.lua
-- Unit tests for lua/kanban-md/core/setup.lua, the platform-agnostic half of
-- setup() that every entry point (cli.lua, the Neovim plugin's init.lua) calls
-- once it has an adapter. Reached indirectly by tests/helpers/setup.lua, but
-- its own contract -- adapter required, adapter registered, config merged, id
-- triggers registered only when auto_id is on -- was never asserted directly.
--
-- Everything it touches is a module singleton (the registry, config, and the
-- class-level triggers on Board/Column/Card), so this file snapshots all of
-- them and puts them back afterwards.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local adapter_registry = require('kanban-md.adapter_registry')
local config = require('kanban-md.config')
local core_setup = require('kanban-md.core.setup')

local CLASSES = { Board = Board, Column = Column, Card = Card }

--- An adapter that satisfies Adapter.validate() and does nothing else.
local function stub_adapter(name)
  return {
    name = name or "StubAdapter",
    notify = function() end,
    read_buffer = function() return {} end,
    write_buffer = function() end,
    get_cursor = function() return 1, 0 end,
    set_cursor = function() end,
    prompt_input = function() end,
    prompt_select = function() end,
  }
end

local function id_trigger_on(class)
  return class:get_triggers("on_create")["generate_ulid_id"]
end

local function clear_id_triggers()
  for _, class in pairs(CLASSES) do
    class:clear_triggers("on_create", "generate_ulid_id")
  end
end

describe("core.setup", function()
  local previous_adapter
  local previous_id_triggers

  setup(function()
    previous_adapter = adapter_registry.has_adapter() and adapter_registry.get_adapter() or nil

    previous_id_triggers = {}
    for name, class in pairs(CLASSES) do
      previous_id_triggers[name] = id_trigger_on(class)
    end
  end)

  teardown(function()
    config.reset()
    adapter_registry.set_adapter(previous_adapter)

    clear_id_triggers()
    for name, class in pairs(CLASSES) do
      if previous_id_triggers[name] then
        class:register_on_create("generate_ulid_id", previous_id_triggers[name])
      end
    end
  end)

  before_each(function()
    config.reset()
    clear_id_triggers()
  end)

  describe("adapter handling", function()
    it("requires an adapter", function()
      local ok, err = pcall(core_setup.setup, {})

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("core.setup requires an adapter instance", 1, true))
    end)

    it("registers the adapter in the central registry", function()
      local adapter = stub_adapter("FirstAdapter")

      core_setup.setup(nil, adapter)

      assert.is_true(adapter_registry.has_adapter())
      assert.equals(adapter, adapter_registry.get_adapter())
    end)

    it("replaces a previously registered adapter", function()
      core_setup.setup(nil, stub_adapter("FirstAdapter"))
      local second = stub_adapter("SecondAdapter")

      core_setup.setup(nil, second)

      assert.equals(second, adapter_registry.get_adapter())
    end)

    it("returns the adapter and the config module", function()
      local adapter = stub_adapter()

      local state = core_setup.setup(nil, adapter)

      assert.equals(adapter, state.adapter)
      assert.equals(config, state.config)
    end)
  end)

  describe("configuration", function()
    it("applies user overrides", function()
      core_setup.setup({ wip_limit = 7, cycle_time_unit = "hours" }, stub_adapter())

      assert.equals(7, config.get_value("wip_limit"))
      assert.equals("hours", config.get_value("cycle_time_unit"))
    end)

    it("leaves untouched keys at their defaults", function()
      local default_separator = config.get_defaults().property_separator

      core_setup.setup({ wip_limit = 7 }, stub_adapter())

      assert.equals(default_separator, config.get_value("property_separator"))
    end)

    it("merges rather than replaces across repeated setups", function()
      core_setup.setup({ wip_limit = 7 }, stub_adapter())
      core_setup.setup({ cycle_time_unit = "hours" }, stub_adapter())

      assert.equals(7, config.get_value("wip_limit"))
      assert.equals("hours", config.get_value("cycle_time_unit"))
    end)

    it("accepts a nil config", function()
      assert.has_no.errors(function()
        core_setup.setup(nil, stub_adapter())
      end)

      assert.equals(config.get_defaults().wip_limit, config.get_value("wip_limit"))
    end)
  end)

  describe("id triggers", function()
    it("registers the ULID on_create trigger on Board, Column and Card", function()
      core_setup.setup(nil, stub_adapter())

      for name, class in pairs(CLASSES) do
        assert.is_function(id_trigger_on(class), name .. " has no generate_ulid_id trigger")
      end
    end)

    it("registers the same trigger function on all three classes", function()
      core_setup.setup(nil, stub_adapter())

      assert.equals(id_trigger_on(Board), id_trigger_on(Column))
      assert.equals(id_trigger_on(Board), id_trigger_on(Card))
    end)

    it("does not register them when auto_id is off", function()
      core_setup.setup({ auto_id = false }, stub_adapter())

      for name, class in pairs(CLASSES) do
        assert.is_nil(id_trigger_on(class), name .. " registered a trigger with auto_id off")
      end
    end)

    it("leaves new cards on Card's own fallback id when auto_id is off", function()
      core_setup.setup({ auto_id = false }, stub_adapter())

      -- Card:new() has a counter-based fallback of its own; with no ULID
      -- trigger registered that is what a new card gets, not a ULID.
      local id = Card:new(nil, "No ULID for me").id

      assert.matches("^card_%d+_%d+$", id)
    end)

    it("gives new cards a prefixed ULID once registered", function()
      core_setup.setup(nil, stub_adapter())

      assert.matches("^card_[0-9A-HJKMNP-TV-Z]+$", Card:new(nil, "Give me an id").id)
    end)

    it("does not overwrite an id the caller supplied", function()
      core_setup.setup(nil, stub_adapter())

      assert.equals("card_mine", Card:new("card_mine", "Keep my id").id)
    end)

    it("re-registers idempotently rather than stacking duplicates", function()
      core_setup.setup(nil, stub_adapter())
      core_setup.setup(nil, stub_adapter())

      local seen = 0
      for _, name in ipairs(Card.trigger_order["on_create"]) do
        if name == "generate_ulid_id" then
          seen = seen + 1
        end
      end

      assert.equals(1, seen)
    end)
  end)
end)
