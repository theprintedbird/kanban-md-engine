-- tests/fixtures/type_triggers.lua
-- A trigger module a column type can name in `column_config.types[*].triggers`.
--
-- Board:register_trigger_from_config() resolves a type's triggers by
-- require()ing the module and calling the named field as a factory, so an
-- end-to-end test of that path needs a module on package.path holding a real
-- factory. tests/ is on the busted lpath, hence "fixtures.type_triggers".
--
-- The triggers record what they saw on the card rather than in an upvalue, so
-- a spec asserts on the card it moved and nothing leaks between examples.

local M = {}

--- on_entry factory: stamps the entered column's name onto the card.
function M.record_entry()
  return function(self, context)
    context.card.properties.entered_via_type = self.name
    return true
  end
end

--- on_exit factory: stamps the departed column's name onto the card.
function M.record_exit()
  return function(self, context)
    context.card.properties.left_via_type = self.name
    return true
  end
end

--- on_entry factory taking arguments: stamps them onto the card.
--- Exercises the `args` list of a trigger configuration.
function M.stamp(key, value)
  return function(self, context)
    context.card.properties[key] = value
    return true
  end
end

return M
