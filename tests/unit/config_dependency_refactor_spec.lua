require('polyfills.vim')
local config = require("kanban-md.config")

describe("Config Dependency Refactor", function()
  local original_config

  before_each(function()
    -- Save original config
    original_config = vim.deepcopy(config.get())
  end)

  after_each(function()
    -- Restore original config
    config.setup(original_config)
  end)

  describe("get_dependency_mode()", function()
    it("returns false when dependency_validation is false", function()
      config.setup({ dependency_validation = false })
      assert.is_false(config.get_dependency_mode())
    end)

    it("returns false when dependency_validation is 'off'", function()
      config.setup({ dependency_validation = "off" })
      assert.is_false(config.get_dependency_mode())
    end)

    it("returns 'strict' when dependency_validation is true", function()
      config.setup({ dependency_validation = true })
      assert.are.equals("strict", config.get_dependency_mode())
    end)

    it("returns 'strict' when dependency_validation is 'on'", function()
      config.setup({ dependency_validation = "on" })
      assert.are.equals("strict", config.get_dependency_mode())
    end)

    it("returns 'strict' when dependency_validation is 'strict'", function()
      config.setup({ dependency_validation = "strict" })
      assert.are.equals("strict", config.get_dependency_mode())
    end)

    it("returns 'warn' when dependency_validation is 'warn'", function()
      config.setup({ dependency_validation = "warn" })
      assert.are.equals("warn", config.get_dependency_mode())
    end)
  end)

  describe("get_subtask_mode()", function()
    it("returns false when subtask_validation is false", function()
      config.setup({ subtask_validation = false })
      assert.is_false(config.get_subtask_mode())
    end)

    it("returns false when subtask_validation is 'off'", function()
      config.setup({ subtask_validation = "off" })
      assert.is_false(config.get_subtask_mode())
    end)

    it("returns 'strict' when subtask_validation is true", function()
      config.setup({ subtask_validation = true })
      assert.are.equals("strict", config.get_subtask_mode())
    end)

    it("returns 'strict' when subtask_validation is 'on'", function()
      config.setup({ subtask_validation = "on" })
      assert.are.equals("strict", config.get_subtask_mode())
    end)

    it("returns 'strict' when subtask_validation is 'strict'", function()
      config.setup({ subtask_validation = "strict" })
      assert.are.equals("strict", config.get_subtask_mode())
    end)

    it("returns 'warn' when subtask_validation is 'warn'", function()
      config.setup({ subtask_validation = "warn" })
      assert.are.equals("warn", config.get_subtask_mode())
    end)
  end)

  describe("Independent Configuration", function()
    it("allows dependencies to be strict while subtasks are off", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = false
      })
      assert.are.equals("strict", config.get_dependency_mode())
      assert.is_false(config.get_subtask_mode())
    end)

    it("allows subtasks to be strict while dependencies are off", function()
      config.setup({
        dependency_validation = false,
        subtask_validation = "strict"
      })
      assert.is_false(config.get_dependency_mode())
      assert.are.equals("strict", config.get_subtask_mode())
    end)

    it("allows dependencies to be warn while subtasks are strict", function()
      config.setup({
        dependency_validation = "warn",
        subtask_validation = "strict"
      })
      assert.are.equals("warn", config.get_dependency_mode())
      assert.are.equals("strict", config.get_subtask_mode())
    end)

    it("allows both to be enabled with different modes", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = "warn"
      })
      assert.are.equals("strict", config.get_dependency_mode())
      assert.are.equals("warn", config.get_subtask_mode())
    end)
  end)

  describe("normalize_dependency_mode()", function()
    it("normalizes false to false", function()
      assert.is_false(config.normalize_dependency_mode(false))
    end)

    it("normalizes 'off' to false", function()
      assert.is_false(config.normalize_dependency_mode("off"))
    end)

    it("normalizes true to 'strict'", function()
      assert.are.equals("strict", config.normalize_dependency_mode(true))
    end)

    it("normalizes 'on' to 'strict'", function()
      assert.are.equals("strict", config.normalize_dependency_mode("on"))
    end)

    it("normalizes 'strict' to 'strict'", function()
      assert.are.equals("strict", config.normalize_dependency_mode("strict"))
    end)

    it("normalizes 'warn' to 'warn'", function()
      assert.are.equals("warn", config.normalize_dependency_mode("warn"))
    end)

    it("returns false for invalid values", function()
      assert.is_false(config.normalize_dependency_mode("invalid"))
      assert.is_false(config.normalize_dependency_mode(123))
      assert.is_false(config.normalize_dependency_mode(nil))
    end)
  end)
end)
