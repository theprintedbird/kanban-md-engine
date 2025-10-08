-- lua/kanban-md/type_converter.lua
-- Type converter with automatic type conversion for numeric properties
  -- - Purpose: Type-safe wrapper for board/column/task property parsing
  -- - Scope: Internal utility for handling HTML comment configurations like <!-- column:config wip_limit: 3 -->
  -- - Content: Automatic type conversion logic (strings → numbers/booleans/arrays)
  -- - Usage: Wraps raw parsed properties to ensure correct types
  -- - Example conversions: "3" → 3, "true" → true, "tag1, tag2" → {"tag1", "tag2"}

local TypeConverter = {}
TypeConverter.__index = TypeConverter

-- Define which properties should be converted to numbers
local NUMERIC_PROPERTIES = {
  wip_limit = true,
  cycle_time_unit = false, -- This stays as string
  max_points = true,
  complexity = true,
  created = true,
  started = true,
  done = true,
  archived = true,
  actual_time = true,
  blocked_time = true,
  position = true
}

-- Define which properties should be converted to arrays
local ARRAY_PROPERTIES = {
  tags = true,
  authorized_approvers = true
}

-- Define which properties should be converted to booleans
local BOOLEAN_PROPERTIES = {
  blocked = true,
  urgent = true,
  reviewed = true,
  auto = true,
  revalidated = true,
  changes_requested = true
}

function TypeConverter:new(raw_config)
  local obj = {
    _raw = raw_config or {},
    _converted = {}
  }
  setmetatable(obj, TypeConverter)
  return obj
end

-- Convert a single value based on its property name
function TypeConverter:_convert_value(key, value)
  if value == nil then
    return nil
  end

  -- Handle numeric properties
  if NUMERIC_PROPERTIES[key] then
    local num = tonumber(value)
    if num then
      return num
    else
      -- If conversion fails, log warning and return original
      vim.notify(string.format("Warning: Could not convert '%s' to number for property '%s'", tostring(value), key), vim.log.levels.WARN)
      return value
    end
  end

  -- Handle boolean properties
  if BOOLEAN_PROPERTIES[key] then
    if type(value) == "boolean" then
      return value
    elseif type(value) == "string" then
      local lower = value:lower()
      if lower == "true" then
        return true
      elseif lower == "false" then
        return false
      end
    end
    -- If not a clear boolean, return original
    return value
  end

  -- Handle array properties
  if ARRAY_PROPERTIES[key] then
    if type(value) == "table" then
      return value -- Already an array
    elseif type(value) == "string" then
      -- Handle empty string
      if value == "" then
        return {}
      end
      -- Try to parse as comma-separated list
      local array = {}
      for item in value:gmatch("([^,]+)") do
        -- Trim whitespace - wrap in parens to get only the first return value
        local trimmed = (item:gsub("^%s+", ""):gsub("%s+$", ""))
        table.insert(array, trimmed)
      end
      return array
    end
    return value
  end

  -- For all other properties, return as-is
  return value
end

-- Getter with automatic type conversion
function TypeConverter:__index(key)
  -- Check if it's a method first
  if TypeConverter[key] then
    return TypeConverter[key]
  end

  -- Check if we've already converted this value
  if self._converted[key] ~= nil then
    return self._converted[key]
  end

  -- Get raw value and convert it
  local raw_value = self._raw[key]
  local converted_value = self:_convert_value(key, raw_value)

  -- Cache the converted value
  self._converted[key] = converted_value

  return converted_value
end

-- Setter that stores in raw format
function TypeConverter:__newindex(key, value)
  -- Store in raw format
  self._raw[key] = value
  -- Clear any cached converted value
  self._converted[key] = nil
end

-- Get all keys (for iteration)
function TypeConverter:keys()
  local keys = {}
  for k, _ in pairs(self._raw) do
    table.insert(keys, k)
  end
  return keys
end

-- Convert entire config to a plain table (useful for serialization)
function TypeConverter:to_table()
  local result = {}
  for key, _ in pairs(self._raw) do
    result[key] = self[key] -- This will trigger type conversion
  end
  return result
end

-- Check if a key exists
function TypeConverter:has(key)
  return self._raw[key] ~= nil
end

-- Get raw value without conversion (useful for debugging)
function TypeConverter:get_raw(key)
  return self._raw[key]
end

-- Merge another config into this one
function TypeConverter:merge(other_config)
  if type(other_config) == "table" then
    for key, value in pairs(other_config) do
      self[key] = value
    end
  end
end

-- Static methods to register property types (for optional modules)
function TypeConverter.register_array_property(property_name)
  ARRAY_PROPERTIES[property_name] = true
end

function TypeConverter.register_numeric_property(property_name)
  NUMERIC_PROPERTIES[property_name] = true
end

function TypeConverter.register_boolean_property(property_name)
  BOOLEAN_PROPERTIES[property_name] = true
end

return TypeConverter
