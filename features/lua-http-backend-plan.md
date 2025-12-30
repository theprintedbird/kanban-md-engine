# Lua-HTTP Backend Implementation Plan

**Date**: 2025-11-17
**Status**: Implementation
**Branch**: `claude/lua-http-backend-01KAtPvXtRNwViqgzK3HSY9f`
**Dependencies**: kanban-md engine (abstracted), web frontend

---

## Overview

This document outlines the implementation of a pure Lua HTTP backend using the `lua-http` library. This backend provides a REST API and WebSocket server for the kanban-md web frontend, using the abstracted kanban-md engine directly.

**Technology Stack**:
- **lua-http**: Pure Lua HTTP/1.1 and HTTP/2 library
- **kanban-md engine**: Direct integration via `require('kanban-md.cli')`
- **cjson**: JSON encoding/decoding
- **LuaFileSystem (lfs)**: File system operations
- **entr**: File watching for live updates (external process)

**Design Principles**:
- Pure Lua (no C dependencies except LuaSocket)
- Direct engine integration (no translation layer)
- Flat file storage (markdown files)
- Single-user focused (authentication handled separately)
- Simple deployment
- Development-friendly (easy to run locally)

---

## Why lua-http?

**Advantages for this use case**:
1. **Pure Lua**: Easier debugging, no compilation needed
2. **HTTP/2 support**: Modern protocol support
3. **Lightweight**: Minimal footprint for single-user deployment
4. **Direct engine access**: No language boundary crossing
5. **Development friendly**: Quick iteration, simple setup
6. **WebSocket support**: Built-in via lua-http-websocket

**Trade-offs**:
- Lower performance than OpenResty (acceptable for single user)
- Manual routing (but gives more control)
- Smaller ecosystem (but we only need basic features)

**Perfect for**:
- Personal deployments
- Single-user boards
- Development and prototyping
- Learning Lua backend development

---

## Architecture

### System Architecture

**Production (NFS with Apache reverse proxy):**

```
┌─────────────────┐
│   Browser       │
│  (Web Frontend) │
└────────┬────────┘
         │ HTTPS (443)
         ▼
┌─────────────────────────────────┐
│   Apache (NFS)                  │
│   - SSL termination             │
│   - Static file serving         │
│   - Reverse proxy /api → :8080  │
└────────┬────────────────────────┘
         │ HTTP (localhost:8080)
         ▼
┌─────────────────────────────────┐
│   lua-http Server (daemon)      │
│                                 │
│  ┌──────────────────────────┐  │
│  │  HTTP Router             │  │
│  │  - GET /api/boards/:id   │  │
│  │  - POST /api/boards/...  │  │
│  └──────────────────────────┘  │
│                                 │
│  ┌──────────────────────────┐  │
│  │  WebSocket Server        │  │
│  │  - /api/boards/:id/watch │  │
│  └──────────────────────────┘  │
│                                 │
│  ┌──────────────────────────┐  │
│  │  kanban-md Engine        │  │
│  │  (via CLI entry point)   │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  File System                    │
│  /home/private/boards/*.md      │
└─────────────────────────────────┘
```

**Local Development:**

```
┌─────────────────┐
│   Browser       │
│  (Web Frontend) │
└────────┬────────┘
         │ HTTP/WS
         ▼
┌─────────────────────────────────┐
│   lua-http Server               │
│                                 │
│  ┌──────────────────────────┐  │
│  │  HTTP Router             │  │
│  │  - GET /api/boards/:id   │  │
│  │  - POST /api/boards/...  │  │
│  │  - Static file serving   │  │
│  └──────────────────────────┘  │
│                                 │
│  ┌──────────────────────────┐  │
│  │  WebSocket Server        │  │
│  │  - /api/boards/:id/watch │  │
│  └──────────────────────────┘  │
│                                 │
│  ┌──────────────────────────┐  │
│  │  kanban-md Engine        │  │
│  │  (via CLI entry point)   │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  File System                    │
│  data/boards/*.md               │
└─────────────────────────────────┘
         ▲
         │
    ┌────┴─────┐
    │  entr    │ ← File watcher
    │ (daemon) │   notifies server
    └──────────┘
```

### Request Flow

```
1. Browser → HTTP Request → Router
2. Router → Parse route → Find handler
3. Handler → Load markdown file → kanban-md engine
4. Engine → Parse/modify → Return data structure
5. Handler → Convert to JSON → HTTP Response → Browser
6. (On file change) → entr → WebSocket → Browser
```

---

## Directory Structure

```
backend/
├── server.lua              # Main HTTP server entry point
├── router.lua              # HTTP routing
├── handlers/
│   ├── boards.lua          # Board CRUD handlers
│   ├── cards.lua           # Card operation handlers
│   ├── static.lua          # Static file serving
│   └── websocket.lua       # WebSocket connection handler
├── middleware/
│   ├── cors.lua            # CORS headers
│   ├── logger.lua          # Request logging
│   └── error.lua           # Error handling
├── services/
│   ├── board_service.lua   # Board business logic
│   ├── file_service.lua    # File I/O operations
│   └── watch_service.lua   # File watching coordination
├── utils/
│   ├── response.lua        # HTTP response helpers
│   └── validation.lua      # Input validation
├── config.lua              # Configuration
└── start.sh                # Startup script with file watcher

data/
└── boards/                 # Markdown board files
    ├── demo.md
    ├── personal.md
    └── work.md
```

