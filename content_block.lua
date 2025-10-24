-- lua/kanban-md/content_block.lua
-- Content block types and utilities for preserving markdown content

local ContentBlock = {}

-- Block types
ContentBlock.TYPES = {
  MARKDOWN = "markdown",       -- Arbitrary markdown content
  TITLE = "title",            -- Board title (H1)
  BOARD_CONFIG = "board_config",  -- Board config comment
  COLUMN = "column",          -- Column section (H6)
  ARCHIVE = "archive",        -- Archive section
  STATS = "stats",           -- Stats section
}

-- Create a markdown block
-- @param lines table - Array of markdown lines to preserve
-- @return table - Content block of type MARKDOWN
function ContentBlock.markdown(lines)
  return {
    type = ContentBlock.TYPES.MARKDOWN,
    lines = lines
  }
end

-- Create a title block
-- @return table - Content block of type TITLE
function ContentBlock.title()
  return {
    type = ContentBlock.TYPES.TITLE
  }
end

-- Create a board config block
-- @return table - Content block of type BOARD_CONFIG
function ContentBlock.board_config()
  return {
    type = ContentBlock.TYPES.BOARD_CONFIG
  }
end

-- Create a column block (references Column object)
-- @param column_ref table - Reference to Column object
-- @return table - Content block of type COLUMN
function ContentBlock.column(column_ref)
  return {
    type = ContentBlock.TYPES.COLUMN,
    ref = column_ref
  }
end

-- Create an archive block (references Column object)
-- @param column_ref table - Reference to Archive column object
-- @return table - Content block of type ARCHIVE
function ContentBlock.archive(column_ref)
  return {
    type = ContentBlock.TYPES.ARCHIVE,
    ref = column_ref
  }
end

-- Create a stats block (references Column object)
-- @param column_ref table - Reference to Stats column object
-- @return table - Content block of type STATS
function ContentBlock.stats(column_ref)
  return {
    type = ContentBlock.TYPES.STATS,
    ref = column_ref
  }
end

return ContentBlock
