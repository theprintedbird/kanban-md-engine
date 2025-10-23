--- Column Type Resolver
--
-- The ColumnTypeResolver maps Kanban column names to reusable "types" that define behavior,
-- properties, and validation rules. This allows you to configure column behaviors once (e.g.,
-- "completion columns auto-archive after 30 days") and apply them to multiple columns through
-- either explicit assignment, named definitions, or pattern matching. Properties merge through
-- a three-layer priority system where markdown config (highest) overrides named definitions,
-- which override type defaults (lowest).
--
-- Example:
--   -- Define a completion type with auto-archive behavior
--   config.column_config.types.completion = {
--     properties = { is_completion_state = true, auto_archive_days = 30 },
--     patterns = { "done", "complete", "finished" }
--   }
--
--   -- Column "## Done" matches pattern "done" -> gets completion type properties
--   -- Column "## Finished Tasks" matches pattern "finished" -> also completion type
--   -- Override per-column: <!-- column:config type: completion, auto_archive_days: 7 -->
--
-- Resolves column types and merges properties from multiple sources:
-- 1. Type definitions (lowest priority)
-- 2. Named column definitions (medium priority)
-- 3. Markdown properties (highest priority)

local ColumnTypeResolver = {}

--- Resolve column type from all available sources
--- Priority chain:
--- 1. Markdown explicit: markdown_config.type
--- 2. Config named definition: global_config.column_config.definitions[column_name]
--- 3. Config pattern matching: match column_name against types[*].patterns
--- 4. Return nil if no match
---@param column_name string The name of the column
---@param markdown_config table Properties parsed from markdown HTML comment
---@param global_config table Global plugin configuration
---@return string|nil type_name The resolved type name, or nil if no match
function ColumnTypeResolver.resolve_type(column_name, markdown_config, global_config)
  -- Guard: if global_config is nil, we can't resolve types properly
  if not global_config then
    return nil
  end

  -- Priority 1: Explicit type in markdown
  if markdown_config and markdown_config.type then
    return markdown_config.type
  end

  -- Get column_config, handling nil safely
  local column_config = global_config.column_config or {}
  local definitions = column_config.definitions or {}
  local types = column_config.types or {}

  -- Priority 2: Named definition match
  local definition = definitions[column_name]
  if definition and definition.type then
    return definition.type
  end

  -- Priority 3: Pattern matching
  -- Iterate through all types and check their patterns
  -- Convert column name to lowercase for case-insensitive matching
  -- When multiple patterns match, prefer the most specific (longest) pattern
  local column_name_lower = column_name:lower()
  local best_match = nil
  local best_pattern_length = 0

  for type_name, type_def in pairs(types) do
    if type_def.patterns then
      for _, pattern in ipairs(type_def.patterns) do
        -- Use Lua pattern matching (patterns should be lowercase)
        if string.match(column_name_lower, pattern) then
          -- Prefer longer (more specific) patterns
          local pattern_length = #pattern
          if pattern_length > best_pattern_length or
             (pattern_length == best_pattern_length and (not best_match or type_name < best_match)) then
            best_match = type_name
            best_pattern_length = pattern_length
          end
        end
      end
    end
  end

  if best_match then
    return best_match
  end

  -- Priority 4: No match found
  return nil
end

--- Get type definition from global config
---@param type_name string|nil The type name to look up
---@param global_config table Global plugin configuration
---@return table|nil type_def The type definition table, or nil if not found
function ColumnTypeResolver.get_type_definition(type_name, global_config)
  if not type_name or not global_config then
    return nil
  end

  local column_config = global_config.column_config or {}
  local types = column_config.types or {}

  return types[type_name]
end

--- Merge properties following priority: type < definition < markdown
--- Type properties have lowest priority, markdown properties have highest
---@param column_name string The name of the column
---@param markdown_props table Properties from markdown HTML comment
---@param type_name string|nil The resolved type name
---@param global_config table Global plugin configuration
---@return table merged_config The merged configuration table
function ColumnTypeResolver.merge_properties(column_name, markdown_props, type_name, global_config)
  local result = {}

  -- Step 1: Start with type definition properties (if type exists)
  if type_name then
    local type_def = ColumnTypeResolver.get_type_definition(type_name, global_config)
    if type_def and type_def.properties then
      for key, value in pairs(type_def.properties) do
        result[key] = value
      end
    end
  end

  -- Step 2: Merge config definition properties (if column_name in definitions)
  local column_config = global_config.column_config or {}
  local definitions = column_config.definitions or {}
  local definition = definitions[column_name]

  if definition then
    for key, value in pairs(definition) do
      -- Skip 'type' field as it's metadata, not a property
      if key ~= "type" then
        result[key] = value
      end
    end
  end

  -- Step 3: Merge markdown properties (these override everything)
  if markdown_props then
    for key, value in pairs(markdown_props) do
      -- Skip 'type' field in markdown as well (it's used for resolution, not a property)
      if key ~= "type" then
        result[key] = value
      end
    end
  end

  return result
end

--- Validate column has required properties
--- Emits warnings/errors based on global_config.missing_property_requirement
---@param column table The column object with name, type, and config
---@param global_config table Global plugin configuration
function ColumnTypeResolver.validate_requirements(column, global_config)
  if not column.type then
    return -- No type means no requirements to validate
  end

  local type_def = ColumnTypeResolver.get_type_definition(column.type, global_config)
  if not type_def then
    -- Warn about invalid type reference
    print(string.format(
      "Warning: Column '%s' references type '%s' which is not defined in config",
      column.name,
      column.type
    ))
    return
  end

  -- Check for requires_* properties in type definition
  local requirement_level = global_config.missing_property_requirement or "warning"

  for key, value in pairs(type_def) do
    -- Check for requires_* pattern
    local required_property = string.match(key, "^requires_(.+)$")
    if required_property and value == true then
      -- Check if the column has this required property
      local column_config = column.config or {}
      local has_property = column_config[required_property] ~= nil

      if not has_property then
        local message = string.format(
          "Column '%s' of type '%s' requires %s but none is set",
          column.name,
          column.type,
          required_property
        )

        if requirement_level == "error" then
          error(message)
        elseif requirement_level == "warning" then
          print("Warning: " .. message)
        end
        -- "none" means silent, do nothing
      end
    end
  end
end

--- Extract trigger configuration from type definition
---@param type_def table|nil The type definition
---@return table triggers Table of trigger lists by event type (on_entry, on_exit, etc.)
function ColumnTypeResolver.get_type_triggers(type_def)
  if not type_def then
    return {}
  end

  return type_def.triggers or {}
end

return ColumnTypeResolver