---

## Core Implementation

### 1. Main Server (server.lua)

```lua
#!/usr/bin/env lua
-- backend/server.lua
-- Main HTTP server using lua-http

local http_server = require "http.server"
local http_headers = require "http.headers"
local router = require "backend.router"
local config = require "backend.config"
local logger = require "backend.middleware.logger"

-- Initialize kanban-md engine
local kanban = require('kanban-md.cli')
kanban.setup({
  auto_id = true,
  auto_timestamp = true,
  wip_limit = 10,
})

print("Kanban-MD HTTP Server")
print("Configuration:")
print("  Host: " .. config.host)
print("  Port: " .. config.port)
print("  Data directory: " .. config.data_dir)
print("  Static directory: " .. config.static_dir)

-- Create server
local server = http_server.listen {
  host = config.host,
  port = config.port,

  onstream = function(server, stream)
    -- Read request headers
    local req_headers = stream:get_headers()
    local req_method = req_headers:get ":method"
    local req_path = req_headers:get ":path"
    local req_authority = req_headers:get ":authority"

    -- Log request
    logger.log_request(req_method, req_path, req_authority)

    -- Read request body if present
    local req_body = nil
    if req_method == "POST" or req_method == "PUT" then
      req_body = stream:get_body_as_string()
    end

    -- Build request object
    local request = {
      method = req_method,
      path = req_path,
      authority = req_authority,
      headers = req_headers,
      body = req_body,
      stream = stream,
    }

    -- Route request
    local success, err = pcall(function()
      router.route(request)
    end)

    if not success then
      logger.log_error("Request error: " .. tostring(err))

      -- Send 500 error
      local error_response = require("backend.utils.response")
      error_response.send_error(stream, 500, "Internal server error")
    end
  end,

  onerror = function(server, context, op, err, errno)
    local msg = op .. " on " .. tostring(context) .. " failed"
    if err then
      msg = msg .. ": " .. tostring(err)
    end
    logger.log_error(msg)
  end,
}

print("\nServer listening on http://" .. config.host .. ":" .. config.port)
print("Press Ctrl+C to stop\n")

-- Run server (blocks)
assert(server:loop())
```

### 2. HTTP Router (router.lua)

```lua
-- backend/router.lua
-- HTTP request router

local boards_handler = require("backend.handlers.boards")
local cards_handler = require("backend.handlers.cards")
local static_handler = require("backend.handlers.static")
local ws_handler = require("backend.handlers.websocket")
local response = require("backend.utils.response")
local cors = require("backend.middleware.cors")

local M = {}

-- Route patterns (simple pattern matching)
local routes = {
  -- Board routes
  { pattern = "^/api/boards$", methods = { GET = boards_handler.list, POST = boards_handler.create } },
  { pattern = "^/api/boards/([^/]+)$", methods = { GET = boards_handler.get, PUT = boards_handler.update, DELETE = boards_handler.delete } },
  { pattern = "^/api/boards/([^/]+)/stats$", methods = { GET = boards_handler.get_stats } },
  { pattern = "^/api/boards/([^/]+)/validate$", methods = { GET = boards_handler.validate } },
  { pattern = "^/api/boards/([^/]+)/archive$", methods = { POST = boards_handler.archive } },

  -- Card routes
  { pattern = "^/api/boards/([^/]+)/cards$", methods = { POST = cards_handler.add } },
  { pattern = "^/api/boards/([^/]+)/cards/([^/]+)$", methods = { PUT = cards_handler.update, DELETE = cards_handler.delete } },
  { pattern = "^/api/boards/([^/]+)/cards/([^/]+)/move$", methods = { POST = cards_handler.move } },

  -- WebSocket route
  { pattern = "^/api/boards/([^/]+)/watch$", methods = { GET = ws_handler.connect } },
}

function M.route(request)
  local path = request.path
  local method = request.method

  -- Apply CORS middleware
  cors.add_headers(request)

  -- Handle OPTIONS preflight
  if method == "OPTIONS" then
    response.send_json(request.stream, {}, 200)
    return
  end

  -- Try to match routes
  for _, route in ipairs(routes) do
    local matches = { path:match(route.pattern) }

    if #matches > 0 or path:match(route.pattern) then
      local handler = route.methods[method]

      if handler then
        -- Call handler with captures
        handler(request, unpack(matches))
        return
      else
        -- Method not allowed
        response.send_error(request.stream, 405, "Method not allowed")
        return
      end
    end
  end

  -- Static file serving (fallback)
  if method == "GET" then
    static_handler.serve(request)
  else
    response.send_error(request.stream, 404, "Not found")
  end
end

return M
```

### 3. Board Handlers (handlers/boards.lua)

