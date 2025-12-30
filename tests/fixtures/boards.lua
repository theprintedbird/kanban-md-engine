local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local TypeConverter = require('kanban-md.type_converter')

return {
  simple_board = function()
    -- Board with basic columns
    local board = Board:new()
    board.title = "Simple Board"
    board:add_column("Todo")
    board:add_column("In Progress")
    board:add_column("Done")
    return board
  end,

  workflow_board = function()
    -- Board with complex workflow rules
    local board = Board:new()
    board.title = "Workflow Board"
    board.config = TypeConverter:new({ wip_limit = 10 })
    board:add_column("Backlog")
    board:add_column("Ready")
    board:add_column("In Progress")
    board:add_column("Review")
    board:add_column("Testing")
    board:add_column("Done")
    return board
  end,

  triggered_board = function()
    -- Board with all trigger types configured
    local board = Board:new()
    board.title = "Triggered Board"

    local todo = board:add_column("Todo")
    todo.config = TypeConverter:new({
      triggers = { on_entry = {}, on_exit = {}, on_stay = {} }
    })

    local in_progress = board:add_column("In Progress")
    in_progress.config = TypeConverter:new({
      wip_limit = 3,
      triggers = { on_entry = {}, on_exit = {}, on_stay = {} }
    })

    local done = board:add_column("Done")
    done.config = TypeConverter:new({
      triggers = { on_entry = {}, on_exit = {}, on_stay = {} }
    })

    return board
  end,

  capacity_board = function()
    -- Board with WIP limits and resources
    local board = Board:new()
    board.title = "Capacity Board"
    board.config = TypeConverter:new({ wip_limit = 10 })

    local todo = board:add_column("Todo")
    todo.config = TypeConverter:new({ wip_limit = 5 })

    local in_progress = board:add_column("In Progress")
    in_progress.config = TypeConverter:new({ wip_limit = 3 })

    local review = board:add_column("Review")
    review.config = TypeConverter:new({ wip_limit = 2 })

    board:add_column("Done")

    return board
  end
}
