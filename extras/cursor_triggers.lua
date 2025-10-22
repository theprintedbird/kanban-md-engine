-- Cursor positioning trigger for newly created cards
-- Marks cards with _cursor_target flag when they enter a column
-- The flag is used by commands to position the cursor after writing to buffer

-- Create cursor target marking trigger
-- When a card enters a column, mark it with _cursor_target = true
-- This flag will be detected by commands after writing to position the cursor
-- Note: Config checking is done during trigger registration in Board:register_basic_triggers()
local function create_cursor_target_trigger()
  return function(self, context)
    -- Mark the card for cursor positioning
    local card = context.card or self
    if card and card.properties then
      card.properties._cursor_target = true
    end

    return true
  end
end

return {
  create_cursor_target_trigger = create_cursor_target_trigger,
}