```lua
-- backend/handlers/boards.lua
-- Board CRUD handlers

local board_service = require("backend.services.board_service")
local response = require("backend.utils.response")
local validation = require("backend.utils.validation")

local M = {}

-- GET /api/boards
function M.list(request)
  local boards = board_service.list_boards()
  response.send_json(request.stream, boards)
end

-- POST /api/boards
function M.create(request)
  local data = response.parse_json_body(request.body)

  if not data or not data.name then
    response.send_error(request.stream, 400, "Missing board name")
    return
  end

  local board_id, err = board_service.create_board(data.name, data.markdown)

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, { id = board_id, success = true }, 201)
end

-- GET /api/boards/:id
function M.get(request, board_id)
  if not board_id or board_id == "" then
    response.send_error(request.stream, 400, "Missing board ID")
    return
  end

  local board, err = board_service.get_board(board_id)

  if err then
    response.send_error(request.stream, 404, err)
    return
  end

  response.send_json(request.stream, board)
end

-- PUT /api/boards/:id
function M.update(request, board_id)
  local data = response.parse_json_body(request.body)

  if not data or not data.markdown then
    response.send_error(request.stream, 400, "Missing markdown content")
    return
  end

  local success, err = board_service.update_board(board_id, data.markdown)

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, { success = true })
end

-- DELETE /api/boards/:id
function M.delete(request, board_id)
  local success, err = board_service.delete_board(board_id)

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, { success = true })
end

-- GET /api/boards/:id/stats
function M.get_stats(request, board_id)
  local stats, err = board_service.get_stats(board_id)

  if err then
    response.send_error(request.stream, 404, err)
    return
  end

  response.send_json(request.stream, stats)
end

-- GET /api/boards/:id/validate
function M.validate(request, board_id)
  local validation_result, err = board_service.validate_board(board_id)

  if err then
    response.send_error(request.stream, 404, err)
    return
  end

  response.send_json(request.stream, validation_result)
end

-- POST /api/boards/:id/archive
function M.archive(request, board_id)
  local data = response.parse_json_body(request.body) or {}
  local older_than_days = data.olderThanDays or 0

  local result, err = board_service.archive_cards(board_id, older_than_days)

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, result)
end

return M
```

### 4. Card Handlers (handlers/cards.lua)

```lua
-- backend/handlers/cards.lua
-- Card operation handlers

local board_service = require("backend.services.board_service")
local response = require("backend.utils.response")

local M = {}

-- POST /api/boards/:board_id/cards/:card_id/move
function M.move(request, board_id, card_id)
  local data = response.parse_json_body(request.body)

  if not data or not data.fromColumn or not data.toColumn then
    response.send_error(request.stream, 400, "Missing fromColumn or toColumn")
    return
  end

  local board, err = board_service.move_card(
    board_id,
    card_id,
    data.fromColumn,
    data.toColumn
  )

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, {
    success = true,
    board = board
  })
end

-- POST /api/boards/:board_id/cards
function M.add(request, board_id)
  local data = response.parse_json_body(request.body)

  if not data or not data.column or not data.text then
    response.send_error(request.stream, 400, "Missing column or text")
    return
  end

  local board, card_id, err = board_service.add_card(
    board_id,
    data.column,
    data.text,
    data.properties or {}
  )

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, {
    success = true,
    cardId = card_id,
    board = board
  })
end

-- PUT /api/boards/:board_id/cards/:card_id
function M.update(request, board_id, card_id)
  local data = response.parse_json_body(request.body)

  if not data then
    response.send_error(request.stream, 400, "Missing update data")
    return
  end

  local board, err = board_service.update_card(
    board_id,
    card_id,
    data
  )

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, {
    success = true,
    board = board
  })
end

-- DELETE /api/boards/:board_id/cards/:card_id
function M.delete(request, board_id, card_id)
  local board, err = board_service.delete_card(board_id, card_id)

  if err then
    response.send_error(request.stream, 500, err)
    return
  end

  response.send_json(request.stream, {
    success = true,
    board = board
  })
end

return M
```

### 5. Board Service (services/board_service.lua)

