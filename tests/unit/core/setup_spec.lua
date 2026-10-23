-- tests/unit/core/setup_spec.lua
-- Unit tests for lua/kanban-md/core/setup.lua, the platform-agnostic half of
-- setup() that every entry point (cli.lua, the Neovim plugin's init.lua) calls
-- once it has an adapter. Reached indirectly by tests/helpers/setup.lua, but
-- its own contract -- adapter required, adapter registered, config merged, id
-- triggers registered whatever the global auto_id, which the trigger checks
-- itself -- was never asserted directly.
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

      -- Against a key that actually has a default: get_defaults().wip_limit is
      -- nil, so comparing it to the live value asserts nothing.
      assert.equals(config.get_defaults().cycle_time_unit, config.get_value("cycle_time_unit"))
      assert.is_not_nil(config.get_value("cycle_time_unit"))
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

    it("registers them even when the global auto_id is off", function()
      -- A board file may still turn auto_id on, and only a registered trigger
      -- can honour that; the trigger checks auto_id itself.
      core_setup.setup({ auto_id = false }, stub_adapter())

      for name, class in pairs(CLASSES) do
        assert.is_function(id_trigger_on(class), name .. " has no generate_ulid_id trigger with auto_id off")
      end
    end)

    it("leaves new cards on Card's own fallback id when auto_id is off", function()
      core_setup.setup({ auto_id = false }, stub_adapter())

      -- Card:new() has a counter-based fallback of its own; with no board to
      -- consult, the trigger reads the global auto_id and steps aside, so
      -- that fallback is what a new card gets, not a ULID.
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

  describe("board-file auto_id", function()
    local ULID_CARD = "^card_[0-9A-HJKMNP-TV-Z]+$"
    local FALLBACK_CARD = "^card_%d+_%d+$"

    local function parse_with_auto_id(value)
      local board = Board:new()
      board:parse(table.concat({
        "# B",
        "<!-- kanban:config auto_id: " .. tostring(value) .. " -->",
        "",
        "###### Todo",
        "",
        "- A card",
        "",
      }, "\n"))
      return board
    end

    it("turns ULIDs on for parsed cards when the global auto_id is off", function()
      core_setup.setup({ auto_id = false }, stub_adapter())

      local board = parse_with_auto_id(true)

      assert.matches(ULID_CARD, board.columns[1].cards[1].id)
    end)

    it("turns ULIDs off for parsed cards when the global auto_id is on", function()
      core_setup.setup({ auto_id = true }, stub_adapter())

      local board = parse_with_auto_id(false)

      assert.matches(FALLBACK_CARD, board.columns[1].cards[1].id)
    end)

    it("gives the id to the card, not to the board in its create context", function()
      core_setup.setup(nil, stub_adapter())
      local board = Board:new()
      local board_id = board.id

      local card = Card:new(nil, "Mine", nil, { board = board })

      assert.equals(board_id, board.id)
      assert.matches(ULID_CARD, card.id)
    end)
  end)

  -- SPEC.md 4.3: where each identifier is kept. Board and column ids live
  -- only on the in-memory object; only a card id can reach the file.
  describe("identifier storage", function()
    local ULID_BOARD = "^board_[0-9A-HJKMNP-TV-Z]+$"
    local ULID_COLUMN = "^column_[0-9A-HJKMNP-TV-Z]+$"

    local function to_text(output)
      return type(output) == "table" and table.concat(output, "\n") or output
    end

    local function parse(lines)
      local board = Board:new()
      board:parse(table.concat(lines, "\n"))
      return board
    end

    it("generates the board id in Board:new(), not from the file", function()
      core_setup.setup(nil, stub_adapter())

      local board = parse({
        "# B",
        "<!-- kanban:config id: board_authored -->",
        "",
        "###### Todo",
        "",
      })

      assert.matches(ULID_BOARD, board.id)
      assert.equals("board_authored", board.config.id)
    end)

    it("falls back to a timestamp board id when auto_id is off", function()
      core_setup.setup({ auto_id = false }, stub_adapter())

      assert.matches("^board_%d+$", Board:new().id)
    end)

    it("gives parsed columns positional ids, and the archive __ARCHIVE__", function()
      core_setup.setup(nil, stub_adapter())

      local board = parse({
        "# B",
        "",
        "###### Todo",
        "<!-- column:config id: column_authored -->",
        "",
        "###### Done",
        "",
        "###### __ARCHIVE__",
        "",
      })

      assert.equals("column_1", board.columns[1].id)
      assert.equals("column_2", board.columns[2].id)
      assert.equals("__ARCHIVE__", board.archive.id)
      assert.equals("column_authored", board.columns[1].config.id)
    end)

    it("renumbers parsed column ids when the columns are reordered", function()
      core_setup.setup(nil, stub_adapter())

      local board = parse({ "# B", "", "###### Done", "", "###### Todo", "" })

      assert.equals("Todo", board.columns[2].name)
      assert.equals("column_2", board.columns[2].id)
    end)

    it("gives a column added by name a ULID, or its name when auto_id is off", function()
      core_setup.setup(nil, stub_adapter())
      assert.matches(ULID_COLUMN, Board:new():add_column("Todo").id)

      core_setup.setup({ auto_id = false }, stub_adapter())
      assert.equals("Todo", Board:new():add_column("Todo").id)
    end)

    it("writes neither the board id nor any column id", function()
      core_setup.setup(nil, stub_adapter())
      local board = parse({ "# B", "", "###### Todo", "", "- A card", "" })
      board:add_new_column("Added")

      local text = to_text(board:write())

      assert.is_nil(text:find(board.id, 1, true))
      assert.is_nil(text:find("column_", 1, true))
    end)

    it("takes a card id authored in the file as the card's id", function()
      core_setup.setup(nil, stub_adapter())

      local board = parse({ "# B", "", "###### Todo", "", "- A card <!-- id: card_authored -->", "" })

      assert.equals("card_authored", board.columns[1].cards[1].id)
    end)

    it("keeps an authored card id on write even with persist_card_ids off", function()
      core_setup.setup({ persist_card_ids = false }, stub_adapter())

      local board = parse({ "# B", "", "###### Todo", "", "- A card <!-- id: card_authored -->", "" })

      assert.truthy(to_text(board:write()):find("id: card_authored", 1, true))
    end)
  end)
end)
