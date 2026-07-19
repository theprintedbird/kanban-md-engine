-- tests/unit/roundtrip_fixtures_spec.lua
-- Round-trip fidelity tests: parse(write(parse(x))) should produce the same
-- structure as parse(x). See plan Task 10.
--
-- The first block exercises every fixture builder in tests/fixtures/boards.lua
-- (written once to get markdown "x", parsed, re-written, re-parsed) and
-- asserts the two parses agree on title, column names/order, card texts and
-- properties, and board config.
--
-- The second block documents four known round-trip defects (see
-- PLAN-config-fixes.md Tasks 3-6). Those defects are NOT triggered by the
-- plain fixtures in tests/fixtures/boards.lua, so they are reproduced here
-- directly from markdown. Each is marked pending() with a comment naming the
-- plan task that fixes it -- once that task lands, delete the pending() call
-- (the assertions below it already describe the expected, fixed, behaviour)
-- and the case becomes a live regression test.
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

  describe("known round-trip defects (pending until their fix task lands)", function()
    it("does not inject resolved column-type config into markdown (plan Task 3)", function()
      pending("Plan Task 3: parser/writer merge resolved column_config type " ..
        "properties into column.config, and the writer serialises that " ..
        "merged layer, so a pattern-matched type injects an unauthored " ..
        "'<!-- column:config, is_completion_state: true -->' comment on write.")

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

        -- Expected once Task 3 lands: only authored config round-trips: the
        -- injected type-derived comment must not appear in the output.
        assert.is_nil(written:find("column:config", 1, true))
        assert.is_true(parsed1.columns[2].name == "Done")
      end)
    end)

    it("keeps multiline task property comments (plan Task 4)", function()
      pending("Plan Task 4: parser.lua's multiline comment completion " ..
        "branch only fires when pending_config was already set by the " ..
        "single-line path, so a multiline <!-- ... --> comment after a " ..
        "card is silently discarded along with its properties.")

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
      -- Expected once Task 4 lands: properties from the multiline comment
      -- are attached to the preceding card and survive the round trip.
      assert.are.equal(5, card.properties.complexity)
      assert.are.equal("alice", card.properties.assignee)
    end)

    it("preserves unknown __SPECIAL__ sections without leaking their cards (plan Task 5)", function()
      pending("Plan Task 5: parser.lua treats any H6 matching '^__' that " ..
        "isn't __ARCHIVE__ as neither a column nor markdown -- the header " ..
        "line is dropped on write, and because current_column isn't reset " ..
        "its cards are appended to the previous column instead.")

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

      local parsed1 = assert_round_trips(x)

      -- Expected once Task 5 lands: "Task A" stays the only card in Todo,
      -- and the __NOTES__ section (and its content) is preserved verbatim
      -- rather than being absorbed into Todo or vanishing entirely.
      assert.are.equal(1, #parsed1.columns[1].cards)
      assert.are.equal("Task A", parsed1.columns[1].cards[1].text)
    end)

    it("keeps the board config comment when the file has no H1 title (plan Task 6)", function()
      pending("Plan Task 6: write_from_blocks() only emits the " ..
        "kanban:config comment inside the TITLE block branch, so a " ..
        "file with a config comment but no '# Title' loses that comment " ..
        "on write even though board.config parsed correctly.")

      local x = "<!-- kanban:config wip_limit: 5 -->\n\n###### Todo\n\n- Task\n\n###### Done\n"

      local parsed1 = assert_round_trips(x)

      -- Expected once Task 6 lands: wip_limit survives the round trip even
      -- without a title block.
      assert.are.equal(5, parsed1.config.wip_limit)
    end)
  end)
end)
