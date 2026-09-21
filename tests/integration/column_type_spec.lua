require('polyfills.vim')
local Parser = require("kanban-md.parser")
local Board = require("kanban-md.board")
local Config = require("kanban-md.config")
local singletons = require("helpers.singletons")

describe("Column Type System Integration", function()
  local restore_config

  before_each(function()
    -- Config.setup() merges, so restoring by merging the old config back would
    -- leave every column type this spec declares registered for the rest of the
    -- run. Snapshot and reset instead.
    restore_config = singletons.snapshot_config()
    Config.reset()

    -- Set up test configuration
    Config.setup({
      column_config = {
        types = {
          completion = {
            properties = {
              is_completion_state = true,
              auto_archive_days = 30
            },
            triggers = {
              -- A module that exists and exports these factories: the
              -- registration path require()s the module and calls the named
              -- field, so a placeholder name here would make every parse of a
              -- completion column raise.
              on_entry = {
                { module = "fixtures.type_triggers", function_name = "record_entry", name = "record_entry" }
              },
              on_exit = {
                { module = "fixtures.type_triggers", function_name = "record_exit", name = "record_exit" }
              }
            },
            patterns = { "done", "complete", "finished" }
          },
          wip = {
            properties = {
              is_active_state = true,
              default_complexity = 5
            },
            requires_wip_limit = true,
            patterns = { "progress", "active", "doing" }
          },
          blocked = {
            properties = {
              is_blocked_state = true,
              auto_escalate_days = 3
            },
            patterns = { "blocked", "waiting", "parked" }
          },
          archive = {
            properties = {
              is_archive_state = true,
              read_only = true
            },
            patterns = { "__archive__" }
          }
        },
        definitions = {
          ["Done"] = { type = "completion", wip_limit = 10 },
          ["Completed"] = { type = "completion" },
          ["In Progress"] = { type = "wip", wip_limit = 5 },
          ["Blocked Items"] = { type = "blocked" }
        }
      },
      missing_property_requirement = "warning"
    })
  end)

  after_each(function()
    restore_config()
  end)

  describe("Pattern-based type resolution", function()
    it("resolves type from pattern match in column name", function()
      local content = [[
# Test Board

###### Done Tasks
- Task 1
- Task 2
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("Done Tasks", column.name)
      assert.are.equals("completion", column.type)
      assert.is_true(column.config.is_completion_state)
      assert.are.equals(30, column.config.auto_archive_days)
    end)

    it("matches pattern anywhere in column name (case-sensitive)", function()
      local content = [[
# Test Board

###### In Progress Tasks
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("In Progress Tasks", column.name)
      assert.are.equals("wip", column.type)
      assert.is_true(column.config.is_active_state)
    end)

    it("does not match partial patterns incorrectly", function()
      local content = [[
# Test Board

###### Progressing
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Should match "progress" pattern from "wip" type
      assert.are.equals("wip", column.type)
    end)

    it("returns nil type when no pattern matches", function()
      local content = [[
# Test Board

###### Random Column Name
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.is_nil(column.type)
    end)
  end)

  describe("Explicit type in markdown", function()
    it("uses explicit type from markdown config", function()
      local content = [[
# Test Board

###### My Custom Column
<!-- config type: wip, wip_limit: 3 -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("wip", column.type)
      assert.is_true(column.config.is_active_state)
      assert.are.equals(3, column.config.wip_limit)
    end)

    it("explicit type overrides pattern matching", function()
      local content = [[
# Test Board

###### Done Tasks
<!-- config type: wip -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Column name matches "done" pattern (completion type)
      -- But explicit type should override
      assert.are.equals("wip", column.type)
      assert.is_true(column.config.is_active_state)
      assert.is_nil(column.config.is_completion_state)
    end)

    it("explicit type overrides definition-based type", function()
      local content = [[
# Test Board

###### Done
<!-- config type: blocked -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- "Done" has definition mapping to "completion"
      -- But explicit type should override
      assert.are.equals("blocked", column.type)
      assert.is_true(column.config.is_blocked_state)
    end)
  end)

  describe("Definition-based type resolution", function()
    it("resolves type from column definition", function()
      local content = [[
# Test Board

###### Done
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("completion", column.type)
      assert.is_true(column.config.is_completion_state)
      assert.are.equals(10, column.config.wip_limit) -- from definition
    end)

    it("definition type overrides pattern matching", function()
      local content = [[
# Test Board

###### Blocked Items
<!-- config custom_prop: value -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Column name matches "blocked" pattern
      -- Definition also maps to "blocked" type
      -- Should resolve to "blocked" (consistent but tests definition priority)
      assert.are.equals("blocked", column.type)
    end)

    it("uses definition properties in addition to type properties", function()
      local content = [[
# Test Board

###### In Progress
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Definition: "In Progress" -> type: wip, wip_limit: 5
      assert.are.equals("wip", column.type)
      assert.is_true(column.config.is_active_state) -- from type
      assert.are.equals(5, column.config.wip_limit) -- from definition
    end)
  end)

  describe("Property merging", function()
    it("merges type, definition, and markdown properties with correct priority", function()
      local content = [[
# Test Board

###### Done
<!-- config auto_archive_days: 7, custom_prop: test -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Type: is_completion_state = true, auto_archive_days = 30
      -- Definition: wip_limit = 10
      -- Markdown: auto_archive_days = 7, custom_prop = test
      assert.are.equals("completion", column.type)
      assert.is_true(column.config.is_completion_state) -- from type
      assert.are.equals(10, column.config.wip_limit) -- from definition
      assert.are.equals(7, column.config.auto_archive_days) -- markdown overrides type
      assert.are.equals("test", column.config.custom_prop) -- from markdown
    end)

    it("markdown properties override all other sources", function()
      local content = [[
# Test Board

###### In Progress
<!-- config is_active_state: false, wip_limit: 10 -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Type has is_active_state = true
      -- Definition has wip_limit = 5
      -- Markdown overrides both
      assert.is_false(column.config.is_active_state)
      assert.are.equals(10, column.config.wip_limit)
    end)

    it("preserves all property types during merge", function()
      local content = [[
# Test Board

###### Custom
<!-- config type: wip, number_val: 42, bool_val: true, string_val: test -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals(42, column.config.number_val)
      assert.is_true(column.config.bool_val)
      assert.are.equals("test", column.config.string_val)
    end)
  end)

  describe("Backwards compatibility", function()
    it("handles simple config without type system", function()
      local content = [[
# Test Board

###### Todo
<!-- config wip_limit: 5 -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.is_nil(column.type) -- No type matched
      assert.are.equals(5, column.config.wip_limit)
    end)

    it("handles columns without any config", function()
      local content = [[
# Test Board

###### Todo
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("Todo", column.name)
      assert.is_nil(column.type)
      assert.is_not_nil(column.config)
    end)

    it("supports legacy column:config syntax", function()
      local content = [[
# Test Board

###### Done
<!-- column:config wip_limit: 5 -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("completion", column.type)
      assert.are.equals(5, column.config.wip_limit)
    end)

    it("supports new simplified config syntax", function()
      local content = [[
# Test Board

###### Done
<!-- config wip_limit: 5 -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("completion", column.type)
      assert.are.equals(5, column.config.wip_limit)
    end)
  end)

  describe("Trigger registration from type definitions", function()
    -- These parse through Board:new(), not Parser:parse(). Parser is the bare
    -- mixin table: it has no auto_register_triggers, so parse() ends without
    -- registering anything and a test of registration would assert nothing.

    local function parse(content)
      local board = Board:new()
      board:parse(content)
      return board
    end

    local BOARD = [[
# Test Board

###### Backlog
- Task 1

###### Done
]]

    it("registers a type's triggers on every column resolving to that type", function()
      local board = parse([[
# Test Board

###### Backlog
- Task 1

###### Done

###### Completed
]])

      local backlog, done, completed = board.columns[1], board.columns[2], board.columns[3]

      assert.are.equals("completion", done.type)
      assert.are.equals("completion", completed.type)

      for _, column in ipairs({ done, completed }) do
        assert.is_function(column.triggers.on_entry.record_entry,
          column.name .. " should have the type's on_entry trigger registered")
        assert.is_function(column.triggers.on_exit.record_exit,
          column.name .. " should have the type's on_exit trigger registered")
      end

      -- Backlog matches no type, so it gets the basic triggers and nothing else
      assert.is_nil(backlog.type)
      assert.is_nil(backlog.triggers.on_entry.record_entry)
      assert.is_nil((backlog.triggers.on_exit or {}).record_exit)
    end)

    it("runs a registered type trigger when a card enters and leaves the column", function()
      local board = parse(BOARD)
      local backlog, done = board.columns[1], board.columns[2]
      local card = backlog.cards[1]

      assert.is_nil(card.properties.entered_via_type)

      board:move_card(card, backlog, done)
      assert.are.equals("Done", card.properties.entered_via_type)

      board:move_card(card, done, backlog)
      assert.are.equals("Done", card.properties.left_via_type)
    end)

    it("registers a type's triggers alongside the basic ones", function()
      local board = parse(BOARD)
      local done = board.columns[2]

      -- auto_timestamp is on by default, so the type's trigger must not
      -- displace the timestamp trigger registered for every column
      assert.is_function(done.triggers.on_entry.add_timestamp)
      assert.is_function(done.triggers.on_entry.record_entry)
    end)

    it("passes a trigger's configured args to its factory", function()
      Config.reset()
      Config.setup({
        column_config = {
          types = {
            completion = {
              triggers = {
                on_entry = {
                  {
                    module = "fixtures.type_triggers",
                    function_name = "stamp",
                    name = "stamp",
                    args = { "stamped_by", "completion" }
                  }
                }
              },
              patterns = { "done" }
            }
          }
        }
      })

      local board = parse(BOARD)
      local backlog, done = board.columns[1], board.columns[2]
      local card = backlog.cards[1]

      board:move_card(card, backlog, done)

      assert.are.equals("completion", card.properties.stamped_by)
    end)

    it("handles types without triggers gracefully", function()
      local board = parse([[
# Test Board

###### Blocked
- Task 1
]])
      local column = board.columns[1]

      assert.are.equals("blocked", column.type)
      assert.is_nil(column.triggers.on_entry.record_entry)
    end)

    it("raises naming the type, trigger and module when the module cannot be loaded", function()
      Config.reset()
      Config.setup({
        column_config = {
          types = {
            completion = {
              triggers = {
                on_entry = {
                  { module = "kanban-md.no_such_triggers", function_name = "record_entry", name = "record_entry" }
                }
              },
              patterns = { "done" }
            }
          }
        }
      })

      local ok, err = pcall(parse, BOARD)

      assert.is_false(ok, "parsing a column whose type names a missing module should raise")
      err = tostring(err)
      assert.is_truthy(err:find(
        "Column type 'completion' requires trigger 'record_entry' but it could not be registered",
        1, true), "unexpected message: " .. err)
      assert.is_truthy(err:find("Failed to load trigger module 'kanban-md.no_such_triggers'", 1, true),
        "message should name the module that failed to load: " .. err)
      assert.is_truthy(err:find("Check that the trigger module 'kanban-md.no_such_triggers' is loaded", 1, true),
        "unexpected message: " .. err)
    end)

    it("raises when the module loads but does not export the named function", function()
      Config.reset()
      Config.setup({
        column_config = {
          types = {
            completion = {
              triggers = {
                on_entry = {
                  { module = "fixtures.type_triggers", function_name = "no_such_function", name = "no_such_function" }
                }
              },
              patterns = { "done" }
            }
          }
        }
      })

      local ok, err = pcall(parse, BOARD)

      assert.is_false(ok, "parsing a column whose type names a missing function should raise")
      err = tostring(err)
      assert.is_truthy(err:find(
        "Column type 'completion' requires trigger 'no_such_function' but it could not be registered",
        1, true), "unexpected message: " .. err)
      assert.is_truthy(err:find("Trigger function 'no_such_function' not found in module 'fixtures.type_triggers'",
        1, true), "message should name the missing function: " .. err)
    end)
  end)

  describe("Special column names", function()
    it("handles __ARCHIVE__ special column with archive type", function()
      local content = [[
# Test Board

###### __ARCHIVE__
- Archived task
]]

      local board = Parser:parse(content)
      local column = board.archive  -- Archive is stored separately, not in columns array

      assert.is_not_nil(column, "Archive column should exist")
      assert.are.equals("__ARCHIVE__", column.name)
      assert.are.equals("archive", column.type)
      assert.is_true(column.config.is_archive_state)
      assert.is_true(column.config.read_only)
    end)

    it("ignores non-column H6 headers starting with __", function()
      local content = [[
# Test Board

###### __NOTES__
<!-- This should be treated as markdown, not a column -->
]]

      local board = Parser:parse(content)

      -- Headers starting with __ (except __ARCHIVE__) should not create columns
      assert.are.equals(0, #board.columns, "Should have no regular columns")
    end)
  end)

  describe("Multiple columns with different types", function()
    it("correctly types multiple columns in same board", function()
      local content = [[
# Test Board

###### Backlog
- Task 1

###### In Progress
<!-- config wip_limit: 3 -->
- Task 2

###### Done
- Task 3

###### Blocked
- Task 4
]]

      local board = Parser:parse(content)

      assert.are.equals(4, #board.columns)

      -- Backlog - no type match
      assert.are.equals("Backlog", board.columns[1].name)
      assert.is_nil(board.columns[1].type)

      -- In Progress - from definition
      assert.are.equals("In Progress", board.columns[2].name)
      assert.are.equals("wip", board.columns[2].type)
      assert.are.equals(3, board.columns[2].config.wip_limit)

      -- Done - from definition
      assert.are.equals("Done", board.columns[3].name)
      assert.are.equals("completion", board.columns[3].type)

      -- Blocked - from pattern
      assert.are.equals("Blocked", board.columns[4].name)
      assert.are.equals("blocked", board.columns[4].type)
    end)
  end)

  describe("Error cases and warnings", function()
    it("handles invalid type reference gracefully", function()
      local content = [[
# Test Board

###### Custom
<!-- config type: nonexistent_type -->
- Task 1
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Type doesn't exist - should not crash
      -- Type will be set but validation may warn
      assert.are.equals("nonexistent_type", column.type)
    end)

    it("handles missing required properties with validation", function()
      local content = [[
# Test Board

###### In Progress
<!-- config is_active_state: true -->
- Task 1
]]

      -- Type "wip" requires wip_limit but it's not set
      -- Should parse successfully but validation should warn
      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("wip", column.type)
      -- Missing wip_limit - validation should catch this (tested separately)
    end)
  end)

  describe("Complex real-world scenarios", function()
    it("handles complex board with all type resolution methods", function()
      local content = [[
# Project Board

###### Backlog
<!-- config wip_limit: 20 -->
- Future task

###### Ready
<!-- config type: wip, wip_limit: 5 -->
- Ready task

###### In Progress
- Current task

###### Code Review
<!-- config type: wip, wip_limit: 3 -->
- Review task

###### Blocked Items
- Blocked task

###### Finished Tasks
<!-- config auto_archive_days: 14 -->
- Completed task

###### __ARCHIVE__
- Old task
]]

      local board = Parser:parse(content)

      assert.are.equals(6, #board.columns)

      -- Backlog: no type (no pattern match)
      assert.is_nil(board.columns[1].type)
      assert.are.equals(20, board.columns[1].config.wip_limit)

      -- Ready: explicit type
      assert.are.equals("wip", board.columns[2].type)
      assert.are.equals(5, board.columns[2].config.wip_limit)

      -- In Progress: definition-based
      assert.are.equals("wip", board.columns[3].type)
      assert.are.equals(5, board.columns[3].config.wip_limit) -- from definition

      -- Code Review: explicit type
      assert.are.equals("wip", board.columns[4].type)

      -- Blocked Items: definition-based
      assert.are.equals("blocked", board.columns[5].type)

      -- Finished Tasks: pattern match
      assert.are.equals("completion", board.columns[6].type)
      assert.are.equals(14, board.columns[6].config.auto_archive_days)

      -- __ARCHIVE__: pattern match (stored separately in board.archive)
      assert.is_not_nil(board.archive)
      assert.are.equals("archive", board.archive.type)
      assert.is_true(board.archive.config.read_only)
    end)

    it("handles round-trip parsing (parse -> write -> parse)", function()
      local content = [[
# Test Board

###### Done
<!-- config wip_limit: 5 -->
- Task 1
]]

      local board1 = Parser:parse(content)
      local column1 = board1.columns[1]

      -- First parse
      assert.are.equals("completion", column1.type)
      assert.are.equals(5, column1.config.wip_limit)
      assert.is_true(column1.config.is_completion_state)

      -- TODO: When writer is implemented, test round-trip:
      -- local written = Writer.write(board1)
      -- local board2 = Parser:parse(written)
      -- assert.are.equals("completion", board2.columns[1].type)
    end)
  end)

  describe("Edge cases", function()
    it("handles empty board", function()
      local content = "# Empty Board\n"
      local board = Parser:parse(content)

      assert.are.equals(0, #board.columns)
    end)

    it("handles board with only special sections", function()
      local content = [[
# Test Board

###### __ARCHIVE__
- Old task

###### __STATS__
]]

      local board = Parser:parse(content)

      -- At least __ARCHIVE__ should be parsed
      local archive_col = nil
      for _, col in ipairs(board.columns) do
        if col.name == "__ARCHIVE__" then
          archive_col = col
          break
        end
      end

      if archive_col then
        assert.are.equals("archive", archive_col.type)
      end
    end)

    it("handles column names with special characters", function()
      local content = [[
# Test Board

###### Done (v2.0)
- Task
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      -- Should still match "done" pattern
      assert.are.equals("completion", column.type)
    end)

    it("handles very long property lists", function()
      local content = [[
# Test Board

###### Custom
<!-- config type: wip, prop1: val1, prop2: val2, prop3: val3, prop4: val4, prop5: val5, wip_limit: 10 -->
- Task
]]

      local board = Parser:parse(content)
      local column = board.columns[1]

      assert.are.equals("wip", column.type)
      assert.are.equals(10, column.config.wip_limit)
      assert.are.equals("val1", column.config.prop1)
      assert.are.equals("val5", column.config.prop5)
    end)
  end)
end)
