-- tests/unit/persist_card_ids_e2e_spec.lua
-- Regression tests for PLAN-config-fixes.md Task 2:
-- "Persist card IDs end-to-end when persist_card_ids is enabled".
--
-- write_task() (writer_mixin.lua) is the single source of truth for whether a
-- card id gets written: it writes `task.properties.id or task.id` when the
-- effective persist_card_ids is true, and leaves an authored properties.id
-- untouched (never regenerated) when it is false. Card:new() also gets a
-- parse-time fallback id (mirroring Board:new/Column:new) so that even the
-- pure-library path (no setup(), no class-level ULID/hash trigger) always has
-- an obj.id to fall back on.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local test_setup = require('helpers.setup')

local function write(board)
  return table.concat(board:write(), "\n")
end

describe("persist_card_ids end-to-end (plan Task 2)", function()
  describe("board-file persist_card_ids: true, pure-library path (no setup())", function()
    it("writes a stable id: property for every card", function()
      local board = Board:new()
      board:parse(table.concat({
        "# B",
        "<!-- kanban:config persist_card_ids: true -->",
        "",
        "###### Todo",
        "",
        "- First task",
        "- Second task",
        "",
        "###### Done",
        "",
        "- Finished task",
        "",
      }, "\n"))

      local out = write(board)

      -- Every card must have gained an id: property, and each must be
      -- distinct (Card:new's fallback id generator must not collide even
      -- though all three cards are created within the same os.time() second).
      local ids = {}
      for id in out:gmatch("id: (%S-) %-%->") do
        table.insert(ids, id)
      end
      assert.are.equal(3, #ids, "expected an id: property for every card, got: " .. out)
      assert.are_not.equal(ids[1], ids[2])
      assert.are_not.equal(ids[2], ids[3])
      assert.are_not.equal(ids[1], ids[3])
    end)

    it("keeps ids stable across a second parse -> write round trip", function()
      local board = Board:new()
      board:parse(table.concat({
        "# B",
        "<!-- kanban:config persist_card_ids: true -->",
        "",
        "###### Todo",
        "",
        "- First task",
        "- Second task",
        "",
        "###### Done",
        "",
        "- Finished task",
        "",
      }, "\n"))

      local first_write = write(board)

      local board2 = Board:new()
      board2:parse(first_write)
      local second_write = write(board2)

      assert.are.equal(first_write, second_write, "second round trip must not change the persisted ids")

      -- Belt-and-braces: the ids read back from markdown must have landed in
      -- properties.id and must be what write_task used, not fresh fallback
      -- ids -- i.e. properties.id (authored/persisted) wins over regenerating.
      local todo2 = board2:get_column_by_name("Todo")
      for _, card in ipairs(todo2.cards) do
        assert.is_not_nil(card.properties.id)
        assert.are.equal(card.properties.id, card.id)
      end
    end)
  end)

  describe("user-authored ids survive with persist_card_ids off", function()
    it("round-trips an authored id verbatim even though persist_card_ids is false", function()
      local board = Board:new()
      board:parse(table.concat({
        "# B",
        "<!-- kanban:config persist_card_ids: false -->",
        "",
        "###### Todo",
        "",
        "- A task <!-- id: my-authored-id -->",
        "",
        "###### Done",
        "",
      }, "\n"))

      local out = write(board)
      assert.is_truthy(out:find("id: my%-authored%-id", 1, false), "authored id must survive with persist_card_ids: false")

      -- Second round trip: still there, unchanged.
      local board2 = Board:new()
      board2:parse(out)
      local todo2 = board2:get_column_by_name("Todo")
      assert.are.equal("my-authored-id", todo2.cards[1].properties.id)
    end)
  end)

  describe("pure-library fallback ids (no setup())", function()
    it("assigns a non-nil id to every card created without setup()", function()
      local card = Card:new(nil, "Some task", {})
      assert.is_not_nil(card.id)
    end)

    it("never produces duplicate ids across many cards created rapidly", function()
      local seen = {}
      local duplicate = nil
      for i = 1, 200 do
        local card = Card:new(nil, "Task " .. i, {})
        if seen[card.id] then
          duplicate = card.id
          break
        end
        seen[card.id] = true
      end
      assert.is_nil(duplicate, "fallback id generator produced a duplicate: " .. tostring(duplicate))
    end)
  end)

  describe("id_triggers sync cannot diverge from the persisted canonical id", function()
    local config = require('kanban-md.config')

    after_each(function()
      config.reset()
    end)

    it("keeps a single consistent id when auto_id + persist_card_ids are both enabled via setup()", function()
      local kanban_cli = test_setup.setup({ auto_id = true, persist_card_ids = true })
      local board = kanban_cli.Board:new()
      board.title = "Test Board"
      board:add_new_column("Todo")
      local todo = board:get_column_by_name("Todo")

      local card = kanban_cli.Card:new(nil, "Task", {})
      table.insert(todo.cards, card)

      -- id_triggers' on_create sync must agree with card.id -- no split
      -- brain between task.id and task.properties.id.
      assert.are.equal(card.id, card.properties.id)

      local out = write(board)
      assert.is_truthy(out:find("id: " .. card.id, 1, true))
    end)
  end)
end)
