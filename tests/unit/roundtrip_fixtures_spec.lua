-- tests/unit/roundtrip_fixtures_spec.lua
-- Round-trip fidelity tests: parse(write(parse(x))) should produce the same
-- structure as parse(x). See plan Task 10.
--
-- The first block exercises every fixture builder in tests/fixtures/boards.lua
-- (written once to get markdown "x", parsed, re-written, re-parsed) and
-- asserts the two parses agree on title, column names/order, card texts and
-- properties, and board config.
--
-- The second block is the regression cover for four round-trip defects that
-- were once open (PLAN-config-fixes.md Tasks 3-6, fixed in 5cd696f, 99d30fe,
-- 378599b and aaf9d06). They are not triggered by the plain fixtures in
-- tests/fixtures/boards.lua, so each is reproduced here directly from the
-- markdown that used to break it. They were written as pending() cases
-- describing the fixed behaviour, and each fix commit made its own live; they
-- are all live now.
require('polyfills.vim')

local Board = require('kanban-md.board')
local TypeConverter = require('kanban-md.type_converter')
local fixtures = require('fixtures.boards')
local test_setup = require('helpers.setup')

local function to_plain_config(cfg)
  if type(cfg) == "table" and getmetatable(cfg) == TypeConverter then
    return cfg:to_table()
  end
  return cfg or {}
end

-- Snapshot only the pieces the task spec calls out: title, column
-- names/order, card texts and properties, and board config. Column-level
-- config (wip limits, resolved types, etc.) is deliberately out of scope.
local function snapshot(board)
  local snap = {
    title = board.title,
    config = to_plain_config(board.config),
    columns = {},
  }

  for _, column in ipairs(board.columns) do
    local cards = {}
    for _, card in ipairs(column.cards) do
      table.insert(cards, {
        text = card.text,
        properties = to_plain_config(card.properties),
      })
    end
    table.insert(snap.columns, { name = column.name, cards = cards })
  end

  return snap
end

local function assert_round_trips(x)
  local parsed1 = Board:new()
  parsed1:parse(x)

  local written = table.concat(parsed1:write(), "\n")

  local parsed2 = Board:new()
  parsed2:parse(written)

  assert.are.same(snapshot(parsed1), snapshot(parsed2))

  return parsed1, parsed2, written
end

describe("Round-trip fidelity: parse(write(parse(x))) == parse(x)", function()
  describe("fixture boards (tests/fixtures/boards.lua)", function()
    for name, build in pairs(fixtures) do
      it("round-trips '" .. name .. "' without structural drift", function()
        local fixture_board = build()
        local x = table.concat(fixture_board:write(), "\n")

        assert_round_trips(x)
      end)
    end
  end)

  describe("regressions: round-trip defects that were once open", function()
    it("does not inject resolved column-type config into markdown (plan Task 3)", function()
      test_setup.with_config({
        column_config = {
          types = {
            completion = {
              properties = { is_completion_state = true },
              patterns = { "done" },
            },
          },
        },
      }, function()
        local x = "# B3\n\n###### Todo\n\n- A task\n\n###### Done\n"

        local parsed1, _, written = assert_round_trips(x)

        -- Only authored config round-trips: the type-derived comment the
        -- writer used to inject must not appear in the output.
        assert.is_nil(written:find("column:config", 1, true))
        assert.is_true(parsed1.columns[2].name == "Done")
      end)
    end)

    it("keeps multiline task property comments (plan Task 4)", function()
      local x = table.concat({
        "# B4",
        "",
        "###### Todo",
        "",
        "- A task",
        "<!--",
        "complexity: 5",
        "assignee: alice",
        "-->",
        "",
        "###### Done",
        "",
      }, "\n")

      local parsed1 = assert_round_trips(x)

      local card = parsed1.columns[1].cards[1]
      -- Properties from the multiline comment are attached to the preceding
      -- card and survive the round trip; the parser used to drop them.
      assert.are.equal(5, card.properties.complexity)
      assert.are.equal("alice", card.properties.assignee)
    end)

    it("preserves unknown __SPECIAL__ sections without leaking their cards (plan Task 5)", function()
      local x = table.concat({
        "# B5",
        "",
        "###### Todo",
        "",
        "- Task A",
        "",
        "###### __NOTES__",
        "",
        "- Some note",
        "",
        "###### Done",
        "",
      }, "\n")

      local parsed1, _, written = assert_round_trips(x)

      -- "Task A" stays the only card in Todo, and the __NOTES__ section keeps
      -- both its heading and its content: it used to be absorbed into Todo,
      -- taking its list items with it.
      assert.are.equal(2, #parsed1.columns)
      assert.are.equal(1, #parsed1.columns[1].cards)
      assert.are.equal("Task A", parsed1.columns[1].cards[1].text)
      assert.is_not_nil(written:find("###### __NOTES__", 1, true))
      assert.is_not_nil(written:find("- Some note", 1, true))
    end)

    it("keeps the board config comment when the file has no H1 title (plan Task 6)", function()
      local x = "<!-- kanban:config wip_limit: 5 -->\n\n###### Todo\n\n- Task\n\n###### Done\n"

      local parsed1 = assert_round_trips(x)

      -- wip_limit survives the round trip even without a title block.
      assert.are.equal(5, parsed1.config.wip_limit)
    end)

    it("board config round-trips correctly when a title is present (plan Task 6)", function()
      local x = "# Board Title\n<!-- kanban:config wip_limit: 5 -->\n\n###### Todo\n\n- Task\n\n###### Done\n"

      local parsed1 = assert_round_trips(x)

      -- Config should be preserved with title present
      assert.are.equal(5, parsed1.config.wip_limit)
      assert.are.equal("Board Title", parsed1.title)
    end)
  end)

  describe("plain HTML comments outside columns", function()
    it("keeps the kanban-board marker above the title", function()
      local x = "<!-- kanban-board -->\n# Board\n<!-- kanban:config wip_limit: 5 -->\n\n###### Todo\n\n- Task\n\n###### Done\n"

      local parsed1, _, written = assert_round_trips(x)

      assert.are.equal("<!-- kanban-board -->", written:match("^[^\n]*"))
      assert.are.equal(5, parsed1.config.wip_limit)
      assert.are.equal("Board", parsed1.title)
    end)

    it("keeps the kanban-board marker below the title", function()
      local x = "# Board\n<!-- kanban-board -->\n\n###### Todo\n\n- Task\n"

      local parsed1, _, written = assert_round_trips(x)

      assert.is_not_nil(written:find("<!-- kanban-board -->", 1, true))
      assert.are.equal(1, #parsed1.columns[1].cards)
    end)

    it("keeps multi-line comments outside columns verbatim", function()
      local x = "# Board\n<!--\nA note\n###### Not a column\n-->\n\n###### Todo\n\n- Task\n"

      local parsed1, _, written = assert_round_trips(x)

      assert.is_not_nil(written:find("<!--\nA note\n###### Not a column\n-->", 1, true))
      assert.are.equal(1, #parsed1.columns)
    end)

    it("still attaches comments inside a column to the card", function()
      local x = "# Board\n\n###### Todo\n\n- Task\n<!-- complexity: 2 -->\n"

      local parsed1, _, written = assert_round_trips(x)

      assert.are.equal(2, parsed1.columns[1].cards[1].properties.complexity)
      assert.is_nil(written:find("\n<!-- complexity", 1, true))
    end)
  end)
end)
