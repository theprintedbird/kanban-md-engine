-- tests/unit/cli_spec.lua
-- Unit tests for lua/kanban-md/cli.lua, the standalone Lua entry point.
--
-- Two things here had no test at all: the guard that refuses to run under a
-- real Neovim, and user config reaching core_setup.setup(). Both touch process
-- globals and module singletons, so this file snapshots _G.vim, _G._TEST, the
-- registered adapter and the plugin config, and restores them afterwards.
require('polyfills.vim')

local CLIAdapter = require('kanban-md.adapters.cli')
local adapter_registry = require('kanban-md.adapter_registry')
local cli = require('kanban-md.cli')
local config = require('kanban-md.config')

describe("kanban-md.cli", function()
  local previous_vim, previous_test, previous_adapter

  setup(function()
    previous_vim = _G.vim
    previous_test = _G._TEST
    previous_adapter = adapter_registry.has_adapter() and adapter_registry.get_adapter() or nil
  end)

  teardown(function()
    _G.vim = previous_vim
    _G._TEST = previous_test
    config.reset()
    adapter_registry.set_adapter(previous_adapter)
  end)

  before_each(function()
    _G.vim = previous_vim
    _G._TEST = previous_test
    config.reset()
  end)

  describe("exports", function()
    it("re-exports the core classes and modules", function()
      assert.equals(require('kanban-md.board'), cli.Board)
      assert.equals(require('kanban-md.column'), cli.Column)
      assert.equals(require('kanban-md.card'), cli.Card)
      assert.equals(require('kanban-md.triggerable'), cli.Triggerable)
      assert.equals(require('kanban-md.triggers'), cli.triggers)
      assert.equals(config, cli.config)
    end)

    it("exposes setup() as its only function", function()
      assert.is_function(cli.setup)
    end)
  end)

  describe("the Neovim guard", function()
    it("refuses to run when vim is present and _TEST is not set", function()
      _G.vim = { real_neovim = true }
      _G._TEST = nil

      local ok, err = pcall(cli.setup)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find(
        "Use require('kanban-md').setup() in Neovim, not require('kanban-md.cli')", 1, true))
    end)

    it("refuses when _TEST is false rather than absent", function()
      _G.vim = { real_neovim = true }
      _G._TEST = false

      assert.is_false(pcall(cli.setup))
    end)

    it("allows the test escape hatch when _TEST is set", function()
      _G.vim = { real_neovim = true }
      _G._TEST = true

      assert.has_no.errors(function() cli.setup() end)
    end)

    it("allows plain standalone Lua, where there is no vim at all", function()
      _G.vim = nil
      _G._TEST = nil

      assert.has_no.errors(function() cli.setup() end)
    end)

    it("does not touch the adapter when it refuses", function()
      adapter_registry.set_adapter(nil)
      _G.vim = { real_neovim = true }
      _G._TEST = nil

      pcall(cli.setup)

      assert.is_false(adapter_registry.has_adapter())
    end)
  end)

  describe("setup()", function()
    it("injects the CLI adapter", function()
      _G.vim = nil

      cli.setup()

      assert.equals(CLIAdapter, cli.adapter)
      assert.equals(CLIAdapter, adapter_registry.get_adapter())
    end)

    it("passes user config through to the plugin config", function()
      _G.vim = nil

      cli.setup({ wip_limit = 3, cycle_time_unit = "hours" })

      assert.equals(3, config.get_value("wip_limit"))
      assert.equals("hours", config.get_value("cycle_time_unit"))
    end)

    it("leaves keys the caller did not mention at their defaults", function()
      _G.vim = nil
      local default_separator = config.get_defaults().property_separator

      cli.setup({ wip_limit = 3 })

      assert.equals(default_separator, config.get_value("property_separator"))
    end)

    it("accepts no config at all", function()
      _G.vim = nil

      cli.setup()

      assert.equals(config.get_defaults().wip_limit, config.get_value("wip_limit"))
    end)

    it("registers the id triggers core_setup is responsible for", function()
      _G.vim = nil

      cli.setup()

      assert.is_function(cli.Card:get_triggers("on_create")["generate_ulid_id"])
    end)

    it("is safe to call more than once", function()
      _G.vim = nil

      cli.setup({ wip_limit = 3 })
      cli.setup({ cycle_time_unit = "hours" })

      assert.equals(3, config.get_value("wip_limit"))
      assert.equals("hours", config.get_value("cycle_time_unit"))
      assert.equals(CLIAdapter, adapter_registry.get_adapter())
    end)
  end)
end)