```lua
-- backend/services/board_service.lua
-- Board business logic using kanban-md engine

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local file_service = require('backend.services.file_service')
local watch_service = require('backend.services.watch_service')
local cjson = require('cjson')

local M = {}

--- Load a board from file
-- @param board_id string Board identifier
-- @return table|nil, string|nil Board data or error
function M.get_board(board_id)
  -- Read markdown file
  local markdown, err = file_service.read_board(board_id)
  if err then
    return nil, err
  end

  -- Parse with kanban-md engine
  local board = Board:new()
  board:parse(markdown)

  -- Register triggers
  board:auto_register_triggers()

  -- Calculate stats
  board:calculate_stats()

  -- Validate
  board:validate()

  -- Convert to JSON-friendly structure
  local board_data = {
    id = board_id,
    title = board.title,
    columns = board.columns,
    stats = board.stats,
    config = board.config,
    validation = board.validation,
  }

  return board_data, nil
end

--- Update board with new markdown
-- @param board_id string Board identifier
-- @param markdown string New markdown content
-- @return boolean, string|nil Success status or error
function M.update_board(board_id, markdown)
  local success, err = file_service.write_board(board_id, markdown)

  if err then
    return false, err
  end

  -- Notify watchers
  watch_service.notify_board_updated(board_id)

  return true, nil
end

--- Move a card between columns
-- @param board_id string Board identifier
-- @param card_id string Card identifier
-- @param from_column string Source column name
-- @param to_column string Target column name
-- @return table|nil, string|nil Updated board or error
function M.move_card(board_id, card_id, from_column, to_column)
  -- Load board
  local markdown, err = file_service.read_board(board_id)
  if err then
    return nil, err
  end

  -- Parse
  local board = Board:new()
  board:parse(markdown)
  board:auto_register_triggers()

  -- Find card and columns
  local card_data = board:find_task(card_id)
  if not card_data then
    return nil, "Card not found: " .. card_id
  end

  local from_col = board:get_column_by_name(from_column)
  local to_col = board:get_column_by_name(to_column)

  if not from_col then
    return nil, "Source column not found: " .. from_column
  end

  if not to_col then
    return nil, "Target column not found: " .. to_column
  end

  -- Perform move
  local success, move_err = pcall(function()
    board:move_card(card_data, from_col, to_col)
  end)

  if not success then
    return nil, "Failed to move card: " .. tostring(move_err)
  end

  -- Recalculate stats
  board:calculate_stats()
  board:validate()

  -- Write back
  local output_lines = board:write()
  local output_markdown = table.concat(output_lines, "\n")

  local write_success, write_err = file_service.write_board(board_id, output_markdown)
  if write_err then
    return nil, write_err
  end

  -- Notify watchers
  watch_service.notify_board_updated(board_id)

  -- Return updated board
  return {
    id = board_id,
    title = board.title,
    columns = board.columns,
    stats = board.stats,
    config = board.config,
    validation = board.validation,
  }, nil
end

--- Add a new card
-- @param board_id string Board identifier
-- @param column_name string Column to add card to
-- @param text string Card text
-- @param properties table Card properties
-- @return table|nil, string|nil, string|nil Board, card ID, or error
function M.add_card(board_id, column_name, text, properties)
  -- Load board
  local markdown, err = file_service.read_board(board_id)
  if err then
    return nil, nil, err
  end

  -- Parse
  local board = Board:new()
  board:parse(markdown)
  board:auto_register_triggers()

  -- Find column
  local column = board:get_column_by_name(column_name)
  if not column then
    return nil, nil, "Column not found: " .. column_name
  end

  -- Create card
  local card = Card:new(text)
  for k, v in pairs(properties) do
    card.properties[k] = v
  end

  -- Add card
  local success, add_err = pcall(function()
    column:add_card(card)
  end)

  if not success then
    return nil, nil, "Failed to add card: " .. tostring(add_err)
  end

  -- Recalculate
  board:calculate_stats()
  board:validate()

  -- Write back
  local output_lines = board:write()
  local output_markdown = table.concat(output_lines, "\n")

  local write_success, write_err = file_service.write_board(board_id, output_markdown)
  if write_err then
    return nil, nil, write_err
  end

  -- Notify watchers
  watch_service.notify_board_updated(board_id)

  -- Return updated board and card ID
  return {
    id = board_id,
    title = board.title,
    columns = board.columns,
    stats = board.stats,
    config = board.config,
    validation = board.validation,
  }, card.properties.id, nil
end

--- Update card properties
-- (Similar pattern to add_card and move_card)

--- Delete card
-- (Similar pattern)

--- List all boards
function M.list_boards()
  return file_service.list_boards()
end

--- Get board statistics
function M.get_stats(board_id)
  local board, err = M.get_board(board_id)
  if err then
    return nil, err
  end

  return board.stats, nil
end

--- Validate board
function M.validate_board(board_id)
  local board, err = M.get_board(board_id)
  if err then
    return nil, err
  end

  return board.validation, nil
end

--- Archive completed cards
function M.archive_cards(board_id, older_than_days)
  -- Load, parse, archive, write pattern
  -- Similar to move_card
end

return M
```

### 6. WebSocket Handler (handlers/websocket.lua)

```lua
-- backend/handlers/websocket.lua
-- WebSocket connection handler for live updates

local websocket = require "http.websocket"
local watch_service = require "backend.services.watch_service"
local cjson = require "cjson"

local M = {}

function M.connect(request, board_id)
  local stream = request.stream

  -- Upgrade to WebSocket
  local ws, err = websocket.new_from_stream(stream, request.headers)
  if not ws then
    print("WebSocket upgrade failed:", err)
    return
  end

  print("WebSocket connected for board:", board_id)

  -- Register with watch service
  watch_service.register_watcher(board_id, ws)

  -- Keep connection alive
  while true do
    local data, opcode, err = ws:receive()

    if not data then
      print("WebSocket error:", err)
      break
    end

    if opcode == websocket.OPCODE_TEXT then
      -- Handle incoming messages (e.g., pong responses)
      local success, msg = pcall(cjson.decode, data)
      if success and msg.type == "pong" then
        -- Client responded to ping
      end
    elseif opcode == websocket.OPCODE_CLOSE then
      print("WebSocket closed by client")
      break
    end
  end

  -- Cleanup
  watch_service.unregister_watcher(board_id, ws)
  ws:close()
end

return M
```

### 7. Watch Service (services/watch_service.lua)

