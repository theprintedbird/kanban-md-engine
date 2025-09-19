-- Board = {
-- 	columns = {
-- 		user = {},
-- 		special = {"__ARCHIVE__", "__STATS__"}
-- 	}
-- }


-- Triggerable mixin
local Triggerable = {}

-- Register a trigger on a column
-- column1:register_trigger("on_column_event", "column_update",  function(self, ...)
-- Register a trigger on the board
-- board:register_trigger("on_board_event", "board_update", function(self, ...)
-- 	print("Board trigger: self.columns=" .. #self.columns .. ", args=", ...)
-- end)
-- 	print("Column " .. self.id .. " trigger: args=", ...)
-- end)
function Triggerable:register_trigger(event_type, name, func)
  if not self.triggers then
    self.triggers = {}
  end
  if not self.triggers[event_type] then
    self.triggers[event_type] = {}
  end
  self.triggers[event_type][name] = func
end

-- Execute triggers
-- board:execute_trigger("on_board_event", "board_update", "data1", "data2")
-- column1:execute_trigger("on_column_event", "column_update", "task1", "task2")
function Triggerable:execute_trigger(event_type, name, ...)
  if self.triggers and self.triggers[event_type] and self.triggers[event_type][name] then
    -- Call the function with self as the first argument, followed by variadic args
    self.triggers[event_type][name](self, ...)
  end
end

-- Column class
local Column = {}
Column.__index = Column

-- Mixin Triggerable into Column
setmetatable(Column, { __index = Triggerable })

function Column:new(id)
  local obj = { id = id }
  setmetatable(obj, Column)
  return obj
end

local Card = {}
Card.__index = Card
-- Mixin Triggerable into Card
setmetatable(Card, { __index = Triggerable })

function Card:new(id)
  local obj = { id = id }
  setmetatable(obj, Card)
  return obj
end

-- Board class
local Board = {}
Board.__index = Board

-- Mixin Triggerable into Board
setmetatable(Board, { __index = Triggerable })

-- Create a new board
-- local board = Board:new()
function Board:new()
  local obj = { columns = {} }
  setmetatable(obj, Board)
  return obj
end

-- Add a column
-- local column1 = board:add_column("col1")
function Board:add_column(id)
  local column = Column:new(id)
  table.insert(self.columns, column)
  return column
end

function Board:get_column(id)
  for _, column in ipairs(self.columns) do
    if column.id == id then
			return column
    end
  end
  return nil
end

function Board:add_card(text, options)
end

local add_timestamp = function(self, task)
	-- Normalize column name to valid property name
	local normalize_column_name = function(column_name)
		-- Special case for archive
		if column_name == "__ARCHIVE__" then
			return "archived"
		end

		-- Convert to lowercase and replace spaces/special chars with underscores
		return column_name:lower():gsub("[^%w_]", "_")
	end
	-- Add timestamp for the target column (always add, allowing multiple visits)
	local timestamp_key = normalize_column_name(task.column)
	task.properties[timestamp_key] = os.time()
	return task
end

local board = Board:new()
local column1 = board:add_column("col1")
board.columns[1].register_trigger("card_created", "add_timestamp", add_timestamp)

for _, column in ipairs(board.columns) do
	column.register_trigger("on_enter", "add_timestamp", add_timestamp)
	column.register_trigger("on_enter", "validate_wip_limit", function(self,board, column, task)
		-- do something
	end)
end
