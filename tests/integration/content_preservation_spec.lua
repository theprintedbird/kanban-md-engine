-- tests/integration/content_preservation_spec.lua
-- Integration tests for content preservation through full board lifecycle

require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local Card = require("kanban-md.card")
local config_module = require("kanban-md.config")

describe("Content preservation integration", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
    -- Enable persisting card IDs for these tests
    config_module.setup({ persist_card_ids = true })
  end)

  after_each(function()
    config_module.setup(original_config)
  end)

  describe("full board lifecycle with mixed content", function()
    it("should preserve all content through complete workflow", function()
      -- Initial board with rich documentation
      local input = {
        "# Product Roadmap",
        "",
        "This board tracks our product development roadmap.",
        "",
        "## How to Use",
        "",
        "1. Add features to Backlog",
        "2. Move to Planning when ready",
        "3. Move to Development when started",
        "4. Move to Done when complete",
        "",
        "## Priority Levels",
        "",
        "- P0: Critical",
        "- P1: High",
        "- P2: Medium",
        "",
        "###### Backlog",
        "- Feature A <!-- id: feat-a, priority: P0 -->",
        "- Feature B <!-- id: feat-b, priority: P1 -->",
        "",
        "###### Planning",
        "<!-- column:config wip_limit: 3 -->",
        "",
        "###### Development",
        "<!-- column:config wip_limit: 2 -->",
        "- Feature C <!-- id: feat-c, priority: P0 -->",
        "",
        "###### Done",
        "- Feature D <!-- id: feat-d -->",
        "",
        "###### __ARCHIVE__",
        "",
        "## Team Notes",
        "",
        "Remember to update the changelog weekly."
      }

      -- Parse board
      local board = Board:new()
      board:parse(input)

      -- Verify initial state
      assert.are.equals("Product Roadmap", board.title)
      assert.are.equals(4, #board.columns) -- Backlog, Planning, Development, Done (Archive is stored separately)

      -- Perform various operations

      -- 1. Move Feature A from Backlog to Planning
      local backlog = board:get_column_by_name("Backlog")
      local planning = board:get_column_by_name("Planning")
      local feat_a = board:find_task("feat-a")

      assert.is_not_nil(feat_a, "Should find Feature A")
      board:move_card(feat_a, backlog, planning)

      -- 2. Add a new feature to Backlog
      local new_feature = Card:new("feat-e", "Feature E")
      new_feature.properties.priority = "P2"
      backlog:add_card(new_feature)

      -- 3. Move Feature C from Development to Done
      local development = board:get_column_by_name("Development")
      local done = board:get_column_by_name("Done")
      local feat_c = board:find_task("feat-c")

      assert.is_not_nil(feat_c, "Should find Feature C")
      board:move_card(feat_c, development, done)

      -- Write board to markdown
      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify all documentation is preserved
      assert.is_not_nil(output_text:match("This board tracks our product development roadmap"),
        "Board description should be preserved")
      assert.is_not_nil(output_text:match("## How to Use"),
        "How to Use section should be preserved")
      assert.is_not_nil(output_text:match("Add features to Backlog"),
        "Instructions should be preserved")
      assert.is_not_nil(output_text:match("## Priority Levels"),
        "Priority Levels section should be preserved")
      assert.is_not_nil(output_text:match("P0: Critical"),
        "Priority definitions should be preserved")
      assert.is_not_nil(output_text:match("## Team Notes"),
        "Team Notes section should be preserved")
      assert.is_not_nil(output_text:match("update the changelog weekly"),
        "Team notes content should be preserved")

      -- Verify columns use H6
      assert.is_not_nil(output_text:match("###### Backlog"), "Backlog should use H6")
      assert.is_not_nil(output_text:match("###### Planning"), "Planning should use H6")
      assert.is_not_nil(output_text:match("###### Development"), "Development should use H6")
      assert.is_not_nil(output_text:match("###### Done"), "Done should use H6")
      assert.is_not_nil(output_text:match("###### __ARCHIVE__"), "Archive should use H6")

      -- Verify card movements worked
      assert.is_not_nil(output_text:match("feat%-a"), "Feature A should be in output")
      assert.is_not_nil(output_text:match("feat%-e"), "Feature E (new) should be in output")
      assert.is_not_nil(output_text:match("feat%-c"), "Feature C should be in output")

      -- Parse output again to verify round-trip
      local board2 = Board:new()
      board2:parse(output)

      assert.are.equals(board.title, board2.title)
      assert.are.equals(#board.columns, #board2.columns)
    end)
  end)

  describe("card operations preserving documentation", function()
    it("should preserve docs when adding multiple cards", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Guidelines",
        "Always add priority tags.",
        "",
        "###### Todo",
        "- Existing task",
        "",
        "## Notes",
        "Review weekly."
      })

      local todo = board:get_column_by_name("Todo")

      -- Add multiple cards
      for i = 1, 5 do
        local card = Card:new("task-" .. i, "New task " .. i)
        todo:add_card(card)
      end

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Guidelines"))
      assert.is_not_nil(output_text:match("Always add priority tags"))
      assert.is_not_nil(output_text:match("## Notes"))
      assert.is_not_nil(output_text:match("Review weekly"))

      -- Verify all new cards added
      for i = 1, 5 do
        assert.is_not_nil(output_text:match("New task " .. i), "Should have new task " .. i)
      end
    end)

    it("should preserve docs when moving cards between columns", function()
      local board = Board:new()
      board:parse({
        "# Workflow Board",
        "",
        "## Process",
        "Follow the workflow strictly.",
        "",
        "###### Todo",
        "- Task 1 <!-- id: t1 -->",
        "- Task 2 <!-- id: t2 -->",
        "- Task 3 <!-- id: t3 -->",
        "",
        "## Tips",
        "Use tags for categorization.",
        "",
        "###### In Progress",
        "",
        "###### Done"
      })

      local todo = board:get_column_by_name("Todo")
      local in_progress = board:get_column_by_name("In Progress")
      local done = board:get_column_by_name("Done")

      -- Move tasks through workflow
      local t1 = board:find_task("t1")
      local t2 = board:find_task("t2")

      board:move_card(t1, todo, in_progress)
      board:move_card(t2, todo, done)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved after moves
      assert.is_not_nil(output_text:match("## Process"), "Process section preserved")
      assert.is_not_nil(output_text:match("Follow the workflow strictly"), "Process content preserved")
      assert.is_not_nil(output_text:match("## Tips"), "Tips section preserved")
      assert.is_not_nil(output_text:match("Use tags for categorization"), "Tips content preserved")

      -- Verify cards moved correctly
      local lines = output

      local t1_col, t2_col, t3_col
      local current_col

      for _, line in ipairs(lines) do
        if line:match("^######") then
          current_col = line:match("^######%s+(.+)$")
        elseif line:match("Task 1") then
          t1_col = current_col
        elseif line:match("Task 2") then
          t2_col = current_col
        elseif line:match("Task 3") then
          t3_col = current_col
        end
      end

      assert.are.equals("In Progress", t1_col, "Task 1 should be in In Progress")
      assert.are.equals("Done", t2_col, "Task 2 should be in Done")
      assert.are.equals("Todo", t3_col, "Task 3 should remain in Todo")
    end)

    it("should preserve docs when archiving cards", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Instructions",
        "Archive completed tasks monthly.",
        "",
        "###### Todo",
        "- Active task",
        "",
        "###### Done",
        "- Completed task <!-- id: c1 -->",
        "",
        "###### __ARCHIVE__",
        "",
        "## Statistics",
        "Track metrics here."
      })

      local done = board:get_column_by_name("Done")
      local completed = board:find_task("c1")

      -- Archive the completed task
      board:move_card(completed, done, board.archive)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Instructions"))
      assert.is_not_nil(output_text:match("Archive completed tasks monthly"))
      assert.is_not_nil(output_text:match("## Statistics"))
      assert.is_not_nil(output_text:match("Track metrics here"))

      -- Verify card in archive
      local lines = output
      local c1_col
      local current_col

      for _, line in ipairs(lines) do
        if line:match("^######") then
          current_col = line:match("^######%s+(.+)$")
        elseif line:match("Completed task") then
          c1_col = current_col
        end
      end

      assert.are.equals("__ARCHIVE__", c1_col, "Completed task should be in Archive")
    end)

    it("should preserve docs when deleting cards", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Rules",
        "Keep board clean.",
        "",
        "###### Todo",
        "- Task to keep",
        "- Task to delete",
        "- Another to keep",
        "",
        "## Footer",
        "Last updated today."
      })

      local todo = board:get_column_by_name("Todo")

      -- Delete middle task
      table.remove(todo.cards, 2)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Rules"))
      assert.is_not_nil(output_text:match("Keep board clean"))
      assert.is_not_nil(output_text:match("## Footer"))
      assert.is_not_nil(output_text:match("Last updated today"))

      -- Verify correct tasks remain
      assert.is_not_nil(output_text:match("Task to keep"))
      assert.is_not_nil(output_text:match("Another to keep"))
      assert.is_nil(output_text:match("Task to delete"))
    end)
  end)

  describe("column operations preserving sections", function()
    it("should preserve sections when adding new column", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Documentation",
        "This board is important.",
        "",
        "###### Todo",
        "- Task",
        "",
        "###### Done"
      })

      -- Add new column
      local Column = require("kanban-md.column")
      local in_progress = Column:new(nil, "In Progress")

      -- Insert between Todo and Done
      table.insert(board.columns, 2, in_progress)

      -- Update content blocks
      local ContentBlock = require("kanban-md.content_block")

      -- Find position to insert (after Todo column block)
      local insert_pos
      for i, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.COLUMN and block.ref.name == "Todo" then
          insert_pos = i + 1
          break
        end
      end

      if insert_pos then
        table.insert(board.content_blocks, insert_pos, ContentBlock.column(in_progress))
      end

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Documentation"))
      assert.is_not_nil(output_text:match("This board is important"))

      -- Verify new column exists
      assert.is_not_nil(output_text:match("###### In Progress"))

      -- Verify column order
      local todo_idx, progress_idx, done_idx
      local lines = output

      for i, line in ipairs(lines) do
        if line == "###### Todo" then
          todo_idx = i
        elseif line == "###### In Progress" then
          progress_idx = i
        elseif line == "###### Done" then
          done_idx = i
        end
      end

      assert.is_not_nil(todo_idx)
      assert.is_not_nil(progress_idx)
      assert.is_not_nil(done_idx)
      assert.is_true(todo_idx < progress_idx)
      assert.is_true(progress_idx < done_idx)
    end)

    it("should preserve sections when modifying column config", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Setup Notes",
        "WIP limits enforced.",
        "",
        "###### Todo",
        "- Task",
        "",
        "###### In Progress",
        "<!-- column:config wip_limit: 2 -->",
        "- Active task",
        "",
        "## Review",
        "Check limits weekly."
      })

      -- Modify WIP limit. Since PLAN-config-fixes.md Task 3, the writer
      -- serialises the *authored* layer (column.markdown_config) by default and
      -- never the resolved column.config, so to change what is persisted we
      -- update the authored layer (mirroring it into column.config keeps the
      -- resolved layer that triggers/stats consult in sync).
      local in_progress = board:get_column_by_name("In Progress")
      in_progress.markdown_config.wip_limit = 5
      in_progress.config.wip_limit = 5

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Setup Notes"))
      assert.is_not_nil(output_text:match("WIP limits enforced"))
      assert.is_not_nil(output_text:match("## Review"))
      assert.is_not_nil(output_text:match("Check limits weekly"))

      -- Verify config updated
      assert.is_not_nil(output_text:match("wip_limit:%s*5") or output_text:match("wip_limit: 5"))
    end)
  end)

  describe("archive operations preserving content", function()
    it("should preserve all content when archiving multiple tasks", function()
      local board = Board:new()
      board:parse({
        "# Project Board",
        "",
        "## Archive Policy",
        "Archive tasks older than 30 days.",
        "",
        "###### Done",
        "- Task 1 <!-- id: t1, done: 1609459200 -->",
        "- Task 2 <!-- id: t2, done: 1609459300 -->",
        "- Task 3 <!-- id: t3, done: 1609459400 -->",
        "",
        "###### __ARCHIVE__",
        "- Old task",
        "",
        "## Metrics",
        "Throughput: 5 tasks/week"
      })

      local done = board:get_column_by_name("Done")

      -- Archive all done tasks
      while #done.cards > 0 do
        local task = done.cards[1]
        board:move_card(task, done, board.archive)
      end

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("## Archive Policy"))
      assert.is_not_nil(output_text:match("Archive tasks older than 30 days"))
      assert.is_not_nil(output_text:match("## Metrics"))
      assert.is_not_nil(output_text:match("Throughput: 5 tasks/week"))

      -- Verify all tasks in archive
      assert.is_not_nil(output_text:match("t1"))
      assert.is_not_nil(output_text:match("t2"))
      assert.is_not_nil(output_text:match("t3"))

      -- Verify Done column is empty
      local lines = output
      local in_done = false
      local done_has_tasks = false

      for _, line in ipairs(lines) do
        if line == "###### Done" then
          in_done = true
        elseif line:match("^######") then
          in_done = false
        elseif in_done and line:match("^%s*%-") then
          done_has_tasks = true
        end
      end

      assert.is_false(done_has_tasks, "Done column should be empty")
    end)
  end)

  describe("complex real-world scenarios", function()
    it("should handle sprint board with daily updates", function()
      local board = Board:new()
      board:parse({
        "# Sprint 24 - Q2 2024",
        "",
        "**Goal**: Implement user authentication and profile management",
        "",
        "## Team",
        "- Alice (Frontend)",
        "- Bob (Backend)",
        "- Carol (QA)",
        "",
        "## Sprint Details",
        "",
        "- **Start**: 2024-04-01",
        "- **End**: 2024-04-14",
        "- **Capacity**: 120 points",
        "",
        "###### Backlog",
        "- User registration <!-- id: us-1, complexity: 8, assignee: Bob -->",
        "- Email verification <!-- id: us-2, complexity: 5, assignee: Bob -->",
        "",
        "## Daily Standup Notes",
        "",
        "### 2024-04-02",
        "- Alice blocked on API spec",
        "- Bob working on registration",
        "",
        "###### In Development",
        "<!-- column:config wip_limit: 3 -->",
        "- Login page <!-- id: us-3, complexity: 5, assignee: Alice -->",
        "",
        "###### In Review",
        "<!-- column:config wip_limit: 2 -->",
        "",
        "###### Done",
        "- Setup auth service <!-- id: us-4, complexity: 3 -->",
        "",
        "###### __ARCHIVE__",
        "",
        "## Definition of Done",
        "",
        "- [ ] Code reviewed",
        "- [ ] Tests written",
        "- [ ] Documentation updated",
        "",
        "## Burndown",
        "",
        "| Date | Remaining |",
        "| ---- | --------- |",
        "| 04-01 | 120 |",
        "| 04-02 | 117 |"
      })

      -- Simulate day's work: move login page to review
      local dev = board:get_column_by_name("In Development")
      local review = board:get_column_by_name("In Review")
      local login = board:find_task("us-3")

      board:move_card(login, dev, review)

      -- Add new task to backlog
      local new_task = Card:new("us-5", "Password reset")
      new_task.properties.complexity = 3
      new_task.properties.assignee = "Bob"
      local backlog = board:get_column_by_name("Backlog")
      backlog:add_card(new_task)

      -- Move registration to development
      local registration = board:find_task("us-1")
      board:move_card(registration, backlog, dev)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify ALL documentation preserved
      assert.is_not_nil(output_text:match("**Goal**"), "Sprint goal preserved")
      assert.is_not_nil(output_text:match("## Team"), "Team section preserved")
      assert.is_not_nil(output_text:match("Alice %(Frontend%)"), "Team members preserved")
      assert.is_not_nil(output_text:match("## Sprint Details"), "Sprint details preserved")
      assert.is_not_nil(output_text:match("Capacity.*120"), "Capacity preserved")
      assert.is_not_nil(output_text:match("## Daily Standup Notes"), "Standup notes preserved")
      assert.is_not_nil(output_text:match("Alice blocked on API spec"), "Standup content preserved")
      assert.is_not_nil(output_text:match("## Definition of Done"), "DoD preserved")
      assert.is_not_nil(output_text:match("Code reviewed"), "DoD items preserved")
      assert.is_not_nil(output_text:match("## Burndown"), "Burndown preserved")
      assert.is_not_nil(output_text:match("| Date | Remaining |"), "Burndown table preserved")

      -- Verify card movements
      assert.is_not_nil(output_text:match("us%-5"), "New task added")

      local lines = output
      local us1_col, us3_col
      local current_col

      for _, line in ipairs(lines) do
        if line:match("^######") then
          current_col = line:match("^######%s+(.+)$")
        elseif line:match("us%-1") then
          us1_col = current_col
        elseif line:match("us%-3") then
          us3_col = current_col
        end
      end

      assert.are.equals("In Development", us1_col, "Registration should be in development")
      assert.are.equals("In Review", us3_col, "Login should be in review")
    end)
  end)

  describe("multi-line card preservation", function()
    it("should preserve multi-line cards through parse-write cycle", function()
      local content = {
        "# Test Board",
        "",
        "###### TODO",
        "",
        "- Card 1",
        "  with continuation",
        "  and more",
        "- Card 2"
      }

      local board = Board:new()
      board:parse(content)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify continuation lines preserved
      assert.is_not_nil(output_text:match("- Card 1"))
      assert.is_not_nil(output_text:match("  with continuation"))
      assert.is_not_nil(output_text:match("  and more"))
      assert.is_not_nil(output_text:match("- Card 2"))
    end)

    it("should preserve column documentation around multi-line cards", function()
      local content = {
        "# Test Board",
        "",
        "###### TODO",
        "",
        "Column notes here",
        "",
        "- Card 1",
        "  with continuation",
        "- Card 2",
        "",
        "More notes after cards"
      }

      local board = Board:new()
      board:parse(content)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify documentation preserved
      assert.is_not_nil(output_text:match("Column notes here"))
      assert.is_not_nil(output_text:match("More notes after cards"))

      -- Verify cards preserved
      assert.is_not_nil(output_text:match("- Card 1"))
      assert.is_not_nil(output_text:match("  with continuation"))
    end)

    it("should preserve mixed single and multi-line cards", function()
      local content = {
        "# Test Board",
        "",
        "###### TODO",
        "",
        "- Single line card",
        "- Multi-line card",
        "  with details",
        "  and more details",
        "- Another single",
        "- Another multi",
        "  with one continuation"
      }

      local board = Board:new()
      board:parse(content)

      local todo = board:get_column_by_name("TODO")
      assert.equals(4, #todo.cards)

      -- Check content_lines set correctly
      assert.is_nil(todo.cards[1].content_lines) -- single line
      assert.is_not_nil(todo.cards[2].content_lines) -- multi-line
      assert.is_nil(todo.cards[3].content_lines) -- single line
      assert.is_not_nil(todo.cards[4].content_lines) -- multi-line

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify all cards preserved
      assert.is_not_nil(output_text:match("- Single line card"))
      assert.is_not_nil(output_text:match("- Multi%-line card"))
      assert.is_not_nil(output_text:match("  with details"))
      assert.is_not_nil(output_text:match("  and more details"))
      assert.is_not_nil(output_text:match("- Another single"))
      assert.is_not_nil(output_text:match("- Another multi"))
      assert.is_not_nil(output_text:match("  with one continuation"))
    end)

    it("should preserve multi-line content when moving card between columns", function()
      local content = {
        "# Test Board",
        "",
        "###### TODO",
        "",
        "- Multi-line card <!-- id: ml1 -->",
        "  with important notes",
        "  and more context",
        "",
        "###### Done"
      }

      local board = Board:new()
      board:parse(content)

      local todo = board:get_column_by_name("TODO")
      local done = board:get_column_by_name("Done")
      local card = board:find_task("ml1")

      -- Verify multi-line before move
      assert.is_not_nil(card.content_lines)
      assert.equals(3, #card.content_lines)

      -- Move card
      board:move_card(card, todo, done)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify card moved to Done section
      local lines = output
      local card_col
      local current_col

      for _, line in ipairs(lines) do
        if line:match("^######") then
          current_col = line:match("^######%s+(.+)$")
        elseif line:match("Multi%-line card") then
          card_col = current_col
        end
      end

      assert.are.equals("Done", card_col)

      -- Verify all content lines preserved
      assert.is_not_nil(output_text:match("- Multi%-line card"))
      assert.is_not_nil(output_text:match("  with important notes"))
      assert.is_not_nil(output_text:match("  and more context"))
    end)

    it("should preserve multi-line content when archiving card", function()
      local content = {
        "# Test Board",
        "",
        "###### Done",
        "",
        "- Completed task <!-- id: ct1 -->",
        "  with detailed notes",
        "  about the implementation",
        "",
        "###### __ARCHIVE__"
      }

      local board = Board:new()
      board:parse(content)

      local done = board:get_column_by_name("Done")
      local card = board:find_task("ct1")

      -- Archive the card
      board:move_card(card, done, board.archive)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify card in archive
      local lines = output
      local in_archive = false
      local found_card = false

      for _, line in ipairs(lines) do
        if line:match("^###### __ARCHIVE__") then
          in_archive = true
        elseif line:match("^######") then
          in_archive = false
        elseif in_archive and line:match("Completed task") then
          found_card = true
        end
      end

      assert.is_true(found_card, "Card should be in archive")

      -- Verify all content lines preserved
      assert.is_not_nil(output_text:match("- Completed task"))
      assert.is_not_nil(output_text:match("  with detailed notes"))
      assert.is_not_nil(output_text:match("  about the implementation"))
    end)

    it("should preserve multi-line content with properties", function()
      local content = {
        "# Test Board",
        "",
        "###### TODO",
        "",
        "- Task with properties <!-- id: tp1, complexity: 5 -->",
        "  continuation line 1",
        "  continuation line 2"
      }

      local board = Board:new()
      board:parse(content)

      local todo = board:get_column_by_name("TODO")
      local card = board:find_task("tp1")

      -- Verify properties and content
      assert.equals(5, card.properties.complexity)
      assert.is_not_nil(card.content_lines)
      assert.equals(3, #card.content_lines)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Verify properties written on first line
      assert.is_not_nil(output_text:match("- Task with properties <!%-%-"))
      assert.is_not_nil(output_text:match("complexity: 5"))

      -- Verify continuation lines separate
      assert.is_not_nil(output_text:match("  continuation line 1"))
      assert.is_not_nil(output_text:match("  continuation line 2"))
    end)
  end)
end)
