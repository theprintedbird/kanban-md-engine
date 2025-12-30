-- tests/unit/column_helpers_spec.lua
-- Tests for semantic state column helper functions

require('polyfills.vim')

_G._TEST = true

local column_helpers = require("kanban-md.helpers.column")

describe("Column Helpers - Semantic State Detection", function()
	local function create_test_board(columns, config)
		return {
			columns = columns,
			config = config or {}
		}
	end

	local function create_column(name, config)
		return {
			name = name,
			config = config or {},
			tasks = {},
			cards = {}
		}
	end

	describe("is_start_column", function()
		it("should detect explicit is_start_state property", function()
			local start_col = create_column("In Progress", { is_start_state = true })
			local other_col = create_column("Done", {})
			local board = create_test_board({ start_col, other_col })

			assert.is_true(column_helpers.is_start_column(start_col, board))
			assert.is_false(column_helpers.is_start_column(other_col, board))
		end)

		it("should use config.default_start_column as fallback", function()
			local progress_col = create_column("In Progress", {})
			local backlog_col = create_column("Backlog", {})
			local board = create_test_board(
				{ backlog_col, progress_col },
				{ default_start_column = "In Progress" }
			)

			assert.is_true(column_helpers.is_start_column(progress_col, board))
			assert.is_false(column_helpers.is_start_column(backlog_col, board))
		end)

		it("should support partial case-insensitive matching for default_start_column", function()
			local progress_col = create_column("In Progress", {})
			local board = create_test_board(
				{ progress_col },
				{ default_start_column = "progress" }
			)

			assert.is_true(column_helpers.is_start_column(progress_col, board))
		end)

		it("should use position-based fallback (first regular column)", function()
			local backlog_col = create_column("Backlog", {})
			local progress_col = create_column("In Progress", {})
			local done_col = create_column("Done", {})
			local board = create_test_board({ backlog_col, progress_col, done_col })

			assert.is_true(column_helpers.is_start_column(backlog_col, board))
			assert.is_false(column_helpers.is_start_column(progress_col, board))
			assert.is_false(column_helpers.is_start_column(done_col, board))
		end)

		it("should ignore special columns in position-based fallback", function()
			local archive_col = create_column("__ARCHIVE__", {})
			local backlog_col = create_column("Backlog", {})
			local board = create_test_board({ archive_col, backlog_col })

			assert.is_false(column_helpers.is_start_column(archive_col, board))
			assert.is_true(column_helpers.is_start_column(backlog_col, board))
		end)

		it("should prioritize explicit property over config default", function()
			local explicit_col = create_column("Ready", { is_start_state = true })
			local progress_col = create_column("In Progress", {})
			local board = create_test_board(
				{ explicit_col, progress_col },
				{ default_start_column = "In Progress" }
			)

			assert.is_true(column_helpers.is_start_column(explicit_col, board))
			assert.is_false(column_helpers.is_start_column(progress_col, board))
		end)
	end)

	describe("is_backlog_column", function()
		it("should detect explicit is_backlog_state property", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local other_col = create_column("Done", {})
			local board = create_test_board({ backlog_col, other_col })

			assert.is_true(column_helpers.is_backlog_column(backlog_col, board))
			assert.is_false(column_helpers.is_backlog_column(other_col, board))
		end)

		it("should use config.default_backlog_column as fallback", function()
			local backlog_col = create_column("Backlog", {})
			local progress_col = create_column("In Progress", {})
			local board = create_test_board(
				{ backlog_col, progress_col },
				{ default_backlog_column = "Backlog" }
			)

			assert.is_true(column_helpers.is_backlog_column(backlog_col, board))
			assert.is_false(column_helpers.is_backlog_column(progress_col, board))
		end)

		it("should support partial case-insensitive matching for default_backlog_column", function()
			local backlog_col = create_column("Backlog", {})
			local board = create_test_board(
				{ backlog_col },
				{ default_backlog_column = "back" }
			)

			assert.is_true(column_helpers.is_backlog_column(backlog_col, board))
		end)

		it("should use position-based fallback (first column)", function()
			local first_col = create_column("First", {})
			local second_col = create_column("Second", {})
			local board = create_test_board({ first_col, second_col }, {})

			assert.is_true(column_helpers.is_backlog_column(first_col, board))
			assert.is_false(column_helpers.is_backlog_column(second_col, board))
		end)

		it("should prioritize explicit property over config default", function()
			local explicit_col = create_column("To Do", { is_backlog_state = true })
			local backlog_col = create_column("Backlog", {})
			local board = create_test_board(
				{ explicit_col, backlog_col },
				{ default_backlog_column = "Backlog" }
			)

			assert.is_true(column_helpers.is_backlog_column(explicit_col, board))
			assert.is_false(column_helpers.is_backlog_column(backlog_col, board))
		end)
	end)

	describe("is_blocked_column", function()
		it("should detect explicit is_blocked_state property", function()
			local blocked_col = create_column("Blocked", { is_blocked_state = true })
			local other_col = create_column("Done", {})
			local board = create_test_board({ blocked_col, other_col })

			assert.is_true(column_helpers.is_blocked_column(blocked_col, board))
			assert.is_false(column_helpers.is_blocked_column(other_col, board))
		end)

		it("should require explicit property (no fallback)", function()
			local blocked_col = create_column("Blocked", {})
			local board = create_test_board({ blocked_col })

			assert.is_false(column_helpers.is_blocked_column(blocked_col, board))
		end)

		it("should return false for nil column", function()
			local board = create_test_board({})
			assert.is_false(column_helpers.is_blocked_column(nil, board))
		end)
	end)

	describe("is_waiting_column", function()
		it("should detect explicit is_waiting_state property", function()
			local waiting_col = create_column("Waiting", { is_waiting_state = true })
			local other_col = create_column("Done", {})
			local board = create_test_board({ waiting_col, other_col })

			assert.is_true(column_helpers.is_waiting_column(waiting_col, board))
			assert.is_false(column_helpers.is_waiting_column(other_col, board))
		end)

		it("should require explicit property (no fallback)", function()
			local waiting_col = create_column("Waiting for Review", {})
			local board = create_test_board({ waiting_col })

			assert.is_false(column_helpers.is_waiting_column(waiting_col, board))
		end)

		it("should return false for nil column", function()
			local board = create_test_board({})
			assert.is_false(column_helpers.is_waiting_column(nil, board))
		end)
	end)

	describe("is_completion_column (existing tests verification)", function()
		it("should continue to work with explicit is_completion_state property", function()
			local done_col = create_column("Done", { is_completion_state = true })
			local other_col = create_column("In Progress", {})
			local board = create_test_board({ other_col, done_col })

			assert.is_true(column_helpers.is_completion_column(done_col, board))
			assert.is_false(column_helpers.is_completion_column(other_col, board))
		end)

		it("should use position-based fallback (last regular column)", function()
			local backlog_col = create_column("Backlog", {})
			local progress_col = create_column("In Progress", {})
			local done_col = create_column("Done", {})
			local board = create_test_board({ backlog_col, progress_col, done_col })

			assert.is_false(column_helpers.is_completion_column(backlog_col, board))
			assert.is_false(column_helpers.is_completion_column(progress_col, board))
			assert.is_true(column_helpers.is_completion_column(done_col, board))
		end)
	end)
end)