```lua
-- backend/services/watch_service.lua
-- Coordinates file watching and WebSocket notifications

local cjson = require "cjson"
local websocket = require "http.websocket"

local M = {}

-- Map of board_id -> array of WebSocket connections
local watchers = {}

--- Register a WebSocket watcher for a board
function M.register_watcher(board_id, ws)
  if not watchers[board_id] then
    watchers[board_id] = {}
  end

  table.insert(watchers[board_id], ws)
  print("Registered watcher for board:", board_id, "Total:", #watchers[board_id])
end

--- Unregister a watcher
function M.unregister_watcher(board_id, ws)
  if not watchers[board_id] then
    return
  end

  for i, w in ipairs(watchers[board_id]) do
    if w == ws then
      table.remove(watchers[board_id], i)
      print("Unregistered watcher for board:", board_id)
      break
    end
  end
end

--- Notify all watchers that a board was updated
function M.notify_board_updated(board_id)
  if not watchers[board_id] then
    return
  end

  local message = cjson.encode({
    type = "board_updated",
    boardId = board_id,
    timestamp = os.time(),
  })

  print("Notifying watchers for board:", board_id, "Count:", #watchers[board_id])

  -- Send to all connected watchers
  for i = #watchers[board_id], 1, -1 do
    local ws = watchers[board_id][i]

    local success, err = pcall(function()
      ws:send(message, websocket.OPCODE_TEXT)
    end)

    if not success then
      print("Failed to send to watcher:", err)
      -- Remove dead connection
      table.remove(watchers[board_id], i)
    end
  end
end

return M
```

### 8. File Service (services/file_service.lua)

```lua
-- backend/services/file_service.lua
-- File I/O operations for board storage

local lfs = require "lfs"
local config = require "backend.config"

local M = {}

--- Read a board markdown file
function M.read_board(board_id)
  local path = config.data_dir .. "/" .. board_id .. ".md"

  local file, err = io.open(path, "r")
  if not file then
    return nil, "Board not found: " .. board_id
  end

  local content = file:read("*all")
  file:close()

  return content, nil
end

--- Write a board markdown file
function M.write_board(board_id, markdown)
  local path = config.data_dir .. "/" .. board_id .. ".md"

  local file, err = io.open(path, "w")
  if not file then
    return false, "Failed to write board: " .. err
  end

  file:write(markdown)
  file:close()

  return true, nil
end

--- List all board files
function M.list_boards()
  local boards = {}

  for file in lfs.dir(config.data_dir) do
    if file:match("%.md$") then
      local board_id = file:gsub("%.md$", "")
      table.insert(boards, {
        id = board_id,
        name = board_id, -- Could read title from file
      })
    end
  end

  return boards
end

--- Delete a board file
function M.delete_board(board_id)
  local path = config.data_dir .. "/" .. board_id .. ".md"
  local success, err = os.remove(path)

  if not success then
    return false, "Failed to delete board: " .. err
  end

  return true, nil
end

return M
```

### 9. Configuration (config.lua)

```lua
-- backend/config.lua
-- Server configuration

return {
  host = os.getenv("KANBAN_HOST") or "127.0.0.1",
  port = tonumber(os.getenv("KANBAN_PORT")) or 8080,
  data_dir = os.getenv("KANBAN_DATA_DIR") or "data/boards",
  static_dir = os.getenv("KANBAN_STATIC_DIR") or "web",
}
```

### 10. Response Utilities (utils/response.lua)

```lua
-- backend/utils/response.lua
-- HTTP response helpers

local http_headers = require "http.headers"
local cjson = require "cjson"

local M = {}

--- Send JSON response
function M.send_json(stream, data, status)
  status = status or 200

  local res_headers = http_headers.new()
  res_headers:append(":status", tostring(status))
  res_headers:append("content-type", "application/json")
  res_headers:append("access-control-allow-origin", "*")

  stream:write_headers(res_headers, false)

  local json = cjson.encode(data)
  stream:write_chunk(json, true)
end

--- Send error response
function M.send_error(stream, status, message)
  M.send_json(stream, {
    error = message,
    status = status
  }, status)
end

--- Parse JSON body
function M.parse_json_body(body)
  if not body or body == "" then
    return nil
  end

  local success, data = pcall(cjson.decode, body)
  if not success then
    return nil
  end

  return data
end

--- Send file response
function M.send_file(stream, path, content_type)
  local file = io.open(path, "rb")
  if not file then
    M.send_error(stream, 404, "File not found")
    return
  end

  local content = file:read("*all")
  file:close()

  local res_headers = http_headers.new()
  res_headers:append(":status", "200")
  res_headers:append("content-type", content_type or "text/plain")
  res_headers:append("content-length", tostring(#content))

  stream:write_headers(res_headers, false)
  stream:write_chunk(content, true)
end

return M
```

---

## File Watching with entr

### Setup Script (start.sh)

