-- tests/unit/property_quoting_spec.lua
-- Quoted property values (SPEC.md 7.6): the parser reads a quoted value as a
-- string with no type conversion, and the writer quotes a string whenever it
-- would not read back unchanged without quotes. Array elements follow the
-- same rules, judged against the array's own separators. Each half is useless
-- without the other, so the round trip is the test that matters.

require('polyfills.vim')
_G._TEST = true

local Board = require("kanban-md.board")
local ParserMixin = require("kanban-md.parser")
local WriterMixin = require("kanban-md.writer_mixin")
local adapter_registry = require("kanban-md.adapter_registry")

local parse_properties = ParserMixin._private.parse_properties
local format_property_value = WriterMixin._private.format_property_value

describe("Quoted property values", function()
  describe("parsing", function()
    it("strips double or single quotes and keeps the value a string", function()
      local props = parse_properties([[a: "42", b: '42', c: "true", d: "2024-03-04", e: "1.5"]])

      assert.are.same({ a = "42", b = "42", c = "true", d = "2024-03-04", e = "1.5" }, props)
    end)

    it("keeps whitespace inside the quotes", function()
      local props = parse_properties([[task_indent: "  ", note: " padded "]])

      assert.are.equals("  ", props.task_indent)
      assert.are.equals(" padded ", props.note)
    end)

    it("reads an empty pair of quotes as the empty string", function()
      assert.are.same({ a = "", b = "x" }, parse_properties([[a: "", b: x]]))
    end)

    it("treats commas, brackets and key: inside quotes as part of the value", function()
      local props = parse_properties([[title: "one, two", link: "see: here", raw: "[a", n: 3]])

      assert.are.same({ title = "one, two", link = "see: here", raw = "[a", n = 3 }, props)
    end)

    it("ends a quoted value at a space-separated next key", function()
      assert.are.same({ a = "x, y", b = 2 }, parse_properties([[a: "x, y" b: 2]]))
    end)

    it("keeps a quote of the same kind that does not end the value", function()
      assert.are.same({ q = 'say "hi" now', n = 1 }, parse_properties([[q: "say "hi" now", n: 1]]))
    end)

    it("leaves an unclosed quote in the string", function()
      assert.are.same({ a = '"open', b = 2 }, parse_properties([[a: "open, b: 2]]))
    end)

    it("leaves mismatched quotes in the string", function()
      assert.are.same({ a = [["x']] }, parse_properties([[a: "x']]))
    end)

    it("reads a quoted wip_limit as a number via config coercion", function()
      local board = Board:new()
      board:parse({ "# Board", "<!-- kanban:config wip_limit: '7' -->", "###### To Do",
        "<!-- column:config wip_limit: \"3\" -->" })

      assert.are.equals(7, board.config.wip_limit)
      assert.are.equals(3, board.columns[1].config.wip_limit)
    end)
  end)

  describe("writing", function()
    it("leaves a string that reads back unchanged unquoted", function()
      for _, str in ipairs({ "hello world", "In Progress", "https://example.com/a", "a-b", "-5", "x:y", "see: here" }) do
        assert.are.equals(str, format_property_value(str))
      end
    end)

    it("quotes a string that would otherwise read back differently", function()
      local cases = {
        [""] = '""',
        ["  "] = '"  "',
        [" lead"] = '" lead"',
        ["trail "] = '"trail "',
        ["a, b"] = '"a, b"',
        ["then see: here"] = '"then see: here"',
        ["[a]"] = '"[a]"',
        ["a]b"] = '"a]b"',
        ["42"] = '"42"',
        ["1.5"] = '"1.5"',
        ["2024-03-04"] = '"2024-03-04"',
        ["2024-03-04 standup"] = '"2024-03-04 standup"',
        ["true"] = '"true"',
        ["FALSE"] = '"FALSE"',
        ['"quoted"'] = '""quoted""',
        ["'x"] = [["'x"]],
      }

      for str, expected in pairs(cases) do
        assert.are.equals(expected, format_property_value(str), "for " .. string.format("%q", str))
      end
    end)

    it("switches to single quotes when a double quote would end the value early", function()
      assert.are.equals([['say "hi", ok']], format_property_value('say "hi", ok'))
    end)

    it("does not quote a number or boolean", function()
      assert.are.equals("42", format_property_value(42))
      assert.are.equals("true", format_property_value(true))
    end)

    it("warns when no quote character can hold the string", function()
      local messages = {}
      local adapter = { notify = function(_, message, level) table.insert(messages, { message, level }) end }
      local original = adapter_registry._adapter
      adapter_registry.set_adapter(adapter)

      local ok, err = pcall(format_property_value, [[a", b', c]])

      adapter_registry.set_adapter(original)
      assert(ok, err)
      assert.are.same(
        { { [[Property value cannot be written so it reads back unchanged: a", b', c]], "warn" } },
        messages
      )
    end)
  end)

  describe("round trip", function()
    local function round_trip(value)
      local board = Board:new()
      board:parse({ "# Board", "###### To Do", "- Card" })
      board.columns[1].cards[1].properties.value = value
      board.columns[1].cards[1].properties.after = 1

      local reparsed = Board:new()
      reparsed:parse(board:write())
      local props = reparsed.columns[1].cards[1].properties
      return props.value, props.after
    end

    local strings = {
      "", " ", "  ", "\t", " padded ", "a, b", "one,two", "see: here", "a b: c",
      "[a]", "[a, b]", "a[b", "a]b", "42", "007", "1.5", "2024-03-04", "2024-03-04T12:34:50Z",
      "2024-03-04 standup", "true", "False", '"', "'", '""', '"x"', "'x'", '"open', "it's",
      'say "hi"', 'say "hi", ok', 'a" b: c', "plain", "In Progress", "https://example.com/a?b=c",
    }

    for _, str in ipairs(strings) do
      it("preserves " .. string.format("%q", str), function()
        local value, after = round_trip(str)

        assert.are.equals(str, value)
        assert.are.equals(1, after)
      end)
    end

    it("is stable across a second write", function()
      local board = Board:new()
      board:parse({ "# Board", "###### To Do", [[- Card <!-- a: "  ", b: "x, y", c: '7' -->]] })

      local first = board:write()
      local again = Board:new()
      again:parse(first)

      assert.are.same(first, again:write())
      assert.are.equals([[- Card <!-- a: "  ", b: "x, y", c: "7" -->]], first[#first])
    end)
  end)

  describe("array elements", function()
    describe("parsing", function()
      it("strips quotes from an element and keeps what is inside verbatim", function()
        local props = parse_properties([==[tags: ["one, two", 'a]b', " padded ", "", plain], n: 1]==])

        assert.are.same({ tags = { "one, two", "a]b", " padded ", "", "plain" }, n = 1 }, props)
      end)

      it("keeps a quote of the same kind that does not end the element", function()
        assert.are.same({ t = { 'say "hi" now', "x" } }, parse_properties([==[t: ["say "hi" now", x]]==]))
      end)

      it("keeps an unclosed quote in the element", function()
        assert.are.same({ t = { '"open', "b" }, n = 2 }, parse_properties([==[t: ["open, b], n: 2]==]))
      end)

      it("does not convert an element by type", function()
        assert.are.same({ t = { "42", "true", "2024-03-04" } }, parse_properties([==[t: [42, "true", 2024-03-04]]==]))
      end)

      it("drops empty unquoted elements", function()
        assert.are.same({ a = {}, b = {}, c = { "x", "y" } }, parse_properties([==[a: [], b: [ ], c: [x,, y,]]==]))
      end)

      it("keeps a nested bracket pair in one element", function()
        assert.are.same({ t = { "a", "[b, c]" } }, parse_properties([==[t: [a, [b, c]]]==]))
      end)

      it("ends an array at a space-separated next key", function()
        assert.are.same({ t = { "x, y" }, n = 2 }, parse_properties([==[t: ["x, y"] n: 2]==]))
      end)

      it("reads text after the closing bracket as part of an ordinary string", function()
        assert.are.same({ t = "[a] b", n = 1 }, parse_properties([==[t: [a] b, n: 1]==]))
      end)
    end)

    describe("writing", function()
      it("leaves an element that reads back unchanged unquoted", function()
        assert.are.equals("[hello world, 42, true, see: here, it's]",
          format_property_value({ "hello world", "42", "true", "see: here", "it's" }))
      end)

      it("quotes an element that would otherwise read back differently", function()
        local cases = {
          [""] = '[""]',
          [" lead"] = '[" lead"]',
          ["trail "] = '["trail "]',
          ["a, b"] = '["a, b"]',
          ["a]b"] = '["a]b"]',
          ["[a"] = '["[a"]',
          ['"x"'] = '[""x""]',
          ["'x"] = [==[["'x"]]==],
        }

        for str, expected in pairs(cases) do
          assert.are.equals(expected, format_property_value({ str }), "for " .. string.format("%q", str))
        end
      end)

      it("switches to single quotes when a double quote would end the element early", function()
        assert.are.equals([==[['say "hi"]', x]]==], format_property_value({ 'say "hi"]', "x" }))
      end)

      it("warns when no quote character can hold the element", function()
        local messages = {}
        local adapter = { notify = function(_, message, level) table.insert(messages, { message, level }) end }
        local original = adapter_registry._adapter
        adapter_registry.set_adapter(adapter)

        local ok, err = pcall(format_property_value, { [[a", b', c]] })

        adapter_registry.set_adapter(original)
        assert(ok, err)
        assert.are.same(
          { { [[Property value cannot be written so it reads back unchanged: a", b', c]], "warn" } },
          messages
        )
      end)
    end)

    describe("round trip", function()
      local function round_trip(value)
        local board = Board:new()
        board:parse({ "# Board", "###### To Do", "- Card" })
        board.columns[1].cards[1].properties.value = value
        board.columns[1].cards[1].properties.after = 1

        local reparsed = Board:new()
        reparsed:parse(board:write())
        local props = reparsed.columns[1].cards[1].properties
        return props.value, props.after
      end

      local elements = {
        "", " ", "\t", " padded ", "a, b", "one,two", "see: here", "a b: c", "[a]", "[a, b]",
        "a[b", "a]b", "]", "42", "true", "2024-03-04", '"', "'", '""', '"x"', "'x'", '"open',
        "it's", 'say "hi"', 'say "hi", ok', 'x"]', "plain", "In Progress",
      }

      for _, str in ipairs(elements) do
        it("preserves " .. string.format("%q", str) .. " between other elements", function()
          local value, after = round_trip({ "first", str, "last" })

          assert.are.same({ "first", str, "last" }, value)
          assert.are.equals(1, after)
        end)
      end

      it("is stable across a second write", function()
        local board = Board:new()
        board:parse({ "# Board", "###### To Do", [==[- Card <!-- t: ['a, b', " x ", c] -->]==] })

        local first = board:write()
        local again = Board:new()
        again:parse(first)

        assert.are.same(first, again:write())
        assert.are.equals([==[- Card <!-- t: ["a, b", " x ", c] -->]==], first[#first])
      end)
    end)
  end)
end)
