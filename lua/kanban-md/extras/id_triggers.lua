-- ULID-based ID generation triggers for Board, Column, and Card
-- Uses the ulid helper with proper seeding for unique, sortable identifiers

local ulid = require('kanban-md.helpers.ulid')

-- TODO check if this is needed since not Neovim-only library
-- Set up proper time function for Neovim
-- Neovim doesn't have socket.gettime, so we use os.time with millisecond emulation
ulid.set_time_func(function()
  -- os.time() only gives second precision, so we add sub-second component
  -- This is acceptable as ULID's random portion provides uniqueness
  local t = os.time()
  -- Add a small random offset to simulate milliseconds (0-999ms)
  return t + (math.random(0, 999) / 1000)
end)

-- Seed the random generator once on module load
-- Using a time-based seed with additional entropy
math.randomseed(os.time() * math.random(1, 10000))

-- Locate the owning board from the trigger context or the object itself, so
-- config resolution can honour board-file overrides. Returns nil when no board
-- is reachable (e.g. a card/column created standalone before being attached).
local function resolve_board(obj, context)
  if context then
    if type(context.board) == "table" then
      return context.board
    end
    if type(context.column) == "table" and type(context.column.board) == "table" then
      return context.column.board
    end
    if type(context.card) == "table" and type(context.card.column) == "table"
        and type(context.card.column.board) == "table" then
      return context.card.column.board
    end
  end

  if type(obj) == "table" then
    if type(obj.get_config_value) == "function" then
      return obj
    end
    if type(obj.board) == "table" then
      return obj.board
    end
  end

  return nil
end

-- Resolve a config value through the board (board file > plugin config) when a
-- board is reachable, otherwise fall back to the global plugin config.
local function resolve_config_value(obj, context, key)
  local board = resolve_board(obj, context)
  if board and type(board.get_config_value) == "function" then
    return board:get_config_value(key)
  end
  return require('kanban-md.config').get_value(key)
end

-- Helper function to determine object type and generate appropriate prefix
local function get_id_prefix(obj, context)
  if context and context.board and obj == context.board then
    return "board_"
  elseif context and context.column and obj == context.column then
    return "column_"
  elseif context and context.card and obj == context.card then
    return "card_"
  end

  -- Fallback: try to detect type from metatable or properties
  if obj.columns then
    return "board_"
  elseif obj.cards then
    return "column_"
  else
    return "card_"
  end
end

-- Create ULID-based ID generation trigger
local function create_ulid_id_trigger()
  return function(self, context)
    -- Determine which object we're generating an ID for
    local obj = context.board or context.column or context.card or self

    -- Check if auto_id is enabled (board file config wins when reachable)
    if not resolve_config_value(obj, context, 'auto_id') then
      return true
    end

    local persist = resolve_config_value(obj, context, 'persist_card_ids')

    -- Only generate if ID doesn't exist or is empty
    if not obj.id or obj.id == "" then
      local prefix = get_id_prefix(obj, context)
      local generated_id = prefix .. ulid()
      obj.id = generated_id

      -- If persist_card_ids is enabled, sync to properties for persistence
      if persist and obj.properties then
        obj.properties.id = generated_id
      end
    elseif obj.id and persist and obj.properties then
      -- If ID already exists and persist_card_ids is enabled, ensure it's synced to properties
      obj.properties.id = obj.id
    end

    return true
  end
end

-- ID generation trigger (time-based hash)
-- Alternative to the ULID ID
local function create_time_based_id_trigger()
  return function(self, context)
    local card = context.card or self

    -- Check if auto_id is enabled (board file config wins when reachable)
    if not resolve_config_value(card, context, 'auto_id') then
      return true
    end

    local persist = resolve_config_value(card, context, 'persist_card_ids')

    -- Only generate if ID doesn't exist
    if not card.id or card.id == "" then
      local id_source = card.text .. (context.timestamp or os.time())
      local hash = 0
      for i = 1, #id_source do
        hash = (hash * 31 + string.byte(id_source, i)) % 0x100000000
      end
      local generated_id = string.format("%08x", hash)
      card.id = generated_id

      -- If persist_card_ids is enabled, sync to properties for persistence
      if persist and card.properties then
        card.properties.id = generated_id
      end
    elseif card.id and persist and card.properties then
      -- If ID already exists and persist_card_ids is enabled, ensure it's synced to properties
      card.properties.id = card.id
    end
    return true
  end
end


return {
  ulid_id = create_ulid_id_trigger,
  time_based_id = create_time_based_id_trigger,
}
