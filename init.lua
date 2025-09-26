-- Event-driven kanban board implementation
-- Single entry point for all classes and utilities

local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local Command = require('kanban-md.command')
local CommandLog = require('kanban-md.command_log')
local Triggerable = require('kanban-md.triggerable')
local triggers = require('kanban-md.triggers')
local config = require('kanban-md.config')
local commands = require('kanban-md.commands')

local M = {
  Board = Board,
  Column = Column,
  Card = Card,
  Command = Command,
  CommandLog = CommandLog,
  Triggerable = Triggerable,
  triggers = triggers,
  config = config,
}

-- Plugin setup function
function M.setup(user_config)
  -- Configure the plugin
  config.setup(user_config)
  
  -- Register Neovim commands
  commands.setup()
end

return M