```bash
#!/bin/bash
# backend/start.sh
# Starts the HTTP server and file watcher

set -e

DATA_DIR="${KANBAN_DATA_DIR:-data/boards}"
SERVER_PID=""
ENTR_PID=""

# Cleanup on exit
cleanup() {
  echo "Shutting down..."
  if [ -n "$SERVER_PID" ]; then
    kill $SERVER_PID 2>/dev/null || true
  fi
  if [ -n "$ENTR_PID" ]; then
    kill $ENTR_PID 2>/dev/null || true
  fi
  exit 0
}

trap cleanup SIGINT SIGTERM

# Start HTTP server
echo "Starting HTTP server..."
lua backend/server.lua &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 2

# Start file watcher
echo "Starting file watcher on $DATA_DIR/*.md..."

# Use entr to watch markdown files
# When a file changes, notify via HTTP POST to server
ls "$DATA_DIR"/*.md | entr -p sh -c '
  CHANGED_FILE=$(echo "$1" | xargs basename .md)
  echo "File changed: $CHANGED_FILE"
  # Trigger notification (could be HTTP endpoint or Unix socket)
  # For now, the server polls or uses inotify
' &

ENTR_PID=$!

echo "File watcher PID: $ENTR_PID"
echo ""
echo "Server running at http://127.0.0.1:8080"
echo "Press Ctrl+C to stop"
echo ""

# Wait for server process
wait $SERVER_PID
```

### Alternative: Built-in File Watching

Instead of `entr`, we could use LuaFileSystem's inotify bindings:

```lua
-- services/inotify_watcher.lua (Linux only)
local inotify = require "inotify"
local watch_service = require "backend.services.watch_service"
local config = require "backend.config"

local M = {}

function M.start()
  local handle = inotify.init()

  -- Watch data directory
  local wd = handle:addwatch(config.data_dir, inotify.IN_MODIFY, inotify.IN_CLOSE_WRITE)

  print("Watching directory:", config.data_dir)

  -- Run in separate coroutine
  while true do
    local events = handle:read()

    for _, ev in ipairs(events) do
      if ev.name:match("%.md$") then
        local board_id = ev.name:gsub("%.md$", "")
        print("File modified:", board_id)
        watch_service.notify_board_updated(board_id)
      end
    end
  end
end

return M
```

---

## Static File Serving

```lua
-- handlers/static.lua
local response = require "backend.utils.response"
local config = require "backend.config"

local M = {}

-- MIME types
local mime_types = {
  [".html"] = "text/html",
  [".css"] = "text/css",
  [".js"] = "application/javascript",
  [".json"] = "application/json",
  [".png"] = "image/png",
  [".jpg"] = "image/jpeg",
  [".jpeg"] = "image/jpeg",
  [".gif"] = "image/gif",
  [".svg"] = "image/svg+xml",
  [".ico"] = "image/x-icon",
}

function M.serve(request)
  local path = request.path

  -- Default to index.html
  if path == "/" then
    path = "/index.html"
  end

  -- Security: prevent directory traversal
  if path:match("%.%.") then
    response.send_error(request.stream, 403, "Forbidden")
    return
  end

  -- Build file path
  local file_path = config.static_dir .. path

  -- Determine content type
  local ext = path:match("(%.[^.]+)$")
  local content_type = mime_types[ext] or "application/octet-stream"

  -- Send file
  response.send_file(request.stream, file_path, content_type)
end

return M
```

---

## Deployment

### Local Development

```bash
# Install dependencies
luarocks install http
luarocks install lua-cjson
luarocks install luafilesystem

# Create data directory
mkdir -p data/boards

# Create a demo board
cat > data/boards/demo.md << 'EOF'
# Demo Board

###### Backlog

- First task

###### In Progress

- Second task

###### Done

- Completed task
EOF

# Start server
chmod +x backend/start.sh
./backend/start.sh
```

### Production Deployment (NearlyFreeSpeech.NET)

NFS uses Apache with persistent processes (daemons) for application servers. The lua-http backend runs as a daemon on a local port, and Apache reverse proxies requests to it.

#### Directory Structure on NFS

```
/home/
├── public/                    # Apache document root
│   ├── index.html             # Frontend entry point
│   ├── css/
│   ├── js/
│   └── .htaccess              # Apache configuration
├── private/                   # Private data (not web-accessible)
│   └── boards/                # Markdown board files
│       ├── demo.md
│       └── personal.md
└── protected/                 # Application code
    └── kanban-md/
        ├── lua/               # Lua modules
        ├── backend/           # HTTP server code
        └── run.sh             # Daemon startup script
```

#### Step 1: Install Lua Dependencies

NFS allows installing packages via their package management. Check available Lua packages:

```bash
# SSH into your NFS site
ssh yoursite_yourmember@ssh.phx.nearlyfreespeech.net

# Check available Lua packages
pkg_info -a | grep lua

# If luarocks is available, install dependencies
luarocks install --local http
luarocks install --local lua-cjson
luarocks install --local luafilesystem

# Or compile from source if needed
cd /home/protected
# Download and build lua-http, cjson, lfs
```

#### Step 2: Create the Daemon Run Script

NFS daemons use a `run.sh` script pattern. Create `/home/protected/kanban-md/run.sh`:

```bash
#!/bin/sh
# /home/protected/kanban-md/run.sh
# Daemon startup script for lua-http server

# Set environment
export LUA_PATH="/home/protected/kanban-md/lua/?.lua;/home/protected/kanban-md/lua/?/init.lua;;"
export LUA_CPATH="/home/protected/lib/?.so;;"
export KANBAN_HOST="127.0.0.1"
export KANBAN_PORT="8080"
export KANBAN_DATA_DIR="/home/private/boards"

# Change to application directory
cd /home/protected/kanban-md

# Start the server
exec lua backend/server.lua
```

