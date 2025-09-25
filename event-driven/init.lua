-- Event-driven kanban board implementation
-- Single entry point for all event-driven classes and utilities

local Board = require('kanban-md.event-driven.board')
local Column = require('kanban-md.event-driven.column')
local Card = require('kanban-md.event-driven.card')
local Command = require('kanban-md.event-driven.command')
local CommandLog = require('kanban-md.event-driven.command_log')
local Triggerable = require('kanban-md.event-driven.triggerable')
local triggers = require('kanban-md.event-driven.triggers')

return {
  Board = Board,
  Column = Column,
  Card = Card,
  Command = Command,
  CommandLog = CommandLog,
  Triggerable = Triggerable,
  triggers = triggers
}