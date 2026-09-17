-- tests/fixtures/large_board.lua
-- Generates board markdown of an arbitrary size, for the performance
-- regression tests. Deterministic: the same arguments always produce
-- byte-identical markdown, so a timing comparison between two runs is
-- comparing the same work.

local M = {}

--- Build markdown for a board with `columns` columns of `cards_per_column`
--- cards each. Every card carries an id and a spread of properties, so the
--- parser does property work rather than just reading bare list items.
--- The first column is the backlog state and the last the completion state,
--- so stats has real lead/cycle times to compute.
--- @param columns number how many columns to emit
--- @param cards_per_column number how many cards per column
--- @return string the board markdown
function M.markdown(columns, cards_per_column)
  local lines = {
    "# Performance Board",
    "",
    "<!-- kanban:config wip_limit: 100000 -->",
    "",
  }

  -- Fixed timestamps, so stats computes the same durations on every run.
  local backlog_at = 1700000000
  local done_at = backlog_at + 86400 * 3

  for column = 1, columns do
    lines[#lines + 1] = "###### Column " .. column
    if column == 1 then
      lines[#lines + 1] = "<!-- column:config is_backlog_state: true -->"
    elseif column == columns then
      lines[#lines + 1] = "<!-- column:config is_completion_state: true -->"
    end
    lines[#lines + 1] = ""

    for card = 1, cards_per_column do
      lines[#lines + 1] = string.format(
        "- Task %d-%d <!-- id: perf_%d_%d, complexity: %d, assignee: dev%d, " ..
        "tags: [alpha, beta], column_1: %d, column_%d: %d -->",
        column, card, column, card,
        (card % 8) + 1, card % 5,
        backlog_at, columns, done_at)
    end

    lines[#lines + 1] = ""
  end

  return table.concat(lines, "\n")
end

--- Id of the last card in a board of the given shape -- the worst case for
--- any lookup that scans columns in order.
--- @param columns number
--- @param cards_per_column number
--- @return string the card id
function M.last_card_id(columns, cards_per_column)
  return string.format("perf_%d_%d", columns, cards_per_column)
end

return M
