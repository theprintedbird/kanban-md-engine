rockspec_format = "3.0"

package = "kanban-md-engine"
version = "scm-1"

source = {
   url = "git+https://github.com/theprintedbird/kanban-md-engine.git",
}

description = {
   summary = "Kanban board engine for Obsidian-compatible Markdown files",
   detailed = [[
      A platform-agnostic Lua engine for reading and writing Kanban boards
      held in Markdown. Boards use H6 column headings and HTML comments for
      configuration and card properties, so they stay readable in Obsidian
      and any other Markdown viewer. The engine parses a board, applies
      moves through a trigger system that maintains column timestamps and
      WIP limits, and writes it back with all surrounding prose preserved.
   ]],
   homepage = "https://github.com/theprintedbird/kanban-md-engine",
   license = "MIT",
}

dependencies = {
   -- 5.1 covers LuaJIT, which is what Neovim embeds.
   "lua >= 5.1, < 5.5",
}

test_dependencies = {
   "busted >= 2.0",
   "luacov >= 0.15",
   "luacheck >= 1.1",
}

test = {
   type = "busted",
}

build = {
   type = "builtin",
   modules = {
      ["kanban-md.adapter_registry"]         = "lua/kanban-md/adapter_registry.lua",
      ["kanban-md.adapters.cli"]             = "lua/kanban-md/adapters/cli.lua",
      ["kanban-md.adapters.interface"]       = "lua/kanban-md/adapters/interface.lua",
      ["kanban-md.board"]                    = "lua/kanban-md/board.lua",
      ["kanban-md.card"]                     = "lua/kanban-md/card.lua",
      ["kanban-md.cli"]                      = "lua/kanban-md/cli.lua",
      ["kanban-md.column"]                   = "lua/kanban-md/column.lua",
      ["kanban-md.column_type_resolver"]     = "lua/kanban-md/column_type_resolver.lua",
      ["kanban-md.config"]                   = "lua/kanban-md/config.lua",
      ["kanban-md.content_block"]            = "lua/kanban-md/content_block.lua",
      ["kanban-md.core.setup"]               = "lua/kanban-md/core/setup.lua",
      ["kanban-md.extras.capacity_triggers"] = "lua/kanban-md/extras/capacity_triggers.lua",
      ["kanban-md.extras.id_triggers"]       = "lua/kanban-md/extras/id_triggers.lua",
      ["kanban-md.extras.subtasks_triggers"] = "lua/kanban-md/extras/subtasks_triggers.lua",
      ["kanban-md.extras.workflow_triggers"] = "lua/kanban-md/extras/workflow_triggers.lua",
      ["kanban-md.helpers.column"]           = "lua/kanban-md/helpers/column.lua",
      ["kanban-md.helpers.ulid"]             = "lua/kanban-md/helpers/ulid.lua",
      ["kanban-md.parser"]                   = "lua/kanban-md/parser.lua",
      ["kanban-md.stats"]                    = "lua/kanban-md/stats.lua",
      ["kanban-md.templates"]                = "lua/kanban-md/templates.lua",
      ["kanban-md.triggerable"]              = "lua/kanban-md/triggerable.lua",
      ["kanban-md.triggers"]                 = "lua/kanban-md/triggers.lua",
      ["kanban-md.type_converter"]           = "lua/kanban-md/type_converter.lua",
      ["kanban-md.utils.string"]             = "lua/kanban-md/utils/string.lua",
      ["kanban-md.utils.table"]              = "lua/kanban-md/utils/table.lua",
      ["kanban-md.validation_result"]        = "lua/kanban-md/validation_result.lua",
      ["kanban-md.version"]                  = "lua/kanban-md/version.lua",
      ["kanban-md.virtual_text"]             = "lua/kanban-md/virtual_text.lua",
      ["kanban-md.workflow_engine"]          = "lua/kanban-md/workflow_engine.lua",
      ["kanban-md.writer_mixin"]             = "lua/kanban-md/writer_mixin.lua",
   },
}