Make it executable:
```bash
chmod +x /home/protected/kanban-md/run.sh
```

#### Step 3: Set Up the Daemon

NFS provides a daemon management system. Set up your daemon via the NFS member portal:

1. Go to your site's "Daemons" tab in the member portal
2. Add a new daemon:
   - **Tag**: `kanban`
   - **Command Line**: `/home/protected/kanban-md/run.sh`
   - **Working Directory**: `/home/protected/kanban-md`

Alternatively, use the NFS API or command line tools if available.

#### Step 4: Configure Apache Reverse Proxy

Create `/home/public/.htaccess`:

```apache
# Enable rewrite engine
RewriteEngine On

# Proxy API requests to lua-http backend
# NFS uses mod_proxy with RewriteRule [P] flag

# API endpoints
RewriteRule ^api/(.*)$ http://127.0.0.1:8080/api/$1 [P,L]

# WebSocket upgrade for live updates
# Note: WebSocket proxying may require additional NFS configuration
# If WebSockets aren't supported, fall back to polling
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule ^api/boards/([^/]+)/watch$ ws://127.0.0.1:8080/api/boards/$1/watch [P,L]

# Serve static files directly from Apache (more efficient)
# index.html, CSS, JS are served from /home/public/

# SPA fallback: serve index.html for unmatched routes
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteCond %{REQUEST_URI} !^/api/
RewriteRule ^ index.html [L]
```

**Important**: If `.htaccess` proxy rules don't work, you may need to request proxy support via NFS support or use their "Custom Apache" realm feature.

#### Step 5: Alternative - Apache VirtualHost (Custom Realm)

If you have a custom Apache realm on NFS, add to your site configuration:

```apache
<VirtualHost *:80>
    ServerName yoursite.nfshost.com
    DocumentRoot /home/public

    # Proxy settings
    ProxyPreserveHost On
    ProxyRequests Off

    # API reverse proxy
    ProxyPass /api http://127.0.0.1:8080/api
    ProxyPassReverse /api http://127.0.0.1:8080/api

    # WebSocket proxy (if mod_proxy_wstunnel is available)
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule ^/api/boards/([^/]+)/watch$ ws://127.0.0.1:8080/api/boards/$1/watch [P,L]

    # Static files
    <Directory /home/public>
        Require all granted
        Options -Indexes
    </Directory>
</VirtualHost>
```

#### Step 6: Verify Daemon is Running

```bash
# Check if your daemon is running
ps aux | grep lua

# Check the daemon log (location varies by NFS setup)
# Usually in /home/logs/ or accessible via member portal

# Test the backend directly
curl http://127.0.0.1:8080/api/boards

# Test via Apache proxy
curl https://yoursite.nfshost.com/api/boards
```

#### Step 7: WebSocket Considerations

NFS may or may not support WebSocket proxying (`mod_proxy_wstunnel`). If WebSockets don't work:

1. **Polling fallback**: The frontend should fall back to polling `/api/boards/:id` every few seconds
2. **Contact NFS support**: Ask if `mod_proxy_wstunnel` is available for your realm
3. **Alternative**: Use Server-Sent Events (SSE) instead of WebSockets, which works over standard HTTP

Add polling fallback to the frontend:

```javascript
// Frontend WebSocket with polling fallback
class BoardConnection {
  constructor(boardId) {
    this.boardId = boardId;
    this.useWebSocket = true;
    this.pollInterval = null;
  }

  connect(onUpdate) {
    if (this.useWebSocket) {
      try {
        this.ws = new WebSocket(`wss://${location.host}/api/boards/${this.boardId}/watch`);
        this.ws.onmessage = (e) => onUpdate(JSON.parse(e.data));
        this.ws.onerror = () => this.fallbackToPolling(onUpdate);
      } catch {
        this.fallbackToPolling(onUpdate);
      }
    } else {
      this.fallbackToPolling(onUpdate);
    }
  }

  fallbackToPolling(onUpdate) {
    this.useWebSocket = false;
    this.pollInterval = setInterval(async () => {
      const res = await fetch(`/api/boards/${this.boardId}`);
      const board = await res.json();
      onUpdate({ type: 'board_updated', board });
    }, 3000);
  }
}
```

#### NFS-Specific Notes

1. **No systemd**: NFS doesn't use systemd; daemons are managed through their member portal
2. **Port restrictions**: Use ports above 1024; 8080 is a good default
3. **File permissions**: Ensure `/home/private/boards` is writable by the web process
4. **Memory limits**: NFS has memory limits per process; lua-http is lightweight enough
5. **Logs**: Check the NFS-provided log viewer in the member portal for daemon output
6. **Restarts**: Daemons auto-restart if they crash; you can also restart via the portal

#### Troubleshooting NFS Deployment

**Daemon not starting**:
```bash
# Check run.sh permissions
ls -la /home/protected/kanban-md/run.sh

