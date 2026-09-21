require('polyfills.vim')
local ColumnTypeResolver = require("kanban-md.column_type_resolver")
local adapter_registry = require("kanban-md.adapter_registry")

describe("ColumnTypeResolver", function()
  -- Sample config used across tests
  local sample_config

  before_each(function()
    sample_config = {
      column_config = {
        types = {
          completion = {
            properties = {
              is_completion_state = true,
              auto_archive_days = 30
            },
            triggers = {
              on_entry = {
                { module = "kanban-md.triggers", function_name = "timestamp", name = "timestamp" }
              }
            },
            patterns = { "done", "complete", "finished" }
          },
          wip = {
            properties = {
              is_active_state = true
            },
            requires_wip_limit = true
          },
          blocked = {
            properties = {
              is_blocked_state = true
            },
            patterns = { "blocked", "waiting", "parked" }
          },
          multi_pattern = {
            properties = {
              test_prop = "value"
            },
            patterns = { "pattern1", "pattern2", "pattern3" }
          }
        },
        definitions = {
          ["Done"] = { type = "completion" },
          ["Completed"] = { type = "completion", wip_limit = 10 },
          ["Blocked Tasks"] = { type = "blocked", wip_limit = 5 },
          ["Custom Override"] = { type = "wip" }
        }
      },
      missing_property_requirement = "warning"
    }
  end)

  describe("resolve_type()", function()
    it("returns explicit type from markdown config (highest priority)", function()
      local markdown_config = { type = "wip" }
      local result = ColumnTypeResolver.resolve_type("Done", markdown_config, sample_config)
      assert.equals("wip", result)
    end)

    it("returns type from named definition when no explicit type in markdown", function()
      local markdown_config = { wip_limit = 5 }
      local result = ColumnTypeResolver.resolve_type("Done", markdown_config, sample_config)
      assert.equals("completion", result)
    end)

    it("returns type from pattern match when no definition or explicit type", function()
      local markdown_config = {}
      local result = ColumnTypeResolver.resolve_type("Finished Tasks", markdown_config, sample_config)
      assert.equals("completion", result)
    end)

    it("matches pattern with single pattern in array", function()
      local markdown_config = {}
      local result = ColumnTypeResolver.resolve_type("Blocked Items", markdown_config, sample_config)
      assert.equals("blocked", result)
    end)

    it("matches first pattern when multiple patterns exist", function()
      local markdown_config = {}
      -- Should match "pattern1"
      local result = ColumnTypeResolver.resolve_type("This has pattern1 in it", markdown_config, sample_config)
      assert.equals("multi_pattern", result)
    end)

    it("matches any pattern in multiple patterns array", function()
      local markdown_config = {}
      -- Should match "pattern3"
      local result = ColumnTypeResolver.resolve_type("Contains pattern3 here", markdown_config, sample_config)
      assert.equals("multi_pattern", result)
    end)

    it("returns nil when no match found", function()
      local markdown_config = {}
      local result = ColumnTypeResolver.resolve_type("Random Column Name", markdown_config, sample_config)
      assert.is_nil(result)
    end)

    it("verifies priority order: markdown > definition > pattern", function()
      -- Column "done" would match pattern "done" -> completion type
      -- But we have a definition that overrides it to "wip"
      -- And markdown explicit type should override both
      local markdown_config = { type = "blocked" }
      local result = ColumnTypeResolver.resolve_type("Custom Override", markdown_config, sample_config)
      assert.equals("blocked", result) -- markdown wins
    end)

    it("handles nil markdown config gracefully", function()
      local result = ColumnTypeResolver.resolve_type("Done", nil, sample_config)
      assert.equals("completion", result)
    end)

    it("handles empty markdown config", function()
      local result = ColumnTypeResolver.resolve_type("Done", {}, sample_config)
      assert.equals("completion", result)
    end)

    it("handles nil global config gracefully", function()
      local markdown_config = { type = "wip" }
      local result = ColumnTypeResolver.resolve_type("Done", markdown_config, nil)
      assert.is_nil(result)
    end)

    it("handles missing column_config in global config", function()
      local markdown_config = {}
      local config_without_column_config = { missing_property_requirement = "warning" }
      local result = ColumnTypeResolver.resolve_type("Done", markdown_config, config_without_column_config)
      assert.is_nil(result)
    end)
  end)

  describe("get_type_definition()", function()
    it("returns type definition for valid type name", function()
      local result = ColumnTypeResolver.get_type_definition("completion", sample_config)
      assert.is_not_nil(result)
      assert.is_true(result.properties.is_completion_state)
      assert.equals(30, result.properties.auto_archive_days)
    end)

    it("returns nil for non-existent type", function()
      local result = ColumnTypeResolver.get_type_definition("nonexistent", sample_config)
      assert.is_nil(result)
    end)

    it("returns nil when type_name is nil", function()
      local result = ColumnTypeResolver.get_type_definition(nil, sample_config)
      assert.is_nil(result)
    end)

    it("returns nil when global config is nil", function()
      local result = ColumnTypeResolver.get_type_definition("completion", nil)
      assert.is_nil(result)
    end)

    it("returns complete type definition with all fields", function()
      local result = ColumnTypeResolver.get_type_definition("completion", sample_config)
      assert.is_not_nil(result.properties)
      assert.is_not_nil(result.triggers)
      assert.is_not_nil(result.patterns)
    end)
  end)

  describe("merge_properties()", function()
    it("returns type properties when only type exists", function()
      local result = ColumnTypeResolver.merge_properties("Unknown Column", {}, "completion", sample_config)
      assert.is_true(result.is_completion_state)
      assert.equals(30, result.auto_archive_days)
    end)

    it("merges definition properties over type properties", function()
      -- "Completed" definition has wip_limit: 10
      local result = ColumnTypeResolver.merge_properties("Completed", {}, "completion", sample_config)
      assert.is_true(result.is_completion_state) -- from type
      assert.equals(30, result.auto_archive_days) -- from type
      assert.equals(10, result.wip_limit) -- from definition
    end)

    it("merges markdown properties over both type and definition", function()
      local markdown_props = { auto_archive_days = 7, custom_prop = "test" }
      local result = ColumnTypeResolver.merge_properties("Completed", markdown_props, "completion", sample_config)
      assert.is_true(result.is_completion_state) -- from type
      assert.equals(10, result.wip_limit) -- from definition
      assert.equals(7, result.auto_archive_days) -- from markdown (overrides type)
      assert.equals("test", result.custom_prop) -- from markdown (new property)
    end)

    it("handles all three sources with markdown winning conflicts", function()
      -- Type has: is_completion_state = true, auto_archive_days = 30
      -- Definition (Completed) has: wip_limit = 10
      -- Markdown has: auto_archive_days = 5, wip_limit = 3, new_prop = "value"
      local markdown_props = { auto_archive_days = 5, wip_limit = 3, new_prop = "value" }
      local result = ColumnTypeResolver.merge_properties("Completed", markdown_props, "completion", sample_config)

      assert.is_true(result.is_completion_state) -- from type (no conflict)
      assert.equals(5, result.auto_archive_days) -- from markdown (overrides type)
      assert.equals(3, result.wip_limit) -- from markdown (overrides definition)
      assert.equals("value", result.new_prop) -- from markdown (new)
    end)

    it("handles empty markdown config gracefully", function()
      local result = ColumnTypeResolver.merge_properties("Completed", {}, "completion", sample_config)
      assert.is_true(result.is_completion_state)
      assert.equals(10, result.wip_limit)
    end)

    it("handles nil type (no type properties)", function()
      local markdown_props = { wip_limit = 5 }
      local result = ColumnTypeResolver.merge_properties("Completed", markdown_props, nil, sample_config)
      -- Should still get definition properties and markdown
      assert.equals(5, result.wip_limit) -- markdown overrides definition's type lookup failure
    end)

    it("handles column with no definition (only type and markdown)", function()
      local markdown_props = { wip_limit = 5 }
      local result = ColumnTypeResolver.merge_properties("Random Column", markdown_props, "completion", sample_config)
      assert.is_true(result.is_completion_state) -- from type
      assert.equals(30, result.auto_archive_days) -- from type
      assert.equals(5, result.wip_limit) -- from markdown
    end)

    it("returns only markdown properties when no type or definition exists", function()
      local markdown_props = { wip_limit = 5, custom = "value" }
      local result = ColumnTypeResolver.merge_properties("Random Column", markdown_props, nil, sample_config)
      assert.equals(5, result.wip_limit)
      assert.equals("value", result.custom)
    end)

    it("handles nil markdown_props gracefully", function()
      local result = ColumnTypeResolver.merge_properties("Completed", nil, "completion", sample_config)
      assert.is_true(result.is_completion_state)
      assert.equals(10, result.wip_limit)
    end)

    it("preserves all property types (numbers, booleans, strings, tables)", function()
      local markdown_props = {
        number_prop = 42,
        bool_prop = true,
        string_prop = "test",
        table_prop = { key = "value" }
      }
      local result = ColumnTypeResolver.merge_properties("Random", markdown_props, nil, sample_config)
      assert.equals(42, result.number_prop)
      assert.is_true(result.bool_prop)
      assert.equals("test", result.string_prop)
      assert.equals("value", result.table_prop.key)
    end)
  end)

  describe("validate_requirements()", function()
    -- Mock column objects for testing
    local function make_column(name, column_type, config_props)
      return {
        name = name,
        type = column_type,
        config = config_props or {}
      }
    end

    -- validate_requirements() reports through the registered adapter at warn
    -- level. adapter_registry holds a module singleton, so the mock is put
    -- back after each test.
    local warnings
    local previous_adapter

    before_each(function()
      warnings = {}
      previous_adapter = adapter_registry.has_adapter() and adapter_registry.get_adapter() or nil

      adapter_registry.set_adapter({
        notify = function(_, message, level)
          table.insert(warnings, { message = message, level = level })
        end,
      })
    end)

    after_each(function()
      adapter_registry.set_adapter(previous_adapter)
    end)

    it("warns when a required property is missing", function()
      -- Type "wip" has requires_wip_limit = true
      local column = make_column("In Progress", "wip", {})

      ColumnTypeResolver.validate_requirements(column, sample_config)

      assert.equals(1, #warnings)
      assert.equals(
        "Column 'In Progress' of type 'wip' requires wip_limit but none is set",
        warnings[1].message
      )
      assert.equals("warn", warnings[1].level)
    end)

    it("says nothing when the required property is present", function()
      local column = make_column("In Progress", "wip", { wip_limit = 5 })

      ColumnTypeResolver.validate_requirements(column, sample_config)

      assert.same({}, warnings)
    end)

    it("says nothing for a column with no type", function()
      local column = make_column("Random Column", nil, {})

      ColumnTypeResolver.validate_requirements(column, sample_config)

      assert.same({}, warnings)
    end)

    it("says nothing for a type with no requirements", function()
      local column = make_column("Done", "completion", {})

      ColumnTypeResolver.validate_requirements(column, sample_config)

      assert.same({}, warnings)
    end)

    it("warns once per missing requirement", function()
      local test_config = vim.deepcopy(sample_config)
      test_config.column_config.types.multi_req = {
        properties = {},
        requires_wip_limit = true,
        requires_assignee = true
      }

      local column = make_column("Test", "multi_req", {})

      ColumnTypeResolver.validate_requirements(column, test_config)

      assert.equals(2, #warnings)

      local messages = { warnings[1].message, warnings[2].message }
      table.sort(messages)
      assert.same({
        "Column 'Test' of type 'multi_req' requires assignee but none is set",
        "Column 'Test' of type 'multi_req' requires wip_limit but none is set",
      }, messages)
    end)

    it("stays silent when missing_property_requirement is 'none'", function()
      local test_config = vim.deepcopy(sample_config)
      test_config.missing_property_requirement = "none"

      ColumnTypeResolver.validate_requirements(make_column("In Progress", "wip", {}), test_config)

      assert.same({}, warnings)
    end)

    it("raises when missing_property_requirement is 'error'", function()
      local test_config = vim.deepcopy(sample_config)
      test_config.missing_property_requirement = "error"

      local ok, err = pcall(
        ColumnTypeResolver.validate_requirements, make_column("In Progress", "wip", {}), test_config)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find(
        "Column 'In Progress' of type 'wip' requires wip_limit but none is set", 1, true))
      assert.same({}, warnings)
    end)

    it("warns about a type that is not defined in config", function()
      ColumnTypeResolver.validate_requirements(make_column("Odd", "no_such_type", {}), sample_config)

      assert.equals(1, #warnings)
      assert.equals(
        "Column 'Odd' references type 'no_such_type' which is not defined in config",
        warnings[1].message
      )
      assert.equals("warn", warnings[1].level)
    end)

    it("does not raise when no adapter is registered", function()
      adapter_registry.set_adapter(nil)

      assert.has_no.errors(function()
        ColumnTypeResolver.validate_requirements(make_column("In Progress", "wip", {}), sample_config)
      end)
    end)
  end)

  describe("get_type_triggers()", function()
    it("returns trigger lists from type definition", function()
      local type_def = sample_config.column_config.types.completion
      local result = ColumnTypeResolver.get_type_triggers(type_def)

      assert.is_not_nil(result)
      assert.is_not_nil(result.on_entry)
      assert.equals(1, #result.on_entry)
      assert.equals("timestamp", result.on_entry[1].name)
      assert.equals("kanban-md.triggers", result.on_entry[1].module)
    end)

    it("returns empty table when type has no triggers", function()
      local type_def = sample_config.column_config.types.wip
      local result = ColumnTypeResolver.get_type_triggers(type_def)

      assert.is_not_nil(result)
      assert.equals("table", type(result))
    end)

    it("handles nil type definition", function()
      local result = ColumnTypeResolver.get_type_triggers(nil)

      assert.is_not_nil(result)
      assert.equals("table", type(result))
      -- Should return empty table
    end)

    it("returns complete trigger structure with all event types", function()
      -- Create a type with multiple event triggers
      local type_def = {
        triggers = {
          on_entry = {
            { module = "test", function_name = "entry_fn", name = "entry" }
          },
          on_exit = {
            { module = "test", function_name = "exit_fn", name = "exit" }
          },
          on_update = {
            { module = "test", function_name = "update_fn", name = "update" }
          }
        }
      }

      local result = ColumnTypeResolver.get_type_triggers(type_def)

      assert.is_not_nil(result.on_entry)
      assert.is_not_nil(result.on_exit)
      assert.is_not_nil(result.on_update)
      assert.equals("entry", result.on_entry[1].name)
      assert.equals("exit", result.on_exit[1].name)
      assert.equals("update", result.on_update[1].name)
    end)

    it("handles type definition with empty triggers table", function()
      local type_def = { triggers = {} }
      local result = ColumnTypeResolver.get_type_triggers(type_def)

      assert.is_not_nil(result)
      assert.equals("table", type(result))
    end)
  end)

  describe("Edge cases and error handling", function()
    it("handles column names with special characters", function()
      local markdown_config = {}
      local result = ColumnTypeResolver.resolve_type("__ARCHIVE__", markdown_config, sample_config)
      -- Should not crash, returns nil (no pattern matches)
      assert.is_nil(result)
    end)

    it("handles very long column names", function()
      local long_name = string.rep("Long Column Name ", 100)
      local markdown_config = {}
      local result = ColumnTypeResolver.resolve_type(long_name, markdown_config, sample_config)
      assert.is_nil(result) -- No match
    end)

    it("handles patterns with Lua pattern special characters", function()
      -- Create config with pattern containing Lua special chars
      local test_config = vim.deepcopy(sample_config)
      test_config.column_config.types.special = {
        properties = { test = true },
        patterns = { "test%.done" } -- . is special in Lua patterns
      }

      local result = ColumnTypeResolver.resolve_type("test.done", {}, test_config)
      assert.equals("special", result)
    end)

    it("handles circular property references gracefully", function()
      -- This shouldn't happen but test defensive coding
      local markdown_props = { a = "value" }
      local result = ColumnTypeResolver.merge_properties("Test", markdown_props, "completion", sample_config)
      -- Should complete without infinite loop
      assert.is_not_nil(result)
    end)

    it("handles numeric column names", function()
      local result = ColumnTypeResolver.resolve_type("123", {}, sample_config)
      assert.is_nil(result)
    end)

    it("handles empty string column name", function()
      local result = ColumnTypeResolver.resolve_type("", {}, sample_config)
      assert.is_nil(result)
    end)

    it("preserves property order during merge", function()
      local markdown_props = { z_prop = "z", a_prop = "a", m_prop = "m" }
      local result = ColumnTypeResolver.merge_properties("Test", markdown_props, nil, sample_config)

      -- All properties should be present
      assert.equals("z", result.z_prop)
      assert.equals("a", result.a_prop)
      assert.equals("m", result.m_prop)
    end)
  end)
end)