# Test run.sh manually
/home/protected/kanban-md/run.sh

# Check for missing Lua modules
lua -e "require 'http.server'"
```

**Proxy not working**:
```bash
# Test backend directly
curl -v http://127.0.0.1:8080/api/boards

# Check .htaccess syntax
# Look for errors in Apache error log (via NFS portal)
```

**Permission denied on boards directory**:
```bash
chmod 755 /home/private/boards
chmod 644 /home/private/boards/*.md
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM debian:bullseye-slim

# Install Lua and dependencies
RUN apt-get update && apt-get install -y \
    lua5.3 \
    luarocks \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Lua dependencies
RUN luarocks install http && \
    luarocks install lua-cjson && \
    luarocks install luafilesystem

# Copy application
WORKDIR /app
COPY . /app

# Create data directory
RUN mkdir -p /app/data/boards

# Expose port
EXPOSE 8080

# Start server
CMD ["lua", "backend/server.lua"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  kanban-md:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./data/boards:/app/data/boards
      - ./web:/app/web
    environment:
      - KANBAN_HOST=0.0.0.0
      - KANBAN_PORT=8080
    restart: unless-stopped
```

---

## Testing Strategy

### Manual Testing

```bash
# Test GET board
curl http://localhost:8080/api/boards/demo

# Test move card
curl -X POST http://localhost:8080/api/boards/demo/cards/card-123/move \
  -H "Content-Type: application/json" \
  -d '{"fromColumn": "Backlog", "toColumn": "In Progress"}'

# Test add card
curl -X POST http://localhost:8080/api/boards/demo/cards \
  -H "Content-Type: application/json" \
  -d '{"column": "Backlog", "text": "New task", "properties": {"complexity": 3}}'
```

### Automated Tests

Use existing busted tests for engine logic, add integration tests for HTTP layer:

```lua
-- tests/http/api_spec.lua
describe("HTTP API", function()
  local server
  local http = require "http.client"

  before_each(function()
    -- Start test server
  end)

  after_each(function()
    -- Stop server
  end)

  it("should get a board", function()
    local response = http.get("http://localhost:8080/api/boards/demo")
    assert.equals(200, response.status)
    assert.is_not_nil(response.body.title)
  end)

  -- More tests...
end)
```

---

## Performance Considerations

### Single User Optimizations

- **No caching needed**: Single user means no concurrent access issues
- **Simple file locking**: Use `flock` for writes
- **In-memory board cache**: Optional, cache parsed boards for 1-2 seconds
- **Connection pooling**: Not needed for single user

### Potential Bottlenecks

1. **File I/O**: Reading/writing markdown files on every request
   - **Solution**: Add simple TTL cache (1-2 second expiry)

2. **Parsing overhead**: Parsing markdown on every load
   - **Solution**: Cache parsed board objects

3. **WebSocket overhead**: Multiple connections for same board
   - **Not an issue**: Single user = max 1-2 connections

---

## Future Enhancements

1. **Board caching**: In-memory cache with TTL
2. **Compression**: gzip responses
3. **ETags**: Conditional requests
4. **Rate limiting**: Prevent abuse (if made public)
5. **Authentication**: JWT tokens (handled separately)
6. **Metrics**: Request logging, performance tracking
7. **Hot reload**: Reload server on code changes

---

## Implementation Phases

### Phase 1: Core HTTP Server ✓
- [x] server.lua with lua-http
- [x] router.lua with basic routing
- [x] config.lua
- [x] response utilities

### Phase 2: Board Operations ✓
- [x] file_service.lua
- [x] board_service.lua
- [x] boards handler (GET, PUT)

### Phase 3: Card Operations ✓
- [x] cards handler (move, add, update, delete)
- [x] Integrate with board_service

### Phase 4: WebSocket Support ✓
- [x] websocket handler
- [x] watch_service
- [ ] File watcher integration (entr or inotify) *decision*: use inotify (optional, server works without it)

### Phase 5: Static Files & Polish ✓
- [x] static file serving
- [x] CORS middleware
- [x] Error handling
- [x] Logging

### Phase 6: Testing & Deployment
- [ ] Integration tests
- [ ] Docker setup
- [ ] Deployment documentation

---

## Troubleshooting

### Common Issues

**Port already in use**:
```bash
lsof -ti:8080 | xargs kill
```

**WebSocket not connecting**:
- Check CORS headers
- Verify WebSocket upgrade headers
- Check firewall rules

**File permissions**:
```bash
chmod -R 755 data/boards
chown -R $USER:$USER data/boards
```

**Dependencies missing**:
```bash
luarocks list
luarocks install <missing-package>
```

---

## Conclusion

This lua-http backend provides a simple, pure-Lua HTTP server for kanban-md with:

- **Direct engine integration**: No translation layer
- **File-based storage**: Simple markdown files
- **WebSocket support**: Real-time updates
- **Easy deployment**: Single binary, minimal dependencies
- **Development-friendly**: Fast iteration, simple debugging

Perfect for single-user personal deployments and development.

**Status**: Ready for implementation

**Next Steps**:
1. Implement Phase 1 (Core HTTP server)
2. Test with existing frontend
3. Add remaining phases incrementally
4. Deploy to production environment
